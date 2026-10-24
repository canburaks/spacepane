import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native renderer interaction", .serialized)
@MainActor
struct NativeRendererInteractionTests {
    @Test func outlineDoesNotClaimCopyWhenItIsNotTheFirstResponder() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let outline = try #require(view.documentView as? NSOutlineView)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                timestamp: 0, windowNumber: 0, context: nil, characters: "c",
                                                charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        // No rows are selected, so exercising this route never writes the general pasteboard.
        #expect(outline.selectedRowIndexes.isEmpty)
        #expect(!outline.performKeyEquivalent(with: event))
    }

    @Test func outlineRestylingRetainsExpandedRowsAndSelection() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let nodes = [SafeOutlineNode(id: 0, name: "$", value: "{…}", children: [
            .init(id: 1, name: "nested", value: "{…}", children: [
                .init(id: 2, name: "password", value: "••••")
            ]),
            .init(id: 3, name: "safe", value: "😀")
        ])]
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        let nested = try #require(outline.item(atRow: 1))
        outline.expandItem(nested)
        outline.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        #expect(outline.numberOfRows == 4)
        view.display(nodes, typography: .init(fontSize: 18), palette: palette(),
                     syntaxStyle: .init(usesColor: false), locale: .current)
        #expect(outline.numberOfRows == 4)
        #expect(outline.isItemExpanded(nested))
        #expect(outline.selectedRowIndexes == IndexSet(integer: 2))
        let selectedItem = try #require(outline.item(atRow: 2))
        let field = try #require(view.outlineView(outline, viewFor: outline.tableColumns[1], item: selectedItem) as? NSTextField)
        #expect(field.stringValue == "••••")
        #expect(field.accessibilityValue() == "••••")
    }

    @Test func outlineCellsExposeSafeNativeValuesWithoutRepeatingTheirDescriptions() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display([.init(id: 0, name: "password", value: "••••", isDuplicateKey: true)],
                     typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        let outline = try #require(view.documentView as? NSOutlineView)
        let item = try #require(outline.item(atRow: 0))
        for (index, text) in ["password", "••••"].enumerated() {
            let field = try #require(view.outlineView(outline, viewFor: outline.tableColumns[index], item: item) as? NSTextField)
            let native = NSTextField(labelWithString: text)
            native.isSelectable = true
            #expect(native.accessibilityValue() == text)
            #expect(field.accessibilityValue() == text)
            #expect(field.accessibilityRole() == native.accessibilityRole())
            #expect(field.accessibilityLabel() == native.accessibilityLabel())
            #expect(field.accessibilityHelp() == PreviewStrings.text(.previewDuplicateKey))
        }
    }

    @Test func aNewGenerationWithIdenticalSummaryContentResetsOutlineSelection() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        // Not listing-shaped (no entries array), so the Summary outline stays the initial mode; a listing
        // opens in Files instead (listings workstream).
        let text = #"{"archiveFormat":"directory","listedEntries":1,"note":"safe😀"}"#
        let presentation = TextPresentation(formatID: .folder, text: text, lineCount: 1,
                                            byteCount: text.utf8.count, encoding: .utf8,
                                            redactionCount: 0, syntax: .json)
        view.display(.ready(presentation))
        let scroll = view.outlineView
        let outline = try #require(scroll.documentView as? NSOutlineView)
        #expect(!scroll.isHidden)
        outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(outline.selectedRow == 1)
        view.display(.ready(presentation), resetsContentState: true)
        #expect(outline.selectedRowIndexes.isEmpty)
    }

    @Test func unloadedMIDIPresentationDoesNotExposeEnabledPlaybackActions() throws {
        let view = NativeMIDIPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        let controls = descendants(of: view)
        let play = try #require(controls.compactMap { $0 as? NSButton }.first)
        let slider = try #require(controls.compactMap { $0 as? NSSlider }.first)
        #expect(!play.isEnabled)
        #expect(!slider.isEnabled)
    }

    @Test func clearedMIDIPresentationDisablesPlaybackAndScrubbing() throws {
        let view = NativeMIDIPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        view.show(.init(format: 0, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 2, events: []))
        let controls = descendants(of: view)
        let play = try #require(controls.compactMap { $0 as? NSButton }.first)
        let slider = try #require(controls.compactMap { $0 as? NSSlider }.first)
        #expect(play.isEnabled)
        #expect(slider.isEnabled)
        view.clear()
        #expect(!play.isEnabled)
        #expect(!slider.isEnabled)
        #expect(slider.doubleValue == 0)
        #expect(play.title == PreviewStrings.text(.midiPlay))
    }

    @Test func renderedMarkdownKeepsSafeSelectionCopyAndInertLinksDuringRestyling() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let text = "# Heading\n**password:** ••••\n[link](javascript:inert)"
        let presentation = TextPresentation(formatID: .markdown, text: text, lineCount: 3,
                                            byteCount: text.utf8.count, encoding: .utf8,
                                            redactionCount: 1, syntax: .markdown)
        view.display(.ready(presentation))
        let mode = view.modeControl
        mode.selectedSegment = 1
        #expect(mode.sendAction(mode.action, to: mode.target))
        let content = try #require(view.scrollView.documentView as? NSTextView)
        #expect(!content.isEditable)
        #expect(content.isSelectable)
        #expect(content.usesFindBar)
        #expect(content.string == "Heading\npassword: •••• link (javascript:inert)")
        #expect(content.accessibilityLabel() == PreviewStrings.text(.selectableContent))
        let concealed = (content.string as NSString).range(of: "••••")
        content.setSelectedRange(concealed)
        view.display(.ready(presentation), typography: .init(fontSize: 18), theme: .dark)
        #expect(content.selectedRange() == concealed)
        #expect(content.textStorage?.attribute(.link, at: content.string.utf16.count - 1, effectiveRange: nil) == nil)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        #expect(content.writeSelection(to: pasteboard, types: content.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == "••••")
    }

    @Test func outlineAdaptsKeyColumnWidthForCompactSidebarAndStylesScalarValueRolesWithLongValueTooltips() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        let longValue = String(repeating: "a", count: 64)
        let nodes: [SafeOutlineNode] = [
            .init(id: 0, name: "short", value: "safe"),
            .init(id: 1, name: "long", value: longValue)
        ]
        view.display(nodes, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        view.layoutSubtreeIfNeeded()
        let outline = try #require(view.documentView as? NSOutlineView)
        let keyColumn = try #require(outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("key")))
        let valueColumn = try #require(outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("value")))
        #expect(keyColumn.width >= 80 && keyColumn.width <= 140)

        view.setFrameSize(NSSize(width: 600, height: 300))
        view.layoutSubtreeIfNeeded()
        #expect(keyColumn.width == 220)

        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 0, name: "secret", value: "••••")) == .comment)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 1, name: "container", value: "{…}", children: [
            .init(id: 2, name: "child", value: "1")
        ])) == .comment)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 3, name: "flag", value: "true")) == .keyword)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 4, name: "flag", value: "false")) == .keyword)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 5, name: "empty", value: "null")) == .keyword)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 6, name: "count", value: "42")) == .number)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 7, name: "delta", value: "-3.14")) == .number)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 8, name: "zip", value: "0123")) == .string)
        #expect(NativeOutlinePreviewView.valueRole(for: .init(id: 9, name: "text", value: "safe")) == .string)
        #expect(NativeOutlinePreviewView.displayedValueText(for: .init(id: 1, name: "obj", value: "{…}", children: [.init(id: 2, name: "a", value: "1"), .init(id: 3, name: "b", value: "2")]), locale: Locale(identifier: "en_US")) == "{…} (2)")
        #expect(NativeOutlinePreviewView.displayedValueText(for: .init(id: 1, name: "arr", value: "[…]", children: [.init(id: 2, name: "[0]", value: "x")]), locale: Locale(identifier: "en_US")) == "[…] (1)")
        #expect(NativeOutlinePreviewView.displayedValueText(for: .init(id: 1, name: "leaf", value: "{…}"), locale: Locale(identifier: "en_US")) == "{…}")

        let shortItem = try #require(outline.item(atRow: 0))
        let longItem = try #require(outline.item(atRow: 1))
        let shortField = try #require(view.outlineView(outline, viewFor: valueColumn, item: shortItem) as? NSTextField)
        let longField = try #require(view.outlineView(outline, viewFor: valueColumn, item: longItem) as? NSTextField)
        #expect(shortField.toolTip == nil)
        #expect(longField.toolTip == longValue)

        #expect(NativeOutlinePreviewView.shouldShowHoverTooltip(for: "authentication_config", isKey: true, density: .compact) == true)
        #expect(NativeOutlinePreviewView.shouldShowHoverTooltip(for: "authentication_config", isKey: true, density: .regular) == false)
        #expect(NativeOutlinePreviewView.shouldShowHoverTooltip(for: "id", isKey: true, density: .compact) == false)

        view.display([.init(id: 10, name: "container", value: "{…}", children: [
            .init(id: 11, name: "first", value: "1"),
            .init(id: 12, name: "second", value: "2")
        ])], typography: .init(), palette: palette(), syntaxStyle: .init(), locale: .current)
        #expect(outline.numberOfRows == 3)
        #expect(view.toggleExpansion(atRow: 0))
        #expect(outline.numberOfRows == 1)
        #expect(view.toggleExpansion(atRow: 0))
        #expect(outline.numberOfRows == 3)
    }

    private func palette() -> NativeTextPalette {
        .init(theme: .system, isDark: false, increasedContrast: false)
    }
}
