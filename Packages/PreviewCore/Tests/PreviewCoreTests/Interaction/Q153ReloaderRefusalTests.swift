import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 live reload refusal")
@MainActor
struct Q153ReloaderRefusalTests {
    @Test func unavailableBytesAreNotEligibleForWatching() {
        #expect(!PreviewLiveReloader.watches(.unavailable(.unavailableContent)))
        for failure in [PreviewFailure.unreadableFile, .inputTooLarge, .malformedDocument, .binaryContent, .deadlineExceeded] {
            #expect(PreviewLiveReloader.watches(.unavailable(failure)))
        }
    }

    @Test(arguments: [false, true])
    func refusalReleasesWatchBeforeApplyingEitherResultForm(resultBearing: Bool) async {
        let watch = Q153Watch(), sequence = Q153WatchSequence([watch]), applies = Q153ReloadApplies(), loads = Mutex(0)
        let value: LiveReloadResult = resultBearing
            ? .result(PreviewResult(outcome: .unavailable(.unavailableContent), effectiveBudget: .standard), .defaults)
            : .preview(.unavailable(.unavailableContent), .defaults)
        let reloader = PreviewLiveReloader(load: { _ in loads.withLock { $0 += 1 }; return value },
            apply: { applies.apply($0) }, monitorFactory: { _, _ in sequence.make() })
        applies.reloader = reloader
        defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        watch.emit(.modified)
        var replies = applies.values.makeAsyncIterator()
        #expect(await replies.next() == value)
        #expect(!reloader.isWatching && watch.stopCount == 1 && applies.watchingAtApply == [false])
        reloader.reloadNow()
        let attempted = reloader.pendingReloadCompletion()
        #expect(attempted == nil)
        await attempted?.value // RED's unwanted reload also completes before cleanup/assertions.
        #expect(loads.withLock { $0 } == 1 && applies.results == [value])
    }

    @Test(arguments: [PreviewOutcome.unavailable(.missingFile), .unavailable(.unsupportedFormat), .disabledByUser(.json), .cancelled])
    func otherNonWatchableOutcomesAlsoEndTheWatch(outcome: PreviewOutcome) async {
        let watch = Q153Watch(), applies = Q153ReloadApplies()
        let value = LiveReloadResult.preview(outcome, .defaults)
        let reloader = PreviewLiveReloader(load: { _ in value }, apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        reloader.reloadNow()
        let completion = reloader.pendingReloadCompletion()
        await completion?.value
        #expect(applies.results == [value] && applies.watchingAtApply == [false])
        #expect(!reloader.isWatching && watch.stopCount == 1)
    }
}
