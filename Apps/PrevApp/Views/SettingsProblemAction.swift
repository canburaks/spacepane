import SwiftUI
import PreviewRenderers

/// The button that deals with a storage problem: Try Again after a failed save, Restore Defaults after an unusable
/// settings file. Neither changes a choice the person made, so neither registers an Undo.
struct SettingsProblemAction: View {
    let settings: CompanionSettings
    let action: SettingsStatus.Action

    var body: some View {
        Button(PreviewStrings.text(action.titleKey)) {
            switch action {
            case .tryAgain: settings.retrySave()
            case .restoreDefaults: settings.restoreDefaults()
            }
        }
        .controlSize(.small)
    }
}
