import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The rail inside a real preview: these specify the hook in `NativePreviewView` and `PreviewTextContentView`
/// (the lead's integration patch), so they fail until it is applied. The rail itself is covered by
/// `Q74ContentsRailTests`. The rail is found by type; nothing here needs a new seam.
@Suite("Q74 Contents rail in the preview", .serialized)
@MainActor
struct Q74ContentsRailHostTests {
    private let english = Locale(identifier: "en")
    private let short = "# Alpha\n\nintro\n\n## Beta\n\nmore text\n\n## Gamma\n\nthe end"

    private func presentation(_ text: String) -> TextPresentation {
        TextPresentation(formatID: .markdown, text: text, lineCount: text.components(separatedBy: "\n").count,
                         byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .markdown)
    }

    private func long() -> String {
        let body = String(repeating: "Some words that make a line of the section body.\n\n", count: 6)
        return "# Title\n\n" + (0..<40).map { "## Section \($0)\n\n" + body }.joined()
    }

    private func railView(in host: InteractionHarness) throws -> MarkupContentsRail {
        try #require(descendants(of: MarkupContentsRail.self, in: host.view).first)
    }

    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1))
        host.view.layoutSubtreeIfNeeded()
    }

    private func resize(_ host: InteractionHarness, to width: CGFloat) {
        host.view.setFrameSize(NSSize(width: width, height: host.view.frame.height))
        host.view.layoutSubtreeIfNeeded()
    }

    @Test func aWideRenderedDocumentShowsTheRailBesideTheText() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.show(presentation(short))
        try #require(host.view.selectedMode == .rendered)
        let rail = try railView(in: host)
        #expect(rail.isOffered && !rail.isHidden)
        #expect(rail.list.headings.map(\.title) == ["Alpha", "Beta", "Gamma"])
        #expect(rail.frame.width == ContentsRailPolicy.expandedWidth && rail.frame.minX == 0)
        let text = host.view.convert(host.view.scrollView.bounds, from: host.view.scrollView)
        #expect(text.minX >= rail.frame.maxX - 0.5)
        // Contents stays a mode too: the rail adds a view, it does not take one away.
        #expect(host.view.displayedModes.contains(.contents))
    }

    @Test func aNarrowPaneKeepsContentsAsAModeAndHasNoRail() throws {
        let host = InteractionHarness(width: 600, height: 400)
        defer { host.release() }
        host.show(presentation(short))
        let rail = try railView(in: host)
        #expect(!rail.isOffered && rail.isHidden && rail.frame.width == 0)
        #expect(host.view.displayedModes.contains(.contents))
        let text = host.view.convert(host.view.scrollView.bounds, from: host.view.scrollView)
        #expect(text.minX == 0)
    }

    @Test func theRailIsOnlyForTheRenderedTextOfAShownDocument() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.show(presentation(short))
        let rail = try railView(in: host)
        try #require(rail.isOffered)
        try select(.source, in: host)
        #expect(!rail.isOffered && rail.isHidden)
        try select(.contents, in: host)
        #expect(!rail.isOffered)
        try select(.rendered, in: host)
        #expect(rail.isOffered && rail.list.headings.count == 3)
        host.view.showSettingsUnavailable()
        host.view.layoutSubtreeIfNeeded()
        #expect(!rail.isOffered && rail.isHidden)
    }

    @Test func aHostThatFixesItsDensityNeverShowsTheRail() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.view.forcedDensity = .regular
        host.show(presentation(short))
        let rail = try railView(in: host)
        #expect(!rail.isOffered)
    }

    @Test func resizingAcrossTheThresholdTogglesTheRailWithoutFlicker() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.show(presentation(short))
        let rail = try railView(in: host)
        let narrowest = ContentsRailPolicy.minimumHostWidth - ContentsRailPolicy.hysteresis
        let widest = ContentsRailPolicy.minimumHostWidth + ContentsRailPolicy.hysteresis
        #expect(rail.isOffered)
        resize(host, to: ContentsRailPolicy.minimumHostWidth)
        #expect(rail.isOffered)
        resize(host, to: narrowest - 1)
        #expect(!rail.isOffered && rail.frame.width == 0)
        resize(host, to: ContentsRailPolicy.minimumHostWidth)
        #expect(!rail.isOffered)
        resize(host, to: widest)
        #expect(rail.isOffered && rail.frame.width == ContentsRailPolicy.expandedWidth)
        #expect(rail.list.headings.count == 3)
    }

    @Test func theRailFollowsTheScrollOfTheText() throws {
        let host = InteractionHarness(width: 1_000, height: 320)
        defer { host.release() }
        host.show(presentation(long()))
        let rail = try railView(in: host)
        try #require(rail.isOffered)
        rail.viewportChanged()
        #expect(rail.list.tableView.selectedRow == 0)
        let clip = host.view.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, host.textView.frame.height - clip.bounds.height) / 2))
        host.view.scrollView.reflectScrolledClipView(clip)
        rail.viewportChanged()
        let reading = try #require(ContentsVisibleRange.viewport(of: host.textView))
        let expected = try #require(ContentsSectionTracker.sectionIndex(
            visible: reading.visible, textLength: reading.textLength, headings: rail.list.headings))
        #expect(expected > 0 && rail.list.tableView.selectedRow == expected)
        #expect(host.announcements.texts.isEmpty)
    }

    @Test func choosingAHeadingSelectsItInTheTextAndKeepsFocusAndSilenceInTheRail() throws {
        let host = InteractionHarness(width: 1_000, height: 320)
        defer { host.release() }
        host.show(presentation(long()))
        let rail = try railView(in: host)
        try #require(rail.isOffered)
        #expect(host.window.makeFirstResponder(rail.list.tableView))
        host.announcements.texts.removeAll()
        let heading = rail.list.headings[20]
        rail.list.activate(row: 20)
        #expect((host.textView.string as NSString).substring(with: host.textView.selectedRange()) == heading.title)
        let reading = try #require(ContentsVisibleRange.viewport(of: host.textView))
        #expect(reading.visible.location <= heading.range.location && heading.range.location < NSMaxRange(reading.visible))
        #expect(host.window.firstResponder === rail.list.tableView)
        #expect(host.announcements.texts.isEmpty)
        rail.viewportChanged()
        #expect(rail.tracker.current == 20 && rail.list.tableView.selectedRow == 20)
    }

    @Test func copyingFromTheRailUsesThePreviewsPasteboardAndConfirmsOnce() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.show(presentation(short))
        let rail = try railView(in: host)
        rail.list.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        host.announcements.texts.removeAll()
        rail.list.tableView.copy(nil)
        #expect(host.pasteboard.string(forType: .string) == "Beta")
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
        #expect(rail.list.tableView.pasteboard === host.pasteboard)
    }

    @Test func theRailReadsBeforeTheTextForVoiceOver() throws {
        let host = InteractionHarness(width: 1_000, height: 500)
        defer { host.release() }
        host.show(presentation(short))
        let rail = try railView(in: host)
        let order = host.view.navigationOrderViews
        let railIndex = try #require(order.firstIndex { $0 === rail })
        let textIndex = try #require(order.firstIndex { $0 === host.view.scrollView })
        #expect(railIndex < textIndex)
    }
}
