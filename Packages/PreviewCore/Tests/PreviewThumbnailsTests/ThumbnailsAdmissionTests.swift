import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewThumbnails

// MARK: Helpers

/// Parks tasks until it is opened; a task that arrives after it opened passes at once. It holds no thread, so a
/// test keeps admitted work in flight without letting any time pass.
final class AdmissionLatch: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passesAtOnce = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.waiters.append(continuation)
                return false
            }
            if passesAtOnce { continuation.resume() }
        }
    }

    func open() {
        let released = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in released { waiter.resume() }
    }
}

/// The order in which things happened.
final class AdmissionLog: Sendable {
    private let entries = Mutex([Int]())

    func append(_ value: Int) {
        entries.withLock { entries -> Void in entries.append(value) }
    }

    var values: [Int] { entries.withLock { entries -> [Int] in entries } }
}

/// How many pieces of work are inside the admission now, and the most that ever were.
final class AdmissionProbe: Sendable {
    private struct Counts {
        var current = 0
        var maximum = 0
    }

    private let counts = Mutex(Counts())

    func enter() {
        counts.withLock { counts -> Void in
            counts.current += 1
            counts.maximum = max(counts.maximum, counts.current)
        }
    }

    func leave() {
        counts.withLock { counts -> Void in counts.current -= 1 }
    }

    var current: Int { counts.withLock { counts -> Int in counts.current } }
    var maximum: Int { counts.withLock { counts -> Int in counts.maximum } }
}

