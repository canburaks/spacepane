import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewThumbnails

// MARK: Helpers

/// A scheduler whose clock moves only when the test moves it. Nothing in the gate tests waits on real time.
final class ManualThumbnailScheduler: ThumbnailTimerScheduling {
    private struct Entry {
        let id: Int
        let due: Duration
        let action: @Sendable () -> Void
    }

    private struct State {
        var now = Duration.zero
        var nextID = 0
        var entries: [Entry] = []
    }

    private let state = Mutex(State())

    func schedule(after interval: Duration, _ action: @escaping @Sendable () -> Void) -> ThumbnailTimerHandle {
        let id = state.withLock { state -> Int in
            state.nextID += 1
            state.entries.append(Entry(id: state.nextID, due: state.now + interval, action: action))
            return state.nextID
        }
        return ThumbnailTimerHandle { [self] in cancel(id) }
    }

    /// Moves the clock forward and runs every action that has come due, earliest first, outside the lock.
    func advance(by interval: Duration) {
        let due = state.withLock { state -> [Entry] in
            state.now += interval
            let now = state.now
            let ready = state.entries.filter { $0.due <= now }.sorted { $0.due < $1.due }
            state.entries.removeAll { $0.due <= now }
            return ready
        }
        for entry in due { entry.action() }
    }

    /// Timers that have neither fired nor been cancelled.
    var pendingCount: Int { state.withLock { state -> Int in state.entries.count } }

    private func cancel(_ id: Int) {
        state.withLock { state -> Void in
            state.entries.removeAll { $0.id == id }
        }
    }
}

/// Everything a gate delivered, in order.
final class GateDeliveries<Value: Sendable>: Sendable {
    private let values = Mutex([Value]())

    func record(_ value: Value) {
        values.withLock { values -> Void in values.append(value) }
    }

    var all: [Value] { values.withLock { values -> [Value] in values } }
}

// MARK: The gate

@Suite("Thumbnail reply gate")
struct ThumbnailReplyGateTests {
    private func makeGate(scheduler: ManualThumbnailScheduler, deliveries: GateDeliveries<String>,
                          limit: Duration = .seconds(1), onTimeout: @escaping @Sendable () -> Void = {}) -> ThumbnailReplyGate<String> {
        ThumbnailReplyGate<String>(limit: limit, scheduler: scheduler, timeoutValue: "glyph", onTimeout: onTimeout,
                                   deliver: { deliveries.record($0) })
    }

