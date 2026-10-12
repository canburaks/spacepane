import Foundation
import PreviewContracts

/// Output ceilings for generated Markdown, derived from the request's budget.
struct MarkdownLimits: Sendable {
    let maximumUTF16Units: Int
    let maximumUTF8Bytes: Int
    let maximumLines: Int
    /// Longest line written; longer paragraphs wrap here so no line approaches the shared per-line limit.
    let wrapBytes: Int

    /// Room kept free at the top of a document for front matter, which is written after the body because
    /// it reports what the body turned out to contain.
    static let frontMatterReserve = (utf16: 8_192, utf8: 24_576, lines: 24)

    init(context: RequestContext, reservesFrontMatter: Bool = false) {
        let budget = context.budget
        let reserve = reservesFrontMatter ? Self.frontMatterReserve : (utf16: 0, utf8: 0, lines: 0)
        maximumUTF16Units = max(0, min(DocumentLimits.renderableUTF16Units, budget.maxOutputUTF8Bytes) - reserve.utf16)
        // A quarter of the output budget stays free: concealment replaces each secret with four bullets.
        maximumUTF8Bytes = max(0, budget.maxOutputUTF8Bytes - budget.maxOutputUTF8Bytes / 4 - reserve.utf8)
        maximumLines = max(1, min(budget.maxTextLines - 16, 19_900) - reserve.lines)
        wrapBytes = max(16, min(8_192, budget.maxLineUTF8Bytes / 2))
    }
}

/// Leading characters of a block's lines: block quote markers, list indentation and a list marker.
struct LinePrefix: Equatable, Sendable {
    var quoteDepth = 0
    var indent = 0
    var marker: String?

    var first: String { quote + String(repeating: " ", count: indent) + (marker ?? "") }
    var rest: String { quote + String(repeating: " ", count: indent + (marker?.count ?? 0)) }
    private var quote: String { String(repeating: "> ", count: quoteDepth) }
}

/// Text escaping for the native Markdown subset. The renderer reads backslash escapes before any other
/// inline marker, so escaping the few characters it interprets keeps document text from being mistaken for
/// formatting, links or images.
enum MarkdownEscaping {
    /// Prose: backslash, emphasis markers, backtick and opening bracket.
    ///
    /// An underscore inside a word (`api_key`, `snake_case`) is left as written. The shared privacy filter
    /// recognizes secret-bearing names such as `api_key = value` by their spelling, and a backslash in the
    /// middle of the name would hide it; concealment takes priority over how an intraword underscore renders.
    static func prose(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { proseSpecials.contains($0) }) else { return text }
        var result = ""
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            if needsEscape(scalar, after: previous) { result.append("\\") }
            result.unicodeScalars.append(scalar)
            previous = scalar
        }
        return result
    }

    /// Whether `scalar` must be escaped in prose, given the scalar written just before it.
    static func needsEscape(_ scalar: Unicode.Scalar, after previous: Unicode.Scalar?) -> Bool {
        guard proseSpecials.contains(scalar) else { return false }
        if scalar == "_", let previous, previous.properties.isAlphabetic || previous.properties.numericType != nil { return false }
        return true
    }

    /// Longest image description written, so the whole `![description]()` stays inside the renderer's span scan.
    static let maximumImageDescriptionCharacters = 400

    /// An inert Markdown image that carries only its description: `![description]()`. The adapters never keep an
    /// image source, so the renderer draws one localized marker and nothing is requested or shown from the file.
    /// The description is prose-escaped exactly as other text is (an intraword underscore stays as written, so the
    /// shared privacy filter still recognizes `api_key = value`) and its closing bracket is escaped too, so no
    /// description can end the image early. Nil when there is no description to show.
    static func image(description raw: String) -> String? {
        var value = singleLine(raw)
        guard !value.isEmpty else { return nil }
        if value.count > maximumImageDescriptionCharacters {
            value = String(value.prefix(maximumImageDescriptionCharacters)) + "…"
        }
        return "![" + prose(value).replacingOccurrences(of: "]", with: "\\]") + "]()"
    }

    /// Code spans: only the backslash escape is read inside them; a backtick would end the span.
    static func code(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar == "`" { result.append("'"); continue }
            if scalar == "\\" { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Escapes a line start that would otherwise begin a heading, list, quote, fence or table row.
    static func leading(_ line: String) -> String {
        guard let first = line.unicodeScalars.first else { return line }
        if "#>-+~|".unicodeScalars.contains(first) { return "\\" + line }
        // `1.` or `12)` followed by a space starts an ordered list in most Markdown dialects.
        let digits = line.unicodeScalars.prefix { $0.value >= 48 && $0.value <= 57 }
        if !digits.isEmpty {
            let rest = line.unicodeScalars.dropFirst(digits.count)
            if let marker = rest.first, marker == "." || marker == ")" {
                var scalars = Array(line.unicodeScalars)
                scalars.insert("\\", at: digits.count)
                return String(String.UnicodeScalarView(scalars))
            }
        }
        return line
    }

    /// Whitespace-collapsed single line with control characters removed.
    static func singleLine(_ text: String) -> String {
        var result = ""
        var pending = false
        for scalar in text.unicodeScalars {
            if isBreakingSpace(scalar) { pending = true; continue }
            if isRemovable(scalar) { continue }
            if pending, !result.isEmpty { result.append(" ") }
            pending = false
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Controls the shared text pass rejects as binary, plus the byte order mark and zero-width no-break space.
    static func isRemovable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0xFEFF || scalar.value == 0x7F || (scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13)
    }

    /// Whitespace that collapses between words (not the no-break space, which is preserved).
    static func isBreakingSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 9, 10, 13, 32, 0x85, 0x2028, 0x2029, 12, 11, 0x3000: return true
        default: return false
        }
    }

    private static let proseSpecials: Set<Unicode.Scalar> = ["\\", "*", "_", "`", "["]
}

