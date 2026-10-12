import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Counts completed full layout passes while forwarding every other delegate message to the text view.
@MainActor
private final class LayoutPassCounter: NSObject, @preconcurrency NSLayoutManagerDelegate {
    private let forwarding: (any NSLayoutManagerDelegate)?
    private(set) var completedPasses = 0

    init(forwarding: (any NSLayoutManagerDelegate)?) { self.forwarding = forwarding }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?,
                       atEnd layoutFinishedFlag: Bool) {
        if layoutFinishedFlag { completedPasses += 1 }
        forwarding?.layoutManager?(layoutManager, didCompleteLayoutFor: textContainer, atEnd: layoutFinishedFlag)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || ((forwarding as AnyObject?)?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? { forwarding }
}

@Suite("Native initial layout", .serialized)
@MainActor
struct NativeInitialLayoutTests {
    private let ordinaryLines = (1...400).map { "line \($0) with safe words that need wrapping " + String(repeating: "word ", count: 12) }

    @Test func sourceTextViewUsesTextKit1FromConstructionAndKeepsItsContainer() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let (_, content, _) = try components(of: view)
        let container = try #require(content.textContainer)
        #expect(content.textLayoutManager == nil)
        #expect(content.layoutManager != nil)
        view.display(ready(ordinaryLines.joined(separator: "\n")), typography: PreviewTypography(showsLineNumbers: true))
        view.layoutSubtreeIfNeeded()
        #expect(content.textLayoutManager == nil)
        #expect(content.textContainer === container)
        #expect(content.layoutManager?.textContainers.first === container)
    }

    @Test func legacyVerticalScrollerIsReservedBeforeTheSingleWrappingLayout() throws {
        let text = ordinaryLines.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .legacy
        let counter = LayoutPassCounter(forwarding: content.layoutManager?.delegate)
        content.layoutManager?.delegate = counter
        view.display(ready(text), typography: PreviewTypography())
        view.layoutSubtreeIfNeeded()
        #expect(counter.completedPasses == 1)
        try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
        #expect(scroll.verticalScroller?.isHidden == false)
        #expect(scroll.contentSize.width < scroll.frame.width)
        #expect(content.string == text)
    }

    @Test func overlayScrollersKeepTheirFullWidthAndSingleLayout() throws {
        let text = ordinaryLines.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .overlay
        let counter = LayoutPassCounter(forwarding: content.layoutManager?.delegate)
        content.layoutManager?.delegate = counter
        view.display(ready(text), typography: PreviewTypography())
        view.layoutSubtreeIfNeeded()
        #expect(counter.completedPasses == 1)
        #expect(scroll.contentSize.width == scroll.frame.width)
        try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
    }

    @Test func documentsThatOnlyOverflowAfterWrappingStillEndWithConsistentWidth() throws {
        // The conservative bound cannot prove overflow for these two lines, but ordinary glyph widths make
        // them taller than the viewport, so the scroller appears after layout and the text re-wraps once.
        let text = String(repeating: "wrapped safe words ", count: 37) + "\n" + String(repeating: "more words ", count: 60)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .legacy
        view.display(ready(text), typography: PreviewTypography())
        view.layoutSubtreeIfNeeded()
        #expect(scroll.verticalScroller?.isHidden == false)
        #expect(scroll.contentSize.width < scroll.frame.width)
        try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
    }

    @Test func oneVeryLongLineIsKnownToOverflowBeforeItIsLaidOut() throws {
        // A minified document is a single logical line that wraps into hundreds of fragments.
        let text = String(repeating: "{\"key\":\"value\",\"count\":12345},", count: 3_000)
        for typography in [PreviewTypography(), PreviewTypography(fontSize: 10, characterSpacing: -1)] {
            let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
            let (scroll, content, _) = try components(of: view)
            scroll.scrollerStyle = .legacy
            let counter = LayoutPassCounter(forwarding: content.layoutManager?.delegate)
            content.layoutManager?.delegate = counter
            view.display(ready(text), typography: typography)
            view.layoutSubtreeIfNeeded()
            #expect(counter.completedPasses == 1)
            #expect(scroll.verticalScroller?.isHidden == false)
            #expect(scroll.contentSize.width < scroll.frame.width)
            try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
            #expect(content.string == text)
        }
    }

    @Test func geometryStaysConsistentAcrossTheOverflowBoundaryForSeveralTypographies() throws {
        let typographies = [PreviewTypography(), PreviewTypography(fontSize: 9, lineSpacing: 3),
                            PreviewTypography(fontSize: 31, lineSpacing: 0, showsLineNumbers: true),
                            PreviewTypography(fontSize: 13, lineSpacing: 12, showsLineNumbers: true)]
        for typography in typographies {
            for lineCount in [1, 8, 15, 19, 20, 21, 22, 23, 24, 28, 40, 90] {
                let text = (1...lineCount).map { "logical line \($0) of safe words" }.joined(separator: "\n")
                let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 420, height: 380))
                let (scroll, content, _) = try components(of: view)
                scroll.scrollerStyle = .legacy
                view.display(ready(text), typography: typography)
                view.layoutSubtreeIfNeeded()
                try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
                let overflows = content.frame.height > scroll.contentSize.height + 0.5
                #expect(overflows == (scroll.verticalScroller?.isHidden == false),
                        "\(lineCount) lines at \(typography.fontSize) pt")
                #expect(content.string == text)
            }
        }
    }

    @Test func shortDocumentsNeverReserveAScrollerOrGrowTheDocument() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .legacy
        view.display(ready("one safe line\nanother safe line"), typography: PreviewTypography())
        view.layoutSubtreeIfNeeded()
        #expect(scroll.contentSize.width == scroll.frame.width)
        #expect(scroll.verticalScroller?.isHidden != false)
        #expect(content.frame.height == scroll.contentSize.height)
        try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
    }

    @Test func unwrappedLongDocumentKeepsItsExactHorizontalExtentAndSingleLayout() throws {
        let longest = String(repeating: "wide", count: 400)
        let text = (1...300).map { $0 == 150 ? longest : "line \($0)" }.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .legacy
        let counter = LayoutPassCounter(forwarding: content.layoutManager?.delegate)
        content.layoutManager?.delegate = counter
        view.display(ready(text), typography: PreviewTypography(wrapsLines: false))
        view.layoutSubtreeIfNeeded()
        #expect(counter.completedPasses == 1)
        let manager = try #require(content.layoutManager)
        let container = try #require(content.textContainer)
        let used = manager.usedRect(for: container)
        #expect(used.width > 1_000)
        #expect(scroll.hasHorizontalScroller)
        #expect(content.frame.width >= used.maxX + content.textContainerInset.width * 2)
        #expect(content.frame.width > scroll.contentSize.width)
        #expect(content.string == text)
    }

    @Test func resizingAReservedLayoutRewrapsOnceAtTheNewWidth() throws {
        let text = ordinaryLines.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let (scroll, content, _) = try components(of: view)
        scroll.scrollerStyle = .legacy
        view.display(ready(text), typography: PreviewTypography())
        view.layoutSubtreeIfNeeded()
        let counter = LayoutPassCounter(forwarding: content.layoutManager?.delegate)
        content.layoutManager?.delegate = counter
        let before = content.textContainer?.containerSize.width
        view.setFrameSize(NSSize(width: 520, height: 420))
        view.layoutSubtreeIfNeeded()
        #expect(counter.completedPasses == 1)
        #expect(content.textContainer?.containerSize.width != before)
        try expectConsistentWrappedGeometry(view, scroll: scroll, content: content)
    }

    @Test func lastLogicalLineStaysReachableAfterTheReservedLayout() throws {
        let text = (1...300).map { "logical line \($0)" }.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
        let (scroll, content, ruler) = try components(of: view)
        scroll.scrollerStyle = .legacy
        view.display(ready(text), typography: PreviewTypography(showsLineNumbers: true))
        view.layoutSubtreeIfNeeded()
        let bottom = max(0, content.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        let labels = ruler.visibleLabels(in: content)
        #expect(labels.last?.number == 300)
        #expect(ruler.lineIndex.count == 300)
        #expect(content.string == text)
    }

    /// The text view, container and scroll view must agree and the layout must match an independent one.
    private func expectConsistentWrappedGeometry(_ view: NativePreviewView, scroll: NSScrollView,
                                                 content: NSTextView) throws {
        let manager = try #require(content.layoutManager)
        let container = try #require(content.textContainer)
        let inset = content.textContainerInset
        #expect(container.widthTracksTextView)
        #expect(abs(container.containerSize.width - (scroll.contentSize.width - inset.width * 2)) < 1)
        #expect(abs(content.frame.width - scroll.contentSize.width) < 1)
        #expect(manager.firstUnlaidCharacterIndex() == (content.string as NSString).length)
        let used = manager.usedRect(for: container)
        let height = max(used.maxY, manager.extraLineFragmentRect.maxY) + inset.height * 2
        #expect(abs(content.frame.height - max(scroll.contentSize.height, height)) < 1)
        // Independent layout of the same attributed text at the same width.
        let storage = NSTextStorage(attributedString: try #require(content.textStorage))
        let referenceManager = NSLayoutManager()
        let referenceContainer = NSTextContainer(containerSize: container.containerSize)
        referenceContainer.lineFragmentPadding = container.lineFragmentPadding
        referenceManager.addTextContainer(referenceContainer)
        storage.addLayoutManager(referenceManager)
        referenceManager.ensureLayout(for: referenceContainer)
        #expect(referenceManager.usedRect(for: referenceContainer).height == used.height)
    }

    private func ready(_ text: String) -> PreviewOutcome {
        .ready(TextPresentation(formatID: .plainText, text: text, lineCount: 1,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0))
    }

    private func components(of view: NativePreviewView) throws -> (NSScrollView, NSTextView, LogicalLineNumberGutter) {
        let scroll = view.scrollView
        return (scroll, try #require(scroll.documentView as? NSTextView), view.lineNumberGutter)
    }
}
