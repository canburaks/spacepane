import Dispatch
import Foundation
import PreviewContracts

/// Reports changes to one previewed file or folder, without ever reading or writing it.
///
/// A kernel file-system source on an event-only descriptor (`O_EVTONLY`, which grants no read or write
/// access and does not keep a volume busy) watches the item's own vnode. Nothing polls: events arrive from the
/// kernel, bursts of them (an editor saving, a log growing) are coalesced into one report after a quiet period
/// with an upper bound on the wait, and a replaced file is found again by its path.
///
/// Atomic saves replace the watched item with a new one at the same path. When the vnode is deleted or
/// renamed, the monitor re-opens the path (a bounded number of delayed attempts) and, if a file is there,
/// keeps watching it and reports `.replaced`. If none appears the monitor reports `.removed` and ends. It also
/// ends after `.revoked` (access withdrawn, such as an unmounted volume). Ending finishes `events`.
///
/// Everything is local to the process. Nothing here widens file access: opening the path needs the same
/// permission as reading it, and a host that cannot open it simply gets no monitor (`init` returns nil).
public final class PreviewSourceMonitor: Sendable {
    public enum Event: Sendable, Equatable {
        /// Content, size, attributes or links changed.
        case modified
        /// The item was replaced by a new file at the same path and the monitor now watches the new one.
        case replaced
        /// The item is gone and no replacement appeared. The monitor has ended.
        case removed
        /// Event access was withdrawn or became unavailable. The monitor has ended.
        case revoked
    }

    public struct Timing: Sendable, Equatable {
        /// Quiet time after the last change before one report is made.
        public var debounce: Duration
        /// Longest a continuous stream of changes may delay a report.
        public var maximumDelay: Duration
        /// Waits between attempts to re-open the path after the item disappeared. The first attempt is immediate.
        public var reopenDelays: [Duration]

        public init(debounce: Duration, maximumDelay: Duration, reopenDelays: [Duration]) {
            self.debounce = debounce
            self.maximumDelay = maximumDelay
            self.reopenDelays = reopenDelays
        }

        public static let standard = Timing(
            debounce: .milliseconds(300), maximumDelay: .seconds(2),
            reopenDelays: [10, 25, 50, 100, 200, 400, 800].map { Duration.milliseconds($0) })
    }

    /// Changes, coalesced. The stream finishes when the monitor ends or is stopped; only the latest unread
    /// report is kept, which suffices because every report means "read the item again".
    public let events: AsyncStream<Event>
    private let core: Core

    /// Starts watching `url`. Returns nil when the item is not a regular file or folder or cannot be opened
    /// for events, for example without permission; the preview itself is unaffected.
    public convenience init?(watching url: URL, timing: Timing = .standard) {
        self.init(watching: url, timing: timing, access: BoundedReadAccess())
    }

    init?(watching url: URL, timing: Timing = .standard, access: BoundedReadAccess,
          reopenScheduler: (any RequestTimerScheduling)? = nil) {
        guard let descriptor = try? PreviewMonitorDescriptor.open(watching: url, access: access) else { return nil }
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(1))
        let core = Core(url: url, timing: timing, continuation: continuation, access: access,
                        reopenScheduler: reopenScheduler)
        self.core = core
        events = stream
        // Cancelling the consuming task ends the stream and must release the descriptor too.
        continuation.onTermination = { _ in core.queue.async { core.shutdown() } }
        core.queue.sync { core.install(descriptor) }
    }

    /// Stops watching and closes the descriptor shortly afterwards. Safe to call more than once.
    public func stop() {
        let core = core
        core.queue.async { core.shutdown() }
    }

    /// Stops watching and returns once the descriptor is closed.
    public func stopAndWait() async {
        let core = core
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            core.queue.async {
                core.shutdown()
                core.whenDescriptorsClosed { continuation.resume() }
            }
        }
    }

    deinit {
        let core = core
        core.queue.async { core.shutdown() }
    }

    // Feed the same queued boundary as a kernel event; no caller may mutate Core off its queue.
    func receive(_ flags: DispatchSource.FileSystemEvent) async {
        let core = core
        let rawFlags = flags.rawValue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            core.queue.async {
                core.receive(DispatchSource.FileSystemEvent(rawValue: rawFlags))
                continuation.resume()
            }
        }
    }

    func waitForPendingOperations() async {
        let core = core
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            core.queue.async { continuation.resume() }
        }
    }

    /// Descriptors currently held by all monitors in this process, for leak checks.
    static var openDescriptorCount: Int { PreviewMonitorDescriptor.openCount.load(ordering: .acquiring) }
}