/// Appends Markdown blocks within the output ceilings. When a ceiling is reached the writer stops accepting
/// output and reports `isFull`; callers treat that as a partial document and never as an error.
struct MarkdownWriter {
    let limits: MarkdownLimits
    private(set) var text = ""
    private(set) var utf16Count = 0
    private(set) var utf8Count = 0
    private(set) var lineCount = 0
    /// Set when some output was refused because a ceiling was reached.
    private(set) var isFull = false
    private var lastLineWasBlank = true

    /// `reservesFrontMatter` leaves room for `document(…)` to prepend front matter to this body.
    init(context: RequestContext, reservesFrontMatter: Bool = false) {
        limits = MarkdownLimits(context: context, reservesFrontMatter: reservesFrontMatter)
    }

    var isEmpty: Bool { lineCount == 0 }

    /// Front matter followed by `body`. Flags are keys written as `key: true`; `partial` is added when the body
    /// stopped early, so the status line can say the document is incomplete. Counts are keys written as `key: 12`:
    /// numbers the adapter measured (chapters read and chapters in the book) that the status line states in the
    /// reader's language, so the view never has to infer them.
    static func document(fields: [(key: String, value: String)], flags: [String],
                         counts: [(key: String, value: Int)] = [], body: MarkdownWriter,
                         context: RequestContext) -> String {
        var header = MarkdownWriter(context: context)
        let allFlags = flags + (body.isFull && !flags.contains("partial") ? ["partial"] : [])
        header.frontMatter(fields, flags: allFlags, counts: counts)
        return header.text + body.text
    }

    // MARK: Lines

    mutating func appendLine(_ line: String) {
        guard !isFull else { return }
        let bytes = line.utf8.count + 1
        let units = line.utf16.count + 1
        guard lineCount < limits.maximumLines, utf8Count + bytes <= limits.maximumUTF8Bytes,
              utf16Count + units <= limits.maximumUTF16Units else {
            isFull = true
            return
        }
        text.append(line)
        text.append("\n")
        utf8Count += bytes
        utf16Count += units
        lineCount += 1
        lastLineWasBlank = line.isEmpty
    }

    /// Writes one blank line unless the output is empty or already ends with one.
    mutating func ensureBlankLine() {
        if lineCount > 0, !lastLineWasBlank { appendLine("") }
    }

    /// Marks the output incomplete because the source had more than could be read or converted.
    mutating func markIncomplete() { isFull = true }

    /// Wraps `line` at the byte limit, preferring spaces, with `first` before the first row and `rest` before others.
    mutating func appendWrapped(_ line: String, first: String, rest: String) {
        var remaining = Substring(line)
        var prefix = first
        while !remaining.isEmpty, !isFull {
            let available = max(8, limits.wrapBytes - prefix.utf8.count)
            if remaining.utf8.count <= available {
                appendLine(prefix + remaining)
                return
            }
            var used = 0
            var cut = remaining.startIndex
            var lastSpace: Substring.Index?
            for index in remaining.indices {
                let size = remaining[index].utf8.count
                if used + size > available { break }
                used += size
                cut = remaining.index(after: index)
                if remaining[index] == " " { lastSpace = index }
            }
            if cut == remaining.startIndex { cut = remaining.index(after: remaining.startIndex) }
            if let space = lastSpace, space > remaining.startIndex { cut = space }
            appendLine(prefix + remaining[..<cut])
            remaining = remaining[cut...].drop { $0 == " " }
            prefix = rest
        }
    }

