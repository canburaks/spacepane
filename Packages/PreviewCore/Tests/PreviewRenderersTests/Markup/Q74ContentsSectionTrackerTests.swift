import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Which heading is the current section while the rendered text scrolls (decision 027, Q-74). The rule works on
/// character offsets alone, so every case is a plain value check: nothing here lays out text, takes focus or speaks.
@Suite("Q74 Contents section tracker")
struct Q74ContentsSectionTrackerTests {
    private let textLength = 1_000
    /// Five headings with a short run of text between them, the last one near the end.
    private let starts = [0, 100, 250, 400, 900]

    private func headings(at locations: [Int]) -> [MarkupHeading] {
        locations.enumerated().map { entry in
            MarkupHeading(level: entry.offset == 0 ? 1 : 2, title: "Heading \(entry.offset)",
                          range: NSRange(location: entry.element, length: 9))
        }
    }

    private func visible(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

    private func section(_ range: NSRange, in list: [MarkupHeading], length: Int? = nil) -> Int? {
        ContentsSectionTracker.sectionIndex(visible: range, textLength: length ?? textLength, headings: list)
    }

    /// The rule written out with a linear scan, so the binary search is compared with something simpler.
    private func reference(_ range: NSRange, length: Int, in list: [MarkupHeading]) -> Int? {
        let end = min(range.location + range.length, length)
        let anchor = range.location + (end - range.location) / 4
        let position = (end >= length && range.location > 0) ? max(end - 1, 0) : anchor
        let found = list.indices.last(where: { list[$0].range.location <= position })
        return range.location == 0 ? found.map { _ in 0 } : found
    }

    // MARK: The nearest preceding heading

    @Test func theAnchorIsAQuarterOfTheWayDownTheVisibleCharacters() {
        let list = headings(at: starts)
        #expect(section(visible(0, 80), in: list) == 0)
        #expect(section(visible(120, 100), in: list) == 1)
        #expect(section(visible(500, 100), in: list) == 3)
        // The heading at 250 is reached when the anchor, a quarter down 80 characters, gets there: 230 + 20 = 250.
        #expect(section(visible(230, 80), in: list) == 2)
        #expect(section(visible(230, 79), in: list) == 1)
        // A zero-length reading is a point: the heading it sits on counts.
        #expect(section(visible(250, 0), in: list) == 2)
    }

    @Test func nothingIsCurrentBeforeTheFirstHeading() {
        let list = headings(at: [50, 300, 700])
        #expect(section(visible(0, 100), in: list) == nil)
        #expect(section(visible(0, 220), in: list) == 0)
        #expect(section(visible(0, 100), in: []) == nil)
    }

    @Test func theStartOfTheTextKeepsTheFirstHeadingCurrent() {
        // A dense document fits its second heading into the first quarter of the view: at the top, the opening
        // section is still the reader's. Nothing changes while no heading precedes the anchor.
        let dense = headings(at: [0, 10, 40, 300])
        #expect(section(visible(0, 100), in: dense) == 0)
        #expect(section(visible(0, 1_000), in: dense) == 0)
        // One character down, the anchor (1 + 99 / 4 = 25) decides again: the heading at 10 is current.
        #expect(section(visible(1, 100), in: dense) == 1)
        #expect(section(visible(1, 200), in: dense) == 2)
        #expect(section(visible(0, 30), in: headings(at: [50, 300])) == nil)
    }

    @Test func theEndOfTheTextSelectsTheLastHeadingInView() {
        let list = headings(at: starts)
        // Until the end is on screen the anchor (762 here) is still inside the section that starts at 400.
        #expect(section(visible(700, 250), in: list) == 3)
        #expect(section(visible(700, 300), in: list) == 4)
        #expect(section(visible(990, 10), in: list) == 4)
        // A view that shows everything is also at the start: the first heading, not the last one in view.
        #expect(section(visible(0, 1_000), in: list) == 0)
    }

    @Test func unusableReadingsHaveNoSection() {
        let list = headings(at: starts)
        #expect(section(NSRange(location: NSNotFound, length: 0), in: list) == nil)
        #expect(section(NSRange(location: -4, length: 20), in: list) == nil)
        #expect(section(NSRange(location: 10, length: -1), in: list) == nil)
        #expect(section(visible(1_001, 0), in: list) == nil)
        #expect(!ContentsSectionTracker.isUsable(visible(1_001, 0), textLength: textLength))
        #expect(ContentsSectionTracker.isUsable(visible(1_000, 0), textLength: textLength))
        #expect(ContentsSectionTracker.isUsable(visible(0, 0), textLength: textLength))
    }

    @Test func aLengthPastTheEndOfTheTextIsClampedToIt() {
        let list = headings(at: starts)
        #expect(section(visible(10, Int.max), in: list) == 4)
        #expect(section(visible(0, Int.max), in: list) == 0)
        var tracker = ContentsSectionTracker()
        tracker.pin(1)
        tracker.update(visible: visible(50, Int.max), textLength: textLength, headings: list)
        #expect(tracker.current == 4 && tracker.pinned == nil)
    }

    @Test func scrollingDownNeverMovesTheCurrentSectionBackAndFollowsTheRule() {
        let list = headings(at: starts)
        var previous = -1
        for location in stride(from: 0, through: textLength, by: 7) {
            let range = visible(location, min(160, textLength - location))
            let index = section(range, in: list)
            #expect(index == reference(range, length: textLength, in: list), "at \(location)")
            #expect((index ?? -1) >= previous, "at \(location)")
            previous = index ?? -1
        }
        #expect(previous == 4)
    }

    @Test func aFullSizeHeadingListAgreesWithTheLinearRule() {
        let length = 65_000
        let list = headings(at: Array(stride(from: 0, to: length, by: 13)))
        #expect(list.count == 5_000)
        for location in stride(from: 0, through: length, by: 997) {
            for size in [0, 1, 40, 600] {
                let range = visible(location, min(size, length - location))
                #expect(section(range, in: list, length: length) == reference(range, length: length, in: list),
                        "at \(location) size \(size)")
            }
        }
    }

