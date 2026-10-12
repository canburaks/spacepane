import Foundation
import PreviewContracts

/// A strict, bounded and cancellable JSON reader over one request-owned byte array.
///
/// Large documents (HAR captures, GeoJSON collections) must not be materialized, and their node
/// counts routinely exceed the shared output budgets, so this reader is a cursor: callers walk the
/// members they need and every other value is skipped without decoding. Nothing is evaluated or
/// resolved. Grammar errors are `malformedDocument`; nesting beyond `maxJSONDepth` is
/// `structureTooDeep`. A UTF-8 byte-order mark is ignored, as RFC 8259 permits parsers to do.
struct DataJSONReader {
    enum Kind: Equatable { case object, array, string, number, boolean, null }

    /// Keys are matched exactly, so a longer one can never equal a key a caller looks for.
    static let maximumKeyBytes = 256

    private let bytes: [UInt8]
    private let context: RequestContext
    private let maximumDepth: Int
    private(set) var position = 0
    private var checkpointPosition = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
        maximumDepth = context.budget.maxJSONDepth
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { position = 3 }
        checkpointPosition = position
    }

    // MARK: Structure

    /// Reads the whole document with `body`, then requires only whitespace to remain.
    mutating func document(_ body: (_ reader: inout DataJSONReader) throws -> Void) throws {
        try context.checkpoint()
        try body(&self)
        try skipWhitespace()
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
    }

    /// Visits each member of the object at the cursor. `body` reads or skips the member's value;
    /// a body that leaves it untouched has it skipped.
    mutating func forEachMember(depth: Int,
                                _ body: (_ key: String, _ reader: inout DataJSONReader) throws -> Void) throws {
        try open(.object, depth: depth)
        try skipWhitespace()
        if take(0x7D) { return }
        while true {
            try skipWhitespace()
            let key = try string(maximumBytes: Self.maximumKeyBytes).text
            try skipWhitespace()
            guard take(0x3A) else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            try visitValue(depth: depth + 1) { reader in try body(key, &reader) }
            try skipWhitespace()
            if take(0x7D) { return }
            guard take(0x2C) else { throw PreviewFailure.malformedDocument }
        }
    }

    mutating func forEachElement(depth: Int,
                                 _ body: (_ index: Int, _ reader: inout DataJSONReader) throws -> Void) throws {
        try open(.array, depth: depth)
        try skipWhitespace()
        if take(0x5D) { return }
        var index = 0
        while true {
            try skipWhitespace()
            let current = index
            try visitValue(depth: depth + 1) { reader in try body(current, &reader) }
            index += 1
            try skipWhitespace()
            if take(0x5D) { return }
            guard take(0x2C) else { throw PreviewFailure.malformedDocument }
        }
    }

    /// The kind of the value at the cursor, without consuming it.
    mutating func peekKind() throws -> Kind {
        try skipWhitespace()
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        switch bytes[position] {
        case 0x7B: return .object
        case 0x5B: return .array
        case 0x22: return .string
        case 0x74, 0x66: return .boolean
        case 0x6E: return .null
        case 0x2D, 0x30...0x39: return .number
        default: throw PreviewFailure.malformedDocument
        }
    }

    /// Skips the value at the cursor without decoding it.
    mutating func skipValue(depth: Int) throws {
        switch try peekKind() {
        case .object: try forEachMember(depth: depth) { _, _ in }
        case .array: try forEachElement(depth: depth) { _, _ in }
        case .string: try skipString()
        case .number: _ = try numberSpan()
        case .boolean: _ = try boolean()
        case .null: try null()
        }
    }

    // MARK: Scalars

    /// A string clipped to `maximumBytes` of UTF-8 at a character boundary. Lone surrogate escapes
    /// become U+FFFD, since a conforming document may carry them but UTF-8 cannot.
    mutating func string(maximumBytes: Int) throws -> (text: String, clipped: Bool) {
        try skipWhitespace()
        guard take(0x22) else { throw PreviewFailure.malformedDocument }
        var output: [UInt8] = []
        var clipped = false
        func append(_ byte: UInt8) {
            if output.count < maximumBytes { output.append(byte) } else { clipped = true }
        }
        while true {
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            try tick()
            let byte = bytes[position]
            position += 1
            switch byte {
            case 0x22:
                return (try Self.decode(&output, clipped: clipped), clipped)
            case 0x5C:
                guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                let escape = bytes[position]
                position += 1
                switch escape {
                case 0x22, 0x5C, 0x2F: append(escape)
                case 0x62: append(0x08)
                case 0x66: append(0x0C)
                case 0x6E: append(0x0A)
                case 0x72: append(0x0D)
                case 0x74: append(0x09)
                case 0x75:
                    for unit in try scalarBytes() { append(unit) }
                default: throw PreviewFailure.malformedDocument
                }
            case 0x00..<0x20: throw PreviewFailure.malformedDocument
            default: append(byte)
            }
        }
    }

    mutating func skipString() throws {
        try skipWhitespace()
        guard take(0x22) else { throw PreviewFailure.malformedDocument }
        while true {
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            try tick()
            let byte = bytes[position]
            position += 1
            if byte == 0x22 { return }
            if byte == 0x5C {
                guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                position += 1
            } else if byte < 0x20 { throw PreviewFailure.malformedDocument }
        }
    }

    /// The byte range of a number, validated against the JSON grammar and never converted.
    mutating func numberSpan() throws -> Range<Int> {
        try skipWhitespace()
        let start = position
        _ = take(0x2D)
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        if take(0x30) {
            // A leading zero may not be followed by another digit.
            if position < bytes.count, (0x30...0x39).contains(bytes[position]) { throw PreviewFailure.malformedDocument }
        } else {
            guard try digits() > 0 else { throw PreviewFailure.malformedDocument }
        }
        if take(0x2E) { guard try digits() > 0 else { throw PreviewFailure.malformedDocument } }
        if position < bytes.count, bytes[position] == 0x65 || bytes[position] == 0x45 {
            position += 1
            if position < bytes.count, bytes[position] == 0x2B || bytes[position] == 0x2D { position += 1 }
            guard try digits() > 0 else { throw PreviewFailure.malformedDocument }
        }
        return start..<position
    }

    /// A finite double, or `malformedDocument` for an exponent beyond the double range.
    mutating func double() throws -> Double {
        let span = try numberSpan()
        guard let value = Double(String(decoding: bytes[span], as: UTF8.self)), value.isFinite else {
            throw PreviewFailure.malformedDocument
        }
        return value
    }

    func lexeme(_ span: Range<Int>) -> String { String(decoding: bytes[span], as: UTF8.self) }

    mutating func boolean() throws -> Bool {
        try skipWhitespace()
        if try literal("true") { return true }
        if try literal("false") { return false }
        throw PreviewFailure.malformedDocument
    }

    mutating func null() throws {
        try skipWhitespace()
        guard try literal("null") else { throw PreviewFailure.malformedDocument }
    }

    // MARK: Internals

    private mutating func open(_ kind: Kind, depth: Int) throws {
        guard depth <= maximumDepth else { throw PreviewFailure.structureTooDeep }
        guard try peekKind() == kind else { throw PreviewFailure.malformedDocument }
        position += 1
    }

    /// Runs `body` on one value; a value it did not consume is skipped.
    private mutating func visitValue(depth: Int, _ body: (inout DataJSONReader) throws -> Void) throws {
        let start = position
        try body(&self)
        if position == start { try skipValue(depth: depth) }
    }

    private mutating func digits() throws -> Int {
        var count = 0
        while position < bytes.count, (0x30...0x39).contains(bytes[position]) {
            position += 1
            count += 1
            try tick()
        }
        return count
    }

    private mutating func literal(_ word: StaticString) throws -> Bool {
        let length = word.utf8CodeUnitCount
        guard position + length <= bytes.count else { return false }
        let matches = word.withUTF8Buffer { expected in
            (0..<length).allSatisfy { bytes[position + $0] == expected[$0] }
        }
        guard matches else { return false }
        position += length
        if position < bytes.count, Self.isWordByte(bytes[position]) { throw PreviewFailure.malformedDocument }
        return true
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x5F
    }

    private mutating func skipWhitespace() throws {
        while position < bytes.count, bytes[position] == 0x20 || bytes[position] == 0x09
                || bytes[position] == 0x0A || bytes[position] == 0x0D {
            position += 1
        }
        try tick()
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    private mutating func tick() throws {
        if position - checkpointPosition >= 4_096 {
            try context.checkpoint()
            checkpointPosition = position
        }
    }

    /// Four hex digits after `\u`, joined with a following low surrogate when the first is a high one.
    private mutating func scalarBytes() throws -> [UInt8] {
        var value = try hex4()
        if (0xD800...0xDBFF).contains(value) {
            if position + 1 < bytes.count, bytes[position] == 0x5C, bytes[position + 1] == 0x75 {
                let save = position
                position += 2
                let low = try hex4()
                if (0xDC00...0xDFFF).contains(low) {
                    value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                } else {
                    position = save
                    value = 0xFFFD
                }
            } else { value = 0xFFFD }
        } else if (0xDC00...0xDFFF).contains(value) {
            value = 0xFFFD
        }
        guard let scalar = Unicode.Scalar(value) else { return Array("\u{FFFD}".utf8) }
        return Array(String(Character(scalar)).utf8)
    }

    private mutating func hex4() throws -> UInt32 {
        guard position + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let digit: UInt32
            switch bytes[position] {
            case 0x30...0x39: digit = UInt32(bytes[position] - 0x30)
            case 0x41...0x46: digit = UInt32(bytes[position] - 0x37)
            case 0x61...0x66: digit = UInt32(bytes[position] - 0x57)
            default: throw PreviewFailure.malformedDocument
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    /// Validates the retained bytes as UTF-8, first dropping a scalar the clip cut in half.
    private static func decode(_ output: inout [UInt8], clipped: Bool) throws -> String {
        if clipped { trimIncompleteScalar(&output) }
        guard let text = String(validating: output, as: UTF8.self) else { throw PreviewFailure.malformedDocument }
        return text
    }

    private static func trimIncompleteScalar(_ bytes: inout [UInt8]) {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, bytes[index] & 0xC0 == 0x80, continuation < 3 {
            index -= 1
            continuation += 1
        }
        guard index >= 0 else { return }
        let lead = bytes[index]
        let expected = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        if expected > continuation + 1 { bytes.removeSubrange(index...) }
    }
}

/// A small materialized JSON value for documents that are bounded by construction, such as the
/// schema embedded in an Avro file. Numbers keep their exact spelling.
indirect enum DataJSONValue {
    case object([(key: String, value: DataJSONValue)])
    case array([DataJSONValue])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    subscript(key: String) -> DataJSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }
    var stringValue: String? { if case .string(let text) = self { text } else { nil } }
    var arrayValue: [DataJSONValue]? { if case .array(let values) = self { values } else { nil } }
    var integerValue: Int? { if case .number(let lexeme) = self { Int(lexeme) } else { nil } }
}

extension DataJSONReader {
    /// Reads one value into a tree. `nodes` is the remaining node allowance for the whole tree.
    mutating func value(depth: Int, nodes: inout Int, maximumStringBytes: Int = 65_536) throws -> DataJSONValue {
        guard nodes > 0 else { throw PreviewFailure.tooManyNodes }
        nodes -= 1
        switch try peekKind() {
        case .object:
            var members: [(key: String, value: DataJSONValue)] = []
            var remaining = nodes
            try forEachMember(depth: depth) { key, reader in
                members.append((key, try reader.value(depth: depth + 1, nodes: &remaining,
                                                      maximumStringBytes: maximumStringBytes)))
            }
            nodes = remaining
            return .object(members)
        case .array:
            var elements: [DataJSONValue] = []
            var remaining = nodes
            try forEachElement(depth: depth) { _, reader in
                elements.append(try reader.value(depth: depth + 1, nodes: &remaining,
                                                 maximumStringBytes: maximumStringBytes))
            }
            nodes = remaining
            return .array(elements)
        case .string: return .string(try string(maximumBytes: maximumStringBytes).text)
        case .number: return .number(lexeme(try numberSpan()))
        case .boolean: return .boolean(try boolean())
        case .null:
            try null()
            return .null
        }
    }
}
