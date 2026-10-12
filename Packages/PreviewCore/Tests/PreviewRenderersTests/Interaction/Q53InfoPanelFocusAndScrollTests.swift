import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q53 static information focus and scroll host keys", .serialized)
@MainActor
struct Q53InfoPanelFocusAndScrollTests {
    private let english = Locale(identifier: "en_US")

    @Test func disclosureLeavesContentFocusAndInformationRowsNeverOwnAFieldEditor() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        showSource(in: host)
        #expect(host.window.makeFirstResponder(host.view.textView))
        let focus = host.window.firstResponder
        let button = try infoButton(host.view)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.infoPanelIsOpen && host.window.firstResponder === focus)
        let labels = descendants(of: NSTextField.self, in: host.view.infoPanelView)
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(!label.isEditable && !label.isSelectable)
            #expect(label.currentEditor() == nil)
        }
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(!host.view.infoPanelIsOpen && host.window.firstResponder === focus)
        #expect((host.window.firstResponder as? NSView)?.isHiddenOrHasHiddenAncestor == false)
    }

    @Test func theActualPanelScrollViewHandsSpaceAndEscapeToTheHostUnchanged() throws {
        let host = InteractionHarness(width: 800, height: 240)
        defer { host.release() }
        let catcher = Q53PanelScrollKeyCatcher(frame: host.view.frame)
        host.window.contentView = catcher
        catcher.addSubview(host.view)
        showSource(in: host)
        try infoButton(host.view).performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(of: NSScrollView.self, in: host.view.infoPanelView).first)
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        let origin = scroll.contentView.bounds.origin
        for (code, character) in [(PreviewKeyCode.space, " "), (PreviewKeyCode.escape, "\u{1B}")] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: host.window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            #expect(!host.view.performKeyEquivalent(with: event))
            scroll.keyDown(with: event)
            #expect(scroll.contentView.bounds.origin == origin)
            #expect(host.view.infoPanelIsOpen)
        }
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape])
    }

    @Test func clearingInformationResetsItsNaturalHeightAndAllContentImmediately() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        showSource(in: host)
        try infoButton(host.view).performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        let panel = try #require(host.view.infoPanelView as? PreviewInfoPanelView)
        #expect(panel.naturalHeight > 0)
        var heights: [CGFloat] = []
        panel.onNaturalHeightChanged = { heights.append($0) }
        panel.clear()
        #expect(panel.naturalHeight == 0 && heights == [0])
        #expect(!panel.isExpanded && panel.isHidden && panel.lines.isEmpty && panel.commands.isEmpty)
        #expect(((panel.accessibilityValue() as? String) ?? "").isEmpty)
        panel.clear()
        #expect(heights == [0], "Clearing the already-empty component is not another layout change")
    }

    @Test func closingAndStateReplacementReleaseActualInformationScrollFocus() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        showSource(in: host)
        let button = try infoButton(host.view)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(of: NSScrollView.self, in: host.view.infoPanelView).first)
        #expect(host.window.makeFirstResponder(scroll))
        #expect(host.window.firstResponder === scroll)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(!host.view.infoPanelIsOpen)
        expectVisibleFocusOutsideInformation(in: host)

        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.window.makeFirstResponder(scroll))
        host.view.showLoading()
        #expect(!host.view.infoPanelIsOpen && host.view.displayedInfoLines.isEmpty)
        #expect(((host.view.infoPanelView.accessibilityValue() as? String) ?? "").isEmpty)
        expectVisibleFocusOutsideInformation(in: host)
    }

    private func infoButton(_ view: NativePreviewView) throws -> NSButton {
        try #require((view.infoBadge as NSView) as? NSButton)
    }
    private func showSource(in host: InteractionHarness) {
        host.view.display(.ready(plainPresentation("Q53 safe source", format: .plainText, syntax: .plain)),
            locale: english, resetsContentState: true)
        host.view.layoutSubtreeIfNeeded()
    }
    private func expectVisibleFocusOutsideInformation(in host: InteractionHarness) {
        if let focused = host.window.firstResponder as? NSView {
            #expect(focused !== host.view.infoPanelView && !focused.isDescendant(of: host.view.infoPanelView))
            #expect(!focused.isHiddenOrHasHiddenAncestor)
        }
    }
}

@MainActor
private final class Q53PanelScrollKeyCatcher: NSView {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}
