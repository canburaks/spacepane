import Foundation
import PreviewContracts

/// Secrets that the shared assignment heuristic cannot see because they are not `key = value`
/// pairs: command-line flags and Dockerfile `ENV KEY value` lines. Credentials embedded in URLs
/// (`scheme://user:password@host`) are not here: they occur in every text format, so the shared
/// privacy stage (`DefaultPrivacyFilter`) is their single owner.
/// Every scan is one linear pass over UTF-8 bytes (all delimiters are ASCII), checks the request
/// every few hundred bytes and returns ranges that begin and end on ASCII boundaries.
enum EmbeddedSecretRanges {
    /// `--password value`, `--token=value`, `-p`-style flags are not recognised unless their name
    /// is a secret field name. The value is the next word, or the quoted string, or the text after `=`.
    static func commandLineFlags(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            // A flag starts a word: line start, whitespace, or an opening quote.
            guard bytes[index] == 45, index == 0 || isWordBoundary(bytes[index - 1]) else { index += 1; continue }
            var nameStart = index
            while nameStart < bytes.count, bytes[nameStart] == 45 { nameStart += 1 }
            var nameEnd = nameStart
            while nameEnd < bytes.count, isFlagNameCharacter(bytes[nameEnd]) { nameEnd += 1 }
            guard nameEnd > nameStart, nameStart - index <= 2 else { index = max(nameEnd, index + 1); continue }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
            guard SecretFieldPolicy.isSensitive(name) else { index = nameEnd; continue }
            var valueStart = nameEnd
            if valueStart < bytes.count, bytes[valueStart] == 61 {
                valueStart += 1
            } else {
                while valueStart < bytes.count, bytes[valueStart] == 32 || bytes[valueStart] == 9 { valueStart += 1 }
                // The next word must be a value, not another flag or the end of the line.
                guard valueStart > nameEnd, valueStart < bytes.count, bytes[valueStart] != 45,
                      bytes[valueStart] != 10, bytes[valueStart] != 13 else { index = nameEnd; continue }
            }
            let valueEnd = wordEnd(bytes, from: valueStart)
            if valueEnd > valueStart { ranges.append(SensitiveRange(utf8Range: valueStart..<valueEnd)) }
            index = max(valueEnd, nameEnd)
        }
        return ranges
    }

    /// Dockerfile `ENV NAME value` and `ARG NAME value` without an `=`: the rest of the line is the value.
    static func dockerEnvironment(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var lineStart = 0
        while lineStart < bytes.count {
            try context.checkpoint()
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 {
                if (lineEnd - lineStart).isMultiple(of: 512) { try context.checkpoint() }
                lineEnd += 1
            }
            var index = lineStart
            while index < lineEnd, bytes[index] == 32 || bytes[index] == 9 { index += 1 }
            let keywordEnd = wordBoundary(bytes, from: index, limit: lineEnd)
            let keyword = String(decoding: bytes[index..<keywordEnd], as: UTF8.self).lowercased()
            if keyword == "env" || keyword == "arg" {
                var nameStart = keywordEnd
                while nameStart < lineEnd, bytes[nameStart] == 32 || bytes[nameStart] == 9 { nameStart += 1 }
                let nameEnd = wordBoundary(bytes, from: nameStart, limit: lineEnd)
                let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
                if !name.contains("="), SecretFieldPolicy.isSensitive(name), nameEnd < lineEnd {
                    // A trailing backslash continues the value onto the next line; keep that readable-safe.
                    var end = lineEnd
                    if bytes[end - 1] == 92 { end = bytes.count }
                    if end > nameEnd { ranges.append(SensitiveRange(utf8Range: nameEnd..<end)) }
                }
            }
            lineStart = lineEnd < bytes.count ? lineEnd + 1 : lineEnd
        }
        return ranges
    }

    /// The first `key:` / `key=` assignment on a line whose key is a secret name, as the range of its value:
    /// everything after the delimiter to the end of the line. Unlike the shared plain-text heuristic it never
    /// extends a value onto following lines, so an empty value (`Enter password:`) conceals nothing more.
    /// The first `key:` / `key=` assignment on the line whose key is a secret name, as the range of its
    /// value: everything after the delimiter to the end of the line.
    static func firstSecretAssignment(in bytes: [UInt8], line: Range<Int>, context: RequestContext) throws -> SensitiveRange? {
        var index = line.lowerBound
        while index < line.upperBound {
            if (index - line.lowerBound).isMultiple(of: 512) { try context.checkpoint() }
            let byte = bytes[index]
            guard byte == 58 || byte == 61 else { index += 1; continue }
            let delimiter = index
            index += 1
            // Walk back over blanks, one closing quote and the key's identifier characters.
            var end = delimiter
            while end > line.lowerBound, bytes[end - 1] == 32 || bytes[end - 1] == 9 { end -= 1 }
            if end > line.lowerBound, bytes[end - 1] == 34 || bytes[end - 1] == 39 { end -= 1 }
            var start = end
            while start > line.lowerBound, isKeyCharacter(bytes[start - 1]) { start -= 1 }
            guard start < end, isKeyStart(bytes[start]) else { continue }
            guard SecretFieldPolicy.isSensitive(String(decoding: bytes[start..<end], as: UTF8.self)) else { continue }
            return delimiter + 1 < line.upperBound ? SensitiveRange(utf8Range: (delimiter + 1)..<line.upperBound) : nil
        }
        return nil
    }

    // MARK: Helpers

    private static func isKeyCharacter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 95 || byte == 46 || byte == 45
    }

    private static func isKeyStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }

    private static func isWordBoundary(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 34 || byte == 39 || byte == 40 || byte == 91
    }

    private static func isFlagNameCharacter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }

    private static func wordBoundary(_ bytes: [UInt8], from start: Int, limit: Int) -> Int {
        var end = start
        while end < limit, bytes[end] != 32, bytes[end] != 9 { end += 1 }
        return end
    }

    /// The end of the word or quoted string starting at `start`; an unterminated quote runs to the end of its line.
    private static func wordEnd(_ bytes: [UInt8], from start: Int) -> Int {
        guard start < bytes.count else { return start }
        let first = bytes[start]
        if first == 34 || first == 39 {
            var end = start + 1
            while end < bytes.count, bytes[end] != first, bytes[end] != 10, bytes[end] != 13 {
                if bytes[end] == 92, first == 34, end + 1 < bytes.count, bytes[end + 1] != 10, bytes[end + 1] != 13 { end += 1 }
                end += 1
            }
            return end < bytes.count && bytes[end] == first ? end + 1 : end
        }
        var end = start
        while end < bytes.count, ![32, 9, 10, 13].contains(bytes[end]) { end += 1 }
        return end
    }
}

/// The adapters' shared way to add embedded-secret ranges to a document's own ranges.
enum SecretRangeBudget {
    /// Concealing the whole text is the safe answer when a document yields more ranges than the
    /// shared privacy stage will accept (`maxJSONNodes`), instead of failing the preview.
    static func capped(_ ranges: [SensitiveRange], byteCount: Int, context: RequestContext) -> [SensitiveRange] {
        ranges.count <= context.budget.maxJSONNodes ? ranges : [SensitiveRange(utf8Range: 0..<byteCount)]
    }
}
