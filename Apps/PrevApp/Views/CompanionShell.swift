import SwiftUI
import PreviewContracts
import PreviewCore
import PreviewRenderers

struct CompanionShell: View {
    let configuration: HostedConfiguration
    let settings: CompanionSettings
    let preferences: CompanionPreferences
    let updater: SparkleUpdater
    @Binding var route: CompanionRoute
    @CompanionState private var session: PreviewSession
    @CompanionState private var sampleSession: AppearanceSampleSession
    @CompanionState private var diagnostics: QuickLookProviderDiagnostics
    @CompanionState private var settingsObserver: UUID?
    @Environment(\.locale) private var locale
    /// The window's undo manager, which Edit > Undo and Edit > Redo drive.
    @Environment(\.undoManager) private var undoManager

    init(configuration: HostedConfiguration, settings: CompanionSettings, preferences: CompanionPreferences,
         updater: SparkleUpdater, pipeline: PreviewPipeline, route: Binding<CompanionRoute>) {
        self.configuration = configuration
        self.settings = settings
        self.preferences = preferences
        self.updater = updater
        _route = route
        _session = CompanionState(initialValue: PreviewSession(pipeline: pipeline))
        _sampleSession = CompanionState(initialValue: AppearanceSampleSession(pipeline: pipeline))
        // This app is never reported as another provider; the scan runs only when the user asks for it.
        let ownIdentifiers = Bundle.main.bundleIdentifier.map { Set([$0]) } ?? []
        _diagnostics = CompanionState(initialValue: QuickLookProviderDiagnostics(
            scanner: QuickLookProviderScanner(excludedBundleIdentifiers: ownIdentifiers)))
    }

    var body: some View {
        // A fixed sidebar is the only navigation, so it cannot be collapsed or resized away.
        HStack(spacing: 0) {
            CompanionSidebar(configuration: configuration, settings: settings, route: $route)
                .frame(width: CompanionMetrics.sidebarWidth)
            Divider().ignoresSafeArea()
            content(for: route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        // The hidden title bar draws no title, but the Window menu, Mission Control and VoiceOver read it.
        .navigationTitle(windowTitle)
        .focusedSceneValue(\.previewSession, session)
        .fileImporter(isPresented: $session.presentsFileImporter,
                      allowedContentTypes: FormatCatalog.standard.descriptors.flatMap(\.contentTypes)) { result in
            switch result {
            case .success(let url):
                route = .tryPreview
                session.open(url, preferences: settings.snapshot)
            case .failure(let error):
                route = .tryPreview
                session.fileImporterFailed(error: error)
            }
        }
        .task { await settings.load() }
        // The window opens on the page it was left on.
        .onChange(of: route) { preferences.setLastRoute(route) }
        .onChange(of: undoManager) { settings.attachUndoManager(undoManager) }
        .onAppear {
            settings.attachUndoManager(undoManager)
            settings.setAnnouncer { text in CompanionAnnouncer.announce(text) }
            if settingsObserver == nil {
                settingsObserver = settings.observe { [weak session = session] snapshot in
                    session?.settingsChanged(snapshot)
                }
            }
        }
        .onDisappear {
            session.cancel()
            sampleSession.close()
            diagnostics.cancel()
            if let settingsObserver { settings.removeObserver(settingsObserver) }
            settingsObserver = nil
        }
    }

    /// The page that is showing, then the app, so the window is named after what it shows.
    private var windowTitle: String {
        route.windowTitle(appName: configuration.displayName, locale: locale)
    }

    private var overlappingProvidersByFormat: [FormatID: [String]] {
        guard case .finished(let report) = diagnostics.state else { return [:] }
        var map: [FormatID: [String]] = [:]
        for provider in report.providers {
            for formatID in provider.overlappingFormats {
                map[formatID, default: []].append(provider.name)
            }
        }
        return map
    }

    @ViewBuilder private func content(for route: CompanionRoute) -> some View {
        switch route {
        case .general:
            GeneralView(configuration: configuration, settings: settings,
                        diagnostics: diagnostics)
        case .fileTypes:
            FileTypeSettingsView(settings: settings, overlappingProvidersByFormat: overlappingProvidersByFormat)
        case .theme: AppearanceSettingsView(settings: settings, sample: sampleSession)
        case .about: AboutView(configuration: configuration, updater: updater)
        case .tryPreview:
            DirectPreviewView(session: session, settings: settings,
                              overlappingProvidersByFormat: overlappingProvidersByFormat)
        }
    }
}
