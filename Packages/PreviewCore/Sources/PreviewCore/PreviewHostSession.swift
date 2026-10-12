import Foundation

public enum PreviewHostDelivery<Value: Sendable>: Sendable {
    case completed(Value)
    case timedOut
    case cancelled
}

extension PreviewHostDelivery: Equatable where Value: Equatable {}

/// Owns one preview host's work and terminal delivery. Parsing may be noncooperative, but a Dispatch
/// deadline can still deliver the timeout state; native work is cancelled and its late value discarded.
/// Delivery is on the main actor, where hosts install a state and answer their completion handler.
/// This preserves content-ready completion; choosing earlier state/grace completion requires host evidence.
@MainActor
public final class PreviewHostSession<Value: Sendable> {
    public let id: UUID
    private let gate: RequestReplyGate<PreviewHostDelivery<Value>>
    private var hasStarted = false

    /// Thirty seconds is a host safety ceiling, separate from each adapter's shorter request budget.
    public init(id: UUID = UUID(), limit: Duration = .seconds(30),
                scheduler: any RequestTimerScheduling = DispatchRequestScheduler(),
                deliver: @escaping @MainActor (PreviewHostDelivery<Value>) -> Void) {
        self.id = id
        gate = RequestReplyGate(limit: limit, scheduler: scheduler, timeoutValue: .timedOut) { delivery in
            Task { @MainActor in deliver(delivery) }
        }
    }

    isolated deinit { cancelOnTeardown() }

    /// Kept out of line: Swift 6.3.3's optimizer (Xcode 26.6, hosted run 133) crashes in EarlyPerfInliner when it
    /// inlines the gate's cancel into this generic class's isolated deinit under whole-module optimization.
    /// Xcode 27's compiler does not. The deinit's behaviour is unchanged.
    @inline(never)
    private func cancelOnTeardown() {
        _ = gate.cancel(with: .cancelled)
    }

    public var isFinished: Bool { gate.isClosed }

    public func start(_ operation: @escaping @Sendable () async -> Value) {
        guard !hasStarted, !gate.isClosed else { return }
        hasStarted = true
        gate.start { .completed(await operation()) }
    }

    public func cancel() { gate.cancel(with: .cancelled) }
}
