import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 deterministic reload generations and lifetime")
@MainActor
struct Q153ReloaderControlTests {
    @Test func lateRefusalFromEarlierReloadCannotStopNewerGeneration() async throws {
        let watch = Q153Watch(), gate = Q153ReloadGate(), applies = Q153ReloadApplies()
        let reloader = PreviewLiveReloader(load: { _ in await gate.load() }, apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        reloader.reloadNow()
        var starts = gate.starts.makeAsyncIterator()
        #expect(await starts.next() == 1)
        let old = try #require(reloader.pendingReloadCompletion())
        reloader.reloadNow()
        #expect(await starts.next() == 2)
        let current = try #require(reloader.pendingReloadCompletion()), newer = q153ReloadMarker("newer")
        await gate.release(2, newer); await current.value
        await gate.release(1, .preview(.unavailable(.unavailableContent), .defaults)); await old.value
        #expect(applies.results == [newer] && applies.watchingAtApply == [true])
        let calls = await gate.calls
        #expect(reloader.isWatching && watch.stopCount == 0 && calls == 2)
    }

    @Test func replacingWatchDropsLateOldResultAndRetainsOnlyNewWatch() async throws {
        let first = Q153Watch(), second = Q153Watch(), sequence = Q153WatchSequence([first, second])
        let gate = Q153ReloadGate(), applies = Q153ReloadApplies()
        let reloader = PreviewLiveReloader(load: { _ in await gate.load() }, apply: { applies.apply($0) }, monitorFactory: { _, _ in sequence.make() })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/first.txt")))
        reloader.reloadNow()
        var starts = gate.starts.makeAsyncIterator(); #expect(await starts.next() == 1)
        let old = try #require(reloader.pendingReloadCompletion())
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/second.txt")))
        #expect(first.stopCount == 1 && second.stopCount == 0)
        reloader.reloadNow(); #expect(await starts.next() == 2)
        let current = try #require(reloader.pendingReloadCompletion()), newer = q153ReloadMarker("replacement")
        await gate.release(2, newer); await current.value
        await gate.release(1, .preview(.unavailable(.unavailableContent), .defaults)); await old.value
        #expect(applies.results == [newer] && reloader.isWatching && second.stopCount == 0)
    }

    @Test func stopDropsSuspendedCompletionAndReleasesReloaderLifetime() async throws {
        let watch = Q153Watch(), gate = Q153ReloadGate(), applies = Q153ReloadApplies()
        var reloader: PreviewLiveReloader? = PreviewLiveReloader(load: { _ in await gate.load() },
            apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader
        weak var weakReloader = reloader
        #expect(reloader?.start(watching: URL(fileURLWithPath: "/unused/owned.txt")) == true)
        reloader?.reloadNow()
        var starts = gate.starts.makeAsyncIterator(); #expect(await starts.next() == 1)
        let old = try #require(reloader?.pendingReloadCompletion())
        reloader?.stop()
        await gate.release(1, q153ReloadMarker("late")); await old.value
        #expect(applies.results.isEmpty && watch.stopCount == 1 && reloader?.isWatching == false)
        reloader?.reloadNow(); #expect(reloader?.pendingReloadCompletion() == nil)
        reloader = nil
        #expect(weakReloader == nil)
    }

    @Test func failedFactoryStartsNoReloadAndRetainsNoWatch() async {
        let loads = Mutex(0), applies = Q153ReloadApplies()
        let reloader = PreviewLiveReloader(load: { _ in loads.withLock { $0 += 1 }; return q153ReloadMarker("unused") },
            apply: { applies.apply($0) }, monitorFactory: { _, _ in nil })
        #expect(!reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        reloader.reloadNow()
        #expect(!reloader.isWatching && reloader.pendingReloadCompletion() == nil)
        #expect(loads.withLock { $0 } == 0 && applies.results.isEmpty)
    }

    @Test func watchableCureKeepsWatchAndAllowsExplicitReloadNow() async throws {
        let watch = Q153Watch(), applies = Q153ReloadApplies(), value = LiveReloadResult.preview(.unavailable(.unreadableFile), .defaults)
        let reloader = PreviewLiveReloader(load: { _ in value }, apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        for _ in 0..<2 {
            reloader.reloadNow()
            let completion = try #require(reloader.pendingReloadCompletion()); await completion.value
        }
        #expect(applies.results == [value, value] && applies.watchingAtApply == [true, true])
        #expect(reloader.isWatching && watch.stopCount == 0)
    }

    @Test(arguments: [LiveReloadResult.settingsUnavailable, .disabled])
    func settingsAndReloadSwitchStillReleaseBeforeApply(result: LiveReloadResult) async throws {
        let watch = Q153Watch(), applies = Q153ReloadApplies()
        let reloader = PreviewLiveReloader(load: { _ in result }, apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        reloader.reloadNow()
        let completion = try #require(reloader.pendingReloadCompletion()); await completion.value
        #expect(applies.results == [result] && applies.watchingAtApply == [false] && watch.stopCount == 1)
        #expect(!reloader.isWatching)
    }

    @Test(arguments: [PreviewSourceMonitor.Event.removed, .revoked])
    func terminalMonitorEventStillAppliesOneFinalResultAndStops(event: PreviewSourceMonitor.Event) async {
        let watch = Q153Watch(), applies = Q153ReloadApplies(), value = q153ReloadMarker("final")
        let reloader = PreviewLiveReloader(load: { _ in value }, apply: { applies.apply($0) }, monitorFactory: { _, _ in watch })
        applies.reloader = reloader; defer { reloader.stop() }
        #expect(reloader.start(watching: URL(fileURLWithPath: "/unused/owned.txt")))
        watch.emit(event)
        var replies = applies.values.makeAsyncIterator(); #expect(await replies.next() == value)
        #expect(!reloader.isWatching && watch.stopCount == 1 && applies.watchingAtApply == [false])
        reloader.reloadNow(); #expect(reloader.pendingReloadCompletion() == nil)
    }
}
