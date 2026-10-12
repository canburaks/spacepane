import Foundation
import Synchronization
@testable import PreviewRenderers

/// Models a native call that cannot be interrupted. Cancellation never opens its continuation gate.
final class NoncooperativeImageDecodeProbe: Sendable {
    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }
    private struct State {
        var started = 0
        var finished = 0
        var cancelledFinishes = 0
        var running = 0
        var maximum = 0
        var open = false
        var parked: [CheckedContinuation<Void, Never>] = []
        var startedWaiters: [Waiter] = []
        var finishedWaiters: [Waiter] = []
    }
    private let state = Mutex(State())

    var cancelledFinishes: Int { state.withLock { $0.cancelledFinishes } }
    var started: Int { state.withLock { $0.started } }
    var maximumConcurrent: Int { state.withLock { $0.maximum } }

    func decode() -> ImagePageScheduler.Decode { { [self] _, _ in await run() } }
    func nativeDecode() -> ImagePageDecoder.NativeDecode { { [self] _, _ in await run() } }

    func run() async -> DecodedPageImage? {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.started += 1
            state.running += 1
            state.maximum = max(state.maximum, state.running)
            let ready = state.startedWaiters.filter { $0.count <= state.started }.map(\.continuation)
            state.startedWaiters.removeAll { $0.count <= state.started }
            return ready
        }
        for continuation in ready { continuation.resume() }
        await withCheckedContinuation { continuation in
            let open = state.withLock { state -> Bool in
                if state.open { return true }
                state.parked.append(continuation)
                return false
            }
            if open { continuation.resume() }
        }
        let image = DecodedPageImage(image: testBitmap(width: 4, height: 4))
        let cancelled = Task.isCancelled
        let finished = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.running -= 1
            state.finished += 1
            if cancelled { state.cancelledFinishes += 1 }
            let ready = state.finishedWaiters.filter { $0.count <= state.finished }.map(\.continuation)
            state.finishedWaiters.removeAll { $0.count <= state.finished }
            return ready
        }
        for continuation in finished { continuation.resume() }
        return image
    }

    func waitForStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.started >= count { return true }
                state.startedWaiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func waitForFinished(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.finished >= count { return true }
                state.finishedWaiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func open() {
        let parked = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.open = true
            let parked = state.parked
            state.parked = []
            return parked
        }
        for continuation in parked { continuation.resume() }
    }
}

@MainActor
final class ImageDeliveryProbe {
    private(set) var indices: [Int] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ index: Int) {
        indices.append(index)
        let ready = waiters.filter { $0.0 <= indices.count }.map { $0.1 }
        waiters.removeAll { $0.0 <= indices.count }
        for continuation in ready { continuation.resume() }
    }

    func waitForCount(_ count: Int) async {
        if indices.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}
