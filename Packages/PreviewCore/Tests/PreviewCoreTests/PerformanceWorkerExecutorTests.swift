import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

/// Decision 027, Q-40: a pipeline's blocking reads and parses run on its own `PreviewWorkerExecutor`, a dispatch
/// serial queue, not on a thread of the cooperative pool.
///
/// Nothing here sleeps, polls, yields in a loop, reads a clock for an assertion or counts cores. A body that must block
/// waits on a condition that another body or the test signals, so it holds a thread of its own queue and never a pool
/// thread; the test learns that a body started from a stream the body writes to. A failsafe of two minutes frees a
/// body whose partner never came and marks its gate expired, so a regression fails a test instead of hanging the run;
/// no passing run reaches it. Requests carry the largest budget there is, because a request's deadline runs while its
/// read is blocked and a loaded three-core runner can delay a task for many seconds: the default two seconds failed
/// three tests of the first hosted run, with the right behaviour, once other suites had held the pool for 25 seconds.
@Suite("Preview worker executor")
struct PerformanceWorkerExecutorTests {
    // MARK: Actors on a PreviewWorkerExecutor, written the way the pipeline's worker is

    @Test func actorsSharingOneExecutorNeverRunTogether() async {
        let executor = PreviewWorkerExecutor(label: "PerformanceTests.Shared")
        let probes = [ExecutorProbe(executor: executor), ExecutorProbe(executor: executor)]
        let overlap = ExecutorOverlap()
        await withTaskGroup(of: Void.self) { group in
            for caller in 0..<8 {
                group.addTask {
                    for step in 0..<25 { await probes[(caller + step) % 2].measure(overlap) }
                }
            }
        }
        #expect(overlap.entered == 200)
        #expect(overlap.maximum == 1, "Two bodies ran at once on one serial executor")
    }

    @Test func actorsOnSeparateExecutorsRunAtTheSameTime() async {
        let barrier = ExecutorBarrier(parties: 2)
        let first = ExecutorProbe(executor: PreviewWorkerExecutor(label: "PerformanceTests.First"))
        let second = ExecutorProbe(executor: PreviewWorkerExecutor(label: "PerformanceTests.Second"))
        // Each body blocks until the other one is running too, so both must hold a thread at the same moment.
        let met = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { await first.rendezvous(barrier) }
            group.addTask { await second.rendezvous(barrier) }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(met == [true, true], "Each body had to be running while the other was still blocked")
        #expect(!barrier.timedOut)
    }

    // MARK: Through the pipeline

    @Test func theWorkerReadsParsesAndFiltersOnTheQueueItWasGiven() async {
        let marker = QueueMarker()
        let queue = DispatchSerialQueue(label: "PerformanceTests.Marked")
        marker.mark(queue, as: "marked")
        let givenLog = ExecutorLog()
        let given = ObservingStages(marker: marker, log: givenLog)
        let pipeline = makePipeline(reader: given, adapter: given, privacy: given, executor: PreviewWorkerExecutor(queue: queue))
        guard case .ready = await pipeline.preview(url: unusedURL("given"), budget: roomyBudget) else {
            Issue.record("The request on the given queue must finish normally")
            return
        }
        // Only a body running on that queue can read its mark: not a cooperative-pool thread, not the main thread.
        #expect(givenLog.values == ["read marked", "parse marked", "filter marked"])
        // The control: a pipeline with the default executor works on a queue of its own, which carries no mark.
        let ownLog = ExecutorLog()
        let own = ObservingStages(marker: marker, log: ownLog)
        let control = makePipeline(reader: own, adapter: own, privacy: own)
        guard case .ready = await control.preview(url: unusedURL("control"), budget: roomyBudget) else {
            Issue.record("The request on the default queue must finish normally")
            return
        }
        #expect(ownLog.values == ["read other", "parse other", "filter other"])
    }

