import SwiftUI
import PreviewCore
import PreviewFormats
import PreviewCADFormats
import PreviewRenderers

@main
struct CompanionApp: App {
    private let configuration = HostedConfiguration()
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations + CADFormatAdapters.registrations)
    @CompanionState private var settings: CompanionSettings
    @CompanionState private var preferences: CompanionPreferences
    @CompanionState private var route: CompanionRoute

    init() {
        let savedPreferences = CompanionPreferences()
        _settings = State(initialValue: CompanionSettings(configuration: HostedConfiguration()))
        _preferences = State(initialValue: savedPreferences)
        // The window opens on the page it was left on, unless that page is no longer offered.
        _route = State(initialValue: savedPreferences.restoredRoute)
    }

    var body: some Scene {
        Window(configuration.displayName, id: CompanionSceneID.main.rawValue) {
            CompanionShell(configuration: configuration, settings: settings, preferences: preferences,
                           pipeline: pipeline, route: $route)
                .flushesSaveWhenInactive(settings)
        }
        // The sidebar and page headings carry the title; the window keeps its name for the system.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)
        .defaultLaunchBehavior(.presented)
        .commands {
            CompanionCommands(configuration: configuration, route: $route, developerMode: preferences.developerMode)
        }
    }
}

private struct CompanionCommands: Commands {
    let configuration: HostedConfiguration
    @Binding var route: CompanionRoute
    /// Passed by value from the scene so menus follow the saved choice.
    let developerMode: Bool
    @FocusedValue(\.previewSession) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if developerMode {
                Button(PreviewStrings.text(.openFile)) {
                    route = .tryPreview
                    session?.presentsFileImporter = true
                }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(session == nil)
            }
        }
        // The standard macOS title and shortcut. Settings live on the pages of this one window, so this opens
        // General, the page that sets the app up; it never creates a Settings window.
        CommandGroup(replacing: .appSettings) {
            Button(PreviewStrings.text(.settingsMenu)) { select(.general) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            ForEach(CompanionRoute.available(developerMode: developerMode)) { destination in
                Button(PreviewStrings.text(destination.title)) { select(destination) }
                    .keyboardShortcut(destination.shortcutKey, modifiers: .command)
            }
        }
        CommandGroup(replacing: .appInfo) {
            Button(PreviewStrings.format(.aboutApp, arguments: [configuration.displayName], locale: locale)) {
                select(.about)
            }
        }
        // The short help section sits on the About page, inside the same window.
        CommandGroup(replacing: .help) {
            Button(PreviewStrings.format(.helpApp, arguments: [configuration.displayName], locale: locale)) {
                select(.about)
            }
        }
    }

    private func select(_ route: CompanionRoute) {
        self.route = route
        // Target the singleton scene; never create an auxiliary content window.
        openWindow(id: CompanionSceneID.main.rawValue)
    }
}
