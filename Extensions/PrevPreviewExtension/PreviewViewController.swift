import AppKit
import QuickLookUI
import PreviewContracts
import PreviewCore
import PreviewFileAccess
import PreviewFormats
#if PREV_INCLUDE_CAD
import PreviewCADFormats
#endif
import PreviewPreferences
import PreviewRenderers

@MainActor
final class PreviewViewController: NSViewController, @MainActor QLPreviewingController {
    private let pipeline = PreviewPipeline(registrations: PreviewViewController.adapterRegistrations)
    /// The standard adapters. Version 1.0 ships without the STEP and IGES previews: the CAD adapters, which reach
    /// their importer through the embedded XPC service, are registered only in a build with `PREV_INCLUDE_CAD`.
    private static var adapterRegistrations: [AdapterRegistration] {
        #if PREV_INCLUDE_CAD
        StandardFormatAdapters.registrations + CADFormatAdapters.xpcRegistrations
        #else
        StandardFormatAdapters.registrations
        #endif
    }
    private var activeRequest: PreviewHostSession<PreparedPreview>?
    /// The shown file and the settings that governed it, kept while the view is hidden so a view that
    /// appears again can resume live reload. Cleared by every new request.
    private var liveSource: LiveSource?
    private var liveReloader: PreviewLiveReloader?
    var startWatching: @MainActor (PreviewLiveReloader, URL) -> Bool = { $0.start(watching: $1) }
    private var previewView: NativePreviewView { view as! NativePreviewView }

    isolated deinit { cancelActiveRequest(); stopLiveReload() }

    override func loadView() {
        let content = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        // Quick Look embeds a remote view; its backing window's occlusion state
        // does not describe whether Finder is presenting the content.
        content.resourceVisibility = .hostManaged
        content.suspendResources()
        content.providerName = HostedConfiguration().displayName
        // Finder sends typed keys to its own file list, never to the extension: offer no typed filter or find.
        content.acceptsTypedInput = false
        view = content
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Establish the process default before any request metadata, preferences or source work.
        // Each raw I/O boundary also uses its checked synchronous thread scope.
        let fileAccessAllowed = (try? DatalessFiles.refuseMaterializationForProcess()) != nil
        cancelActiveRequest()
        stopLiveReload()
        liveSource = nil
        loadViewIfNeeded()
        previewView.showLoading()
        let trace = PreviewHostTrace(surface: .preview, geometry: hostGeometry)
        guard fileAccessAllowed else {
            previewView.display(PreviewResult(outcome: .unavailable(.unavailableContent)))
            trace.finish(.unavailable, geometry: hostGeometry)
            handler(nil)
            return
        }
        let configuration = HostedConfiguration()
        guard let preferencesURL = PreferencesLocation.appGroupSnapshotURL(identifier: configuration.appGroupIdentifier) else {
            previewView.showSettingsConfigurationUnavailable()
            trace.settings(.unconfigured)
            trace.finish(.configurationUnavailable, geometry: hostGeometry)
            handler(nil)
            return
        }
        let requestID = UUID()
        let request = PreviewHostSession<PreparedPreview>(id: requestID) { [weak self] delivery in
            guard let self, activeRequest?.id == requestID else {
                trace.finish(.cancelled)
                handler(CocoaError(.userCancelled))
                return
            }
            activeRequest = nil
            switch delivery {
            case .cancelled:
                trace.finish(.cancelled, geometry: hostGeometry)
                handler(CocoaError(.userCancelled))
            case .timedOut:
                // The host ceiling is separate from the selected adapter budget. No invented
                // family limit is shown, and a late read cannot replace this terminal state.
                previewView.display(PreviewResult(outcome: .unavailable(.deadlineExceeded)))
                trace.finish(.timedOut, geometry: hostGeometry)
                handler(nil)
            case .completed(.settingsUnavailable):
                previewView.showSettingsUnavailable()
                trace.finish(.settingsUnavailable, geometry: hostGeometry)
                handler(nil)
            case .completed(.preview(let result, let preferences)):
                previewView.display(result, typography: preferences.typography, theme: preferences.theme, syntaxStyle: preferences.syntaxStyle)
                trace.finish(PreviewHostOutcome(result.outcome), geometry: hostGeometry)
                if preferences.reloadsOnFileChange, PreviewLiveReloader.watches(result.outcome) {
                    beginLiveReload(LiveSource(url: url, preferencesURL: preferencesURL))
                }
                handler(nil)
            }
        }
        activeRequest = request
        let pipeline = pipeline
        request.start {
            let loaded = await PreferenceStore(url: preferencesURL).load()
            switch loaded.state {
            case .corrupt, .unreadable, .unsupportedVersion:
                trace.settings(.unavailable)
                return .settingsUnavailable
            case .defaults: trace.settings(.defaults)
            case .loaded: trace.settings(.loaded)
            case .migrated: trace.settings(.migrated)
            }
            return .preview(await pipeline.previewResult(url: url, preferences: loaded.snapshot), loaded.snapshot)
        }
    }

