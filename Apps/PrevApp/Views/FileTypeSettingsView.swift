import SwiftUI
import PreviewContracts
import PreviewRenderers

struct FileTypeSettingsView: View {
    let settings: CompanionSettings
    @CompanionState private var search = ""
    @CompanionState private var collapsed: Set<FormatGroup> = []
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Bumped by ⌘F; the search field takes focus each time it changes.
    @CompanionState private var searchFocusRequest = 0
    /// The configured display name for the subtitle; the same source the shell uses.
    private let appName = HostedConfiguration().displayName

    private enum Symbol {
        static let note = "info.circle"
    }

    /// How long typing must pause before the result count is spoken, so it never talks over the echoed characters.
    private static let announcementDelay = Duration.milliseconds(600)

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let catalogSummary = FileTypeEnablementSummary(FormatCatalog.standard.descriptors, isEnabled: settings.isEnabled)
        CompanionPage(title: PreviewStrings.text(.fileTypes),
                      subtitle: PreviewStrings.format(.fileTypesSubtitle, arguments: [appName], locale: locale),
                      scrolls: false) {
            StatusPill(text: PreviewStrings.format(.fileTypesEnabledCount,
                                                   arguments: [catalogSummary.enabled, catalogSummary.total],
                                                   locale: locale),
                       tone: .informational)
                // A count read before the settings load would be a wrong 0 (CO-22).
                .opacity(settings.isLoading ? 0 : 1)
                .accessibilityHidden(settings.isLoading)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                controlBar.disabled(settings.isLoading)
                // The row appears after Enable All, Disable All, Reset or a group checkbox, until the next change.
                if let notice = settings.undoNotice(in: .fileTypes) {
                    SettingsUndoNotice(settings: settings, notice: notice)
                }
                SettingsSaveNotice(settings: settings)
                if settings.isLoading { loadingRow } else { table }
            }
        }
        .background { findShortcut }
        .task { await settings.load() }
        .task(id: search) { await announceResult(for: search) }
    }

    /// ⌘F while this page is showing; Try Preview keeps its own find, because this button exists only here.
    private var findShortcut: some View {
        Button(PreviewStrings.text(.searchFileTypes)) { searchFocusRequest += 1 }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .clipped()
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// Speaks the number of shown types once typing pauses; a new keystroke cancels the pending sentence.
    private func announceResult(for query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try await Task.sleep(for: Self.announcementDelay) } catch { return }
        let groups = FileTypeSettingsGroup.matching(in: .standard, search: query)
        CompanionAnnouncer.announce(FileTypeSettingsGroup.resultAnnouncement(for: groups, locale: locale))
    }

    /// Stands in for the table while settings load, so no box shows a state that was never read (CO-22).
    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(PreviewStrings.text(.statusLoading))
        }
        .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Control bar

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One layout keeps the search field's identity and focus while the actions wrap.
            FileTypeControlBarLayout {
                searchField
                Group {
                    Button(PreviewStrings.text(.enableAll)) { settings.setAllEnabled(true) }
                    Button(PreviewStrings.text(.disableAll)) { settings.setAllEnabled(false) }
                    Button(PreviewStrings.text(.resetChoices)) { settings.resetFileTypeChoices() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help(PreviewStrings.text(.allTypesScope))
            }
            if isSearching {
                // Bulk and group controls reach types the query hides, so their scope is stated while it applies.
                VStack(alignment: .leading, spacing: 2) {
                    Text(PreviewStrings.text(.allTypesScope))
                    Text(PreviewStrings.text(.groupTypesScope))
                }
                .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchField: some View {
        FileTypeSearchField(text: $search, prompt: PreviewStrings.text(.searchFileTypes), focusRequest: searchFocusRequest)
            .frame(width: 260)
    }

    // MARK: Table

    private var table: some View {
        let groups = FileTypeSettingsGroup.matching(in: .standard, search: search)
        return VStack(spacing: 0) {
            Text(PreviewStrings.text(.fileTypesHeaderFormats))
                .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint).textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CompanionMetrics.cardPadding)
                .padding(.vertical, 7)
            Divider()
            if groups.isEmpty {
                Text(PreviewStrings.text(.noMatchingFileTypes))
                    .foregroundStyle(CompanionInk.hint)
                    .multilineTextAlignment(.center)
                    .padding(CompanionMetrics.pagePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups) { group in
                            if group.id != groups.first?.id { Divider() }
                            FileTypeGroupSection(group: group, settings: settings,
                                                 isExpanded: isSearching || !collapsed.contains(group.group),
                                                 toggleExpansion: { toggle(group.group) })
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.04), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.09)))
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Symbol.note).accessibilityHidden(true)
            Text(PreviewStrings.text(.settingsNotice)).fixedSize(horizontal: false, vertical: true)
        }
        .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
        .padding(.horizontal, CompanionMetrics.cardPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
    }

    private func toggle(_ group: FormatGroup) {
        // While a query is active every group is shown expanded, so the stored state stays untouched.
        guard !isSearching else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
        }
    }
}
