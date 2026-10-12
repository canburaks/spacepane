import Foundation
import PreviewContracts

/// Inline text with decorations whose ranges are relative to the start of `text`.
struct MarkupInlineResult: Equatable, Sendable {
    var text: String
    var decorations: [MarkdownDecoration]
    /// References in this run that were left as inert text. The builder adds them up when the run is appended,
    /// so only what the document shows is counted.
    var omitted = OmittedResources()
    static let empty = MarkupInlineResult(text: "", decorations: [])
}

/// Accumulates the rendered text, decorations and headings of one markup document.
///
/// Every renderer in the markup family writes through this type, which owns the shared bounds:
/// output UTF-16 units, decorations and collected headings. Exceeding a bound makes the
/// document unavailable instead of truncating it silently, so the caller falls back to Source.
/// Offsets are UTF-16 units of the rendered text, the unit AppKit text storage uses.
struct MarkupBuilder {
    struct Limits: Equatable, Sendable {
        var maximumUTF16Units = 262_144
        var maximumDecorations = 20_000
        var maximumHeadings = 5_000
    }

    private(set) var text = ""
    /// UTF-16 length of `text`.
    private(set) var length = 0
    private(set) var decorations: [MarkdownDecoration] = []
    private(set) var headings: [MarkupHeading] = []
    private(set) var codeBlocks: [MarkupCodeBlock] = []
    private(set) var diagramFences: [MarkupDiagramFence] = []
    /// References shown as inert text instead of being loaded; the finished document carries the counts.
    private(set) var omitted = OmittedResources()
    private(set) var isOverflowed = false
    private var endsWithNewline = true
    let limits: Limits

    init(limits: Limits = Limits()) { self.limits = limits }

    var isAtLineStart: Bool { endsWithNewline }