    @Test func theWorkersAnswerIsDeliveredOnceAndTheTimerIsCancelled() {
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<String>()
        let gate = makeGate(scheduler: scheduler, deliveries: deliveries)
        #expect(scheduler.pendingCount == 1, "the deadline is armed as soon as the gate exists")
        #expect(gate.answer("scene"))
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(5))
        #expect(gate.answer("again") == false)
        #expect(deliveries.all == ["scene"])
        #expect(gate.isClosed)
    }

    @Test func theDeadlineDeliversTheTimeoutValueAndALateAnswerIsDropped() {
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<String>()
        let gate = makeGate(scheduler: scheduler, deliveries: deliveries)
        scheduler.advance(by: .milliseconds(999))
        #expect(deliveries.all.isEmpty && !gate.isClosed, "one millisecond before the limit nothing has been answered")
        scheduler.advance(by: .milliseconds(1))
        #expect(deliveries.all == ["glyph"])
        #expect(gate.answer("late") == false)
        scheduler.advance(by: .seconds(10))
        #expect(deliveries.all == ["glyph"])
    }

    @Test func theTimeoutHookRunsOnlyWhenTheDeadlineWins() {
        let timeouts = Counter()
        let scheduler = ManualThumbnailScheduler()
        let answered = makeGate(scheduler: scheduler, deliveries: GateDeliveries<String>(), onTimeout: { timeouts.increment() })
        answered.answer("scene")
        scheduler.advance(by: .seconds(5))
        #expect(timeouts.value == 0)
        let lateScheduler = ManualThumbnailScheduler()
        _ = makeGate(scheduler: lateScheduler, deliveries: GateDeliveries<String>(), onTimeout: { timeouts.increment() })
        lateScheduler.advance(by: .seconds(1))
        #expect(timeouts.value == 1)
    }

    @Test func aDeadlineThatPassesFirstCancelsTheWorkAndItsLateResultIsDropped() async {
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<String>()
        let latch = AdmissionLatch()
        let sawCancellation = Counter()
        let finished = Counter()
        let gate = makeGate(scheduler: scheduler, deliveries: deliveries)
        gate.start {
            await latch.wait()
            if Task.isCancelled { sawCancellation.increment() }
            finished.increment()
            return "scene"
        }
        scheduler.advance(by: .seconds(1))
        #expect(deliveries.all == ["glyph"], "the work has not finished, and the deadline answered for it")
        latch.open()
        #expect(await awaitCondition { finished.value == 1 })
        #expect(sawCancellation.value == 1, "the deadline cancelled the work, so a queued request leaves the queue")
        await letReadyTasksRun()
        #expect(deliveries.all == ["glyph"], "the late result was dropped")
    }

    @Test func aWorkerThatFinishesFirstAnswersAndTheDeadlineIsCancelled() async {
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<String>()
        let gate = makeGate(scheduler: scheduler, deliveries: deliveries)
        gate.start { "scene" }
        #expect(await awaitCondition { deliveries.all == ["scene"] })
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(5))
        #expect(deliveries.all == ["scene"])
    }

    @Test func aWorkerStartedAfterTheGateClosedNeverAnswers() async {
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<String>()
        let finished = Counter()
        let gate = makeGate(scheduler: scheduler, deliveries: deliveries)
        scheduler.advance(by: .seconds(1))
        gate.start {
            finished.increment()
            return "late"
        }
        #expect(await awaitCondition { finished.value == 1 })
        await letReadyTasksRun()
        #expect(deliveries.all == ["glyph"], "the late result was dropped")
    }

    /// The answer and the deadline come from two tasks at once, 200 times over. Either may win; never both, never neither.
    @Test func exactlyOneAnswerIsDeliveredWhateverTheOrder() async {
        let total = 200
        let counts = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for index in 0..<total {
                group.addTask {
                    let scheduler = ManualThumbnailScheduler()
                    let deliveries = GateDeliveries<Int>()
                    let gate = ThumbnailReplyGate<Int>(limit: .seconds(1), scheduler: scheduler, timeoutValue: -1,
                                                       deliver: { deliveries.record($0) })
                    await withTaskGroup(of: Void.self) { race in
                        race.addTask { _ = gate.answer(index) }
                        race.addTask { scheduler.advance(by: .seconds(1)) }
                    }
                    return deliveries.all.count
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == total)
        #expect(counts.allSatisfy { $0 == 1 })
    }

    @Test func aTimerHandleCanBeCancelledTwiceOrAfterItFired() {
        let scheduler = ManualThumbnailScheduler()
        let fired = Counter()
        let handle = scheduler.schedule(after: .seconds(1)) { fired.increment() }
        scheduler.advance(by: .seconds(1))
        handle.cancel()
        handle.cancel()
        #expect(fired.value == 1)
        let cancelled = scheduler.schedule(after: .seconds(1)) { fired.increment() }
        cancelled.cancel()
        cancelled.cancel()
        scheduler.advance(by: .seconds(5))
        #expect(fired.value == 1)
    }
}

// MARK: The Dispatch timer

