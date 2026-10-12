import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en")

private func hiddenFindings() -> [PreviewFinding] {
    PreviewFindings.normalized([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])])
}

/// Plain text with a hidden character: the Invisibles mode exists beside Source, and a note comes with it.
private func presentationWithInvisibles(_ text: String = "alpha\u{200B}beta", redactions: Int = 0,
                                        truncatedSourceBytes: Int? = nil, isReformatted: Bool = false) -> TextPresentation {
    TextPresentation(formatID: .plainText, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                     redactionCount: redactions, truncatedSourceBytes: truncatedSourceBytes,
                     isReformatted: isReformatted, findings: hiddenFindings())
}

/// Text that is the first part of a larger file: a limit notice goes with it.
private func partialPresentation(_ text: String, redactions: Int = 0) -> TextPresentation {
    TextPresentation(formatID: .plainText, text: text, lineCount: max(1, text.components(separatedBy: "\n").count),
                     byteCount: text.utf8.count, encoding: .utf8, redactionCount: redactions,
                     truncatedSourceBytes: 3_000_000)
}

private func approximately(_ first: CGFloat, _ second: CGFloat) -> Bool { abs(first - second) < 0.5 }

private func same(_ first: NSRect, _ second: NSRect) -> Bool {
    approximately(first.minX, second.minX) && approximately(first.minY, second.minY)
        && approximately(first.width, second.width) && approximately(first.height, second.height)
}

@MainActor
private func displayedFrame(of control: NSView, in host: NSView) -> NSRect {
    host.convert(control.bounds, from: control)
}

@MainActor
private func displayedAlignmentRect(of control: NSView, in host: NSView) -> NSRect {
    host.convert(control.alignmentRect(forFrame: control.frame), from: control.superview)
}

@MainActor
private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
    let index = try #require(view.displayedModes.firstIndex(of: mode))
    view.modeControl.selectedSegment = index
    #expect(view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target))
    view.layoutSubtreeIfNeeded()
}

/// Counts completed full layout passes while forwarding every other delegate message to the text view.
@MainActor
private final class ChromeLayoutPassCounter: NSObject, @preconcurrency NSLayoutManagerDelegate {
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

/// The skeleton of the preview chrome (decision 027, Q-33 and Q-46): a mode control with a constant place, notes
/// below it, limits in their own slot, layout guides that follow the safe area, one reading order, and test seams
/// that do not depend on which view holds a label.
@Suite("Chrome skeleton", .serialized)
@MainActor
struct ChromeSkeletonTests {
    private func harness() -> InteractionHarness {
        let host = InteractionHarness()
        host.view.chromeScheduler = ManualChromeScheduler()
        return host
    }

    // MARK: The seams

