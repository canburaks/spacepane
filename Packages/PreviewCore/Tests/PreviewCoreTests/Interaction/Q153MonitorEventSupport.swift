import Synchronization
import PreviewCore

final class Q153MonitorTimers: RequestTimerScheduling, Sendable {
    private final class Job: Sendable {
        private let finished = Mutex(false)
        private let cancelled = Mutex(false)
        let action: @Sendable () -> Void
        init(_ action: @escaping @Sendable () -> Void) { self.action = action }
        func cancel() { cancelled.withLock { $0 = true } }
        func fire(includingCancelled: Bool) {
            let runs = finished.withLock { value in
                guard !value else { return false }; value = true; return true
            }
            if runs && (includingCancelled || !cancelled.withLock({ $0 })) { action() }
        }
    }
    private struct State { var count = 0; var jobs: [Job] = [] }
    private let state = Mutex(State())
    func schedule(after interval: Duration, _ action: @escaping @Sendable () -> Void) -> RequestTimerHandle {
        let job = Job(action)
        state.withLock { $0.count += 1; $0.jobs.append(job) }
        return RequestTimerHandle { job.cancel() }
    }
    var scheduledCount: Int { state.withLock { $0.count } }
    func fireFirst(includingCancelled: Bool = false) {
        let job = state.withLock { value -> Job? in
            value.jobs.isEmpty ? nil : value.jobs.removeFirst()
        }
        job?.fire(includingCancelled: includingCancelled)
    }
}
