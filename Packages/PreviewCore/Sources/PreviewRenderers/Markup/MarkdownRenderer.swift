import Foundation
import PreviewContracts

/// How the leading metadata block of Markdown text is shown. A file's own front matter is shown as written. The
/// adapters that convert another format (ebooks, saved web pages) write neutral field names and machine flags
/// instead, which they cannot localize: the renderer gives the fields localized labels and leaves the flags to
/// the status line.
enum MarkdownFrontMatterStyle: Equatable, Sendable {
    case verbatim
    case generated
}

/// The inert Markdown subset: ATX and setext headings, paragraphs, nested ordered/bullet/task
/// lists, block quotes and GitHub alerts, thematic breaks, pipe tables, fenced code (with
/// distinct math and diagram decorations), footnotes, YAML/TOML front matter and inline
/// emphasis, strikethrough, code, math and text links. It reads only already-concealed text.
///
/// Paragraph soft breaks reflow; explicit hard breaks and structural block lines retain their boundaries.
/// Lines that only carry syntax (fence markers, table separators, setext underlines, footnote definitions,
/// front-matter delimiters) produce no output line. HTML is literal and links never load.
struct MarkdownRenderer {
    private enum FenceKind { case code, math, diagram }
    private struct Fence {
        let marker: String
        let kind: FenceKind
        let language: SourceLanguageID?
        var lines: [String] = []
    }
    private struct ListLevel {
        let indent: Int
        let ordered: Bool
        var nextNumber: Int
        var markerLength: Int
    }
    private enum ListMarker {
        case bullet
        case ordered(number: Int, delimiter: Character)
    }

    private let lines: [String]
    private let frontMatterStyle: MarkdownFrontMatterStyle
    private var builder: MarkupBuilder
    private var footnotes = MarkupFootnotes()
    private var emittedLines = 0
    private var list: [ListLevel] = []
    private var tableOpen = false
    private var previousWasQuote = false
    /// The alert the quote lines just written belong to; nil for a plain quote.
    private var openAlert: MarkupAlertKind?
    /// The table whose rows are being written. Its decoration is added when the table ends, so it covers every row.
    private var openTable: OpenTable?
    private var tableContinues = false

    private struct OpenTable {
        let start: Int
        let hasHeader: Bool
        var end: Int
        var columns: [MarkupColumnAlignment] = []
    }

    private static let maximumFrontMatterLines = 200
    private static let ruleText = String(repeating: "\u{2500}", count: 24)
    private static let maximumFootnoteDefinitions = 1_000

    static func render(_ source: String, limits: MarkupBuilder.Limits,
                       frontMatter: MarkdownFrontMatterStyle = .verbatim) -> SafeMarkdownDocument? {
        guard !Task.isCancelled,
              source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        let lines = MarkupLines.split(source)
        guard !Task.isCancelled, lines.count <= 20_000 else { return nil }
        var renderer = MarkdownRenderer(lines: lines, builder: MarkupBuilder(limits: limits), frontMatterStyle: frontMatter)
        return renderer.run()
    }

    private init(lines: [String], builder: MarkupBuilder, frontMatterStyle: MarkdownFrontMatterStyle) {
        self.lines = lines
        self.builder = builder
        self.frontMatterStyle = frontMatterStyle
    }

    // MARK: Driver

