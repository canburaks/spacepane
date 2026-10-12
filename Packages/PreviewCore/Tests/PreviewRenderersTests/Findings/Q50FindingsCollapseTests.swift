import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q50 collapsed findings and bounded details", .serialized)
@MainActor
struct Q50FindingsCollapseTests {
    private let english = Locale(identifier: "en_US")

    @Test(arguments: [1, 3, 12_345]) func summaryUsesActualConcealedValuesAndTheCompleteCopyPolicy(count: Int) {
        let findings = [PreviewFinding(kind: .secretAPIKey, count: 77),
                        PreviewFinding(kind: .hiddenZeroWidth, count: 999)]
        for locale in [english, Locale(identifier: "de_DE"), Locale(identifier: "tr_TR")] {
            let banner = NativeFindingsBanner(frame: NSRect(x: 0, y: 0, width: 700, height: 0))
            banner.display(findings, concealedValueCount: count, offersConcealedCopy: false,
                           palette: chromeTestPalette(), locale: locale)
            let expected = PreviewStrings.count(.findingSummaryConcealed, count, locale: locale)
            #expect(banner.summaryLabel.stringValue == expected)
            #expect(banner.summaryLabel.accessibilityLabel() == expected)
            #expect(expected.contains(count.formatted(.number.locale(locale))))
            #expect(!expected.contains("%") && !expected.contains("finding."))
            #expect(!banner.isExpanded && banner.detailScrollView.isHidden)
            #expect(banner.summarySymbolName == "eye.slash")
        }
    }

    @Test func genericSummaryCountsRecordsRatherThanTheirOccurrences() {
        let banner = NativeFindingsBanner(frame: .zero)
        let findings = [PreviewFinding(kind: .hiddenZeroWidth, count: 200),
                        PreviewFinding(kind: .archiveNested, count: 90)]
        banner.display(findings, offersConcealedCopy: false, palette: chromeTestPalette(), locale: english)
        #expect(banner.summaryLabel.stringValue == "2 findings to review.")
        #expect(!banner.isExpanded && banner.detailScrollView.isHidden)
        banner.display([findings[0]], offersConcealedCopy: false, palette: chromeTestPalette(), locale: english)
        #expect(banner.summaryLabel.stringValue == "1 finding to review.")
        #expect(banner.summarySymbolName != "info.circle")
    }

    @Test func emptyBannerHasNoHeightAndConcealedOnlyPresentationKeepsThePolicy() {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        host.show(presentation())
        #expect(host.view.findingsBanner.isHidden && host.view.findingsBanner.frame.height == 0)
        host.show(presentation(concealed: 3))
        let banner = host.view.findingsBanner
        #expect(!banner.isHidden && banner.hasContent && !banner.isExpanded)
        #expect(banner.summaryLabel.stringValue == "3 likely secrets hidden. Selection and copying use the concealed text.")
        #expect(banner.detailsButton.isHidden && !banner.offersConcealedCopy)
        #expect(banner.frame.height > 0)
        banner.setExpanded(true)
        #expect(!banner.isExpanded)
    }

