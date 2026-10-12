import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceLayoutControls: View {
    @Binding var typography: PreviewTypography
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsSection(PreviewStrings.text(.appearanceLayout)) {
            SettingsCard {
                SettingsRow(PreviewStrings.text(.appearanceLineBehavior)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(PreviewStrings.text(.wrapLines), isOn: $typography.wrapsLines)
                        Toggle(PreviewStrings.text(.lineNumbers), isOn: $typography.showsLineNumbers)
                            .help(PreviewStrings.text(.lineNumbersHint))
                            .accessibilityHint(Text(PreviewStrings.text(.lineNumbersHint)))
                    }
                    .toggleStyle(.checkbox)
                }
                SettingsRow(PreviewStrings.text(.lineSpacing)) {
                    pointStepper(value: $typography.lineSpacing, range: PreviewTypography.lineSpacingRange,
                                 step: 1, title: PreviewStrings.text(.lineSpacing))
                }
                SettingsRow(PreviewStrings.text(.characterSpacing)) {
                    pointStepper(value: $typography.characterSpacing, range: PreviewTypography.characterSpacingRange,
                                 step: 0.25, title: PreviewStrings.text(.characterSpacing))
                }
                SettingsRow(PreviewStrings.text(.tabWidth)) { tabWidthControls }
                // One label for the one choice: the former "Font features" row held only this checkbox.
                SettingsCheckboxRow(PreviewStrings.text(.fontLigatures), isOn: $typography.ligatures)
            }
        }
    }

    /// The value in points beside its stepper, so the number is where the eye is when the stepper is clicked.
    private func pointStepper(value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                              title: String) -> some View {
        let spoken = TypographyPointFormat.spokenText(value.wrappedValue, locale: locale)
        return HStack(spacing: 8) {
            Text(verbatim: TypographyPointFormat.text(value.wrappedValue, locale: locale))
                .monospacedDigit()
                .foregroundStyle(CompanionInk.hint)
                .accessibilityHidden(true)
            Stepper(value: value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(spoken))
        }
    }

    private var tabWidthControls: some View {
        let title = PreviewStrings.text(.tabWidth)
        return HStack(spacing: 8) {
            Text(verbatim: typography.tabWidth.formatted(.number.locale(locale)))
                .monospacedDigit()
                .foregroundStyle(CompanionInk.hint)
                .accessibilityHidden(true)
            Stepper(value: $typography.tabWidth, in: PreviewTypography.tabWidthRange) { Text(title) }
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(typography.tabWidth, format: .number.locale(locale)))
                .help(PreviewStrings.text(.tabWidthHint))
        }
    }
}
