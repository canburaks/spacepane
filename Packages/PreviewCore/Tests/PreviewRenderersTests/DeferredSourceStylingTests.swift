import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Deferred source styling", .serialized)
@MainActor
struct DeferredSourceStylingTests {
    @Test func outlineAppearanceChangesDeferHiddenSourceEditsUntilSourceReturns() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let source = #"{"password":"••••","safe":"😀"}"#
        let presentation = value(source, format: .json)
        view.display(.ready(presentation), theme: .light)
        let text = try sourceView(view)
        let selection = (source as NSString).range(of: "••••")
        text.setSelectedRange(selection)
        let before = try #require(text.textStorage?.copy() as? NSAttributedString)
        try selectMode(1, in: view)
        view.display(.ready(presentation), typography: .init(fontSize: 22, showsLineNumbers: true), theme: .dark)
        #expect(text.isHiddenOrHasHiddenAncestor)
        #expect(text.textStorage?.isEqual(to: before) == true)
        #expect(text.selectedRange() == selection)
        try selectMode(0, in: view)
        #expect(!text.isHiddenOrHasHiddenAncestor)
        #expect(text.string == source)
        #expect(text.selectedRange() == selection)
        let font = try #require(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 22)
        #expect(text.textStorage?.isEqual(to: before) == false)
        #expect(text.isSelectable && !text.isEditable && text.usesFindBar)
    }

    @Test func summaryFirstDoesNotMaterializeInvisibleSourceAndSourceIsAvailableOnDemand() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let source = #"{"entries":[{"path":"safe😀","type":"file"}]}"#
        view.display(.ready(value(source, format: .folder)))
        let text = try sourceView(view)
        #expect(text.isHiddenOrHasHiddenAncestor)
        #expect(text.string.isEmpty)
        try selectMode(0, in: view)
        #expect(!text.isHiddenOrHasHiddenAncestor)
        #expect(text.string == source)
        #expect(text.textStorage?.length == source.utf16.count)
    }

    @Test func replacementWhileOutlineIsVisibleCannotRetainPreviousSourceOrSelection() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(value(#"{"old":"safe-but-outdated"}"#, format: .folder)))
        try selectMode(0, in: view)
        let text = try sourceView(view)
        text.setSelectedRange(NSRange(location: 2, length: 3))
        try selectMode(1, in: view)
        let replacement = #"{"new":"••••"}"#
        view.display(.ready(value(replacement, format: .folder)), resetsContentState: true)
        #expect(text.string.isEmpty)
        #expect(text.selectedRange() == NSRange(location: 0, length: 0))
        try selectMode(0, in: view)
        #expect(text.string == replacement)
        try selectMode(1, in: view)
        view.display(.disabledByUser(.folder))
        #expect(!text.string.contains("new"))
        #expect(!text.string.contains("••••"))
    }

    private func value(_ source: String, format: FormatID) -> TextPresentation {
        .init(formatID: format, text: source, lineCount: 1, byteCount: source.utf8.count,
              encoding: .utf8, redactionCount: 1, syntax: .json)
    }
    private func sourceView(_ view: NativePreviewView) throws -> NSTextView {
        try #require(view.scrollView.documentView as? NSTextView)
    }
    private func selectMode(_ index: Int, in view: NativePreviewView) throws {
        let control = view.modeControl
        #expect(control.segmentCount > index)
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }
}
