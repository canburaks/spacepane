import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Rows of the Contents list (the rail and the Contents mode) hold wrapped headings, so a row is as tall as its
/// heading wraps at the width the list has now. When a legacy scroller appears the clip is narrower than the
/// list's frame, so measuring a cached layout, or the frame, leaves the second line over the next row.
@Suite("Contents rows grow with wrapped headings", .serialized)
@MainActor
struct ContentsRowHeightTests {
    private static let long = "A considerably long heading that wraps onto more than one line in a narrow rail"
    private static let longer = "Another heading, longer still, so that it needs yet another line when the list is narrow"

    private func style(fontSize: Double = 13, lineSpacing: Double = 0, dark: Bool = false) -> SafeModeStyle {
        SafeModeStyle(typography: PreviewTypography(fontSize: fontSize, lineSpacing: lineSpacing),
                      palette: NativeTextPalette(theme: dark ? .dark : .light, isDark: dark, increasedContrast: false),
                      syntaxStyle: .init(), locale: Locale(identifier: "en"))
    }

    private func headings(_ titles: [String], level: Int = 1) -> [MarkupHeading] {
        titles.enumerated().map { MarkupHeading(level: level, title: $1, range: NSRange(location: $0 * 100, length: $1.utf16.count)) }
    }

    private func list(width: CGFloat, height: CGFloat, legacyScrollers: Bool = false, maximumPointSize: CGFloat? = 15,
                      style listStyle: SafeModeStyle? = nil, titles: [String]) -> (MarkupContentsView, NSWindow) {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.maximumPointSize = maximumPointSize
        view.indentPerLevel = 10
        view.selectsFirstRow = false
        if legacyScrollers { view.scrollView.scrollerStyle = .legacy }
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        // A window that was never shown lays its views out lazily. The list is laid out before it is given
        // headings, as it is when the rail or the Contents mode is already on screen.
        view.layoutSubtreeIfNeeded()
        view.display(headings: headings(titles), style: listStyle ?? style())
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    /// What every row must satisfy once laid out: the title fits the field that holds it, the field fits the row,
    /// and the row stays inside the clip, so nothing runs under a scroller or into the next row.
    private func assertRowsFit(_ view: MarkupContentsView, rows: Range<Int>, fileID: String = #fileID, line: Int = #line) throws {
        view.layoutSubtreeIfNeeded()
        let clip = view.scrollView.contentView.bounds.width
        for row in rows {
            let rowView = try #require(view.tableView.rowView(atRow: row, makeIfNecessary: true))
            rowView.layoutSubtreeIfNeeded()
            let cell = try #require(rowView.view(atColumn: 0) as? ContentsCell)
            cell.layoutSubtreeIfNeeded()
            let fieldCell = try #require(cell.field.cell)
            let needed = fieldCell.cellSize(forBounds: NSRect(x: 0, y: 0, width: cell.field.frame.width, height: .greatestFiniteMagnitude)).height
            #expect(cell.field.frame.height >= needed.rounded(.down),
                    "Row \(row): the title needs \(needed) points, its field has \(cell.field.frame.height)")
            #expect(rowView.frame.height >= cell.field.frame.height, "Row \(row): the field is taller than its row")
            // The field keeps 3 points above and below, so the row holds the text and both insets.
            #expect(rowView.frame.height >= needed.rounded(.down) + 6, "Row \(row): \(rowView.frame.height) points cannot hold \(needed) and its insets")
            #expect(abs(rowView.frame.height - view.tableView.rect(ofRow: row).height) < 0.5,
                    "Row \(row): the row view \(rowView.frame.height) disagrees with the table's \(view.tableView.rect(ofRow: row).height)")
            #expect(rowView.frame.maxX <= clip + 0.5, "Row \(row) extends past the clip's \(clip)")
        }
    }

    @Test func aHeadingThatWrapsGetsARowThatHoldsAllItsLines() throws {
        let (view, window) = list(width: 220, height: 400, titles: [Self.long, "Short"])
        try withExtendedLifetime(window) {
            try assertRowsFit(view, rows: 0..<2)
            #expect(view.tableView.rect(ofRow: 0).height > 2 * view.tableView.rect(ofRow: 1).height * 0.9,
                    "The fixture heading must wrap onto several lines, or the test says nothing")
            #expect(view.tableView.rect(ofRow: 1).height == view.tableView.rowHeight, "A short heading keeps a one-line row")
        }
    }

    @Test func rowsAreMeasuredAgainstTheClipWidthWhenALegacyScrollerNarrowsIt() throws {
        let titles = (0..<12).map { "\(Self.long) \($0)" }
        let (view, window) = list(width: 220, height: 160, legacyScrollers: true, titles: titles)
        try withExtendedLifetime(window) {
            #expect(view.scrollView.verticalScroller?.scrollerStyle == .legacy)
            try #require(view.scrollView.contentView.bounds.width < 220,
                         "The legacy scroller must narrow the clip for this test to mean anything")
            try assertRowsFit(view, rows: titles.indices)
        }
    }

    @Test func nestedHeadingsHaveLessRoomForTheirTitle() throws {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))
        view.maximumPointSize = 15
        view.indentPerLevel = 10
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        let deep = (1...4).map { MarkupHeading(level: $0, title: "Medium length heading text", range: NSRange(location: $0, length: 1)) }
        view.layoutSubtreeIfNeeded()
        view.display(headings: deep, style: style())
        try withExtendedLifetime(window) {
            try assertRowsFit(view, rows: 0..<4)
        }
    }

    @Test func rowsRewrapWhenTheListIsResized() throws {
        let (view, window) = list(width: 400, height: 400, titles: [Self.long])
        try withExtendedLifetime(window) {
            let wide = view.tableView.rect(ofRow: 0).height
            view.setFrameSize(NSSize(width: 160, height: 400))
            view.layoutSubtreeIfNeeded()
            #expect(view.tableView.rect(ofRow: 0).height > wide)
            try assertRowsFit(view, rows: 0..<1)
        }
    }

    @Test func aVeryLongHeadingIsLimitedToAFewLines() {
        let (view, window) = list(width: 220, height: 400, titles: [String(repeating: "word ", count: 400)])
        withExtendedLifetime(window) {
            #expect(view.tableView.rect(ofRow: 0).height <= 140, "An unbounded title would swallow the rail")
        }
    }

    // MARK: Largest appearance sizes

    @Test(arguments: [PreviewTypography.fontSizeRange.upperBound, 36, PreviewTypography.fontSizeRange.lowerBound])
    func everyRowIsAsTallAsItsTextAtTheLargestAppearanceSizes(fontSize: Double) throws {
        for spacing in [PreviewTypography.lineSpacingRange.lowerBound, PreviewTypography.lineSpacingRange.upperBound] {
            let titles = ["One line", Self.long, "Wrapped heading text that needs more than one line"]
            let (view, window) = list(width: 400, height: 600, maximumPointSize: nil,
                                      style: style(fontSize: fontSize, lineSpacing: spacing), titles: titles)
            try withExtendedLifetime(window) { try assertRowsFit(view, rows: titles.indices) }
        }
    }

    // MARK: Measuring

    @Test func manyHeadingsAreMeasuredWithOneLayoutManager() {
        let titles = (0..<5_000).map { "Heading number \($0) with some words that may wrap in a narrow list" }
        let (view, window) = list(width: 220, height: 400, titles: titles)
        withExtendedLifetime(window) {
            // The table measures the rows it needs; walking to the end makes it measure many more.
            view.tableView.scrollRowToVisible(titles.count - 1)
            view.layoutSubtreeIfNeeded()
            _ = view.tableView.rect(ofRow: titles.count - 1)
            #expect(view.measurer.measurementCount > 100, "Only \(view.measurer.measurementCount) rows were measured")
            #expect(view.measurer.layoutManagerCount == 1, "A layout manager per row was allocated")
        }
    }

    @Test func anAppearanceOnlyRefreshDoesNotMeasureAgain() {
        let titles = (0..<50).map { "Heading \($0) that is long enough to wrap in the narrow list" }
        let (view, window) = list(width: 220, height: 400, titles: titles)
        withExtendedLifetime(window) {
            _ = view.tableView.rect(ofRow: titles.count - 1)
            let measured = view.measurer.measurementCount
            #expect(measured >= titles.count, "Every row should have been measured")
            // Same width, same font, same titles: only the colors differ.
            view.display(headings: headings(titles), style: style(dark: true))
            view.layoutSubtreeIfNeeded()
            _ = view.tableView.rect(ofRow: titles.count - 1)
            #expect(view.measurer.measurementCount == measured, "The refresh measured \(view.measurer.measurementCount - measured) rows again")
            // A different font size does change the heights.
            view.display(headings: headings(titles), style: style(fontSize: 15, dark: true))
            view.layoutSubtreeIfNeeded()
            _ = view.tableView.rect(ofRow: titles.count - 1)
            #expect(view.measurer.measurementCount > measured)
        }
    }
}
