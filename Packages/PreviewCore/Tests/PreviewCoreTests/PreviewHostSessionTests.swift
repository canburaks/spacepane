import Foundation
import Synchronization
import Testing
import PreviewCore

private final class HostManualTimer: RequestTimerScheduling, Sendable {
    let pending = Mutex<(@Sendable () -> Void)?>(nil)
    func schedule(after interval: Duration, _ action: @escaping @Sendable () -> Void) -> RequestTimerHandle {
        pending.withLock { $0 = action }
        return RequestTimerHandle { [self] in pending.withLock { $0 = nil } }
    }
    func fire() { pending.withLock { action in defer { action = nil }; return action }?() }
}

private actor HostSuspendedWork {
    let started: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<Int, Never>?
    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    func run() async -> Int {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.yield(Void())
        }
    }
    func release() { continuation?.resume(returning: 42); continuation = nil }
}

@Suite("Bounded preview host sessions", .serialized)
@MainActor
struct PreviewHostSessionTests {
    @Test func readyDeliveryCancelsTheTimerAndKeepsIdentity() async {
        let timer = HostManualTimer()
        let (events, sink) = AsyncStream<PreviewHostDelivery<Int>>.makeStream()
        let id = UUID()
        let session = PreviewHostSession<Int>(id: id, scheduler: timer) { sink.yield($0) }
        var iterator = events.makeAsyncIterator()
        session.start { 7 }
        #expect(await iterator.next() == .completed(7))
        #expect(session.id == id && session.isFinished)
        #expect(timer.pending.withLock { $0 == nil })
    }

    @Test func timeoutAnswersWhileNoncooperativeWorkRemainsSuspended() async {
        let timer = HostManualTimer()
        let (events, sink) = AsyncStream<PreviewHostDelivery<Int>>.makeStream()
        let (started, startSink) = AsyncStream<Void>.makeStream()
        let (finished, finishSink) = AsyncStream<Void>.makeStream()
        let work = HostSuspendedWork(started: startSink)
        var delivered: [PreviewHostDelivery<Int>] = []
        let session = PreviewHostSession<Int>(scheduler: timer) { delivered.append($0); sink.yield($0) }
        session.start {
            let answer = await work.run()
            finishSink.yield(Void())
            return answer
        }
        var starts = started.makeAsyncIterator()
        _ = await starts.next()
        timer.fire()
        var replies = events.makeAsyncIterator()
        #expect(await replies.next() == .timedOut)
        #expect(session.isFinished)
        session.cancel()
        timer.fire()
        await work.release()
        var finishes = finished.makeAsyncIterator()
        _ = await finishes.next()
        // The shared gate's synchronous late-answer tests cover terminal exclusion; this checks
        // that releasing the host's suspended producer also preserves its delivered state.
        await Task.yield()
        #expect(delivered == [.timedOut])
    }

    @Test func cancellationBeforeStartDoesNotRunTheOperation() async {
        let timer = HostManualTimer()
        let (events, sink) = AsyncStream<PreviewHostDelivery<Int>>.makeStream()
        let reads = Mutex(0)
        let session = PreviewHostSession<Int>(scheduler: timer) { sink.yield($0) }
        session.cancel()
        session.start { reads.withLock { $0 += 1 }; return 7 }
        var replies = events.makeAsyncIterator()
        #expect(await replies.next() == .cancelled)
        #expect(reads.withLock { $0 } == 0)
        #expect(timer.pending.withLock { $0 == nil })
    }

    @Test func replacementCancellationCannotCompleteTheNewSession() async {
        let timer = HostManualTimer()
        let (oldEvents, oldSink) = AsyncStream<PreviewHostDelivery<Int>>.makeStream()
        let (newEvents, newSink) = AsyncStream<PreviewHostDelivery<Int>>.makeStream()
        let old = PreviewHostSession<Int>(scheduler: timer) { oldSink.yield($0) }
        old.cancel()
        let next = PreviewHostSession<Int>(scheduler: HostManualTimer()) { newSink.yield($0) }
        next.start { 9 }
        var oldReplies = oldEvents.makeAsyncIterator()
        var newReplies = newEvents.makeAsyncIterator()
        #expect(await oldReplies.next() == .cancelled)
        #expect(await newReplies.next() == .completed(9))
        #expect(old.id != next.id)
    }
}
