import SwiftUI
import PreviewContracts
import PreviewRenderers

/// A built-in sample of any catalog format, read through the shared privacy pipeline
/// and drawn by the same native renderer as a real preview. No user file is involved.
struct AppearanceSampleView: View {
    let session: AppearanceSampleSession
    let settings: CompanionSettings
    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        SettingsSection(PreviewStrings.text(.appearanceSampleTitle), detail: PreviewStrings.text(.appearanceSampleUpdates)) {
            window
        }
        .task { session.loadIfNeeded() }
    }

    // Strips follow the system appearance; the preview content follows the selected preview theme. The window
    // takes whatever height the page gives the sample; the notes under it are `AppearanceSampleNotes`.
    private var window: some View {
        VStack(spacing: 0) {
            titleStrip
            Divider()
            pane.frame(minHeight: 60, maxHeight: .infinity)
            Divider()
            statusStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(frameShape)
        .overlay(frameShape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.15)))
        // Where the notes do not fit, the refresh note is still here for the pointer and for VoiceOver.
        .help(PreviewStrings.text(.settingsNotice))
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text(PreviewStrings.text(.settingsNotice)))
    }

    /// The previous sample stays visible while another loads, so the one native pane keeps its identity.
    private var pane: some View {
        ZStack(alignment: .topTrailing) {
            if let result = session.result {
                // The sample is always drawn in the regular density, so the chrome a control changes is
                // visible whatever width the window gives it.
                NativePreviewPane(result: result, typography: settings.snapshot.typography,
                                  generation: session.generation, theme: settings.snapshot.theme,
                                  syntaxStyle: settings.snapshot.syntaxStyle, forcedDensity: .regular)
            } else {
                Color(nsColor: .textBackgroundColor)
            }
            if session.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .accessibilityLabel(Text(PreviewStrings.text(.loading)))
            }
        }
    }

    private var frameShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
    }

    /// The sample's file name and the type menu. There is no window furniture: the frame is a sample, and
    /// three decorative dots would look like controls that do nothing.
    private var titleStrip: some View {
        HStack(spacing: 10) {
            Text(verbatim: session.itemName ?? "")
                .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            typePicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Every catalog format, grouped as on the File Types page.
    private var typePicker: some View {
        Picker(PreviewStrings.text(.appearanceSampleTypePicker),
               selection: Binding(get: { session.selected }, set: { session.select($0) })) {
            ForEach(FileTypeSettingsGroup.matching(in: .standard, search: "")) { group in
                Section(PreviewStrings.text(group.nameKey)) {
                    ForEach(group.members, id: \.id) { format in
                        Text(PreviewStrings.text(catalogKey: format.nameKey)).tag(format.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help(PreviewStrings.text(.appearanceSampleTypePicker))
    }

    /// The type's name is already in the menu above, so the strip carries only the typography in use.
    private var statusStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(PreviewStrings.format(.appearanceSampleStatus,
                                       arguments: [pointValueString, settings.snapshot.typography.tabWidth], locale: locale))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
        }
        .font(CompanionTypography.note)
        .foregroundStyle(CompanionInk.hint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The font size with locale digits and the same unit text as the Typography rows.
    private var pointValueString: String {
        TypographyPointFormat.text(settings.snapshot.typography.fontSize, locale: locale)
    }
}

/// What sits under the sample when there is room: the notice for a sample type that is switched off, what a sample
/// is, and when Finder picks the settings up. The page offers it a height and it says as much as fits, down to
/// nothing, so the sample window never gives up its lines for a note.
struct AppearanceSampleNotes: View {
    let session: AppearanceSampleSession
    let settings: CompanionSettings

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 8) {
                if !settings.isLoading, !settings.isEnabled(session.selected) { disabledNotice }
                note(.appearanceSampleDescription)
                note(.settingsNotice)
            }
            note(.settingsNotice)
            Color.clear.frame(height: 0)
        }
    }

    private func note(_ key: PreviewStrings.Key) -> some View {
        Text(PreviewStrings.text(key))
            .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var disabledNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            CompanionSymbol.warning.image.foregroundStyle(CompanionTone.caution.color).accessibilityHidden(true)
            Text(PreviewStrings.text(.appearanceSampleTypeDisabled)).fixedSize(horizontal: false, vertical: true)
        }
        .font(CompanionTypography.note)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}
