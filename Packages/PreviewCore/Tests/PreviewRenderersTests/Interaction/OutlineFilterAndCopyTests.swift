import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Outline filter and row copy actions", .serialized)
@MainActor
struct OutlineFilterAndCopyTests {
    // MARK: Filter

    @Test func filterKeepsMatchesAndOpensTheirAncestors() throws {
        let (view, outline) = makeOutline()
        #expect(rows(outline) == ["$", "users", "password", "my key", "count"])
        let summary = view.setFilter("jose")
        #expect(summary == OutlineFilterSummary(isActive: true, matchCount: 1))
        #expect(rows(outline) == ["$", "users", "[0]", "name"])
        for row in 0..<3 {
            #expect(outline.isItemExpanded(outline.item(atRow: row)))
        }
    }

    @Test func matchingIgnoresCaseAndDiacriticsInKeysAndValues() throws {
        let (view, outline) = makeOutline()
        #expect(view.setFilter("ZOE").matchCount == 1)
        #expect(rows(outline) == ["$", "users", "[1]", "name"])
        #expect(view.setFilter("Admin").matchCount == 1)
        #expect(rows(outline) == ["$", "users", "[0]", "role"])
        // Keys and values both count, and every matching row is listed.
        #expect(view.setFilter("name").matchCount == 2)
        #expect(rows(outline) == ["$", "users", "[0]", "name", "[1]", "name"])
        #expect(view.setFilter("PASS").matchCount == 1)
        #expect(rows(outline) == ["$", "password"])
        // The query is a literal substring, never a pattern.
        #expect(view.setFilter(".*").matchCount == 0)
    }

