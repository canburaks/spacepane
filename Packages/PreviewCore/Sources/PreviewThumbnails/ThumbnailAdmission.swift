import Foundation
import Synchronization

/// Limits how many content thumbnails read and parse at once (decision 027, Q-40; thumbnails review TH-07).
///
/// Finder can ask for hundreds of thumbnails in one moment, and every request that reaches the pipeline holds a
/// cooperative thread for as long as its synchronous read and parse run. Left unbounded, a burst on a slow or
/// network volume parks every thread the process has and nothing is left to answer Quick Look. The admission
/// lets about half the active processors run their pipelines at the same time (at least one) and queues the
/// rest in arrival order. A queued request holds no thread, only a suspended task, and it leaves the queue the
/// moment its task is cancelled, so a request the reply gate has already answered never keeps its place.
///
/// Only a request that is about to read the file waits here; every policy decision (switch, type choice,
/// catalog policy) answers before the admission and never queues.
public final class ThumbnailAdmission: Sendable {
    /// Half the processors, and never fewer than one: a burst then leaves cores for Finder and for the threads
    /// that deliver the replies.
    public static func width(forProcessorCount count: Int) -> Int { max(1, count / 2) }

    /// The width for this machine.
    public static var standardWidth: Int { width(forProcessorCount: ProcessInfo.processInfo.activeProcessorCount) }

    public let maximumConcurrent: Int

    private struct State {
        var running = 0
        var waiting: [Ticket] = []
    }

    private let state = Mutex(State())

    public init(maximumConcurrent: Int = ThumbnailAdmission.standardWidth) {
        self.maximumConcurrent = max(1, maximumConcurrent)
    }

    /// Requests that hold a slot now. A snapshot, for diagnostics and tests.
    public var runningCount: Int { state.withLock { state -> Int in state.running } }

    /// Requests queued for a slot now. A snapshot, for diagnostics and tests.
    public var waitingCount: Int { state.withLock { state -> Int in state.waiting.count } }

    /// Runs `work` once a slot is free and gives the slot back when it returns. A request whose task is
    /// cancelled before it holds a slot never runs `work` and gets `cancelled` instead.
    public func run<T: Sendable>(ifCancelled cancelled: T, _ work: () async -> T) async -> T {
        guard await acquire() else { return cancelled }
        defer { release() }
        return await work()
    }

    // MARK: Slots

    /// True when the caller holds a slot; false when its task was cancelled first.
    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        // A free slot is taken at once. Otherwise the request joins the queue before it suspends, so the queue
        // order is the order in which requests arrived.
        let queued = state.withLock { state -> Ticket? in
            guard state.running >= maximumConcurrent else {
                state.running += 1
                return nil
            }
            let ticket = Ticket()
            state.waiting.append(ticket)
            return ticket
        }
        guard let queued else { return true }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                queued.park(continuation)
            }
        } onCancel: {
            cancel(queued)
        }
    }

    private func cancel(_ ticket: Ticket) {
        state.withLock { state -> Void in
            state.waiting.removeAll { $0 === ticket }
        }
        _ = ticket.resolve(false)
    }

    private func release() {
        while true {
            let next = state.withLock { state -> Ticket? in
                guard !state.waiting.isEmpty else {
                    state.running -= 1
                    return nil
                }
                return state.waiting.removeFirst()
            }
            guard let next else { return }
            // The slot passes to the next waiter without leaving the count. A waiter cancelled at the same
            // moment refuses it, and the slot goes to the one behind.
            if next.resolve(true) { return }
        }
    }
}

/// One queued request. It is decided once, either granted a slot or cancelled, in whatever order the grant, the
/// cancellation and the suspension of the waiting task happen; the continuation is resumed outside the lock.
private final class Ticket: Sendable {
    private enum Slot {
        case pending
        case parked(CheckedContinuation<Bool, Never>)
        case decided(Bool)
    }

    private let slot = Mutex(Slot.pending)

    /// Registers the suspended task; resumes it at once when the ticket was decided before it parked.
    func park(_ continuation: CheckedContinuation<Bool, Never>) {
        let early = slot.withLock { slot -> Bool? in
            if case .decided(let granted) = slot { return granted }
            slot = .parked(continuation)
            return nil
        }
        if let early { continuation.resume(returning: early) }
    }

    /// Decides the ticket once. True when this call decided it; a ticket that was already decided keeps its answer.
    func resolve(_ granted: Bool) -> Bool {
        let decision = slot.withLock { slot -> (decided: Bool, continuation: CheckedContinuation<Bool, Never>?) in
            switch slot {
            case .decided:
                return (false, nil)
            case .pending:
                slot = .decided(granted)
                return (true, nil)
            case .parked(let continuation):
                slot = .decided(granted)
                return (true, continuation)
            }
        }
        decision.continuation?.resume(returning: granted)
        return decision.decided
    }
}
