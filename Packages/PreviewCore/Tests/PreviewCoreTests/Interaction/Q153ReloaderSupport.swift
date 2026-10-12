import Foundation
import Synchronization
import PreviewContracts
@testable import PreviewCore

final class Q153Watch: PreviewSourceWatching, Sendable {
    let events: AsyncStream<PreviewSourceMonitor.Event>
    private let sink: AsyncStream<PreviewSourceMonitor.Event>.Continuation
    private let stops = Mutex(0)
    init() { let (stream, continuation) = AsyncStream.makeStream(of: PreviewSourceMonitor.Event.self); events = stream; sink = continuation }
    func emit(_ event: PreviewSourceMonitor.Event) { sink.yield(event) }
    func stop() { stops.withLock { $0 += 1 }; sink.finish() }
    var stopCount: Int { stops.withLock { $0 } }
}
final class Q153WatchSequence: Sendable {
    private let watches: Mutex<[Q153Watch]>
    init(_ watches: [Q153Watch]) { self.watches = Mutex(watches) }
    func make() -> (any PreviewSourceWatching)? {
        watches.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    }
}
@MainActor
final class Q153ReloadApplies {
    weak var reloader: PreviewLiveReloader?
    let values: AsyncStream<LiveReloadResult>
    private let sink: AsyncStream<LiveReloadResult>.Continuation
    private(set) var results: [LiveReloadResult] = []
    private(set) var watchingAtApply: [Bool] = []
    init() { let (stream, continuation) = AsyncStream.makeStream(of: LiveReloadResult.self); values = stream; sink = continuation }
    func apply(_ value: LiveReloadResult) {
        watchingAtApply.append(reloader?.isWatching == true)
        results.append(value); sink.yield(value)
    }
}
actor Q153ReloadGate {
    let starts: AsyncStream<Int>
    private let sink: AsyncStream<Int>.Continuation
    private var pending: [Int: CheckedContinuation<LiveReloadResult, Never>] = [:]
    private var count = 0
    init() { let (stream, continuation) = AsyncStream.makeStream(of: Int.self); starts = stream; sink = continuation }
    func load() async -> LiveReloadResult {
        count += 1; let current = count
        return await withCheckedContinuation { pending[current] = $0; sink.yield(current) }
    }
    func release(_ number: Int, _ result: LiveReloadResult) { pending.removeValue(forKey: number)?.resume(returning: result) }
    var calls: Int { count }
}
func q153ReloadMarker(_ marker: String) -> LiveReloadResult {
    .preview(.ready(TextPresentation(formatID: .plainText, text: marker, lineCount: 1,
                                    byteCount: marker.utf8.count, encoding: .utf8, redactionCount: 0)), .defaults)
}
