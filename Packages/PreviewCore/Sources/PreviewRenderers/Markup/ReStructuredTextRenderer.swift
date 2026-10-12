import Foundation

/// A structural reading of reStructuredText for the Rendered and Contents views: section titles
/// (levels follow the order adornment styles first appear), paragraphs, nested bullet and
/// enumerated lists, definition and field lists, literal blocks, quotes, grid/simple/list tables
/// and admonitions. Directives are never run: `include`, `literalinclude`, `raw` and
/// `image` are shown as dimmed text and nothing is read, substituted or emitted as markup.
struct ReStructuredTextRenderer {
    private struct ListFrame {
        let indent: Int
        var ordered: Bool
        var counter: Int
        var markerLength: Int
    }

    private let lines: [String]
    private var writer: MarkupBlockWriter
    private var adornmentLevels: [String: Int] = [:]
    private var list: [ListFrame] = []

    private static let maximumNesting = 8
    private static let adornmentCharacters = Set("=-`:'\"~^_*+#<>")
    private static let admonitionKinds: [String: MarkupAlertKind] = [
        "note": .note, "seealso": .note, "tip": .tip, "hint": .tip, "important": .important, "attention": .important,
        "warning": .warning, "caution": .caution, "danger": .caution, "error": .caution
    ]
    /// Directives that only configure the build; they produce no text.
    private static let silentDirectives: Set<String> = [
        "contents", "sectnum", "header", "footer", "role", "default-role", "highlight", "index", "tabularcolumns",
        "meta", "title", "target-notes", "no-code-block"
    ]

    static func render(_ source: String, limits: MarkupBuilder.Limits) -> SafeMarkdownDocument? {
        guard source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        let lines = MarkupLines.split(source).map { $0.replacingOccurrences(of: "\t", with: "        ") }
        guard lines.count <= 20_000 else { return nil }
        var renderer = ReStructuredTextRenderer(lines: lines, writer: MarkupBlockWriter(limits: limits))
        renderer.parse(0..<lines.count, nesting: 0)
        return renderer.writer.finish { text in
            var scratch = MarkupFootnotes()
            return MarkupDialectInline.render(text, dialect: .restructuredText, footnotes: &scratch)
        }
    }

    private init(lines: [String], writer: MarkupBlockWriter) {
        self.lines = lines
        self.writer = writer
    }

    private mutating func inline(_ text: String) -> MarkupInlineResult {
        MarkupDialectInline.render(text, dialect: .restructuredText, footnotes: &writer.footnotes)
    }

    // MARK: Helpers

    private static func indent(of line: String) -> Int { line.prefix(while: { $0 == " " }).count }