    @Test func pipelinesHandedOneExecutorNeverRunTogether() async {
        let executor = PreviewWorkerExecutor(label: "PerformanceTests.PipelineShared")
        let overlap = ExecutorOverlap()
        let pipelines = [makePipeline(reader: OverlapReader(overlap: overlap), executor: executor),
                         makePipeline(reader: OverlapReader(overlap: overlap), executor: executor)]
        let finished = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for caller in 0..<6 {
                group.addTask {
                    var ready = 0
                    for step in 0..<10 {
                        let outcome = await pipelines[(caller + step) % 2]
                            .preview(url: unusedURL("request-\(caller)-\(step)"), budget: roomyBudget)
                        if case .ready = outcome { ready += 1 }
                    }
                    return ready
                }
            }
            return await group.reduce(into: 0) { $0 += $1 }
        }
        #expect(finished == 60)
        #expect(overlap.maximum == 1, "Two reads ran at once on one serial executor")
    }

    @Test func aBlockedRequestDoesNotDelayAnUnrelatedPipeline() async {
        let barrier = ExecutorBarrier(parties: 2)
        let slow = makePipeline(reader: BarrierReader(barrier: barrier))
        let unrelated = makePipeline(reader: BarrierReader(barrier: barrier))
        // Each read blocks until the other pipeline's read is running too, so neither pipeline waits for the other.
        let outcomes = await withTaskGroup(of: PreviewOutcome.self, returning: [PreviewOutcome].self) { group in
            group.addTask { await slow.preview(url: unusedURL("slow"), budget: roomyBudget) }
            group.addTask { await unrelated.preview(url: unusedURL("unrelated"), budget: roomyBudget) }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outcomes.count == 2)
        for outcome in outcomes {
            guard case .ready = outcome else { Issue.record("Both requests must finish normally: \(outcome)"); return }
        }
        #expect(!barrier.timedOut, "Each read had to be running while the other was still blocked")
    }

    @Test func aCancelledQueuedRequestNeverReadsTheFile() async {
        let gate = ExecutorGate()
        let reads = ExecutorLog()
        let (arrivalStream, arrival) = AsyncStream.makeStream(of: String.self)
        let pipeline = makePipeline(reader: GatedReader(gate: gate, reads: reads, arrival: arrival))
        let firstRequest = Task { () -> PreviewOutcome in
            let outcome = await pipeline.preview(url: unusedURL("first"), budget: roomyBudget)
            arrival.finish()
            return outcome
        }
        // Waits for the event, not for time: the stream delivers the first read's arrival, or ends if the request ends.
        var arrivals = arrivalStream.makeAsyncIterator()
        let firstArrival = await arrivals.next()
        #expect(firstArrival == "first.txt", "The first read had to be blocked inside the worker")
        // Queued behind the blocked first request and cancelled before it can start: its turn must end at once.
        let secondRequest = Task { await pipeline.preview(url: unusedURL("second"), budget: roomyBudget) }
        secondRequest.cancel()
        gate.open()
        #expect(await secondRequest.value == .cancelled)
        guard case .ready = await firstRequest.value else { Issue.record("The running request must finish normally"); return }
        #expect(reads.values == ["first.txt"], "The cancelled request must never reach the reader")
        #expect(!gate.hasExpired)
    }
}

// MARK: Support

/// The largest budget a request can have. Its deadline starts when the worker starts the request.
private let roomyBudget = PreviewBudget(maxMilliseconds: 30_000)

/// A serial actor whose isolation is a `PreviewWorkerExecutor`, written the way the pipeline's own worker is.
private actor ExecutorProbe {
    private let executor: PreviewWorkerExecutor

    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    init(executor: PreviewWorkerExecutor) {
        self.executor = executor
    }

    /// A synchronous body with some work in it that never suspends, so a second body can only overlap it if the
    /// executor itself ran two things at once.
    func measure(_ overlap: ExecutorOverlap) {
        overlap.enter()
        overlap.leave(spin())
    }

    /// A synchronous body that blocks its thread until every party is running, like a read on a stalled volume.
    func rendezvous(_ barrier: ExecutorBarrier) -> Bool {
        barrier.arrive()
    }
}

/// How many bodies were running at once. Every body enters, works and leaves under one counter.
private final class ExecutorOverlap: Sendable {
    private struct State {
        var active = 0
        var maximum = 0
        var entered = 0
        var checksum = 0
    }

    private let state = Mutex(State())

    func enter() { state.withLock { $0.active += 1; $0.entered += 1; $0.maximum = max($0.maximum, $0.active) } }
    func leave(_ work: Int) { state.withLock { $0.active -= 1; $0.checksum &+= work } }
    var maximum: Int { state.withLock { $0.maximum } }
    var entered: Int { state.withLock { $0.entered } }
}

/// Work that takes a moment and is the same every time; no clock is involved.
private func spin() -> Int {
    var total = 0
    for step in 0..<20_000 { total = total &+ step &* step }
    return total
}

/// Strings in the order they arrived, readable from any thread.
private final class ExecutorLog: Sendable {
    private let entries = Mutex<[String]>([])
    func append(_ entry: String) { entries.withLock { $0.append(entry) } }
    var values: [String] { entries.withLock { $0 } }
}

