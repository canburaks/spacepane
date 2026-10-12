import Foundation
import Synchronization
import Testing
@testable import PreviewCore

/// Every live-reload test shares one serialized parent suite: the descriptor counter they check is process-wide.
@Suite("Live reload", .serialized)
enum LiveReload {}

/// A scratch directory removed when the test ends.
final class ScratchDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("live-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String = "source.txt", contents: String = "one\n") throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }
}

/// Collects a monitor's events on a task so tests can wait for them without driving an iterator.
final class EventCollector: Sendable {
    private struct State {
        var events: [PreviewSourceMonitor.Event] = []
        var finished = false
    }
    private final class Box: Sendable { let state = Mutex(State()) }
    private let box = Box()
    private let task: Task<Void, Never>

    init(_ monitor: PreviewSourceMonitor) {
        let box = box
        task = Task {
            for await event in monitor.events { box.state.withLock { $0.events.append(event) } }
            box.state.withLock { $0.finished = true }
        }
    }

    var events: [PreviewSourceMonitor.Event] { box.state.withLock { $0.events } }
    var isFinished: Bool { box.state.withLock { $0.finished } }
    func cancel() { task.cancel() }
}

/// Polls a condition (in tests only) until it holds or the time runs out.
func eventually(timeout: Duration = .seconds(5), _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

func settle(_ duration: Duration = .milliseconds(300)) async { try? await Task.sleep(for: duration) }

/// Short timings keep the tests fast; the logic under test is the same as with `.standard`.
let quickTiming = PreviewSourceMonitor.Timing(
    debounce: .milliseconds(80), maximumDelay: .milliseconds(600),
    reopenDelays: [10, 20, 40, 80, 160, 320].map { Duration.milliseconds($0) })

/// Writes into the existing file, keeping its inode.
func overwrite(_ url: URL, with text: String) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data(text.utf8))
}

func append(_ url: URL, _ text: String) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

/// The descriptors open when a test starts. Earlier tests close theirs asynchronously after `stop()`, so wait for
/// them to drain; the suite runs serially, so nothing else creates monitors meanwhile.
func drainedDescriptors() async -> Int {
    _ = await eventually { PreviewSourceMonitor.openDescriptorCount == 0 }
    return PreviewSourceMonitor.openDescriptorCount
}
