import SwiftUI
import PreviewRenderers

/// Storage problems stay visible on every page that edits settings, with the action that deals with them. Nothing is
/// shown while settings load, save or are saved normally.
struct SettingsSaveNotice: View {
    let settings: CompanionSettings

    var body: some View {
        if let key = settings.status.editingProblem {
            HStack(alignment: .center, spacing: 10) {
                SettingsIconBadge(image: CompanionSymbol.warning.image, tone: .caution, size: 22)
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
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CompanionTone.caution.color.opacity(0.28), lineWidth: 1))
            .accessibilityElement(children: .contain)
        }
    }
}
