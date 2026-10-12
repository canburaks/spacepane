import Foundation

/// A structural reading of Org mode for the Rendered and Contents views: headings, paragraphs,
/// nested bullet/ordered/check/description lists, tables, source/example/quote/center blocks,
/// property drawers and keyword lines, with inline emphasis and links shown as inert text.
/// Nothing is evaluated or exported: source blocks are text, `#+INCLUDE` and `#+SETUPFILE`
/// are shown dimmed and never followed, and drawers and keywords are never interpreted.
struct OrgRenderer {
    private struct ListFrame {
        let indent: Int
        var ordered: Bool
        var counter: Int
        var markerLength: Int
    }

    private let lines: [String]
    private var writer: MarkupBlockWriter
    private var list: [ListFrame] = []
    private var skipped = Set<Int>()

    private static let maximumNesting = 8
    private static let planningPrefixes = ["SCHEDULED:", "DEADLINE:", "CLOSED:"]

    static func render(_ source: String, limits: MarkupBuilder.Limits) -> SafeMarkdownDocument? {
        guard source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        let lines = MarkupLines.split(source).map { $0.replacingOccurrences(of: "\t", with: "        ") }
        guard lines.count <= 20_000 else { return nil }
        var renderer = OrgRenderer(lines: lines, writer: MarkupBlockWriter(limits: limits))
        renderer.collectFootnoteDefinitions()
        renderer.parse(0..<lines.count, nesting: 0)
        return renderer.writer.finish { text in
            var scratch = MarkupFootnotes()
            return MarkupDialectInline.render(text, dialect: .org, footnotes: &scratch)
        }
    }

    private init(lines: [String], writer: MarkupBlockWriter) {
        self.lines = lines
        self.writer = writer
    }

    private mutating func inline(_ text: String) -> MarkupInlineResult {
        MarkupDialectInline.render(text, dialect: .org, footnotes: &writer.footnotes)
    }

    private static func indent(of line: String) -> Int { line.prefix(while: { $0 == " " }).count }

    // MARK: Footnote definitions