    @Test func displayedStatusJoinsTheNoticesTheTypographyHintAndTheZoomReminder() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation("safe"))
        #expect(host.view.displayedStatus.isEmpty)
        let text = "token = [concealed]"
        let concealed = TextPresentation(formatID: .plainText, text: text, lineCount: 1,
                                         byteCount: text.utf8.count, encoding: .utf8,
                                         redactionCount: 1, isReformatted: true)
        host.show(concealed)
        let privacy = PreviewStrings.count(.findingSummaryConcealed, 1, locale: host.view.presentationLocale)
        let notice = PreviewStrings.text(.codeNoticeReformatted)
        #expect(host.view.findingsBanner.summaryLabel.stringValue == privacy)
        #expect(host.view.displayedStatus == notice)
        #expect(host.view.statusLabel.stringValue == notice)
        // The zoom reminder follows on its own line. The chip carries the level and speaks the reminder, so the
        // status label itself no longer holds it.
        host.press("=", .command)
        let zoom = try #require(host.view.zoomChip)
        #expect(host.view.displayedStatus == notice + "\n" + zoom.spoken)
        #expect(host.view.chip.text == zoom.shown && host.view.chip.spokenText == zoom.spoken)
        #expect(host.view.statusLabel.stringValue == notice)
        #expect(host.view.findingsBanner.summaryLabel.stringValue == privacy)
        host.press("0", .command)
        #expect(host.view.displayedStatus == notice)
        #expect(host.view.findingsBanner.summaryLabel.stringValue == privacy)
        // A font that is not installed adds its hint between the notices and the zoom reminder.
        host.view.display(.ready(concealed),
                          typography: PreviewTypography(fontFamily: "FixtureFontThatDoesNotExist-80A7"))
        let hint = PreviewStrings.text(.typographyFallbackHint)
        #expect(host.view.displayedStatus == notice + "\n" + hint)
        #expect(host.view.statusLabel.stringValue == notice + "\n" + hint)
        #expect(host.view.findingsBanner.summaryLabel.stringValue == privacy)
    }

    @Test func displayedStatusHoldsTheLimitsToo() {
        let host = harness()
        defer { host.release() }
        let partial = partialPresentation("safe words\nmore words", redactions: 1)
        host.view.display(.ready(partial), locale: english)
        let notices = PresentationNotices.notices(for: partial, locale: english)
        let limit = notices.first { $0.kind == .limit }?.text ?? ""
        #expect(!limit.isEmpty)
        // Privacy stays in the collapsed findings summary; the status seam still includes the limit.
        #expect(host.view.findingsBanner.summaryLabel.stringValue == PreviewStrings.count(.findingSummaryConcealed, 1, locale: english))
        #expect(host.view.displayedStatus == limit)
        #expect(host.view.statusLabel.stringValue.isEmpty)
        #expect(host.view.limitsLabel.stringValue == limit)
    }

    @Test func displayedModesSelectedModeAndContentViewDescribeWhatIsOnScreen() throws {
        let host = harness()
        defer { host.release() }
        #expect(host.view.displayedModes == [.source] && host.view.selectedMode == .source)
        host.show(plainPresentation("safe"))
        #expect(host.view.displayedModes == [.source] && host.view.modeControl.isHidden)
        #expect(host.view.contentView(for: .source) === host.view.scrollView)
        #expect(host.view.contentView(for: .rendered) == nil && host.view.contentView(for: .table) == nil)

        host.show(presentationWithInvisibles(), resetsContentState: true)
        #expect(host.view.displayedModes == [.source, .invisibles] && host.view.selectedMode == .source)
        #expect(host.view.contentView(for: .invisibles) === host.view.scrollView)
        try select(.invisibles, in: host.view)
        #expect(host.view.selectedMode == .invisibles && host.view.modeControl.selectedSegment == 1)
    }

    @Test func contentViewNeverCreatesAViewOrComputesAProfile() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation("name,note\nalice,hello\n", format: .csv, syntax: .commaSeparated))
        #expect(host.view.displayedModes == [.source, .table, .profile] && host.view.selectedMode == .table)
        let table = try #require(descendants(of: NativeTablePreviewView.self, in: host.view).first)
        #expect(host.view.contentView(for: .table) === table && host.view.contentView(for: .profile) === table)
        let computed = host.view.dataProfileIsComputed
        _ = host.view.contentView(for: .profile)
        #expect(host.view.dataProfileIsComputed == computed)

        host.show(plainPresentation(#"{"a":1,"b":[true,null]}"#, format: .json, syntax: .json), resetsContentState: true)
        #expect(host.view.displayedModes.contains(.outline))
        #expect(host.view.contentView(for: .outline) === host.view.outlineView)

        // A registered mode view exists only once it has been shown.
        let markdown = "# One\n\nbody\n\n## Two\n\nmore\n"
        host.show(plainPresentation(markdown, format: .markdown, syntax: .markdown), resetsContentState: true)
        #expect(host.view.displayedModes.contains(.contents))
        #expect(host.view.contentView(for: .contents) == nil)
        try select(.contents, in: host.view)
        let contents = try #require(descendants(of: MarkupContentsView.self, in: host.view).first)
        #expect(host.view.contentView(for: .contents) === contents)
    }

    @Test func theNamedChromeAndContentViewsStayAttachedAcrossStateChanges() {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let members: [NSView] = [view.statusLabel, view.infoBadge, view.findingsBanner, view.lineNumberGutter,
                                 view.scrollView, view.modeControl, view.outlineView, view.accessoryBar,
                                 view.limitsLabel, view.chip, view.stateView]
        let textView = view.textView
        let scrollView = view.scrollView
        let modeControl = view.modeControl
        #expect(Set(members.map(ObjectIdentifier.init)).count == members.count)
        #expect(members.allSatisfy { $0.isDescendant(of: view) })

        view.display(.ready(plainPresentation("first safe text")))
        view.display(.unavailable(.missingFile))
        view.display(.ready(plainPresentation("replacement safe text")))
        // Composition may nest the views. The facade still exposes the same attached controls and content;
        // accessibility order is characterized separately through navigationOrderViews, not insertion indices.
        #expect(members.allSatisfy { $0.isDescendant(of: view) })
        #expect(view.textView === textView && view.scrollView === scrollView && view.modeControl === modeControl)
        #expect(view.contentView(for: .source) === scrollView)
        #expect(scrollView.documentView === textView)
        #expect(textView.string == "replacement safe text")
    }

    // MARK: Constant place

    @Test func theModeControlStaysWhereItIsWhenTheModeTheNotesOrTheZoomChange() throws {
        let host = harness()
        defer { host.release() }
        host.show(presentationWithInvisibles())
        let view = host.view
        let control = view.modeControl
        let resting = displayedFrame(of: control, in: view)
        #expect(!control.isHidden && view.statusLabel.isHidden)
        // Invisibles adds a note. It sits below the control and moves nothing.
        try select(.invisibles, in: view)
        #expect(same(displayedFrame(of: control, in: view), resting))
        #expect(!view.statusLabel.isHidden && !view.statusLabel.stringValue.isEmpty)
        #expect(displayedFrame(of: view.statusLabel, in: view).maxY <= displayedFrame(of: control, in: view).minY + 0.5)
        // Back to Source: the note goes away and the control still does not move.
        try select(.source, in: view)
        #expect(same(displayedFrame(of: control, in: view), resting) && view.statusLabel.isHidden)
        // A zoom step shows the chip, and moves nothing.
        host.press("=", .command)
        view.layoutSubtreeIfNeeded()
        #expect(!view.chip.isHidden && same(displayedFrame(of: control, in: view), resting))
        // The confirmation that takes the chip for a moment moves nothing either.
        view.reportCopy(.text)
        view.layoutSubtreeIfNeeded()
        #expect(same(displayedFrame(of: control, in: view), resting))
    }

    @Test func theChipSitsInItsReservedSlotAndTheControlStaysClearOfIt() throws {
        let host = harness()
        defer { host.release() }
        host.show(presentationWithInvisibles())
        let view = host.view
        view.layoutSubtreeIfNeeded()
        let slotLeading = view.infoBadge.frame.minX - PreviewChrome.rowGap - PreviewChrome.chipSlotWidth
        // With no chip showing, the control already keeps out of the slot.
        #expect(view.chip.isHidden)
        #expect(displayedFrame(of: view.modeControl, in: view).maxX <= slotLeading - PreviewChrome.gap + 0.5)
        host.press("=", .command)
        view.layoutSubtreeIfNeeded()
        #expect(!view.chip.isHidden)
        #expect(approximately(view.chip.frame.maxX, view.infoBadge.frame.minX - PreviewChrome.rowGap))
        #expect(view.chip.frame.minX >= slotLeading - 0.5)
        #expect(displayedFrame(of: view.modeControl, in: view).maxX <= view.chip.frame.minX - PreviewChrome.gap + 0.5)
        // The chip shares the control's row. Layout aligns on the control's alignment rect, not its frame.
        let controlRect = displayedAlignmentRect(of: view.modeControl, in: view)
        #expect(approximately(view.chip.frame.midY, controlRect.midY))
    }

    // MARK: Guides, slots and the safe area

    @Test func theHeaderRowTakesTheControlsHeightAndTheContentFillsTheRest() throws {
        let host = harness()
        defer { host.release() }
        host.show(presentationWithInvisibles())
        let view = host.view
        let control = view.modeControl
        let header = view.headerGuide.frame
        // Layout aligns on the control's alignment rect, not its frame.
        let controlRect = displayedAlignmentRect(of: control, in: view)
        #expect(approximately(header.minY, controlRect.minY) && approximately(header.height, controlRect.height))
        #expect(approximately(header.maxY, view.safeAreaRect.maxY - PreviewChrome.gap))
        #expect(approximately(header.minX, PreviewChrome.inset) && approximately(header.maxX, view.bounds.maxX - PreviewChrome.inset))
        let content = view.contentGuide.frame
        let textFrame = view.convert(view.scrollView.bounds, from: view.scrollView)
        #expect(approximately(content.minY, view.safeAreaRect.minY))
        #expect(approximately(content.minX, 0) && approximately(content.maxX, view.bounds.maxX))
        #expect(approximately(content.maxY, view.accessoryBar.frame.minY))
        #expect(approximately(textFrame.maxY, content.maxY) && approximately(textFrame.minY, content.minY))
    }

    @Test func limitsSitInTheirOwnSlotAtTheBottomAndTheContentEndsAboveIt() throws {
        let host = harness()
        defer { host.release() }
        let view = host.view
        var textFrame: NSRect { view.convert(view.scrollView.bounds, from: view.scrollView) }
        host.show(plainPresentation(numberedLines(30)))
        #expect(view.limitsLabel.isHidden && view.limitsLabel.stringValue.isEmpty)
        #expect(approximately(textFrame.minY, view.safeAreaRect.minY))
        let partial = partialPresentation(numberedLines(30))
        view.display(.ready(partial), locale: english)
        view.layoutSubtreeIfNeeded()
        let limit = try #require(PresentationNotices.notices(for: partial, locale: english).first { $0.kind == .limit }?.text)
        #expect(view.limitsLabel.stringValue == limit && !view.limitsLabel.isHidden)
        #expect(approximately(view.limitsLabel.frame.minY, view.safeAreaRect.minY + PreviewChrome.rowGap))
        #expect(textFrame.minY >= view.limitsLabel.frame.maxY - 0.5)
        #expect(approximately(view.contentGuide.frame.minY, view.limitsLabel.frame.maxY + PreviewChrome.rowGap))
        // Nothing of the limit is in the notes, and the slot gives its room back when the limit goes away.
        #expect(view.statusLabel.stringValue.isEmpty)
        view.display(.ready(plainPresentation(numberedLines(30))), locale: english)
        view.layoutSubtreeIfNeeded()
        #expect(view.limitsLabel.isHidden && approximately(textFrame.minY, view.safeAreaRect.minY))
    }

    @Test func aStateCollapsesTheHeaderAndFillsThePane() throws {
        let host = harness()
        defer { host.release() }
        host.show(presentationWithInvisibles(truncatedSourceBytes: 3_000_000))
        let view = host.view
        #expect(!view.modeControl.isHidden && !view.findingsBanner.isHidden && !view.limitsLabel.isHidden)
        view.display(.unavailable(.missingFile))
        view.layoutSubtreeIfNeeded()
        #expect(approximately(view.headerGuide.frame.height, 0))
        #expect(view.statusLabel.isHidden && view.infoBadge.isHidden && view.modeControl.isHidden)
        #expect(view.findingsBanner.isHidden && view.limitsLabel.isHidden && view.accessoryBar.frame.height == 0)
        // Nothing empty and focusable stands behind the state.
        #expect(view.scrollView.isHidden && view.textView.isHidden)
        #expect(!view.stateView.isHidden)
        #expect(approximately(view.stateView.frame.width, view.bounds.width) && approximately(view.stateView.frame.height, view.bounds.height))
    }

    @Test func theInsetsOfTheSafeAreaReachTheHeaderAndTheFooter() throws {
        let host = harness()
        defer { host.release() }
        let view = host.view
        view.additionalSafeAreaInsets = NSEdgeInsets(top: 28, left: 0, bottom: 10, right: 0)
        host.show(presentationWithInvisibles(truncatedSourceBytes: 3_000_000))
        view.layoutSubtreeIfNeeded()
        let safe = view.safeAreaRect
        // The insets are part of the view's own safe area ...
        #expect(approximately(safe.maxY, view.bounds.maxY - 28) && approximately(safe.minY, 10))
        // ... the header starts below them and the limits end above them.
        #expect(approximately(view.headerGuide.frame.maxY, safe.maxY - PreviewChrome.gap))
        let controlRect = displayedAlignmentRect(of: view.modeControl, in: view)
        #expect(controlRect.maxY <= safe.maxY - PreviewChrome.gap + 0.5)
        #expect(approximately(view.limitsLabel.frame.minY, safe.minY + PreviewChrome.rowGap))
    }

    // MARK: One layout pass

    @Test func theChromeAddsNoTextLayoutPassWhenItsPartsAppearOrTheDensityChanges() throws {
        let lines = (1...400).map { "line \($0) with safe words that need wrapping " + String(repeating: "word ", count: 12) }
        // The first line holds the hidden character that gives the preview its Invisibles mode, and so its control.
        let text = "alpha\u{200B}beta\n" + lines.joined(separator: "\n")
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let content = try #require(view.scrollView.documentView as? NSTextView)
        view.scrollView.scrollerStyle = .legacy
        let counter = ChromeLayoutPassCounter(forwarding: content.layoutManager?.delegate)
        content.layoutManager?.delegate = counter
        // Every part of the chrome at once: a mode control, a note, findings and a limit.
        view.display(.ready(presentationWithInvisibles(text, redactions: 1, truncatedSourceBytes: 5_000_000)), locale: english)
        view.layoutSubtreeIfNeeded()
        #expect(counter.completedPasses == 1)
        #expect(!view.modeControl.isHidden && !view.findingsBanner.isHidden && !view.limitsLabel.isHidden)
        // Narrower than the density threshold: the text wraps once more, and the density switch adds nothing.
        let before = counter.completedPasses
        view.setFrameSize(NSSize(width: PreviewChrome.compactWidth - PreviewChrome.compactHysteresis - 20, height: 420))
        view.layoutSubtreeIfNeeded()
        #expect(view.density == .compact)
        #expect(counter.completedPasses == before + 1)
    }

    // MARK: Reading order

    @Test func voiceOverReadsTheHeaderTheFindingsTheControlTheContentAndTheLimitsInThatOrder() throws {
        let host = harness()
        defer { host.release() }
        host.show(presentationWithInvisibles(redactions: 1, truncatedSourceBytes: 3_000_000, isReformatted: true))
        host.press("=", .command)
        host.view.layoutSubtreeIfNeeded()
        let view = host.view
        let expected: [NSView] = [view.factsLabel, view.statusLabel, view.chip, view.infoBadge, view.findingsBanner, view.modeControl,
                                  view.scrollView, view.limitsLabel]
        #expect(view.navigationOrderViews.map(ObjectIdentifier.init) == expected.map(ObjectIdentifier.init))
        // AppKit exposes labels and segmented controls through their cells on this SDK. Choose each view's
        // actual platform element, then require all eight semantic owners in order without losing raw children.
        let platformChildren = view.accessibilityChildren() ?? []
        let expectedElements = try expected.map { wanted -> AnyObject in
            let cell = (wanted as? NSControl)?.cell
            return try #require(platformChildren.first { child in
                let object = child as AnyObject
                return object === wanted || cell.map { object === $0 } == true
            }) as AnyObject
        }
        let received = (view.accessibilityChildrenInNavigationOrder() ?? []).map { $0 as AnyObject }
        #expect(received.map(ObjectIdentifier.init) == expectedElements.map(ObjectIdentifier.init))
        #expect(Set(received.map(ObjectIdentifier.init))
                    == Set(platformChildren.map { ObjectIdentifier($0 as AnyObject) }))
    }

    @Test func hiddenViewsAreNotPartOfTheReadingOrderAndAStateStandsAlone() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation("safe"))
        let view = host.view
        #expect(view.navigationOrderViews.allSatisfy { !$0.isHidden })
        #expect(!view.navigationOrderViews.contains { $0 === view.modeControl || $0 === view.findingsBanner })
        view.display(.unavailable(.missingFile))
        #expect(view.navigationOrderViews.map(ObjectIdentifier.init) == [ObjectIdentifier(view.stateView)])
    }

    // MARK: Narrow rows

    /// The chip's slot is a preference: a row too narrow for it keeps the notes and the mode control whole, and the
    /// slot shrinks instead (the first row of a 200 pt preview once lost its content to a 38 pt column of notes).
    @Test func aNarrowPreviewKeepsItsNotesReadableAndItsContentInView() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 200, height: 140))
        // A real formatting notice shares the first row with the badge; privacy stays in its summary.
        let text = "safe words"
        let safe = TextPresentation(formatID: .plainText, text: text, lineCount: 1,
                                    byteCount: text.utf8.count, encoding: .utf8,
                                    redactionCount: 1, isReformatted: true)
        view.display(.ready(safe), locale: english)
        view.layoutSubtreeIfNeeded()
        #expect(view.density == .compact && !view.statusLabel.isHidden)
        #expect(view.statusLabel.stringValue == PreviewStrings.text(.codeNoticeReformatted))
        #expect(!view.findingsBanner.isHidden)
        #expect(view.findingsBanner.summaryLabel.stringValue == PreviewStrings.count(.findingSummaryConcealed, 1, locale: english))
        #expect(view.statusLabel.frame.width >= PreviewChrome.notesMinimumWidth - 1)
        // Whatever the notes need, the content below keeps room for more than a line of text.
        let textFrame = view.convert(view.scrollView.bounds, from: view.scrollView)
        let lineHeight = try #require(view.textView.layoutManager).defaultLineHeight(for: #require(view.textView.font))
        #expect(textFrame.height > lineHeight)
        #expect(textFrame.maxY <= view.statusLabel.frame.minY + 0.5)
    }

    @Test func theSlotGivesWayToTheModeControlInANarrowRow() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 260, height: 300))
        view.display(.ready(presentationWithInvisibles()), locale: english)
        view.layoutSubtreeIfNeeded()
        let control = try #require(view.visibleModeControl)
        #expect(!control.isHidden)
        // The control keeps the width it asks for, however little is left for the slot beside it.
        #expect(control.frame.width >= control.intrinsicContentSize.width - 0.5)
        let controlRect = displayedAlignmentRect(of: control, in: view)
        #expect(controlRect.maxX <= view.infoBadge.frame.minX - PreviewChrome.rowGap + 0.5)
    }
}
