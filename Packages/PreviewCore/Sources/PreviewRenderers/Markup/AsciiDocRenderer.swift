import Foundation

/// A structural reading of AsciiDoc for the Rendered and Contents views: section titles,
/// paragraphs, nested bullet/ordered/check lists, description lists, listing and literal blocks,
/// quotes, admonitions, simple tables and inline emphasis. `include::` and `image::` lines are
/// shown as dimmed text and never followed; attribute entries are shown as dimmed lines and
/// never substituted; passthrough blocks are shown as code, never emitted as markup.
struct AsciiDocRenderer {
    private struct ListState {
        var ordered: Bool
        var counter: Int
    }

    private let lines: [String]
    private var writer: MarkupBlockWriter
    private var attributes: [String] = []
    private var attributeLine: String?
    private var blockTitle: String?
    private var lists: [Int: ListState] = [:]
    private var lastItem: (depth: Int, markerLength: Int)?
    private var attachNextToItem = false
    private var sawFirstBlock = false

    private static let maximumNesting = 8
    private static let admonitions: [String: MarkupAlertKind] = [
        "NOTE": .note, "TIP": .tip, "IMPORTANT": .important, "WARNING": .warning, "CAUTION": .caution
    ]

    static func render(_ source: String, limits: MarkupBuilder.Limits) -> SafeMarkdownDocument? {
        guard source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        let lines = MarkupLines.split(source)
        guard lines.count <= 20_000 else { return nil }
        var renderer = AsciiDocRenderer(lines: lines, writer: MarkupBlockWriter(limits: limits))
        renderer.parse(0..<lines.count, nesting: 0)
        return renderer.writer.finish { text in
            var scratch = MarkupFootnotes()
            return MarkupDialectInline.render(text, dialect: .asciidoc, footnotes: &scratch)
        }
    }

    private init(lines: [String], writer: MarkupBlockWriter) {
        self.lines = lines
        self.writer = writer
    }

    private mutating func inline(_ text: String) -> MarkupInlineResult {
        MarkupDialectInline.render(text, dialect: .asciidoc, footnotes: &writer.footnotes)
    }

    // MARK: Block loop

