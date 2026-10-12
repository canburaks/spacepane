import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native outline performance regressions", .serialized)
@MainActor
struct NativeOutlinePerformanceRegressionTests {
    @Test func aRecordForestExpandsEveryRootOnceWithoutExpandingDescendants() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
        let nodes = records(count: 128)
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        #expect(outline.numberOfRows == 128 * 3)
        for index in 0..<128 {
            let root = try #require(outline.child(index, ofItem: nil))
            let branch = try #require(outline.child(0, ofItem: root))
            #expect(outline.isItemExpanded(root))
            #expect(!outline.isItemExpanded(branch))
        }
    }

    @Test func restylingARecordForestRetainsCollapsedRootsExpandedChildrenAndSafeSelection() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
        let nodes = records(count: 64)
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        let collapsed = try #require(outline.child(0, ofItem: nil))
        outline.collapseItem(collapsed)
        let root = try #require(outline.child(63, ofItem: nil))
        let branch = try #require(outline.child(0, ofItem: root))
        let concealed = try #require(outline.child(0, ofItem: branch))
        outline.expandItem(branch)
        let row = outline.row(forItem: concealed)
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        let count = outline.numberOfRows
        view.display(nodes, typography: .init(fontSize: 18), palette: palette(.dark),
                     syntaxStyle: .init(usesColor: false), locale: .current)
        #expect(outline.numberOfRows == count)
        #expect(!outline.isItemExpanded(collapsed))
        #expect(outline.isItemExpanded(branch))
        #expect(outline.selectedRow == outline.row(forItem: concealed))
        let field = try #require(view.outlineView(outline, viewFor: outline.tableColumns[1], item: concealed) as? NSTextField)
        #expect(field.stringValue == "••••")
        #expect(field.accessibilityValue() == "••••")
        let font = try #require(field.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 18)
    }

    @Test func reusedCellsReplaceSafeTextTraitsAndDuplicateAccessibilityMetadata() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
        let nodes: [SafeOutlineNode] = [
            .init(id: 0, name: "password", value: "••••", isDuplicateKey: true),
            .init(id: 1, name: "visible 😀", value: "safe 日本語")
        ]
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        let duplicate = try #require(outline.item(atRow: 0))
        let normal = try #require(outline.item(atRow: 1))
        let probe = ReusingOutline()
        let column = outline.tableColumns[1]
        let first = try #require(view.outlineView(probe, viewFor: column, item: duplicate) as? NSTextField)
        #expect(first === probe.reusedField)
        #expect(first.identifier == column.identifier)
        #expect(first.stringValue == "••••")
        #expect(first.accessibilityHelp() == PreviewStrings.text(.previewDuplicateKey))
        view.display(nodes, typography: .init(fontSize: 18), palette: palette(.dark),
                     syntaxStyle: .init(usesColor: false), locale: .current)
        let reused = try #require(view.outlineView(probe, viewFor: column, item: normal) as? NSTextField)
        #expect(reused === first)
        #expect(reused.stringValue == "safe 日本語")
        #expect(reused.accessibilityValue() == "safe 日本語")
        #expect(reused.accessibilityHelp() == nil)
        #expect(reused.toolTip == nil)
        #expect(reused.isSelectable)
        #expect(!reused.isEditable)
        #expect(reused.attributedStringValue.attribute(.link, at: 0, effectiveRange: nil) == nil)
        let font = try #require(reused.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 18)
    }

    @Test func instantiatedRowsRestyleInPlaceAndScrolledRowsUseTheLatestAppearance() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 160))
        let nodes = records(count: 128)
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        try draw(view)
        var cached: [Int: NSTextField] = [:]
        outline.enumerateAvailableRowViews { rowView, row in
            if let field = rowView.view(atColumn: 0) as? NSTextField { cached[row] = field }
        }
        #expect(!cached.isEmpty)

        let dark = palette(.dark)
        view.display(nodes, typography: .init(), palette: dark,
                     syntaxStyle: .init(usesColor: false, boldRoles: [.key]), locale: .current)
        var refreshed = 0
        outline.enumerateAvailableRowViews { rowView, row in
            guard let field = rowView.view(atColumn: 0) as? NSTextField else { return }
            #expect(field === cached[row])
            expectLatestAppearance(field, foreground: dark.foreground)
            refreshed += 1
        }
        #expect(refreshed == cached.count)

        outline.scrollRowToVisible(outline.numberOfRows - 1)
        try draw(view)
        var scrolled = 0
        outline.enumerateAvailableRowViews { rowView, _ in
            guard let field = rowView.view(atColumn: 0) as? NSTextField else { return }
            expectLatestAppearance(field, foreground: dark.foreground)
            scrolled += 1
        }
        #expect(scrolled > 0)
    }

    private func expectLatestAppearance(_ field: NSTextField, foreground: NSColor) {
        let attributes = field.attributedStringValue.attributes(at: 0, effectiveRange: nil)
        #expect((attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect((attributes[.foregroundColor] as? NSColor)?.isEqual(foreground) == true)
        #expect(attributes[.link] == nil)
        #expect(field.accessibilityValue() == field.stringValue)
    }

    private func draw(_ view: NSView) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    private func records(count: Int) -> [SafeOutlineNode] {
        (0..<count).map { index in
            .init(id: index * 4, name: "Record \(index)", value: "{…}", children: [
                .init(id: index * 4 + 1, name: "nested", value: "{…}", children: [
                    .init(id: index * 4 + 2, name: "password", value: "••••")
                ]),
                .init(id: index * 4 + 3, name: "safe", value: "visible 😀")
            ])
        }
    }
    private func palette(_ theme: PreviewTheme = .system) -> NativeTextPalette {
        .init(theme: theme, isDark: theme == .dark, increasedContrast: false)
    }
}

@MainActor private final class ReusingOutline: NSOutlineView {
    let reusedField = NSTextField(labelWithString: "")
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { reusedField }
}