/// Names a queue so that code running on it can tell. The key is made once and never changes; setting and reading a
/// queue-specific value are safe from any thread, which is the invariant that makes this safe to share.
private final class QueueMarker: @unchecked Sendable {
    private let key = DispatchSpecificKey<String>()

    func mark(_ queue: DispatchQueue, as name: String) { queue.setSpecific(key: key, value: name) }

    /// The name of the marked queue the caller is running on; nil on any other queue or thread.
    var currentName: String? { DispatchQueue.getSpecific(key: key) }
}

/// Blocks each party until every party has arrived. Event-driven: the condition wakes all the waiters at once. After two
/// minutes a waiter is freed and the barrier marks itself timed out, so a regression fails a test instead of hanging
/// the run. The state is touched only while holding the condition's lock, which is why sharing it is safe.
private final class ExecutorBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let parties: Int
    private var arrived = 0
    private var expired = false

    init(parties: Int) {
        self.parties = parties
    }

    var timedOut: Bool {
        condition.lock()
        defer { condition.unlock() }
        return expired
    }

    /// Blocks the calling thread until every party has arrived; false when the failsafe ended the wait first.
    func arrive() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        arrived += 1
        condition.broadcast()
        let limit = Date(timeIntervalSinceNow: 120)
        while arrived < parties {
            guard condition.wait(until: limit) else {
                expired = true
                return false
            }
        }
        return true
    }
}

/// Holds synchronous bodies until a test opens it, with the same failsafe and the same locking as the barrier.
private final class ExecutorGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false
    private var expired = false

    var hasExpired: Bool {
        condition.lock()
        defer { condition.unlock() }
        return expired
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }

    /// Blocks the calling thread until the gate opens; false when the failsafe ended the wait first.
    @discardableResult
    func block() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let limit = Date(timeIntervalSinceNow: 120)
        while !isOpen {
            guard condition.wait(until: limit) else {
                expired = true
                return false
            }
        }
        return true
    }
}

/// Reports the file it was asked for, blocks the calling thread until the gate opens, like a read on a stalled volume.
private struct GatedReader: PreviewFileReading {
    let gate: ExecutorGate
    let reads: ExecutorLog
    let arrival: AsyncStream<String>.Continuation
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.append(url.lastPathComponent)
        arrival.yield(url.lastPathComponent)
        gate.block()
        return FileBytes(data: Data("text".utf8))
    }
}

/// Works under the overlap counter, so two reads running at once show up as a maximum above one.
private struct OverlapReader: PreviewFileReading {
    let overlap: ExecutorOverlap
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        overlap.enter()
        overlap.leave(spin())
        return FileBytes(data: Data("text".utf8))
    }
}

/// Blocks until every party, in other pipelines, is reading too.
private struct BarrierReader: PreviewFileReading {
    let barrier: ExecutorBarrier
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        _ = barrier.arrive()
        return FileBytes(data: Data("text".utf8))
    }
}

/// Says, at each stage the worker runs, whether it is running on a marked queue and which.
private struct ObservingStages: PreviewFileReading, FormatAdapter, PreviewPrivacyFiltering {
    let marker: QueueMarker
    let log: ExecutorLog

    private func note(_ stage: String) {
        log.append("\(stage) \(marker.currentName ?? "other")")
    }

    func read(url: URL, context: RequestContext) throws -> FileBytes {
        note("read")
        return FileBytes(data: Data("text".utf8))
    }

    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        note("parse")
        return ParsedTextDocument(text: input.text)
    }

    func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText {
        note("filter")
        return SafeText(text: document.text, redactionCount: 0, syntax: document.syntax)
    }
}

private struct PassthroughAdapter: FormatAdapter {
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: input.text)
    }
}

private func makePipeline(reader: any PreviewFileReading, adapter: any FormatAdapter = PassthroughAdapter(),
                          privacy: any PreviewPrivacyFiltering = DefaultPrivacyFilter(),
                          executor: PreviewWorkerExecutor? = nil) -> PreviewPipeline {
    let registrations = [AdapterRegistration(formatID: .plainText) { adapter }]
    guard let executor else { return PreviewPipeline(registrations: registrations, reader: reader, privacy: privacy) }
    return PreviewPipeline(registrations: registrations, reader: reader, privacy: privacy, executor: executor)
}

private func unusedURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/unused/\(name).txt")
}