    // MARK: Blocks

    /// `content` is inline Markdown already escaped by the caller.
    mutating func heading(level: Int, content: String, prefix: LinePrefix = .init()) {
        let flat = MarkdownEscaping.singleLine(content)
        guard !flat.isEmpty else { return }
        ensureBlankLine()
        appendWrapped(String(repeating: "#", count: min(max(level, 1), 6)) + " " + flat, first: prefix.first, rest: prefix.rest)
    }

    /// Paragraph of one or more hard-broken lines of already escaped inline Markdown.
    mutating func paragraph(lines: [String], prefix: LinePrefix, tight: Bool) {
        let content = lines.map { MarkdownEscaping.leading($0) }.filter { !$0.isEmpty }
        guard !content.isEmpty else { return }
        if !tight { ensureBlankLine() }
        for (index, line) in content.enumerated() {
            appendWrapped(line, first: index == 0 ? prefix.first : prefix.rest, rest: prefix.rest)
        }
    }

    /// Fenced code. The fence avoids any run the code itself contains, so the code cannot end its own block.
    mutating func codeBlock(lines: [String], prefix: LinePrefix) {
        guard lines.contains(where: { !$0.isEmpty }) else { return }
        ensureBlankLine()
        let collides: (String) -> Bool = { fence in
            lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(fence) }
        }
        var fence = "```"
        var body = lines
        if collides(fence) {
            fence = "~~~"
            if collides(fence) {
                // Both fences occur in the code: break the leading run with a zero-width space.
                body = lines.map { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") ? "\u{200B}" + line : line
                }
                fence = "```"
            }
        }
        appendLine(prefix.first + fence)
        for line in body { appendWrapped(line, first: prefix.rest, rest: prefix.rest) }
        appendLine(prefix.rest + fence)
    }

    /// Pipe table: the first row is the header. Cells are single-line text without pipes.
    mutating func table(rows: [[String]], prefix: LinePrefix) {
        let columns = min(rows.map(\.count).max() ?? 0, 32)
        guard columns > 0 else { return }
        ensureBlankLine()
        func line(_ cells: [String]) -> String {
            var padded = Array(cells.prefix(columns))
            while padded.count < columns { padded.append("") }
            var row = "| " + padded.joined(separator: " | ") + " |"
            // Table rows cannot wrap; drop trailing cells until the row fits the line limit.
            while row.utf8.count > limits.wrapBytes * 3, padded.count > 1 {
                padded.removeLast()
                row = "| " + padded.joined(separator: " | ") + " |"
            }
            return row
        }
        for (index, row) in rows.enumerated() {
            appendLine((index == 0 ? prefix.first : prefix.rest) + line(row))
            if index == 0 { appendLine(prefix.rest + "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |") }
        }
    }

    mutating func thematicBreak(prefix: LinePrefix = .init()) {
        ensureBlankLine()
        appendLine(prefix.first + "---")
    }

    // MARK: Front matter

    /// YAML front matter with plain `key: value` lines. Values are collapsed to one line; a value that YAML
    /// could misread is double-quoted. Empty values are omitted. Each key in `flags` is written as `key: true`
    /// and each entry of `counts` as `key: 12` (a negative count is not written); the presentation layer reads
    /// them to show localized notices.
    mutating func frontMatter(_ fields: [(key: String, value: String)], flags: [String] = [],
                              counts: [(key: String, value: Int)] = []) {
        var present = fields.compactMap { field -> String? in
            let value = Self.scalar(field.value, maximumCharacters: field.key == "description" ? 2_048 : 512)
            return value.isEmpty ? nil : "\(field.key): \(value)"
        } + flags.map { "\($0): true" }
        present += counts.filter { $0.value >= 0 }.map { "\($0.key): \($0.value)" }
        guard !present.isEmpty else { return }
        appendLine("---")
        for line in present { appendLine(line) }
        appendLine("---")
        appendLine("")
    }

    static func scalar(_ raw: String, maximumCharacters: Int = 512) -> String {
        var value = MarkdownEscaping.singleLine(raw)
        if value.count > maximumCharacters { value = String(value.prefix(maximumCharacters)) + "…" }
        guard !value.isEmpty else { return "" }
        let indicators: Set<Character> = ["-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`"]
        let reserved = ["true", "false", "null", "yes", "no", "on", "off", "~"]
        let needsQuotes = indicators.contains(value.first ?? "a") || value.contains(": ") || value.contains(" #")
            || value.hasSuffix(":") || reserved.contains(value.lowercased()) || value.first == " " || value.last == " "
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
