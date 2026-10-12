import Foundation
import PreviewContracts

/// All source adapters retain the original decoded characters. Syntax is only a rendering hint.
///
/// The language hint comes from the request's name hint (see `SourceLanguageDetector`) and never from
/// the content; it selects lexical decoration in the renderer and extra concealment here, nothing else.
/// A source file larger than the input budget is shown as its leading complete lines (see
/// `TextInputPolicyProviding`); the presentation then reports the full size.
public struct SourceCodeAdapter: FormatAdapter, TextInputPolicyProviding {
    public init() {}
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.line) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let language = SourceLanguageDetector.language(for: context.nameHint)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: try SourceCodePrivacyRanges.ranges(in: input.text, language: language, context: context),
                                  syntax: .sourceCode, sourceLanguage: language)
    }
}

/// Source concealment: the shared configuration/assignment pass plus the secrets that are not
/// assignments (command-line flags in shell-like files, Dockerfile `ENV` lines). Escaped literals
/// use the shared value classifier. Source-visible URL credentials retain precise concealment in
/// the shared privacy stage, so their scheme and host remain readable.
enum SourceCodePrivacyRanges {
    static func ranges(in text: String, language: SourceLanguageID?, context: RequestContext) throws -> [SensitiveRange] {
        var ranges = try ConfigurationPrivacyRanges.ranges(in: text, syntax: .sourceCode, context: context)
        let bytes = Array(text.utf8)
        ranges += try decodedLiteralRanges(in: bytes, language: language, context: context)
        ranges += try callStyleRanges(in: bytes, hashComments: supportsHashComments(language), context: context)
        if usesCommandLines(language) {
            ranges += try EmbeddedSecretRanges.commandLineFlags(in: bytes, context: context)
        }
        if language == .dockerfile {
            ranges += try EmbeddedSecretRanges.dockerEnvironment(in: bytes, context: context)
        }
        return SecretRangeBudget.capped(ranges, byteCount: bytes.count, context: context)
    }

