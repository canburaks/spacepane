import Foundation
import Synchronization

/// A one-shot timer. The extension uses Dispatch; tests inject a manual one, so no test waits on a clock.
public protocol RequestTimerScheduling: Sendable {
    /// Runs `action` once, `interval` from now, unless the returned handle is cancelled first.
    func schedule(after interval: Duration, _ action: @escaping @Sendable () -> Void) -> RequestTimerHandle
}

/// Stops a timer that has not fired yet.
public struct RequestTimerHandle: Sendable {
    private let cancellation: @Sendable () -> Void

    public init(cancel: @escaping @Sendable () -> Void) {
        cancellation = cancel
    }

    /// Cancelling twice, or after the timer fired, does nothing.
    public func cancel() { cancellation() }
}

/// The production timer: a work item on a Dispatch queue. It needs no thread of the Swift cooperative pool, so it
/// fires on time even when parsing and blocked reads occupy every one of them.
public struct DispatchRequestScheduler: RequestTimerScheduling {
    private let queue: DispatchQueue

    /// The default queue is a concurrent system queue; a test passes its own so it controls when work may run.
    public init(queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated)) {
        self.queue = queue
    }

    public func schedule(after interval: Duration, _ action: @escaping @Sendable () -> Void) -> RequestTimerHandle {
        let timer = OneShotTimer(action)
        let item = DispatchWorkItem { timer.fire() }
        queue.asyncAfter(deadline: .now() + interval.requestDispatchInterval, execute: item)
        return RequestTimerHandle { timer.cancel() }
    }
}

/// Runs its action at most once. Cancelling marks it finished, so a work item that is already queued does nothing.
private final class OneShotTimer: Sendable {
    private let finished = Mutex(false)
    private let action: @Sendable () -> Void

    init(_ action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func fire() {
        let runs = finished.withLock { finished -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        if runs { action() }
    }

    func cancel() {
        finished.withLock { finished -> Void in finished = true }
    }
}

private extension Duration {
    var requestDispatchInterval: DispatchTimeInterval {
        let parts = components
        let nanoseconds = parts.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !nanoseconds.overflow else { return .nanoseconds(Int.max) }
        return .nanoseconds(Int(clamping: nanoseconds.partialValue + parts.attoseconds / 1_000_000_000))
    }
}

/// Answers one bounded asynchronous request exactly once, within its time limit (decision 027, Q-40; thumbnails review TH-07).
///
/// Two parties race to answer: the work, a task that reads the file and builds the picture, and a deadline timer.
/// Whichever closes the gate first delivers and the other is dropped. The deadline is a scheduler timer and not a
/// Swift task, so it still fires when parsing and blocked reads hold every cooperative thread; the earlier
/// `ThumbnailRace`, whose timer was a task on that same pool, could not promise it. The value delivered when the
/// deadline wins is chosen by the caller (the content-free glyph), and the work's task is cancelled so that a
/// request waiting for admission leaves the queue; its late result, if it still arrives, is dropped.
///
/// `deliver` runs at most once, on the thread of whichever party won, and is the only place a reply is built.
public final class RequestReplyGate<Value: Sendable>: Sendable {
    private struct State {
        var isClosed = false
        var timer: RequestTimerHandle?
        var worker: Task<Void, Never>?
    }

    /// What closing the gate hands back: the pieces its caller stops.
    private typealias Closed = (timer: RequestTimerHandle?, worker: Task<Void, Never>?)

    private let state = Mutex(State())
    private let timeoutValue: Value
    private let onTimeout: @Sendable () -> Void
    private let deliver: @Sendable (Value) -> Void

    /// Arms the deadline at once. `onTimeout` runs only when the deadline wins, just before the timeout value is
    /// delivered.
    public init(limit: Duration, scheduler: any RequestTimerScheduling, timeoutValue: Value,
                onTimeout: @escaping @Sendable () -> Void = {},
                deliver: @escaping @Sendable (Value) -> Void) {
        self.timeoutValue = timeoutValue
        self.onTimeout = onTimeout
        self.deliver = deliver
        let timer = scheduler.schedule(after: limit) { [self] in self.timeout() }
        let alreadyClosed = state.withLock { state -> Bool in
            if state.isClosed { return true }
            state.timer = timer
            return false
        }
        if alreadyClosed { timer.cancel() }
    }

    /// True once a value has been delivered.
    public var isClosed: Bool { state.withLock { state -> Bool in state.isClosed } }

    /// Runs `work` as a task whose result answers the gate. When the deadline passes first the task is cancelled
    /// and the gate delivers the timeout value instead.
    public func start(_ work: @escaping @Sendable () async -> Value) {
        let task = Task { [self] in
            _ = self.answer(await work())
        }
        let alreadyClosed = state.withLock { state -> Bool in
            if state.isClosed { return true }
            state.worker = task
            return false
        }
        if alreadyClosed { task.cancel() }
    }

    /// Delivers `value` unless the gate has already closed. True when this call delivered.
    @discardableResult
    public func answer(_ value: Value) -> Bool {
        guard let closed = close() else { return false }
        closed.timer?.cancel()
        deliver(value)
        return true
    }

    /// Abandons outstanding work and delivers the caller's cancellation value once. A later result
    /// cannot reopen the gate; a native read may still finish before it observes task cancellation.
    @discardableResult
    public func cancel(with value: Value) -> Bool {
        guard let closed = close() else { return false }
        closed.timer?.cancel()
        closed.worker?.cancel()
        deliver(value)
        return true
    }

    private func timeout() {
        guard let closed = close() else { return }
        closed.worker?.cancel()
        onTimeout()
        deliver(timeoutValue)
    }

    /// Closes the gate. Only the caller that gets a value back may deliver, which is what makes delivery happen once.
    private func close() -> Closed? {
        state.withLock { state -> Closed? in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            let closed: Closed = (state.timer, state.worker)
            state.timer = nil
            state.worker = nil
            return closed
        }
    }
}
