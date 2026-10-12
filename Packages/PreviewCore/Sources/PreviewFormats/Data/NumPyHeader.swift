import Foundation
import PreviewContracts

/// A NumPy data type read from an `.npy` header's `descr`. Only the description is kept for
/// types whose values are not shown (strings, datetimes, objects, structured records). The
/// `object` kind is never loaded: it means pickled Python objects, which are never read.
struct NumPyDType {
    enum Kind: Equatable {
        case bool, signed, unsigned, float, complex
        case bytes, unicode, datetime, timedelta, void, object
        case structured
    }

    enum ByteOrder { case little, big, notApplicable }

    let kind: Kind
    let byteOrder: ByteOrder
    /// Bytes per element; 0 when not derivable (structured types).
    let itemSize: Int
    /// The `descr` spelling, for display. Structured types show their field count instead.
    let descr: String
    let unit: String?
    var fields: [(name: String, dtype: String)] = []

    /// Kinds whose values the table can print exactly.
    var hasPrintableValues: Bool {
        switch kind {
        case .bool: itemSize == 1
        case .signed, .unsigned: [1, 2, 4, 8].contains(itemSize)
        case .float: [2, 4, 8].contains(itemSize)
        case .complex: [8, 16].contains(itemSize)
        default: false
        }
    }

    /// A readable name followed by the on-disk spelling, such as `float64 (<f8)`.
    var display: String {
        let name: String
        switch kind {
        case .bool: name = "bool"
        case .signed: name = "int\(itemSize * 8)"
        case .unsigned: name = "uint\(itemSize * 8)"
        case .float: name = "float\(itemSize * 8)"
        case .complex: name = "complex\(itemSize * 8)"
        case .bytes: name = "bytes[\(itemSize)]"
        case .unicode: name = "str[\(itemSize / 4)]"
        case .datetime: name = "datetime64[\(unit ?? "generic")]"
        case .timedelta: name = "timedelta64[\(unit ?? "generic")]"
        case .void: name = "void[\(itemSize)]"
        case .object: name = "object"
        case .structured: return "structured (\(fields.count))"
        }
        return "\(name) (\(descr))"
    }

    /// Parses a type string such as `<f8`, `|b1`, `>i4`, `<U5` or `<M8[ns]`.
    init(descr: String) throws {
        var text = Substring(descr)
        var order = ByteOrder.notApplicable
        if let first = text.first, "<>|=".contains(first) {
            order = first == ">" ? .big : first == "|" ? .notApplicable : .little
            text = text.dropFirst()
        }
        guard let letter = text.first else { throw PreviewFailure.malformedDocument }
        text = text.dropFirst()
        var digits = ""
        while let next = text.first, next.isASCII, next.isNumber {
            digits.append(next)
            text = text.dropFirst()
        }
        var parsedUnit: String?
        if text.first == "[", text.last == "]" {
            parsedUnit = String(text.dropFirst().dropLast())
            text = ""
        }
        guard text.isEmpty, digits.count <= 6 else { throw PreviewFailure.malformedDocument }
        let size = Int(digits)
        let resolved: (Kind, Int)
        switch letter {
        case "b": resolved = (.bool, size ?? 1)
        case "i": resolved = (.signed, size ?? 8)
        case "u": resolved = (.unsigned, size ?? 8)
        case "f": resolved = (.float, size ?? 8)
        case "c": resolved = (.complex, size ?? 16)
        case "S", "a": resolved = (.bytes, size ?? 0)
        case "U": resolved = (.unicode, (size ?? 0) * 4)
        case "M": resolved = (.datetime, size ?? 8)
        case "m": resolved = (.timedelta, size ?? 8)
        case "V": resolved = (.void, size ?? 0)
        case "O": resolved = (.object, size ?? 8)
        default: throw PreviewFailure.malformedDocument
        }
        kind = resolved.0
        itemSize = resolved.1
        byteOrder = order
        self.descr = descr
        unit = parsedUnit
    }

    /// A record dtype: only its field names and types are described.
    init(structuredFields: [(name: String, dtype: String)], descr: String) {
        kind = .structured
        byteOrder = .notApplicable
        itemSize = 0
        self.descr = descr
        unit = nil
        fields = structuredFields
    }
}

/// The three entries of an `.npy` header dictionary.
struct NumPyHeader {
    let dtype: NumPyDType
    let fortranOrder: Bool
    let shape: [Int]
    /// Bytes from the start of the array stream to the first data byte.
    let dataOffset: Int
    /// The format version from the preamble, such as `1.0`.
    let version: String

    var elementCount: Int? {
        var total = 1
        for dimension in shape {
            let (product, overflow) = total.multipliedReportingOverflow(by: dimension)
            if overflow { return nil }
            total = product
        }
        return total
    }

