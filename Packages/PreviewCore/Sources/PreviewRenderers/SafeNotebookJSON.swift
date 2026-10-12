import Foundation
import PreviewContracts

/// Typed value of notebook JSON that has already passed the shared privacy filter. The filter
/// can replace a complete string, array or object with the inert concealment token, so the token
/// is a first-class scalar here rather than a syntax error. Typed access (unlike the display
/// outline) keeps a string such as "{…}" distinct from an empty object.
enum SafeNotebookValue {
    case object([SafeNotebookMember])
    case array([SafeNotebookValue])
    case string(String)
    case number(String)
    case literal(String)
    case concealed

    static let concealmentToken = SecretFieldPolicy.concealmentToken

    /// A repeated name is ambiguous between JSON implementations; the view declines such a
    /// notebook instead of preferring one value.
    func member(_ name: String) throws -> SafeNotebookValue? {
        guard case .object(let members) = self else { return nil }
        var found: SafeNotebookValue?
        for member in members where member.key.utf8.elementsEqual(name.utf8) {
            guard found == nil else { throw SafeNotebookInvalid() }
            found = member.value
        }
        return found
    }
}

struct SafeNotebookMember {
    let key: String
    let value: SafeNotebookValue
}

struct SafeNotebookInvalid: Error {}

/// Bounded recursive-descent reader over privacy-filtered text only. It never sees source bytes.
struct SafeNotebookJSONParser {
    private static let tokenBytes = Array(SafeNotebookValue.concealmentToken.utf8)
    private let bytes: [UInt8]
    private let maximumNodes: Int
    private let maximumDepth: Int
    private var position = 0
    private var nodes = 0

    /// Returns nil for oversized, too-deep, too-large or syntactically invalid text.
    static func parse(_ source: String, maximumUTF16Units: Int, maximumNodes: Int, maximumDepth: Int) -> SafeNotebookValue? {
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumNodes > 0, maximumDepth > 0,
              source.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units else { return nil }
        var parser = SafeNotebookJSONParser(bytes: Array(source.utf8), maximumNodes: maximumNodes, maximumDepth: maximumDepth)
        return try? parser.document()
    }

    private init(bytes: [UInt8], maximumNodes: Int, maximumDepth: Int) {
        self.bytes = bytes
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
    }

    private mutating func document() throws -> SafeNotebookValue {
        skipWhitespace()
        let root = try value(depth: 1)
        skipWhitespace()
        guard position == bytes.count else { throw SafeNotebookInvalid() }
        return root
    }

    private mutating func value(depth: Int) throws -> SafeNotebookValue {
        guard depth <= maximumDepth, nodes < maximumNodes, let byte = current else { throw SafeNotebookInvalid() }
        nodes += 1
        switch byte {
        case 123: return try object(depth: depth)
        case 91: return try array(depth: depth)
        case 34: return .string(try string())
        case 116: return try literal("true")
        case 102: return try literal("false")
        case 110: return try literal("null")
        case 45, 48...57: return try number()
        default:
            guard bytes[position...].starts(with: Self.tokenBytes) else { throw SafeNotebookInvalid() }
            position += Self.tokenBytes.count
            try requireScalarBoundary()
            return .concealed
        }
    }

    private mutating func object(depth: Int) throws -> SafeNotebookValue {
        position += 1
        skipWhitespace()
        var members: [SafeNotebookMember] = []
        if take(125) { return .object(members) }
        while true {
            let key = try string()
            skipWhitespace()
            guard take(58) else { throw SafeNotebookInvalid() }
            skipWhitespace()
            members.append(SafeNotebookMember(key: key, value: try value(depth: depth + 1)))
            skipWhitespace()
            if take(125) { return .object(members) }
            guard take(44) else { throw SafeNotebookInvalid() }
            skipWhitespace()
        }
    }

    private mutating func array(depth: Int) throws -> SafeNotebookValue {
        position += 1
        skipWhitespace()
        var elements: [SafeNotebookValue] = []
        if take(93) { return .array(elements) }
        while true {
            elements.append(try value(depth: depth + 1))
            skipWhitespace()
            if take(93) { return .array(elements) }
            guard take(44) else { throw SafeNotebookInvalid() }
            skipWhitespace()
        }
    }

    private mutating func string() throws -> String {
        guard take(34) else { throw SafeNotebookInvalid() }
        var output: [UInt8] = []
        while let byte = current {
            position += 1
            if byte == 34 { return String(decoding: output, as: UTF8.self) }
            guard byte >= 32 else { throw SafeNotebookInvalid() }
            guard byte == 92 else { output.append(byte); continue }
            guard let escape = current else { throw SafeNotebookInvalid() }
            position += 1
            switch escape {
            case 34, 92, 47: output.append(escape)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                var scalarValue = try hex4()
                if (0xD800...0xDBFF).contains(scalarValue) {
                    guard take(92), take(117) else { throw SafeNotebookInvalid() }
                    let low = try hex4()
                    guard (0xDC00...0xDFFF).contains(low) else { throw SafeNotebookInvalid() }
                    scalarValue = 0x10000 + ((scalarValue - 0xD800) << 10) + (low - 0xDC00)
                }
                guard let scalar = Unicode.Scalar(scalarValue) else { throw SafeNotebookInvalid() }
                output.append(contentsOf: Array(String(scalar).utf8))
            default: throw SafeNotebookInvalid()
            }
        }
        throw SafeNotebookInvalid()
    }

    private mutating func hex4() throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw SafeNotebookInvalid() }
            let digit: UInt32
            switch byte {
            case 48...57: digit = UInt32(byte - 48)
            case 65...70: digit = UInt32(byte - 55)
            case 97...102: digit = UInt32(byte - 87)
            default: throw SafeNotebookInvalid()
            }
            result = result * 16 + digit
            position += 1
        }
        return result
    }

    private mutating func number() throws -> SafeNotebookValue {
        let start = position
        _ = take(45)
        if !take(48) {
            guard let byte = current, (49...57).contains(byte) else { throw SafeNotebookInvalid() }
            consumeDigits()
        }
        if take(46) {
            guard let byte = current, (48...57).contains(byte) else { throw SafeNotebookInvalid() }
            consumeDigits()
        }
        if take(101) || take(69) {
            if !take(43) { _ = take(45) }
            guard let byte = current, (48...57).contains(byte) else { throw SafeNotebookInvalid() }
            consumeDigits()
        }
        try requireScalarBoundary()
        return .number(String(decoding: bytes[start..<position], as: UTF8.self))
    }

    private mutating func literal(_ expected: String) throws -> SafeNotebookValue {
        let spelling = Array(expected.utf8)
        guard bytes[position...].starts(with: spelling) else { throw SafeNotebookInvalid() }
        position += spelling.count
        try requireScalarBoundary()
        return .literal(expected)
    }

    private mutating func consumeDigits() { while let byte = current, (48...57).contains(byte) { position += 1 } }

    /// A bare scalar must end at whitespace, a delimiter or the end of the text.
    private func requireScalarBoundary() throws {
        guard let byte = current else { return }
        guard [9, 10, 13, 32, 44, 93, 125].contains(byte) else { throw SafeNotebookInvalid() }
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 9 || byte == 10 || byte == 13 || byte == 32 { position += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        position += 1
        return true
    }

    private var current: UInt8? { position < bytes.count ? bytes[position] : nil }
}
