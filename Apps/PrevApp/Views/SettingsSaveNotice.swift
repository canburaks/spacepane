import SwiftUI
import PreviewRenderers

/// Storage problems stay visible on every page that edits settings, with the action that deals with them. Nothing is
/// shown while settings load, save or are saved normally.
struct SettingsSaveNotice: View {
    let settings: CompanionSettings

    var body: some View {
        if let key = settings.status.editingProblem {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CompanionSymbol.warning.image.foregroundStyle(CompanionTone.caution.color).accessibilityHidden(true)
                Text(PreviewStrings.text(key)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let action = SettingsStatus.action(for: key) {
                    SettingsProblemAction(settings: settings, action: action)
                }
            }
            .font(CompanionTypography.note)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CompanionTone.caution.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}
