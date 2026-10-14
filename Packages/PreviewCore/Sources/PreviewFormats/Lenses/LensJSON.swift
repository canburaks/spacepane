import Foundation
import PreviewContracts

/// One value of the displayed JSON and the logical line it starts on (decision 029).
///
/// The configuration lenses read the *displayed, concealed* text, so they cannot use `JSONSerialization`
/// on it: concealment leaves a bare `••••` where a secret value stood, which is not JSON, and Foundation
/// reports no positions. This small reader accepts what the three JSON adapters accept (comments,
/// trailing commas, single-quoted strings, unquoted keys, the bare concealment token) and records the
/// line of every value and member key, counted with `LogicalLines`' definition of a line break so the
/// lines match the gutter and the findings of every other stage.
struct LensJSONNode: Sendable {
    /// One-based logical line on which the value starts.
    let line: Int
    let value: LensJSONValue
}

enum LensJSONValue: Sendable {
    case object([LensJSONMember])
    case array([LensJSONNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    /// `SecretFieldPolicy.concealmentToken` where the privacy stage hid a value of any type.
    case concealed
}

struct LensJSONMember: Sendable {
    let key: String
    /// Line of the key.
    let line: Int
    let value: LensJSONNode
}

extension LensJSONNode {
    var members: [LensJSONMember]? { if case .object(let members) = value { members } else { nil } }
    var elements: [LensJSONNode]? { if case .array(let elements) = value { elements } else { nil } }
    var string: String? { if case .string(let text) = value { text } else { nil } }
    var number: Double? { if case .number(let number) = value { number } else { nil } }
    var bool: Bool? { if case .bool(let flag) = value { flag } else { nil } }
    var isConcealed: Bool { if case .concealed = value { true } else { false } }
    var isNull: Bool { if case .null = value { true } else { false } }

    /// The member with exactly this key. With duplicate keys the last wins, as in `JSON.parse`.
    /// Keys compare by code units: `String` equality would equate canonically equivalent spellings
    /// (the Kelvin sign and `K`), which no consumer of the file does.
    func member(_ key: String) -> LensJSONMember? {
        members?.last { $0.key.equalsExactly(key) }
    }

    /// Whether the value stands for something: not null, not an empty string, array or object.
    /// A concealed value counts, because something was there.
    var hasContent: Bool {
        switch value {
        case .null: false
        case .string(let text): !text.isEmpty
        case .array(let elements): !elements.isEmpty
        case .object(let members): !members.isEmpty
        case .number, .bool, .concealed: true
        }
    }

    func isString(_ expected: String) -> Bool { string?.equalsExactly(expected) == true }
}

extension String {
    /// Code-unit equality, for keys and enumerated values of file formats.
    func equalsExactly(_ other: String) -> Bool { utf8.elementsEqual(other.utf8) }
}

enum LensJSON {
    /// The root value of `text`, or `nil` when the text is not one complete JSON document within the
    /// request's depth and node budgets. Malformed input never throws: only cancellation and the
    /// request deadline do. Work is linear in the text and allocates nothing beyond the parsed values.
    static func parse(_ text: String, context: RequestContext) throws -> LensJSONNode? {
        var reader = LensJSONReader(bytes: Array(text.utf8), context: context)
        do { return try reader.document() }
        catch is LensJSONReader.Failure { return nil }
    }
}

private struct LensJSONReader {
    /// The input is not a document this reader accepts, or exceeds a budget.
    struct Failure: Error {}

    private static let concealment = Array(SecretFieldPolicy.concealmentToken.utf8)
    private static let checkpointInterval = 4_096

    private let bytes: [UInt8]
    private let context: RequestContext
    private var index = 0
    private var line = 1
    private var nodes = 0
    private var checkpointIndex = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    mutating func document() throws -> LensJSONNode {
        try context.checkpoint()
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
        try skipTrivia()
        let root = try value(depth: 1)
        try skipTrivia()
        guard index == bytes.count else { throw Failure() }
        try context.checkpoint()
        return root
    }

    // MARK: Positions

    /// Byte length of the line break at `position`, or 0: LF, CR, CRLF, NEL, LINE SEPARATOR and
    /// PARAGRAPH SEPARATOR, the breaks of `LogicalLines`.
    private func lineBreakLength(at position: Int) -> Int {
        switch bytes[position] {
        case 0x0A: return 1
        case 0x0D: return position + 1 < bytes.count && bytes[position + 1] == 0x0A ? 2 : 1
        case 0xC2: return position + 1 < bytes.count && bytes[position + 1] == 0x85 ? 2 : 0
        case 0xE2:
            return position + 2 < bytes.count && bytes[position + 1] == 0x80
                && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9) ? 3 : 0
        default: return 0
        }
    }

    /// Steps over one byte or one line break, counting the line.
    private mutating func advance() {
        let length = lineBreakLength(at: index)
        if length > 0 { line += 1; index += length } else { index += 1 }
    }

    private mutating func tick() throws {
        if index - checkpointIndex >= Self.checkpointInterval {
            checkpointIndex = index
            try context.checkpoint()
        }
    }

    // MARK: Grammar

    private mutating func skipTrivia() throws {
        while index < bytes.count {
            try tick()
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0B || byte == 0x0C { index += 1; continue }
            if lineBreakLength(at: index) > 0 { advance(); continue }
            guard byte == 0x2F, index + 1 < bytes.count else { return }
            if bytes[index + 1] == 0x2F {
                index += 2
                while index < bytes.count, lineBreakLength(at: index) == 0 { index += 1; try tick() }
            } else if bytes[index + 1] == 0x2A {
                index += 2
                var closed = false
                while index < bytes.count {
                    try tick()
                    if bytes[index] == 0x2A, index + 1 < bytes.count, bytes[index + 1] == 0x2F {
                        index += 2
                        closed = true
                        break
                    }
                    advance()
                }
                guard closed else { throw Failure() }
            } else { return }
        }
    }

    private mutating func value(depth: Int) throws -> LensJSONNode {
        try context.checkpoint()
        nodes += 1
        guard depth <= context.budget.maxJSONDepth, nodes <= context.budget.maxJSONNodes,
              index < bytes.count else { throw Failure() }
        let start = line
        switch bytes[index] {
        case 0x7B: return LensJSONNode(line: start, value: .object(try object(depth: depth)))
        case 0x5B: return LensJSONNode(line: start, value: .array(try array(depth: depth)))
        case 0x22, 0x27: return LensJSONNode(line: start, value: .string(try string()))
        default: return LensJSONNode(line: start, value: try bare())
        }
    }

    private mutating func object(depth: Int) throws -> [LensJSONMember] {
        index += 1
        var members: [LensJSONMember] = []
        while true {
            try skipTrivia()
            guard index < bytes.count else { throw Failure() }
            if bytes[index] == 0x7D { index += 1; return members }
            let keyLine = line
            let key = try keyName()
            try skipTrivia()
            guard index < bytes.count, bytes[index] == 0x3A else { throw Failure() }
            index += 1
            try skipTrivia()
            members.append(LensJSONMember(key: key, line: keyLine, value: try value(depth: depth + 1)))
            try skipTrivia()
            guard index < bytes.count else { throw Failure() }
            if bytes[index] == 0x2C { index += 1; continue }
            guard bytes[index] == 0x7D else { throw Failure() }
            index += 1
            return members
        }
    }

    private mutating func array(depth: Int) throws -> [LensJSONNode] {
        index += 1
        var elements: [LensJSONNode] = []
        while true {
            try skipTrivia()
            guard index < bytes.count else { throw Failure() }
            if bytes[index] == 0x5D { index += 1; return elements }
            elements.append(try value(depth: depth + 1))
            try skipTrivia()
            guard index < bytes.count else { throw Failure() }
            if bytes[index] == 0x2C { index += 1; continue }
            guard bytes[index] == 0x5D else { throw Failure() }
            index += 1
            return elements
        }
    }

    private mutating func keyName() throws -> String {
        if bytes[index] == 0x22 || bytes[index] == 0x27 { return try string() }
        let start = index
        while index < bytes.count, JSON5Lexicon.isIdentifierPart(bytes[index]) { index += 1 }
        guard start < index else { throw Failure() }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    /// A quoted string. Line breaks inside it (a line continuation, or LINE and PARAGRAPH SEPARATOR,
    /// which JSON allows) count as lines.
    private mutating func string() throws -> String {
        let quote = bytes[index]
        index += 1
        let start = index
        while true {
            guard index < bytes.count else { throw Failure() }
            try tick()
            let byte = bytes[index]
            if byte == quote { break }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else { throw Failure() }
            }
            advance()
        }
        let content = bytes[start..<index]
        index += 1
        guard let decoded = JSON5Lexicon.decodeString(content) else { throw Failure() }
        return decoded
    }

    /// `true`, `false`, `null`, a number, or the concealment token.
    private mutating func bare() throws -> LensJSONValue {
        let start = index
        while index < bytes.count, !Self.isDelimiter(bytes[index]), lineBreakLength(at: index) == 0 { index += 1 }
        let token = bytes[start..<index]
        guard !token.isEmpty else { throw Failure() }
        if token.elementsEqual(Self.concealment) { return .concealed }
        switch String(decoding: token, as: UTF8.self) {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default:
            guard JSON5Lexicon.isNumber(token) else { throw Failure() }
            return .number(Double(String(decoding: token, as: UTF8.self)) ?? .nan)
        }
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        JSON5Lexicon.isWhitespace(byte) || byte == 0x2C || byte == 0x5D || byte == 0x7D || byte == 0x3A
            || byte == 0x2F || byte == 0x22 || byte == 0x27
    }
}
