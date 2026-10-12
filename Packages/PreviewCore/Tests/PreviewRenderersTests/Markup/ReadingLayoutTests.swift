import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Rendered reading layout", .serialized)
@MainActor
struct ReadingLayoutTests {
    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        host.view.modeControl.selectedSegment = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.modeControl.sendAction(host.view.modeControl.action, to: host.view.modeControl.target))
        host.view.layoutSubtreeIfNeeded()
    }

    private func font(_ word: String, in text: NSTextView) throws -> NSFont {
        let range = (text.string as NSString).range(of: word)
        #expect(range.location != NSNotFound)
        return try #require(text.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }

    @Test func undecoratedProseUsesTheSystemFaceAtTheConfiguredSize() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation("Plain readable prose", format: .markdown, syntax: .markdown),
                  typography: PreviewTypography(fontSize: 19, fontFamily: "Menlo"))
        #expect(host.view.selectedMode == .rendered)
        #expect(try font("Plain", in: host.textView) == NSFont.systemFont(ofSize: 19))
        let paragraph = try #require(host.textView.textStorage?.attribute(.paragraphStyle, at: 0,
                                              effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(paragraph.lineHeightMultiple - 1.4) < 0.001)
    }

    @Test func codeUsesTheSelectedFamilyAndSourceKeepsItsOwnTypography() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let typography = PreviewTypography(fontSize: 18, fontFamily: "Menlo")
        host.show(plainPresentation("Prose with `inlineCode`.\n\n```swift\nblockCode\n```",
                                   format: .markdown, syntax: .markdown), typography: typography)
        let expectedCode = NativeTextTypography(typography).font
        #expect(try font("Prose", in: host.textView) == NSFont.systemFont(ofSize: 18))
        #expect(try font("inlineCode", in: host.textView) == expectedCode)
        #expect(try font("blockCode", in: host.textView) == expectedCode)
        try select(.source, in: host)
        #expect(try font("Prose", in: host.textView) == expectedCode)
    }

    @Test func readingForcesWrappingAndHidesLineToolsThenRestoresSourceChoices() throws {
        let host = InteractionHarness(width: 1200)
        defer { host.release() }
        let presentation = plainPresentation("A paragraph with safe text.\n\nAnother paragraph.",
                                             format: .markdown, syntax: .markdown)
        host.show(presentation, typography: PreviewTypography(wrapsLines: false, showsLineNumbers: true))
        #expect(!host.view.scrollView.hasHorizontalScroller)
        #expect(host.view.lineNumberGutter.isHidden)
        #expect(!host.view.presentGoToLine())
        let menu = try #require(host.view.textView(host.textView, menu: NSMenu(),
                              for: host.keyEvent("", []), at: 0))
        #expect(!menu.items.contains { $0.title == PreviewCommand.goToLine.localizedTitle() })
        #expect(host.textView.textContainerInset.width > PreviewChrome.inset)
        let measure = ("abcdefghijklmnopqrstuvwxyz" as NSString).size(withAttributes:
            [.font: NSFont.systemFont(ofSize: 13)]).width / 26 * 70
        #expect(abs((try #require(host.textView.textContainer)).containerSize.width - measure) < 1)
        try select(.source, in: host)
        #expect(host.view.scrollView.hasHorizontalScroller)
        #expect(!host.view.lineNumberGutter.isHidden)
        #expect(host.textView.textContainerInset.width == PreviewChrome.inset)
        #expect(host.view.presentGoToLine())
        try select(.rendered, in: host)
        #expect(host.view.accessoryBar.content == .none)
        #expect(!host.view.goToLineIsOpen)
    }

    @Test func resizeAndRestylePreserveSafeCodeUnitsSelectionAndInertAttributes() throws {
        let host = InteractionHarness(width: 1100)
        defer { host.release() }
        let source = "Safe cafe\u{301} prose with •••• and `code`."
        let presentation = plainPresentation(source, format: .markdown, syntax: .markdown)
        host.show(presentation)
        let before = Array(host.textView.string.utf16)
        let selection = (host.textView.string as NSString).range(of: "••••")
        host.textView.setSelectedRange(selection)
        host.window.setContentSize(NSSize(width: 260, height: 420))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.textView.textContainerInset.width == PreviewChrome.inset)
        #expect((try #require(host.textView.textContainer)).containerSize.width > 0)
        host.show(presentation, typography: PreviewTypography(fontSize: 26, fontFamily: "Menlo"))
        #expect(Array(host.textView.string.utf16) == before)
        #expect(host.textView.selectedRange() == selection)
        #expect(try font("Safe", in: host.textView) == NSFont.systemFont(ofSize: 26))
        #expect(host.textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(host.textView.writeSelection(to: host.pasteboard, types: host.textView.writablePasteboardTypes))
        #expect(host.pasteboard.string(forType: .string) == "••••")
    }
}
