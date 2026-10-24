import SwiftUI
import PreviewRenderers

/// The raw values are stored in the companion's defaults (`companion.lastRoute`), so renaming one makes the
/// window forget the page it was left on.
enum CompanionRoute: String, CaseIterable, Identifiable {
    case general, fileTypes, theme, about, tryPreview
    var id: Self { self }

    // Every destination is always offered: the sidebar, the View menu and Command-1 to Command-5 list the same
    // five pages, and nothing is revealed by a setting (App Review Guidelines 2.5.19 and 5.6).

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
