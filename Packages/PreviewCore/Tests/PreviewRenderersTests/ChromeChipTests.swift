import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// A stand-in for the hosted views that report copies and speak through the preview's shared announcer.
@MainActor
private final class ChromeFakeReportingView: NSView, PreviewCopyReporting, PreviewAnnouncing {
    var copyHandler: ((PreviewCopyEvent) -> Void)?
    var announcer: PreviewAnnouncer?
}

/// The chip beside the info badge (decision 027, Q-37): "Copied" for a moment after any copy, the temporary zoom level
/// for as long as it applies, one string, one announcement, no motion under Reduce Motion, cancelled by a new
/// generation. No test waits: the scheduler is run by hand.
@Suite("Chrome chip", .serialized)
@MainActor
struct ChromeChipTests {
    private let copied = PreviewStrings.text(.chipCopied)

    private func harness() -> (host: InteractionHarness, scheduler: ManualChromeScheduler) {
        let host = InteractionHarness()
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        return (host, scheduler)
    }

    // MARK: Copied

    @Test func copyAllShowsTheChipAnnouncesOnceAndEndsAfterItsDuration() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation("token = ••••\nplain", redactions: 1))
        #expect(host.view.chip.isHidden)
        #expect(host.press("c", [.command, .shift]))
        #expect(!host.view.chip.isHidden && host.view.chip.text == copied && host.view.chip.spokenText == copied)
        #expect(host.announcements.texts == [copied])
        #expect(scheduler.waiting.count == 1 && scheduler.waiting.first?.delay == PreviewChrome.chipDuration)
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden && host.view.chip.text.isEmpty)
        #expect(host.announcements.texts == [copied])
    }

    @Test func copyConcealedTextReportsThroughTheSamePathWithNoConfirmationOfItsOwn() {
        let (host, _) = harness()
        defer { host.release() }
        host.view.concealedTextPasteboard = host.pasteboard
        let text = "user=demo\npassword=••••\n"
        host.show(plainPresentation(text, format: .markdown, syntax: .markdown, redactions: 1))
        #expect(host.view.findingsBanner.offersConcealedCopy)
        host.announcements.texts.removeAll()
        host.view.findingsBanner.copyActionButton.performClick(nil)
        #expect(host.pasteboard.string(forType: .string) == text)
        #expect(host.announcements.texts == [copied] && host.view.chip.text == copied)
        #expect(descendants(of: NSTextField.self, in: host.view.findingsBanner).filter { $0.stringValue == copied }.isEmpty)
    }

    @Test func theTextViewReportsItsCopiesToThePreview() {
        let (host, _) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        // The text view's own copy (Command-C) writes to the system pasteboard, which a test never touches; the
        // handler it calls is the same one a copy would reach.
        #expect(host.view.textView.copyHandler != nil)
        host.view.textView.copyHandler?(.text)
        #expect(host.view.chip.text == copied && host.announcements.texts == [copied])
    }

    @Test func hostedViewsThatAskForTheServicesGetThem() {
        let (host, _) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        let reporting = ChromeFakeReportingView(frame: .zero)
        host.view.adoptPreviewServices(reporting)
        #expect(reporting.announcer === host.view.announcer)
        reporting.copyHandler?(.rows(3))
        #expect(host.view.chip.text == copied && host.announcements.texts == [copied])
        reporting.copyHandler?(.path)
        #expect(host.announcements.texts == [copied, copied])
        // A view that adopts neither contract is left alone.
        host.view.adoptPreviewServices(NSView(frame: .zero))
    }

    @Test func aNewCopyReplacesTheChipAndRestartsItsLife() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        host.view.reportCopy(.text)
        host.view.reportCopy(.text)
        #expect(scheduler.scheduled.count == 2 && scheduler.scheduled[0].isCancelled && scheduler.waiting.count == 1)
        // Two copies are two announcements: the announcer never collapses repeats.
        #expect(host.announcements.texts == [copied, copied])
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden)
    }

    @Test func aNewGenerationCancelsTheChipAndItsTimer() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        host.view.reportCopy(.text)
        host.show(plainPresentation("the next file"), resetsContentState: true)
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
        // A timer that fires late changes nothing.
        scheduler.scheduled[0].runIgnoringCancellation()
        #expect(host.view.chip.isHidden)
        // A request that starts with the loading state is a new generation too.
        host.view.reportCopy(.text)
        host.view.showLoading()
        #expect(host.view.chip.isHidden && scheduler.scheduled[1].isCancelled)
        #expect(scheduler.waiting.count == 1)
    }

    @Test func aHiddenPreviewKeepsNoConfirmation() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        host.view.reportCopy(.text)
        host.view.suspendResources()
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
    }

    // MARK: Zoom

    @Test func zoomShowsItsLevelInTheChipUntilItIsReset() throws {
        let (host, _) = harness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(10)), typography: PreviewTypography(fontSize: 13))
        #expect(host.view.chip.isHidden && host.view.zoomChip == nil)
        host.press("=", .command)
        let level = try #require(host.view.zoomChip)
        #expect(!host.view.chip.isHidden && host.view.chip.text == level.shown && host.view.chip.spokenText == level.spoken)
        #expect(host.announcements.texts == [host.view.zoomLevelText])
        host.press("=", .command)
        #expect(host.announcements.texts.count == 2 && host.view.chip.text == host.view.zoomChip?.shown)
        host.press("0", .command)
        #expect(host.view.chip.isHidden && host.view.zoomChip == nil)
        // Back at the saved size the announced level is 100 percent.
        #expect(host.announcements.texts.last == host.view.zoomLevelText)
        #expect(host.announcements.texts.count == 3)
    }

    @Test func theCopiedChipTakesTheZoomLevelsPlaceForAMomentAndGivesItBack() throws {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(10)), typography: PreviewTypography(fontSize: 13))
        host.press("=", .command)
        let level = try #require(host.view.zoomChip)
        host.view.reportCopy(.text)
        #expect(host.view.chip.text == copied)
        // The zoom reminder is still part of the status text while the confirmation shows.
        #expect(host.view.displayedStatus.contains(level.spoken))
        scheduler.runWaiting()
        #expect(!host.view.chip.isHidden && host.view.chip.text == level.shown)
    }

    // MARK: Motion

    @Test func theChipFadesInUnlessReduceMotionIsOn() {
        for reduces in [false, true] {
            let (host, _) = harness()
            host.view.chip.reducesMotion = { reduces }
            host.show(plainPresentation("safe words"))
            host.view.reportCopy(.text)
            #expect(!host.view.chip.isHidden, "reduce motion \(reduces)")
            #expect(host.view.chip.changedWithMotion == !reduces, "reduce motion \(reduces)")
            // A chip that only changes its text in place never moves.
            host.view.reportCopy(.text)
            #expect(!host.view.chip.changedWithMotion, "reduce motion \(reduces)")
            host.release()
        }
    }

    @Test func hidingTheChipNeverAnimates() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.show(plainPresentation("safe words"))
        host.view.reportCopy(.text)
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden && !host.view.chip.changedWithMotion && host.view.chip.alphaValue == 1)
    }
}
