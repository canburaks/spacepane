import Foundation
import PreviewContracts

/// Apple's quoted key/value source form, including comments and Unicode escapes.
/// Unsupported legacy forms fail closed instead of guessing secret-field identity.
public struct StringsSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        var scanner = StringsScanner(bytes: Array(input.text.utf8), context: context)
        try scanner.scan()
        return ParsedTextDocument(text: input.text, sensitiveRanges: scanner.sensitive,
                                  usesStructuredPrivacy: true, syntax: .strings)
    }
}

private struct StringsScanner {
    let bytes: [UInt8]
    let context: RequestContext
    var index = 0
    var nodes = 0
    var sensitive: [SensitiveRange] = []

    mutating func scan() throws {
        while true {
            try trivia()
            guard index < bytes.count else { return }
            nodes += 1
            guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            let key = try quoted()
            try trivia()
            guard take(61) else { throw PreviewFailure.malformedDocument }
            try trivia()
            let start = index
            _ = try quoted()
            if SecretFieldPolicy.isSensitive(key) { sensitive.append(.init(utf8Range: start..<index)) }
            try trivia()
            guard take(59) else { throw PreviewFailure.malformedDocument }
        }
    }

    mutating func trivia() throws {
        while index < bytes.count {
            try context.checkpoint()
            if [9, 10, 13, 32].contains(bytes[index]) { index += 1; continue }
            if index + 1 < bytes.count, bytes[index] == 47, bytes[index + 1] == 47 {
                index += 2
                let contentStart = index
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { try progress(); index += 1 }
                try annotateComment(contentStart..<index)
            } else if index + 1 < bytes.count, bytes[index] == 47, bytes[index + 1] == 42 {
                index += 2
                let contentStart = index
                var closed = false
                while index + 1 < bytes.count {
                    try progress()
                    if bytes[index] == 42, bytes[index + 1] == 47 { index += 2; closed = true; break }
                    index += 1
                }
                guard closed else { throw PreviewFailure.malformedDocument }
                try annotateComment(contentStart..<(index - 2))
            } else { return }
        }
    }

    private mutating func annotateComment(_ content: Range<Int>) throws {
        if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: content, context: context) {
            guard sensitive.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            sensitive.append(range)
        }
    }

    mutating func quoted() throws -> String {
        guard take(34) else { throw PreviewFailure.malformedDocument }
        var output: [UInt8] = []
        while index < bytes.count {
            try progress()
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                guard let text = String(bytes: output, encoding: .utf8) else { throw PreviewFailure.malformedDocument }
                return text
            }
            if byte != 92 { output.append(byte); continue }
            guard index < bytes.count else { throw PreviewFailure.malformedDocument }
            let escape = bytes[index]; index += 1
            switch escape {
            case 34, 92: output.append(escape)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 85, 117:
                let high = try hexUnit()
                let value: UInt32
                if (0xD800...0xDBFF).contains(high) {
                    guard take(92), index < bytes.count, [85, 117].contains(bytes[index]) else { throw PreviewFailure.malformedDocument }
                    index += 1
                    let low = try hexUnit()
                    guard (0xDC00...0xDFFF).contains(low) else { throw PreviewFailure.malformedDocument }
                    value = 0x10000 + ((high - 0xD800) << 10) + low - 0xDC00
                } else { value = high }
                guard let scalar = UnicodeScalar(value) else { throw PreviewFailure.malformedDocument }
                output.append(contentsOf: String(scalar).utf8)
            default: throw PreviewFailure.malformedDocument
            }
        }
        throw PreviewFailure.malformedDocument
    }

    mutating func hexUnit() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < bytes.count else { throw PreviewFailure.malformedDocument }
            let byte = bytes[index]; index += 1
            let digit: UInt32
            switch byte {
            case 48...57: digit = UInt32(byte - 48)
            case 65...70: digit = UInt32(byte - 55)
            case 97...102: digit = UInt32(byte - 87)
            default: throw PreviewFailure.malformedDocument
            }
            value = value * 16 + digit
        }
        return value
    }
    mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    func progress() throws { if index.isMultiple(of: 512) { try context.checkpoint() } }
}
