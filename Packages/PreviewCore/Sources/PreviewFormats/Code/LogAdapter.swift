import Foundation
import PreviewContracts

/// Plain-text logs. The text is shown exactly as decoded; timestamps, severities and stack frames are
/// only decoration applied to the concealed text by the renderer. A log larger than the input budget
/// shows its leading complete lines (see `TextInputPolicyProviding`).
///
/// Logs get their own concealment instead of the shared assignment heuristic because that heuristic
/// treats an assignment with no value (`Enter password:`) as the start of a multi-line value and
/// conceals the rest of the file, and it hides the line number of every stack frame whose file name
/// contains a secret word (`at PasswordMatcher.verify(PasswordMatcher.java:73)`). The log pass keeps
/// the same key rules (`SecretFieldPolicy`) but ends a value at the end of its line, except for a value
/// that opens an unbalanced bracket. It also conceals secret command-line flags and cookie headers.
/// Credentials in URLs and recognisable token values (bearer tokens, JWTs, provider keys, private keys)
/// are concealed by the shared privacy stage in every document.
public struct LogAdapter: FormatAdapter, TextInputPolicyProviding {
    public init() {}
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.line) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let bytes = Array(input.text.utf8)
        var ranges = try LogPrivacyRanges.ranges(in: bytes, context: context)
        ranges += try EmbeddedSecretRanges.commandLineFlags(in: bytes, context: context)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: SecretRangeBudget.capped(ranges, byteCount: bytes.count, context: context),
                                  usesStructuredPrivacy: true, syntax: .log)
    }
}

/// Line-based concealment for log text. Every delimiter is ASCII, so ranges start and end on UTF-8
/// scalar boundaries.
enum LogPrivacyRanges {
    /// Bound on the lines an unbalanced `{` or `[` value may swallow before everything after it is concealed.
    private static let maximumContinuationLines = 2_000

    static func ranges(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var lineStart = 0
        while lineStart < bytes.count {
            try context.checkpoint()
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 {
                if (lineEnd - lineStart).isMultiple(of: 512) { try context.checkpoint() }
                lineEnd += 1
            }
            var next = lineEnd
            if next < bytes.count { next += (bytes[next] == 13 && next + 1 < bytes.count && bytes[next + 1] == 10) ? 2 : 1 }
            if !isInertFrame(bytes, lineStart..<lineEnd),
               let range = try EmbeddedSecretRanges.firstSecretAssignment(in: bytes, line: lineStart..<lineEnd, context: context) {
                ranges.append(range)
                // A value that opens a bracket it does not close continues onto the following lines.
                if let depth = unclosedDepth(bytes, range.utf8Range), depth > 0 {
                    next = try conceal(bytes, from: next, depth: depth, ranges: &ranges, context: context)
                }
            }
            lineStart = next
        }
        for range in try cookieValues(in: bytes, context: context) { ranges.append(range) }
        return ranges
    }

    /// Net depth of `{`/`[` against `}`/`]` inside a concealed value, ignoring quoting.
    private static func unclosedDepth(_ bytes: [UInt8], _ range: Range<Int>) -> Int? {
        var depth = 0
        var seenOpen = false
        for byte in bytes[range] {
            switch byte {
            case 123, 91: depth += 1; seenOpen = true
            case 125, 93: depth -= 1
            default: break
            }
        }
        guard seenOpen else { return nil }
        // Only a value that starts with the bracket continues; text such as `x [y` does not.
        var first = range.lowerBound
        while first < range.upperBound, bytes[first] == 32 || bytes[first] == 9 || bytes[first] == 34 || bytes[first] == 39 { first += 1 }
        guard first < range.upperBound, bytes[first] == 123 || bytes[first] == 91 else { return nil }
        return depth
    }

    /// Conceals following lines until the bracket depth returns to zero, and returns where scanning resumes.
    private static func conceal(_ bytes: [UInt8], from start: Int, depth initial: Int, ranges: inout [SensitiveRange],
                                context: RequestContext) throws -> Int {
        var depth = initial
        var lineStart = start
        var lines = 0
        while lineStart < bytes.count, depth > 0 {
            try context.checkpoint()
            if lines >= maximumContinuationLines {
                ranges.append(SensitiveRange(utf8Range: lineStart..<bytes.count))
                return bytes.count
            }
            lines += 1
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 {
                if (lineEnd - lineStart).isMultiple(of: 512) { try context.checkpoint() }
                switch bytes[lineEnd] {
                case 123, 91: depth += 1
                case 125, 93: depth -= 1
                default: break
                }
                lineEnd += 1
            }
            var content = lineStart
            while content < lineEnd, bytes[content] == 32 || bytes[content] == 9 { content += 1 }
            if content < lineEnd { ranges.append(SensitiveRange(utf8Range: content..<lineEnd)) }
            lineStart = lineEnd
            if lineStart < bytes.count { lineStart += (bytes[lineStart] == 13 && lineStart + 1 < bytes.count && bytes[lineStart + 1] == 10) ? 2 : 1 }
        }
        return lineStart
    }