    /// Inspect common escaped quoted/text-block literals without evaluating source. Comment
    /// quotes cannot steal a later string's delimiter. Python raw literals retain literal escapes;
    /// dynamic names/interpolation and language-specific escape grammars are not executed.
    private static func decodedLiteralRanges(in bytes: [UInt8], language: SourceLanguageID?,
                                             context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var index = 0
        var checkpointAt = 0
        let hashComments = supportsHashComments(language)
        while index < bytes.count {
            if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
            if (hashComments && bytes[index] == 35) || (bytes[index] == 47 && index + 1 < bytes.count && [42, 47].contains(bytes[index + 1])) {
                try skipTrivia(in: bytes, index: &index, hashComments: hashComments, context: context)
                continue
            }
            guard [34, 39, 96].contains(bytes[index]) else { index += 1; continue }
            let start = index
            // A missing closing quote may be a malformed file or a bounded leading prefix. Only
            // successfully decoded content is recognized; no invalid escape is guessed or dropped.
            // A recognizable credential conceals the complete uncertain original span through EOF.
            guard let literal = try quotedLiteral(in: bytes, index: &index, context: context),
                  bytes[literal.content].contains(92), !isPythonRawLiteral(in: bytes, before: start, language: language),
                  let decoded = JSON5Lexicon.decodeString(bytes[literal.content]) else { continue }
            try context.checkpoint()
            if try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded,
                originalText: String(decoding: bytes[literal.range], as: UTF8.self), context: context) {
                guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                ranges.append(.init(utf8Range: literal.range))
            }
        }
        return ranges
    }

    private static func isPythonRawLiteral(in bytes: [UInt8], before quote: Int,
                                          language: SourceLanguageID?) -> Bool {
        guard language == .python else { return false }
        var start = quote
        while start > 0, quote - start < 3, identifier(bytes[start - 1]) { start -= 1 }
        let prefix = String(decoding: bytes[start..<quote], as: UTF8.self).lowercased()
        return ["r", "br", "rb", "fr", "rf"].contains(prefix)
    }

    /// Literal definitions are inspected, never executed. The first quoted argument names a
    /// field; the second argument (or indexed environment assignment) owns its original byte span.
    private static func callStyleRanges(in bytes: [UInt8], hashComments: Bool, context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            guard identifier(bytes[index]) else { index += 1; continue }
            let start = index
            while index < bytes.count, identifier(bytes[index]) {
                if index.isMultiple(of: 512) { try context.checkpoint() }
                index += 1
            }
            guard index - start <= 80 else { continue }
            let word = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
            let method = word.split(separator: ".").last.map(String.init)
            let environment = word == "os.environ"
            guard environment || method == "define" || method == "setproperty" else { continue }
            var cursor = index
            try skipTrivia(in: bytes, index: &cursor, hashComments: hashComments, context: context)
            guard cursor < bytes.count, bytes[cursor] == (environment ? 91 : 40) else { continue }
            cursor += 1
            try skipTrivia(in: bytes, index: &cursor, hashComments: hashComments, context: context)
            guard let name = try quotedLiteral(in: bytes, index: &cursor, context: context),
                  name.closed else { index = max(index, cursor); continue }
            let decodedName = JSON5Lexicon.decodeString(bytes[name.content])
            index = max(index, cursor)
            guard decodedName.map(SecretFieldPolicy.isSensitive) ?? true else { continue }
            try skipTrivia(in: bytes, index: &cursor, hashComments: hashComments, context: context)
            guard cursor < bytes.count, bytes[cursor] == (environment ? 93 : 44) else { continue }
            cursor += 1
            if environment {
                try skipTrivia(in: bytes, index: &cursor, hashComments: hashComments, context: context)
                guard cursor < bytes.count, bytes[cursor] == 61 else { continue }
                cursor += 1
            }
            try skipTrivia(in: bytes, index: &cursor, hashComments: hashComments, context: context)
            let value = try expressionRange(in: bytes, index: &cursor, environment: environment, hashComments: hashComments, context: context)
            if !value.isEmpty {
                guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                ranges.append(.init(utf8Range: value))
            }
            index = max(index, cursor)
        }
        return ranges
    }

    /// Conceal the complete inert expression owned by a sensitive literal name, not only its
    /// first quoted fragment. Matching delimiters and comments are lexical boundaries only;
    /// this does not evaluate calls, interpolation, variables or concatenation.
    private static func expressionRange(in bytes: [UInt8], index: inout Int, environment: Bool,
                                        hashComments: Bool, context: RequestContext) throws -> Range<Int> {
        let start = index
        var closing: [UInt8] = []
        var checkpointAt = index
        while index < bytes.count {
            if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
            let byte = bytes[index]
            if [34, 39, 96].contains(byte) {
                _ = try quotedLiteral(in: bytes, index: &index, context: context)
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                index += 2
                while index < bytes.count {
                    if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
                    if bytes[index] == 42, index + 1 < bytes.count, bytes[index + 1] == 47 { index += 2; break }
                    index += 1
                }
                continue
            }
            if (hashComments && byte == 35) || (byte == 47 && index + 1 < bytes.count && bytes[index + 1] == 47) {
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                    if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
                    index += 1
                }
                continue
            }
            if [40, 91, 123].contains(byte) {
                guard closing.count < context.budget.maxJSONDepth else { index = bytes.count; return start..<index }
                closing.append(byte == 40 ? 41 : byte == 91 ? 93 : 125)
            } else if [41, 93, 125].contains(byte) {
                if closing.isEmpty, !environment, byte == 41 { return start..<index }
                // An uncertain/malformed expression must not expose its continuation.
                guard closing.last == byte else { index = bytes.count; return start..<index }
                closing.removeLast()
            } else if closing.isEmpty {
                if !environment, byte == 44 { return start..<index }
                if environment, byte == 59 { return start..<index }
                if environment, byte == 10 || byte == 13 {
                    if index == start || bytes[index - 1] != 92 { return start..<index }
                }
            }
            index += 1
        }
        return start..<index
    }

    private struct QuotedLiteral {
        let range: Range<Int>
        let content: Range<Int>
        let closed: Bool
    }

    private static func quotedLiteral(in bytes: [UInt8], index: inout Int, context: RequestContext) throws -> QuotedLiteral? {
        guard index < bytes.count, [34, 39, 96].contains(bytes[index]) else { return nil }
        let start = index
        let quote = bytes[index]
        let width = quote != 96 && index + 2 < bytes.count && bytes[index + 1] == quote && bytes[index + 2] == quote ? 3 : 1
        index += width
        let contentStart = index
        var checkpointAt = index
        while index < bytes.count {
            if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
            if bytes[index] == 92 { index = min(bytes.count, index + 2); continue }
            if bytes[index] == quote, index + width <= bytes.count,
               bytes[index..<(index + width)].allSatisfy({ $0 == quote }) {
                let contentEnd = index
                index += width
                return QuotedLiteral(range: start..<index, content: contentStart..<contentEnd, closed: true)
            }
            index += 1
        }
        // An unterminated sensitive value cannot safely expose continuation lines. Triple-quoted
        // Python/Java literals must find the complete delimiter, never an empty two-quote value.
        return QuotedLiteral(range: start..<index, content: contentStart..<index, closed: false)
    }

    /// Comments between literal call arguments are inert trivia, not expression boundaries.
    private static func skipTrivia(in bytes: [UInt8], index: inout Int, hashComments: Bool, context: RequestContext) throws {
        var checkpointAt = index
        while index < bytes.count {
            if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
            if [9, 10, 13, 32].contains(bytes[index]) { index += 1; continue }
            if (hashComments && bytes[index] == 35) || (bytes[index] == 47 && index + 1 < bytes.count && bytes[index + 1] == 47) {
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                    if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
                    index += 1
                }
                continue
            }
            if bytes[index] == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                index += 2
                while index < bytes.count {
                    if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
                    if bytes[index] == 42, index + 1 < bytes.count, bytes[index + 1] == 47 { index += 2; break }
                    index += 1
                }
                continue
            }
            return
        }
    }

    /// Language hints only establish lexical comment boundaries; they never execute source.
    /// In particular JavaScript/TypeScript private fields use # as syntax, not a line comment.
    private static func supportsHashComments(_ language: SourceLanguageID?) -> Bool {
        guard let language else { return false }
        return [.python, .ruby, .php, .perl, .r, .julia, .coffeeScript, .awk, .shell, .fish,
                .powerShell, .nushell, .elixir, .crystal, .nim, .hcl, .nix, .starlark,
                .cmake, .meson, .makefile, .dockerfile, .just, .ignoreList, .graphQL].contains(language)
    }

    private static func identifier(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 || byte == 46
    }

    /// Languages whose files routinely hold command lines with credential flags; unknown names are
    /// included because the check only ever adds concealment.
    private static func usesCommandLines(_ language: SourceLanguageID?) -> Bool {
        guard let language else { return true }
        return [.shell, .fish, .batch, .powerShell, .nushell, .dockerfile, .makefile, .just].contains(language)
    }
}