    /// Bytes of array data; nil for types without a fixed element size or on overflow.
    var dataByteCount: Int? {
        guard dtype.kind != .structured, let count = elementCount else { return nil }
        let (bytes, overflow) = count.multipliedReportingOverflow(by: dtype.itemSize)
        return overflow ? nil : bytes
    }

    var shapeDescription: String {
        shape.count == 1 ? "(\(shape[0]),)" : "(" + shape.map(String.init).joined(separator: ", ") + ")"
    }

    static let maximumHeaderBytes = 65_536
    private static let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]

    /// Parses the preamble and header from the first bytes of an array stream. `read` returns
    /// bytes at an offset of that stream, so the same code serves files and archive members.
    static func parse(available: Int, context: RequestContext,
                      read: (_ offset: Int, _ count: Int) throws -> [UInt8]) throws -> NumPyHeader {
        try context.checkpoint()
        guard available >= 10 else { throw PreviewFailure.malformedDocument }
        let preamble = try read(0, 10)
        guard preamble.count == 10, Array(preamble[0..<6]) == magic else { throw PreviewFailure.malformedDocument }
        let major = preamble[6]
        let headerStart: Int
        let headerLength: Int
        switch major {
        case 1:
            headerStart = 10
            headerLength = Int(preamble[8]) | Int(preamble[9]) << 8
        case 2, 3:
            guard available >= 12 else { throw PreviewFailure.malformedDocument }
            let extended = try read(8, 4)
            guard extended.count == 4 else { throw PreviewFailure.malformedDocument }
            headerStart = 12
            headerLength = extended.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        default:
            throw PreviewFailure.unsupportedFormat
        }
        guard headerLength > 0, headerLength <= maximumHeaderBytes, headerStart + headerLength <= available else {
            throw PreviewFailure.malformedDocument
        }
        let text = try read(headerStart, headerLength)
        guard text.count == headerLength else { throw PreviewFailure.malformedDocument }
        var parser = NumPyLiteralParser(bytes: text, utf8: major == 3, context: context)
        let dictionary = try parser.dictionary()
        return try interpret(dictionary, dataOffset: headerStart + headerLength, version: "\(major).\(preamble[7])")
    }

    private static func interpret(_ entries: [(key: String, value: NumPyLiteral)], dataOffset: Int,
                                  version: String) throws -> NumPyHeader {
        guard entries.count == 3, Set(entries.map(\.key)).count == 3,
              let description = entries.first(where: { $0.key == "descr" })?.value,
              case .bool(let fortran)? = entries.first(where: { $0.key == "fortran_order" })?.value,
              case .tuple(let dimensions)? = entries.first(where: { $0.key == "shape" })?.value,
              dimensions.count <= 32 else { throw PreviewFailure.malformedDocument }
        let shape = try dimensions.map { value -> Int in
            guard case .integer(let dimension) = value else { throw PreviewFailure.malformedDocument }
            return dimension
        }
        return NumPyHeader(dtype: try dtype(from: description), fortranOrder: fortran, shape: shape,
                           dataOffset: dataOffset, version: version)
    }

    private static func dtype(from literal: NumPyLiteral) throws -> NumPyDType {
        switch literal {
        case .string(let text):
            return try NumPyDType(descr: text)
        case .list(let items):
            // A structured dtype: `[(name, type[, shape]), ...]`. Padding fields have empty names.
            var fields: [(name: String, dtype: String)] = []
            for item in items {
                guard case .tuple(let parts) = item, parts.count >= 2, parts.count <= 3,
                      case .string(let name) = parts[0] else { throw PreviewFailure.malformedDocument }
                let described: String
                switch parts[1] {
                case .string(let text): described = try NumPyDType(descr: text).display
                case .list: described = try dtype(from: parts[1]).display
                default: throw PreviewFailure.malformedDocument
                }
                fields.append((DataTable.clip(name, to: 100).0, described))
            }
            return NumPyDType(structuredFields: fields, descr: "structured")
        default:
            throw PreviewFailure.malformedDocument
        }
    }
}

/// A Python literal, restricted to what an `.npy` header can contain.
indirect enum NumPyLiteral {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case tuple([NumPyLiteral])
    case list([NumPyLiteral])
}

/// A strict recursive-descent reader for the header's Python dictionary literal. It never
/// evaluates anything: names, calls, comments and operators are all errors. Depth, node count and
/// string length are bounded.
struct NumPyLiteralParser {
    private let bytes: [UInt8]
    private let utf8: Bool
    private let context: RequestContext
    private var position = 0
    private var remainingNodes = 4_000
    private static let maximumDepth = 8
    private static let maximumStringBytes = 1_024

    init(bytes: [UInt8], utf8: Bool, context: RequestContext) {
        self.bytes = bytes
        self.utf8 = utf8
        self.context = context
    }

