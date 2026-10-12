import Foundation
import PreviewContracts

/// INI-family configuration: `.ini`, `.cfg`, `.conf`, `.properties`, `.xcconfig` and well-known
/// dotfiles such as `.gitconfig`, `.editorconfig`, `.npmrc` and `.pypirc`.
///
/// The dialects share one lenient reading: `[section]` headers, `key = value` or `key: value`
/// assignments (the first delimiter wins, except that a URL-like key such as the `.npmrc` line
/// `//registry.example/:_authToken=...` is split at its `=`), `;`, `#` and `!` comments, indented or
/// backslash continuation lines, and whitespace-separated `directive value` lines. Nothing is
/// interpreted, expanded or included: values are inert characters. Unlike strict formats this adapter
/// accepts any text, because `.conf` and `.cfg` files hold many unrelated grammars (nginx blocks, tmux
/// commands); the renderer derives an outline only when every line fits the INI shape and otherwise
/// shows the concealed source with its structure notice.
///
/// Privacy is structural (`usesStructuredPrivacy == true`): the shared plain-text heuristic treats an
/// assignment with no value (`password =`, a common placeholder) as the start of a multi-line value and
/// would conceal the rest of the file, so `INIPrivacyRanges` applies the same key rules per line instead.
/// For every line it conceals the value of a secret key (decided from the text before the first
/// delimiter, so `//registry.example/:_authToken=...` and `_auth` work), any `key:`/`key=` assignment
/// later on the line, whitespace `directive value` lines such as `requirepass`, and the indented or
/// backslash continuation lines of a secret value. Credentials embedded in URLs and recognisable token
/// values (bearer tokens, JWTs, provider keys, private keys) are concealed by the shared privacy stage
/// in every document.
public struct INIConfigurationAdapter: FormatAdapter, TextInputPolicyProviding {
    public init() {}
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.line) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let bytes = Array(input.text.utf8)
        let ranges = try INIPrivacyRanges.ranges(in: bytes, context: context)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: SecretRangeBudget.capped(ranges, byteCount: bytes.count, context: context),
                                  usesStructuredPrivacy: true, syntax: .ini)
    }
}

/// Line-based concealment for INI-family files. Delimiters and comment markers are ASCII, so every
/// range starts and ends on a UTF-8 scalar boundary.
enum INIPrivacyRanges {
    /// Last key segments that name a credential although `SecretFieldPolicy` does not: npm's `_auth`,
    /// redis' `requirepass` and `masterauth`, passphrases and cookies. Whole-segment equality keeps
    /// `bypass`, `compass` and nginx `proxy_pass` readable.
    private static let additionalSecretSegments: Set<String> = [
        "auth", "passphrase", "requirepass", "masterauth", "cookie", "sessionid"
    ]

    static func ranges(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var lineStart = 0
        // The previous line held a sensitive value, so indented or backslash-continued lines belong to it.
        var continuesSensitiveValue = false
        var previousEndedWithBackslash = false
        while lineStart < bytes.count {
            try context.checkpoint()
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 {
                if (lineEnd - lineStart).isMultiple(of: 512) { try context.checkpoint() }
                lineEnd += 1
            }
            var content = lineStart
            while content < lineEnd, bytes[content] == 32 || bytes[content] == 9 { content += 1 }
            let isBlank = content == lineEnd
            let isIndented = content > lineStart
            let endsWithBackslash = !isBlank && bytes[lineEnd - 1] == 92

            if continuesSensitiveValue, !isBlank, isIndented || previousEndedWithBackslash {
                ranges.append(SensitiveRange(utf8Range: content..<lineEnd))
                previousEndedWithBackslash = endsWithBackslash
            } else {
                continuesSensitiveValue = false
                previousEndedWithBackslash = false
                if !isBlank {
                    // INI-aware key rules first, then any assignment later on the line (also in comments).
                    var start = try sensitiveValueStart(in: bytes, line: content..<lineEnd, context: context)
                    if let generic = try EmbeddedSecretRanges.firstSecretAssignment(in: bytes, line: content..<lineEnd, context: context) {
                        start = min(start ?? generic.utf8Range.lowerBound, generic.utf8Range.lowerBound)
                    }
                    if let start {
                        if start < lineEnd { ranges.append(SensitiveRange(utf8Range: start..<lineEnd)) }
                        continuesSensitiveValue = true
                        previousEndedWithBackslash = endsWithBackslash
                    }
                }
            }
            // CRLF: the following LF starts an empty "line" that must not end a continuation.
            var next = lineEnd
            if next < bytes.count { next += (bytes[next] == 13 && next + 1 < bytes.count && bytes[next + 1] == 10) ? 2 : 1 }
            lineStart = next
            if isBlank { continuesSensitiveValue = false }
        }
        return ranges
    }

    /// Offset where a sensitive value begins when `line` assigns a credential, otherwise `nil`.
    private static func sensitiveValueStart(in bytes: [UInt8], line: Range<Int>, context: RequestContext) throws -> Int? {
        let first = bytes[line.lowerBound]
        // Comment lines and section headers carry no assignment; the shared heuristic still scans them.
        if first == 59 || first == 35 || first == 33 || first == 91 { return nil }
        var equals: Int?
        var colon: Int?
        var firstSpace: Int?
        var index = line.lowerBound
        while index < line.upperBound {
            if (index - line.lowerBound).isMultiple(of: 512) { try context.checkpoint() }
            let byte = bytes[index]
            if byte == 61, equals == nil { equals = index }
            else if byte == 58, colon == nil { colon = index }
            else if (byte == 32 || byte == 9), firstSpace == nil { firstSpace = index }
            index += 1
            if equals != nil, colon != nil { break }
        }
        // nginx's ordinary routing directive can hold URI colons and query assignments. Those
        // bytes belong to its value, not a longer key such as "proxy_pass http". An exact directive
        // (or assignment with that key) follows the shared ordinary-field policy; the separate
        // later-assignment and recognizable-value passes still conceal real credentials in it.
        let firstTokenEnd = [firstSpace, equals, colon].compactMap { $0 }.min() ?? line.upperBound
        if bytes[line.lowerBound..<firstTokenEnd].elementsEqual("proxy_pass".utf8),
           !SecretFieldPolicy.isSensitive("proxy_pass") { return nil }
        var starts: [Int] = []
        if let equals, isSecretKey(bytes[line.lowerBound..<equals]) { starts.append(equals + 1) }
        if let colon, isSecretKey(bytes[line.lowerBound..<colon]) { starts.append(colon + 1) }
        if equals == nil, colon == nil, let firstSpace, isSecretKey(bytes[line.lowerBound..<firstSpace]) {
            starts.append(firstSpace)
        }
        return starts.min()
    }

    private static func isSecretKey(_ key: ArraySlice<UInt8>) -> Bool {
        let text = String(decoding: key, as: UTF8.self)
        if SecretFieldPolicy.isSensitive(text) { return true }
        let lastSegment = text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).last.map { $0.lowercased() }
        return lastSegment.map(additionalSecretSegments.contains) ?? false
    }
}