    /// `Cookie:` and `Set-Cookie:` header values anywhere on a line, to the end of that line.
    private static func cookieValues(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        let needle = Array("cookie:".utf8)
        var index = 0
        while index + needle.count <= bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            guard lowered(bytes[index]) == needle[0] else { index += 1; continue }
            var matches = true
            for offset in 1..<needle.count where lowered(bytes[index + offset]) != needle[offset] { matches = false; break }
            guard matches, index == 0 || !isKeyCharacter(bytes[index - 1]) || bytes[index - 1] == 45 else { index += 1; continue }
            var lineEnd = index + needle.count
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 { lineEnd += 1 }
            if lineEnd > index + needle.count { ranges.append(SensitiveRange(utf8Range: (index + needle.count)..<lineEnd)) }
            index = lineEnd
        }
        return ranges
    }

    /// A stack frame whose every `:` follows a source file name and precedes a line or column number,
    /// such as Java `at a.b.C.d(C.java:73)`, Node `at x (file.js:10:5)` or a Go `\t/path/file.go:12 +0x1d`
    /// line. These shapes cannot carry an assignment, so the key scan skips them instead of hiding
    /// their line numbers. A word with a `:` that does not follow a known source suffix is not a frame.
    static func isInertFrame(_ bytes: [UInt8], _ line: Range<Int>) -> Bool {
        var index = line.lowerBound
        while index < line.upperBound, bytes[index] == 32 || bytes[index] == 9 { index += 1 }
        guard index < line.upperBound else { return false }
        let words = bytes[index..<line.upperBound].split(separator: 32, omittingEmptySubsequences: true)
        guard words.count >= 2, words.count <= 5 else { return false }
        if words[words.startIndex].elementsEqual(Array("at".utf8)) {
            return words.dropFirst().allSatisfy { isFrameWord(Array($0)) }
        }
        // Go and similar: `/path/file.go:12 +0x1d`
        guard isFrameWord(Array(words[words.startIndex])), words[words.startIndex].contains(58) else { return false }
        return words.dropFirst().allSatisfy { word in
            word.first == 43 && word.dropFirst().allSatisfy { isHexDigit($0) || $0 == 120 }
        }
    }

    private static let sourceSuffixes: Set<String> = [
        "java", "kt", "kts", "scala", "groovy", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "swift",
        "m", "mm", "c", "cc", "cpp", "cxx", "h", "hpp", "cs", "php", "dart", "ex", "exs", "erl", "lua", "pl", "pm",
        "r", "jl", "hs", "ml", "fs", "vb", "sh", "zig", "nim"
    ]

    /// Qualified names and locations: no `=`, quotes or spaces; every `:` follows `.suffix` of a source
    /// file and is followed by a digit.
    private static func isFrameWord(_ word: [UInt8]) -> Bool {
        guard !word.isEmpty else { return false }
        for (offset, byte) in word.enumerated() {
            if byte == 58 {
                guard offset + 1 < word.count, (48...57).contains(word[offset + 1]) else { return false }
                // The column in `file.js:10:5` follows a `:line`; every other colon follows a source suffix.
                var digitsStart = offset
                while digitsStart > 0, (48...57).contains(word[digitsStart - 1]) { digitsStart -= 1 }
                if digitsStart < offset, digitsStart > 0, word[digitsStart - 1] == 58 { continue }
                var suffixStart = offset
                while suffixStart > 0, isKeyCharacter(word[suffixStart - 1]), word[suffixStart - 1] != 46 { suffixStart -= 1 }
                guard suffixStart > 0, word[suffixStart - 1] == 46,
                      sourceSuffixes.contains(String(decoding: word[suffixStart..<offset], as: UTF8.self)) else { return false }
                continue
            }
            let allowed = isKeyCharacter(byte) || [36, 60, 62, 47, 92, 40, 41, 64, 91, 93].contains(byte)
            guard allowed else { return false }
        }
        return true
    }

    private static func isKeyCharacter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 95 || byte == 46 || byte == 45
    }
    private static func isKeyStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }
    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }
    private static func lowered(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
}
