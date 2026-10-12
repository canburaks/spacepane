import PreviewContracts

/// The first lines of the concealed text, fit to the page.
enum ThumbnailExcerpt {
    /// Syntaxes whose lines are prose: they wrap at word boundaries instead of clipping.
    private static let proseSyntaxes: Set<TextSyntax> = [.plain, .lyrics, .latex, .fountain, .asciidoc, .restructuredText, .orgMode]

    /// A bounded amount of source is read for any page, regardless of how long the document is.
    private static let artProbeScalars = 4_096

    /// Returns nil when the text holds nothing visible. `rows` can lower the page's row capacity,
    /// for a page that shares the sheet with other excerpts.
    static func page(from text: String, syntax: TextSyntax, metrics: ThumbnailMetrics, rows: Int? = nil) -> ThumbnailTextPage? {
        let capacityRows = min(metrics.rows, rows ?? metrics.rows)
        let wraps = proseSyntaxes.contains(syntax) && !containsDrawingCharacters(text)
        let source = ThumbnailLines.raw(in: text, limit: capacityRows * 3 + 16, maxScalars: metrics.columns * 6)
        let lexer = ThumbnailLexer(syntax: syntax)
        var lexerState = ThumbnailLexer.State()
        var lines: [ThumbnailLine] = []
        var used = 0.0
        var previousWasBlank = true
        let capacity = Double(capacityRows)
        for raw in source {
            if used >= capacity { break }
            let line = ThumbnailLines.trimmingTrailingWhitespace(ThumbnailLines.expandTabs(raw))
            if line.isEmpty {
                // Leading blank lines are skipped and runs of blank lines collapse to one.
                if !previousWasBlank { lines.append(.blank); used += 1 }
                previousWasBlank = true
                continue
            }
            previousWasBlank = false
            let indent = min(ThumbnailLines.leadingSpaces(line), metrics.columns / 2)
            let body = Array(line.dropFirst(ThumbnailLines.leadingSpaces(line)))
            let width = max(1, metrics.columns - indent)
            let pieces = wraps ? ThumbnailLines.wrap(body, cells: width, maximumPieces: 4)
                               : [ThumbnailCells.prefix(body, cells: width)]
            for piece in pieces where used < capacity {
                lines.append(ThumbnailLine(indent: indent, runs: lexer.runs(in: piece, state: &lexerState)))
                used += 1
            }
        }
        while lines.last == .blank { lines.removeLast() }
        return lines.isEmpty ? nil : ThumbnailTextPage(lines: lines)
    }

    /// Box-drawing, block, and braille scalars mark text art: wrapping would break it.
    private static func containsDrawingCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars.prefix(artProbeScalars) {
            switch scalar.value {
            case 0x2500...0x259F, 0x2800...0x28FF: return true
            default: continue
            }
        }
        return false
    }
}
