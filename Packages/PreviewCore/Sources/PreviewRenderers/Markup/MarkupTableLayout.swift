import CoreGraphics
import Foundation

/// What a table cell holds, as far as alignment goes.
enum MarkupCellShape: Equatable, Sendable {
    case text
    /// A number; `fractionDigits` counts the digits after its decimal point (0 for an integer).
    case number(fractionDigits: Int)
}

/// Reads a cell as a number or as text, from its characters alone. The reading is deliberately narrow: an optional
/// sign, an optional currency symbol before or after, digits grouped by commas or spaces in threes, an optional
/// fraction after a period and an optional percent sign. Anything else is text, so a column is only aligned as
/// numbers when every cell in it plainly is one.
enum MarkupNumberShape {
    /// A cell longer than this many scalars is text without being read further.
    static let maximumScalars = 32

    private static let signs: [Unicode.Scalar] = ["+", "-", "\u{2212}"]
    private static let percents: [Unicode.Scalar] = ["%", "\u{2030}"]
    private static let spaces: [Unicode.Scalar] = [" ", "\u{00A0}", "\u{202F}"]
    private static let groupingMarks: [Unicode.Scalar] = [",", " ", "\u{00A0}", "\u{202F}"]

    static func classify(_ cell: String) -> MarkupCellShape {
        var scalars: [Unicode.Scalar] = []
        for scalar in cell.unicodeScalars {
            if scalars.count >= maximumScalars { return .text }
            scalars.append(scalar)
        }
        var start = 0, end = scalars.count
        while start < end, spaces.contains(scalars[start]) { start += 1 }
        while end > start, spaces.contains(scalars[end - 1]) { end -= 1 }
        if start < end, signs.contains(scalars[start]) { start += 1 }
        if start < end, isCurrency(scalars[start]) { start += 1 }
        if end > start, percents.contains(scalars[end - 1]) || isCurrency(scalars[end - 1]) { end -= 1 }
        guard start < end else { return .text }

        var integerDigits = 0, fractionDigits = 0, groupDigits = 0
        var groupCount = 0
        var seenPoint = false
        var index = start
        while index < end {
            let scalar = scalars[index]
            if scalar.properties.generalCategory == .decimalNumber {
                if seenPoint { fractionDigits += 1 } else { integerDigits += 1; groupDigits += 1 }
            } else if scalar == ".", !seenPoint {
                // A group before the point is complete only with three digits, unless it is the only group.
                if groupCount > 0, groupDigits != 3 { return .text }
                seenPoint = true
            } else if !seenPoint, groupingMarks.contains(scalar) {
                // A mark needs digits before it: the first group has one to three, every later group exactly three.
                if groupDigits == 0 || groupDigits > 3 || (groupCount > 0 && groupDigits != 3) { return .text }
                groupCount += 1
                groupDigits = 0
            } else {
                return .text
            }
            index += 1
        }
        if !seenPoint, groupCount > 0, groupDigits != 3 { return .text }
        if seenPoint, fractionDigits == 0 { return .text }
        guard integerDigits + fractionDigits > 0 else { return .text }
        return .number(fractionDigits: fractionDigits)
    }

    private static func isCurrency(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .currencySymbol
    }
}

/// The tab stops of a table of tab-separated cells, from the widths its cells measure. The rendered text keeps its
/// tabs, so copying a table still yields tab-separated rows; only where a tab lands changes (decision 027, Q-72).
/// Everything is bounded before it is measured or stored: rows, columns and the length of a cell.
struct MarkupTableLayout: Equatable, Sendable {
    /// How a column sits at its stop.
    enum Placement: Equatable, Sendable {
        case leading, center, trailing
        /// Numbers whose fractions differ in length line up on their decimal point.
        case decimal
    }

    struct Stop: Equatable, Sendable {
        /// Where the stop lies, from the start of the line.
        let location: CGFloat
        let placement: Placement
    }

    /// What measuring the cells of one column found.
    struct ColumnMeasure: Equatable, Sendable {
        /// The widest cell, on one line.
        var width: CGFloat = 0
        /// The widest part of a cell up to its decimal point: the whole cell when it is text or has no point.
        var integerWidth: CGFloat = 0
        /// The widest part of a number from its decimal point on.
        var fractionWidth: CGFloat = 0
        var numberCells = 0
        var textCells = 0
        var fewestFractionDigits = Int.max
        var mostFractionDigits = 0

        /// A cell that is not a number, or a header, which only sets the column's width.
        mutating func addText(width cellWidth: CGFloat, countsAsContent: Bool) {
            width = max(width, cellWidth)
            integerWidth = max(integerWidth, cellWidth)
            if countsAsContent { textCells += 1 }
        }

