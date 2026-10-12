import SwiftUI
import PreviewRenderers

/// The General page's storage card. It lists verified problems the banner does not already state (a failed
/// save, a recovered file), each with an icon as well as a tint, and, when given the settings, the action that deals
/// with it. A healthy state is the sidebar footer's one neutral sentence, not a card.
struct SettingsStorageStatusView: View {
    let keys: [PreviewStrings.Key]
    var settings: CompanionSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys, id: \.self) { key in
                if key != keys.first { Divider() }
                line(key)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ key: PreviewStrings.Key) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CompanionSymbol.warning.image.foregroundStyle(CompanionTone.caution.color).accessibilityHidden(true)
            Text(PreviewStrings.text(key))
                .fixedSize(horizontal: false, vertical: true)
            if let settings, let action = SettingsStatus.action(for: key) {
                Spacer(minLength: 8)
                SettingsProblemAction(settings: settings, action: action)
            }
        }
        .font(CompanionTypography.note)
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
