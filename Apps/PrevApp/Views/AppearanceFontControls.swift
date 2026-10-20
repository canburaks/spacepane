import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceFontControls: View {
    @Binding var typography: PreviewTypography
    let fontFamilies: FontFamilyList
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsSection(PreviewStrings.text(.appearanceTypography)) {
            SettingsCard {
                // Each control has one visible, clickable label. The chosen value is shown by the control
                // itself, never repeated as a subtitle.
                SettingsRow(PreviewStrings.text(.fontFamily)) { familyPicker }
                SettingsRow(PreviewStrings.text(.fontSize)) { sizeControls }
                SettingsRow(PreviewStrings.text(.fontWeight)) { weightPicker }
                SettingsCheckboxRow(PreviewStrings.text(.italicFont), isOn: $typography.italic)
                Text(PreviewStrings.text(.fontFallbackNotice))
                    .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
        }
    }

    /// System Monospaced first, then the fixed-width families, then every other family.
    private var familyPicker: some View {
        Picker(PreviewStrings.text(.fontFamily), selection: $typography.fontFamily) {
            Text(PreviewStrings.text(.systemMonospacedFont)).tag(String?.none)
            if let selected = typography.fontFamily, !fontFamilies.contains(selected) {
                Text(PreviewStrings.format(.unavailableFontFamily, arguments: [selected], locale: locale))
                    .tag(Optional(selected))
            }
            if !fontFamilies.fixedWidth.isEmpty {
                Section(PreviewStrings.text(.fontFamilyFixedWidth)) {
                    ForEach(fontFamilies.fixedWidth, id: \.self) { family in
                        Text(verbatim: family).tag(Optional(family))
                    }
                }
            }
            if !fontFamilies.others.isEmpty {
                Section(PreviewStrings.text(.fontFamilyOthers)) {
                    ForEach(fontFamilies.others, id: \.self) { family in
                        Text(verbatim: family).tag(Optional(family))
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 170)
        .help(PreviewStrings.text(.fontFamily))
    }

    /// A field to type the size into, beside the stepper that nudges it by one point.
    private var sizeControls: some View {
        let spoken = TypographyPointFormat.spokenText(typography.fontSize, locale: locale)
        return HStack(spacing: 8) {
            TextField(PreviewStrings.text(.fontSize), value: sizeBinding,
                      format: .number.precision(.fractionLength(0...2)).locale(locale))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .help(PreviewStrings.text(.fontSize))
                .accessibilityLabel(Text(PreviewStrings.text(.fontSize)))
                .accessibilityValue(Text(spoken))
            Stepper(value: sizeBinding, in: PreviewTypography.fontSizeRange, step: 1) {
                Text(PreviewStrings.text(.fontSize))
            }
            .labelsHidden()
            .help(PreviewStrings.text(.fontSize))
            .accessibilityLabel(Text(PreviewStrings.text(.fontSize)))
            .accessibilityValue(Text(spoken))
        }
    }

    /// The size, kept inside its range: the field can be typed into, so a value outside the range is limited
    /// to it, and a value that is not a number changes nothing.
    private var sizeBinding: Binding<Double> {
        Binding(get: { typography.fontSize },
                set: { newValue in
                    typography.fontSize = TypographyPointFormat.clamped(newValue, to: PreviewTypography.fontSizeRange,
                                                                        fallback: typography.fontSize)
                })
    }

    private var weightPicker: some View {
        ViewThatFits(in: .horizontal) {
            weightControl
                .pickerStyle(.segmented)
                .fixedSize()
            weightControl
                .pickerStyle(.menu)
                .fixedSize()
        }
    }

    private var weightControl: some View {
        Picker(PreviewStrings.text(.fontWeight), selection: $typography.weight) {
            ForEach(PreviewFontWeight.allCases, id: \.self) { weight in
                Text(PreviewStrings.text(weightKey(weight))).tag(weight)
            }
        }
        .labelsHidden()
        .help(PreviewStrings.text(.fontWeight))
    }

    private func weightKey(_ value: PreviewFontWeight) -> PreviewStrings.Key {
        switch value {
        case .regular: .weightRegular
        case .medium: .weightMedium
        case .semibold: .weightSemibold
        case .bold: .weightBold
        }
    }
}
