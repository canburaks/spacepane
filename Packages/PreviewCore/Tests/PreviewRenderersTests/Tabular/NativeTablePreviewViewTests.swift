import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native table preview", .serialized)
@MainActor
struct NativeTablePreviewViewTests {
    @Test func displayBuildsOneColumnPerTitleAndOneRowPerRecord() throws {
        let view = makeView()
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(view.tableView.numberOfColumns == 3)
        #expect(view.tableView.tableColumns.map(\.title) == ["name", "password", "note"])
        #expect(view.tableView.numberOfRows == 3)
        #expect(view.scrollView.documentView === view.tableView)
        #expect(view.tableView.allowsMultipleSelection)
        #expect(view.tableView.usesAlternatingRowBackgroundColors)
        #expect((view.scrollView.superview as? NSStackView)?.arrangedSubviews.count == 2)
        #expect(view.tableView.accessibilityLabel() == PreviewStrings.format(
            .previewTableAccessibilityLabel, arguments: [Int64(3), Int64(3)], locale: .current))
    }

    @Test func cellsExposeOnlySafeTextWithTheirColumnTitleAndNativeAccessibility() throws {
        let view = makeView()
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let cell = try field(view, row: 0, column: 2)
        #expect(cell.stringValue == "hello, world")
        #expect(cell.accessibilityValue() == "hello, world")
        #expect(cell.accessibilityLabel() == "note")
        #expect(cell.isSelectable)
        #expect(!cell.isEditable)
        #expect(cell.attributedStringValue.attribute(.link, at: 0, effectiveRange: nil) == nil)
        let native = NSTextField(labelWithString: "x")
        native.isSelectable = true
        #expect(cell.accessibilityRole() == native.accessibilityRole())
        let concealed = try field(view, row: 0, column: 1)
        #expect(concealed.stringValue == "••••")
        // A ragged row reads as an empty cell, not a crash or a neighbouring value.
        #expect(try field(view, row: 2, column: 1).stringValue == "")
    }

    @Test func cellsAreDrawnWithNaturalAlignmentAndConcealmentUsesTheCommentRole() throws {
        let view = makeView()
        let colors = palette()
        view.display(sample, typography: .init(), palette: colors, syntaxStyle: .init(), locale: .current)
        let plain = try field(view, row: 0, column: 0).attributedStringValue.attributes(at: 0, effectiveRange: nil)
        let concealed = try field(view, row: 0, column: 1).attributedStringValue.attributes(at: 0, effectiveRange: nil)
        #expect((plain[.paragraphStyle] as? NSParagraphStyle)?.alignment == .natural)
        #expect((plain[.paragraphStyle] as? NSParagraphStyle)?.baseWritingDirection == .natural)
        #expect((plain[.foregroundColor] as? NSColor)?.isEqual(colors.foreground) == true)
        #expect((concealed[.foregroundColor] as? NSColor)?.isEqual(colors.color(for: .comment)) == true)
    }

    @Test func lineBreaksShowAsSpacesInOneLineWhileTheTooltipKeepsThem() throws {
        let view = makeView()
        let table = SafeTable(columns: ["note"], rows: [["first line\nsecond line, which is rather long\r\nthird"], ["short"]], truncation: [])
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let multiline = try field(view, row: 0, column: 0)
        #expect(multiline.stringValue == "first line second line, which is rather long  third")
        #expect(multiline.toolTip == "first line\nsecond line, which is rather long\r\nthird")
        #expect(try field(view, row: 1, column: 0).toolTip == nil)
    }

    @Test func restylingKeepsColumnsRowsSelectionScrollAndUpdatesRealizedCellsInPlace() throws {
        let view = makeView(height: 160)
        let table = tallTable(rows: 120)
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        try draw(view)
        let columns = view.tableView.tableColumns
        view.tableView.selectRowIndexes(IndexSet([3, 7]), byExtendingSelection: false)
        view.tableView.scrollRowToVisible(60)
        let origin = view.scrollView.contentView.bounds.origin
        var cached: [Int: NSTextField] = [:]
        view.tableView.enumerateAvailableRowViews { rowView, row in
            if let field = rowView.view(atColumn: 0) as? NSTextField { cached[row] = field }
        }
        #expect(!cached.isEmpty)

        let dark = palette(.dark)
        view.display(table, typography: .init(fontSize: 18), palette: dark,
                     syntaxStyle: .init(usesColor: false), locale: .current)
        #expect(view.tableView.tableColumns.elementsEqual(columns, by: ===), "Restyling must not rebuild columns")
        #expect(view.tableView.numberOfRows == 120)
        #expect(view.tableView.selectedRowIndexes == IndexSet([3, 7]))
        #expect(view.scrollView.contentView.bounds.origin == origin)
        var refreshed = 0
        view.tableView.enumerateAvailableRowViews { rowView, row in
            guard let field = rowView.view(atColumn: 0) as? NSTextField else { return }
            #expect(field === cached[row])
            let attributes = field.attributedStringValue.attributes(at: 0, effectiveRange: nil)
            #expect((attributes[.font] as? NSFont)?.pointSize == 18)
            #expect((attributes[.foregroundColor] as? NSColor)?.isEqual(dark.foreground) == true)
            #expect(field.accessibilityValue() == field.stringValue)
            refreshed += 1
        }
        #expect(refreshed == cached.count)
        #expect(view.tableView.rowHeight >= 26)
        // Rows scrolled into view later use the latest appearance as well.
        view.tableView.scrollRowToVisible(110)
        try draw(view)
        view.tableView.enumerateAvailableRowViews { rowView, _ in
            guard let field = rowView.view(atColumn: 0) as? NSTextField else { return }
            #expect((field.attributedStringValue.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont)?.pointSize == 18)
        }
    }

    @Test func aDifferentTableReplacesColumnsAndResetsSelectionAndScroll() throws {
        let view = makeView(height: 160)
        view.display(tallTable(rows: 120), typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        view.tableView.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        view.tableView.scrollRowToVisible(100)
        let old = view.tableView.tableColumns
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(view.tableView.tableColumns.count == 3)
        #expect(view.tableView.tableColumns.allSatisfy { column in !old.contains { $0 === column } })
        #expect(view.tableView.selectedRowIndexes.isEmpty)
        #expect(view.scrollView.contentView.bounds.origin.y <= 0.5)
        #expect(view.tableView.numberOfRows == 3)
    }

    @Test func clearReleasesDataAndResetsViewState() throws {
        let view = makeView(height: 160)
        let truncated = SafeTable(columns: sample.columns, rows: sample.rows, truncation: [.rows])
        view.display(truncated, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        view.tableView.selectAll(nil)
        #expect(!view.tableView.selectedRowIndexes.isEmpty)
        view.clear()
        #expect(view.tableView.numberOfRows == 0)
        #expect(view.tableView.numberOfColumns == 0)
        #expect(view.tableView.selectedRowIndexes.isEmpty)
        #expect((view.scrollView.superview as? NSStackView)?.arrangedSubviews.count == 2)
        #expect(view.filterField.superview?.isHidden == true)
        #expect(view.tableView.accessibilityLabel() == nil)
        #expect(view.scrollView.contentView.bounds.origin.y <= 0.5)
        // A cleared view yields no cells even if AppKit asks for one.
        #expect(view.tableView(view.tableView, viewFor: NSTableColumn(identifier: .init("stale")), row: 0) == nil)
    }

    @Test func localizedLimitsBelongToTheHostAndNeverAppearInsideTheTable() throws {
        let view = makeView()
        let locale = Locale(identifier: "en_US")
        let presentation = plainPresentation("a\n1\n2\n", format: .csv, syntax: .commaSeparated)
        var modes = SafePreviewModes(presentation, locale: locale)
        for truncation in [SafeTable.Truncation.rows, .columns, .cells] {
            let table = SafeTable(columns: sample.columns, rows: sample.rows, truncation: truncation)
            modes.table = table
            view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: locale)
            let notices = ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: locale)
            let expected = truncation == .rows
                ? PreviewStrings.count(.previewTableShownRows, sample.rows.count, locale: locale)
                : PreviewStrings.text(.previewTableLimitCaps)
            #expect(notices == [.init(kind: .limit, text: expected)])
            #expect(!expected.isEmpty)
            #expect(!descendants(of: NSTextField.self, in: view).contains { $0.stringValue == expected })
            #expect((view.scrollView.superview as? NSStackView)?.arrangedSubviews.count == 2)
        }
        modes.table = sample
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: locale)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: locale).isEmpty)
        #expect((view.scrollView.superview as? NSStackView)?.arrangedSubviews.count == 2)
    }

    @Test func copyWritesOnlyTheSafeTextOfSelectedRowsAsTabSeparatedLines() throws {
        let view = makeView()
        let table = SafeTable(columns: ["name", "password", "note"], rows: [
            ["alice", "••••", "a\tb\r\nc"], ["bob", "••••"], ["carol", "••••", "😀 日本語"]
        ], truncation: [])
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        view.tableView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "alice\t••••\ta b  c\ncarol\t••••\t😀 日本語")
        view.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        view.tableView.copy(nil)
        // A ragged row is padded to the table width so every line has the same number of cells.
        #expect(pasteboard.string(forType: .string) == "bob\t••••\t")
    }

    @Test func copyWithoutASelectionLeavesThePasteboardAlone() throws {
        let view = makeView()
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("untouched", forType: .string)
        view.tableView.pasteboard = pasteboard
        view.tableView.deselectAll(nil)
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "untouched")
    }

    @Test func commandCIsClaimedOnlyByTheFirstResponder() throws {
        let view = makeView()
        view.display(sample, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                timestamp: 0, windowNumber: 0, context: nil, characters: "c",
                                                charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        view.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        // No window, so the table is not the first responder and must not intercept the shortcut.
        #expect(!view.tableView.performKeyEquivalent(with: event))
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func reusedCellsReplaceTextColorAccessibilityAndTooltips() throws {
        let view = makeView()
        let table = SafeTable(columns: ["a", "b"], rows: [["••••", "a rather long cell value for a tooltip"], ["plain", "short"]], truncation: [])
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let probe = ReusingTable()
        let columns = view.tableView.tableColumns
        let first = try #require(view.tableView(probe, viewFor: columns[1], row: 0) as? NSTextField)
        #expect(first === probe.reusedField)
        #expect(first.toolTip == "a rather long cell value for a tooltip")
        #expect(first.accessibilityLabel() == "b")
        let reused = try #require(view.tableView(probe, viewFor: columns[0], row: 1) as? NSTextField)
        #expect(reused === first)
        #expect(reused.stringValue == "plain")
        #expect(reused.toolTip == nil)
        #expect(reused.accessibilityLabel() == "a")
        #expect(reused.accessibilityValue() == "plain")
        #expect(reused.isSelectable && !reused.isEditable)
        #expect(reused.identifier == first.identifier)
    }

    @Test func nativePreviewViewOpensDelimitedPresentationsAsATableWithSourceStillAvailable() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let text = "name,password\nalice,••••\n"
        let presentation = TextPresentation(formatID: .csv, text: text, lineCount: 2, byteCount: text.utf8.count,
                                            encoding: .utf8, redactionCount: 1, syntax: .commaSeparated)
        view.display(.ready(presentation))
        let table = try #require(descendants(of: NativeTablePreviewView.self, in: view).first)
        let mode = view.modeControl
        #expect(!table.isHidden)
        #expect(table.tableView.numberOfRows == 1)
        #expect(mode.segmentCount == 3)
        #expect((0..<3).map { mode.label(forSegment: $0) } == [PreviewStrings.text(.previewModeSource), PreviewStrings.text(.previewModeTable),
                                                               PreviewStrings.text(.previewModeProfile)])
        #expect(mode.selectedSegment == 1)
        mode.selectedSegment = 0
        #expect(mode.sendAction(mode.action, to: mode.target))
        #expect(table.isHidden)
        mode.selectedSegment = 1
        #expect(mode.sendAction(mode.action, to: mode.target))
        #expect(!table.isHidden)
        view.display(.unavailable(.malformedDocument))
        #expect(table.isHidden)
        #expect(table.tableView.numberOfRows == 0)
    }

    @Test func malformedSafeTextFallsBackToSafeSourceWithoutATable() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let text = "name,note\nalice,\"never closed\n"
        let presentation = TextPresentation(formatID: .csv, text: text, lineCount: 3, byteCount: text.utf8.count,
                                            encoding: .utf8, redactionCount: 0, syntax: .commaSeparated)
        view.display(.ready(presentation))
        let table = try #require(descendants(of: NativeTablePreviewView.self, in: view).first)
        #expect(table.isHidden)
        #expect(table.tableView.numberOfRows == 0)
        let source = view.scrollView.documentView as? NSTextView
        #expect(source?.string == text)
    }

    // MARK: Spoken descriptions

    @Test func aDescribedCellIsReadAloudFromItsDescriptionWhileItsTextStaysAndOtherCellsAreUnchanged() throws {
        let view = makeView()
        var table = SafeTable(columns: ["bars", "name"], rows: [["▁▃█", "alice"], ["█▃▁", "bob"]], truncation: [])
        table.cellDescriptions = [.init(row: 0, column: 0): "rising from low to high"]
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let described = try field(view, row: 0, column: 0)
        #expect(described.stringValue == "▁▃█")
        #expect(described.accessibilityValue() as? String == "rising from low to high")
        #expect(described.accessibilityLabel() == "bars")
        let plain = try field(view, row: 0, column: 1)
        #expect(plain.accessibilityValue() as? String == "alice")
        let undescribed = try field(view, row: 1, column: 0)
        #expect(undescribed.accessibilityValue() as? String == "█▃▁", "Only cells with a description differ")
        // Copy keeps the visible text.
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        view.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "▁▃█\talice")
    }

    @Test func aReusedCellDropsTheDescriptionOfItsPreviousValue() throws {
        let view = makeView()
        var table = SafeTable(columns: ["a"], rows: [["▁█"], ["plain"]], truncation: [])
        table.cellDescriptions = [.init(row: 0, column: 0): "described"]
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let probe = ReusingCellTable()
        let first = try #require(view.tableView(probe, viewFor: view.tableView.tableColumns[0], row: 0) as? SafeTableCellField)
        #expect(first === probe.reusedField)
        #expect(first.accessibilityValue() as? String == "described")
        let reused = try #require(view.tableView(probe, viewFor: view.tableView.tableColumns[0], row: 1) as? SafeTableCellField)
        #expect(reused === first)
        #expect(reused.stringValue == "plain")
        #expect(reused.accessibilityValue() as? String == "plain")
    }

    @Test func aDescribedCellKeepsItsOwnDescriptionAfterSortAndFilter() throws {
        let view = makeView()
        var table = SafeTable(columns: ["name", "bars"], rows: [["alpha", "▁▃█"], ["bravo", "plain"], ["charlie", "▃▃▃"]],
                              truncation: [])
        // Descriptions are keyed by source row, and each one names the row it belongs to.
        table.cellDescriptions = [.init(row: 0, column: 1): "alpha rises", .init(row: 2, column: 1): "charlie is flat"]
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)

        view.sortRows(column: 0, ascending: false)
        // The display order is now charlie, bravo, alpha; every cell reads the description of its own source row.
        #expect(try field(view, row: 0, column: 0).stringValue == "charlie")
        #expect(try field(view, row: 0, column: 1).stringValue == "▃▃▃")
        #expect(try field(view, row: 0, column: 1).accessibilityValue() as? String == "charlie is flat")
        #expect(try field(view, row: 1, column: 1).accessibilityValue() as? String == "plain", "An undescribed cell reads its own text")
        #expect(try field(view, row: 2, column: 1).stringValue == "▁▃█")
        #expect(try field(view, row: 2, column: 1).accessibilityValue() as? String == "alpha rises")

        view.setFilter("charlie")
        #expect(view.tableView.numberOfRows == 1)
        let remaining = try field(view, row: 0, column: 1)
        #expect(remaining.stringValue == "▃▃▃")
        #expect(remaining.accessibilityValue() as? String == "charlie is flat")

        // Clearing the filter keeps the sort, and each description is still on its own row.
        view.setFilter("")
        #expect(view.tableView.numberOfRows == 3)
        #expect(try field(view, row: 2, column: 1).accessibilityValue() as? String == "alpha rises")
    }

    @Test func tablesWithDifferentDescriptionsOrHeaderWidthsAreNotEqualSoTheViewRefreshes() throws {
        let base = SafeTable(columns: ["a"], rows: [["x"]], truncation: [])
        var described = base
        described.cellDescriptions = [.init(row: 0, column: 0): "one"]
        var other = base
        other.cellDescriptions = [.init(row: 0, column: 0): "two"]
        var composed = base
        composed.cellDescriptions = [.init(row: 0, column: 0): "\u{E9}"]
        var decomposed = base
        decomposed.cellDescriptions = [.init(row: 0, column: 0): "e\u{301}"]
        #expect(base != described && described != other)
        #expect(described == described)
        #expect(composed != decomposed, "Exact code units, as for cells")
        var wider = base
        wider.headerFieldCount = 3
        #expect(base != wider)
        var same = base
        same.headerFieldCount = nil
        #expect(base == same)
        let view = makeView()
        view.display(base, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let columns = view.tableView.tableColumns
        view.display(described, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(!view.tableView.tableColumns.elementsEqual(columns, by: ===), "A table that differs only by description is rebuilt")
        #expect(try field(view, row: 0, column: 0).accessibilityValue() as? String == "one")
    }

    // MARK: Helpers

    private var sample: SafeTable {
        SafeTable(columns: ["name", "password", "note"],
                  rows: [["alice", "••••", "hello, world"], ["bob", "••••", "ok"], ["carol"]], truncation: [])
    }

    private func tallTable(rows: Int) -> SafeTable {
        SafeTable(columns: ["id", "label"], rows: (0..<rows).map { ["row \($0)", "label \($0)"] }, truncation: [])
    }

    private func makeView(height: CGFloat = 300) -> NativeTablePreviewView {
        let view = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    private func field(_ view: NativeTablePreviewView, row: Int, column: Int) throws -> NSTextField {
        try #require(view.tableView(view.tableView, viewFor: view.tableView.tableColumns[column], row: row) as? NSTextField)
    }

    private func draw(_ view: NSView) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    private func palette(_ theme: PreviewTheme = .system) -> NativeTextPalette {
        .init(theme: theme, isDark: theme == .dark, increasedContrast: false)
    }
}

@MainActor private final class ReusingCellTable: NSTableView {
    let reusedField = SafeTableCellField(labelWithString: "")
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { reusedField }
}

@MainActor private final class ReusingTable: NSTableView {
    let reusedField = NSTextField(labelWithString: "")
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { reusedField }
}
