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
    @FocusState private var searchIsFocused: Bool
    /// The configured display name for the subtitle; the same source the shell uses.
    private let appName = HostedConfiguration().displayName

    private enum Symbol {
        static let search = "magnifyingglass"
        static let clear = "xmark.circle.fill"
        static let note = "info.circle"
    }

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
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                controlBar.disabled(settings.isLoading)
                // The row appears after Enable All, Disable All, Reset or a group checkbox, until the next change.
                if let notice = settings.undoNotice(in: .fileTypes) {
                    SettingsUndoNotice(settings: settings, notice: notice)
                }
                SettingsSaveNotice(settings: settings)
                table.disabled(settings.isLoading)
            }
        }
        .task { await settings.load() }
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
        HStack(spacing: 6) {
            Image(systemName: Symbol.search).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(text: $search, prompt: Text(PreviewStrings.text(.searchFileTypes))) {
                Text(PreviewStrings.text(.searchFileTypes))
            }
            .textFieldStyle(.plain)
            .focused($searchIsFocused)
            .accessibilityLabel(Text(PreviewStrings.text(.searchFileTypes)))
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: Symbol.clear).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help(PreviewStrings.text(.fileTypesClearSearch))
                    .accessibilityLabel(Text(PreviewStrings.text(.fileTypesClearSearch)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 260)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(searchIsFocused ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.4 : 0.12),
                          lineWidth: searchIsFocused ? 2 : 1))
        // The whole box, not only its text, focuses the field.
        .contentShape(Rectangle())
        .onTapGesture { searchIsFocused = true }
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
