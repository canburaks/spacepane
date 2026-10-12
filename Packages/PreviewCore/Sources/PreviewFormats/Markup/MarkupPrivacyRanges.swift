import Foundation
import PreviewContracts

/// Concealment planning for the markup-document family. The shared privacy stage already
/// conceals recognizable credential values and `key: value` / `key = value` assignments with
/// secret-like keys in every text. These planners add the syntax-specific forms it cannot see:
/// YAML/TOML front matter (including block scalars), LaTeX macro names, Org properties and
/// reStructuredText substitutions. Ranges are UTF-8 offsets into the decoded text and always
/// err toward concealing more.
enum MarkupPrivacyRanges {
    /// Front matter longer than this many lines is not recognized, matching the renderer.
    static let maximumFrontMatterLines = 200
    /// Brace groups are followed for at most this many bytes.
    static let maximumGroupBytes = 4_096

    // MARK: Markdown front matter

    /// Concealment ranges for a whole Markdown document. A leading front-matter block is planned
    /// on its own with the YAML or TOML rules plus the generic assignment rules, and the body is
    /// planned separately, so a multi-line secret in metadata (a block scalar or a triple-quoted
    /// string) hides only the metadata and never swallows the document after it.
    static func markdown(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        try context.checkpoint()
        let bytes = Array(source.utf8)
        guard let block = try frontMatterBlock(in: bytes, context: context) else {
            return try ConfigurationPrivacyRanges.ranges(in: source, syntax: .markdown, context: context)
        }
        let slice = String(decoding: bytes[block.contentStart..<block.contentEnd], as: UTF8.self)
        var ranges = try ConfigurationPrivacyRanges.ranges(in: slice, syntax: block.isTOML ? .toml : .yaml, context: context)
        ranges += try ConfigurationPrivacyRanges.ranges(in: slice, syntax: .markdown, context: context)
        ranges = ranges.map { shifted($0, by: block.contentStart) }
        let body = String(decoding: bytes[block.bodyStart...], as: UTF8.self)
        ranges += try ConfigurationPrivacyRanges.ranges(in: body, syntax: .markdown, context: context).map { shifted($0, by: block.bodyStart) }
        return ranges
    }

    private static func shifted(_ range: SensitiveRange, by offset: Int) -> SensitiveRange {
        SensitiveRange(utf8Range: (range.utf8Range.lowerBound + offset)..<(range.utf8Range.upperBound + offset))
    }

    private struct FrontMatterBlock {
        let isTOML: Bool
        /// First byte after the opening delimiter line.
        let contentStart: Int
        /// First byte of the closing delimiter line.
        let contentEnd: Int
        /// First byte after the closing delimiter line.
        let bodyStart: Int
    }

    /// A leading `---` (YAML) or `+++` (TOML) block with a closing delimiter within the line limit.
    private static func frontMatterBlock(in bytes: [UInt8], context: RequestContext) throws -> FrontMatterBlock? {
        let lines = try lineSpans(bytes, limit: maximumFrontMatterLines + 1, context: context)
        guard let first = lines.first else { return nil }
        let delimiter = trimmed(bytes, first)
        guard delimiter == "---" || delimiter == "+++" else { return nil }
        let isTOML = delimiter == "+++"
        for index in 1..<max(lines.count, 1) {
            let value = trimmed(bytes, lines[index])
            guard value == delimiter || (!isTOML && value == "...") else { continue }
            return FrontMatterBlock(isTOML: isTOML, contentStart: first.next, contentEnd: lines[index].start, bodyStart: lines[index].next)
        }
        return nil
    }

    // MARK: LaTeX

