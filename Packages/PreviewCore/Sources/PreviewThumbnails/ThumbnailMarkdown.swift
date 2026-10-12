import Foundation
import PreviewContracts

/// A heading plus body text for Markdown-like documents. This reads only the concealed text, decorates
/// nothing it cannot see, and never resolves a link or an image target.
enum ThumbnailMarkdown {
    /// The character that opens a heading line in each supported markup.
    private static func headingMarker(for syntax: TextSyntax) -> Unicode.Scalar? {
        switch syntax {
        case .markdown: "#"
        case .asciidoc: "="
        case .orgMode: "*"
        default: nil
        }
    }

    static func supports(_ syntax: TextSyntax) -> Bool { headingMarker(for: syntax) != nil }

    /// Source lines read beyond what a page can hold, so that comment lines, which draw nothing, do not use up the
    /// lines the page is built from.
    private static let commentLineAllowance = 200
    /// Inspect complete lines before display clipping, with fixed bounds even for a very wide line.
    /// A boundary that leaves markup state uncertain withholds the page rather than guessing.
    private static let maximumInspectedLineScalars = 8_192
    private static let maximumInspectedScalars = 65_536

    /// The page of a rendered markup, or nil when nothing a reader sees is left. Comments (`<!-- -->` and the like)
    /// are not drawn (see `ThumbnailCommentSkipper`), so a document of comments alone has no page and the caller
    /// does not fall back to drawing its raw text.
    static func page(from text: String, syntax: TextSyntax, metrics: ThumbnailMetrics, rows: Int? = nil) -> ThumbnailTextPage? {
        guard let marker = headingMarker(for: syntax) else { return nil }
        let capacityRows = min(metrics.rows, rows ?? metrics.rows)
        guard let source = ThumbnailLines.complete(in: text, limit: capacityRows * 4 + 24 + commentLineAllowance,
            maxScalars: maximumInspectedLineScalars, maximumInspectedScalars: maximumInspectedScalars) else { return nil }
        var lines: [ThumbnailLine] = []
        var used = 0.0
        let capacity = Double(capacityRows)
        var index = skipFrontMatter(source)
        var inFence = false
        var previousWasBlank = true
        var comments = ThumbnailCommentSkipper(syntax: syntax)
        func append(_ line: ThumbnailLine) {
            // A line that would overflow the page ends the excerpt; the first line is always kept.
            guard lines.isEmpty || used + line.rowCost <= capacity else { used = capacity; return }
            lines.append(line)
            used += line.rowCost
        }
        while index < source.count, used < capacity {
            var line = ThumbnailLines.trimmingTrailingWhitespace(ThumbnailLines.expandTabs(source[index]))
            index += 1
            // A comment is not part of the rendered document, but the text of a fenced code block is, comment-like
            // or not. A line that is all comment is skipped without ending the paragraph it sits in.
            if comments.isInsideComment || !inFence {
                guard let visible = comments.visible(in: line) else { continue }
                line = ThumbnailLines.trimmingTrailingWhitespace(visible)
            }
            // Comment state saw the complete bounded line. Only now discard text that cannot fit
            // the page, so a tail's opener or closer cannot alter what the following line means.
            line = Array(line.prefix(metrics.columns * 8))
            let leading = ThumbnailLines.leadingSpaces(line)
            let body = Array(line.dropFirst(leading))
            if body.isEmpty {
                if !previousWasBlank { append(.blank) }
                previousWasBlank = true
                continue
            }
            previousWasBlank = false
            if isFence(body) { inFence.toggle(); continue }
            if inFence {
                let clipped = ThumbnailCells.prefix(Array(line), cells: metrics.columns)
                append(ThumbnailLine(indent: 0, runs: [ThumbnailRun(ThumbnailCells.string(clipped), tone: .muted)]))
                continue
            }
            if let heading = headingText(body, marker: marker) {
                let cells = Int(Double(metrics.columns) / Double(ThumbnailMetrics.headingScale))
                for piece in ThumbnailLines.wrap(clean(heading), cells: max(1, cells), maximumPieces: 2) {
                    append(ThumbnailLine(runs: [ThumbnailRun(ThumbnailCells.string(piece))], emphasis: .heading))
                }
                continue
            }
            if isRule(body) || isTableSeparator(body) { continue }
            var tone = ThumbnailTone.text
            var prefix: [Unicode.Scalar] = []
            var content = body
            if let rest = listItem(body) {
                prefix = Array("• ".unicodeScalars)
                content = rest
            } else if let quoted = blockQuote(body) {
                prefix = Array("│ ".unicodeScalars)
                content = quoted
                tone = .muted
            }
            let indent = min(leading, metrics.columns / 2)
            let width = max(1, metrics.columns - indent)
            let cleaned = prefix + clean(content)
            for (offset, piece) in ThumbnailLines.wrap(cleaned, cells: width, maximumPieces: 4).enumerated() where used < capacity {
                // Wrapped list lines hang under the text, not the bullet.
                let hanging = offset > 0 && !prefix.isEmpty ? ThumbnailCells.width(of: prefix) : 0
                append(ThumbnailLine(indent: min(indent + hanging, metrics.columns - 1),
                                     runs: [ThumbnailRun(ThumbnailCells.string(piece), tone: tone)]))
            }
        }
        while lines.last == .blank { lines.removeLast() }
        return lines.isEmpty ? nil : ThumbnailTextPage(lines: lines)
    }

