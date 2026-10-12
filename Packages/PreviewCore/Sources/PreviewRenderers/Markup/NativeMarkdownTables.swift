import AppKit

extension NativeMarkdownStyling {
    /// `NSTextContainer`'s default padding at each end of a line, which the preview's text container keeps.
    private static let lineFragmentPadding: CGFloat = 5

    /// Tab stops from the measured width of the cells, so the columns line up and a column of numbers sits on its
    /// trailing edge or its decimal point. The text, its tabs and what copying yields are untouched; this runs after
    /// the cells have their fonts (bold header, code spans), because it measures them. Measuring is bounded to the
    /// first `MarkupTableLayout.maximumRows` rows, and a table too wide for the reading column keeps the paragraph's
    /// ordinary tab stops.
    @MainActor
    static func applyTable(columns: [MarkupColumnAlignment], hasHeader: Bool, range: NSRange,
                           to storage: NSTextStorage, typography: NativeTextTypography) {
        let text = storage.string as NSString
        let rows = MarkupTableLayout.rows(in: text, range: range)
        guard rows.contains(where: { $0.cells.count > 1 }) else { return }
        let reading = ReadingLayout(typography: typography)
        var measures: [MarkupTableLayout.ColumnMeasure] = []
        for (rowIndex, row) in rows.enumerated() {
            let isHeader = hasHeader && rowIndex == 0
            for (column, cell) in row.cells.enumerated() {
                while measures.count <= column { measures.append(MarkupTableLayout.ColumnMeasure()) }
                measure(cell, isHeader: isHeader, into: &measures[column], storage: storage, text: text,
                        typography: typography)
            }
        }
        let digit = max(("0" as NSString).size(withAttributes: [.font: reading.font]).width, 1)
        // The widest column the reading text can have, less the padding the text container keeps at both ends of a line.
        let available = reading.measure - 2 * lineFragmentPadding
        guard let layout = MarkupTableLayout.make(columns: measures, alignments: columns, gap: digit * 2,
                                                  maximumWidth: available) else { return }
        let first = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let stops = MarkupTabStops.stops(for: layout, rightToLeft: first?.baseWritingDirection == .rightToLeft)
        alter(storage, range, typography) { $0.tabStops = stops }
    }

    /// Adds one cell to its column: a number by the width of its whole and fraction parts, anything else by its width.
    /// A header only sets the width of its column; it never decides whether the column holds numbers.
    @MainActor
    private static func measure(_ cell: NSRange, isHeader: Bool, into column: inout MarkupTableLayout.ColumnMeasure,
                                storage: NSTextStorage, text: NSString, typography: NativeTextTypography) {
        guard cell.length > 0 else { return }
        let shape = isHeader ? MarkupCellShape.text : MarkupNumberShape.classify(text.substring(with: cell))
        switch shape {
        case .text:
            column.addText(width: width(of: cell, storage: storage, text: text, typography: typography),
                           countsAsContent: !isHeader)
        case .number(let fractionDigits):
            let point = text.range(of: ".", options: [], range: cell)
            if point.location == NSNotFound {
                column.addNumber(integerWidth: width(of: cell, storage: storage, text: text, typography: typography),
                                 fractionWidth: 0, fractionDigits: fractionDigits)
            } else {
                let whole = NSRange(location: cell.location, length: point.location - cell.location)
                let fraction = NSRange(location: point.location, length: NSMaxRange(cell) - point.location)
                column.addNumber(integerWidth: width(of: whole, storage: storage, text: text, typography: typography),
                                 fractionWidth: width(of: fraction, storage: storage, text: text, typography: typography),
                                 fractionDigits: fractionDigits)
            }
        }
    }

    /// The width of a stretch of text in the fonts it is set in, one font run at a time, with the character spacing
    /// between letters. A stretch with no characters is as wide as nothing.
    @MainActor
    private static func width(of range: NSRange, storage: NSTextStorage, text: NSString,
                              typography: NativeTextTypography) -> CGFloat {
        guard range.length > 0 else { return 0 }
        var total: CGFloat = 0
        storage.enumerateAttribute(.font, in: range, options: []) { value, run, _ in
            let font = (value as? NSFont) ?? typography.font
            let piece = text.substring(with: run) as NSString
            total += piece.size(withAttributes: [.font: font]).width + typography.characterSpacing * CGFloat(run.length)
        }
        return total
    }
}