    mutating func dictionary() throws -> [(key: String, value: NumPyLiteral)] {
        skipSpace()
        guard take(0x7B) else { throw PreviewFailure.malformedDocument }
        var entries: [(key: String, value: NumPyLiteral)] = []
        while true {
            skipSpace()
            if take(0x7D) { break }
            guard case .string(let key) = try literal(depth: 1) else { throw PreviewFailure.malformedDocument }
            skipSpace()
            guard take(0x3A) else { throw PreviewFailure.malformedDocument }
            entries.append((key, try literal(depth: 1)))
            guard entries.count <= 16 else { throw PreviewFailure.tooManyNodes }
            skipSpace()
            if take(0x2C) { continue }
            skipSpace()
            guard take(0x7D) else { throw PreviewFailure.malformedDocument }
            break
        }
        skipSpace()
        // The rest is padding: spaces and a final newline.
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        return entries
    }

    private mutating func literal(depth: Int) throws -> NumPyLiteral {
        guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
        guard remainingNodes > 0 else { throw PreviewFailure.tooManyNodes }
        remainingNodes -= 1
        if remainingNodes.isMultiple(of: 256) { try context.checkpoint() }
        skipSpace()
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        switch bytes[position] {
        case 0x27, 0x22: return .string(try string())
        case 0x28: return .tuple(try sequence(close: 0x29, depth: depth))
        case 0x5B: return .list(try sequence(close: 0x5D, depth: depth))
        case 0x30...0x39: return .integer(try integer())
        case 0x54: try word("True"); return .bool(true)
        case 0x46: try word("False"); return .bool(false)
        default: throw PreviewFailure.malformedDocument
        }
    }

    /// Elements of a tuple or list; a trailing comma is allowed, as Python does.
    private mutating func sequence(close: UInt8, depth: Int) throws -> [NumPyLiteral] {
        position += 1
        var items: [NumPyLiteral] = []
        while true {
            skipSpace()
            if take(close) { return items }
            items.append(try literal(depth: depth + 1))
            guard items.count <= 1_024 else { throw PreviewFailure.tooManyNodes }
            skipSpace()
            if take(0x2C) { continue }
            skipSpace()
            guard take(close) else { throw PreviewFailure.malformedDocument }
            return items
        }
    }

    private mutating func string() throws -> String {
        let quote = bytes[position]
        position += 1
        var raw: [UInt8] = []
        while true {
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            let byte = bytes[position]
            position += 1
            if byte == quote { break }
            guard byte >= 0x20 else { throw PreviewFailure.malformedDocument }
            if byte == 0x5C {
                guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                let escape = bytes[position]
                position += 1
                switch escape {
                case 0x5C, 0x27, 0x22: raw.append(escape)
                case 0x6E: raw.append(0x0A)
                case 0x74: raw.append(0x09)
                default: throw PreviewFailure.malformedDocument
                }
            } else {
                raw.append(byte)
            }
            guard raw.count <= Self.maximumStringBytes else { throw PreviewFailure.lineTooLong }
        }
        if utf8 {
            guard let text = String(validating: raw, as: UTF8.self) else { throw PreviewFailure.malformedDocument }
            return text
        }
        // Versions 1 and 2 store Latin-1.
        return String(String.UnicodeScalarView(raw.map { Unicode.Scalar($0) }))
    }

    /// A non-negative decimal integer, optionally with Python 2's `L` suffix.
    private mutating func integer() throws -> Int {
        var value = 0
        var count = 0
        while position < bytes.count, (0x30...0x39).contains(bytes[position]) {
            let (scaled, first) = value.multipliedReportingOverflow(by: 10)
            let (sum, second) = scaled.addingReportingOverflow(Int(bytes[position] - 0x30))
            guard !first, !second else { throw PreviewFailure.malformedDocument }
            value = sum
            position += 1
            count += 1
        }
        guard count > 0 else { throw PreviewFailure.malformedDocument }
        if position < bytes.count, bytes[position] == 0x4C { position += 1 }
        return value
    }

    private mutating func word(_ expected: String) throws {
        let letters = Array(expected.utf8)
        guard position + letters.count <= bytes.count, Array(bytes[position..<(position + letters.count)]) == letters else {
            throw PreviewFailure.malformedDocument
        }
        position += letters.count
        if position < bytes.count, (0x41...0x5A).contains(bytes[position]) || (0x61...0x7A).contains(bytes[position])
            || (0x30...0x39).contains(bytes[position]) || bytes[position] == 0x5F { throw PreviewFailure.malformedDocument }
    }

    private mutating func skipSpace() {
        while position < bytes.count, bytes[position] == 0x20 || bytes[position] == 0x0A
                || bytes[position] == 0x09 || bytes[position] == 0x0D { position += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }
}
