import Foundation
import PreviewContracts

/// JSON with comments (`.jsonc`, VS Code `.code-workspace`, `tsconfig.json`) and its JSON5 superset
/// (`.json5`). The adapter validates a bounded lenient grammar (see `JSON5Lexicon`) without converting
/// numbers, deduplicating keys or evaluating anything, and returns the exact decoded characters.
///
/// Privacy is structural, as for strict JSON: the value of every member whose decoded key names a
/// secret is concealed whole, quoted, unquoted or single-quoted keys alike. Comments are outside the
/// field grammar, so a comment whose text holds a secret assignment is concealed (its delimiters stay).
/// Malformed input is `malformedDocument` with no raw fallback, exactly like strict JSON, because
/// concealment cannot be trusted on a guessed structure. Depth and node counts use the JSON budgets.
public struct JSONCAdapter: FormatAdapter {
    public init() {}

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        var scanner = JSONCScanner(bytes: Array(input.text.utf8), context: context)
        try scanner.scan()
        return ParsedTextDocument(text: input.text, sensitiveRanges: scanner.sensitiveRanges,
                                  usesStructuredPrivacy: true, syntax: .jsonWithComments)
    }
}

/// Request-local lenient scanner. Recursion depth is bounded by `maxJSONDepth` before it can grow, and
/// each token or comment byte advances the position, so work is linear in the input.
struct JSONCScanner {
    let bytes: [UInt8]
    let context: RequestContext
    private var position = 0
    private var checkpointPosition = 0
    private var nodes = 0
    private(set) var sensitiveRanges: [SensitiveRange] = []
    private var sensitiveOffsets: Set<Range<Int>> = []

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    mutating func scan() throws {
        try context.checkpoint()
        try skipTrivia()
        try value(depth: 1)
        try skipTrivia()
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
    }

    // MARK: Grammar

    private mutating func addSensitive(_ range: Range<Int>) throws {
        if sensitiveOffsets.contains(range) { return }
        guard sensitiveRanges.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        sensitiveOffsets.insert(range)
        sensitiveRanges.append(.init(utf8Range: range))
    }

