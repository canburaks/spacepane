import PreviewContracts

/// Chooses a shape from concealed text and value-free parser facts, without source access.
enum ThumbnailContentBuilder {
    /// Text-derived content, or nil when the presentation holds nothing worth drawing. An app-made summary
    /// (`TextOrigin.summary`) is never drawn; a supported grid may draw its typed facts and bounded concealed
    /// headers instead. Whatever shape is chosen, the drawn strings
    /// then lose the hidden formatting characters that would change how they read (decision 027, Q-127).
    static func textContent(for presentation: TextPresentation, metrics: ThumbnailMetrics) -> ThumbnailContent? {
        guard let content = shapedContent(for: presentation, metrics: metrics) else { return nil }
        return ThumbnailDrawnText.sanitizedContent(content)
    }

    private static func shapedContent(for presentation: TextPresentation, metrics: ThumbnailMetrics) -> ThumbnailContent? {
        if let grid = ThumbnailGridBuilder.grid(for: presentation, metrics: metrics) { return .grid(grid) }
        if presentation.formatID == .json, presentation.facts.facts.contains(where: {
            switch $0 {
            case .grid, .records(_, .records, _): return true
            default: return false
            }
        }) { return nil } // A record shape that cannot be represented never falls back to its body values.
        guard presentation.origin != .summary else { return nil }
        let text = presentation.text
        guard !text.isEmpty else { return nil }
        // A notebook has a fixed source shape; a database without usable facts never draws its summary.
        switch presentation.formatID {
        case .sqlite:
            return nil
        case .jupyterNotebook:
            return ThumbnailStructuredShapes.notebookPage(from: text, metrics: metrics).map(ThumbnailContent.text)
        default:
            break
        }
        switch presentation.syntax {
        case .commaSeparated, .tabSeparated:
            // A delimited grid without parser counts stays generic; it never draws sampled body values.
            return nil
        case .plain:
            switch ThumbnailGridBuilder.tabSeparatedProbe(fromPlainText: text, metrics: metrics) {
            case .grid(let grid): return .grid(grid)
            case .withheld: return nil
            case .notGrid: break
            }
        case .json:
            if ThumbnailJSONOutline.prefersOutline(text: text, lineCount: presentation.lineCount, columns: metrics.columns),
               let page = ThumbnailJSONOutline.page(from: text, metrics: metrics) {
                return .text(page)
            }
        default:
            // A rendered markup is drawn as its page or not at all: its raw text holds comments that a reader of
            // the document never sees, and an excerpt of the raw text would draw them.
            if ThumbnailMarkdown.supports(presentation.syntax) {
                return ThumbnailMarkdown.page(from: text, syntax: presentation.syntax, metrics: metrics).map(ThumbnailContent.text)
            }
        }
        return ThumbnailExcerpt.page(from: text, syntax: presentation.syntax, metrics: metrics).map(ThumbnailContent.text)
    }
}

/// Which document pictures are worth decoding, best first: a cover or an icon identifies the file,
/// a page is the next best, and a figure is a fallback. Only a few are tried so decode work stays bounded.
enum ThumbnailImageSelection {
    static let maximumAttempts = 3
    private static let roleOrder: [PreviewImage.Role] = [.cover, .icon, .page, .figure]

    static func candidates(from images: [PreviewImage]) -> [PreviewImage] {
        let valid = images.filter(\.isValid)
        return Array(roleOrder.flatMap { role in valid.filter { $0.role == role } }.prefix(maximumAttempts))
    }
}
