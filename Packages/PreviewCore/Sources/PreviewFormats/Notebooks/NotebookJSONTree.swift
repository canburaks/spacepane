import Foundation
import PreviewContracts

/// One string token of already-validated JSON: its exact raw byte span (quotes included)
/// and its decoded text. The span is what privacy concealment replaces.
struct NotebookJSONString {
    let range: Range<Int>
    let value: String
}

struct NotebookJSONMember {
    let key: NotebookJSONString
    let value: NotebookJSONValue
    /// Exact value span, excluding surrounding whitespace, for inert source replacement.
    let valueRange: Range<Int>
}

/// Typed view of notebook JSON. Numbers and literals keep only their byte span, so their
/// original spelling is read on demand and is never converted or rounded.
enum NotebookJSONValue {
    case object([NotebookJSONMember])
    case array([NotebookJSONValue])
    case string(NotebookJSONString)
    case number(Range<Int>)
    case literal(Range<Int>)

    /// Duplicate names are ambiguous across JSON implementations; a looked-up notebook field
    /// that occurs twice is rejected instead of silently preferring either value.
    func member(_ name: String) throws -> NotebookJSONValue? {
        guard case .object(let members) = self else { return nil }
        var found: NotebookJSONValue?
        for member in members where member.key.value.utf8.elementsEqual(name.utf8) {
            guard found == nil else { throw PreviewFailure.malformedDocument }
            found = member.value
        }
        return found
    }
}

/// Builds the typed tree from bytes that `JSONScanner` has already validated. The scanner
/// owns grammar, depth and node budgets; this pass only decodes and keeps byte spans, and
/// still fails closed rather than trusting an index. It performs no source access.
struct NotebookJSONTreeBuilder {
    private let bytes: [UInt8]
    private let context: RequestContext
    private var position = 0
    private var checkpointPosition = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    mutating func build() throws -> NotebookJSONValue {
        try context.checkpoint()
        skipWhitespace()
        let root = try value(depth: 1)
        skipWhitespace()
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return root
    }

    private mutating func value(depth: Int) throws -> NotebookJSONValue {
        try checkpointProgress()
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        guard let byte = current else { throw PreviewFailure.malformedDocument }
        switch byte {
        case 123: return try object(depth: depth)
        case 91: return try array(depth: depth)
        case 34: return .string(try string())
        case 116, 102, 110: return try literal()
        case 45, 48...57: return try number()
        default: throw PreviewFailure.malformedDocument
        }
    }

    private mutating func object(depth: Int) throws -> NotebookJSONValue {
        position += 1
        skipWhitespace()
        var members: [NotebookJSONMember] = []
        if take(125) { return .object(members) }
        while true {
            let key = try string()
            skipWhitespace()
            guard take(58) else { throw PreviewFailure.malformedDocument }
            skipWhitespace()
            let valueStart = position
            let memberValue = try value(depth: depth + 1)
            members.append(NotebookJSONMember(key: key, value: memberValue, valueRange: valueStart..<position))
            skipWhitespace()
            if take(125) { return .object(members) }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            skipWhitespace()
        }
    }

    private mutating func array(depth: Int) throws -> NotebookJSONValue {
        position += 1
        skipWhitespace()
        var elements: [NotebookJSONValue] = []
        if take(93) { return .array(elements) }
        while true {
            elements.append(try value(depth: depth + 1))
            skipWhitespace()
            if take(93) { return .array(elements) }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            skipWhitespace()
        }
    }

    private mutating func string() throws -> NotebookJSONString {
        let start = position
        guard take(34) else { throw PreviewFailure.malformedDocument }
        var escaped = false
        while let byte = current {
            try checkpointProgress()
            position += 1
            if byte == 34 {
                return NotebookJSONString(range: start..<position, value: try decode(start + 1..<position - 1, escaped: escaped))
            }
            if byte == 92 {
                escaped = true
                guard current != nil else { throw PreviewFailure.malformedDocument }
                position += 1
            }
        }
        throw PreviewFailure.malformedDocument
    }

    /// Mirrors the scanner's grammar. Lone surrogates were already rejected there; they are
    /// rejected again here so that a decoding disagreement cannot produce replacement text.
    private func decode(_ content: Range<Int>, escaped: Bool) throws -> String {
        guard escaped else { return String(decoding: bytes[content], as: UTF8.self) }
        var output: [UInt8] = []
        output.reserveCapacity(content.count)
        var index = content.lowerBound
        while index < content.upperBound {
            if (index - content.lowerBound).isMultiple(of: 4096) { try context.checkpoint() }
            let byte = bytes[index]
            index += 1
            guard byte == 92 else { output.append(byte); continue }
            guard index < content.upperBound else { throw PreviewFailure.malformedDocument }
            let escape = bytes[index]
            index += 1
            switch escape {
            case 34, 92, 47: output.append(escape)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                var scalarValue = try hex4(at: &index, limit: content.upperBound)
                if (0xD800...0xDBFF).contains(scalarValue) {
                    guard index + 1 < content.upperBound, bytes[index] == 92, bytes[index + 1] == 117 else {
                        throw PreviewFailure.malformedDocument
                    }
                    index += 2
                    let low = try hex4(at: &index, limit: content.upperBound)
                    guard (0xDC00...0xDFFF).contains(low) else { throw PreviewFailure.malformedDocument }
                    scalarValue = 0x10000 + ((scalarValue - 0xD800) << 10) + (low - 0xDC00)
                }
                guard let scalar = Unicode.Scalar(scalarValue) else { throw PreviewFailure.malformedDocument }
                output.append(contentsOf: Array(String(Character(scalar)).utf8))
            default: throw PreviewFailure.malformedDocument
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func hex4(at index: inout Int, limit: Int) throws -> UInt32 {
        guard index + 4 <= limit else { throw PreviewFailure.malformedDocument }
        var result: UInt32 = 0
        for _ in 0..<4 {
            let digit: UInt32
            switch bytes[index] {
            case 48...57: digit = UInt32(bytes[index] - 48)
            case 65...70: digit = UInt32(bytes[index] - 55)
            case 97...102: digit = UInt32(bytes[index] - 87)
            default: throw PreviewFailure.malformedDocument
            }
            result = result * 16 + digit
            index += 1
        }
        return result
    }

    private mutating func number() throws -> NotebookJSONValue {
        let start = position
        while let byte = current, [43, 45, 46, 69, 101].contains(byte) || (48...57).contains(byte) {
            try checkpointProgress()
            position += 1
        }
        guard position > start else { throw PreviewFailure.malformedDocument }
        return .number(start..<position)
    }

    private mutating func literal() throws -> NotebookJSONValue {
        let start = position
        while let byte = current, (97...122).contains(byte) { position += 1 }
        let spelling = bytes[start..<position]
        guard spelling.elementsEqual("true".utf8) || spelling.elementsEqual("false".utf8)
                || spelling.elementsEqual("null".utf8) else { throw PreviewFailure.malformedDocument }
        return .literal(start..<position)
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 9 || byte == 10 || byte == 13 || byte == 32 { position += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        position += 1
        return true
    }

    private mutating func checkpointProgress() throws {
        if position - checkpointPosition >= 512 {
            try context.checkpoint()
            checkpointPosition = position
        }
    }

    private var current: UInt8? { position < bytes.count ? bytes[position] : nil }
}