    private var hostGeometry: PreviewHostGeometry? {
        PreviewHostGeometry(width: view.bounds.width, height: view.bounds.height)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if isViewLoaded { previewView.resumeResources() }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if isViewLoaded { previewView.resumeResources() }
        // Changes made while the view was hidden were not watched: show the current file again.
        if let source = liveSource, liveReloader == nil, activeRequest == nil {
            beginLiveReload(source)
            liveReloader?.reloadNow()
        }
    }

    override func viewWillDisappear() {
        if isViewLoaded { previewView.suspendResources() }
        cancelActiveRequest()
        // Reload only while the preview is shown.
        stopLiveReload()
        super.viewWillDisappear()
    }

    private func cancelActiveRequest() {
        guard let request = activeRequest else { return }
        activeRequest = nil
        request.cancel()
    }

    // MARK: Live reload

    struct LiveSource {
        let url: URL
        let preferencesURL: URL
    }

    private enum PreparedPreview: Sendable {
        case settingsUnavailable
        case preview(PreviewResult, PreviewPreferencesSnapshot)
    }

    /// Watches the shown file. Every reload reads the settings again, so a changed appearance or a turned-off
    /// switch applies without reopening the preview. Nothing is watched when the file cannot be opened for events.
    func beginLiveReload(_ source: LiveSource) {
        let pipeline = pipeline
        let reloader = PreviewLiveReloader(load: { url in
            let loaded = await PreferenceStore(url: source.preferencesURL).load()
            switch loaded.state {
            case .corrupt, .unreadable, .unsupportedVersion: return .settingsUnavailable
            case .defaults, .loaded, .migrated: break
            }
            guard loaded.snapshot.reloadsOnFileChange else { return .disabled }
            return .result(await pipeline.previewResult(url: url, preferences: loaded.snapshot), loaded.snapshot)
        }, apply: { [weak self] result in
            self?.applyReload(result)
        })
        let started = startWatching(reloader, source.url)
        liveReloader = started ? reloader : nil
        liveSource = started ? source : nil
    }

    func applyReload(_ result: LiveReloadResult) {
        switch result {
        case .preview(let outcome, let preferences):
            // Not a new request: keep the mode, scroll position, selection and zoom where they still apply.
            previewView.display(outcome, typography: preferences.typography, theme: preferences.theme,
                                syntaxStyle: preferences.syntaxStyle, resetsContentState: false)
        case .result(let result, let preferences):
            previewView.display(result, typography: preferences.typography, theme: preferences.theme,
                                syntaxStyle: preferences.syntaxStyle, resetsContentState: false)
        case .settingsUnavailable:
            previewView.showSettingsUnavailable()
        case .disabled:
            break
        }
        // A terminal reload cannot leave a hidden-view hint that later restarts its watch.
        if liveReloader?.isWatching != true {
            liveSource = nil
            stopLiveReload()
        }
    }

    private func stopLiveReload() {
        liveReloader?.stop()
        liveReloader = nil
    }
}
