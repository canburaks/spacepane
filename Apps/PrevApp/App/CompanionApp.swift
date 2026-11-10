import SwiftUI
import PreviewContracts
import PreviewCore
import PreviewFormats
#if PREV_INCLUDE_CAD
import PreviewCADFormats
#endif
import PreviewRenderers

@main
struct CompanionApp: App {
    private let configuration = HostedConfiguration()
    private let pipeline = PreviewPipeline(registrations: Self.adapterRegistrations)
    @CompanionState private var settings: CompanionSettings
    @CompanionState private var preferences: CompanionPreferences
    @CompanionState private var updater: SparkleUpdater
    @CompanionState private var route: CompanionRoute
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate

    /// The standard adapters. Version 1.0 ships without the STEP and IGES previews: the CAD adapters are registered
    /// only in a build with `PREV_INCLUDE_CAD` (which also needs the two CAD catalog entries back in the catalog).
    private static var adapterRegistrations: [AdapterRegistration] {
        #if PREV_INCLUDE_CAD
        StandardFormatAdapters.registrations + CADFormatAdapters.registrations
        #else
        StandardFormatAdapters.registrations
        #endif
    }

    init() {
        let savedPreferences = CompanionPreferences()
        _settings = State(initialValue: CompanionSettings(configuration: HostedConfiguration()))
        _preferences = State(initialValue: savedPreferences)
        _updater = State(initialValue: SparkleUpdater())
        // The window opens on the page it was left on, unless that page is no longer offered.
        _route = State(initialValue: savedPreferences.restoredRoute)
    }

    var body: some Scene {
        Window(configuration.displayName, id: CompanionSceneID.main.rawValue) {
            CompanionShell(configuration: configuration, settings: settings, preferences: preferences,
                           updater: updater, pipeline: pipeline, route: $route)
                .flushesSaveWhenInactive(settings)
                .onAppear { appDelegate.settings = settings }
        }
        // The sidebar and page headings carry the title; the window keeps its name for the system.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)
        .defaultLaunchBehavior(.presented)
        .commands {
            CompanionCommands(configuration: configuration, updater: updater, route: $route)
        }
    }
}

private struct CompanionCommands: Commands {
    let configuration: HostedConfiguration
    let updater: SparkleUpdater
    @Binding var route: CompanionRoute
    @FocusedValue(\.previewSession) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(PreviewStrings.text(.openFile)) {
                route = .tryPreview
                session?.presentsFileImporter = true
            }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(session == nil)
        }
        // The standard macOS title and shortcut. Settings live on the pages of this one window, so this opens
        // General, the page that sets the app up; it never creates a Settings window.
        CommandGroup(replacing: .appSettings) {
            Button(PreviewStrings.text(.settingsMenu)) { select(.general) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            ForEach(CompanionRoute.allCases) { destination in
                Button(PreviewStrings.text(destination.title)) { select(destination) }
                    .keyboardShortcut(destination.shortcutKey, modifiers: .command)
            }
        }
        CommandGroup(replacing: .appInfo) {
            Button(PreviewStrings.format(.aboutApp, arguments: [configuration.displayName], locale: locale)) {
                select(.about)
            }
            #if PREV_INCLUDE_SPARKLE
            Button(PreviewStrings.text(.checkForUpdates)) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            #endif
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
