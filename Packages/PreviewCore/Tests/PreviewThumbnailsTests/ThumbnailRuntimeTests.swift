import Foundation
import Testing
import PreviewContracts
import PreviewPreferences
@testable import PreviewThumbnails

@Suite("Thumbnail limits")
struct ThumbnailLimitsTests {
    @Test func defaultBudgetsAreValidAndStrict() {
        let limits = ThumbnailLimits.standard
        #expect(limits.textBudget.isValid && limits.databaseBudget.isValid)
        #expect(limits.textBudget.maxInputBytes == 262_144)
        #expect(limits.textBudget.maxMilliseconds == 300)
        #expect(limits.textBudget.maxInputBytes < PreviewBudget.standard.maxInputBytes)
        #expect(limits.hardTimeout > .milliseconds(300) && limits.hardTimeout <= .seconds(2))
        #expect(limits.maximumConcealedValues == 0)
        #expect(limits.maximumImagePixels <= 16_000_000)
    }

    @Test func databasesGetTheirOwnBudget() {
        let limits = ThumbnailLimits.standard
        #expect(limits.budget(for: .sqlite) == limits.databaseBudget)
        #expect(limits.budget(for: .json) == limits.textBudget)
        #expect(limits.databaseBudget.maxInputBytes > limits.textBudget.maxInputBytes)
    }
}

@Suite("Thumbnail race")
struct ThumbnailRaceTests {
    @Test func theWorkerWinsWhenItIsFast() async {
        let result = await ThumbnailRace.run(limit: .seconds(5), onTimeout: "timeout", onCancel: "cancel") { "done" }
        #expect(result == "done")
    }



    @Test func aTaskCancelledBeforeItStartsStillResolvesOnce() async {
        let task = Task { () -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return await ThumbnailRace.run(limit: .seconds(30), onTimeout: "timeout", onCancel: "cancel") {
                try? await Task.sleep(for: .seconds(30))
                return "late"
            }
        }
        #expect(await task.value == "cancel")
    }


    @Test func manyConcurrentRacesEachResolveExactlyOnce() async {
        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for index in 0..<200 {
                group.addTask {
                    // Even indices race a 1 ms timer against 1 ms of work, so either side can win;
                    // odd indices finish at once. A second resume would trap in the checked continuation.
                    await ThumbnailRace.run(limit: .milliseconds(index.isMultiple(of: 2) ? 1 : 500), onTimeout: -1, onCancel: -2) {
                        if index.isMultiple(of: 2) { try? await Task.sleep(for: .milliseconds(1)) }
                        return index
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 200)
        #expect(results.allSatisfy { $0 == -1 || $0 >= 0 })
        #expect(results.filter { $0 >= 0 && !$0.isMultiple(of: 2) }.count == 100)
    }
}

@Suite("Thumbnail preferences source")
struct ThumbnailPreferencesSourceTests {
    @Test func noContainerMeansNoSettings() async {
        #expect(await ThumbnailPreferencesSource.appGroup(snapshotURL: nil).load() == nil)
        #expect(await ThumbnailPreferencesSource.fixed(nil).load() == nil)
    }

    @Test func aMissingDocumentIsFirstRunAndYieldsDefaults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let loaded = await ThumbnailPreferencesSource.appGroup(snapshotURL: fixture.directory.appendingPathComponent("preferences.json")).load()
        #expect(loaded == .defaults)
        #expect(loaded?.showsContentThumbnails == true)
    }

    @Test func aSavedSnapshotKeepsFileTypeChoices() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("preferences.json")
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setEnabled(false, for: .csv)
        try await PreferenceStore(url: url).save(snapshot)
        let loaded = await ThumbnailPreferencesSource.appGroup(snapshotURL: url).load()
        #expect(loaded?.isEnabled(.csv) == false)
        #expect(loaded?.isEnabled(.json) == true)
    }

    @Test func corruptOrUnsupportedDocumentsNeverGuess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = try fixture.file("corrupt.json", "{ not json")
        #expect(await ThumbnailPreferencesSource.appGroup(snapshotURL: corrupt).load() == nil)
        let future = try fixture.file("future.json", #"{"schemaVersion":999}"#)
        #expect(await ThumbnailPreferencesSource.appGroup(snapshotURL: future).load() == nil)
        let oversized = try fixture.file("big.json", String(repeating: "x", count: 200_000))
        #expect(await ThumbnailPreferencesSource.appGroup(snapshotURL: oversized).load() == nil)
    }

    @Test func aDirectoryInPlaceOfTheDocumentIsUnreadable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = fixture.directory.appendingPathComponent("preferences.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(await ThumbnailPreferencesSource.appGroup(snapshotURL: directory).load() == nil)
    }
}

@Suite("Thumbnail wall-clock liveness", .serialized)
struct ThumbnailWallClockTests {
    @Test func theTimerWinsAndTheWorkerIsCancelled() async {
        let observedCancellation = Counter()
        let clock = ContinuousClock()
        let start = clock.now
        let result = await ThumbnailRace.run(limit: .milliseconds(100), onTimeout: "timeout", onCancel: "cancel") {
            do { try await Task.sleep(for: .seconds(60)) } catch { observedCancellation.increment() }
            return "late"
        }
        #expect(result == "timeout")
        // Far below the worker's 60 s, with headroom for a heavily loaded parallel test run.
        #expect(clock.now - start < .seconds(20))
        for _ in 0..<100 where observedCancellation.value == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(observedCancellation.value == 1)
    }

    @Test func anOuterCancellationResolvesPromptly() async {
        let clock = ContinuousClock()
        let task = Task { await ThumbnailRace.run(limit: .seconds(30), onTimeout: "timeout", onCancel: "cancel") {
            try? await Task.sleep(for: .seconds(30))
            return "late"
        } }
        try? await Task.sleep(for: .milliseconds(50))
        let start = clock.now
        task.cancel()
        #expect(await task.value == "cancel")
        #expect(clock.now - start < .seconds(3))
    }

    @Test func aBlockedWorkerDoesNotDelayTheResult() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await ThumbnailRace.run(limit: .milliseconds(100), onTimeout: "timeout", onCancel: "cancel") {
            // Non-cooperative: it never checks cancellation.
            blockThread(6)
            return "late"
        }
        #expect(result == "timeout")
        // Well below the 6 s the worker blocks, with headroom for a loaded parallel test run.
        #expect(clock.now - start < .seconds(4))
    }
}
