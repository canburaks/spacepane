import SwiftUI
import PreviewContracts
import PreviewCore
import PreviewRenderers

struct CompanionShell: View {
    let configuration: HostedConfiguration
    let settings: CompanionSettings
    let preferences: CompanionPreferences
    @Binding var route: CompanionRoute
    @CompanionState private var session: PreviewSession
    @CompanionState private var sampleSession: AppearanceSampleSession
    @CompanionState private var diagnostics: QuickLookProviderDiagnostics
    @CompanionState private var settingsObserver: UUID?
    @Environment(\.locale) private var locale
    /// The window's undo manager, which Edit > Undo and Edit > Redo drive.
    @Environment(\.undoManager) private var undoManager

    init(configuration: HostedConfiguration, settings: CompanionSettings, preferences: CompanionPreferences,
         pipeline: PreviewPipeline, route: Binding<CompanionRoute>) {
        self.configuration = configuration
        self.settings = settings
        self.preferences = preferences
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
            CompanionSidebar(configuration: configuration, settings: settings,
                             developerMode: preferences.developerMode, route: $route)
                .frame(width: CompanionMetrics.sidebarWidth)
            Divider().ignoresSafeArea()
            content(for: route.resolved(developerMode: preferences.developerMode))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        // The hidden title bar draws no title, but the Window menu, Mission Control and VoiceOver read it.
        .navigationTitle(windowTitle)
        .focusedSceneValue(\.previewSession, session)
        .fileImporter(isPresented: $session.presentsFileImporter,
                      allowedContentTypes: FormatCatalog.standard.descriptors.flatMap(\.contentTypes)) { result in
            // A picker requested before Developer Mode was turned off must not reveal its destination.
            guard preferences.developerMode else { return }
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
        .onChange(of: preferences.developerMode) {
            route = route.resolved(developerMode: preferences.developerMode)
            // A hidden destination must not keep a file that a later settings change would reread.
            if !preferences.developerMode { session.close() }
        }
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
        route.resolved(developerMode: preferences.developerMode)
            .windowTitle(appName: configuration.displayName, locale: locale)
    }

    @ViewBuilder private func content(for route: CompanionRoute) -> some View {
        switch route {
        case .general:
            GeneralView(configuration: configuration, settings: settings, preferences: preferences,
                        diagnostics: diagnostics)
        case .fileTypes: FileTypeSettingsView(settings: settings)
        case .theme: AppearanceSettingsView(settings: settings, sample: sampleSession)
        case .about: AboutView(configuration: configuration, developerMode: preferences.developerMode)
        case .tryPreview: DirectPreviewView(session: session, settings: settings)
        }
    }
}
