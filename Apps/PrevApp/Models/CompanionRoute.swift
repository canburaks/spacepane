import SwiftUI
import PreviewRenderers

/// The raw values are stored in the companion's defaults (`companion.lastRoute`), so renaming one makes the
/// window forget the page it was left on.
enum CompanionRoute: String, CaseIterable, Identifiable {
    case general, fileTypes, theme, about, tryPreview
    var id: Self { self }

    /// Developer destinations stay out of the sidebar, menus and shortcuts until Developer Mode is on.
    var requiresDeveloperMode: Bool { self == .tryPreview }

    static func available(developerMode: Bool) -> [Self] {
        allCases.filter { developerMode || !$0.requiresDeveloperMode }
    }

    /// A destination that is no longer offered resolves to the first page.
    func resolved(developerMode: Bool) -> Self {
        requiresDeveloperMode && !developerMode ? .general : self
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .general: "1"
        case .fileTypes: "2"
        case .theme: "3"
        case .about: "4"
        case .tryPreview: "5"
        }
    }
    var title: PreviewStrings.Key {
        switch self {
        case .general: .navigationGeneral
        case .fileTypes: .fileTypes
        case .theme: .navigationTheme
        case .about: .navigationAbout
        case .tryPreview: .tryPreview
        }
    }
    var symbol: CompanionSymbol {
        switch self {
        case .general: .general
        case .fileTypes: .fileTypes
        case .theme: .theme
        case .about: .about
        case .tryPreview: .tryPreview
        }
    }

    /// The window's title: the page, then the app, so the Window menu, Mission Control and VoiceOver name
    /// the page that is showing.
    func windowTitle(appName: String, locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
        PreviewStrings.format(.windowTitle,
                              arguments: [PreviewStrings.text(title, languagePreferences: languagePreferences), appName],
                              locale: locale, languagePreferences: languagePreferences)
    }
}

enum CompanionSceneID: String {
    case main = "companion.main"
}