    /// Comments with secret-like assignments and the arguments of control sequences whose names
    /// look secret (`\password{…}`, `\def\token{…}`, `\newcommand{\apikey}{…}`).
    static func latex(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        let bytes = Array(source.utf8)
        var ranges: [SensitiveRange] = []
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            switch bytes[index] {
            case 0x5C: // backslash
                let nameStart = index + 1
                var nameEnd = nameStart
                while nameEnd < bytes.count, isASCIILetter(bytes[nameEnd]) { nameEnd += 1 }
                if nameEnd == nameStart { index = min(index + 2, bytes.count); continue }
                let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
                if SecretFieldPolicy.isSensitive(name) {
                    let end = endOfBalancedTail(bytes, from: nameEnd)
                    if end > nameEnd { ranges.append(SensitiveRange(utf8Range: nameEnd..<end)) }
                    index = max(end, nameEnd)
                } else { index = nameEnd }
            case 0x25: // percent: a comment to the end of the line
                let start = index + 1
                var end = start
                while end < bytes.count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
                if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: start..<end, context: context) {
                    ranges.append(range)
                }
                index = end
            default: index += 1
            }
        }
        return ranges
    }

    /// From `start`, the end of the line, extended through any braces still open there (bounded).
    private static func endOfBalancedTail(_ bytes: [UInt8], from start: Int) -> Int {
        var depth = 0
        var index = start
        let limit = min(bytes.count, start + maximumGroupBytes)
        while index < limit {
            let byte = bytes[index]
            if byte == 0x5C { index += 2; continue }
            if byte == 0x7B { depth += 1 }
            else if byte == 0x7D { depth = max(depth - 1, 0) }
            else if (byte == 10 || byte == 13) && depth == 0 { return index }
            index += 1
        }
        // A group left open to the bound hides the rest of the bounded window and nothing past it.
        return min(index, bytes.count)
    }

    // MARK: Org

    /// `#+PROPERTY: name value` lines whose property name looks secret, and comment lines.
    static func org(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        let bytes = Array(source.utf8)
        var ranges: [SensitiveRange] = []
        for span in try lineSpans(bytes, limit: Int.max, context: context) {
            try context.checkpoint()
            let line = String(decoding: bytes[span.start..<span.end], as: UTF8.self)
            let lowered = line.lowercased()
            if lowered.hasPrefix("#+property:") || lowered.hasPrefix("#+header:") || lowered.hasPrefix("#+header-args") {
                // The value after the first colon starts with the property name: `#+PROPERTY: name value`.
                guard let colon = line.utf8.firstIndex(of: 0x3A) else { continue }
                let valueStart = span.start + line.utf8.distance(from: line.utf8.startIndex, to: colon) + 1
                let value = String(decoding: bytes[valueStart..<span.end], as: UTF8.self)
                let words = value.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "\t" })
                if words.prefix(2).contains(where: { SecretFieldPolicy.isSensitive(String($0)) }) {
                    ranges.append(SensitiveRange(utf8Range: valueStart..<span.end))
                }
            } else if line.hasPrefix("# ") || line == "#" {
                if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: (span.start + 1)..<span.end, context: context) {
                    ranges.append(range)
                }
            }
        }
        return ranges
    }

    // MARK: reStructuredText and AsciiDoc

    /// Substitution definitions whose name looks secret, and explicit comments with secret-like assignments.
    static func restructuredText(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        let bytes = Array(source.utf8)
        var ranges: [SensitiveRange] = []
        for span in try lineSpans(bytes, limit: Int.max, context: context) {
            try context.checkpoint()
            let line = String(decoding: bytes[span.start..<span.end], as: UTF8.self)
            guard line.hasPrefix(".. ") else { continue }
            let rest = line.dropFirst(3)
            if rest.hasPrefix("|"), let close = rest.dropFirst().firstIndex(of: "|") {
                let name = String(rest[rest.index(after: rest.startIndex)..<close])
                if SecretFieldPolicy.isSensitive(name), let marker = line.range(of: "::") {
                    let offset = line.utf8.distance(from: line.startIndex, to: marker.upperBound)
                    ranges.append(SensitiveRange(utf8Range: (span.start + offset)..<span.end))
                }
            } else if !rest.contains("::") {
                if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: (span.start + 3)..<span.end, context: context) {
                    ranges.append(range)
                }
            }
        }
        return ranges
    }

    /// `//` comment lines with secret-like assignments.
    static func asciidocComments(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        let bytes = Array(source.utf8)
        var ranges: [SensitiveRange] = []
        for span in try lineSpans(bytes, limit: Int.max, context: context) {
            try context.checkpoint()
            guard span.end - span.start > 2, bytes[span.start] == 0x2F, bytes[span.start + 1] == 0x2F else { continue }
            if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: (span.start + 2)..<span.end, context: context) {
                ranges.append(range)
            }
        }
        return ranges
    }

    // MARK: Fountain

    /// The title page is a block of `Key: value` lines at the top of the file, ended by a blank line.
    static func fountainTitlePage(in source: String, context: RequestContext) throws -> [SensitiveRange] {
        try context.checkpoint()
        let bytes = Array(source.utf8)
        var end = 0
        for span in try lineSpans(bytes, limit: 200, context: context) {
            if trimmed(bytes, span).isEmpty { break }
            end = span.end
        }
        guard end > 0 else { return [] }
        let slice = String(decoding: bytes[0..<end], as: UTF8.self)
        guard slice.contains(":") else { return [] }
        return try ConfigurationPrivacyRanges.ranges(in: slice, syntax: .yaml, context: context)
    }

    // MARK: Lines

    struct LineSpan {
        let start: Int
        let end: Int
        /// Offset of the first byte after the line terminator.
        let next: Int
    }

    /// Byte spans of lines (LF, CR and CRLF), at most `limit` of them.
    static func lineSpans(_ bytes: [UInt8], limit: Int, context: RequestContext) throws -> [LineSpan] {
        var spans: [LineSpan] = []
        var start = 0
        while start <= bytes.count, spans.count < limit {
            if spans.count.isMultiple(of: 256) { try context.checkpoint() }
            var end = start
            while end < bytes.count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
            var next = end
            if next < bytes.count { next += (bytes[next] == 13 && next + 1 < bytes.count && bytes[next + 1] == 10) ? 2 : 1 }
            spans.append(LineSpan(start: start, end: end, next: next))
            if end >= bytes.count { break }
            start = next
        }
        return spans
    }

    private static func trimmed(_ bytes: [UInt8], _ span: LineSpan) -> String {
        String(decoding: bytes[span.start..<span.end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
}