    @discardableResult
    private mutating func value(depth: Int) throws -> String? {
        try context.checkpoint()
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        nodes += 1
        guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard let byte = current else { throw PreviewFailure.malformedDocument }
        switch byte {
        case 123: try object(depth: depth)
        case 91: try array(depth: depth)
        case 34, 39:
            let start = position
            let decoded = try quoted()
            if bytes[start..<position].contains(92), try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded, originalText: String(decoding: bytes[start..<position], as: UTF8.self), context: context) {
                try addSensitive(start..<position)
            }
            return decoded
        default: try bareValue()
        }
        return nil
    }

    private mutating func object(depth: Int) throws {
        position += 1
        try skipTrivia()
        var hasSensitiveName = false
        var namedValues: [Range<Int>] = []
        while true {
            if take(125) { break }
            let key = try memberKey()
            try skipTrivia()
            guard take(58) else { throw PreviewFailure.malformedDocument }
            try skipTrivia()
            let start = position
            let decoded = try value(depth: depth + 1)
            let role = SecretFieldPolicy.namedValueRole(key)
            if role == .name, let decoded, SecretFieldPolicy.isSensitive(decoded) { hasSensitiveName = true }
            if role == .value { namedValues.append(start..<position) }
            if SecretFieldPolicy.isSensitive(key) {
                try addSensitive(start..<position)
            }
            try skipTrivia()
            if take(125) { break }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            try skipTrivia()   // A trailing comma is allowed: the loop head accepts `}` again.
        }
        if hasSensitiveName { for range in namedValues { try addSensitive(range) } }
    }

    private mutating func array(depth: Int) throws {
        position += 1
        try skipTrivia()
        while true {
            if take(93) { return }
            try value(depth: depth + 1)
            try skipTrivia()
            if take(93) { return }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            try skipTrivia()
        }
    }

    /// A quoted string or an unquoted identifier name, decoded for the privacy decision only.
    private mutating func memberKey() throws -> String {
        guard let byte = current else { throw PreviewFailure.malformedDocument }
        if byte == 34 || byte == 39 { return try quoted() }
        guard JSON5Lexicon.isIdentifierStart(byte) else { throw PreviewFailure.malformedDocument }
        let start = position
        while let next = current, JSON5Lexicon.isIdentifierPart(next) {
            try progress()
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    /// Consumes a quoted string and returns its decoded characters. A raw line break is invalid unless
    /// escaped; the escape rules are those of `JSON5Lexicon.decodeString`.
    @discardableResult
    private mutating func quoted() throws -> String {
        let quote = bytes[position]
        position += 1
        let start = position
        while let byte = current {
            try progress()
            if byte == quote {
                let content = bytes[start..<position]
                position += 1
                guard let decoded = JSON5Lexicon.decodeString(content) else { throw PreviewFailure.malformedDocument }
                return decoded
            }
            if byte == 10 || byte == 13 { throw PreviewFailure.malformedDocument }
            position += 1
            if byte == 92 {
                guard let escaped = current else { throw PreviewFailure.malformedDocument }
                // An escaped CRLF is one continuation; skip both so the CR is not seen as a raw break.
                position += 1
                if escaped == 13, current == 10 { position += 1 }
            }
        }
        throw PreviewFailure.malformedDocument
    }

    /// Numbers (`-1`, `.5`, `0xFF`, `+Infinity`) and literals (`true`, `null`, `NaN`).
    private mutating func bareValue() throws {
        let start = position
        while let byte = current, !isTokenDelimiter(byte) {
            try progress()
            position += 1
        }
        guard position > start else { throw PreviewFailure.malformedDocument }
        let token = bytes[start..<position]
        if JSON5Lexicon.literals.contains(String(decoding: token, as: UTF8.self)) { return }
        guard JSON5Lexicon.isNumber(token) else { throw PreviewFailure.malformedDocument }
    }

    // MARK: Trivia and tokens

    /// Whitespace plus `//` and `/* */` comments. A comment whose text assigns a secret is concealed.
    private mutating func skipTrivia() throws {
        while let byte = current {
            try progress()
            if JSON5Lexicon.isWhitespace(byte) { position += 1; continue }
            // U+00A0, U+2028, U+2029 and the byte order mark are JSON5 whitespace too.
            if let width = unicodeSpaceWidth() { position += width; continue }
            guard byte == 47, position + 1 < bytes.count else { return }
            if bytes[position + 1] == 47 {
                position += 2
                let contentStart = position
                while let next = current, next != 10, next != 13 {
                    try progress()
                    position += 1
                }
                try annotateComment(contentStart..<position)
            } else if bytes[position + 1] == 42 {
                position += 2
                let contentStart = position
                var closed = false
                while position + 1 < bytes.count {
                    try progress()
                    if bytes[position] == 42, bytes[position + 1] == 47 { closed = true; break }
                    position += 1
                }
                guard closed else { throw PreviewFailure.malformedDocument }
                try annotateComment(contentStart..<position)
                position += 2
            } else {
                return
            }
        }
    }

    private func unicodeSpaceWidth() -> Int? {
        guard position + 1 < bytes.count else { return nil }
        if bytes[position] == 0xC2, bytes[position + 1] == 0xA0 { return 2 }
        guard position + 2 < bytes.count else { return nil }
        if bytes[position] == 0xEF, bytes[position + 1] == 0xBB, bytes[position + 2] == 0xBF { return 3 }
        if bytes[position] == 0xE2, bytes[position + 1] == 0x80, bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9 { return 3 }
        return nil
    }

    private mutating func annotateComment(_ content: Range<Int>) throws {
        if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: content, context: context) {
            guard sensitiveRanges.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            sensitiveRanges.append(range)
        }
    }

    private func isTokenDelimiter(_ byte: UInt8) -> Bool {
        JSON5Lexicon.isWhitespace(byte) || [44, 93, 125, 58, 47, 123, 91, 34, 39].contains(byte)
    }

    private mutating func progress() throws {
        if position - checkpointPosition >= 512 {
            try context.checkpoint()
            checkpointPosition = position
        }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        position += 1
        return true
    }

    private var current: UInt8? { position < bytes.count ? bytes[position] : nil }
}
