import Foundation
import PreviewContracts

/// Block-level output shared by the line-oriented markup renderers (AsciiDoc, reStructuredText,
/// Org and Fountain). It owns the blank-line rules between blocks, so a dialect parser only
/// decides what each block is: consecutive list items, table rows and screenplay lines stay
/// together, while other blocks are separated by one empty line. All text it writes has
/// already passed through concealment.
struct MarkupBlockWriter {
    enum Kind { case none, block, list, table, lines }

    var builder: MarkupBuilder
    var footnotes = MarkupFootnotes()
    private var last: Kind = .none
    /// The table whose rows were just written. Its decoration is added when the table ends, so it covers every row.
    private var openTable: OpenTable?

    private struct OpenTable {
        let start: Int
        let hasHeader: Bool
        var end: Int
    }

    init(limits: MarkupBuilder.Limits) { builder = MarkupBuilder(limits: limits) }

    var isOverflowed: Bool { builder.isOverflowed }

    /// Starts a block of `kind`: grouped kinds continue on the next line, others get a blank line.
    private mutating func begin(_ kind: Kind) {
        if last == .table, kind != .table { closeTable() }
        if last == kind, kind != .block { builder.ensureLineStart() } else { builder.ensureBlockSeparation() }
        last = kind
    }

    /// Ends the current group so the next block is separated, even if it has the same kind.
    mutating func separate() {
        closeTable()
        last = .block
    }

    /// Adds the decoration of the table that just ended; every row it covers is already written.
    private mutating func closeTable() {
        guard let table = openTable else { return }
        openTable = nil
        builder.decorate(.table(columns: [], hasHeader: table.hasHeader),
                         range: NSRange(location: table.start, length: table.end - table.start))
    }

    // MARK: Blocks

    @discardableResult
    mutating func heading(level: Int, _ inline: MarkupInlineResult, listed: Bool = true,
                          style: MarkdownDecoration.Style? = nil, extra: [MarkdownDecoration.Style] = []) -> NSRange {
        begin(.block)
        let start = builder.length
        builder.append(inline)
        let range = NSRange(location: start, length: inline.text.utf16.count)
        builder.decorate(style ?? .heading(min(max(level, 1), 6)), from: start)
        for decoration in extra { builder.decorate(decoration, from: start) }
        if listed { builder.addHeading(level: level, title: inline.text, range: range) }
        return range
    }

    mutating func paragraph(_ inline: MarkupInlineResult, styles: [MarkdownDecoration.Style] = []) {
        guard !inline.text.isEmpty else { return }
        begin(.block)
        let start = builder.length
        builder.append(inline)
        for style in styles { builder.decorate(style, from: start) }
    }

    /// A line that belongs to a run of lines (a screenplay's dialogue, a quote's verses).
    mutating func line(_ inline: MarkupInlineResult, styles: [MarkdownDecoration.Style] = [], groupedWithPrevious: Bool = true) {
        if groupedWithPrevious { begin(.lines) } else { begin(.block); last = .lines }
        let start = builder.length
        builder.append(inline)
        for style in styles { builder.decorate(style, from: start) }
    }

    mutating func listItem(marker: String, depth: Int, _ inline: MarkupInlineResult, taskDone: Bool? = nil) {
        begin(.list)
        let start = builder.length
        if let taskDone { builder.append(marker, style: .taskMarker(done: taskDone)) } else { builder.append(marker) }
        builder.append(" ")
        builder.append(inline)
        builder.decorate(.listItem(depth: min(depth, 15), markerLength: marker.count + 1), from: start)
    }

    /// A further paragraph of a list item, aligned with the item's text.
    mutating func listContinuation(depth: Int, markerLength: Int, _ inline: MarkupInlineResult) {
        guard !inline.text.isEmpty else { return }
        begin(.list)
        let start = builder.length
        builder.append(inline)
        builder.decorate(.listContinuation(depth: min(depth, 15), markerLength: markerLength), from: start)
    }

    mutating func codeBlock(_ lines: [String], style: MarkdownDecoration.Style = .codeBlock,
                            language: SourceLanguageID? = nil) {
        begin(.block)
        let bodyStart = builder.length
        for (offset, text) in lines.enumerated() {
            if offset > 0 { builder.newline() }
            let start = builder.length
            builder.append(text)
            if !text.isEmpty { builder.decorate(style, from: start) }
        }
        builder.recordCodeBlock(from: bodyStart, language: language)
    }

    mutating func mathBlock(_ tex: String) {
        begin(.block)
        for (offset, text) in MarkupMath.approximate(tex, multiline: true).components(separatedBy: "\n").enumerated() {
            if offset > 0 { builder.newline() }
            let start = builder.length
            builder.append(text)
            if !text.isEmpty { builder.decorate(.mathBlock, from: start) }
        }
    }

    mutating func rule() {
        begin(.block)
        builder.append(String(repeating: "\u{2500}", count: 24), style: .rule)
    }

    /// An admonition: a titled line in the alert style, then its body as quoted paragraphs.
    mutating func admonition(_ kind: MarkupAlertKind, body: [MarkupInlineResult]) {
        begin(.block)
        let start = builder.length
        builder.append(MarkdownRenderer.alertGlyph(kind) + " " + MarkdownRenderer.alertTitle(kind))
        builder.decorate(.quote, from: start)
        builder.decorate(.alertBar(kind), from: start)
        builder.decorate(.alertTitle(kind), from: start)
        for paragraph in body where !paragraph.text.isEmpty {
            builder.newline()
            let lineStart = builder.length
            builder.append(paragraph)
            builder.decorate(.quote, from: lineStart)
            builder.decorate(.alertBar(kind), from: lineStart)
        }
    }

    mutating func quote(_ paragraphs: [MarkupInlineResult]) {
        for (offset, paragraph) in paragraphs.enumerated() where !paragraph.text.isEmpty {
            if offset == 0 { begin(.block) } else { builder.ensureBlockSeparation() }
            let start = builder.length
            builder.append(paragraph)
            builder.decorate(.quote, from: start)
            builder.decorate(.indent(1), from: start)
        }
    }

    /// One table row: cells separated by tabs. A header row is set in bold.
    mutating func tableRow(_ cells: [MarkupInlineResult], header: Bool = false) {
        begin(.table)
        let start = builder.length
        for (position, cell) in cells.enumerated() {
            if position > 0 { builder.append("\t") }
            builder.append(cell)
        }
        if header { builder.decorate(.tableHeader, from: start) }
        if openTable == nil {
            openTable = OpenTable(start: start, hasHeader: header, end: builder.length)
        } else {
            openTable?.end = builder.length
        }
    }

    /// Dimmed source text for constructs that only point elsewhere (includes, image targets) or are comments.
    mutating func dimmedLine(_ text: String, grouped: Bool = true) {
        if grouped { begin(.lines) } else { begin(.block); last = .lines }
        builder.append(text, style: .dimmed)
    }

    /// Records a reference shown as dimmed text (an include, an image target) instead of being loaded.
    mutating func noteOmitted(_ kind: OmittedResourceKind) { builder.noteOmitted(kind) }

    // MARK: Finish

    mutating func finish(footnoteInline: (String) -> MarkupInlineResult) -> SafeMarkdownDocument? {
        closeTable()
        builder.appendFootnotes(footnotes, render: footnoteInline)
        return builder.finish()
    }
}