    /// YAML front matter between `---` fences at the very start carries metadata, not the page.
    private static func skipFrontMatter(_ source: [[Unicode.Scalar]]) -> Int {
        guard let first = source.first, ThumbnailCells.string(first).trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in 1..<min(source.count, 41) {
            let candidate = ThumbnailCells.string(source[index]).trimmingCharacters(in: .whitespaces)
            if candidate == "---" || candidate == "..." { return index + 1 }
        }
        return 0
    }

    private static func isFence(_ body: [Unicode.Scalar]) -> Bool {
        body.count >= 3 && (body.prefix(3).allSatisfy { $0 == "`" } || body.prefix(3).allSatisfy { $0 == "~" })
    }

    private static func headingText(_ body: [Unicode.Scalar], marker: Unicode.Scalar) -> [Unicode.Scalar]? {
        let level = body.prefix(while: { $0 == marker }).count
        guard (1...6).contains(level), level < body.count, body[level] == " " else { return nil }
        var text = Array(body.dropFirst(level + 1))
        // A closing run of markers ("## Title ##") is decoration.
        while let last = text.last, last == marker || last == " " { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    private static func isRule(_ body: [Unicode.Scalar]) -> Bool {
        let compact = body.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ body: [Unicode.Scalar]) -> Bool {
        body.first == "|" && body.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func listItem(_ body: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        if body.count > 2, body[0] == "-" || body[0] == "*" || body[0] == "+", body[1] == " " {
            var rest = Array(body.dropFirst(2))
            // Task list markers read as checkboxes.
            if rest.count >= 4, rest[0] == "[", rest[2] == "]", rest[3] == " " {
                if rest[1] == " " { rest = Array("☐ ".unicodeScalars) + rest.dropFirst(4) }
                else if rest[1] == "x" || rest[1] == "X" { rest = Array("☑ ".unicodeScalars) + rest.dropFirst(4) }
            }
            return rest
        }
        let digits = body.prefix(while: { $0.value >= 48 && $0.value <= 57 })
        if !digits.isEmpty, digits.count <= 3, digits.count + 1 < body.count,
           body[digits.count] == "." || body[digits.count] == ")", body[digits.count + 1] == " " {
            return Array(body.dropFirst(digits.count + 2))
        }
        return nil
    }

    private static func blockQuote(_ body: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        guard body.first == ">" else { return nil }
        var rest = body.dropFirst()
        while let first = rest.first, first == " " || first == ">" { rest = rest.dropFirst() }
        return Array(rest)
    }

    /// Removes inline markers and link syntax, keeping only link text and image descriptions.
    static func clean(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        var index = 0
        let count = scalars.count
        while index < count {
            let scalar = scalars[index]
            switch scalar {
            case "`":
                index += 1
            case "*", "_", "~":
                // Doubled or repeated markers are emphasis; a lone underscore inside a word stays.
                if scalar == "_", index > 0, index + 1 < count, scalars[index - 1] != " ", scalars[index + 1] != " ",
                   scalars[index - 1] != "_", scalars[index + 1] != "_" {
                    result.append(scalar)
                }
                index += 1
            case "!", "[":
                var start = index
                if scalar == "!" {
                    guard index + 1 < count, scalars[index + 1] == "[" else { result.append(scalar); index += 1; continue }
                    start = index + 1
                }
                guard let close = scalars[(start + 1)...].firstIndex(of: "]") else { result.append(scalar); index += 1; continue }
                result.append(contentsOf: scalars[(start + 1)..<close])
                index = close + 1
                // Drop the target: "(url)" or "[reference]".
                if index < count, scalars[index] == "(" || scalars[index] == "[" {
                    let closer: Unicode.Scalar = scalars[index] == "(" ? ")" : "]"
                    if let end = scalars[(index + 1)...].firstIndex(of: closer) { index = end + 1 }
                }
            default:
                result.append(scalar)
                index += 1
            }
        }
        return result
    }
}