    private func isBlank(_ index: Int) -> Bool {
        index < 0 || index >= lines.count || lines[index].trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isAdornment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, adornmentCharacters.contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    /// Lines after `index` that are blank or indented deeper than `indent`, dedented, with trailing blanks removed.
    private func indentedBlock(after index: Int, deeperThan indent: Int, in range: Range<Int>) -> (lines: [String], next: Int) {
        var cursor = index + 1
        var collected: [String] = []
        while cursor < range.upperBound {
            let line = lines[cursor]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { collected.append(""); cursor += 1; continue }
            guard Self.indent(of: line) > indent else { break }
            collected.append(line)
            cursor += 1
        }
        while collected.last == "" { collected.removeLast(); cursor -= 1 }
        // Leave trailing blank lines for the main loop.
        let minimum = collected.filter { !$0.isEmpty }.map(Self.indent(of:)).min() ?? 0
        return (collected.map { $0.isEmpty ? "" : String($0.dropFirst(minimum)) }, cursor)
    }

    // MARK: Block loop

    private mutating func parse(_ range: Range<Int>, nesting: Int) {
        var index = range.lowerBound
        while index < range.upperBound {
            guard !writer.isOverflowed else { return }
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            let indent = Self.indent(of: raw)
            // Titles: overlined and underlined.
            if indent == 0, let (level, title, consumed) = title(at: index, in: range) {
                list.removeAll()
                writer.heading(level: level, inline(title))
                index += consumed
                continue
            }
            // Transition.
            if indent == 0, Self.isAdornment(raw), trimmed.count >= 4, isBlank(index - 1) || index == range.lowerBound, isBlank(index + 1) {
                list.removeAll()
                writer.rule()
                index += 1
                continue
            }
            if indent == 0, trimmed.hasPrefix("..") && (trimmed == ".." || trimmed.hasPrefix(".. ")) {
                list.removeAll()
                index = explicitMarkup(at: index, in: range, nesting: nesting)
                continue
            }
            if trimmed.hasPrefix(">>> ") || trimmed == ">>>" {
                var code: [String] = []
                var cursor = index
                while cursor < range.upperBound, !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty { code.append(lines[cursor]); cursor += 1 }
                writer.codeBlock(code)
                index = cursor
                continue
            }
            if trimmed.hasPrefix("| ") || trimmed == "|", !trimmed.hasPrefix("|-") {
                // Line block: every line stands alone.
                var cursor = index
                var first = true
                while cursor < range.upperBound, lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let text = lines[cursor].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)
                    writer.line(inline(text), groupedWithPrevious: !first)
                    first = false
                    cursor += 1
                }
                index = cursor
                continue
            }
            if trimmed.hasPrefix("+-") || trimmed.hasPrefix("+="), trimmed.hasSuffix("+") { index = gridTable(at: index, in: range); continue }
            if trimmed.hasPrefix("="), trimmed.contains("  "), trimmed.allSatisfy({ $0 == "=" || $0 == " " }) { index = simpleTable(at: index, in: range); continue }
            if let field = Self.fieldItem(trimmed) {
                index = fieldItem(field, at: index, in: range)
                continue
            }
            if let item = Self.listItem(raw) {
                index = listItem(item, at: index, in: range)
                continue
            }
            // Definition list: a term over an indented definition.
            if indent == 0, index + 1 < range.upperBound, Self.indent(of: lines[index + 1]) > 0,
               !isBlank(index + 1), !trimmed.hasSuffix("::"), Self.listItem(lines[index + 1]) == nil {
                let (block, next) = indentedBlock(after: index, deeperThan: 0, in: range)
                list.removeAll()
                writer.line(inline(trimmed), styles: [.definitionTerm])
                for paragraph in Self.paragraphs(of: block) { writer.line(inline(paragraph), styles: [.indent(1)]) }
                index = next
                continue
            }
            if indent > 0, list.isEmpty {
                // An indented block with no list is a block quote.
                let (block, next) = indentedBlock(after: index - 1, deeperThan: indent - 1, in: range)
                let paragraphs = Self.paragraphs(of: block)
                writer.quote(paragraphs.map { inline($0) })
                index = next
                continue
            }
            index = paragraph(at: index, in: range, nesting: nesting)
        }
    }

    // MARK: Titles

    private mutating func title(at index: Int, in range: Range<Int>) -> (level: Int, title: String, consumed: Int)? {
        let first = lines[index]
        // Overlined: adornment, title, matching adornment.
        if Self.isAdornment(first), index + 2 < range.upperBound, Self.isAdornment(lines[index + 2]),
           let mark = first.trimmingCharacters(in: .whitespaces).first,
           lines[index + 2].trimmingCharacters(in: .whitespaces).first == mark {
            let text = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !Self.isAdornment(lines[index + 1]) else { return nil }
            return (level(for: "o" + String(mark)), text, 3)
        }
        // Underlined: text over an adornment at least as long as the text.
        if !Self.isAdornment(first), index + 1 < range.upperBound, Self.isAdornment(lines[index + 1]) {
            let text = first.trimmingCharacters(in: .whitespaces)
            let adornment = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard adornment.count >= text.count || adornment.count >= 3, let mark = adornment.first,
                  Self.listItem(first) == nil, Self.fieldItem(text) == nil, !text.hasPrefix("..") else { return nil }
            return (level(for: "u" + String(mark)), text, 2)
        }
        return nil
    }

    private mutating func level(for key: String) -> Int {
        if let known = adornmentLevels[key] { return known }
        let level = min(adornmentLevels.count + 1, 6)
        adornmentLevels[key] = level
        return level
    }

    // MARK: Paragraphs and literal blocks

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

    private mutating func paragraph(at index: Int, in range: Range<Int>, nesting: Int) -> Int {
        let firstIndent = Self.indent(of: lines[index])
        var parts: [String] = []
        var cursor = index
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if cursor > index, Self.indent(of: raw) != firstIndent { break }
            if cursor > index, Self.listItem(raw) != nil { break }
            parts.append(trimmed)
            cursor += 1
        }
        var text = parts.joined(separator: " ")
        var literalFollows = false
        if text.hasSuffix("::") {
            literalFollows = true
            text = text == "::" ? "" : (text.hasSuffix(" ::") ? String(text.dropLast(3)) : String(text.dropLast()))
        }
        if !text.isEmpty {
            if !list.isEmpty, firstIndent > 0 {
                let frame = list[list.count - 1]
                writer.listContinuation(depth: list.count - 1, markerLength: frame.markerLength, inline(text))
            } else {
                list.removeAll()
                writer.paragraph(inline(text))
            }
        }
        guard literalFollows else { return cursor }
        // The literal block is the indented block after the paragraph (after a blank line).
        var start = cursor
        while start < range.upperBound, isBlank(start) { start += 1 }
        guard start < range.upperBound, Self.indent(of: lines[start]) > firstIndent else { return cursor }
        let (block, next) = indentedBlock(after: start - 1, deeperThan: firstIndent, in: range)
        writer.codeBlock(block)
        return next
    }

    // MARK: Fields and lists

    private static func fieldItem(_ trimmed: String) -> (name: String, body: String)? {
        guard trimmed.hasPrefix(":"), !trimmed.hasPrefix("::") else { return nil }
        var index = trimmed.index(after: trimmed.startIndex)
        var escaped = false
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped { escaped = false } else if character == "\\" { escaped = true }
            else if character == ":" {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<index])
                let after = trimmed.index(after: index)
                guard !name.isEmpty, after == trimmed.endIndex || trimmed[after] == " " else { return nil }
                return (name, trimmed[after...].trimmingCharacters(in: .whitespaces))
            }
            index = trimmed.index(after: index)
        }
        return nil
    }

    private mutating func fieldItem(_ field: (name: String, body: String), at index: Int, in range: Range<Int>) -> Int {
        let (block, next) = indentedBlock(after: index, deeperThan: Self.indent(of: lines[index]), in: range)
        let body = ([field.body] + block.map { $0.trimmingCharacters(in: .whitespaces) }).filter { !$0.isEmpty }.joined(separator: " ")
        var result = MarkupInlineResult(text: field.name + ": ", decorations: [
            .init(range: NSRange(location: 0, length: (field.name + ":").utf16.count), style: .definitionTerm)
        ])
        let rendered = inline(body)
        result.decorations += rendered.decorations.map {
            .init(range: NSRange(location: $0.range.location + result.text.utf16.count, length: $0.range.length), style: $0.style)
        }
        result.text += rendered.text
        result.omitted.add(rendered.omitted)
        writer.line(result)
        return next
    }

    private struct Item {
        let indent: Int
        let ordered: Bool
        let number: Int?
        let text: String
        let markerLength: Int
    }

    private static func listItem(_ raw: String) -> Item? {
        let indent = Self.indent(of: raw)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        if "*-+\u{2022}\u{2023}\u{2043}".contains(first), trimmed.dropFirst().first == " " {
            // `--` and `---` lines are transitions or dashes, not bullets.
            return Item(indent: indent, ordered: false, number: nil, text: trimmed.dropFirst().trimmingCharacters(in: .whitespaces), markerLength: 2)
        }
        // Enumerators: `1.`, `1)`, `(1)`, `a.`, `#.`
        var body = Substring(trimmed)
        var parenthesized = false
        if body.hasPrefix("(") { body = body.dropFirst(); parenthesized = true }
        let token = body.prefix(while: { $0.isLetter || $0.isNumber || $0 == "#" })
        guard !token.isEmpty, token.count <= 4 || token == "#" else { return nil }
        let after = body.dropFirst(token.count)
        guard after.hasPrefix(". ") && !parenthesized || after.hasPrefix(") ") || after.hasPrefix(".") && after.count == 1 else { return nil }
        // Letters and roman numerals must be a single letter to avoid taking ordinary sentences.
        let number = Int(token)
        if number == nil, token != "#", token.count > 1, !token.allSatisfy({ "ivxlcdmIVXLCDM".contains($0) }) { return nil }
        if number == nil, token != "#", token.count == 1, !(token.first!.isLetter) { return nil }
        let text = String(after.dropFirst(after.hasPrefix(".") && after.count == 1 ? 1 : 2)).trimmingCharacters(in: .whitespaces)
        return Item(indent: indent, ordered: true, number: number, text: text, markerLength: token.count + 2)
    }

    private mutating func listItem(_ item: Item, at index: Int, in range: Range<Int>) -> Int {
        while let top = list.last, item.indent < top.indent { list.removeLast() }
        if let top = list.last, top.indent == item.indent {
            if top.ordered != item.ordered { list[list.count - 1] = ListFrame(indent: item.indent, ordered: item.ordered, counter: 0, markerLength: item.markerLength) }
        } else if list.count < 16 {
            list.append(ListFrame(indent: item.indent, ordered: item.ordered, counter: 0, markerLength: item.markerLength))
        }
        let depth = list.count - 1
        list[depth].counter = item.ordered ? (item.number ?? list[depth].counter + 1) : 0
        // Item text: this line and following lines indented to the item's text.
        var parts = [item.text]
        var cursor = index + 1
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard Self.indent(of: raw) > item.indent, Self.listItem(raw) == nil else { break }
            parts.append(trimmed)
            cursor += 1
        }
        let marker = item.ordered ? "\(list[depth].counter)." : ["\u{2022}", "\u{25E6}", "\u{25AA}"][min(depth, 2)]
        list[depth].markerLength = marker.count + 1
        writer.listItem(marker: marker, depth: depth, inline(parts.joined(separator: " ")))
        return cursor
    }

    // MARK: Explicit markup and directives

    private mutating func explicitMarkup(at index: Int, in range: Range<Int>, nesting: Int) -> Int {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let rest = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        let (block, next) = indentedBlock(after: index, deeperThan: 0, in: range)
        // Targets and substitution definitions carry no text of their own.
        if rest.hasPrefix("_") || rest.hasPrefix("|") || rest.hasPrefix("__") { return next }
        // Footnote and citation definitions: `.. [1] text`.
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let label = String(rest[...close])
            let body = ([String(rest[rest.index(after: close)...])] + block).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            writer.paragraph(inline(label + " " + body.joined(separator: " ")))
            return next
        }
        // Directive: `.. name:: arguments`.
        if let marker = rest.range(of: "::"), !rest[..<marker.lowerBound].contains(" ") || rest[..<marker.lowerBound].allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" || $0 == ":" || $0 == "+" }) {
            let name = String(rest[..<marker.lowerBound])
            let arguments = String(rest[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
            directive(name: name.lowercased(), arguments: arguments, content: block, nesting: nesting)
            return next
        }
        // Anything else is a comment, shown dimmed.
        writer.dimmedLine(trimmed, grouped: false)
        for line in block where !line.isEmpty { writer.dimmedLine(line) }
        return next
    }

    /// The directive's option lines (`:name: value`) and its body, split at the first blank line.
    private static func splitOptions(_ content: [String]) -> (options: [String], body: [String]) {
        var options: [String] = []
        var cursor = 0
        while cursor < content.count, content[cursor].hasPrefix(":") { options.append(content[cursor]); cursor += 1 }
        while cursor < content.count, content[cursor].isEmpty { cursor += 1 }
        return (options, Array(content[cursor...]))
    }

    private mutating func directive(name: String, arguments: String, content: [String], nesting: Int) {
        list.removeAll()
        let (options, body) = Self.splitOptions(content)
        if let kind = Self.admonitionKinds[name] {
            // Text on the directive line and an immediately following line form one paragraph.
            let continuesArguments = content.first.map { !$0.isEmpty } ?? false
            let lines = arguments.isEmpty ? body : (continuesArguments ? [arguments] + body : [arguments, ""] + body)
            writer.admonition(kind, body: Self.paragraphs(of: lines).map { inline($0) })
            return
        }
        switch name {
        case "code-block", "sourcecode", "code", "parsed-literal", "highlight-code":
            writer.codeBlock(body)
        case "math":
            let tex = (arguments.isEmpty ? [] : [arguments]) + body
            writer.mathBlock(tex.joined(separator: "\n"))
        case "image", "figure":
            if let kind = OmittedResourceKind.image(destination: arguments) { writer.noteOmitted(kind) }
            writer.dimmedLine(arguments, grouped: false)
            if name == "figure" { for paragraph in Self.paragraphs(of: body) { writer.paragraph(inline(paragraph), styles: [.italic]) } }
        case "include", "literalinclude", "raw", "csv-table-file":
            // Shown as text and never followed or emitted.
            if name == "include" || name == "literalinclude" { writer.noteOmitted(.linkedFile) }
            writer.dimmedLine(".. " + name + ":: " + arguments, grouped: false)
        case "toctree":
            for entry in body where !entry.isEmpty && !entry.hasPrefix(":") { writer.dimmedLine(entry) }
        case "list-table": listTable(body, headerRows: options)
        case "csv-table": csvTable(arguments: arguments, body: body)
        case "admonition", "topic", "sidebar", "epigraph", "pull-quote", "highlights", "blockquote":
            if !arguments.isEmpty { writer.paragraph(inline(arguments), styles: [.bold]) }
            writer.quote(Self.paragraphs(of: body).map { inline($0) })
        default:
            if Self.silentDirectives.contains(name) { return }
            // Unknown directives are shown, never run: the directive line, then its text.
            writer.dimmedLine(".. " + name + ":: " + arguments, grouped: false)
            for paragraph in Self.paragraphs(of: body) { writer.paragraph(inline(paragraph)) }
        }
    }

    // MARK: Tables

    private mutating func listTable(_ body: [String], headerRows options: [String]) {
        var rows: [[String]] = []
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("* -") || line.hasPrefix("*  -") {
                rows.append([String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)])
            } else if trimmed.hasPrefix("- "), !rows.isEmpty {
                rows[rows.count - 1].append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty, var last = rows.last, var cell = last.popLast() {
                cell += " " + trimmed
                last.append(cell)
                rows[rows.count - 1] = last
            }
        }
        let headerCount = options.compactMap { option -> Int? in
            guard option.hasPrefix(":header-rows:") else { return nil }
            return Int(option.dropFirst(":header-rows:".count).trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        for (position, row) in rows.enumerated() { writer.tableRow(row.map { inline($0) }, header: position < headerCount) }
    }

    private mutating func csvTable(arguments: String, body: [String]) {
        for line in body where !line.isEmpty {
            writer.tableRow(Self.csvCells(line).map { inline($0) }, header: false)
        }
    }

    private static func csvCells(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" { quoted.toggle(); continue }
            if character == ",", !quoted { cells.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(character)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private mutating func gridTable(at index: Int, in range: Range<Int>) -> Int {
        // Rows above a `+===+` border are the header; every `|` line is one row of cells.
        var cursor = index
        var pending: [[String]] = []
        var headerCount = 0
        while cursor < range.upperBound {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("+") || trimmed.hasPrefix("|") else { break }
            if trimmed.hasPrefix("+") {
                if trimmed.hasPrefix("+=") { headerCount = pending.count }
            } else {
                var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                pending.append(cells)
            }
            cursor += 1
        }
        for (position, row) in pending.enumerated() { writer.tableRow(row.map { inline($0) }, header: position < headerCount) }
        return max(cursor, index + 1)
    }

    private mutating func simpleTable(at index: Int, in range: Range<Int>) -> Int {
        // Columns are the runs of `=` in the border; rows are lines until the closing border.
        var columns: [(Int, Int)] = []
        var position = 0
        let characters = Array(lines[index])
        while position < characters.count {
            if characters[position] == "=" {
                let start = position
                while position < characters.count, characters[position] == "=" { position += 1 }
                columns.append((start, position))
            } else { position += 1 }
        }
        var cursor = index + 1
        var borders = 1
        while cursor < range.upperBound, borders < 3 {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("="), trimmed.allSatisfy({ $0 == "=" || $0 == " " }) { borders += 1; cursor += 1; continue }
            if trimmed.isEmpty, borders >= 2 { break }
            let characters = Array(line)
            let cells = columns.enumerated().map { offset, column -> String in
                let end = offset == columns.count - 1 ? characters.count : columns[offset + 1].0
                guard column.0 < characters.count else { return "" }
                return String(characters[column.0..<min(end, characters.count)]).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { writer.tableRow(cells.map { inline($0) }, header: borders == 1) }
            cursor += 1
        }
        return cursor
    }
}