    private mutating func parse(_ range: Range<Int>, nesting: Int) {
        var index = range.lowerBound
        while index < range.upperBound {
            guard !writer.isOverflowed else { return }
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                attachNextToItem = false
                continue
            }
            // Line comment (block comments are delimited blocks).
            if trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") {
                writer.dimmedLine(trimmed)
                index += 1
                continue
            }
            // Attribute entry: `:name: value`.
            if trimmed.hasPrefix(":"), trimmed.dropFirst().contains(":"), !trimmed.hasPrefix(": "), Self.isAttributeEntry(trimmed) {
                writer.dimmedLine(trimmed)
                index += 1
                continue
            }
            // Block attribute line: `[source,swift]`, `[NOTE]`, `[cols="1,2"]`.
            if raw.first != " ", raw.first != "\t", trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[["), !trimmed.contains("](") {
                attributeLine = trimmed
                attributes = Self.positionalAttributes(trimmed)
                index += 1
                continue
            }
            if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") { index += 1; continue } // an anchor
            // Block title: `.Title`
            if trimmed.hasPrefix("."), trimmed.count > 1, let second = trimmed.dropFirst().first, second != ".", second != " " {
                blockTitle = String(trimmed.dropFirst())
                index += 1
                continue
            }
            if let delimiter = Self.delimiter(trimmed) {
                index = delimited(delimiter, at: index, in: range, nesting: nesting)
                resetBlockContext()
                continue
            }
            if let (level, title) = Self.sectionTitle(trimmed) {
                lists.removeAll()
                lastItem = nil
                writer.heading(level: level, inline(title))
                emitFirstBlockExtras(isDocumentTitle: !sawFirstBlock && level == 1, from: &index)
                sawFirstBlock = true
                resetBlockContext()
                index += 1
                continue
            }
            sawFirstBlock = true
            if trimmed == "'''" { writer.rule(); index += 1; resetBlockContext(); continue }
            if trimmed == "<<<" || trimmed == "toc::[]" { index += 1; continue }
            if trimmed.hasPrefix("include::") {
                writer.noteOmitted(.linkedFile)
                writer.dimmedLine(trimmed, grouped: false)
                index += 1
                resetBlockContext()
                continue
            }
            if trimmed.hasPrefix("image::") {
                if let kind = OmittedResourceKind.image(destination: Self.imageTarget(trimmed)) { writer.noteOmitted(kind) }
                writer.dimmedLine(Self.imageText(trimmed), grouped: false)
                index += 1
                resetBlockContext()
                continue
            }
            if trimmed == "+" { attachNextToItem = lastItem != nil; index += 1; continue }
            if trimmed.hasPrefix("|===") { index = table(at: index, in: range); resetBlockContext(); continue }
            if let item = Self.listItem(raw) {
                index = listItem(item, at: index, in: range)
                continue
            }
            if let (term, definition) = Self.descriptionItem(trimmed) {
                index = descriptionItem(term: term, definition: definition, at: index, in: range)
                continue
            }
            if let (kind, rest) = Self.admonition(trimmed) {
                let (text, next) = paragraphText(startingAt: index, firstLine: rest, in: range)
                emitBlockTitle()
                writer.admonition(kind, body: [inline(text)])
                index = next
                resetBlockContext()
                continue
            }
            // Literal paragraph: lines indented by a space.
            if raw.first == " " || raw.first == "\t" {
                var literal: [String] = []
                var cursor = index
                while cursor < range.upperBound, lines[cursor].first == " " || lines[cursor].first == "\t" {
                    literal.append(String(lines[cursor].dropFirst()))
                    cursor += 1
                }
                emitBlockTitle()
                writer.codeBlock(literal)
                index = cursor
                resetBlockContext()
                continue
            }
            let (text, next) = paragraphText(startingAt: index, firstLine: trimmed, in: range)
            paragraph(text)
            index = next
        }
    }

    private mutating func resetBlockContext() {
        attributes = []
        attributeLine = nil
        blockTitle = nil
        lists.removeAll()
        lastItem = nil
        attachNextToItem = false
    }

    private mutating func emitBlockTitle() {
        guard let title = blockTitle else { return }
        blockTitle = nil
        writer.paragraph(inline(title), styles: [.bold])
    }

    /// Author and revision lines directly under the document title.
    private mutating func emitFirstBlockExtras(isDocumentTitle: Bool, from index: inout Int) {
        guard isDocumentTitle else { return }
        var cursor = index + 1
        var count = 0
        while cursor < lines.count, count < 2 {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix(":"), !trimmed.hasPrefix("//"), Self.sectionTitle(trimmed) == nil else { break }
            writer.line(inline(trimmed), styles: [.centered])
            cursor += 1
            count += 1
        }
        index = cursor - 1
    }

    // MARK: Paragraphs

    /// The reflowed text of the paragraph starting at `index`, and the index after it.
    private func paragraphText(startingAt index: Int, firstLine: String, in range: Range<Int>) -> (String, Int) {
        var parts = [firstLine.hasSuffix(" +") ? String(firstLine.dropLast(2)) : firstLine]
        var cursor = index + 1
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || Self.startsBlock(trimmed, raw: raw) { break }
            parts.append(trimmed.hasSuffix(" +") ? String(trimmed.dropLast(2)) : trimmed)
            cursor += 1
        }
        return (parts.joined(separator: " "), cursor)
    }

    private mutating func paragraph(_ text: String) {
        emitBlockTitle()
        let style = attributes.first?.lowercased()
        let result = inline(text)
        switch style {
        case "quote", "verse": writer.quote([result])
        case "literal", "listing", "source": writer.codeBlock([text])
        case "stem", "latexmath": writer.mathBlock(text)
        default:
            if attachNextToItem, let item = lastItem {
                writer.listContinuation(depth: item.depth, markerLength: item.markerLength, result)
            } else {
                writer.paragraph(result)
            }
        }
        resetBlockContext()
    }

    /// Whether a line begins something other than paragraph text, ending the paragraph above it.
    private static func startsBlock(_ trimmed: String, raw: String) -> Bool {
        if raw.first != " ", raw.first != "\t", trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.contains("](") { return true }
        if delimiter(trimmed) != nil || sectionTitle(trimmed) != nil || trimmed.hasPrefix("|===") { return true }
        if listItem(raw) != nil || descriptionItem(trimmed) != nil { return true }
        if trimmed == "+" || trimmed.hasPrefix("//") || trimmed.hasPrefix("include::") || trimmed.hasPrefix("image::") { return true }
        return false
    }

    // MARK: Lists

    private struct Item {
        let depth: Int
        let ordered: Bool
        let explicitNumber: Int?
        let text: String
    }

    private static func listItem(_ raw: String) -> Item? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        if first == "*" || first == "-" || first == "." {
            let run = trimmed.prefix(while: { $0 == first })
            guard run.count <= 6, trimmed.dropFirst(run.count).first == " " else { return nil }
            // A lone hyphen is a one-level bullet; `*` and `.` runs give the nesting depth.
            if first == "-" && run.count > 1 { return nil }
            return Item(depth: run.count - 1, ordered: first == ".", explicitNumber: nil,
                        text: trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces))
        }
        if first.isASCII, first.isNumber {
            let digits = trimmed.prefix(while: { $0.isASCII && $0.isNumber })
            let rest = trimmed.dropFirst(digits.count)
            if digits.count <= 6, rest.hasPrefix(". ") || rest.hasPrefix(") "), let number = Int(digits) {
                return Item(depth: 0, ordered: true, explicitNumber: number, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        if trimmed.hasPrefix("<"), let close = trimmed.firstIndex(of: ">"), trimmed[trimmed.index(after: trimmed.startIndex)..<close].allSatisfy(\.isNumber),
           trimmed[trimmed.index(after: close)...].hasPrefix(" ") {
            return Item(depth: 0, ordered: false, explicitNumber: nil, text: trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private mutating func listItem(_ item: Item, at index: Int, in range: Range<Int>) -> Int {
        emitBlockTitle()
        attributes = []
        // Forget deeper levels, and levels whose kind changed.
        for depth in lists.keys where depth > item.depth { lists[depth] = nil }
        var state = lists[item.depth] ?? ListState(ordered: item.ordered, counter: 0)
        if state.ordered != item.ordered { state = ListState(ordered: item.ordered, counter: 0) }
        state.counter = item.explicitNumber ?? state.counter + 1
        lists[item.depth] = state
        var text = item.text
        var taskDone: Bool?
        if !item.ordered, text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { taskDone = true; text = String(text.dropFirst(4)) }
        else if !item.ordered, text.hasPrefix("[ ] ") { taskDone = false; text = String(text.dropFirst(4)) }
        // Continuation lines of the item text.
        var parts = [text]
        var cursor = index + 1
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || Self.startsBlock(trimmed, raw: raw) { break }
            parts.append(trimmed)
            cursor += 1
        }
        let marker: String
        if let done = taskDone { marker = done ? "\u{2611}" : "\u{2610}" }
        else if item.ordered { marker = "\(state.counter)." }
        else { marker = ["\u{2022}", "\u{25E6}", "\u{25AA}"][min(item.depth, 2)] }
        writer.listItem(marker: marker, depth: item.depth, inline(parts.joined(separator: " ")), taskDone: taskDone)
        lastItem = (item.depth, marker.count + 1)
        return cursor
    }

    private static func descriptionItem(_ trimmed: String) -> (String, String)? {
        guard let range = trimmed.range(of: ":: ") ?? (trimmed.hasSuffix("::") ? trimmed.range(of: "::", options: .backwards) : nil) else { return nil }
        let term = String(trimmed[..<range.lowerBound])
        guard !term.isEmpty, !term.hasPrefix(":"), !term.contains("::") else { return nil }
        return (term, String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private mutating func descriptionItem(term: String, definition: String, at index: Int, in range: Range<Int>) -> Int {
        emitBlockTitle()
        var parts = definition.isEmpty ? [] : [definition]
        var cursor = index + 1
        while cursor < range.upperBound {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || Self.startsBlock(trimmed, raw: raw) { break }
            parts.append(trimmed)
            cursor += 1
        }
        writer.line(inline(term), styles: [.definitionTerm])
        if !parts.isEmpty { writer.line(inline(parts.joined(separator: " ")), styles: [.indent(1)]) }
        return cursor
    }

    // MARK: Delimited blocks

    private static func delimiter(_ trimmed: String) -> String? {
        if trimmed == "--" { return "--" }
        guard trimmed.count >= 4, let first = trimmed.first, "-.=*_+/".contains(first), trimmed.allSatisfy({ $0 == first }) else { return nil }
        return trimmed
    }

    private func closing(of delimiter: String, after index: Int, in range: Range<Int>) -> Int? {
        var cursor = index + 1
        while cursor < range.upperBound {
            if lines[cursor].trimmingCharacters(in: .whitespaces) == delimiter { return cursor }
            cursor += 1
        }
        return nil
    }

    private mutating func delimited(_ delimiter: String, at index: Int, in range: Range<Int>, nesting: Int) -> Int {
        let close = closing(of: delimiter, after: index, in: range)
        let bodyRange = (index + 1)..<(close ?? range.upperBound)
        let body = Array(lines[bodyRange])
        let next = close.map { $0 + 1 } ?? range.upperBound
        let kind = attributes.first?.lowercased() ?? ""
        emitBlockTitle()
        switch delimiter.first {
        case "-", ".":
            if kind == "stem" || kind == "latexmath" { writer.mathBlock(body.joined(separator: "\n")) }
            else { writer.codeBlock(body) }
        case "+":
            // Passthrough is never emitted as markup; stem blocks are math, everything else is shown as code.
            if kind == "stem" || kind == "latexmath" || kind == "asciimath" { writer.mathBlock(body.joined(separator: "\n")) }
            else { writer.codeBlock(body) }
        case "/":
            for line in body { writer.dimmedLine(line) }
        case "_":
            writer.quote(paragraphs(of: body))
        default:
            // Example, sidebar and open blocks hold ordinary blocks; an admonition style turns them into one.
            if let admonition = Self.admonitions[attributes.first ?? ""] {
                writer.admonition(admonition, body: paragraphs(of: body))
            } else if nesting < Self.maximumNesting {
                let saved = (attributes, attributeLine)
                attributes = []
                attributeLine = nil
                parse(bodyRange, nesting: nesting + 1)
                (attributes, attributeLine) = saved
            }
        }
        return next
    }

    /// Paragraphs of a block body (blank-line separated, reflowed), as inline results.
    private mutating func paragraphs(of body: [String]) -> [MarkupInlineResult] {
        var result: [MarkupInlineResult] = []
        var current: [String] = []
        func flush(_ renderer: inout AsciiDocRenderer) {
            if !current.isEmpty { result.append(renderer.inline(current.joined(separator: " "))); current = [] }
        }
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(&self) } else { current.append(trimmed) }
        }
        flush(&self)
        return result
    }

    // MARK: Tables

    private mutating func table(at index: Int, in range: Range<Int>) -> Int {
        let close = closing(of: "|===", after: index, in: range)
        let body = Array(lines[(index + 1)..<(close ?? range.upperBound)])
        let next = close.map { $0 + 1 } ?? range.upperBound
        emitBlockTitle()
        var rows: [[String]] = []
        var singleCells: [String] = []
        var multiCell = false
        var firstGroupEnded = false
        var headerByBlankLine = false
        for line in body.prefix(10_000) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { if rows.count == 1 && !firstGroupEnded { headerByBlankLine = true; firstGroupEnded = true }; continue }
            if trimmed.hasPrefix("|") || trimmed.contains(" |") {
                let cells = Self.cells(of: trimmed)
                if cells.count > 1 { multiCell = true; rows.append(cells) } else { singleCells.append(contentsOf: cells) }
            } else if !singleCells.isEmpty {
                singleCells[singleCells.count - 1] += " " + trimmed
            }
        }
        if !multiCell, !singleCells.isEmpty {
            let columns = max(Self.columnCount(attributeLine) ?? 1, 1)
            rows = stride(from: 0, to: singleCells.count, by: columns).map { Array(singleCells[$0..<min($0 + columns, singleCells.count)]) }
        }
        let headerRequested = attributeLine?.lowercased().contains("header") == true || headerByBlankLine
        for (position, row) in rows.enumerated() {
            writer.tableRow(row.map { inline($0) }, header: headerRequested && position == 0)
        }
        resetBlockContext()
        return next
    }

    private static func cells(of line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "|" { cells.append(current); current = ""; continue }
            current.append(character)
        }
        cells.append(current)
        if !line.hasPrefix("|") { return cells.map { $0.trimmingCharacters(in: .whitespaces) } }
        return cells.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func columnCount(_ attributeLine: String?) -> Int? {
        guard let line = attributeLine, let range = line.range(of: "cols=") else { return nil }
        let rest = line[range.upperBound...].drop(while: { $0 == "\"" || $0 == "'" })
        let spec = rest.prefix(while: { $0 != "\"" && $0 != "'" && $0 != "]" })
        if let star = spec.firstIndex(of: "*"), let count = Int(spec[..<star]) { return count }
        return spec.split(separator: ",").count
    }

    // MARK: Small recognizers

    private static func isAttributeEntry(_ trimmed: String) -> Bool {
        let body = trimmed.dropFirst().drop(while: { $0 == "!" })
        guard let colon = body.firstIndex(of: ":") else { return false }
        let name = body[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "!"))
        return !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func positionalAttributes(_ line: String) -> [String] {
        let inner = String(line.dropFirst().dropLast())
        return inner.split(separator: ",").map { part in
            var value = part.trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(where: { $0 == "#" || $0 == "." || $0 == "%" }) { value = String(value[..<hash]) }
            return value
        }
    }

    private static func sectionTitle(_ trimmed: String) -> (Int, String)? {
        let marks = trimmed.prefix(while: { $0 == "=" })
        guard (1...6).contains(marks.count), trimmed.dropFirst(marks.count).first == " " else { return nil }
        let title = trimmed.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (marks.count, title)
    }

    private static func admonition(_ trimmed: String) -> (MarkupAlertKind, String)? {
        guard let colon = trimmed.firstIndex(of: ":"), colon != trimmed.startIndex,
              let kind = admonitions[String(trimmed[..<colon])],
              trimmed[trimmed.index(after: colon)...].hasPrefix(" ") else { return nil }
        return (kind, trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    /// The target of an `image::target[alt]` line: the text between the macro name and the first bracket.
    private static func imageTarget(_ trimmed: String) -> String {
        String(trimmed.dropFirst("image::".count).prefix(while: { $0 != "[" }))
    }

    private static func imageText(_ trimmed: String) -> String {
        guard let bracket = trimmed.firstIndex(of: "["), trimmed.hasSuffix("]") else { return trimmed }
        let alt = trimmed[trimmed.index(after: bracket)..<trimmed.index(before: trimmed.endIndex)]
            .split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return alt.isEmpty ? imageTarget(trimmed) : alt
    }
}