extension PreviewSourceMonitor {
    /// Dispatch sources need a serial queue; every field below is read and written only on `queue`, which is
    /// the documented invariant that makes this type safe to share (the Sendable conformance is therefore
    /// unchecked). Handlers run on `queue`, and the public entry points hop onto it.
    fileprivate final class Core: @unchecked Sendable {
        let queue: DispatchQueue
        private let access: BoundedReadAccess
        private let reopenScheduler: any RequestTimerScheduling
        private let url: URL
        private let timing: Timing
        private let continuation: AsyncStream<Event>.Continuation
        private var source: (any DispatchSourceFileSystemObject)?
        private var owner: PreviewMonitorDescriptor?
        private var liveDescriptors = 0
        private var isStopped = false
        private var pending: Event?
        private var burstStart: DispatchTime?
        private var debounceItem: DispatchWorkItem?
        private var reopenItem: RequestTimerHandle?
        private var closeWaiters: [() -> Void] = []

        init(url: URL, timing: Timing, continuation: AsyncStream<Event>.Continuation,
             access: BoundedReadAccess, reopenScheduler: (any RequestTimerScheduling)?) {
            let queue = DispatchQueue(label: "PreviewSourceMonitor", qos: .utility)
            self.queue = queue
            self.url = url
            self.timing = timing
            self.continuation = continuation
            self.access = access
            self.reopenScheduler = reopenScheduler ?? DispatchRequestScheduler(queue: queue)
        }

        // MARK: Queue-confined state machine

        func install(_ owner: PreviewMonitorDescriptor) {
            guard !isStopped, let descriptor = try? owner.fileDescriptor() else { owner.close(); return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete, .link, .revoke],
                queue: queue)
            liveDescriptors += 1
            source.setEventHandler { [self] in sourceFired() }
            // The descriptor must stay open until the kernel registration is gone, so it closes here.
            source.setCancelHandler { [self, owner] in
                owner.close()
                liveDescriptors -= 1
                if liveDescriptors == 0 { releaseWaiters() }
            }
            self.source = source
            self.owner = owner
            source.resume()
        }

        private func sourceFired() {
            guard !isStopped, let source else { return }
            receive(source.data)
        }

        func receive(_ flags: DispatchSource.FileSystemEvent) {
            guard !isStopped, source != nil else { return }
            if flags.contains(.revoke) { finish(with: .revoked); return }
            if flags.contains(.delete) || flags.contains(.rename) { detach(); return }
            guard let owner else { finish(with: .revoked); return }
            do { try owner.requireAvailable() }
            catch { finish(with: .revoked); return }
            note(.modified)
        }

        /// The watched vnode left its path. Atomic saves look exactly like this and are followed at once by a
        /// new file at the same path, so look for one before deciding the item is gone.
        private func detach() {
            closeSource()
            reopen(attempt: 0)
        }

        private func reopen(attempt: Int) {
            reopenItem = nil
            guard !isStopped else { return }
            do {
                let owner = try PreviewMonitorDescriptor.open(watching: url, access: access)
                install(owner)
                note(.replaced)
                return
            } catch let failure as PreviewFailure where failure == .unavailableContent {
                finish(with: .revoked)
                return
            } catch {} // Preserve bounded retries for other inability to watch.
            guard attempt < timing.reopenDelays.count else { finish(with: .removed); return }
            reopenItem = reopenScheduler.schedule(after: timing.reopenDelays[attempt]) { [self] in
                queue.async { [self] in reopen(attempt: attempt + 1) }
            }
        }

        /// Coalesces reports: one is made after `debounce` of quiet, or `maximumDelay` after the first change
        /// of a burst, whichever comes first. A replacement outranks plain modification.
        private func note(_ event: Event) {
            guard !isStopped else { return }
            if pending == nil || event == .replaced { pending = event }
            let now = DispatchTime.now()
            let start = burstStart ?? now
            burstStart = start
            let deadline = min(now + timing.debounce.dispatchInterval, start + timing.maximumDelay.dispatchInterval)
            debounceItem?.cancel()
            let item = DispatchWorkItem { [self] in flush() }
            debounceItem = item
            queue.asyncAfter(deadline: deadline, execute: item)
        }

        private func flush() {
            debounceItem = nil
            burstStart = nil
            guard !isStopped, let event = pending else { return }
            pending = nil
            continuation.yield(event)
        }

        /// A final report, then the end of the monitor. Earlier unreported changes are subsumed by it.
        private func finish(with event: Event) {
            guard !isStopped else { return }
            continuation.yield(event)
            shutdown()
        }

        private func closeSource() {
            guard let source else { return }
            self.source = nil
            source.cancel()
            owner = nil // Cancel handler retains ownership until kernel registration is gone.
        }

        func shutdown() {
            guard !isStopped else { return }
            isStopped = true
            debounceItem?.cancel(); debounceItem = nil
            reopenItem?.cancel(); reopenItem = nil
            pending = nil
            closeSource()
            continuation.finish()
            if liveDescriptors == 0 { releaseWaiters() }
        }

        func whenDescriptorsClosed(_ body: @escaping () -> Void) {
            if isStopped && liveDescriptors == 0 { body() } else { closeWaiters.append(body) }
        }

        private func releaseWaiters() {
            guard isStopped else { return }
            let waiters = closeWaiters
            closeWaiters = []
            for waiter in waiters { waiter() }
        }
    }
}

private extension Duration {
    var dispatchInterval: DispatchTimeInterval {
        let parts = components
        let nanoseconds = parts.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !nanoseconds.overflow else { return .nanoseconds(Int.max) }
        return .nanoseconds(Int(clamping: nanoseconds.partialValue + parts.attoseconds / 1_000_000_000))
    }
}
