import SwiftUI
import PreviewContracts
import PreviewRenderers

/// Separate color schemes for light and dark previews. Wide enough, each appearance shows its schemes as tiles drawn
/// from the schemes' own colors; narrower, it keeps a menu. Either way it offers Standard and the schemes whose own
/// background suits that appearance. The live sample beside the controls shows the effect at once; High Contrast
/// and the system Increase Contrast setting always use Standard colors.
struct AppearanceSchemeControls: View {
    @Binding var style: PreviewSyntaxStyle

    var body: some View {
        SettingsSection(PreviewStrings.text(.schemeTitle)) {
            SettingsCard {
                schemeRow(title: .schemeLight, hint: .schemeLightHint, polarity: .light, selection: $style.lightScheme)
                schemeRow(title: .schemeDark, hint: .schemeDarkHint, polarity: .dark, selection: $style.darkScheme)
                Text(PreviewStrings.text(.schemeNote))
                    .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
        }
    }

    /// The tiles when the row is wide enough for a few of them, the menu when it is not. Both choose through the
    /// same style, so the sample and the saved settings follow either.
    private func schemeRow(title: PreviewStrings.Key, hint: PreviewStrings.Key, polarity: PreviewColorSchemeID.Polarity,
                           selection: Binding<PreviewColorSchemeID>) -> some View {
        ViewThatFits(in: .horizontal) {
            galleryRow(title: title, hint: hint, polarity: polarity)
            menuRow(title: title, hint: hint, polarity: polarity, selection: selection)
        }
    }

    private func galleryRow(title: PreviewStrings.Key, hint: PreviewStrings.Key,
                            polarity: PreviewColorSchemeID.Polarity) -> some View {
        let name = PreviewStrings.text(title)
        let tiles = AppearanceSchemeGallery.tiles(
            for: polarity, selected: AppearanceSchemeGallery.selected(for: polarity, in: style))
        return VStack(alignment: .leading, spacing: 10) {
            SettingsRowLabel(title: name, subtitle: PreviewStrings.text(hint))
            TileFlowLayout {
                ForEach(tiles) { tile in
                    AppearanceSchemeTileView(tile: tile, hint: hint) {
                        style = AppearanceSchemeGallery.selecting(tile.id, for: polarity, in: style)
                    }
                }
            }
        }
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
        .frame(minWidth: AppearanceTileFlow.minimumWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: name))
    }

    private func menuRow(title: PreviewStrings.Key, hint: PreviewStrings.Key, polarity: PreviewColorSchemeID.Polarity,
                         selection: Binding<PreviewColorSchemeID>) -> some View {
        let name = PreviewStrings.text(title)
        return SettingsRow(name, subtitle: PreviewStrings.text(hint)) {
            Picker(name, selection: selection) {
                ForEach(PreviewColorSchemeID.choices(for: polarity), id: \.self) { scheme in
                    Text(PreviewStrings.text(AppearanceSchemeNames.key(for: scheme))).tag(scheme)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(Text(name))
            .accessibilityHint(Text(PreviewStrings.text(hint)))
        }
    }
}
