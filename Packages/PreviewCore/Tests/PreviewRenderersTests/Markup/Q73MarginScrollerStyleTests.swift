import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The margin controls and the narrow cards under each scroller style, pinned explicitly. AppKit switches automatic
/// scrollers to the legacy style once a mouse event is posted anywhere in the process, so a test that did not choose a
/// style would pass or fail depending on which test ran before it.
@Suite("Q73 code margin under every scroller style", .serialized)
@MainActor
struct Q73MarginScrollerStyleTests {
    private let english = Locale(identifier: "en_US")
    nonisolated static let styles: [NSScroller.Style] = [.overlay, .legacy]

    private func makeHost(width: CGFloat, height: CGFloat, style: NSScroller.Style) -> InteractionHarness {
        let host = InteractionHarness(width: width, height: height)
        host.view.scrollView.scrollerStyle = style
        return host
    }

    private func source(_ bodies: [String]) -> String {
        "before\n\n" + bodies.map { "```swift\n" + $0 + "\n```" }.joined(separator: "\n\n") + "\n\nafter"
    }

    private func controls(in host: InteractionHarness) -> [NativeCodeCopyButton] {
        descendants(of: NativeCodeCopyButton.self, in: host.view).filter { !$0.isHidden }
    }

    private func cardBounds(_ range: NSRange, in view: NSTextView) throws -> NSRect {
        let storage = try #require(view.textStorage), manager = try #require(view.layoutManager)
        let paragraph = try #require(storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        let card = try #require(paragraph.textBlocks.first { $0 is NativeCodeTextBlock })
        return manager.boundsRect(for: card, at: manager.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }

    @Test(arguments: styles)
    func wideHostsPlaceEveryControlClearOfTheColumnAndSpeakTheLanguageUnderEachStyle(style: NSScroller.Style) throws {
        let host = makeHost(width: 1200, height: 620, style: style)
        defer { host.release() }
        Q72Support.show(source(["let first = 1", "let second = 2"]), in: host)
        let buttons = controls(in: host)
        try #require(buttons.count == 2)
        let column = NSRect(x: host.textView.textContainerOrigin.x, y: host.textView.visibleRect.minY,
                            width: host.textView.textContainer?.containerSize.width ?? 0, height: host.textView.visibleRect.height)
        for button in buttons {
            let frame = host.textView.convert(button.bounds, from: button)
            let card = try cardBounds(button.copyTarget.block.range, in: host.textView)
            #expect(host.textView.visibleRect.contains(frame) && !frame.intersects(column) && !frame.intersects(card))
            #expect(button.accessibilityLabel() == CodeBlockCopyAccessibilityLabel.text(for: .swift, locale: english))
        }
    }

    @Test(arguments: styles)
    func narrowLongLTRAndRTLBodiesKeepCardPaintAndSelectionInsideTheViewportUnderEachStyle(style: NSScroller.Style) throws {
        let host = makeHost(width: 360, height: 420, style: style)
        defer { host.release() }
        for words in ["let value = 123 ", "مرحبا let value = 123 "] {
            let body = String(repeating: words, count: 70)
            Q72Support.show(source([body]), in: host)
            #expect(controls(in: host).isEmpty && !host.view.scrollView.hasHorizontalScroller)
            let range = (host.textView.string as NSString).range(of: body)
            try #require(range.location != NSNotFound && range.length > 0)
            host.textView.setSelectedRange(range)
            let card = try cardBounds(range, in: host.textView), viewport = host.textView.visibleRect
            #expect(card.minX >= viewport.minX && card.maxX <= viewport.maxX && card.height > viewport.height)
            #expect(host.textView.frame.width <= host.view.scrollView.contentSize.width)
            #expect(host.textView.selectedRange() == range)
        }
    }

    @Test func switchingTheStyleOfALiveHostNeverLeavesAControlBehindOrChangesTheText() throws {
        let host = makeHost(width: 1200, height: 620, style: .overlay)
        defer { host.release() }
        Q72Support.show(source(["let value = 1"]), in: host)
        let safe = Array(host.textView.string.utf16)
        for style in [NSScroller.Style.legacy, .overlay, .legacy] {
            host.view.scrollView.scrollerStyle = style
            host.view.layoutSubtreeIfNeeded()
            #expect(controls(in: host).count == 1)
            #expect(Array(host.textView.string.utf16) == safe)
        }
    }
}
