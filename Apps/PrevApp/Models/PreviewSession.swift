import Foundation
import Observation
import PreviewContracts
import PreviewCore

@MainActor @Observable
final class PreviewSession {
    var presentsFileImporter = false
    private(set) var sourceURL: URL?
    private(set) var result: PreviewResult?
    var outcome: PreviewOutcome? { result?.outcome }
    /// Identifies one request. A live reload keeps it, so the pane keeps the reader's place; every new
    /// request, including one for the same file, replaces it.
    private(set) var generation = UUID()
    private(set) var isLoading = false
    private(set) var pickerFailed = false
    /// Counts every failed pick, so the page can announce each one even when `pickerFailed` was already set.
    private(set) var pickerFailureCount = 0
    @ObservationIgnored private let pipeline: PreviewPipeline
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let startWatching: @MainActor (PreviewLiveReloader, URL) -> Bool
    /// Snapshot for deterministic request-lifetime checks; awaiting it never starts work.
    var currentRequest: Task<Void, Never>? { task }
    @ObservationIgnored private var recognizedFormat: FormatID?
    @ObservationIgnored private var requestPreferences: PreviewPreferencesSnapshot?
    /// The latest snapshot the companion reported, which a live reload runs under (never an older copy).
    @ObservationIgnored private var latestPreferences = PreviewPreferencesSnapshot.defaults
    /// The preview is only live while its page is on screen.
    @ObservationIgnored private var isPreviewVisible = true
    @ObservationIgnored private var liveReloader: PreviewLiveReloader?
    /// Holds the file's security scope for as long as it is watched: re-opening it after an atomic save needs it.
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var monitorStartFailed = false

    init(pipeline: PreviewPipeline,
         startWatching: @escaping @MainActor (PreviewLiveReloader, URL) -> Bool = { $0.start(watching: $1) }) {
        self.pipeline = pipeline
        self.startWatching = startWatching
    }

    isolated deinit { task?.cancel(); stopLiveReload() }

    func open(_ url: URL, preferences: PreviewPreferencesSnapshot) {
        sourceURL = url
        recognizedFormat = nil
        pickerFailed = false
        latestPreferences = preferences
        reload(preferences: preferences)
    }

    func settingsChanged(_ preferences: PreviewPreferencesSnapshot) {
        latestPreferences = preferences
        guard sourceURL != nil else { return }
        // Presentation observes typography/theme directly. Only a policy change or a change in what
        // an adapter reads (folder depth, hidden items) replaces the content request, so appearance
        // edits preserve selection and I/O.
        guard requestPreferences?.defaultEnabled != preferences.defaultEnabled
                || requestPreferences?.formatOverrides != preferences.formatOverrides
                || requestPreferences?.requestOptions != preferences.requestOptions else {
            // The reload switch may still have flipped.
            updateLiveReload()
            return
        }
        reload(preferences: preferences)
    }

    /// Tells the session whether its preview page is on screen. Reloading stops while it is hidden and, on
    /// return, the file is shown again in case it changed meanwhile.
    func previewVisibilityChanged(_ isVisible: Bool) {
        guard isVisible != isPreviewVisible else { return }
        isPreviewVisible = isVisible
        if isVisible {
            updateLiveReload()
            liveReloader?.reloadNow()
        } else {
            stopLiveReload()
        }
    }

    func fileImporterFailed(error: any Error) {
        // Dismissing the system picker does not replace an existing or pending preview.
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { return }
        cancel()
        sourceURL = nil
        recognizedFormat = nil
        pickerFailed = true
        pickerFailureCount += 1
    }

    func cancel() {
        task?.cancel()
        task = nil
        stopLiveReload()
        generation = UUID()
        result = nil
        isLoading = false
    }

    /// Forgets the file as well as its request, so a later settings change cannot read it again.
    func close() {
        cancel()
        sourceURL = nil
        recognizedFormat = nil
        requestPreferences = nil
        pickerFailed = false
        presentsFileImporter = false
    }

    private func reload(preferences: PreviewPreferencesSnapshot) {
        requestPreferences = preferences
        monitorStartFailed = false
        let knownFormat = recognizedFormat
        cancel()
        guard let url = sourceURL else { return }
        if let knownFormat, !preferences.isEnabled(knownFormat) {
            result = PreviewResult(outcome: .disabledByUser(knownFormat))
            return
        }
        isLoading = true
        let requestGeneration = generation
        let pipeline = pipeline
        task = Task { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result = await pipeline.previewResult(url: url, preferences: preferences)
            guard let self, !Task.isCancelled, generation == requestGeneration else { return }
            record(result)
            isLoading = false
            task = nil
            updateLiveReload()
        }
    }

    private func record(_ result: PreviewResult) {
        self.result = result
        switch result.outcome {
        case .ready(let presentation): recognizedFormat = presentation.formatID
        case .geometryReady(let presentation): recognizedFormat = presentation.formatID
        case .disabledByUser(let id): recognizedFormat = id
        case .unavailable, .cancelled: recognizedFormat = nil
        }
    }

    // MARK: Live reload

    /// Watches the file exactly when reloading is on, the preview page is visible, the first request has
    /// finished and the shown outcome is one a file change could alter. Otherwise nothing is watched.
    private func updateLiveReload() {
        let wanted = !monitorStartFailed && sourceURL != nil && task == nil && isPreviewVisible && latestPreferences.reloadsOnFileChange
            && outcome.map(PreviewLiveReloader.watches) == true
        if !wanted { stopLiveReload() }
        else if liveReloader?.isWatching != true { startLiveReload() }
    }

    private func startLiveReload() {
        guard let url = sourceURL else { return }
        stopLiveReload()
        let scoped = url.startAccessingSecurityScopedResource()
        let pipeline = pipeline
        let reloader = PreviewLiveReloader(load: { [weak self] url in
            // The newest snapshot, so a reload follows policy and appearance changes made since opening.
            guard let preferences = await self?.currentPreferences(), preferences.reloadsOnFileChange else { return .disabled }
            return .result(await pipeline.previewResult(url: url, preferences: preferences), preferences)
        }, apply: { [weak self] result in
            self?.applyReload(result)
        })
        guard startWatching(reloader, url) else {
            monitorStartFailed = true
            if scoped { url.stopAccessingSecurityScopedResource() }
            return
        }
        liveReloader = reloader
        scopedURL = scoped ? url : nil
    }

    private func currentPreferences() -> PreviewPreferencesSnapshot { latestPreferences }

    private func applyReload(_ result: LiveReloadResult) {
        switch result {
        case .preview(let reloaded, let preferences):
            // The same request: the generation stays, so the pane keeps mode, scroll position and selection.
            requestPreferences = preferences
            record(PreviewResult(outcome: reloaded))
        case .result(let reloaded, let preferences):
            requestPreferences = preferences
            record(reloaded)
        case .settingsUnavailable, .disabled:
            break
        }
        // A deleted file ends its own watch; release the scope with it.
        if liveReloader?.isWatching != true { stopLiveReload() }
    }

    private func stopLiveReload() {
        liveReloader?.stop()
        liveReloader = nil
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil
    }
}