/// Waits for `condition` by yielding, never by sleeping. A condition that does not come true fails the test after a
/// bounded number of turns instead of hanging it; the bound is generous because a loaded machine starts the tasks
/// that make the condition true late, and a condition that holds returns at once.
func awaitCondition(turns: Int = 2_000_000, _ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<turns {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// Lets the tasks that are ready run before the caller looks again, without sleeping. A wrong late answer is not
/// observable as an event, so a test that asserts "nothing more happened" gives it these turns to show itself first.
func letReadyTasksRun(turns: Int = 2_000) async {
    for _ in 0..<turns { await Task.yield() }
}

/// Holds a slot of the admission until the latch opens, as a stalled read on a slow volume would.
func occupy(_ admission: ThumbnailAdmission, until latch: AdmissionLatch) -> Task<Int, Never> {
    Task {
        await admission.run(ifCancelled: -1) { () async -> Int in
            await latch.wait()
            return 0
        }
    }
}

// MARK: The admission

@Suite("Thumbnail admission")
struct ThumbnailAdmissionTests {
    @Test func theWidthIsHalfTheProcessorsAndAtLeastOne() {
        #expect(ThumbnailAdmission.width(forProcessorCount: -4) == 1)
        #expect(ThumbnailAdmission.width(forProcessorCount: 0) == 1)
        #expect(ThumbnailAdmission.width(forProcessorCount: 1) == 1)
        #expect(ThumbnailAdmission.width(forProcessorCount: 2) == 1)
        #expect(ThumbnailAdmission.width(forProcessorCount: 3) == 1)
        #expect(ThumbnailAdmission.width(forProcessorCount: 4) == 2)
        #expect(ThumbnailAdmission.width(forProcessorCount: 10) == 5)
        #expect(ThumbnailAdmission.width(forProcessorCount: 18) == 9)
        #expect(ThumbnailAdmission().maximumConcurrent
                == ThumbnailAdmission.width(forProcessorCount: ProcessInfo.processInfo.activeProcessorCount))
        #expect(ThumbnailAdmission(maximumConcurrent: 0).maximumConcurrent == 1)
        #expect(ThumbnailAdmission(maximumConcurrent: 7).maximumConcurrent == 7)
    }

    @Test func waitingWorkRunsInArrivalOrder() async {
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let latch = AdmissionLatch()
        let started = AdmissionLog()
        // The first request takes the only slot and keeps it until the latch opens.
        let running = Task {
            await admission.run(ifCancelled: -1) { () async -> Int in
                started.append(0)
                await latch.wait()
                return 0
            }
        }
        #expect(await awaitCondition { admission.runningCount == 1 })
        var waiting: [Task<Int, Never>] = []
        for index in 1...3 {
            waiting.append(Task {
                await admission.run(ifCancelled: -1) { () async -> Int in
                    started.append(index)
                    return index
                }
            })
            // Each request is queued before the next one is created, so arrival order is known.
            #expect(await awaitCondition { admission.waitingCount == index })
        }
        latch.open()
        #expect(await running.value == 0)
        var results: [Int] = []
        for task in waiting { results.append(await task.value) }
        #expect(results == [1, 2, 3])
        #expect(started.values == [0, 1, 2, 3])
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func aCancelledWaiterLeavesTheQueueAndNeverRuns() async {
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let latch = AdmissionLatch()
        let started = AdmissionLog()
        let running = Task {
            await admission.run(ifCancelled: -1) { () async -> Int in
                started.append(0)
                await latch.wait()
                return 0
            }
        }
        #expect(await awaitCondition { admission.runningCount == 1 })
        let doomed = Task {
            await admission.run(ifCancelled: -1) { () async -> Int in
                started.append(1)
                return 1
            }
        }
        #expect(await awaitCondition { admission.waitingCount == 1 })
        let patient = Task {
            await admission.run(ifCancelled: -1) { () async -> Int in
                started.append(2)
                return 2
            }
        }
        #expect(await awaitCondition { admission.waitingCount == 2 })
        doomed.cancel()
        // The refusal is the answer, and the place in the queue is gone before it arrives.
        #expect(await doomed.value == -1)
        #expect(admission.waitingCount == 1)
        latch.open()
        #expect(await running.value == 0)
        #expect(await patient.value == 2)
        #expect(started.values == [0, 2])
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func aRequestCancelledBeforeItStartsNeverRunsEvenWithAFreeSlot() async {
        let admission = ThumbnailAdmission(maximumConcurrent: 4)
        let started = AdmissionLog()
        let task = Task { () -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return await admission.run(ifCancelled: -1) { () async -> Int in
                started.append(9)
                return 9
            }
        }
        #expect(await task.value == -1)
        #expect(started.values.isEmpty)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test(arguments: [1, 2, 3])
    func neverMoreThanTheWidthRunAtOnce(width: Int) async {
        let total = 12
        let admission = ThumbnailAdmission(maximumConcurrent: width)
        let probe = AdmissionProbe()
        let latch = AdmissionLatch()
        let tasks = (0..<total).map { index in
            Task {
                await admission.run(ifCancelled: -1) { () async -> Int in
                    probe.enter()
                    await latch.wait()
                    probe.leave()
                    return index
                }
            }
        }
        // Every request has arrived: `width` of them hold a slot and the rest are queued behind them.
        #expect(await awaitCondition { admission.runningCount == width && admission.waitingCount == total - width })
        #expect(await awaitCondition { probe.current == width })
        latch.open()
        var finished = 0
        for task in tasks {
            let answer = await task.value
            if answer >= 0 { finished += 1 }
        }
        #expect(finished == total)
        #expect(probe.maximum == width)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    /// Grants and cancellations arrive in every order here. Whatever happens, every request is answered, a request
    /// that was never cancelled ran, none ran twice, and the slots are all given back.
    @Test func cancellationsRacingGrantsNeverLoseASlotOrStrandAWaiter() async {
        let total = 120
        let admission = ThumbnailAdmission(maximumConcurrent: 2)
        let ran = AdmissionLog()
        let completed = Counter()
        let tasks = (0..<total).map { index in
            Task { () -> Int in
                let answer = await admission.run(ifCancelled: -1) { () async -> Int in
                    ran.append(index)
                    await Task.yield()
                    return index
                }
                completed.increment()
                return answer
            }
        }
        for (index, task) in tasks.enumerated() where index.isMultiple(of: 3) { task.cancel() }
        let allAnswered = await awaitCondition(turns: 5_000_000) { completed.value == total }
        // A stranded waiter would leave this unmet; cancelling the rest keeps the failure from hanging the run.
        if !allAnswered { for task in tasks { task.cancel() } }
        #expect(allAnswered, "every request is answered, cancelled or not")
        guard allAnswered else { return }
        var answers: [Int] = []
        for task in tasks { answers.append(await task.value) }
        for index in 0..<total where !index.isMultiple(of: 3) { #expect(answers[index] == index, "request \(index) was never cancelled") }
        #expect(Set(ran.values).count == ran.values.count, "no request ran twice")
        #expect(answers.filter { $0 >= 0 }.count == ran.values.count, "a request ran exactly when it was not refused")
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }
}

// MARK: The admission inside the service

@Suite("Thumbnail admission in the service")
struct ThumbnailAdmissionServiceTests {
    private func makeAdmittingService(admission: ThumbnailAdmission, reads: Counter) -> ContentThumbnailService {
        ContentThumbnailService(registrations: StandardFormatAdapters.registrations, preferences: .fixed(.defaults),
                                reader: SpyReader(reads: reads), limits: relaxedLimits, admission: admission)
    }

    @Test func requestsWaitForASlotWithoutReadingAndAnswerOnceItIsFree() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let reads = Counter()
        let subject = makeAdmittingService(admission: admission, reads: reads)
        // Something else holds the only slot, so the requests below must queue behind it.
        let latch = AdmissionLatch()
        let occupier = occupy(admission, until: latch)
        #expect(await awaitCondition { admission.runningCount == 1 })
        let urls = try (0..<3).map { try fixture.file("note\($0).txt", "note number \($0)\n") }
        let requests = urls.map { url in Task { await subject.outcome(for: url, geometry: standardGeometry) } }
        #expect(await awaitCondition { admission.waitingCount == 3 })
        #expect(reads.value == 0, "a waiting request has not touched the file")
        latch.open()
        _ = await occupier.value
        for request in requests { #expect(await request.value.scene != nil) }
        #expect(reads.value == 3)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func aCancelledRequestLeavesTheQueueWithoutReadingTheFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let reads = Counter()
        let subject = makeAdmittingService(admission: admission, reads: reads)
        let latch = AdmissionLatch()
        let occupier = occupy(admission, until: latch)
        #expect(await awaitCondition { admission.runningCount == 1 })
        let url = try fixture.file("note.txt", "note\n")
        let request = Task { await subject.outcome(for: url, geometry: standardGeometry) }
        #expect(await awaitCondition { admission.waitingCount == 1 })
        request.cancel()
        #expect(await request.value.reason == .cancelled)
        // The race answers first and cancels the worker, which then leaves the queue.
        #expect(await awaitCondition { admission.waitingCount == 0 })
        #expect(reads.value == 0)
        latch.open()
        _ = await occupier.value
        #expect(admission.runningCount == 0)
    }

    @Test func policyDecisionsAnswerAtOnceWhileEverySlotIsTaken() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let reads = Counter()
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setEnabled(false, for: .json)
        let subject = ContentThumbnailService(registrations: StandardFormatAdapters.registrations, preferences: .fixed(snapshot),
                                              reader: SpyReader(reads: reads), limits: relaxedLimits, admission: admission)
        let latch = AdmissionLatch()
        let occupier = occupy(admission, until: latch)
        #expect(await awaitCondition { admission.runningCount == 1 })
        let disabled = try fixture.file("data.json", "{\"a\": 1}")
        let archive = try fixture.file("bundle.tar", Data(count: 1_024))
        // Neither request reads the file, so neither needs a slot: both are answered while the slot stays taken.
        #expect(await subject.outcome(for: disabled, geometry: standardGeometry).reason == .disabledByUser)
        #expect(await subject.outcome(for: archive, geometry: standardGeometry).reason == .genericPolicy)
        #expect(admission.waitingCount == 0 && admission.runningCount == 1)
        #expect(reads.value == 0)
        latch.open()
        _ = await occupier.value
    }
}