@Suite("Dispatch thumbnail scheduler")
struct DispatchThumbnailSchedulerTests {
    /// A due timer runs, once, on the queue it was given. Nothing here waits for time to pass: the interval is zero.
    @Test func aDueActionRunsOnceOnTheGivenQueue() async {
        let queue = DispatchQueue(label: "thumbnails.tests.due")
        let scheduler = DispatchThumbnailScheduler(queue: queue)
        let fired = Counter()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = scheduler.schedule(after: .zero) {
                fired.increment()
                continuation.resume()
            }
        }
        #expect(fired.value == 1)
    }

    /// The queue is suspended while the timers are scheduled, so the first one cannot run before it is cancelled.
    /// A second timer on the same serial queue then marks the point by which the first would have run.
    @Test func aCancelledTimerNeverRuns() async {
        let queue = DispatchQueue(label: "thumbnails.tests.cancelled")
        queue.suspend()
        let scheduler = DispatchThumbnailScheduler(queue: queue)
        let cancelledRuns = Counter()
        let handle = scheduler.schedule(after: .zero) { cancelledRuns.increment() }
        handle.cancel()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = scheduler.schedule(after: .zero) { continuation.resume() }
            queue.resume()
        }
        #expect(cancelledRuns.value == 0)
    }
}

// MARK: The gate in front of the service

@Suite("Thumbnail reply gate with the service")
struct ThumbnailReplyGateServiceTests {
    @Test func aRequestQueuedBehindStalledWorkIsAnsweredWithTheBadgedGlyphAtTheDeadline() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let subject = ContentThumbnailService(registrations: StandardFormatAdapters.registrations, preferences: .fixed(.defaults),
                                              limits: relaxedLimits, admission: admission)
        // Stalled work holds the only slot, as a blocked read on a slow volume would.
        let latch = AdmissionLatch()
        let occupier = occupy(admission, until: latch)
        #expect(await awaitCondition { admission.runningCount == 1 })
        let url = try fixture.file("report.final.json", "{\"title\": \"Demo\"}\n")
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<ThumbnailResult>()
        let gate = ThumbnailReplyGate<ThumbnailResult>(
            limit: subject.hardTimeout, scheduler: scheduler,
            timeoutValue: ThumbnailResult(outcome: .generic(.timedOut), badge: subject.badge(for: url)),
            deliver: { deliveries.record($0) })
        gate.start { await subject.result(for: url, geometry: standardGeometry) }
        #expect(await awaitCondition { admission.waitingCount == 1 })
        // The deadline passes while the request still waits for a slot: one answer, the glyph, with the badge.
        scheduler.advance(by: subject.hardTimeout)
        let delivered = deliveries.all
        #expect(delivered.count == 1)
        #expect(delivered.first?.outcome.reason == .timedOut)
        #expect(delivered.first?.badge?.token == "JSON")
        // The deadline cancelled the work, so the request left the queue instead of waiting for a slot it no longer needs.
        #expect(await awaitCondition { admission.waitingCount == 0 })
        latch.open()
        _ = await occupier.value
        #expect(deliveries.all.count == 1)
        #expect(admission.runningCount == 0)
    }

    @Test func aRequestThatFinishesBeforeTheDeadlineDeliversItsPageWithTheBadge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let subject = makeService()
        let url = try fixture.file("notes.txt", "Meeting notes\nbuy milk and eggs\n")
        let scheduler = ManualThumbnailScheduler()
        let deliveries = GateDeliveries<ThumbnailResult>()
        let gate = ThumbnailReplyGate<ThumbnailResult>(
            limit: subject.hardTimeout, scheduler: scheduler,
            timeoutValue: ThumbnailResult(outcome: .generic(.timedOut), badge: subject.badge(for: url)),
            deliver: { deliveries.record($0) })
        gate.start { await subject.result(for: url, geometry: geometry(384)) }
        #expect(await awaitCondition { deliveries.all.count == 1 })
        #expect(deliveries.all.first?.outcome.scene != nil)
        #expect(deliveries.all.first?.badge?.token == "TXT")
        #expect(scheduler.pendingCount == 0, "the answer cancelled the deadline")
        scheduler.advance(by: subject.hardTimeout)
        #expect(deliveries.all.count == 1)
    }
}