    /// The output from UTF-16 offset `start` to the end, as written so far.
    func text(from start: Int) -> String {
        guard start >= 0, start < length else { return "" }
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: start)
        return String(text[index...])
    }

    mutating func append(_ string: String) {
        guard !isOverflowed, !string.isEmpty else { return }
        text.append(string)
        length += string.utf16.count
        endsWithNewline = string.last.map { $0 == "\n" } ?? endsWithNewline
        if length > limits.maximumUTF16Units { isOverflowed = true }
    }

    mutating func newline() { append("\n") }

    /// Starts a new line unless the output already sits at a line start.
    mutating func ensureLineStart() { if !endsWithNewline { newline() } }

    /// Leaves exactly one empty line between blocks, and none at the start of the document.
    mutating func ensureBlockSeparation() {
        guard length > 0 else { return }
        ensureLineStart()
        if !text.hasSuffix("\n\n") { newline() }
    }

    mutating func decorate(_ style: MarkdownDecoration.Style, range: NSRange) {
        guard !isOverflowed, range.length > 0, range.location >= 0, NSMaxRange(range) <= length else { return }
        guard decorations.count < limits.maximumDecorations else { isOverflowed = true; return }
        decorations.append(.init(range: range, style: style))
    }

    /// Decorates from `start` to the current end of the output.
    mutating func decorate(_ style: MarkdownDecoration.Style, from start: Int) {
        decorate(style, range: NSRange(location: start, length: length - start))
    }

    mutating func append(_ string: String, style: MarkdownDecoration.Style) {
        let start = length
        append(string)
        decorate(style, from: start)
    }

    mutating func append(_ inline: MarkupInlineResult) {
        omitted.add(inline.omitted)
        let base = length
        append(inline.text)
        for decoration in inline.decorations {
            decorate(decoration.style, range: NSRange(location: base + decoration.range.location, length: decoration.range.length))
        }
    }

    /// Records a reference the renderer showed as inert text (an include, an image target) instead of loading it.
    mutating func noteOmitted(_ kind: OmittedResourceKind) { omitted.note(kind) }

    /// Records one complete emitted body; nothing is clipped or reconstructed from line styles.
    mutating func recordCodeBlock(from start: Int, language: SourceLanguageID? = nil) {
        guard !isOverflowed, start >= 0, start < length else { return }
        guard codeBlocks.count < limits.maximumDecorations else { isOverflowed = true; return }
        codeBlocks.append(.init(range: NSRange(location: start, length: length - start), language: language))
    }

    /// Empty bodies remain explicit identities for honest bounded diagram selection/counts.
    mutating func recordDiagramFence(from start: Int) {
        guard !isOverflowed, start >= 0, start <= length else { return }
        guard diagramFences.count < limits.maximumDecorations else { isOverflowed = true; return }
        diagramFences.append(.init(range: NSRange(location: start, length: length - start)))
    }

    /// Records a heading whose title occupies `range` of the rendered text.
    mutating func addHeading(level: Int, title: String, range: NSRange) {
        guard !isOverflowed, headings.count < limits.maximumHeadings, range.length > 0,
              range.location >= 0, NSMaxRange(range) <= length else { return }
        headings.append(.init(level: min(max(level, 1), 6), title: title, range: range))
    }

    /// Finishes the document, or returns nil when a bound was exceeded. Right-to-left paragraphs
    /// are tagged here once for every dialect, so each renderer only has to produce text.
    func finish() -> SafeMarkdownDocument? {
        guard !isOverflowed else { return nil }
        var all = decorations
        for range in joiningAlertTitles(to: rightToLeftRanges()) {
            guard all.count < limits.maximumDecorations else { return nil }
            all.append(.init(range: range, style: .rightToLeft))
        }
        // Paragraph and block styles apply first so inline styles compose on the fonts they set.
        let ordered = all.filter { !Self.isInline($0.style) } + all.filter { Self.isInline($0.style) }
        return SafeMarkdownDocument(text: text, decorations: ordered, headings: headings, omitted: omitted,
                                    codeBlocks: codeBlocks, diagramFences: diagramFences)
    }

    private static func isInline(_ style: MarkdownDecoration.Style) -> Bool {
        switch style {
        case .bold, .italic, .code, .strikethrough, .math, .footnoteMark, .footnoteLabel, .taskMarker,
             .alertTitle, .frontMatterKey, .dimmed, .definitionTerm: true
        // A table is measured in the fonts its cells end up with, so it applies after every block and inline face.
        case .table: true
        default: false
        }
    }

    /// Whole-line blocks are source code, math or rules, which keep their natural left-to-right layout.
    private static func keepsLeftToRight(_ style: MarkdownDecoration.Style) -> Bool {
        switch style {
        case .codeBlock, .diagramSource, .mathBlock, .rule: true
        default: false
        }
    }

    /// An alert's title is written in the interface language, but the alert reads in the direction of its body. A
    /// title line that sits directly above a right-to-left run joins the run, so the bar and the title share a side.
    private func joiningAlertTitles(to runs: [NSRange]) -> [NSRange] {
        guard !runs.isEmpty else { return runs }
        var titles: [NSRange] = []
        for decoration in decorations {
            if case .alertTitle = decoration.style { titles.append(decoration.range) }
        }
        guard !titles.isEmpty else { return runs }
        var indexByStart: [Int: Int] = [:]
        for (index, run) in runs.enumerated() { indexByStart[run.location] = index }
        var joined = runs
        for title in titles {
            // The body starts on the line after the title: one line feed past its end.
            guard let index = indexByStart[NSMaxRange(title) + 1] else { continue }
            let run = joined[index]
            joined[index] = NSRange(location: title.location, length: NSMaxRange(run) - title.location)
        }
        return joined
    }

    /// Runs of consecutive right-to-left lines (blank lines continue a run) outside left-to-right blocks.
    private func rightToLeftRanges() -> [NSRange] {
        let blocks = decorations.filter { Self.keepsLeftToRight($0.style) }.map(\.range).sorted { $0.location < $1.location }
        // Fenced code is decorated as inline code over each whole line; such a line is code, not prose.
        let codeSpans = decorations.filter { $0.style == .code }.map(\.range).sorted { $0.location < $1.location }
        func isWholeLineCode(_ lineStart: Int, _ lineEnd: Int) -> Bool {
            var low = 0, high = codeSpans.count
            while low < high {
                let middle = (low + high) / 2
                if codeSpans[middle].location <= lineStart { low = middle + 1 } else { high = middle }
            }
            return low > 0 && NSMaxRange(codeSpans[low - 1]) >= lineEnd
        }
        var blockIndex = 0
        var runs: [NSRange] = []
        var runStart: Int?
        var runEnd = 0
        var lineStart = 0
        var offset = 0
        var direction: Bool?
        var lineHasContent = false

        func finishLine(end: Int) {
            defer { direction = nil; lineHasContent = false }
            guard lineHasContent else { return }   // blank lines never end or start a run
            while blockIndex < blocks.count, NSMaxRange(blocks[blockIndex]) <= lineStart { blockIndex += 1 }
            let inBlock = (blockIndex < blocks.count && blocks[blockIndex].location < end) || isWholeLineCode(lineStart, end)
            if !inBlock, direction == true {
                if runStart == nil { runStart = lineStart }
                runEnd = end
            } else if let start = runStart {
                runs.append(NSRange(location: start, length: runEnd - start))
                runStart = nil
            }
        }

        for scalar in text.unicodeScalars {
            let units = scalar.value > 0xFFFF ? 2 : 1
            if scalar == "\n" {
                finishLine(end: offset)
                offset += 1
                lineStart = offset
                continue
            }
            if scalar != " " && scalar != "\t" { lineHasContent = true }
            if direction == nil, let strong = MarkupDirection.strongDirection(of: scalar) { direction = strong }
            offset += units
        }
        finishLine(end: offset)
        if let start = runStart { runs.append(NSRange(location: start, length: runEnd - start)) }
        return runs.filter { $0.length > 0 }
    }
}
