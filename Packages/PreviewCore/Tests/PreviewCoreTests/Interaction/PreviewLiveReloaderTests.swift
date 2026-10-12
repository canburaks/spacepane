import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewCore

/// Counts calls from concurrent closures.
private final class Counter: Sendable {
    private let storage = Mutex(0)
    func next() -> Int { storage.withLock { $0 += 1; return $0 } }
    var value: Int { storage.withLock { $0 } }
}

/// Holds a load until the test lets it finish, to stage out-of-order completion.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// What the host's `apply` callback received, in order.
@MainActor
private final class Applied {
    var results: [LiveReloadResult] = []
    var texts: [String] {
        results.compactMap { result in
            if case .preview(.ready(let presentation), _) = result { return presentation.text }
            return nil
        }
    }
}

private func marker(_ number: Int) -> LiveReloadResult {
    .preview(.ready(TextPresentation(formatID: .plainText, text: "load \(number)", lineCount: 1, byteCount: 6,
                                     encoding: .utf8, redactionCount: 0)), .defaults)
}

extension LiveReload {
    @Suite("Reloader")
    @MainActor
    struct Reloader {
        private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !condition() {
                guard ContinuousClock.now < deadline else { return false }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return true
        }

        @Test func aChangeRunsTheLoadAndAppliesItsResult() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in marker(loads.next()) },
                                               apply: { applied.results.append($0) })
            #expect(reloader.start(watching: file) && reloader.isWatching)
            try overwrite(file, with: "changed\n")
            #expect(await eventually { applied.results.count == 1 })
            #expect(applied.results == [marker(1)])
            await settle()
            #expect(loads.value == 1)
            reloader.stop()
        }

        @Test func aBurstOfChangesIsOneReload() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in marker(loads.next()) },
                                               apply: { applied.results.append($0) })
            reloader.start(watching: file)
            for index in 0..<40 { try append(file, "line \(index)\n") }
            #expect(await eventually { !applied.results.isEmpty })
            await settle(.milliseconds(400))
            #expect(loads.value == 1 && applied.results.count == 1)
            reloader.stop()
        }

        @Test func aSlowReloadThatFinishesAfterANewerOneIsDropped() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let gate = Gate()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in
                let number = loads.next()
                if number == 1 { await gate.wait() }
                return marker(number)
            }, apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try overwrite(file, with: "first\n")
            #expect(await eventually { loads.value == 1 })
            // A second change arrives while the first reload is still reading.
            try overwrite(file, with: "second\n")
            #expect(await eventually { applied.results == [marker(2)] })
            // The first reload now finishes late; it must not replace the newer content.
            await gate.open()
            await settle(.milliseconds(300))
            #expect(applied.results == [marker(2)])
            reloader.stop()
        }

        @Test func stoppingAbandonsAReloadInFlightAndReleasesTheDescriptor() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let gate = Gate()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in
                _ = loads.next()
                await gate.wait()
                return marker(1)
            }, apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try overwrite(file, with: "first\n")
            #expect(await eventually { loads.value == 1 })
            reloader.stop()
            #expect(!reloader.isWatching)
            await gate.open()
            await settle(.milliseconds(200))
            #expect(applied.results.isEmpty)
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
            // Changes after stopping start nothing.
            try overwrite(file, with: "later\n")
            await settle(.milliseconds(300))
            #expect(loads.value == 1 && applied.results.isEmpty)
        }

        @Test func movingToAnotherFileDropsTheEarlierWatchAndItsLateResult() async throws {
            let scratch = try ScratchDirectory()
            let first = try scratch.file("first.txt")
            let second = try scratch.file("second.txt")
            let applied = Applied()
            let loads = Counter()
            let gate = Gate()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { url in
                let number = loads.next()
                if url.lastPathComponent == "first.txt" { await gate.wait() }
                return marker(number * 100 + (url.lastPathComponent == "first.txt" ? 1 : 2))
            }, apply: { applied.results.append($0) })
            reloader.start(watching: first)
            try overwrite(first, with: "edit\n")
            #expect(await eventually { loads.value == 1 })
            reloader.start(watching: second)
            await gate.open()
            await settle(.milliseconds(200))
            #expect(applied.results.isEmpty)
            // The old file no longer triggers anything; the new one does.
            try overwrite(first, with: "edit again\n")
            await settle(.milliseconds(300))
            #expect(loads.value == 1)
            try overwrite(second, with: "edit\n")
            #expect(await eventually { applied.results.count == 1 })
            #expect(applied.results == [marker(202)])
            reloader.stop()
        }

        @Test func aDeletedFileIsReloadedOnceToItsFinalStateAndWatchingEnds() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { url in
                .preview(await pipeline.preview(url: url, preferences: .defaults), .defaults)
            }, apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try FileManager.default.removeItem(at: file)
            #expect(await eventually { applied.results.count == 1 })
            guard case .preview(let outcome, _) = applied.results[0] else {
                Issue.record("Expected a preview result")
                return
            }
            #expect(outcome == .unavailable(.missingFile))
            #expect(!reloader.isWatching)
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
        }

        @Test func theRealPipelineShowsEditsAndAtomicSavesAsNewContent() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file("data.json", contents: #"{"version":1}"#)
            let applied = Applied()
            let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { url in
                .preview(await pipeline.preview(url: url, preferences: .defaults), .defaults)
            }, apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try overwrite(file, with: #"{"version":2}"#)
            #expect(await eventually { applied.texts.last?.contains("2") == true })
            try #"{"version":3}"#.write(to: file, atomically: true, encoding: .utf8)
            #expect(await eventually { applied.texts.last?.contains("3") == true })
            try overwrite(file, with: #"{"version":4}"#)
            #expect(await eventually { applied.texts.last?.contains("4") == true })
            reloader.stop()
        }

        @Test func turningReloadingOffStopsTheWatchAfterTheNextChange() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in
                _ = loads.next()
                return .disabled
            }, apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try overwrite(file, with: "changed\n")
            #expect(await eventually { applied.results == [.disabled] })
            #expect(!reloader.isWatching)
            try overwrite(file, with: "again\n")
            await settle(.milliseconds(300))
            #expect(loads.value == 1)
        }

        @Test func unreadableSettingsStopTheWatchAndAreReportedToTheHost() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in .settingsUnavailable },
                                               apply: { applied.results.append($0) })
            reloader.start(watching: file)
            try overwrite(file, with: "changed\n")
            #expect(await eventually { applied.results == [.settingsUnavailable] })
            #expect(!reloader.isWatching)
        }

        @Test func anItemThatCannotBeWatchedLeavesNothingRunning() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in .disabled }, apply: { _ in })
            #expect(!reloader.start(watching: scratch.url.appendingPathComponent("missing.txt")))
            #expect(!reloader.isWatching)
            reloader.reloadNow()
            #expect(PreviewSourceMonitor.openDescriptorCount == baseline)
        }

        @Test func reloadNowRereadsWithoutAChangeAndOnlyWhileWatching() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let applied = Applied()
            let loads = Counter()
            let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in marker(loads.next()) },
                                               apply: { applied.results.append($0) })
            reloader.reloadNow()
            await settle(.milliseconds(100))
            #expect(loads.value == 0)
            reloader.start(watching: file)
            reloader.reloadNow()
            #expect(await eventually { applied.results == [marker(1)] })
            reloader.stop()
            reloader.reloadNow()
            await settle(.milliseconds(100))
            #expect(loads.value == 1)
        }

        @Test func onlyOutcomesACureCanChangeAreWatched() {
            let presentation = TextPresentation(formatID: .plainText, text: "x", lineCount: 1, byteCount: 1,
                                                encoding: .utf8, redactionCount: 0)
            #expect(PreviewLiveReloader.watches(.ready(presentation)))
            for failure in [PreviewFailure.inputTooLarge, .unreadableFile, .malformedDocument, .binaryContent, .deadlineExceeded] {
                #expect(PreviewLiveReloader.watches(.unavailable(failure)))
            }
            #expect(!PreviewLiveReloader.watches(.unavailable(.missingFile)))
            #expect(!PreviewLiveReloader.watches(.unavailable(.unsupportedFormat)))
            #expect(!PreviewLiveReloader.watches(.disabledByUser(.json)))
            #expect(!PreviewLiveReloader.watches(.cancelled))
        }

        @Test func droppingTheReloaderStopsItsMonitor() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            do {
                let reloader = PreviewLiveReloader(timing: quickTiming, load: { _ in .disabled }, apply: { _ in })
                reloader.start(watching: file)
                #expect(PreviewSourceMonitor.openDescriptorCount == baseline + 1)
            }
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
        }
    }
}