    /// `[fn:label] text` lines at the start of a line, with their continuation lines.
    private mutating func collectFootnoteDefinitions() {
        var index = 0
        while index < lines.count, writer.footnotes.definitionOrder.count < MarkupFootnotes.maximumCount {
            let line = lines[index]
            guard line.hasPrefix("[fn:"), let close = line.firstIndex(of: "]") else { index += 1; continue }
            let label = String(line[line.index(line.startIndex, offsetBy: 4)..<close])
            guard !label.isEmpty, !label.contains(":"), !label.contains(" ") else { index += 1; continue }
            var parts = [String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)]
            skipped.insert(index)
            var next = index + 1
            while next < lines.count, !lines[next].trimmingCharacters(in: .whitespaces).isEmpty, !lines[next].hasPrefix("[fn:"),
                  !lines[next].hasPrefix("*") {
                parts.append(lines[next].trimmingCharacters(in: .whitespaces))
                skipped.insert(next)
                next += 1
            }
            if writer.footnotes.definitions[label] == nil {
                writer.footnotes.definitions[label] = parts.filter { !$0.isEmpty }.joined(separator: " ")
                writer.footnotes.definitionOrder.append(label)
            }
            index = next
        }
    }

    // MARK: Block loop

    private mutating func parse(_ range: Range<Int>, nesting: Int) {
        var index = range.lowerBound
        while index < range.upperBound {
            guard !writer.isOverflowed else { return }
            if skipped.contains(index) { index += 1; continue }
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            let indent = Self.indent(of: raw)
            if indent == 0, raw.hasPrefix("*"), let (level, text) = Self.heading(raw) {
                list.removeAll()
                writer.heading(level: level, inline(text))
                index += 1
                continue
            }
            if trimmed.uppercased().hasPrefix("#+BEGIN_") {
                index = block(at: index, in: range, nesting: nesting)
                continue
            }
            if trimmed.hasPrefix("#+") {
                keyword(trimmed)
                index += 1
                continue
            }
            if trimmed == "#" || trimmed.hasPrefix("# ") {
                writer.dimmedLine(trimmed)
                index += 1
                continue
            }
            if trimmed.uppercased() == ":PROPERTIES:" || trimmed.uppercased() == ":LOGBOOK:" {
                var cursor = index
                writer.dimmedLine(trimmed, grouped: false)
                cursor += 1
                while cursor < range.upperBound {
                    let line = lines[cursor].trimmingCharacters(in: .whitespaces)
                    writer.dimmedLine(line)
                    cursor += 1
                    if line.uppercased() == ":END:" { break }
                }
                index = cursor
                continue
            }
            if Self.planningPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                writer.dimmedLine(trimmed)
                index += 1
                continue
            }
            if trimmed.count >= 5, trimmed.allSatisfy({ $0 == "-" }) { list.removeAll(); writer.rule(); index += 1; continue }
            if trimmed.hasPrefix("|") { index = table(at: index, in: range); continue }
            if trimmed.hasPrefix(": ") || trimmed == ":" {
                var cursor = index
                var code: [String] = []
                while cursor < range.upperBound, lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix(":") {
                    let line = lines[cursor].trimmingCharacters(in: .whitespaces)
                    code.append(String(line.dropFirst(line.hasPrefix(": ") ? 2 : 1)))
                    cursor += 1
                }
                writer.codeBlock(code)
                index = cursor
                continue
            }
            if trimmed == "\\[" || trimmed.hasPrefix("\\begin{") {
                index = latexBlock(at: index, in: range)
                continue
            }
            if let item = Self.listItem(raw) {
                index = listItem(item, at: index, in: range)
                continue
            }
            index = paragraph(at: index, in: range)
        }
    }

    // MARK: Headings and keywords

    private static func heading(_ raw: String) -> (Int, String)? {
        let stars = raw.prefix(while: { $0 == "*" })
        guard raw.dropFirst(stars.count).first == " " else { return nil }
        let text = raw.dropFirst(stars.count).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (min(stars.count, 6), text)
    }

    private mutating func keyword(_ trimmed: String) {
        let body = trimmed.dropFirst(2)
        guard let colon = body.firstIndex(of: ":") else { writer.dimmedLine(trimmed); return }
        let name = body[..<colon].uppercased()
        let value = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        switch name {
        case "TITLE" where !value.isEmpty:
            writer.heading(level: 1, inline(value), listed: false, extra: [.centered])
        case "AUTHOR" where !value.isEmpty, "DATE" where !value.isEmpty, "SUBTITLE" where !value.isEmpty:
            writer.paragraph(inline(value), styles: [.centered])
        default:
            // Options, includes and other keywords are shown, never applied or followed.
            if name == "INCLUDE" { writer.noteOmitted(.linkedFile) }
            writer.dimmedLine(trimmed)
        }
    }

    // MARK: Blocks

    private mutating func block(at index: Int, in range: Range<Int>, nesting: Int) -> Int {
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        let nameStart = opening.index(opening.startIndex, offsetBy: 8)
        let name = opening[nameStart...].prefix(while: { !$0.isWhitespace }).uppercased()
        let end = "#+END_" + name
        var cursor = index + 1
        var body: [String] = []
        // An unterminated block runs to the end of the document.
        while cursor < range.upperBound {
            let line = lines[cursor]
            if line.trimmingCharacters(in: .whitespaces).uppercased() == end { cursor += 1; break }
            body.append(line)
            cursor += 1
        }
        list.removeAll()
        let minimum = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(Self.indent(of:)).min() ?? 0
        let dedented = body.map { $0.count >= minimum ? String($0.dropFirst(minimum)) : $0 }
        switch name {
        case "SRC", "EXAMPLE", "EXPORT", "VERSE", "LATEX", "HTML":
            writer.codeBlock(dedented.map { $0.hasPrefix(",*") || $0.hasPrefix(",#") ? String($0.dropFirst()) : $0 })
        case "COMMENT":
            for line in dedented where !line.isEmpty { writer.dimmedLine(line) }
        case "QUOTE":
            writer.quote(Self.paragraphs(of: dedented).map { inline($0) })
        case "CENTER":
            for paragraph in Self.paragraphs(of: dedented) { writer.paragraph(inline(paragraph), styles: [.centered]) }
        case "EQUATION":
            writer.mathBlock(dedented.joined(separator: "\n"))
        default:
            // Unknown special blocks (warning, note ...) hold ordinary paragraphs.
            if let kind = Self.alertKind(name) {
                writer.admonition(kind, body: Self.paragraphs(of: dedented).map { inline($0) })
            } else if nesting < Self.maximumNesting {
                for paragraph in Self.paragraphs(of: dedented) { writer.paragraph(inline(paragraph)) }
            }
        }
        return cursor
    }

    private static func alertKind(_ name: String) -> MarkupAlertKind? { MarkupAlertKind(rawValue: name.lowercased()) }

    private static func paragraphs(of block: [String]) -> [String] {
        var result: [String] = []
        var current: [String] = []
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { if !current.isEmpty { result.append(current.joined(separator: " ")); current = [] } }
            else { current.append(trimmed) }
        }
        if !current.isEmpty { result.append(current.joined(separator: " ")) }
        return result
    }

    private mutating func latexBlock(at index: Int, in range: Range<Int>) -> Int {
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        let closing: String
        if opening == "\\[" { closing = "\\]" }
        else if let close = opening.firstIndex(of: "}") { closing = "\\end" + String(opening[opening.index(opening.startIndex, offsetBy: 6)..<close]) + "}" }
        else { closing = "\\end{" }
        var cursor = index + 1
        var body: [String] = opening == "\\[" ? [] : [opening]
        while cursor < range.upperBound {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(closing) { if opening != "\\[" { body.append(line) }; cursor += 1; break }
            body.append(line)
            cursor += 1
        }
        list.removeAll()
        writer.mathBlock(body.joined(separator: "\n"))
        return cursor
    }

    // MARK: Tables

    private mutating func table(at index: Int, in range: Range<Int>) -> Int {
        list.removeAll()
        var cursor = index
        var rows: [(cells: [String], isRule: Bool)] = []
        while cursor < range.upperBound {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { break }
            if trimmed.hasPrefix("|-") { rows.append(([], true)) }
            else {
                var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                rows.append((cells, false))
            }
            cursor += 1
        }
        let headerAtTop = rows.count > 1 && rows[1].isRule
        for (position, row) in rows.enumerated() where !row.isRule {
            writer.tableRow(row.cells.map { inline($0) }, header: headerAtTop && position == 0)
        }
        return cursor
    }

    // MARK: Lists

    private struct Item {
        let indent: Int
        let ordered: Bool
        let number: Int?
        let text: String
    }

    private static func listItem(_ raw: String) -> Item? {
        let indent = Self.indent(of: raw)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        // `*` starts a list item only when indented; at column zero it is a heading.
        if first == "-" || first == "+" || (first == "*" && indent > 0), trimmed.dropFirst().first == " " {
            return Item(indent: indent, ordered: false, number: nil, text: trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        if first.isASCII, first.isNumber {
            let digits = trimmed.prefix(while: { $0.isASCII && $0.isNumber })
            let rest = trimmed.dropFirst(digits.count)
            if digits.count <= 6, rest.hasPrefix(". ") || rest.hasPrefix(") "), let number = Int(digits) {
                return Item(indent: indent, ordered: true, number: number, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private mutating func listItem(_ item: Item, at index: Int, in range: Range<Int>) -> Int {
        while let top = list.last, item.indent < top.indent { list.removeLast() }
        if let top = list.last, top.indent == item.indent {
            if top.ordered != item.ordered { list[list.count - 1] = ListFrame(indent: item.indent, ordered: item.ordered, counter: 0, markerLength: 2) }
        } else if list.count < 16 {
            list.append(ListFrame(indent: item.indent, ordered: item.ordered, counter: 0, markerLength: 2))
        }
        let depth = list.count - 1
        list[depth].counter = item.ordered ? (item.number ?? list[depth].counter + 1) : 0
        var parts = [item.text]
        var cursor = index + 1
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard Self.indent(of: raw) > item.indent, Self.listItem(raw) == nil, !skipped.contains(cursor) else { break }
            parts.append(trimmed)
            cursor += 1
        }
        var text = parts.joined(separator: " ")
        var task: Bool?
        // Counter cookies `[@5]` and checkboxes.
        if text.hasPrefix("[@"), let close = text.firstIndex(of: "]") { text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces) }
        if text.hasPrefix("[X] ") || text.hasPrefix("[x] ") { task = true; text = String(text.dropFirst(4)) }
        else if text.hasPrefix("[ ] ") || text.hasPrefix("[-] ") { task = false; text = String(text.dropFirst(4)) }
        let marker: String
        if let done = task { marker = done ? "\u{2611}" : "\u{2610}" }
        else if item.ordered { marker = "\(list[depth].counter)." }
        else { marker = ["\u{2022}", "\u{25E6}", "\u{25AA}"][min(depth, 2)] }
        list[depth].markerLength = marker.count + 1
        // Description list: `term :: description`.
        if let range = text.range(of: " :: ") {
            let term = String(text[..<range.lowerBound])
            let definition = String(text[range.upperBound...])
            var result = inline(term)
            let length = result.text.utf16.count
            result.decorations.append(.init(range: NSRange(location: 0, length: length), style: .definitionTerm))
            let rendered = inline(definition)
            result.decorations += rendered.decorations.map {
                .init(range: NSRange(location: $0.range.location + length + 2, length: $0.range.length), style: $0.style)
            }
            result.text += ": " + rendered.text
            result.omitted.add(rendered.omitted)
            writer.listItem(marker: marker, depth: depth, result, taskDone: task)
        } else {
            writer.listItem(marker: marker, depth: depth, inline(text), taskDone: task)
        }
        return cursor
    }

    // MARK: Paragraphs

    private mutating func paragraph(at index: Int, in range: Range<Int>) -> Int {
        let firstIndent = Self.indent(of: lines[index])
        var parts: [String] = []
        var cursor = index
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || skipped.contains(cursor) { break }
            if cursor > index {
                let startsHeading = raw.hasPrefix("*") && Self.heading(raw) != nil
                let startsItem = Self.listItem(raw) != nil && Self.indent(of: raw) <= firstIndent
                if startsHeading || startsItem || trimmed.hasPrefix("|") || trimmed.hasPrefix("#+") { break }
            }
            parts.append(trimmed)
            cursor += 1
        }
        let result = inline(parts.joined(separator: " "))
        if !list.isEmpty, firstIndent > 0 {
            writer.listContinuation(depth: list.count - 1, markerLength: list[list.count - 1].markerLength, result)
        } else {
            list.removeAll()
            writer.paragraph(result)
        }
        return max(cursor, index + 1)
    }
}
