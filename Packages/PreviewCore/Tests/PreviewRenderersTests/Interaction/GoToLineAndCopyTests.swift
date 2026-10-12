import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Go to Line and Copy All", .serialized)
@MainActor
struct GoToLineAndCopyTests {
    // MARK: Go to Line

    @Test func commandLOpensAnInlineBarWithFocusAndEscapeClosesIt() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(50)))
        let bar = host.view.accessoryBar
        #expect(bar.content == .none && host.view.accessoryHeightConstraint?.constant == 0)
        #expect(host.press("l", .command))
        #expect(bar.content == .goToLine && !bar.goToLineBar.isHidden)
        #expect(host.view.accessoryHeightConstraint?.constant == PreviewAccessoryBar.height)
        #expect(host.window.firstResponder === bar.goToLineBar.field.currentEditor())
        // Inline: the bar is part of the preview's own view tree, not a window or panel.
        #expect(bar.isDescendant(of: host.view) && bar.window === host.window)
        #expect(bar.goToLineBar.message == PreviewStrings.format(.interactionGoToLineRange, arguments: [Int64(50)]))
        #expect(bar.goToLineBar.field.accessibilityLabel() == PreviewStrings.text(.interactionGoToLine))
        // Escape dismisses and returns focus to the text.
        let editor = try #require(bar.goToLineBar.field.currentEditor() as? NSTextView)
        #expect(bar.goToLineBar.control(bar.goToLineBar.field, textView: editor,
                                        doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(bar.content == .none && host.view.accessoryHeightConstraint?.constant == 0)
        #expect(host.window.firstResponder === host.textView)
    }

    @Test func enteringALineSelectsAndRevealsItAndAnnouncesIt() throws {
        let host = InteractionHarness(height: 220)
        defer { host.release() }
        host.show(plainPresentation(numberedLines(500)), typography: PreviewTypography(wrapsLines: false))
        host.press("l", .command)
        let bar = host.view.accessoryBar.goToLineBar
        bar.field.stringValue = "400"
        bar.field.sendAction(bar.field.action, to: bar.field.target)
        let selected = host.textView.selectedRange()
        #expect((host.textView.string as NSString).substring(with: selected) == "line 400")
        #expect(host.view.accessoryBar.content == .none)
        #expect(host.window.firstResponder === host.textView)
        let manager = try #require(host.textView.layoutManager)
        let container = try #require(host.textView.textContainer)
        let glyphs = manager.glyphRange(forCharacterRange: selected, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: host.textView.textContainerOrigin.x, dy: host.textView.textContainerOrigin.y)
        #expect(host.textView.visibleRect.contains(NSPoint(x: rect.minX, y: rect.midY)))
        #expect(host.textView.visibleRect.minY > 0)
        #expect(host.announcements.texts == [PreviewStrings.format(.interactionGoToLineJumped,
                                                                    arguments: [Int64(400), Int64(500)])])
    }

    @Test func invalidEntriesStayOpenWithALocalizedErrorAndMoveNothing() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(50)))
        host.textView.setSelectedRange(NSRange(location: 3, length: 2))
        host.press("l", .command)
        let bar = host.view.accessoryBar.goToLineBar
        let expected = PreviewStrings.format(.interactionGoToLineInvalid, arguments: [Int64(50)])
        for input in ["0", "51", "-2", "abc", "", "3.5"] {
            bar.field.stringValue = input
            bar.field.sendAction(bar.field.action, to: bar.field.target)
            #expect(bar.isShowingError && bar.message == expected, "\(input)")
            #expect(host.view.accessoryBar.content == .goToLine)
            #expect(host.textView.selectedRange() == NSRange(location: 3, length: 2))
        }
        #expect(host.announcements.texts == Array(repeating: expected, count: 6))
        // A valid entry afterwards still works and clears the error.
        bar.field.stringValue = "2"
        bar.field.sendAction(bar.field.action, to: bar.field.target)
        #expect((host.textView.string as NSString).substring(with: host.textView.selectedRange()) == "line 2")
    }

    @Test func goToLineWorksWithoutTheGutterOnCRLFTextAndHasNoLinesInEmptyText() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation("a\r\nbb\r\nccc"), typography: PreviewTypography(showsLineNumbers: false))
        host.press("l", .command)
        let bar = host.view.accessoryBar.goToLineBar
        bar.onSubmit?("2")
        #expect((host.textView.string as NSString).substring(with: host.textView.selectedRange()) == "bb")
        let empty = InteractionHarness()
        defer { empty.release() }
        empty.show(plainPresentation(""))
        // A 0-byte file shows the empty state, where Go to Line is not offered; the bar's own answer is unchanged.
        #expect(!empty.press("l", .command))
        empty.view.accessoryBar.goToLineBar.onSubmit?("1")
        #expect(empty.view.accessoryBar.goToLineBar.message == PreviewStrings.text(.interactionGoToLineNoLines))
    }

    @Test func goToLineIsOfferedOnlyWhereTheTextHasLines() throws {
        let host = InteractionHarness()
        defer { host.release() }
        // Nothing displayed yet, a failure, and an outline all decline the shortcut.
        #expect(!host.press("l", .command))
        host.view.display(.unavailable(.malformedDocument))
        #expect(!host.press("l", .command) && host.view.accessoryBar.content == .none)
        let json = #"{"members":[{"path":"a","type":"file"}]}"#
        host.show(plainPresentation(json, format: .folder, syntax: .json))
        #expect(host.view.accessoryBar.content == .filter)
        #expect(!host.press("l", .command))
        // Focus in an unrelated view of the window means the shortcut is not the preview's.
        let container = NSView(frame: host.view.frame)
        host.window.contentView = container
        container.addSubview(host.view)
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        container.addSubview(other)
        host.show(plainPresentation(numberedLines(5)), resetsContentState: true)
        host.window.makeFirstResponder(other)
        #expect(!host.view.ownsKeyboardFocus && !host.press("l", .command))
        #expect(host.view.accessoryBar.content == .none)
    }

    @Test func aNewRequestOrAModeSwitchClosesTheBar() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(5)))
        host.press("l", .command)
        #expect(host.view.accessoryBar.content == .goToLine)
        // The same request keeps the bar through a restyle, a new request does not.
        host.view.display(.ready(plainPresentation(numberedLines(5))), typography: PreviewTypography(fontSize: 15))
        #expect(host.view.accessoryBar.content == .goToLine)
        host.show(plainPresentation(numberedLines(5)), resetsContentState: true)
        #expect(host.view.accessoryBar.content == .none)
    }

    // MARK: Copy All

    @Test func copyAllCopiesTheWholeConcealedDisplayedTextNeverSource() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let text = "token = ••••\nplain 😀\n"
        host.show(plainPresentation(text, redactions: 1))
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == text)
        // One chip and one announcement for every copy, with the one short string.
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
        // The command key alone still means the standard copy of the selection.
        host.pasteboard.clearContents()
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == text)
    }

    @Test func copyAllInRenderedMarkdownCopiesTheRenderedTextAndOutlinesCopyTheConcealedDocument() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let markdown = "# Heading\n**password:** ••••\n"
        host.show(plainPresentation(markdown, format: .markdown, syntax: .markdown, redactions: 1))
        let control = host.view.modeControl
        control.selectedSegment = 1
        #expect(control.sendAction(control.action, to: control.target))
        #expect(host.textView.string.hasPrefix("Heading") && !host.textView.string.contains("**"))
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == host.textView.string)
        // Outline modes copy the document's concealed text.
        let json = #"{"members":[{"path":"safe😀","type":"file"}]}"#
        host.show(plainPresentation(json, format: .folder, syntax: .json), resetsContentState: true)
        host.pasteboard.clearContents()
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == json)
    }

    @Test func copyAllDoesNothingWithoutContentOrWhileATextFieldIsBeingEdited() throws {
        let host = InteractionHarness()
        defer { host.release() }
        #expect(!host.press("c", [.command, .shift]))
        host.view.display(.disabledByUser(.json))
        #expect(!host.press("c", [.command, .shift]))
        host.view.display(.unavailable(.missingFile))
        #expect(!host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == nil)
        host.show(plainPresentation(numberedLines(3)))
        host.press("l", .command)
        // Focus is in the Go to Line field editor: Command-Shift-C is not taken from it.
        #expect(!host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == nil)
    }

    @Test func theContextMenuOffersCopyAllGoToLineAndZoomCommands() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let text = "secret = ••••\nnext"
        host.show(plainPresentation(text, redactions: 1))
        let menu = try #require(host.view.textView(host.textView, menu: NSMenu(),
                                                   for: host.keyEvent("x", []), at: 0))
        let titles = menu.items.map(\.title)
        for key in [PreviewStrings.Key.interactionCopyAll, .interactionGoToLine, .interactionZoomIn,
                    .interactionZoomOut, .interactionZoomReset] {
            #expect(titles.contains(PreviewStrings.text(key)))
        }
        let copyAll = try #require(menu.items.first { $0.title == PreviewStrings.text(.interactionCopyAll) })
        #expect(copyAll.keyEquivalent == "c" && copyAll.keyEquivalentModifierMask == [.command, .shift])
        // The items come from the command table: each keeps its own action object, which runs the command.
        let copyAllAction = try #require(copyAll.representedObject as? PreviewCommandAction)
        #expect(copyAll.target === copyAllAction)
        copyAllAction.run(copyAll)
        #expect(host.pasteboard.string(forType: .string) == text)
        let goToLine = try #require(menu.items.first { $0.title == PreviewStrings.text(.interactionGoToLine) })
        try #require(goToLine.representedObject as? PreviewCommandAction).run(goToLine)
        #expect(host.view.accessoryBar.content == .goToLine)
    }

    @Test func findStillReachesTheTextFinderInTextModes() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(20)))
        #expect(host.textView.usesFindBar)
        #expect(host.press("f", .command))
        // The system find bar opened and took focus, as with the standard text-view shortcut.
        #expect(host.view.scrollView.isFindBarVisible)
        #expect(host.press("g", .command))
        #expect(host.press("g", [.command, .shift]))
    }

    // MARK: Layout

    @Test func theBarsSitBetweenTheModeControlAndTheirContentAndCollapseToNothing() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(30)))
        let bar = host.view.accessoryBar
        var textFrame: NSRect { host.view.convert(host.view.scrollView.bounds, from: host.view.scrollView) }
        #expect(bar.frame.height == 0)
        let collapsedTop = textFrame.maxY
        host.press("l", .command)
        host.view.layoutSubtreeIfNeeded()
        #expect(bar.frame.height == PreviewAccessoryBar.height)
        #expect(textFrame.maxY == bar.frame.minY)
        #expect(textFrame.maxY < collapsedTop)
        let field = bar.goToLineBar.field
        let fieldFrame = field.convert(field.bounds, to: host.view)
        #expect(fieldFrame.width > 40 && host.view.bounds.contains(fieldFrame) && bar.frame.contains(fieldFrame))
        try draw(host.view)
        bar.goToLineBar.onDismiss?()
        host.view.layoutSubtreeIfNeeded()
        #expect(bar.frame.height == 0 && textFrame.maxY == collapsedTop)

        let outlineHost = InteractionHarness()
        defer { outlineHost.release() }
        outlineHost.show(plainPresentation(#"{"members":[{"path":"a","type":"file"}]}"#, format: .folder, syntax: .json))
        let filterBar = outlineHost.view.accessoryBar
        #expect(filterBar.frame.height == PreviewAccessoryBar.height)
        #expect(outlineHost.view.outlineView.frame.maxY == filterBar.frame.minY)
        let search = filterBar.filterBar.searchField
        let searchFrame = search.convert(search.bounds, to: outlineHost.view)
        #expect(searchFrame.width >= 140 && filterBar.frame.contains(searchFrame))
        try draw(outlineHost.view)
    }

    private func draw(_ view: NSView) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
}
