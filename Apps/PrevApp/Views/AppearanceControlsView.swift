import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceControlsView: View {
    @Binding var typography: PreviewTypography
    @Binding var theme: PreviewTheme
    @Binding var syntaxStyle: PreviewSyntaxStyle
    let fontFamilies: FontFamilyList
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
            SettingsSection(PreviewStrings.text(.appearance)) {
                SettingsCard { colorModeRow }
            }
            AppearanceSchemeControls(style: $syntaxStyle)
            AppearanceFontControls(typography: $typography, fontFamilies: fontFamilies)
            AppearanceLayoutControls(typography: $typography)
            AppearanceSyntaxControls(style: $syntaxStyle)
        }
    }

    /// Segments are preferred. A narrow column or a long translation falls back to a menu. The label is the
    /// control's one visible name: the chosen mode is shown by the control itself, not repeated as a subtitle.
    private var colorModeRow: some View {
        let title = PreviewStrings.text(.appearanceColorMode)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                SettingsRowLabel(title: title, subtitle: nil)
                Spacer(minLength: 8)
                picker(.segmented).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRowLabel(title: title, subtitle: nil)
                picker(.segmented).fixedSize(horizontal: true, vertical: false)
            }
            HStack(alignment: .center, spacing: 12) {
                SettingsRowLabel(title: title, subtitle: nil)
                Spacer(minLength: 8)
                picker(.menu).fixedSize()
            }
        }
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
    }

    private enum PickerKind { case segmented, menu }

    @ViewBuilder private func picker(_ kind: PickerKind) -> some View {
        let choices = Picker(PreviewStrings.text(.appearanceColorMode), selection: $theme) {
            ForEach(PreviewTheme.allCases, id: \.self) { choice in
                Text(PreviewStrings.text(themeKey(choice))).tag(choice)
            }
        }
        .labelsHidden()
        switch kind {
        case .segmented: choices.pickerStyle(.segmented)
        case .menu: choices.pickerStyle(.menu)
        }
    }

    private func themeKey(_ value: PreviewTheme) -> PreviewStrings.Key {
        switch value {
        case .system: .themeSystem
        case .light: .themeLight
        case .dark: .themeDark
        case .highContrast: .themeHighContrast
        }
    }
}