    // MARK: Following a scroll

    @Test func anUpdateReportsOnlyRealChanges() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        #expect(tracker.current == nil)
        let first = tracker.update(visible: visible(120, 100), textLength: textLength, headings: list)
        #expect(first && tracker.current == 1)
        let same = tracker.update(visible: visible(130, 100), textLength: textLength, headings: list)
        #expect(!same && tracker.current == 1)
        let next = tracker.update(visible: visible(260, 100), textLength: textLength, headings: list)
        #expect(next && tracker.current == 2)
    }

    @Test func anUnusableReadingChangesNothing() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.update(visible: visible(260, 100), textLength: textLength, headings: list)
        let notFound = tracker.update(visible: NSRange(location: NSNotFound, length: 0), textLength: textLength,
                                      headings: list)
        let beyond = tracker.update(visible: visible(5_000, 10), textLength: textLength, headings: list)
        #expect(!notFound && !beyond)
        #expect(tracker.current == 2)
    }

    @Test func aReplacementDocumentForgetsEverything() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.pin(3)
        tracker.reset()
        #expect(tracker.current == nil && tracker.pinned == nil)
        #expect(tracker == ContentsSectionTracker())
        tracker.update(visible: visible(260, 100), textLength: textLength, headings: list)
        tracker.reset()
        #expect(tracker.current == nil)
    }

    // MARK: A heading the reader chose

    @Test func aChosenHeadingIsCurrentAtOnceAndStaysWhileItIsInViewBelowTheAnchor() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.pin(3)
        #expect(tracker.current == 3 && tracker.pinned == 3)
        // The heading at 400 sits near the bottom of [330, 490); the anchor at 370 still belongs to the section at 250.
        let changed = tracker.update(visible: visible(330, 160), textLength: textLength, headings: list)
        #expect(!changed)
        #expect(tracker.current == 3 && tracker.pinned == 3)
    }

    @Test func scrollingTheChosenHeadingOutOfViewReleasesIt() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.pin(1)
        // The view [240, 540) no longer contains the heading at 100, so the anchor at 315 decides.
        let changed = tracker.update(visible: visible(240, 300), textLength: textLength, headings: list)
        #expect(changed)
        #expect(tracker.current == 2 && tracker.pinned == nil)
    }

    @Test func aLaterHeadingReachingTheAnchorReleasesTheChosenOne() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.pin(1)
        // The heading at 100 is in view, but the anchor at 250 is already in the section that starts there.
        let changed = tracker.update(visible: visible(100, 600), textLength: textLength, headings: list)
        #expect(changed)
        #expect(tracker.current == 2 && tracker.pinned == nil)
    }

    @Test func aChosenIndexThatNoLongerExistsIsDropped() {
        let list = headings(at: starts)
        var tracker = ContentsSectionTracker()
        tracker.pin(99)
        tracker.update(visible: visible(120, 100), textLength: textLength, headings: list)
        #expect(tracker.pinned == nil && tracker.current == 1)
    }
}

