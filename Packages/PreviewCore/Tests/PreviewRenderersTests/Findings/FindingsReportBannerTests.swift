import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Copy Findings Report on the banner (decision 029): offered while findings are listed, written to the preview's
/// private pasteboard, confirmed once like every other copy, and independent of Copy Concealed Text. The report's
/// heading and footer resources arrive with the translations, so these tests compare against the keys' own
/// resolution and assert structure, order and absent text instead of exact English sentences.
@Suite("Copy Findings Report on the banner", .serialized)
@MainActor
struct FindingsReportBannerTests {
    private let english = Locale(identifier: "en_US")
    private let confirmation = PreviewStrings.text(.findingsReportCopied)

    /// Ten findings, more than the banner's rows ever needed to scroll, each with real English wording today.
    private let manyKinds: [PreviewFindingKind] = [
        .archiveUnsafePath, .archiveLinkEscape, .archiveLinks, .archiveExecutables, .archiveDisguisedName,
        .archiveDirectionalName, .archiveEncrypted, .archiveNested, .hiddenZeroWidth, .secretAPIKey
    ]

    private func many() -> [PreviewFinding] {
        PreviewFindings.normalized(manyKinds.map { PreviewFinding(kind: $0, count: 2, lines: [3, 9]) })
    }

    private func presentation(_ findings: [PreviewFinding], text: String = "alpha\nbeta\n", redactions: Int = 0,
                              format: FormatID = .plainText) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: 2, byteCount: text.utf8.count, encoding: .utf8,
                         redactionCount: redactions, syntax: format == .markdown ? .markdown : .plain,
                         findings: PreviewFindings.normalized(findings))
    }

    private func harness(width: CGFloat = 700, height: CGFloat = 500) -> (host: InteractionHarness, scheduler: ManualChromeScheduler) {
        let host = InteractionHarness(width: width, height: height)
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        host.view.concealedTextPasteboard = host.pasteboard
        return (host, scheduler)
    }

    private func show(_ presentation: TextPresentation, in host: InteractionHarness, locale: Locale? = nil,
                      resetsContentState: Bool = true) {
        host.view.display(.ready(presentation), locale: locale ?? english, resetsContentState: resetsContentState)
        host.view.layoutSubtreeIfNeeded()
    }

    private func expectedReport(for presentation: TextPresentation, locale: Locale? = nil) -> String {
        FindingsReport.make(findings: presentation.findings,
                            formatName: FindingsReport.formatName(for: presentation.formatID),
                            locale: locale ?? english).text
    }

    // MARK: Offered only with findings

    @Test func theActionIsOfferedExactlyWhileTheBannerListsAFinding() {
        let (host, _) = harness()
        defer { host.release() }
        let banner = host.view.findingsBanner
        let button = banner.findingsReportActionButton
        show(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])]), in: host)
        #expect(!banner.isHidden && !button.isHidden && banner.offersFindingsReport)
        #expect(button.title == PreviewStrings.text(.findingsReportCopy))
        #expect(button.toolTip == PreviewStrings.text(.findingsReportCopyHint))

        // Concealment alone shows the banner and Copy Concealed Text, but there is no list to copy.
        show(presentation([], redactions: 2, format: .markdown), in: host)
        #expect(!banner.isHidden && banner.offersConcealedCopy)
        #expect(button.isHidden && !banner.offersFindingsReport)

        // An empty banner collapses with everything in it.
        show(presentation([]), in: host)
        #expect(banner.isHidden && !banner.hasContent && button.isHidden && !banner.offersFindingsReport)

        show(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])]), in: host)
        #expect(!button.isHidden)
        for outcome: PreviewOutcome in [.disabledByUser(.plainText), .unavailable(.malformedDocument), .cancelled] {
            host.view.display(.ready(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1)])), locale: english)
            #expect(!button.isHidden)
            host.view.display(outcome, locale: english)
            #expect(button.isHidden && !banner.offersFindingsReport, "\(outcome)")
        }
        host.view.display(.ready(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1)])), locale: english)
        host.view.showLoading()
        #expect(button.isHidden && !banner.offersFindingsReport)
    }

    @Test func aStandaloneBannerCallsItsHookOnlyWhileTheActionIsOffered() {
        let banner = NativeFindingsBanner(frame: NSRect(x: 0, y: 0, width: 700, height: 0))
        var calls = 0
        banner.onCopyFindingsReport = { calls += 1 }
        let button = banner.findingsReportActionButton
        banner.display([PreviewFinding(kind: .hiddenZeroWidth, count: 1)], offersConcealedCopy: false,
                       palette: chromeTestPalette(), locale: english)
        button.performClick(nil)
        #expect(calls == 1)
        banner.display([], offersConcealedCopy: true, palette: chromeTestPalette(), locale: english)
        button.performClick(nil)
        banner.clear()
        button.performClick(nil)
        #expect(calls == 1)
    }

    // MARK: What is copied

    @Test func theWholeReportIsCopiedThroughThePrivatePasteboardEvenWhenTheBannerIsCollapsed() throws {
        let (host, _) = harness()
        defer { host.release() }
        let shown = presentation(many(), format: .markdown)
        show(shown, in: host)
        let banner = host.view.findingsBanner
        #expect(!banner.isExpanded && shown.findings.count == 10)
        banner.findingsReportActionButton.performClick(nil)
        let copied = try #require(host.pasteboard.string(forType: .string))
        #expect(copied == expectedReport(for: shown))

        let paragraphs = copied.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 3)
        let name = FindingsReport.formatName(for: .markdown)
        #expect(paragraphs.first == PreviewStrings.format(.findingsReportHeading, arguments: [name], locale: english))
        #expect(paragraphs.last == PreviewStrings.text(.findingsReportFooter))
        let bullets = paragraphs[1].components(separatedBy: "\n")
        #expect(bullets.count == 10 && bullets.allSatisfy { $0.hasPrefix("• ") && $0.hasSuffix("(Lines: 3, 9)") })
        // The rows keep the banner's order, so each bullet carries its row's wording.
        let ordered = FindingsReport.inBannerOrder(shown.findings)
        #expect(banner.orderedDetailKinds == ordered.map(\.kind))
        for (finding, bullet) in zip(ordered, bullets) {
            #expect(bullet.contains(FindingText.message(for: finding, locale: english)))
            #expect(bullet.hasPrefix("• \(FindingText.severityDescription(finding.severity)): "))
        }
        #expect(!banner.isExpanded)
    }

    @Test func theReportCarriesNoFileNamePathSourceTextOrDecodedText() throws {
        let (host, _) = harness()
        defer { host.release() }
        let body = "path = /Users/alice/Documents/payroll-2026.txt\nTOPSECRET_SENTINEL\nsecret.env\n"
        let findings = [
            PreviewFinding(kind: .hiddenUnicodeTags, severity: .warning, count: 3, lines: [2],
                           detail: .decodedText("DECODED_SENTINEL send the keys")),
            PreviewFinding(kind: .secretAPIKey, count: 1, lines: [1]),
            PreviewFinding(kind: .secretSyncedFolder, count: 1, detail: .syncProvider(.dropbox))
        ]
        show(presentation(findings, text: body), in: host)
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        let copied = try #require(host.pasteboard.string(forType: .string))
        for forbidden in ["payroll", "/Users", "alice", "TOPSECRET", "secret.env", "DECODED_SENTINEL", "send the keys"] {
            #expect(!copied.contains(forbidden), "\(forbidden)")
        }
        for line in body.components(separatedBy: "\n") where !line.isEmpty { #expect(!copied.contains(line)) }
        #expect(copied.components(separatedBy: "\n").filter { $0.hasPrefix("• ") }.count == 3)
        // The banner may still show the decoded text; the clipboard never does.
        host.view.findingsBanner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.findingsBanner.detailLabels.contains { $0.stringValue.contains("DECODED_SENTINEL") })
    }

    @Test func theReportFollowsThePresentationLocale() throws {
        let (host, _) = harness()
        defer { host.release() }
        let german = Locale(identifier: "de_DE")
        let shown = presentation([PreviewFinding(kind: .hiddenZeroWidth, severity: .caution, count: 1, lines: [12_345])])
        show(shown, in: host, locale: german)
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        let copied = try #require(host.pasteboard.string(forType: .string))
        #expect(copied == expectedReport(for: shown, locale: german))
        #expect(copied.contains("(Lines: 12.345)"))
    }

    @Test func aReplacementPresentationReplacesTheReport() throws {
        let (host, _) = harness()
        defer { host.release() }
        show(presentation([PreviewFinding(kind: .archiveNested, count: 1)]), in: host)
        let second = presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [2])])
        show(second, in: host, resetsContentState: false)
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        let copied = try #require(host.pasteboard.string(forType: .string))
        #expect(copied == expectedReport(for: second))
        #expect(!copied.contains("Archives inside this archive"))
    }

    // MARK: Confirmation

    @Test func aSuccessfulCopyShowsOneChipAnnouncesOnceAndEndsAfterItsDuration() {
        let (host, scheduler) = harness()
        defer { host.release() }
        show(presentation(many()), in: host)
        #expect(host.view.chip.isHidden)
        host.announcements.texts.removeAll()
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        #expect(host.announcements.texts == [confirmation])
        #expect(!host.view.chip.isHidden && host.view.chip.text == confirmation && host.view.chip.spokenText == confirmation)
        #expect(scheduler.waiting.count == 1 && scheduler.waiting.first?.delay == PreviewChrome.chipDuration)
        // The banner itself draws and says nothing.
        #expect(descendants(of: NSTextField.self, in: host.view.findingsBanner).filter { $0.stringValue == confirmation }.isEmpty)
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden && host.announcements.texts == [confirmation])
        // A second copy is a second announcement and restarts the chip's life.
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        #expect(host.announcements.texts == [confirmation, confirmation, confirmation])
        #expect(scheduler.scheduled.count == 3 && scheduler.scheduled[1].isCancelled && scheduler.waiting.count == 1)
    }

    @Test func aFailedWriteLeavesNoChipAndNoAnnouncement() {
        let (host, scheduler) = harness()
        defer { host.release() }
        show(presentation(many()), in: host)
        host.pasteboard.clearContents()
        host.pasteboard.setString("unchanged", forType: .string)
        host.view.plainTextCopyWriter = { _, board in
            #expect(board === host.pasteboard)
            return false
        }
        host.announcements.texts.removeAll()
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        #expect(host.announcements.texts.isEmpty && host.view.chip.isHidden && scheduler.scheduled.isEmpty)
        #expect(host.pasteboard.string(forType: .string) == "unchanged")
    }

    @Test func nothingIsCopiedOrAnnouncedWithoutFindings() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.pasteboard.clearContents()
        host.pasteboard.setString("unchanged", forType: .string)
        show(presentation([], redactions: 1, format: .markdown), in: host)
        host.announcements.texts.removeAll()
        #expect(!host.view.copyFindingsReport())
        host.view.findingsBanner.findingsReportActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == "unchanged")
        #expect(host.announcements.texts.isEmpty && host.view.chip.isHidden && scheduler.scheduled.isEmpty)
    }

    // MARK: Beside Copy Concealed Text

    @Test func copyConcealedTextStillWorksAndTheTwoActionsDoNotInterfere() throws {
        let (host, _) = harness()
        defer { host.release() }
        let text = "user=demo\npassword=••••\n"
        let shown = presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])], text: text,
                                 redactions: 1, format: .markdown)
        show(shown, in: host)
        let banner = host.view.findingsBanner
        #expect(host.view.selectedMode == .rendered && banner.offersConcealedCopy && banner.offersFindingsReport)
        #expect(!banner.copyActionButton.isHidden && !banner.findingsReportActionButton.isHidden)
        host.announcements.texts.removeAll()

        banner.copyActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == text)
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])

        banner.findingsReportActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == expectedReport(for: shown))
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied), confirmation])
        #expect(!(host.pasteboard.string(forType: .string) ?? "").contains("password"))

        banner.copyActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == text)

        // Source mode has no concealed-text copy, and the report is still on offer.
        let index = try #require(host.view.displayedModes.firstIndex(of: .source))
        #expect(host.view.selectMode(number: index + 1))
        #expect(!banner.offersConcealedCopy && banner.offersFindingsReport)
    }

    // MARK: Collapse, overflow, clearing

    @Test func collapseDisclosureAndClearingBehaveAsBefore() {
        let (host, _) = harness()
        defer { host.release() }
        let shown = presentation(many())
        show(shown, in: host)
        let banner = host.view.findingsBanner
        #expect(!banner.isExpanded && banner.detailScrollView.isHidden && !banner.detailsButton.isHidden)
        #expect(banner.summaryLabel.stringValue == "10 findings to review.")
        banner.setExpanded(true)
        host.view.layoutSubtreeIfNeeded()
        #expect(banner.rowLabels.count == 10 && !banner.rowLabels.contains { $0.stringValue.contains("More findings") })
        #expect(!banner.findingsReportActionButton.isHidden)
        banner.collapseDetails()
        #expect(!banner.isExpanded && !banner.findingsReportActionButton.isHidden)
        banner.clear()
        #expect(banner.isHidden && banner.rowLabels.isEmpty && banner.findingsReportActionButton.isHidden)
        #expect(!banner.offersFindingsReport)
    }

    // MARK: Style, keyboard and VoiceOver

    @Test func theButtonIsStyledAndReachedLikeCopyConcealedText() throws {
        let (host, _) = harness()
        defer { host.release() }
        show(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])], redactions: 1, format: .markdown), in: host)
        let banner = host.view.findingsBanner
        let report = banner.findingsReportActionButton
        let concealed = banner.copyActionButton
        #expect(report !== concealed && report.superview === concealed.superview)
        let row = try #require(report.superview as? NSStackView)
        let order = row.arrangedSubviews.filter { !$0.isHidden }
        #expect(order == [banner.detailsButton, concealed, report])
        #expect(report.bezelStyle == concealed.bezelStyle && report.controlSize == concealed.controlSize)
        #expect(report.target === banner && concealed.target === banner && report.action != nil)
        #expect(report.contentTintColor == nil && report.bezelColor == nil)
        #expect(report.isEnabled && report.acceptsFirstResponder && !report.refusesFirstResponder)
        // Whether it joins the key loop follows the system's full keyboard access setting, as for the other buttons.
        #expect(report.canBecomeKeyView == concealed.canBecomeKeyView)
        // Keyboard focus: it can be the first responder like the other buttons, and the arrow is the system's.
        host.window.makeKeyAndOrderFront(nil)
        #expect(host.window.makeFirstResponder(report) && host.window.firstResponder === report)
        // VoiceOver: a labelled control with the hint, treated like the other actions.
        #expect(report.accessibilityRole() == concealed.accessibilityRole())
        #expect(report.isAccessibilityElement() == concealed.isAccessibilityElement())
        #expect(report.accessibilityLabel() == PreviewStrings.text(.findingsReportCopy))
        #expect(report.accessibilityHelp() == PreviewStrings.text(.findingsReportCopyHint))
        #expect(concealed.accessibilityHelp() == PreviewStrings.text(.findingActionCopyConcealedHelp))
    }

    @Test func theButtonStaysAvailableAndUncoloredInEveryAppearance() {
        let banner = NativeFindingsBanner(frame: NSRect(x: 0, y: 0, width: 700, height: 0))
        let findings = [PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1]),
                        PreviewFinding(kind: .secretSyncedFolder, count: 1, detail: .syncProvider(.box))]
        for (isDark, contrast) in [(false, false), (true, false), (false, true), (true, true)] {
            let palette = NativeTextPalette(theme: .system, isDark: isDark, increasedContrast: contrast)
            banner.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            banner.display(findings, offersConcealedCopy: true, palette: palette, locale: english)
            let button = banner.findingsReportActionButton
            #expect(!button.isHidden && button.isEnabled, "dark \(isDark) contrast \(contrast)")
            // The system draws the control, so its colors follow the appearance and the contrast setting.
            #expect(button.contentTintColor == nil && button.bezelColor == nil)
        }
    }

    @Test func theActionSitsOutsideTheScrollingDetailsSoACollapsedBannerStillOffersIt() {
        // The button sits in the always-visible controls row, outside the scrolling details.
        let (host, _) = harness(width: 420, height: 400)
        defer { host.release() }
        show(presentation(many()), in: host)
        let banner = host.view.findingsBanner
        let button = banner.findingsReportActionButton
        #expect(!banner.isExpanded && banner.detailScrollView.isHidden)
        #expect(button.isDescendant(of: banner) && !button.isDescendant(of: banner.detailScrollView))
        #expect(!button.isHiddenOrHasHiddenAncestor)
    }
}