    @Test func disclosureUsesNativeButtonActionsAndReportsOnlyChanges() {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        host.show(presentation(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1)]))
        let banner = host.view.findingsBanner
        var changes: [Bool] = []
        var presses = 0
        let expansion = banner.onExpansionChanged
        let disclosure = banner.onDisclosureActivated
        banner.onExpansionChanged = { expansion?($0); changes.append($0) }
        banner.onDisclosureActivated = { disclosure?(); presses += 1 }
        #expect(banner.detailsButton.title == "Show details")
        banner.detailsButton.performClick(nil)
        #expect(banner.isExpanded && !banner.detailScrollView.isHidden)
        #expect(banner.detailsButton.title == "Hide details")
        #expect((banner.detailsButton.accessibilityValue() as? Int) == 1)
        banner.setExpanded(true)
        #expect(changes == [true] && presses == 1)
        // AppKit can deliver the action while returning false; verify the actual state and callbacks.
        _ = banner.detailsButton.accessibilityPerformPress()
        #expect(!banner.isExpanded && banner.detailScrollView.isHidden)
        #expect(changes == [true, false] && presses == 2)
        banner.clear()
        #expect(changes == [true, false])
    }

    @Test func everyBoundedFindingRemainsReachableWithCloudFolderFirst() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let findings = allFindings()
        host.show(presentation(findings: findings, concealed: 3))
        let banner = host.view.findingsBanner
        #expect(banner.orderedDetailKinds == [.secretSyncedFolder] + findings.filter { $0.kind != .secretSyncedFolder }.map(\.kind))
        #expect(banner.rowLabels.count == findings.count)
        #expect(!banner.rowLabels.contains { $0.stringValue.contains("More findings") })
        banner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        let scroll = banner.detailScrollView
        let document = try #require(scroll.documentView)
        let first = try #require(banner.rowLabels.first)
        let last = try #require(banner.rowLabels.last)
        #expect(scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        #expect(document.convert(first.bounds, from: first).intersects(scroll.contentView.bounds))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(document.convert(last.bounds, from: last).intersects(scroll.contentView.bounds))
    }

    @Test(arguments: [700, 380], [1.0, 2.0])
    func expandedBandRespectsHostCapScrollsAndCollapseReturnsSpace(width: Int, fontScale: Double) throws {
        let host = InteractionHarness(width: CGFloat(width), height: width == 700 ? 500 : 700)
        defer { host.release() }
        host.show(presentation(findings: allFindings(), concealed: 3))
        let banner = host.view.findingsBanner
        for label in [banner.summaryLabel] + banner.rowLabels + banner.detailLabels {
            if let font = label.font { label.font = NSFont.systemFont(ofSize: font.pointSize * CGFloat(fontScale)) }
        }
        banner.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        let collapsedHeight = banner.frame.height
        let contentHeight = host.view.scrollView.frame.height
        let windowFrame = host.window.frame
        banner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        let expandedHeight = banner.frame.height
        let cap = host.view.safeAreaLayoutGuide.frame.height * PreviewChrome.findingsMaximumFraction
        #expect(expandedHeight <= cap + 1)
        #expect(expandedHeight > collapsedHeight)
        #expect(banner.detailScrollView.contentView.bounds.height > 0)
        let document = try #require(banner.detailScrollView.documentView)
        #expect(document.frame.height > banner.detailScrollView.contentView.bounds.height)
        #expect(host.view.scrollView.frame.height < contentHeight)
        banner.collapseDetails()
        host.view.layoutSubtreeIfNeeded()
        #expect(abs(banner.frame.height - collapsedHeight) <= 1)
        #expect(abs(host.view.scrollView.frame.height - contentHeight) <= 1)
        #expect(host.window.frame == windowFrame)
    }

    @Test func decodedDetailIsInertClippedToTwoLinesAndCompleteForAccessibility() throws {
        let payload = String(repeating: "<b>plain text</b>\n", count: 80)
        let finding = PreviewFinding(kind: .hiddenUnicodeTags, count: 500, detail: .decodedText(payload))
        let host = InteractionHarness(width: 380, height: 700)
        defer { host.release() }
        host.show(presentation(findings: [finding]))
        let banner = host.view.findingsBanner
        banner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        let detail = try #require(banner.detailLabels.first)
        let message = try #require(banner.rowLabels.first)
        let expected = try #require(FindingText.detail(for: finding, locale: english))
        let font = try #require(detail.font)
        #expect(detail.maximumNumberOfLines == 2 && detail.lineBreakMode == .byWordWrapping)
        #expect(detail.cell?.truncatesLastVisibleLine == true)
        #expect(detail.frame.height <= ceil(font.ascender - font.descender + font.leading) * 2 + 2)
        #expect(Array(detail.stringValue.utf16) == Array(expected.utf16))
        #expect(message.accessibilityLabel()?.contains(expected) == true)
        #expect(detail.attributedStringValue.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(expected.contains("<b>") && expected.count < payload.count)
    }

    @Test func expandedDetailsKeepTheirScrollPositionAcrossRestylingAndHostResize() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let safe = presentation(findings: allFindings(), concealed: 3)
        host.show(safe)
        let banner = host.view.findingsBanner
        banner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        let scroll = banner.detailScrollView
        let first = try #require(banner.rowLabels.first)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        let position = scroll.contentView.bounds.origin
        #expect(position.y > 0)
        host.view.display(.ready(safe), theme: .dark, locale: host.view.presentationLocale)
        host.view.layoutSubtreeIfNeeded()
        #expect(banner.isExpanded && banner.rowLabels.first === first)
        #expect(scroll.contentView.bounds.origin == position)
        host.window.setContentSize(NSSize(width: 380, height: 700))
        host.view.layoutSubtreeIfNeeded()
        #expect(banner.isExpanded && banner.rowLabels.first === first)
        #expect(abs(scroll.contentView.bounds.origin.y - position.y) <= 1)
        #expect(banner.frame.height <= host.view.safeAreaLayoutGuide.frame.height * PreviewChrome.findingsMaximumFraction + 1)
    }

    @Test func disclosurePostsOneLayoutWhileProgrammaticCollapseDoesNotDuplicateTransitions() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        var layouts: [(state: NativeStateContent.Kind?, mode: NativePreviewMode, expanded: Bool)] = []
        host.view.announcer.notificationHandler = { [weak view = host.view] element, notification, userInfo in
            guard let view, notification == .layoutChanged else { return }
            #expect(element === view && userInfo.isEmpty)
            layouts.append((view.stateContent?.kind, view.selectedMode, view.findingsBanner.isExpanded))
        }
        let safe = presentation(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1)])
        host.show(safe)
        layouts.removeAll()
        host.view.findingsBanner.detailsButton.performClick(nil)
        #expect(layouts.count == 1 && layouts.first?.expanded == true)
        layouts.removeAll()
        host.view.showLoading()
        #expect(!host.view.findingsBanner.isExpanded && layouts.isEmpty)
        try #require(scheduler.waiting.first).run()
        #expect(layouts.count == 1 && layouts.first?.state == .loading && layouts.first?.expanded == false)
        host.show(safe)
        host.view.findingsBanner.detailsButton.performClick(nil)
        layouts.removeAll()
        host.view.display(.ready(safe), locale: host.view.presentationLocale, resetsContentState: true)
        #expect(!host.view.findingsBanner.isExpanded && layouts.isEmpty)
        host.view.findingsBanner.detailsButton.performClick(nil)
        layouts.removeAll()
        let markdown = presentation(findings: safe.findings, format: .markdown, text: "# Safe\n\ntext\n")
        host.view.display(.ready(markdown), locale: host.view.presentationLocale, resetsContentState: true)
        #expect(layouts.count == 1 && layouts.first?.mode == .rendered && layouts.first?.expanded == false)
    }

    @Test func modeAndAppearanceKeepDisclosureButNewGenerationsAndStatesCollapseIt() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let safe = presentation(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1)])
        host.show(safe)
        let banner = host.view.findingsBanner
        banner.setExpanded(true)
        host.view.display(.ready(safe), theme: .dark, locale: english)
        #expect(banner.isExpanded)
        try select(.invisibles, in: host.view)
        #expect(banner.isExpanded)
        host.view.display(.ready(safe), locale: english, resetsContentState: true)
        #expect(!banner.isExpanded)
        banner.setExpanded(true)
        host.view.display(.unavailable(.malformedDocument), locale: english)
        #expect(banner.isHidden && !banner.isExpanded && banner.rowLabels.isEmpty)
        host.show(safe)
        banner.setExpanded(true)
        host.view.showLoading()
        #expect(banner.isHidden && !banner.isExpanded)
    }

    @Test func concealedCopyOnlyExistsInRenderedAndInvisiblesAndConfirmsSuccessfulWrites() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let safe = presentation(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1)], concealed: 1,
                                format: .markdown, text: "# Safe\npassword=••••\n\n## More\nsafe\n")
        host.view.concealedTextPasteboard = host.pasteboard
        host.show(safe)
        #expect(host.view.selectedMode == .rendered && host.view.findingsBanner.offersConcealedCopy)
        host.announcements.texts.removeAll()
        host.view.findingsBanner.copyActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == safe.text)
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
        for mode in [NativePreviewMode.source, .contents] {
            try select(mode, in: host.view)
            #expect(!host.view.findingsBanner.offersConcealedCopy)
            host.pasteboard.clearContents()
            host.pasteboard.setString("unchanged", forType: .string)
            host.announcements.texts.removeAll()
            host.view.copyConcealedText()
            host.view.findingsBanner.copyActionButton.performClick(nil)
            #expect(host.pasteboard.string(forType: .string) == "unchanged" && host.announcements.texts.isEmpty)
        }
        try select(.invisibles, in: host.view)
        #expect(host.view.findingsBanner.offersConcealedCopy)
        host.announcements.texts.removeAll()
        host.view.findingsBanner.copyActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == safe.text)
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
        host.view.plainTextCopyWriter = { _, board in
            #expect(board === host.pasteboard)
            return false
        }
        host.view.findingsBanner.copyActionButton.performClick(nil)
        #expect(host.announcements.texts.count == 1)
        #expect(!host.view.displayedStatus.contains(PreviewStrings.text(.privacyNotice)))
    }

    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        let index = try #require(view.displayedModes.firstIndex(of: mode))
        #expect(view.selectMode(number: index + 1))
    }

    private func presentation(findings: [PreviewFinding] = [], concealed: Int = 0,
                              format: FormatID = .plainText, text: String = "safe text\n") -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: 2, byteCount: text.utf8.count,
                         encoding: .utf8, redactionCount: concealed,
                         syntax: format == .markdown ? .markdown : .plain, findings: findings)
    }

    private func allFindings() -> [PreviewFinding] {
        PreviewFindings.normalized(PreviewFindingKind.allCases.map {
            $0 == .secretSyncedFolder ? PreviewFinding(kind: $0, count: 1, detail: .syncProvider(.dropbox))
                : PreviewFinding(kind: $0, count: 1, lines: [1])
        })
    }
}