        mutating func addNumber(integerWidth wholeWidth: CGFloat, fractionWidth fractionPartWidth: CGFloat,
                                fractionDigits: Int) {
            width = max(width, wholeWidth + fractionPartWidth)
            integerWidth = max(integerWidth, wholeWidth)
            fractionWidth = max(fractionWidth, fractionPartWidth)
            numberCells += 1
            fewestFractionDigits = min(fewestFractionDigits, fractionDigits)
            mostFractionDigits = max(mostFractionDigits, fractionDigits)
        }

        /// Every cell that has content is a number.
        var isNumeric: Bool { numberCells > 0 && textCells == 0 }
        /// The numbers write different numbers of fraction digits, so right edges alone would not line them up.
        var hasDifferingFractions: Bool { numberCells > 0 && fewestFractionDigits != mostFractionDigits }
    }

    /// One row of a table block: the cells between its tabs, in UTF-16 offsets of the whole text.
    struct Row: Equatable, Sendable {
        let cells: [NSRange]
    }

    /// Rows measured per table; a longer table keeps the stops its first rows give.
    static let maximumRows = 64
    /// Columns that get a stop; cells in later columns fall back to the paragraph's default tab interval.
    static let maximumColumns = 16
    /// Longest stretch of a cell that is measured, in UTF-16 units.
    static let maximumCellUnits = 120

    /// Stops for the columns after the first: the first column starts at the line start and needs none.
    let stops: [Stop]
    /// The width of the whole table, from the line start to the end of its last column.
    let width: CGFloat

    /// How a column sits, from its own cells and the alignment its delimiter row asked for.
    static func placement(of column: ColumnMeasure, alignment: MarkupColumnAlignment) -> Placement {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return column.isNumeric && column.hasDifferingFractions ? .decimal : .trailing
        case .automatic:
            guard column.isNumeric else { return .leading }
            return column.hasDifferingFractions ? .decimal : .trailing
        }
    }

    /// Lays columns of the measured widths side by side with `gap` between them. The columns past `maximumColumns` are
    /// ignored. Returns nil when there is nothing to align (fewer than two columns) or when the table is wider than
    /// `maximumWidth`: a table that cannot fit keeps the paragraph's ordinary tab stops instead of a worse layout.
    static func make(columns: [ColumnMeasure], alignments: [MarkupColumnAlignment], gap: CGFloat,
                     maximumWidth: CGFloat) -> MarkupTableLayout? {
        let count = min(columns.count, maximumColumns)
        guard count > 1, gap.isFinite, gap >= 0, maximumWidth.isFinite else { return nil }
        var stops: [Stop] = []
        var origin: CGFloat = 0
        for index in 0..<count {
            let column = columns[index]
            let alignment = index < alignments.count ? alignments[index] : MarkupColumnAlignment.automatic
            let chosen = Self.placement(of: column, alignment: alignment)
            let span = chosen == .decimal ? column.integerWidth + column.fractionWidth : column.width
            guard span.isFinite, span >= 0 else { return nil }
            if index > 0 {
                let location: CGFloat
                switch chosen {
                case .leading: location = origin
                case .center: location = origin + span / 2
                case .trailing: location = origin + span
                case .decimal: location = origin + column.integerWidth
                }
                stops.append(Stop(location: location, placement: chosen))
            }
            origin += span + gap
        }
        let total = origin - gap
        guard total <= maximumWidth else { return nil }
        return MarkupTableLayout(stops: stops, width: total)
    }

    /// The rows of `range` in `text`, at most `maximumRows` of them, each split at its tabs. A row ends at a line
    /// feed and a cell at a tab; a row keeps at most `maximumColumns` cells and a cell is measured over at most
    /// `maximumCellUnits` units.
    static func rows(in text: NSString, range: NSRange, maximumRows: Int = MarkupTableLayout.maximumRows) -> [Row] {
        guard range.location >= 0, range.location < text.length, range.length > 0, maximumRows > 0 else { return [] }
        let end = range.location + min(range.length, text.length - range.location)
        func cell(_ start: Int, _ stop: Int) -> NSRange {
            NSRange(location: start, length: min(stop - start, maximumCellUnits))
        }
        var rows: [Row] = []
        var lineStart = range.location
        while lineStart <= end, rows.count < maximumRows {
            var cursor = lineStart
            var cellStart = lineStart
            var cells: [NSRange] = []
            while cursor < end {
                let unit = text.character(at: cursor)
                if unit == 10 { break }
                if unit == 9 {
                    if cells.count < maximumColumns { cells.append(cell(cellStart, cursor)) }
                    cellStart = cursor + 1
                }
                cursor += 1
            }
            if cells.count < maximumColumns { cells.append(cell(cellStart, cursor)) }
            rows.append(Row(cells: cells))
            if cursor >= end { break }
            lineStart = cursor + 1
        }
        return rows
    }
}