    @Test func noMatchesIsAnActiveStateWithAnAnnouncedCount() throws {
        let (view, outline) = makeOutline()
        let summary = view.setFilter("zzz")
        #expect(summary == OutlineFilterSummary(isActive: true, matchCount: 0))
        #expect(rows(outline).isEmpty)
        #expect(OutlineFilterBar.countText(for: summary) == PreviewStrings.text(.interactionFilterNoMatches))
        #expect(OutlineFilterBar.countText(for: OutlineFilterSummary(isActive: true, matchCount: 4))
                == PreviewStrings.format(.interactionFilterMatches, arguments: [Int64(4)]))
        #expect(OutlineFilterBar.countText(for: OutlineFilterSummary()) == "")
    }

    @Test func aMatchedContainerKeepsItsWholeSubtreeAvailableAndContainerMarkersNeverMatch() throws {
        let (view, outline) = makeOutline()
        #expect(view.setFilter("users").matchCount == 1)
        #expect(rows(outline) == ["$", "users"])
        let users = try #require(outline.item(atRow: 1))
        #expect(outline.isExpandable(users) && !outline.isItemExpanded(users))
        outline.expandItem(users)
        #expect(rows(outline) == ["$", "users", "[0]", "[1]"])
        #expect(view.setFilter("…").matchCount == 0)
        #expect(view.setFilter("{").matchCount == 0)
    }

    @Test func clearingTheFilterRestoresWhatWasOpenBeforeIt() throws {
        let (view, outline) = makeOutline()
        let users = try #require(outline.item(atRow: 1))
        outline.expandItem(users)
        let before = rows(outline)
        #expect(before == ["$", "users", "[0]", "[1]", "password", "my key", "count"])
        view.setFilter("zoe")
        #expect(rows(outline) != before)
        let summary = view.setFilter("   ")
        #expect(summary == OutlineFilterSummary())
        #expect(rows(outline) == before)
    }

    @Test func nextAndPreviousMatchWrapAroundTheListedMatches() throws {
        let (view, outline) = makeOutline()
        view.setFilter("name")
        let matchRows = (0..<outline.numberOfRows).filter { (outline.item(atRow: $0) as? OutlineItem)?.isMatch == true }
        #expect(matchRows.count == 2)
        #expect(view.selectAdjacentMatch(forward: true))
        #expect(outline.selectedRow == matchRows[0])
        #expect(view.selectAdjacentMatch(forward: true))
        #expect(outline.selectedRow == matchRows[1])
        #expect(view.selectAdjacentMatch(forward: true))
        #expect(outline.selectedRow == matchRows[0])
        #expect(view.selectAdjacentMatch(forward: false))
        #expect(outline.selectedRow == matchRows[1])
        view.setFilter("")
        #expect(!view.selectAdjacentMatch(forward: true))
    }

    @Test func replacingTheNodesKeepsWhatTheReaderOpenedSelectedAndTyped() throws {
        let (view, outline) = makeOutline()
        let users = try #require(outline.item(atRow: 1))
        outline.expandItem(users)
        let second = try #require(outline.item(atRow: 3))
        outline.expandItem(second)
        let nameRow = try #require((0..<outline.numberOfRows).first {
            (outline.item(atRow: $0) as? OutlineItem)?.node.value == "Zoë"
        })
        outline.selectRowIndexes(IndexSet(integer: nameRow), byExtendingSelection: false)
        // The file changed elsewhere: one unrelated value differs.
        var changed = fixture()
        changed = [SafeOutlineNode(id: 0, name: "$", value: "{…}", children: changed[0].children.map {
            $0.name == "count" ? SafeOutlineNode(id: $0.id, name: $0.name, value: "4") : $0
        })]
        view.display(changed, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(rows(outline) == ["$", "users", "[0]", "[1]", "name", "role", "password", "my key", "count"])
        let selected = try #require(outline.item(atRow: outline.selectedRow) as? OutlineItem)
        #expect(selected.node.value == "Zoë")
        // A filter survives the replacement and its result is recomputed.
        var results: [OutlineFilterSummary] = []
        view.onFilterResult = { results.append($0) }
        view.setFilter("viewer")
        view.display(changed, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(results.last == OutlineFilterSummary(isActive: true, matchCount: 1))
        var changedAgain = changed
        changedAgain[0] = SafeOutlineNode(id: 0, name: "$", value: "{…}", children: changed[0].children + [
            .init(id: 99, name: "extra", value: "Viewer too")])
        view.display(changedAgain, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(results.last == OutlineFilterSummary(isActive: true, matchCount: 2))
        #expect(rows(outline).contains("extra"))
    }

    @Test func clearingTheViewForANewRequestForgetsTheFilter() throws {
        let (view, outline) = makeOutline()
        view.setFilter("zoe")
        view.clear()
        #expect(view.filterQuery == nil && view.filterSummary == OutlineFilterSummary())
        view.display(fixture(), typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(rows(outline) == ["$", "users", "password", "my key", "count"])
    }

    @Test func filteringTwentyThousandRowsIsOneLinearPass() throws {
        let nodes = [SafeOutlineNode(id: 0, name: "$", value: "{…}", children: (1...19_999).map {
            SafeOutlineNode(id: $0, name: "key\($0)", value: "value\($0)")
        })]
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let clock = ContinuousClock()
        var summary = OutlineFilterSummary()
        let elapsed = clock.measure { summary = view.setFilter("key19999") }
        #expect(summary.matchCount == 1)
        #expect(elapsed < .seconds(5))
        // A second query reuses the folded text instead of folding every field again.
        let second = clock.measure { summary = view.setFilter("VALUE15000") }
        #expect(summary.matchCount == 1)
        #expect(second < .seconds(5))
    }

    // MARK: The filter bar inside the preview

    @Test func outlineModesShowTheFilterBarAndItDrivesTheRows() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let json = #"{"members":[{"path":"safe😀","type":"file"},{"path":"other","type":"directory"}]}"#
        host.show(plainPresentation(json, format: .folder, syntax: .json))
        let bar = host.view.accessoryBar
        #expect(bar.content == .filter && !bar.filterBar.isHidden)
        #expect(host.view.accessoryHeightConstraint?.constant == PreviewAccessoryBar.height)
        let field = bar.filterBar.searchField
        #expect(field.accessibilityLabel() == PreviewStrings.text(.interactionFilterLabel))
        #expect(field.accessibilityHelp() == PreviewStrings.text(.interactionFilterHelp))
        let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
        let allRows = outline.numberOfRows
        field.stringValue = "SAFE"
        field.sendAction(field.action, to: field.target)
        #expect(host.view.outlineView.filterSummary.matchCount >= 1)
        // A matching row is listed, with its ancestors opened to reach it.
        #expect((0..<outline.numberOfRows).contains { (outline.item(atRow: $0) as? OutlineItem)?.isMatch == true })
        let count = OutlineFilterBar.countText(for: host.view.outlineView.filterSummary)
        #expect(host.announcements.texts.last == count)
        #expect(descendants(of: bar.filterBar).compactMap { $0 as? NSTextField }.contains { $0.stringValue == count })
        // Command-F in an outline focuses the filter instead of the text finder.
        host.window.makeFirstResponder(outline)
        #expect(host.press("f", .command))
        #expect(host.window.firstResponder === field.currentEditor())
        // Escape clears the text, a second Escape returns to the rows.
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(bar.filterBar.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(field.stringValue.isEmpty && outline.numberOfRows == allRows)
        #expect(host.view.outlineView.filterSummary == OutlineFilterSummary())
        #expect(bar.filterBar.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(host.window.firstResponder === outline)
        field.stringValue = "zzzzzz"
        field.sendAction(field.action, to: field.target)
        #expect(host.announcements.texts.last == PreviewStrings.text(.interactionFilterNoMatches))
    }

    @Test func leavingTheOutlineOrStartingANewRequestClearsTheFilter() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let json = #"{"members":[{"path":"safe😀","type":"file"}]}"#
        host.show(plainPresentation(json, format: .folder, syntax: .json))
        let field = host.view.accessoryBar.filterBar.searchField
        field.stringValue = "safe"
        field.sendAction(field.action, to: field.target)
        #expect(host.view.outlineView.filterSummary.isActive)
        let control = host.view.modeControl
        control.selectedSegment = 0
        #expect(control.sendAction(control.action, to: control.target))
        #expect(host.view.accessoryBar.content == .none && field.stringValue.isEmpty)
        #expect(!host.view.outlineView.filterSummary.isActive)
        control.selectedSegment = 1
        #expect(control.sendAction(control.action, to: control.target))
        #expect(host.view.accessoryBar.content == .filter && field.stringValue.isEmpty)
        field.stringValue = "safe"
        field.sendAction(field.action, to: field.target)
        host.show(plainPresentation(json, format: .folder, syntax: .json), resetsContentState: true)
        #expect(field.stringValue.isEmpty && !host.view.outlineView.filterSummary.isActive)
    }

    @Test func selectingASingleOutlineRowShowsItsBreadcrumbPathInTheFilterBar() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let json = #"{"members":[{"path":"safe😀","type":"file"},{"path":"other","type":"directory"}]}"#
        host.show(plainPresentation(json, format: .folder, syntax: .json))
        let bar = host.view.accessoryBar
        let pathLabel = bar.filterBar.pathLabel
        #expect(pathLabel.isHidden)
        #expect(pathLabel.stringValue.isEmpty)
        let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(!pathLabel.isHidden)
        #expect(pathLabel.stringValue == "$.Summary")
        #expect(pathLabel.toolTip == "$.Summary")
        let members = try #require(outline.item(atRow: 1))
        outline.expandItem(members)
        let firstMemberRow = try #require(row(named: "[0]", in: outline))
        outline.selectRowIndexes(IndexSet(integer: firstMemberRow), byExtendingSelection: false)
        #expect(!pathLabel.isHidden)
        #expect(pathLabel.stringValue == "$.Summary.members[0]")
        #expect(pathLabel.toolTip == "$.Summary.members[0]")
        let menu = try #require(bar.filterBar.pathContextMenu())
        #expect(menu.items.map(\.title) == [PreviewStrings.text(.interactionCopyPath)])
        let copyItem = try #require(menu.items.first)
        _ = copyItem.target?.perform(copyItem.action, with: copyItem)
        #expect(host.pasteboard.string(forType: .string) == "$.Summary.members[0]")
        outline.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        #expect(pathLabel.isHidden)
        #expect(pathLabel.stringValue.isEmpty)
        #expect(pathLabel.toolTip == nil)
        outline.selectRowIndexes(IndexSet(integer: firstMemberRow), byExtendingSelection: false)
        #expect(!pathLabel.isHidden)
        #expect(pathLabel.stringValue == "$.Summary.members[0]")
        outline.deselectAll(nil)
        #expect(pathLabel.isHidden)
        #expect(pathLabel.stringValue.isEmpty)
        #expect(pathLabel.toolTip == nil)
        #expect(bar.filterBar.pathContextMenu() == nil)
    }

    @Test func compactOutlineFilterBarShrinksSearchFieldAndExposesMatchCountTooltip() throws {
        let host = InteractionHarness(width: 240)
        defer { host.release() }
        host.show(plainPresentation(#"{"members":[{"path":"a","type":"file"}]}"#, format: .folder, syntax: .json))
        let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let field = host.view.accessoryBar.filterBar.searchField
        field.stringValue = "a"
        field.sendAction(field.action, to: field.target)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.accessoryBar.filterBar.searchField.controlSize == .small)
        #expect(host.view.accessoryBar.filterBar.searchField.frame.width <= 132)
        #expect(host.view.accessoryBar.filterBar.countLabel.toolTip == host.view.accessoryBar.filterBar.countLabel.stringValue)
        #expect(host.view.accessoryBar.filterBar.pathLabel.stringValue == "$.Summary")
        #expect(host.view.accessoryBar.filterBar.pathLabel.isHidden)
        host.window.setContentSize(NSSize(width: 600, height: 420))
        host.view.setFrameSize(NSSize(width: 600, height: 420))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.accessoryBar.filterBar.searchField.controlSize == .regular)
        #expect(host.view.accessoryBar.filterBar.searchField.frame.width >= 140)
        #expect(!host.view.accessoryBar.filterBar.pathLabel.isHidden)
    }

    // MARK: Row copy actions

    @Test func rowCommandsCopyTheConcealedKeyValueAndPath() throws {
        let (view, outline) = makeOutline()
        let pasteboard = privatePasteboard(view)
        defer { pasteboard.releaseGlobally() }
        outline.expandItem(outline.item(atRow: 1))
        outline.expandItem(outline.item(atRow: 3))
        let name = try #require(row(of: "Zoë", in: outline))
        #expect(view.perform(.path, rows: IndexSet(integer: name)))
        #expect(pasteboard.string(forType: .string) == "$.users[1].name")
        #expect(view.perform(.key, rows: IndexSet(integer: name)))
        #expect(pasteboard.string(forType: .string) == "name")
        #expect(view.perform(.value, rows: IndexSet(integer: name)))
        #expect(pasteboard.string(forType: .string) == "Zoë")
        // Concealed values copy concealed.
        let password = try #require(row(of: "••••", in: outline))
        view.perform(.value, rows: IndexSet(integer: password))
        #expect(pasteboard.string(forType: .string) == "••••")
        view.perform(.path, rows: IndexSet(integer: password))
        #expect(pasteboard.string(forType: .string) == "$.password")
        let quoted = try #require(row(named: "my key", in: outline))
        view.perform(.path, rows: IndexSet(integer: quoted))
        #expect(pasteboard.string(forType: .string) == "$['my key']")
        view.perform(.path, rows: IndexSet(integer: 0))
        #expect(pasteboard.string(forType: .string) == "$")
        let index = try #require(row(named: "[1]", in: outline))
        view.perform(.path, rows: IndexSet(integer: index))
        #expect(pasteboard.string(forType: .string) == "$.users[1]")
        // A container's value is its readable subtree, not the placeholder.
        view.perform(.value, rows: IndexSet(integer: index))
        #expect(pasteboard.string(forType: .string) == "name: Zoë\nrole: viewer")
    }

    @Test func commandsOnSeveralRowsCopyOneLineEach() throws {
        let (view, outline) = makeOutline()
        let pasteboard = privatePasteboard(view)
        defer { pasteboard.releaseGlobally() }
        let rows = IndexSet([try #require(row(named: "password", in: outline)), try #require(row(named: "count", in: outline))])
        view.perform(.value, rows: rows)
        #expect(pasteboard.string(forType: .string) == "••••\n3")
        view.perform(.key, rows: rows)
        #expect(pasteboard.string(forType: .string) == "password\ncount")
        #expect(!view.perform(.key, rows: IndexSet()))
    }

    @Test func pathsWorkThroughAFilteredListAndForRecordDocuments() throws {
        let (view, outline) = makeOutline()
        let pasteboard = privatePasteboard(view)
        defer { pasteboard.releaseGlobally() }
        view.setFilter("viewer")
        let role = try #require(row(of: "viewer", in: outline))
        view.perform(.path, rows: IndexSet(integer: role))
        #expect(pasteboard.string(forType: .string) == "$.users[1].role")
        // JSON Lines records are separate documents: each row's path starts at its own `$`.
        let records = [SafeOutlineNode(id: 0, name: "Record 2", value: "{…}", children: [
            .init(id: 1, name: "id", value: "7"), .init(id: 2, name: "tags", value: "[…]", children: [
                .init(id: 3, name: "[0]", value: "a")])])]
        view.display(records, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current,
                     rootsAreDocuments: true)
        view.setFilter("")
        let tags = try #require(row(named: "tags", in: outline))
        outline.expandItem(outline.item(atRow: tags))
        let tag = try #require(row(of: "a", in: outline))
        view.perform(.path, rows: IndexSet(integer: tag))
        #expect(pasteboard.string(forType: .string) == "$.tags[0]")
    }

    @Test func aSecondaryClickBuildsTheMenuForTheRowUnderThePointer() throws {
        let (view, outline) = makeOutline()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let pasteboard = privatePasteboard(view)
        defer { pasteboard.releaseGlobally() }
        let target = try #require(row(named: "count", in: outline))
        let center = NSPoint(x: outline.rect(ofRow: target).midX, y: outline.rect(ofRow: target).midY)
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: outline.convert(center, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(outline.menu(for: event))
        #expect(menu.items.map(\.title) == OutlineRowAction.allCases.map { PreviewStrings.text($0.title) })
        #expect(outline.selectedRowIndexes == IndexSet(integer: target))
        let copyValue = try #require(menu.items.first)
        _ = view.perform(copyValue.action, with: copyValue)
        #expect(pasteboard.string(forType: .string) == "3")
        // Empty space below the rows offers no menu.
        let below = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: outline.convert(NSPoint(x: 10, y: outline.bounds.maxY + 40), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1))
        #expect(outline.menu(for: below) == nil)
    }

    @Test func theSameCommandsAreAccessibilityActionsOnEveryCell() throws {
        let (view, outline) = makeOutline()
        let pasteboard = privatePasteboard(view)
        defer { pasteboard.releaseGlobally() }
        let countRow = try #require(row(named: "count", in: outline))
        let item = try #require(outline.item(atRow: countRow))
        for column in 0..<2 {
            let field = try #require(view.outlineView(outline, viewFor: outline.tableColumns[column], item: item) as? NSTextField)
            let actions = field.accessibilityCustomActions() ?? []
            #expect(actions.map(\.name) == OutlineRowAction.allCases.map { PreviewStrings.text($0.title) })
        }
        let field = try #require(view.outlineView(outline, viewFor: outline.tableColumns[1], item: item) as? NSTextField)
        let value = try #require(field.accessibilityCustomActions()?.first)
        #expect(value.handler?() == true)
        #expect(pasteboard.string(forType: .string) == "3")
    }

    // MARK: Fixtures

    private func fixture() -> [SafeOutlineNode] {
        [SafeOutlineNode(id: 0, name: "$", value: "{…}", children: [
            .init(id: 1, name: "users", value: "[…]", children: [
                .init(id: 2, name: "[0]", value: "{…}", children: [
                    .init(id: 3, name: "name", value: "José"), .init(id: 4, name: "role", value: "admin")]),
                .init(id: 5, name: "[1]", value: "{…}", children: [
                    .init(id: 6, name: "name", value: "Zoë"), .init(id: 7, name: "role", value: "viewer")])]),
            .init(id: 8, name: "password", value: "••••"),
            .init(id: 9, name: "my key", value: "x"),
            .init(id: 10, name: "count", value: "3")])]
    }

    private func makeOutline() -> (NativeOutlinePreviewView, NSOutlineView) {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(fixture(), typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        return (view, view.documentView as! NSOutlineView)
    }

    private func privatePasteboard(_ view: NativeOutlinePreviewView) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("outline-\(UUID().uuidString)"))
        view.pasteboard = pasteboard
        return pasteboard
    }

    private func rows(_ outline: NSOutlineView) -> [String] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? OutlineItem)?.node.name }
    }

    private func row(of value: String, in outline: NSOutlineView) -> Int? {
        (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? OutlineItem)?.node.value == value }
    }

    private func row(named name: String, in outline: NSOutlineView) -> Int? {
        (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? OutlineItem)?.node.name == name }
    }

    private func palette() -> NativeTextPalette { .init(theme: .system, isDark: false, increasedContrast: false) }
}

extension OutlineFilterAndCopyTests {
    @Test func commandUpAndDownSelectTheFirstAndLastRowOfAnOutline() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let nodes = [SafeOutlineNode(id: 0, name: "$", value: "{…}", children: [
            .init(id: 1, name: "a", value: "1"), .init(id: 2, name: "b", value: "2"), .init(id: 3, name: "c", value: "3")])]
        view.display(nodes, typography: .init(), palette: .init(theme: .system, isDark: false, increasedContrast: false),
                     syntaxStyle: .init(), locale: .current)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        let outline = try #require(view.documentView as? NSOutlineView)
        window.makeFirstResponder(outline)
        // The system key binding for Command-Down is moveToEndOfDocument:, which the outline answers.
        outline.doCommand(by: #selector(NSResponder.moveToEndOfDocument(_:)))
        #expect(outline.selectedRow == outline.numberOfRows - 1)
        outline.doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        #expect(outline.selectedRow == 0)
    }
}
