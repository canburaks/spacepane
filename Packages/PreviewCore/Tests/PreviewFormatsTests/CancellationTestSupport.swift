import Synchronization
import Testing
import PreviewContracts

/// Cooperative-cancellation check for synchronous adapters. A sleep before `cancel()` can outlast the
/// parse in a loaded test run, so the request is placed at a checkpoint instead of racing the scheduler.
enum CancellationTest {
    /// Parses once uncancelled and counts its checkpoints, which depend only on the input. A second
    /// parse cancels its own task at the middle checkpoint and must throw `CancellationError` there,
    /// with half its work remaining. Returns the uncancelled document for content checks.
    @discardableResult
    static func expectStopsActiveParse(budget: PreviewBudget, sourceLocation: SourceLocation = #_sourceLocation,
                                       _ parse: @escaping @Sendable (RequestContext) throws -> ParsedTextDocument)
    async throws -> ParsedTextDocument {
        let completedCheckpoints = Mutex(0)
        var context = RequestContext(budget: budget)
        context.checkpointObserver = { completedCheckpoints.withLock { $0 += 1 } }
        let completed = try parse(context)
        let cancelAt = completedCheckpoints.withLock { $0 } / 2
        try #require(cancelAt > 1, "Cancellation must follow the entry checkpoint", sourceLocation: sourceLocation)
        let observedCheckpoints = Mutex(0)
        let task = Task.detached {
            var context = RequestContext(budget: budget)
            context.checkpointObserver = {
                let count = observedCheckpoints.withLock { $0 += 1; return $0 }
                if count == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do {
                _ = try parse(context)
                return false
            } catch is CancellationError { return true }
            catch { Issue.record("Expected cancellation, got \(error)", sourceLocation: sourceLocation); return false }
        }
        #expect(await task.value, "The parse completed despite cancellation", sourceLocation: sourceLocation)
        #expect(observedCheckpoints.withLock { $0 } == cancelAt, "The parse continued past the cancelling checkpoint",
                sourceLocation: sourceLocation)
        return completed
    }
}