/// The on-screen characters of a real rendered text, read with the geometry the copy controls use.
@Suite("Q74 Contents visible range", .serialized)
@MainActor
struct Q74ContentsVisibleRangeTests {
    private let english = Locale(identifier: "en")

    private func document() -> String {
        let body = String(repeating: "Some words that make a line of the section body.\n\n", count: 6)
        return "# Title\n\n" + (0..<40).map { "## Section \($0)\n\n" + body }.joined()
    }

    private func presentation(_ text: String) -> TextPresentation {
        TextPresentation(formatID: .markdown, text: text, lineCount: text.components(separatedBy: "\n").count,
                         byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .markdown)
    }

    private func scroll(_ host: InteractionHarness, toFraction fraction: CGFloat) {
        let clip = host.view.scrollView.contentView
        let farthest = max(0, host.textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: farthest * fraction))
        host.view.scrollView.reflectScrolledClipView(clip)
    }

    @Test func theViewportFollowsTheScrollPositionOfARenderedDocument() throws {
        let host = InteractionHarness(width: 640, height: 320)
        defer { host.release() }
        let source = presentation(document())
        host.show(source)
        try #require(host.view.selectedMode == .rendered)
        let list = try #require(SafePreviewModes(source, locale: english).markdown?.headings)
        try #require(list.count > 10)
        var tracker = ContentsSectionTracker()

        let top = try #require(ContentsVisibleRange.viewport(of: host.textView))
        #expect(top.visible.location == 0 && top.textLength == host.textView.textStorage?.length)
        tracker.update(visible: top.visible, textLength: top.textLength, headings: list)
        #expect(tracker.current == 0)

        scroll(host, toFraction: 0.5)
        let middle = try #require(ContentsVisibleRange.viewport(of: host.textView))
        #expect(middle.visible.location > top.visible.location && NSMaxRange(middle.visible) <= middle.textLength)
        tracker.update(visible: middle.visible, textLength: middle.textLength, headings: list)
        let current = try #require(tracker.current)
        #expect(current > 0 && current < list.count - 1)
        #expect(list[current].range.location <= middle.visible.location + middle.visible.length / 4)

        scroll(host, toFraction: 1)
        let bottom = try #require(ContentsVisibleRange.viewport(of: host.textView))
        #expect(NSMaxRange(bottom.visible) == bottom.textLength)
        tracker.update(visible: bottom.visible, textLength: bottom.textLength, headings: list)
        #expect(tracker.current == list.count - 1)
    }

    @Test func anEmptyTextViewHasNoViewport() {
        #expect(ContentsVisibleRange.viewport(of: PreviewTextView.makeTextKit1()) == nil)
    }
}
