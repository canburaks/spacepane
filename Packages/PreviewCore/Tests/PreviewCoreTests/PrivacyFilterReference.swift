import Foundation
import PreviewContracts

// ---------------------------------------------------------------------------------------------
// Independent pre-optimization privacy algorithm (one NSString-bridged String, a regular
// expression pass per pattern, a clock read on every progress event). It is the oracle that the
// optimized production filter must match for every input, including Unicode and malformed ranges.
// Explicit policy amendments: Q-01 adds URL credentials; Q-16 adds provider/private-key grammars
// and credential-shaped free-prose authorization. Regex passes and validators below are maintained
// independently; this oracle never calls the production value matcher or reads its pattern table.
// ---------------------------------------------------------------------------------------------
struct ReferencePrivacyFilter {
    func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText {
        try context.checkpoint()
        let source = document.text
        let nsSource = source as NSString
        guard document.sensitiveRanges.count <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        // Convert all required UTF-8 offsets to UTF-16 in one scalar pass; repeated
        // String.Index walks would make documents with many sensitive fields quadratic.
        let requestedOffsets = Set(document.sensitiveRanges.flatMap { [$0.utf8Range.lowerBound, $0.utf8Range.upperBound] })
        var offsets: [Int: Int] = [:]
        var utf8Offset = 0
        var utf16Offset = 0
        for (index, scalar) in source.unicodeScalars.enumerated() {
            if index.isMultiple(of: 1024) { try context.checkpoint() }
            if requestedOffsets.contains(utf8Offset) { offsets[utf8Offset] = utf16Offset }
            utf8Offset += scalar.utf8.count
            utf16Offset += scalar.value > 0xFFFF ? 2 : 1
        }
        if requestedOffsets.contains(utf8Offset) { offsets[utf8Offset] = utf16Offset }
        var ranges: [NSRange] = try document.sensitiveRanges.map { span in
            try context.checkpoint()
            guard let start = offsets[span.utf8Range.lowerBound], let end = offsets[span.utf8Range.upperBound], end >= start else {
                throw PreviewFailure.malformedDocument
            }
            return NSRange(location: start, length: end - start)
        }
        if !document.usesStructuredPrivacy {
            // Redact the rest of a secret assignment's line, including malformed/unterminated quotes.
            // Identifier boundary prevents repeated greedy retries along one long token.
            let keys = try NSRegularExpression(pattern: #"(?i)(?<![a-z0-9_.\p{Cf}\x{034F}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}-])[\"']?([a-z_\p{Cf}\x{034F}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}][a-z0-9_.\p{Cf}\x{034F}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}-]*)[\"']?[\t ]*[:=]"#)
            try enumerateMatches(keys, in: source, context: context) { match in
                if SecretFieldPolicy.isSensitive(nsSource.substring(with: match.range(at: 1))) {
                    let start = NSMaxRange(match.range)
                    let remaining = NSRange(location: start, length: nsSource.length - start)
                    let newline = nsSource.rangeOfCharacter(from: .newlines, options: [], range: remaining)
                    let lineEnd = newline.location == NSNotFound ? nsSource.length : newline.location
                    let lineValue = nsSource.substring(with: NSRange(location: start, length: lineEnd - start))
                    // Plain text has no grammar for multiline values. Conceal the remainder
                    // when a value is ambiguous rather than exposing continuation lines.
                    let end = mayContinueBeyondLine(lineValue, hasFollowingLine: lineEnd < nsSource.length)
                        ? nsSource.length : lineEnd
                    if end > start { ranges.append(NSRange(location: start, length: end - start)) }
                }
            }
        }
        // Recognizable credential values also remain concealed when the surrounding key is innocuous.
        let valuePatterns = [
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\z)"#,
            #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
            #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#,
            #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"(?<![A-Za-z0-9_])(?:[rs]k_(?:live|test)_|sk_org_)[A-Za-z0-9_]{16,}"#,
            #"(?<![A-Za-z0-9_])(?:xoxe\.)?(?:xox[abposr]-|xapp-)[A-Za-z0-9-]{16,}"#,
            #"(?<![A-Za-z0-9_])AIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])"#,
            #"(?<![A-Za-z0-9_])glpat-[A-Za-z0-9_-]{16,}"#,
            #"(?<![A-Za-z0-9_])npm_[A-Za-z0-9]{36}(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9_])pypi-AgE[A-Za-z0-9_-]{20,}"#,
            #"(?<![A-Za-z0-9_])SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])"#,
            #"-----BEGIN PGP PRIVATE KEY BLOCK-----[\s\S]*?(?:-----END PGP PRIVATE KEY BLOCK-----|\z)"#,
            #"(?m)^PuTTY-User-Key-File-[23]:[^\r\n]*[\s\S]*?(?:^Private-MAC:[^\r\n]*|\z)"#
        ]
        for pattern in valuePatterns {
            try context.checkpoint()
            let regex = try NSRegularExpression(pattern: pattern)
            try enumerateMatches(regex, in: source, context: context) { ranges.append($0.range) }
        }
        // The user information of `scheme://user:password@host`. Only group 1 is concealed, so it is its own pass.
        let urlCredentials = try NSRegularExpression(
            pattern: #"(?<=[A-Za-z0-9+.-])://([^ \t\n\r/?#"'<>)\]},;@:]*:[^ \t\n\r/?#"'<>)\]},;]*)@"#)
        try enumerateMatches(urlCredentials, in: source, context: context) { ranges.append($0.range(at: 1)) }
        // Case-insensitive authorization needs shape checks. Validate only bounded data and use
        // separate slow passes, without the production filter's literal gates or validation helpers.
        let basic = try NSRegularExpression(pattern: #"(?i)\bbasic[\t ]+([A-Za-z0-9+/=]{8,})"#)
        try enumerateMatches(basic, in: source, context: context) { match in
            let token = match.range(at: 1)
            if token.length > 4_096 { ranges.append(match.range); return }
            guard let decoded = Data(base64Encoded: nsSource.substring(with: token)) else { return }
            var colon = false
            for byte in decoded {
                if byte < 32 || byte == 127 { return }
                if byte == 58 { colon = true }
            }
            if colon { ranges.append(match.range) }
        }
        let bearer = try NSRegularExpression(pattern: #"(?i)\bbearer[\t ]+([A-Za-z0-9_+/=.-]{8,})"#)
        let nonLetters = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "_+/=.-"))
        try enumerateMatches(bearer, in: source, context: context) { match in
            let token = match.range(at: 1)
            if token.length >= 16 || nsSource.rangeOfCharacter(from: nonLetters, options: [], range: token).location != NSNotFound {
                ranges.append(match.range)
            }
        }
        let encoded = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9+/])LS0tLS1CRUdJTi[A-Za-z0-9+/=]{20,}"#)
        try enumerateMatches(encoded, in: source, context: context) { match in
            let count = min(match.range.length, 256) / 4 * 4
            let encodedHeader = nsSource.substring(with: NSRange(location: match.range.location, length: count))
            guard let bytes = Data(base64Encoded: encodedHeader), let decoded = String(data: bytes, encoding: .utf8) else { return }
            let header = decoded.components(separatedBy: .newlines)[0]
            if header.starts(with: "-----BEGIN ") && header.range(of: "PRIVATE KEY") != nil && header.hasSuffix("-----") {
                ranges.append(match.range)
            }
        }
        let azure = try NSRegularExpression(pattern: #"(?i)\b(?:AccountKey|SharedAccessKey|SharedAccessSignature)[\t ]*=[\t ]*([^;\s\"'<>()\[\]{},]+)"#)
        try enumerateMatches(azure, in: source, context: context) { ranges.append($0.range(at: 1)) }
        // Merge overlaps before replacing, keeping no raw alternate representation.
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in sorted {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        let result = NSMutableString(string: source)
        for range in merged.reversed() { result.replaceCharacters(in: range, with: "••••") }
        let safe = result as String
        guard safe.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        try context.checkpoint()
        return SafeText(text: safe, redactionCount: merged.count, syntax: document.syntax)
    }

    private func enumerateMatches(_ regex: NSRegularExpression, in source: String, context: RequestContext,
                                  body: (NSTextCheckingResult) -> Void) throws {
        var failure: (any Error)?
        regex.enumerateMatches(in: source, options: [.reportProgress], range: NSRange(source.startIndex..., in: source)) { match, _, stop in
            do { try context.checkpoint() }
            catch { failure = error; stop.pointee = true; return }
            if let match { body(match) }
        }
        if let failure { throw failure }
    }

    private func mayContinueBeyondLine(_ value: String, hasFollowingLine: Bool) -> Bool {
        guard hasFollowingLine else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return true }
        if first == "{" || first == "[" || trimmed.hasSuffix("\\") { return true }
        guard first == "\"" || first == "'" else { return false }
        if trimmed.hasPrefix(String(repeating: String(first), count: 3)) { return true }
        var escaped = false
        for character in trimmed.dropFirst() {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == first { return false }
        }
        return true
    }
}
