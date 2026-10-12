import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Sortable, filterable table view", .serialized)
@MainActor
struct SortableTableViewTests {
    private var table: SafeTable {
        SafeTable(columns: ["name", "size", "when"],
                  rows: [["b-10", "300", "2026-02-01"], ["B-2", "20", ""], ["a", "", "2025-12-31"], ["c", "20", "2026-02-01"], ["Zoë", "5", "2026-03-01"]],
                  truncation: [], columnKinds: [.text, .number, .date],
                  sortKeys: [1: [300, 20, nil, 20, 5], 2: [1_769_904_000, nil, 1_767_139_200, 1_769_904_000, 1_772_323_200]])
    }

    @Test func theHeaderStaysVisibleRowsAlternateAndTheFilterControlsAreLabelled() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        #expect(view.tableView.headerView != nil)
        #expect(view.tableView.usesAlternatingRowBackgroundColors)
        #expect(view.scrollView.documentView === view.tableView)
        #expect(view.filterField.placeholderString == PreviewStrings.text(.listingFilterPlaceholder))
        #expect(view.filterField.accessibilityLabel() == PreviewStrings.text(.listingFilterLabel))
        #expect(view.filterField.accessibilityHelp() == PreviewStrings.text(.listingFilterHelp))
        #expect(view.sortButton.accessibilityLabel() == PreviewStrings.text(.listingSortMenu))
        #expect(view.tableView.tableColumns.allSatisfy { $0.sortDescriptorPrototype != nil })
        #expect(view.filterField.superview?.isHidden == false)
    }

    @Test func clickingAHeaderSortsByThatColumnAndTheSecondClickReversesIt() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.tableView.sortDescriptors = [NSSortDescriptor(key: "1", ascending: true)]
        view.tableView(view.tableView, sortDescriptorsDidChange: [])
        #expect(try firstColumn(view) == ["Zoë", "B-2", "c", "b-10", "a"])
        view.tableView.sortDescriptors = [NSSortDescriptor(key: "1", ascending: false)]
        view.tableView(view.tableView, sortDescriptorsDidChange: [])
        #expect(try firstColumn(view) == ["b-10", "B-2", "c", "Zoë", "a"])
        view.tableView.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
        view.tableView(view.tableView, sortDescriptorsDidChange: [])
        #expect(try firstColumn(view) == ["a", "B-2", "b-10", "c", "Zoë"])
    }

    @Test func theSortMenuListsColumnsAndDirectionsAndDrivesTheSameSort() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        let items = try #require(view.sortButton.menu?.items)
        #expect(items.map(\.title) == [PreviewStrings.text(.listingSortMenu), "name", "size", "when", "",
                                       PreviewStrings.text(.listingSortAscending), PreviewStrings.text(.listingSortDescending)])
        #expect(items[4].isSeparatorItem)
        #expect(!items[5].isEnabled && !items[6].isEnabled, "Direction needs a chosen column")
        view.sortRows(column: 2, ascending: false)
        #expect(try firstColumn(view) == ["Zoë", "b-10", "c", "a", "B-2"])
        #expect(view.tableView.sortDescriptors.first?.key == "2")
        #expect(view.tableView.sortDescriptors.first?.ascending == false)
        let after = try #require(view.sortButton.menu?.items)
        #expect(after[3].state == .on && after[1].state == .off)
        #expect(after[5].isEnabled && after[6].isEnabled)
        #expect(after[6].state == .on && after[5].state == .off)
        // Invoking the menu items reaches the same code.
        let item = after[2]
        _ = item.target?.perform(try #require(item.action), with: item)
        #expect(try firstColumn(view) == ["b-10", "B-2", "c", "Zoë", "a"], "Choosing a column keeps the current direction")
        view.sortRows(column: 99, ascending: true)
        #expect(view.tableView.sortDescriptors.first?.key != "99")
    }

    @Test func filteringHidesRowsKeepsTheSortAndReportsHowManyRemain() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.sortRows(column: 0, ascending: true)
        view.setFilter("B")
        #expect(view.filterField.stringValue == "B")
        #expect(try firstColumn(view) == ["B-2", "b-10"])
        #expect(view.tableView.numberOfRows == 2)
        #expect(view.tableView.accessibilityLabel() == PreviewStrings.format(
            .previewTableAccessibilityLabel, arguments: [Int64(2), Int64(3)], locale: english))
        view.setFilter("zoe")
        #expect(try firstColumn(view) == ["Zoë"])
        view.setFilter("nothing matches")
        #expect(view.tableView.numberOfRows == 0)
        view.setFilter("")
        #expect(view.tableView.numberOfRows == 5)
        #expect(try firstColumn(view) == ["a", "B-2", "b-10", "c", "Zoë"], "The sort survives clearing the filter")
    }

    @Test func theFilterActionOfTheSearchFieldAppliesTheTypedText() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.filterField.stringValue = "2026-03"
        let action = try #require(view.filterField.action)
        #expect(view.filterField.sendAction(action, to: view.filterField.target))
        #expect(try firstColumn(view) == ["Zoë"])
    }

    @Test func selectionFollowsTheSameRowsThroughSortingAndFiltering() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.tableView.selectRowIndexes(IndexSet([0, 3]), byExtendingSelection: false)   // b-10 and c
        view.sortRows(column: 0, ascending: true)
        let selected = view.tableView.selectedRowIndexes.map { try? cell(view, row: $0, column: 0) }
        #expect(Set(selected.compactMap { $0 }) == ["b-10", "c"])
        view.setFilter("b-")
        #expect(view.tableView.selectedRowIndexes.count == 1)
        #expect(try cell(view, row: view.tableView.selectedRow, column: 0) == "b-10")
    }

    @Test func copyUsesTheDisplayedOrderAndOnlyTheSelectedVisibleRows() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.sortRows(column: 1, ascending: true)
        view.setFilter("2026-02")
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        view.tableView.selectAll(nil)
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "c\t20\t2026-02-01\nb-10\t300\t2026-02-01")
    }

    @Test func aDifferentTableResetsTheSortFilterAndSelectionButRestylingDoesNot() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.sortRows(column: 1, ascending: false)
        view.setFilter("b")
        view.display(table, typography: .init(fontSize: 20), palette: palette(.dark), syntaxStyle: .init(), locale: english)
        #expect(view.filterField.stringValue == "b")
        #expect(view.tableView.sortDescriptors.first?.key == "1")
        #expect(view.tableView.numberOfRows == 2)
        let other = SafeTable(columns: ["x"], rows: [["1"], ["2"]], truncation: [])
        view.display(other, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        #expect(view.filterField.stringValue.isEmpty)
        #expect(view.tableView.sortDescriptors.isEmpty)
        #expect(view.tableView.numberOfRows == 2)
        #expect(view.sortButton.menu?.items.map(\.title).contains("x") == true)
    }

    @Test func clearRemovesTheFilterBarSortStateAndRows() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.sortRows(column: 1, ascending: true)
        view.setFilter("a")
        view.clear()
        #expect(view.tableView.numberOfRows == 0)
        #expect(view.tableView.numberOfColumns == 0)
        #expect(view.filterField.stringValue.isEmpty)
        #expect(view.filterField.superview?.isHidden == true)
        #expect(view.tableView.sortDescriptors.isEmpty)
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        #expect(view.tableView.numberOfRows == 5, "A cleared view shows the next table unfiltered")
    }

    @Test func partialListingAndRowLimitsAreSeparateHostNotices() throws {
        let view = makeView()
        let presentation = plainPresentation("safe words")
        var modes = SafePreviewModes(presentation, locale: english)
        let partial = SafeTable(columns: ["a"], rows: [["1"]], truncation: [.partialListing], origin: .listing)
        modes.table = partial
        view.display(partial, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        let notice = PreviewStrings.text(.listingPartialNotice)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: english)
            == [.init(kind: .limit, text: notice)])
        #expect(!descendants(of: NSTextField.self, in: view).contains { $0.stringValue == notice })
        let both = SafeTable(columns: ["a"], rows: [["1"]], truncation: [.partialListing, .rows], origin: .listing)
        modes.table = both
        view.display(both, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        let rows = PreviewStrings.count(.previewTableShownRows, 1, locale: english)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: english)
            == [.init(kind: .limit, text: notice), .init(kind: .limit, text: rows)])
        #expect(!descendants(of: NSTextField.self, in: view).contains { $0.stringValue == notice || $0.stringValue == rows })
    }

    @Test func commandFMovesFocusToTheFilterField() throws {
        let view = makeView()
        view.display(table, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view.tableView)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, characters: "f",
                                                  charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        #expect(view.tableView.performKeyEquivalent(with: event))
        let editor = window.firstResponder as? NSText
        #expect(editor != nil && (editor?.delegate as? NSSearchField) === view.filterField)
    }

    @Test func typedCSVColumnsSortByValueNotSpelling() throws {
        let csv = try #require(SafeDelimitedTable.table("n,name\n10,x\n9,y\n100,z\n-5,w\n", syntax: .commaSeparated, locale: english))
        let view = makeView()
        view.display(csv, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.sortRows(column: 0, ascending: true)
        #expect(try firstColumn(view) == ["-5", "9", "10", "100"])
        view.sortRows(column: 1, ascending: false)
        #expect(try firstColumn(view) == ["100", "9", "10", "-5"])
    }

    // MARK: Helpers

    private let english = Locale(identifier: "en_US")

    private func makeView() -> NativeTablePreviewView {
        let view = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    private func palette(_ theme: PreviewTheme = .system) -> NativeTextPalette {
        .init(theme: theme, isDark: theme == .dark, increasedContrast: false)
    }

    private func cell(_ view: NativeTablePreviewView, row: Int, column: Int) throws -> String {
        try #require(view.tableView(view.tableView, viewFor: view.tableView.tableColumns[column], row: row) as? NSTextField).stringValue
    }

    private func firstColumn(_ view: NativeTablePreviewView) throws -> [String] {
        try (0..<view.tableView.numberOfRows).map { try cell(view, row: $0, column: 0) }
    }
}

@Suite("Listing views in the preview", .serialized)
@MainActor
struct ListingPreviewViewTests {
    private let english = Locale(identifier: "en_US")

    private func show(_ presentation: TextPresentation = listingPresentation(archiveListingJSON, format: .zip)) -> NativePreviewView {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        view.display(.ready(presentation), locale: english)
        return view
    }

    private func modeControl(_ view: NativePreviewView) throws -> NSSegmentedControl {
        view.modeControl
    }

    private func select(_ title: PreviewStrings.Key, in view: NativePreviewView) throws {
        let control = try modeControl(view)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == PreviewStrings.text(title) })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }

    @Test func aListingOpensInFilesWithSourceSummaryAndTreeAlongside() throws {
        let view = show()
        let control = try modeControl(view)
        let labels = (0..<control.segmentCount).map { control.label(forSegment: $0) }
        #expect(labels == [.previewModeSource, .previewModeSummary, .previewModeFiles, .previewModeTree].map { PreviewStrings.text($0) })
        #expect(control.selectedSegment == 2)
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        #expect(!files.isHidden)
        #expect(files.table.tableView.numberOfRows == 5)
        #expect(files.table.tableView.tableColumns.map(\.title) == [PreviewStrings.text(.summaryName), PreviewStrings.text(.listingColumnKind),
                                                                    PreviewStrings.text(.listingColumnSize), PreviewStrings.text(.listingModifiedUTC)])
        #expect(descendants(of: NativeListingTreeView.self, in: view).isEmpty, "Tree is created lazily")
    }

    @Test func filesCellsShowLocalizedKindsSizesAndDatesAndSortBySize() throws {
        let view = show()
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        let table = files.table
        func text(_ row: Int, _ column: Int) throws -> String {
            try #require(table.tableView(table.tableView, viewFor: table.tableView.tableColumns[column], row: row) as? NSTextField).stringValue
        }
        #expect(try text(0, 0) == "empty/")
        #expect(try text(0, 1) == PreviewStrings.text(.summaryKindDirectory))
        #expect(try text(4, 0) == "README.md")
        #expect(try text(4, 2).lowercased().contains("kb"))
        #expect(try text(3, 3).contains("12:30"))
        table.sortRows(column: 2, ascending: false)
        #expect(try text(0, 0) == "README.md")
        #expect(try text(1, 0) == "src/main.swift")
        #expect(try text(4, 2) == "", "Rows without a size sort last")
    }

    @Test func theTreeShowsFoldersWithCountsAndSizesAndExpandsSmallListings() throws {
        let view = show()
        try select(.previewModeTree, in: view)
        let tree = try #require(descendants(of: NativeListingTreeView.self, in: view).first)
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        #expect(!tree.isHidden && files.isHidden)
        let outline = tree.outlineView
        #expect(outline.numberOfRows == 6)
        #expect(outline.tableColumns.map(\.title) == [PreviewStrings.text(.summaryName), PreviewStrings.text(.listingItems),
                                                      PreviewStrings.text(.listingColumnSize), PreviewStrings.text(.listingModifiedUTC)])
        #expect(outline.accessibilityLabel() == PreviewStrings.text(.listingTreeAccessibilityLabel))
        func name(_ row: Int) throws -> String {
            let item = try #require(outline.item(atRow: row))
            return try #require((outline.delegate?.outlineView?(outline, viewFor: outline.tableColumns[0], item: item) as? NSTableCellView)?.textField?.stringValue)
        }
        func value(_ row: Int, _ column: Int) throws -> String {
            let item = try #require(outline.item(atRow: row))
            return try #require(outline.delegate?.outlineView?(outline, viewFor: outline.tableColumns[column], item: item) as? NSTextField).stringValue
        }
        #expect(try (0..<6).map(name) == ["empty", "src", "util", "helpers.swift", "main.swift", "README.md"])
        #expect(try value(1, 1) == "2")
        #expect(try value(1, 2).lowercased().contains("kb"))
        #expect(try value(3, 1) == "", "Files have no item count")
        #expect(try value(0, 1) == "", "An explicit empty folder reports no guessed count")
        #expect(view.limitsLabel.stringValue.isEmpty && view.limitsLabel.isHidden)
    }

    @Test func largeTreesOpenCollapsedToTheirTopLevelAndAPartialListingSaysSo() throws {
        let entries = (0..<400).map { #"{"path":"dir\#($0 % 8)/file-\#($0).txt","type":"file","bytes":10}"# }
        let json = #"{"partial":true,"entries":["# + entries.joined(separator: ",") + "]}"
        let view = show(listingPresentation(json))
        try select(.previewModeTree, in: view)
        let tree = try #require(descendants(of: NativeListingTreeView.self, in: view).first)
        #expect(tree.outlineView.numberOfRows == 8)
        let notice = PreviewStrings.text(.listingPartialNotice)
        #expect(view.limitsLabel.stringValue == notice && !view.limitsLabel.isHidden)
        #expect(!descendants(of: NSTextField.self, in: tree).contains { $0.stringValue == notice })
        let item = try #require(tree.outlineView.item(atRow: 0))
        tree.outlineView.expandItem(item)
        #expect(tree.outlineView.numberOfRows == 8 + 50)
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        #expect(!descendants(of: NSTextField.self, in: files).contains { $0.stringValue == notice })
        try select(.previewModeFiles, in: view)
        #expect(view.limitsLabel.stringValue == notice && !view.limitsLabel.isHidden)
        try select(.previewModeSource, in: view)
        #expect(view.limitsLabel.stringValue == notice && !view.limitsLabel.isHidden)
    }

    @Test func treeCopyWritesOnlyTheSafeTextOfSelectedRows() throws {
        let view = show()
        try select(.previewModeTree, in: view)
        let tree = try #require(descendants(of: NativeListingTreeView.self, in: view).first)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        tree.outlineView.pasteboard = pasteboard
        tree.outlineView.selectRowIndexes(IndexSet([1, 4]), byExtendingSelection: false)
        tree.outlineView.copy(nil)
        let lines = try #require(pasteboard.string(forType: .string)).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("src\t2\t"))
        #expect(lines[1].hasPrefix("src/main.swift\t\t"))
        tree.outlineView.deselectAll(nil)
        pasteboard.setString("untouched", forType: .string)
        tree.outlineView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "untouched")
    }

    @Test func restylingKeepsTheTreeItemsAndSelectionButAReplacementClearsThem() throws {
        let view = show()
        try select(.previewModeTree, in: view)
        let tree = try #require(descendants(of: NativeListingTreeView.self, in: view).first)
        let first = tree.outlineView.item(atRow: 1) as AnyObject?
        tree.outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        view.display(.ready(listingPresentation(archiveListingJSON, format: .zip)), typography: .init(fontSize: 18), theme: .dark, locale: english)
        #expect((tree.outlineView.item(atRow: 1) as AnyObject?) === first)
        #expect(tree.outlineView.selectedRow == 1)
        let replacement = listingPresentation(#"{"entries":[{"path":"only.txt","type":"file","bytes":1}]}"#, format: .zip)
        view.display(.ready(replacement), locale: english, resetsContentState: true)
        #expect(tree.outlineView.selectedRowIndexes.isEmpty)
        #expect(tree.outlineView.numberOfRows <= 1)
        view.display(.unavailable(.malformedDocument))
        #expect(tree.isHidden)
        #expect(tree.outlineView.numberOfRows == 0)
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        #expect(files.isHidden)
        #expect(files.table.tableView.numberOfRows == 0)
    }

    @Test func aDisabledTypeShowsNoListingContent() throws {
        let view = show()
        view.display(.disabledByUser(.zip))
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        #expect(files.isHidden)
        #expect(files.table.tableView.numberOfRows == 0)
        let control = try modeControl(view)
        #expect(control.isHidden)
    }

    @Test func switchingModesAndLocalesKeepsFilesAndTreeInStep() throws {
        let view = show()
        view.display(.ready(listingPresentation(archiveListingJSON, format: .zip)), locale: Locale(identifier: "de_DE"))
        let files = try #require(descendants(of: NativeListingFilesView.self, in: view).first)
        let table = files.table
        let size = try #require(table.tableView(table.tableView, viewFor: table.tableView.tableColumns[2], row: 4) as? NSTextField).stringValue
        #expect(size.contains("2") && size.lowercased().contains("kb"))
        try select(.previewModeSource, in: view)
        #expect(files.isHidden)
        try select(.previewModeFiles, in: view)
        #expect(!files.isHidden)
    }
}
