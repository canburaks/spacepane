import Foundation
import PreviewRenderers

/// What the sidebar footer and the General page say about where settings are kept and whether the last save
/// worked. It states storage facts the app has verified and nothing else: never that the extensions are on and
/// never that Finder uses this provider. There is no positive tone, because the app has no signal that
/// could earn one.
struct SettingsStatus: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case neutral, caution }

    let tone: Tone
    /// One short sentence for the footer.
    let titleKey: PreviewStrings.Key
    /// The longer sentence of every verified problem, most important first; empty exactly when the tone is neutral.
    /// The General banner states the storage problems (settings kept for this app only, storage unavailable) with
    /// these same sentences, so the page shows a problem once.
    let problemKeys: [PreviewStrings.Key]

    init(storage: CompanionSettings.StorageMode, save: CompanionSettings.SaveState, recovered: Bool, isLoading: Bool) {
        var problems: [PreviewStrings.Key] = []
        let title: PreviewStrings.Key
        if isLoading {
            title = .statusLoading
        } else {
            if recovered { problems.append(.settingsRecovery) }
            if storage == .unavailable { problems.append(.storageUnavailable) }
            // Without storage every change reports a failed save, which the storage line already says.
            if save == .failed, storage != .unavailable { problems.append(.settingsSaveFailed) }
            if storage == .privateOnly { problems.append(.setupNotConfigured) }
            if recovered {
                title = .statusRecovered
            } else if storage == .unavailable {
                title = .statusUnavailable
            } else if save == .failed {
                title = .statusSaveFailed
            } else if storage == .privateOnly {
                title = .statusAppOnly
            } else {
                switch save {
                case .idle: title = .statusShared
                case .saving: title = .settingsSaving
                case .saved: title = .settingsSaved
                case .failed: title = .statusSaveFailed
                }
            }
        }
        titleKey = title
        problemKeys = problems
        tone = problems.isEmpty ? .neutral : .caution
    }
}

extension SettingsStatus {
    /// What a person can do about a problem the status reports.
    enum Action: Equatable, Sendable {
        case tryAgain, restoreDefaults

        var titleKey: PreviewStrings.Key {
            switch self {
            case .tryAgain: .tryAgain
            case .restoreDefaults: .restoreDefaults
            }
        }
    }

    /// The action that deals with `problem`, when there is one. A failed save can be tried again and an unusable
    /// settings file can be replaced by the defaults; missing storage has nothing to offer.
    static func action(for problem: PreviewStrings.Key) -> Action? {
        switch problem {
        case .settingsSaveFailed: .tryAgain
        case .settingsRecovery: .restoreDefaults
        default: nil
        }
    }

    /// The one problem the pages that edit settings (File Types and Theme) show: a reset file, then missing
    /// storage, then a failed save. App-only storage is General's matter and is not shown there.
    var editingProblem: PreviewStrings.Key? {
        problemKeys.first { $0 != .setupNotConfigured }
    }
}

extension CompanionSettings {
    /// The one status every surface shows, derived from what the store knows.
    var status: SettingsStatus {
        SettingsStatus(storage: storageMode, save: saveState, recovered: recoveredSettings, isLoading: isLoading)
    }
}

/// Opening System Settings from the General page. macOS reports only that some handler accepted the link, never
/// that the Login Items & Extensions pane is showing, so the page cannot call the attempt a success; it shows the
/// manual route after every attempt instead. The workspace calls are injected so a check never opens a window.
enum SystemSettingsOpening {
    enum Result: Equatable, Sendable {
        /// The link was accepted. System Settings opens, but the pane it shows is not confirmed.
        case linkAccepted
        /// The link was refused and System Settings was opened without a pane.
        case applicationOnly
        /// Neither opened.
        case failed
    }

    static func open(link: URL?, openLink: (URL) -> Bool, applicationURL: () -> URL?,
                     openApplication: (URL) -> Void) -> Result {
        // `open` answers true whenever a handler accepts the scheme, even one that ignores the pane, so the
        // application fallback runs only for a refused link and an accepted one stays unconfirmed.
        if let link, openLink(link) { return .linkAccepted }
        guard let application = applicationURL() else { return .failed }
        openApplication(application)
        return .applicationOnly
    }

    /// The sentence shown under the button after an attempt, or nil when none is needed.
    static func manualRouteKey(after result: Result) -> PreviewStrings.Key? {
        .setupSteps
    }
}
