import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceSettingsView: View {
    let settings: CompanionSettings
    let sample: AppearanceSampleSession
    @CompanionState private var fontFamilies: FontFamilyList = .empty

    var body: some View {
        CompanionPage(title: PreviewStrings.text(.navigationTheme), subtitle: PreviewStrings.text(.themeSubtitle),
                      scrolls: false) {
            Button(PreviewStrings.text(.resetAppearance)) { settings.resetAppearance() }
                .buttonStyle(.link)
                .disabled(settings.isLoading)
                .help(PreviewStrings.text(.resetAppearanceHint))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                // Storage problems come first, with the action that deals with them, and stay in view while the
                // controls scroll. The Undo row appears after Reset Appearance, Apply, Import theme or Delete.
                SettingsSaveNotice(settings: settings)
                loadingRow
                if let notice = settings.undoNotice(in: .appearance) {
                    SettingsUndoNotice(settings: settings, notice: notice)
                }
                // The sample stays pinned: beside the scrolling controls when wide, above them when not.
                PinnedSampleLayout {
                    controls
                    AppearanceSampleView(session: sample, settings: settings)
                    AppearanceSampleNotes(session: sample, settings: settings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await settings.load() }
        .onAppear { fontFamilies = InstalledFontFamilies.available() }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
                AppearanceControlsView(
                    typography: Binding(get: { settings.snapshot.typography }, set: { settings.setTypography($0) }),
                    theme: Binding(get: { settings.snapshot.theme }, set: { settings.setTheme($0) }),
                    syntaxStyle: Binding(get: { settings.snapshot.syntaxStyle }, set: { settings.setSyntaxStyle($0) }),
                    fontFamilies: fontFamilies)
                    .disabled(settings.isLoading)
                AppearanceProfilesView(settings: settings).disabled(settings.isLoading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Says what the page is waiting for while the saved settings are read, instead of showing dimmed controls
    /// with no word.
    @ViewBuilder private var loadingRow: some View {
        if settings.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(PreviewStrings.text(.appearanceLoading))
            }
            .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
            .accessibilityElement(children: .combine)
        }
    }
}
