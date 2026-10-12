import Synchronization

/// Delivers exactly one result per request. The worker, a timer and an outer cancellation race to
/// decide it; the losers are cancelled and their results are ignored. The pipeline's deadline is
/// cooperative, so this is the bound that still holds when a native read or decode blocks.
///
/// The timer here is a Swift task, which needs a free cooperative thread to fire. The extension therefore answers
/// Quick Look through `ThumbnailReplyGate`, whose deadline is a Dispatch timer (decision 027, Q-40). This race stays
/// behind `ContentThumbnailService.outcome(for:geometry:)`, for in-process callers and tests, until a Mac session
/// has validated the gate; then it can go.
enum ThumbnailRace {
    static func run<T: Sendable>(limit: Duration, onTimeout: T, onCancel: T,
                                 work: @escaping @Sendable () async -> T) async -> T {
        let state = RaceState<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                state.install(continuation)
                let worker = Task { _ = state.resolve(await work()) }
                let timer = Task {
                    try? await Task.sleep(for: limit)
                    _ = state.resolve(onTimeout)
                }
                state.track([worker, timer])
            }
        } onCancel: {
            _ = state.resolve(onCancel)
        }
    }
}

/// One-shot result slot. All fields change under one lock; the continuation is resumed outside it.
private final class RaceState<T: Sendable>: Sendable {
    private struct Slot {
        var continuation: CheckedContinuation<T, Never>?
        var result: T?
        var resolved = false
        var tasks: [Task<Void, Never>] = []
    }
    private let slot = Mutex(Slot())

    func install(_ continuation: CheckedContinuation<T, Never>) {
        let early: T? = slot.withLock { slot in
            // A cancellation can decide the result before the continuation exists.
            if slot.resolved { return slot.result }
            slot.continuation = continuation
            return nil
        }
        if let early { continuation.resume(returning: early) }
    }

    /// True when this call decided the result.
    func resolve(_ value: T) -> Bool {
        let decision = slot.withLock { slot -> (continuation: CheckedContinuation<T, Never>?, tasks: [Task<Void, Never>])? in
            guard !slot.resolved else { return nil }
            slot.resolved = true
            slot.result = value
            let decided = (continuation: slot.continuation, tasks: slot.tasks)
            slot.continuation = nil
            slot.tasks = []
            return decided
        }
        guard let decision else { return false }
        for task in decision.tasks { task.cancel() }
        decision.continuation?.resume(returning: value)
        return true
    }

    func track(_ tasks: [Task<Void, Never>]) {
        let alreadyResolved = slot.withLock { slot -> Bool in
            if slot.resolved { return true }
            slot.tasks.append(contentsOf: tasks)
            return false
        }
        if alreadyResolved { for task in tasks { task.cancel() } }
    }
}
