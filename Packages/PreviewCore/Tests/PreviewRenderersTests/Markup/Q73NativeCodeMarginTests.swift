import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 native code margin controls", .serialized)
@MainActor
struct Q73NativeCodeMarginTests {
    private let english = Locale(identifier: "en_US")

    @Test func actualTextKitCardsOwnSeparateButtonsOutsideTheColumnIncludingBlankBodies() throws {
        let host = pinnedHarness(width: 1200, height: 620)
        defer { host.release() }
        let bodies = ["let first = \"😀\"\n\nend", "\n", "مرحبا let last = 3"]
        show(source(bodies), in: host)
        let buttons = controls(in: host)
        try #require(buttons.count == 3)
        #expect(buttons.enumerated().allSatisfy { index, button in
            !buttons.prefix(index).contains { $0.copyTarget == button.copyTarget }
        })
        for button in buttons {
            let card = try cardBounds(button.copyTarget.block.range, in: host.textView)
            let frame = host.textView.convert(button.bounds, from: button)
            let column = column(in: host.textView)
            #expect(frame.size == NSSize(width: 22, height: 22))
            #expect(host.textView.visibleRect.contains(frame) && !frame.intersects(column) && !frame.intersects(card))
            #expect(abs(frame.minY - (card.minY + 4)) < 0.01)
            #expect(frame.minX >= column.maxX + 5 || frame.maxX <= column.minX - 5)
            #expect(button.isBordered == false && button.image != nil && button.keyEquivalent.isEmpty)
            #expect(button.accessibilityLabel() == CodeBlockCopyAccessibilityLabel.text(for: button.copyTarget.block.language, locale: english))
            #expect(button.accessibilityHelp() == PreviewStrings.text(.markupCopyCodeBlockHelp))
        }
        let text = host.textView.string, selection = NSRange(location: 0, length: 6)
        host.textView.setSelectedRange(selection)
        host.view.setFrameSize(NSSize(width: 360, height: 620)); host.view.layoutSubtreeIfNeeded()
        #expect(controls(in: host).isEmpty && !host.view.scrollView.hasHorizontalScroller)
        #expect(host.textView.frame.width <= host.view.scrollView.contentSize.width)
        #expect(host.textView.string.utf16.elementsEqual(text.utf16) && host.textView.selectedRange() == selection)
    }

    @Test func narrowLongLTRAndRTLContainingBodiesKeepCardPaintAndSelectionInsideTheViewport() throws {
        let host = pinnedHarness(width: 360, height: 420)
        defer { host.release() }
        // A mouse event elsewhere in the process switches automatic scrollers to the legacy
        // style. The card still has to stay inside that narrower clip.
        host.view.scrollView.scrollerStyle = .legacy
        for words in ["let value = 123 ", "مرحبا let value = 123 "] {
            let body = String(repeating: words, count: 70)
            show(source([body]), in: host)
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

    @Test func aMarginActionCopiesExactSafeBodyWithoutChangingSelectionAndHonorsCurrentTagPolicy() throws {
        let host = pinnedHarness(width: 1200)
        defer { host.release() }
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        let body = "😀 e\u{301} ••••\n\n" + flag + "\u{E0061}\u{E007F}"
        show(source([body]), in: host, findsTags: true)
        let button = try #require(controls(in: host).first)
        host.textView.setSelectedRange(NSRange(location: 0, length: 6))
        let selection = host.textView.selectedRanges
        button.performClick(nil)
        let expected = "😀 e\u{301} ••••\n\n" + flag
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(expected.utf16))
        #expect(host.textView.selectedRanges == selection && host.announcements.texts.count == 1)
        host.view.plainTextCopyWriter = { _, _ in false }
        button.performClick(nil)
        #expect(host.textView.selectedRanges == selection && host.announcements.texts.count == 1)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(expected.utf16))
    }

    @Test func identicalReplacementAndFindingTransitionRemoveOldButtonsBeforeRetainedActionsCanWrite() throws {
        let host = pinnedHarness(width: 1200)
        defer { host.release() }
        let value = source(["same e\u{301} 😀"])
        show(value, in: host)
        let old = try #require(controls(in: host).first)
        show(value, in: host, resetsContentState: true)
        let current = try #require(controls(in: host).first)
        #expect(old.superview == nil && old.copyTarget != current.copyTarget)
        host.pasteboard.setString("previous", forType: .string)
        var writes = 0
        host.view.plainTextCopyWriter = { text, board in writes += 1; return board.setString(text, forType: .string) }
        old.performClick(nil)
        #expect(writes == 0 && host.pasteboard.string(forType: .string) == "previous" && host.announcements.texts.isEmpty)
        current.performClick(nil)
        #expect(writes == 1 && host.announcements.texts.count == 1)
        show(value, in: host, findsTags: true)
        #expect(current.superview == nil)
        current.performClick(nil)
        #expect(writes == 1 && host.announcements.texts.count == 1)
    }

    @Test func hiddenModesAndSuspensionClearControlsAndCannotRecreateThemOnLayout() throws {
        let host = pinnedHarness(width: 1200)
        defer { host.release() }
        show(source(["code"]), in: host)
        let old = try #require(controls(in: host).first)
        host.view.suspendResources(); host.view.needsLayout = true; host.view.layoutSubtreeIfNeeded()
        #expect(controls(in: host).isEmpty && old.superview == nil)
        old.performClick(nil)
        #expect(host.announcements.texts.isEmpty)
        host.view.resumeResources(); host.view.layoutSubtreeIfNeeded()
        let current = try #require(controls(in: host).first)
        #expect(current.copyTarget != old.copyTarget)
        try select(.source, in: host)
        #expect(controls(in: host).isEmpty && current.superview == nil)
        let modeAnnouncements = host.announcements.texts
        current.performClick(nil)
        #expect(host.announcements.texts == modeAnnouncements)
        try select(.rendered, in: host)
        try #require(!controls(in: host).isEmpty)
        host.view.showLoading(); host.view.layoutSubtreeIfNeeded()
        #expect(controls(in: host).isEmpty)
    }

    @Test func scrollUsesNativeConvertedCoordinatesAndOnlyCurrentVisibleAnchors() throws {
        let host = pinnedHarness(width: 1200, height: 340)
        defer { host.release() }
        show(source((0..<240).map { "body \($0)\n\nend" }), in: host)
        let initial = controls(in: host)
        try #require(!initial.isEmpty && initial.count < 10)
        let owner = try #require(descendants(of: PreviewTextContentView.self, in: host.view).first)
        let clip = host.view.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: host.textView.frame.height / 2))
        host.view.scrollView.reflectScrolledClipView(clip)
        owner.refreshCodeBlockCopyControls()
        let current = controls(in: host)
        try #require(!current.isEmpty && current.count < 10)
        #expect(initial.allSatisfy { $0.superview == nil })
        #expect(current.allSatisfy { $0.copyTarget.block.range.location > initial.last!.copyTarget.block.range.location })
        for button in current {
            let frame = host.textView.convert(button.bounds, from: button)
            let card = try cardBounds(button.copyTarget.block.range, in: host.textView)
            #expect(host.textView.visibleRect.contains(frame) && !frame.intersects(column(in: host.textView)))
            #expect(abs(frame.minY - card.minY - 4) < 0.01)
        }
        let retained = try #require(current.first), target = retained.copyTarget
        let selection = NSRange(location: target.block.range.location, length: 1)
        host.textView.setSelectedRange(selection)
        host.view.display(.ready(presentation(source((0..<240).map { "body \($0)\n\nend" }))),
                          theme: .dark, locale: english)
        owner.refreshCodeBlockCopyControls()
        #expect(controls(in: host).contains { $0 === retained && $0.copyTarget == target })
        #expect(host.textView.selectedRange() == selection)
    }

    @Test func buttonAnswersReturnAndHandsSpaceAndEscapeToTheHost() throws {
        let host = pinnedHarness(width: 1200)
        defer { host.release() }
        show(source(["copy"]), in: host)
        let button = try #require(controls(in: host).first)
        let catcher = CodeMarginKeyCatcher()
        button.nextResponder = catcher
        for (code, text) in [(PreviewKeyCode.space, " "), (PreviewKeyCode.escape, "\u{1B}")] {
            button.keyDown(with: try event(code, text, in: host))
        }
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape] && host.announcements.texts.isEmpty)
        button.keyDown(with: try event(PreviewKeyCode.returnKey, "\r", in: host))
        #expect(host.pasteboard.string(forType: .string) == "copy" && host.announcements.texts.count == 1)
    }

    /// The scroller style is process state: a mouse event posted anywhere in the test process switches automatic
    /// scrollers to the legacy style, which narrows the clip by the scroller's width. Every test pins the style it
    /// asserts under, so no test depends on which ran before it.
    private func pinnedHarness(width: CGFloat = 640, height: CGFloat = 420,
                               style: NSScroller.Style = .overlay) -> InteractionHarness {
        let host = InteractionHarness(width: width, height: height)
        host.view.scrollView.scrollerStyle = style
        return host
    }

    private func controls(in host: InteractionHarness) -> [NativeCodeCopyButton] {
        descendants(of: NativeCodeCopyButton.self, in: host.view).filter { !$0.isHidden }
    }
    private func source(_ bodies: [String]) -> String {
        "before\n\n" + bodies.map { "```swift\n" + $0 + "\n```" }.joined(separator: "\n\n") + "\n\nafter"
    }
    private func presentation(_ source: String, findsTags: Bool = false) -> TextPresentation {
        .init(formatID: .markdown, text: source, lineCount: source.components(separatedBy: "\n").count,
              byteCount: source.utf8.count, encoding: .utf8, redactionCount: 1, syntax: .markdown,
              findings: findsTags ? [.init(kind: .hiddenUnicodeTags, count: 2)] : [])
    }
    private func show(_ source: String, in host: InteractionHarness, findsTags: Bool = false,
                      resetsContentState: Bool = false) {
        host.view.display(.ready(presentation(source, findsTags: findsTags)), locale: english,
                          resetsContentState: resetsContentState)
        host.view.layoutSubtreeIfNeeded()
    }
    private func column(in view: NSTextView) -> NSRect {
        NSRect(x: view.textContainerOrigin.x, y: view.visibleRect.minY,
               width: view.textContainer?.containerSize.width ?? 0, height: view.visibleRect.height)
    }
    private func cardBounds(_ range: NSRange, in view: NSTextView) throws -> NSRect {
        let storage = try #require(view.textStorage), manager = try #require(view.layoutManager)
        let paragraph = try #require(storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        let card = try #require(paragraph.textBlocks.first { $0 is NativeCodeTextBlock })
        let glyph = manager.glyphIndexForCharacter(at: range.location)
        return manager.boundsRect(for: card, at: glyph, effectiveRange: nil)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }
    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1)); host.view.layoutSubtreeIfNeeded()
    }
    private func event(_ code: UInt16, _ characters: String, in host: InteractionHarness) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: host.window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
}

@MainActor
private final class CodeMarginKeyCatcher: NSResponder {
    var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}
