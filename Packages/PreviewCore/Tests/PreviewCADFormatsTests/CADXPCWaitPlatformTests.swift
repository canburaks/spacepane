import Foundation
import Testing
import Synchronization
@testable import PreviewCADFormats
import PreviewContracts

/// The wait in `CADXPCClient`: a stored reply wakes it at once, and cancellation or the deadline ends it at the
/// next checkpoint. Nothing here sleeps; the package-only checkpoint observer places cancellation exactly.
///
/// A test that must block does it on a thread of its own (`blockingOnItsOwnThread`) while the test itself suspends,
/// and nothing here asks a libdispatch global queue for work that a blocked thread depends on. The Swift
/// concurrency pool and the global queues draw on the same few threads, so on a three-core runner a handful of
/// blocked tests starved the very closures they were waiting for and held up unrelated suites (first hosted run).
@Suite("CAD XPC reply wait", .serialized) struct CADXPCWaitPlatformTests {
    /// A missing wakeup shows as `false` from `wait` after this long; a working one returns at once, so only a
    /// failing run ever waits this long.
    private static let limitMilliseconds = 10_000

    @Test func aReplyStoredBeforeTheWaitWakesItAtOnce() {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        reply.receive(data: Data([1]), status: nil)
        #expect(reply.wait(milliseconds: Self.limitMilliseconds))
    }

    @Test func aReplyFromAnotherThreadWakesTheWait() async {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        let limit = Self.limitMilliseconds
        // The waiter blocks on its own thread; this thread stores the reply, before or after the waiter arrives.
        let woken = await blockingOnItsOwnThread({ reply.wait(milliseconds: limit) },
                                                 meanwhile: { reply.receive(data: Data([1]), status: nil) })
        #expect(woken)
        guard case .success(let data) = reply.result else { Issue.record("The wait ended without the reply"); return }
        #expect(data == Data([1]))
    }

    @Test func theWaitEndsAtItsSliceWhenNoReplyArrives() {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        #expect(!reply.wait(milliseconds: 1))
        #expect(reply.result == nil)
    }

    @Test func laterRepliesNeitherReplaceTheFirstNorWakeTheWaitAgain() {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        reply.receive(data: Data([1]), status: nil)
        reply.complete(.failure(.cadImporterUnavailable))
        #expect(reply.wait(milliseconds: Self.limitMilliseconds))
        // The one wakeup a reply produces is used up, so a second wait runs out its slice.
        #expect(!reply.wait(milliseconds: 1))
        guard case .success(let data) = reply.result else { Issue.record("A later reply replaced the first"); return }
        #expect(data == Data([1]))
    }

    @Test func aStoredReplyIsReturnedByTheWaitLoop() throws {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        reply.receive(data: Data([9]), status: nil)
        let result = try CADXPCClient.waitForReply(reply, context: RequestContext(budget: .standard))
        guard case .success(let data) = result else { Issue.record("Expected the stored reply"); return }
        #expect(data == Data([9]))
    }

    @Test func aFailureStoredByAnotherThreadIsReturnedByTheWaitLoop() async {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        // The loop's own deadline stays far away, so a slow runner cannot turn this into a deadline failure.
        let budget = PreviewBudget(maxMilliseconds: Self.limitMilliseconds)
        let outcome: Result<CADXPCClient.Reply, any Error> = await blockingOnItsOwnThread({
            Result { try CADXPCClient.waitForReply(reply, context: RequestContext(budget: budget)) }
        }, meanwhile: {
            reply.complete(.failure(.malformedDocument))
        })
        guard case .success(.failure(.malformedDocument)) = outcome else {
            Issue.record("Expected the stored failure, got \(outcome)")
            return
        }
    }

    @Test func cancellationEndsTheWaitAtTheNextCheckpoint() async {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        let checkpoints = Mutex(0)
        let cancelled = await Task.detached { () -> Bool in
            var context = RequestContext(budget: .standard)
            context.checkpointObserver = {
                let count = checkpoints.withLock { $0 += 1; return $0 }
                if count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { _ = try CADXPCClient.waitForReply(reply, context: context, sliceMilliseconds: 1) }
            catch is CancellationError { return true }
            catch { Issue.record("Expected cancellation, got \(error)") }
            return false
        }.value
        #expect(cancelled, "A wait with no reply must end when its task is cancelled")
        #expect(checkpoints.withLock { $0 } == 3)
    }

    @Test func theRequestDeadlineEndsTheWait() {
        let reply = CADXPCClient.ReplyState(maximumBytes: 8)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try CADXPCClient.waitForReply(reply, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 1)),
                                          sliceMilliseconds: 1)
        }
    }

    @Test func unusableServiceNamesAndOversizedInputFailBeforeAnyConnection() {
        for name in ["", String(repeating: "a", count: 256), "a/b", "a\0b"] {
            #expect(throws: PreviewFailure.cadImporterUnavailable) {
                try CADXPCClient.run(serviceName: name, kind: .iges, input: Data(),
                                     context: RequestContext(budget: .standard))
            }
        }
        #expect(throws: PreviewFailure.inputTooLarge) {
            try CADXPCClient.run(serviceName: "example.cad-test", kind: .iges,
                                 input: Data(count: PreviewBudget.standard.maxInputBytes + 1),
                                 context: RequestContext(budget: .standard))
        }
    }
}

/// Runs `work`, which may block, on a new thread and returns its result; `meanwhile` runs on the caller's thread
/// right after that thread started. The caller suspends instead of blocking, so a blocked wait never holds a thread
/// of the Swift concurrency pool, and the thread is created directly rather than taken from a libdispatch queue.
private func blockingOnItsOwnThread<Value: Sendable>(_ work: @escaping @Sendable () -> Value,
                                                      meanwhile: () -> Void) async -> Value {
    await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
        Thread.detachNewThread { continuation.resume(returning: work()) }
        meanwhile()
    }
}
