import PreviewContracts

/// The last step before a page is drawn: characters that change how text is shown, or carry a message, without
/// being shown themselves are removed from every drawn run and cell (decision 027, Q-127; thumbnails review TH-14).
///
/// A thumbnail has no findings banner and no Invisibles mode, and it stays in Finder's durable cache. An embedding
/// or override (U+202E) would make Core Text draw the line in a different order than the text says, a run of Unicode
/// Tags would draw as blanks that hide a message, and zero-width characters would only take cells. The classes
/// dropped are the format-category characters the shared hidden-character classifier reports, so the thumbnail and
/// the findings agree: bidirectional controls, zero-width and other invisible formatting characters, and Unicode
/// Tags. The classifier already leaves alone what a script needs, so a zero-width non-joiner in Persian, a joiner in
/// an emoji sequence or a direction mark in a line of Hebrew stays. Variation selectors and private-use scalars stay
/// as well: they cannot reorder or hide text.
///
/// This runs on the finished page model, after layout, because decoded JSON escapes (`\u202E` in a minified
/// document or a notebook cell) only become scalars during layout. The cell model already counts these characters
/// as zero width or a single cell, so removing them afterwards never overflows a line.
enum ThumbnailDrawnText {
    private static let droppedClasses: Set<HiddenCharacterClass> = [.bidirectionalControl, .zeroWidth, .tag]

    /// `text` without the hidden formatting characters; the same string when it holds none.
    static func sanitizedText(_ text: String) -> String {
        let spans = HiddenCharacters.spans(in: text).filter { droppedClasses.contains($0.kind) }
        guard !spans.isEmpty else { return text }
        var kept = String.UnicodeScalarView()
        var offset = 0
        var next = 0
        for scalar in text.unicodeScalars {
            // Spans are in text order and cover whole scalars, so one forward walk drops each of them.
            while next < spans.count, spans[next].utf16Range.upperBound <= offset { next += 1 }
            let isDropped = next < spans.count && spans[next].utf16Range.contains(offset)
            if !isDropped { kept.append(scalar) }
            offset += scalar.utf16.count
        }
        return String(kept)
    }

    /// The content with every drawn string sanitized. A picture holds no text and is returned as it is.
    static func sanitizedContent(_ content: ThumbnailContent) -> ThumbnailContent {
        switch content {
        case .text(let page):
            return .text(ThumbnailTextPage(lines: page.lines.map(sanitizedLine)))
        case .grid:
            // The grid initializer sanitizes its bounded headers. Counts hold numbers only.
            return content
        case .picture:
            return content
        }
    }

    private static func sanitizedLine(_ line: ThumbnailLine) -> ThumbnailLine {
        var runs: [ThumbnailRun] = []
        for run in line.runs {
            let text = sanitizedText(run.text)
            // A run that held only hidden characters is gone, not an empty run.
            if !text.isEmpty { runs.append(ThumbnailRun(text, tone: run.tone)) }
        }
        return ThumbnailLine(indent: line.indent, runs: runs, emphasis: line.emphasis)
    }
}
