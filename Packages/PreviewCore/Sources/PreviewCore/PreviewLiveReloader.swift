import Foundation
import PreviewContracts

/// What one live reload produced. The host decides how to present each case.
public enum LiveReloadResult: Sendable, Equatable {
    /// The pipeline's outcome for the changed item, with the preference snapshot it was run under.
    case preview(PreviewOutcome, PreviewPreferencesSnapshot)
    /// A result-bearing reload retains the effective budget; the outcome-only case remains compatible.
    case result(PreviewResult, PreviewPreferencesSnapshot)
    /// The shared settings could not be read, so no preview can be made under a known policy.
    case settingsUnavailable
    /// The user turned live reload off since this preview was opened.
    case disabled
}

/// Re-runs a preview when its file changes, for as long as the preview is shown.
///
/// One reloader owns one monitor and at most one reload in flight. Each change cancels the reload before it
/// and bumps a generation, so a slow reload that finishes after a newer change, after `stop()`, or after the
/// reloader moved to another file is dropped and can never replace newer content. The host supplies `load`
/// (which reads a fresh preference snapshot and runs its pipeline) and `apply`, and decides where the
/// resulting presentation goes; the reloader never touches the file and holds no preview content.
@MainActor
public final class PreviewLiveReloader {
    public typealias Load = @Sendable (URL) async -> LiveReloadResult

    private let timing: PreviewSourceMonitor.Timing
    private let load: Load
    private let apply: @MainActor (LiveReloadResult) -> Void
    private let monitorFactory: @Sendable (URL, PreviewSourceMonitor.Timing) -> (any PreviewSourceWatching)?
    private var monitor: (any PreviewSourceWatching)?
    private var observer: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var url: URL?
    private var generation = 0

    public convenience init(timing: PreviewSourceMonitor.Timing = .standard, load: @escaping Load,
                            apply: @escaping @MainActor (LiveReloadResult) -> Void) {
        self.init(timing: timing, load: load, apply: apply,
                  monitorFactory: { PreviewSourceMonitor(watching: $0, timing: $1) })
    }

    init(timing: PreviewSourceMonitor.Timing = .standard, load: @escaping Load,
         apply: @escaping @MainActor (LiveReloadResult) -> Void,
         monitorFactory: @escaping @Sendable (URL, PreviewSourceMonitor.Timing) -> (any PreviewSourceWatching)?) {
        self.timing = timing
        self.load = load
        self.apply = apply
        self.monitorFactory = monitorFactory
    }

    isolated deinit { stop() }

    public var isWatching: Bool { monitor != nil }

    /// Whether an outcome belongs to a file worth watching. A shown preview and a failure that the file itself
    /// can cure (too large, unreadable, malformed) are; a missing file, an unsupported or disabled type and a
    /// cancelled request or unavailable source bytes are not. Missing bytes need an explicit new request.
    public nonisolated static func watches(_ outcome: PreviewOutcome) -> Bool {
        switch outcome {
        case .ready, .geometryReady: true
        case .unavailable(let failure): failure != .missingFile && failure != .unsupportedFormat && failure != .unavailableContent
        case .disabledByUser, .cancelled: false
        }
    }

    /// Starts watching `url`, replacing any earlier watch. Returns false (and watches nothing) when the item
    /// cannot be watched; callers keep their current preview either way. The caller keeps file access valid
    /// for as long as the watch lasts, because re-opening after a replacement needs it.
    @discardableResult
    public func start(watching url: URL) -> Bool {
        stop()
        guard let monitor = monitorFactory(url, timing) else { return false }
        self.monitor = monitor
        self.url = url
        observer = Task { @MainActor [weak self] in
            for await event in monitor.events {
                guard !Task.isCancelled, let self else { return }
                self.handle(event, from: monitor)
            }
        }
        return true
    }

    /// Reloads once now, for example when the preview becomes visible again after changes may have been missed.
    public func reloadNow() {
        guard monitor != nil else { return }
        reload(final: false)
    }

    /// Stops watching and abandons any reload in flight.
    public func stop() {
        generation &+= 1
        reloadTask?.cancel()
        reloadTask = nil
        releaseMonitor()
        url = nil
    }

    private func handle(_ event: PreviewSourceMonitor.Event, from source: any PreviewSourceWatching) {
        // A report from a monitor this reloader has already left must not trigger a reload.
        guard monitor === source else { return }
        reload(final: event == .removed || event == .revoked)
    }

    /// `final` marks the report that ended the monitor: its reload still runs, to show the item's last state.
    private func reload(final: Bool) {
        guard let url else { return }
        generation &+= 1
        let current = generation
        reloadTask?.cancel()
        let load = load
        reloadTask = Task { [weak self] in
            let result = await load(url)
            guard let self, !Task.isCancelled, generation == current else { return }
            reloadTask = nil
            switch result {
            case .preview(let outcome, _): if final || !Self.watches(outcome) { releaseMonitor() }
            case .result(let result, _): if final || !Self.watches(result.outcome) { releaseMonitor() }
            case .settingsUnavailable, .disabled: releaseMonitor()
            }
            apply(result)
        }
    }

    // Read-only completion boundary; deterministic tests await a captured task after stop/replacement.
    func pendingReloadCompletion() -> Task<Void, Never>? { reloadTask }

    private func releaseMonitor() {
        observer?.cancel()
        observer = nil
        monitor?.stop()
        monitor = nil
    }
}