    private mutating func run() -> SafeMarkdownDocument? {
        var index = frontMatter()
        let skipped = collectFootnoteDefinitions(from: index)
        var fence: Fence?
        while index < lines.count {
            guard !Task.isCancelled, !builder.isOverflowed else { return nil }
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open.marker) {
                    emitFence(open)
                    fence = nil
                } else { fence?.lines.append(raw) }
                index += 1
                continue
            }
            if skipped.contains(index) { index += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                resetBlockState()
                let marker = String(trimmed.prefix(3))
                let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let word = info.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "{" }).first.map(String.init) ?? ""
                fence = Fence(marker: marker, kind: word == "math" ? .math : word == "mermaid" ? .diagram : .code,
                              language: MarkupCodeBlock.recognizedLanguage(inFenceInfo: info))
                index += 1
                continue
            }
            index = renderBlock(at: index)
        }
        if let open = fence { emitFence(open) }
        closeTable()
        emitFootnotes()
        guard !Task.isCancelled else { return nil }
        return builder.finish()
    }

    private mutating func resetBlockState() {
        list.removeAll(keepingCapacity: true)
        tableOpen = false
        previousWasQuote = false
        closeTable()
    }

    // MARK: Output helpers

    /// Starts an output line; lines are joined by newlines, so the first one needs no separator.
    private mutating func beginLine() -> Int {
        if emittedLines > 0 { builder.newline() }
        emittedLines += 1
        return builder.length
    }

    private mutating func inline(_ text: String) -> MarkupInlineResult {
        MarkdownInline.render(text, footnotes: &footnotes)
    }

    private mutating func emitEmptyLine() { _ = beginLine() }

    // MARK: Front matter

    /// Renders a leading YAML (`---`) or TOML (`+++`) block as compact key/value lines.
    /// Returns the index of the first line after it, or 0 when there is none. For converted documents
    /// (`MarkdownFrontMatterStyle.generated`) the machine flags are not shown and the fields carry localized labels.
    private mutating func frontMatter() -> Int {
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces), first == "---" || first == "+++" else { return 0 }
        let isTOML = first == "+++"
        let limit = min(lines.count, Self.maximumFrontMatterLines)
        var close: Int?
        for candidate in 1..<max(limit, 1) {
            let value = lines[candidate].trimmingCharacters(in: .whitespaces)
            if value == first || (!isTOML && value == "...") { close = candidate; break }
        }
        guard let close else { return 0 }
        let body = Array(lines[1..<close])
        var entries = FrontMatterEntries.entries(from: body, isTOML: isTOML)
        // Two thematic breaks around prose are not metadata: a block needs at least one key.
        guard entries.isEmpty || entries.contains(where: { $0.key != nil }) else { return 0 }
        guard !entries.isEmpty else { return close + 1 }
        if frontMatterStyle == .generated {
            // Machine flags restate what the status line says in the reader's language, so they are not shown.
            entries.removeAll(where: FrontMatterFlags.isFlag)
            // A block that shows nothing leaves no empty line above the document either.
            guard !entries.isEmpty else { return firstContentLine(after: close) }
        }
        let blockStart = beginLine()
        for (position, entry) in entries.enumerated() {
            if position > 0 { builder.newline() }
            if let key = entry.key {
                builder.append(frontMatterLabel(for: key), style: .frontMatterKey)
                if !entry.value.isEmpty { builder.append(" " + entry.value) }
            } else {
                builder.append(entry.value)
            }
        }
        builder.decorate(.frontMatterBlock, from: blockStart)
        resetBlockState()
        // A blank line separates the metadata from the document body.
        if close + 1 < lines.count { emitEmptyLine() }
        return close + 1
    }

    /// The label of a front-matter key: the key and a colon as written, or for converted documents the localized
    /// label of an adapter field (which includes its own colon, so each language sets its punctuation).
    private func frontMatterLabel(for key: String) -> String {
        if frontMatterStyle == .generated, let field = DocumentFrontMatterField(rawValue: key) {
            return PreviewStrings.text(field.label)
        }
        return key + ":"
    }

    /// The index of the first line after `close` that is not blank.
    private func firstContentLine(after close: Int) -> Int {
        var index = close + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        return index
    }

    // MARK: Footnote definitions

    /// Collects `[^label]: text` definitions (with indented continuations) outside fences and
    /// returns the line indexes they occupy, so the main pass skips them.
    private mutating func collectFootnoteDefinitions(from start: Int) -> Set<Int> {
        var skipped = Set<Int>()
        var fenceMarker: String?
        var index = start
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker {
                if trimmed.hasPrefix(marker) { fenceMarker = nil }
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fenceMarker = String(trimmed.prefix(3)); index += 1; continue }
            if let (label, text) = Self.footnoteDefinition(raw), footnotes.definitionOrder.count < Self.maximumFootnoteDefinitions {
                skipped.insert(index)
                var parts = [text]
                var next = index + 1
                while next < lines.count {
                    let continuation = lines[next]
                    if continuation.trimmingCharacters(in: .whitespaces).isEmpty {
                        // A blank line continues the note only when an indented line follows.
                        guard next + 1 < lines.count, Self.isIndented(lines[next + 1]) else { break }
                        skipped.insert(next)
                        next += 1
                        continue
                    }
                    guard Self.isIndented(continuation) else { break }
                    skipped.insert(next)
                    parts.append(continuation.trimmingCharacters(in: .whitespaces))
                    next += 1
                }
                if footnotes.definitions[label] == nil {
                    footnotes.definitions[label] = parts.filter { !$0.isEmpty }.joined(separator: " ")
                    footnotes.definitionOrder.append(label)
                }
                index = next
                continue
            }
            index += 1
        }
        return skipped
    }

    private static func isIndented(_ line: String) -> Bool { line.hasPrefix("  ") || line.hasPrefix("\t") }

    private static func footnoteDefinition(_ line: String) -> (label: String, text: String)? {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return nil }
        let rest = line.dropFirst(leading)
        guard rest.hasPrefix("[^"), let close = rest.firstIndex(of: "]") else { return nil }
        let label = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<close])
        guard !label.isEmpty, !label.contains(where: { $0.isWhitespace }) else { return nil }
        let after = rest[rest.index(after: close)...]
        guard after.hasPrefix(":") else { return nil }
        return (label, after.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    private mutating func emitFootnotes() {
        footnotes.appendUnreferenced()
        guard !footnotes.isEmpty else { return }
        resetBlockState()
        if !builder.text.isEmpty, !builder.text.hasSuffix("\n") { emitEmptyLine() }
        let titleStart = beginLine()
        let title = PreviewStrings.text(.markupFootnotes)
        builder.append(title)
        let titleRange = NSRange(location: titleStart, length: title.utf16.count)
        builder.decorate(.heading(2), from: titleStart)
        builder.addHeading(level: 2, title: title, range: titleRange)
        var scratch = MarkupFootnotes()
        for (offset, text) in footnotes.texts.enumerated() {
            _ = beginLine()
            let label = MarkupFootnotes.superscript(offset + 1)
            builder.append(label, style: .footnoteLabel)
            builder.append(" ")
            // Notes are plain inline Markdown; references inside notes stay literal.
            builder.append(MarkdownInline.render(text, footnotes: &scratch))
        }
    }

    // MARK: Blocks

    /// Renders the block that starts at `index` and returns the index after the lines it consumed. A table ends with
    /// the first block that is not one of its rows.
    private mutating func renderBlock(at index: Int) -> Int {
        tableContinues = false
        let next = renderBlockBody(at: index)
        if !tableContinues { closeTable() }
        return next
    }

    private mutating func renderBlockBody(at index: Int) -> Int {
        let raw = lines[index]
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Blank lines keep their place but never end a list or a table by themselves.
            emitEmptyLine()
            tableOpen = false
            previousWasQuote = false
            return index + 1
        }
        // Display math: `$$` on its own line opens a block that a `$$` line closes.
        if trimmed == "$$" || (trimmed.hasPrefix("$$") && !trimmed.hasSuffix("$$") && trimmed.count > 2) {
            return renderDisplayMath(at: index)
        }
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
            resetBlockState()
            emitMathBlock(String(trimmed.dropFirst(2).dropLast(2)))
            return index + 1
        }
        if let consumed = renderTable(at: index) { return consumed }
        var quoteDepth = 0
        var content = Substring(raw)
        content = Self.stripQuotePrefix(content, depth: &quoteDepth)
        if quoteDepth > 0 {
            if paragraphContent(at: index, quoteDepth: quoteDepth) != nil {
                let paragraph = joinedParagraph(at: index, quoteDepth: quoteDepth)
                renderQuote(paragraph.text, depth: quoteDepth)
                return paragraph.next
            } else {
                renderQuote(String(content), depth: quoteDepth)
                return index + 1
            }
        }
        previousWasQuote = false
        if let heading = Self.atxHeading(String(content)) {
            resetBlockState()
            emitHeading(level: heading.level, text: heading.text)
            return index + 1
        }
        if Self.isThematicBreak(trimmed) {
            resetBlockState()
            let start = beginLine()
            builder.append(Self.ruleText)
            builder.decorate(.rule, from: start)
            return index + 1
        }
        if let item = Self.listItem(String(content)) {
            emitListItem(item)
            return index + 1
        }
        // Definition list (an extension syntax): a term line followed by `: definition` lines.
        if index + 1 < lines.count, Self.definitionText(lines[index + 1]) != nil, !trimmed.hasPrefix(":"), !Self.isIndented(raw) {
            resetBlockState()
            let term = inline(trimmed)
            let start = beginLine()
            builder.append(term)
            builder.decorate(.definitionTerm, from: start)
            var cursor = index + 1
            while cursor < lines.count, let definition = Self.definitionText(lines[cursor]) {
                let definitionStart = beginLine()
                builder.append(inline(definition))
                builder.decorate(.indent(1), from: definitionStart)
                cursor += 1
            }
            return cursor
        }
        // Setext heading: a paragraph line over a `===` or `---` underline.
        if index + 1 < lines.count, let level = Self.setextLevel(lines[index + 1]), !Self.isIndented(raw) {
            resetBlockState()
            emitHeading(level: level, text: trimmed)
            return index + 2
        }
        if paragraphContent(at: index) != nil {
            let paragraph = joinedParagraph(at: index)
            emitParagraph(paragraph.text, trimmed: paragraph.text)
            return paragraph.next
        } else {
            emitParagraph(raw, trimmed: trimmed)
            return index + 1
        }
    }

    // MARK: Headings, rules, paragraphs

    /// A paragraph can consume only ordinary prose, never a future structural block or another quote depth.
    /// Existing list continuations retain their own lines and decorations; this does not widen the block subset.
    private func paragraphContent(at index: Int, quoteDepth: Int? = nil) -> String? {
        guard let content = content(at: index, quoteDepth: quoteDepth) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !Self.isIndented(content), Self.atxHeading(content) == nil,
              !Self.isThematicBreak(trimmed), Self.listItem(content) == nil,
              !trimmed.hasPrefix("```"), !trimmed.hasPrefix("~~~"), !trimmed.hasPrefix("$$"),
              Self.footnoteDefinition(content) == nil, Self.definitionText(content) == nil else { return nil }
        if quoteDepth != nil, Self.alertKind(trimmed) != nil { return nil }
        let following = self.content(at: index + 1, quoteDepth: quoteDepth)
        if let following, Self.setextLevel(following) != nil || Self.definitionText(following) != nil { return nil }
        if trimmed.contains("|"), trimmed.hasPrefix("|") || following.map(Self.isDelimiterRow) == true { return nil }
        return content
    }

    private func content(at index: Int, quoteDepth: Int?) -> String? {
        guard lines.indices.contains(index) else { return nil }
        var depth = 0
        let content = Self.stripQuotePrefix(Substring(lines[index]), depth: &depth)
        guard depth == (quoteDepth ?? 0) else { return nil }
        return String(content)
    }

    /// Joining before inline parsing lets emphasis pair across a soft break. Input and source-line bounds have
    /// already been checked; inline scan/work bounds and the builder's output/decoration caps still apply.
    private func joinedParagraph(at index: Int, quoteDepth: Int? = nil) -> (text: String, next: Int) {
        var text = ""
        var cursor = index
        var separator = ""
        while !Task.isCancelled, let content = paragraphContent(at: cursor, quoteDepth: quoteDepth) {
            let line = Self.paragraphLine(content, hasFollowingLine: cursor + 1 < lines.count)
            text.append(separator)
            text.append(line.text)
            separator = line.hardBreak ? "\n" : " "
            cursor += 1
        }
        return (text, cursor)
    }

    /// Two trailing ASCII spaces or an unescaped terminal backslash request a hard break. An even backslash
    /// run remains literal, and a backslash at end of input has no following break to escape.
    private static func paragraphLine(_ raw: String, hasFollowingLine: Bool) -> (text: String, hardBreak: Bool) {
        let trailingSpaces = raw.reversed().prefix(while: { $0 == " " }).count
        var end = raw.endIndex
        var hardBreak = false
        if hasFollowingLine, trailingSpaces >= 2 {
            end = raw.index(end, offsetBy: -trailingSpaces)
            hardBreak = true
        } else if hasFollowingLine, raw.last == "\\",
                  raw.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 {
            end = raw.index(before: end)
            hardBreak = true
        }
        var body = raw[..<end]
        while body.first == " " || body.first == "\t" { body = body.dropFirst() }
        while body.last == " " || body.last == "\t" { body = body.dropLast() }
        return (String(body), hardBreak)
    }

    private mutating func emitHeading(level: Int, text: String) {
        let start = beginLine()
        let rendered = inline(text)
        builder.append(rendered)
        builder.decorate(.heading(level), from: start)
        builder.addHeading(level: level, title: rendered.text, range: NSRange(location: start, length: rendered.text.utf16.count))
    }

    private mutating func emitParagraph(_ raw: String, trimmed: String) {
        let continuation = !list.isEmpty && Self.isIndented(raw)
        if !continuation { resetBlockState() }
        let start = beginLine()
        builder.append(inline(continuation ? trimmed : raw))
        if continuation, let level = list.last {
            builder.decorate(.listContinuation(depth: list.count - 1, markerLength: level.markerLength), from: start)
        }
    }

    // MARK: Lists

    private static func listItem(_ line: String) -> (indent: Int, marker: ListMarker, text: String, markerLength: Int)? {
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            indent += line[index] == "\t" ? 4 : 1
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }
        let first = line[index]
        var marker: ListMarker
        var afterMarker: String.Index
        var markerLength: Int
        if first == "-" || first == "+" || first == "*" {
            afterMarker = line.index(after: index)
            marker = .bullet
            markerLength = 1
        } else if first.isASCII, first.isNumber {
            var digitsEnd = index
            while digitsEnd < line.endIndex, line[digitsEnd].isASCII, line[digitsEnd].isNumber { digitsEnd = line.index(after: digitsEnd) }
            let digits = line[index..<digitsEnd]
            guard digits.count <= 9, digitsEnd < line.endIndex, line[digitsEnd] == "." || line[digitsEnd] == ")",
                  let number = Int(digits) else { return nil }
            marker = .ordered(number: number, delimiter: line[digitsEnd])
            afterMarker = line.index(after: digitsEnd)
            markerLength = digits.count + 1
        } else { return nil }
        // The marker must be followed by a space or tab, or end the line.
        if afterMarker < line.endIndex {
            guard line[afterMarker] == " " || line[afterMarker] == "\t" else { return nil }
        }
        let text = line[afterMarker...].trimmingCharacters(in: .whitespaces)
        return (indent, marker, text, markerLength + 1)
    }

    private mutating func emitListItem(_ item: (indent: Int, marker: ListMarker, text: String, markerLength: Int)) {
        tableOpen = false
        while let top = list.last, item.indent < top.indent { list.removeLast() }
        let isOrdered: Bool
        var number = 0
        if case .ordered(let written, _) = item.marker { isOrdered = true; number = written } else { isOrdered = false }
        if let top = list.last, top.indent == item.indent {
            if top.ordered != isOrdered {
                list[list.count - 1] = ListLevel(indent: item.indent, ordered: isOrdered, nextNumber: number, markerLength: item.markerLength)
            }
        } else if list.count < 16 {
            list.append(ListLevel(indent: item.indent, ordered: isOrdered, nextNumber: number, markerLength: item.markerLength))
        }
        let depth = max(list.count - 1, 0)
        var level = list[depth]
        var markerText: String
        var taskDone: Bool?
        var text = item.text
        if isOrdered {
            let delimiter: Character
            if case .ordered(_, let value) = item.marker { delimiter = value } else { delimiter = "." }
            markerText = "\(level.nextNumber)\(delimiter)"
            level.nextNumber += 1
        } else {
            markerText = ["\u{2022}", "\u{25E6}", "\u{25AA}"][min(depth, 2)]
        }
        if let task = Self.taskState(text) {
            taskDone = task.done
            text = task.text
            markerText = task.done ? "\u{2611}" : "\u{2610}"
        }
        level.markerLength = markerText.count + 1
        list[depth] = level
        let start = beginLine()
        if let done = taskDone { builder.append(markerText, style: .taskMarker(done: done)) } else { builder.append(markerText) }
        builder.append(" ")
        builder.append(inline(text))
        builder.decorate(.listItem(depth: depth, markerLength: level.markerLength), from: start)
    }

    private static func taskState(_ text: String) -> (done: Bool, text: String)? {
        guard text.hasPrefix("["), text.count >= 3 else { return nil }
        let characters = Array(text.prefix(4))
        guard characters.count >= 3, characters[2] == "]" else { return nil }
        let done: Bool
        switch characters[1] {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        if characters.count > 3, !characters[3].isWhitespace { return nil }
        return (done, String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Quotes and alerts

    private static func stripQuotePrefix(_ line: Substring, depth: inout Int) -> Substring {
        var rest = line
        var spaces = 0
        while rest.first == " ", spaces < 3 { rest = rest.dropFirst(); spaces += 1 }
        while rest.first == ">" {
            depth += 1
            rest = rest.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            if depth >= 6 { break }
        }
        return depth > 0 ? rest : line
    }

    private mutating func renderQuote(_ content: String, depth: Int) {
        resetListAndTable()
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if !previousWasQuote, depth == 1, let kind = Self.alertKind(trimmed) {
            let start = beginLine()
            builder.append(Self.alertGlyph(kind) + " ")
            builder.append(Self.alertTitle(kind))
            builder.decorate(.quote, from: start)
            builder.decorate(.alertBar(kind), from: start)
            builder.decorate(.alertTitle(kind), from: start)
            openAlert = kind
            previousWasQuote = true
            return
        }
        // Only quote lines that directly follow an alert's title belong to it; any other quote starts plain.
        if !previousWasQuote { openAlert = nil }
        previousWasQuote = true
        let start = beginLine()
        if let heading = Self.atxHeading(content) {
            let rendered = inline(heading.text)
            builder.append(rendered)
            builder.addHeading(level: heading.level, title: rendered.text, range: NSRange(location: start, length: rendered.text.utf16.count))
            builder.decorate(.heading(heading.level), from: start)
        } else if let item = Self.listItem(content) {
            let marker: String
            switch item.marker {
            case .bullet: marker = "\u{2022}"
            case .ordered(let number, let delimiter): marker = "\(number)\(delimiter)"
            }
            builder.append(marker + " ")
            builder.append(inline(item.text))
        } else {
            builder.append(inline(content))
        }
        builder.decorate(.quote, from: start)
        if let alert = openAlert { builder.decorate(.alertBar(alert), from: start) }
        if depth > 1 { builder.decorate(.indent(depth - 1), from: start) }
    }

    private mutating func resetListAndTable() {
        list.removeAll(keepingCapacity: true)
        tableOpen = false
    }

    private static func alertKind(_ text: String) -> MarkupAlertKind? {
        guard text.hasPrefix("[!"), text.hasSuffix("]") else { return nil }
        return MarkupAlertKind(rawValue: text.dropFirst(2).dropLast().lowercased())
    }

    static func alertTitle(_ kind: MarkupAlertKind) -> String {
        switch kind {
        case .note: PreviewStrings.text(.markupAlertNote)
        case .tip: PreviewStrings.text(.markupAlertTip)
        case .important: PreviewStrings.text(.markupAlertImportant)
        case .warning: PreviewStrings.text(.markupAlertWarning)
        case .caution: PreviewStrings.text(.markupAlertCaution)
        }
    }

    static func alertGlyph(_ kind: MarkupAlertKind) -> String {
        switch kind {
        case .note: "\u{24D8}"
        case .tip: "\u{2726}"
        case .important: "\u{203C}"
        case .warning: "\u{26A0}"
        case .caution: "\u{2298}"
        }
    }

    // MARK: Headings and rules

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return nil }
        let rest = line.dropFirst(leading)
        let hashes = rest.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let afterHashes = rest.dropFirst(hashes)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }
        var text = afterHashes.trimmingCharacters(in: .whitespaces)
        // An optional closing run of hashes, separated by a space, is not part of the title.
        if let lastNonHash = text.lastIndex(where: { $0 != "#" }), lastNonHash != text.index(before: text.endIndex),
           text[lastNonHash] == " " || text[lastNonHash] == "\t" {
            text = text[...lastNonHash].trimmingCharacters(in: .whitespaces)
        } else if !text.isEmpty, text.allSatisfy({ $0 == "#" }) { text = "" }
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }

    /// The text of a `: definition` line, or nil when the line is not one.
    private static func definitionText(_ line: String) -> String? {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return nil }
        let rest = line.dropFirst(leading)
        guard rest.hasPrefix(": ") else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func setextLevel(_ line: String) -> Int? {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return nil }
        let rest = line.dropFirst(leading).trimmingCharacters(in: .whitespaces)
        guard let first = rest.first, first == "=" || first == "-", rest.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    // MARK: Tables

    private static func cells(of line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; current.append(character); continue }
            if character == "|" { cells.append(current); current = ""; continue }
            current.append(character)
        }
        cells.append(current)
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("|"), !cells.isEmpty { cells.removeFirst() }
        if trimmedLine.hasSuffix("|"), !trimmedLine.hasSuffix("\\|"), !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
    }

    private static func isDelimiterRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        let cells = Self.cells(of: trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// A pipe-table row. A table begins at a line starting with `|` (as before) or at a line with
    /// pipes over a delimiter row; later pipe lines continue it. Returns nil when `index` is not a row.
    private mutating func renderTable(at index: Int) -> Int? {
        let raw = lines[index]
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        if Self.isDelimiterRow(trimmed) {
            guard tableOpen else { return nil }
            // The delimiter row writes no text; its colons choose how the columns are aligned.
            tableOpen = true
            tableContinues = true
            if openTable?.columns.isEmpty == true { openTable?.columns = Self.columnAlignments(of: trimmed) }
            return index + 1
        }
        let nextIsDelimiter = index + 1 < lines.count && Self.isDelimiterRow(lines[index + 1])
        guard trimmed.hasPrefix("|") || tableOpen || nextIsDelimiter else { return nil }
        resetListAndTable()
        previousWasQuote = false
        tableOpen = true
        let start = beginLine()
        let cells = Self.cells(of: raw)
        for (position, cell) in cells.enumerated() {
            if position > 0 { builder.append("\t") }
            builder.append(inline(cell))
        }
        if nextIsDelimiter { builder.decorate(.tableHeader, from: start) }
        if openTable == nil {
            openTable = OpenTable(start: start, hasHeader: nextIsDelimiter, end: builder.length)
        } else {
            openTable?.end = builder.length
        }
        tableContinues = true
        return index + 1
    }

    /// The alignment each delimiter cell asks for: `:--` leading, `:-:` center, `--:` trailing and a bare `---`
    /// leaves the choice to the cells.
    private static func columnAlignments(of delimiterRow: String) -> [MarkupColumnAlignment] {
        var alignments: [MarkupColumnAlignment] = []
        for cell in cells(of: delimiterRow).prefix(MarkupTableLayout.maximumColumns) {
            let colonBefore = cell.hasPrefix(":"), colonAfter = cell.hasSuffix(":")
            if colonBefore && colonAfter { alignments.append(.center) }
            else if colonBefore { alignments.append(.leading) }
            else if colonAfter { alignments.append(.trailing) }
            else { alignments.append(.automatic) }
        }
        return alignments
    }

    /// Adds the decoration of the table that just ended; every row it covers is already written.
    private mutating func closeTable() {
        guard let table = openTable else { return }
        openTable = nil
        builder.decorate(.table(columns: table.columns, hasHeader: table.hasHeader),
                         range: NSRange(location: table.start, length: table.end - table.start))
    }

    // MARK: Code, math and diagrams

    private mutating func emitFence(_ fence: Fence) {
        switch fence.kind {
        case .code, .diagram:
            var bodyStart: Int?
            for line in fence.lines {
                let start = beginLine()
                if bodyStart == nil { bodyStart = start }
                builder.append(line)
                if line.isEmpty { continue }
                // Fenced lines keep the established inline-code decoration; the direction pass treats a
                // line wholly covered by it as code.
                builder.decorate(fence.kind == .diagram ? .diagramSource : .code, from: start)
            }
            if let bodyStart { builder.recordCodeBlock(from: bodyStart, language: fence.language) }
            if fence.kind == .diagram { builder.recordDiagramFence(from: bodyStart ?? builder.length) }
        case .math:
            emitMathBlock(fence.lines.joined(separator: "\n"))
        }
    }

    private mutating func renderDisplayMath(at index: Int) -> Int {
        resetBlockState()
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        var cursor = index
        if opening != "$$" { parts.append(String(opening.dropFirst(2))) }
        cursor += 1
        var closed = false
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            if line == "$$" { closed = true; cursor += 1; break }
            if line.hasSuffix("$$") { parts.append(String(line.dropLast(2))); closed = true; cursor += 1; break }
            parts.append(lines[cursor])
            cursor += 1
        }
        if !closed {
            // An unterminated block is text, not math: show the lines as written.
            for line in lines[index..<cursor] {
                _ = beginLine()
                builder.append(inline(line))
            }
            return cursor
        }
        emitMathBlock(parts.joined(separator: "\n"))
        return cursor
    }

    private mutating func emitMathBlock(_ tex: String) {
        let approximated = MarkupMath.approximate(tex, multiline: true)
        for line in approximated.components(separatedBy: "\n") {
            let start = beginLine()
            builder.append(line)
            if !line.isEmpty { builder.decorate(.mathBlock, from: start) }
        }
    }
}
