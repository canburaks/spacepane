import SwiftUI
import PreviewContracts
import PreviewRenderers

/// A group header with its tri-state checkbox, followed by the visible type cells.
struct FileTypeGroupSection: View {
    let group: FileTypeSettingsGroup
    let settings: CompanionSettings
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    var overlappingProvidersByFormat: [FormatID: [String]] = [:]
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    private enum Symbol { static let disclosure = "chevron.forward" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .topLeading)],
                          alignment: .leading, spacing: 12) {
                    ForEach(group.visibleMembers, id: \.id) { format in
                        FileTypeCell(format: format, settings: settings,
                                     overlappingProviders: overlappingProvidersByFormat[format.id] ?? [])
                    }
                }
                .padding(.horizontal, CompanionMetrics.cardPadding)
                .padding(.vertical, 12)
                .padding(.leading, 26)
            }
        }
    }

    private var header: some View {
        let name = PreviewStrings.text(group.nameKey)
        let summary = group.enablement(isEnabled: settings.isEnabled)
        return HStack(spacing: 8) {
            disclosureButton(name: name)
            Toggle(sources: groupBindings, isOn: \.self) {
                Text(verbatim: name).font(CompanionTypography.sectionHeading)
            }
            .toggleStyle(.checkbox)
            .help(PreviewStrings.text(.groupTypesScope))
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityHint(Text(PreviewStrings.text(.groupTypesScope)))
            HStack(spacing: 8) {
                StatusPill(
                    text: PreviewStrings.format(.fileTypesEnabledCount, arguments: [summary.enabled, summary.total], locale: locale),
                    tone: summary.enabled > 0 ? .informational : .neutral
                )
                // No status word follows: the checkbox state and the count carry the choice, and a word such as
                // "Enabled" would read as what Finder previews.
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleExpansion() }
            .help(PreviewStrings.format(.fileTypesGroupDisclosure, arguments: [name], locale: locale))
        }
        .padding(.horizontal, CompanionMetrics.cardPadding)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
    }

    private func disclosureButton(name: String) -> some View {
        let label = PreviewStrings.format(.fileTypesGroupDisclosure, arguments: [name], locale: locale)
        return Button(action: toggleExpansion) {
            Image(systemName: Symbol.disclosure)
                .font(CompanionTypography.note.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? (layoutDirection == .rightToLeft ? -90 : 90) : 0))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityRepresentation {
            DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { _ in toggleExpansion() })) {
                EmptyView()
            } label: {
                Text(verbatim: label)
            }
        }
    }

    /// The native collection toggle writes each source. Each write targets the whole
    /// group atomically, hidden members included; repeated identical writes are no-ops.
    private var groupBindings: [Binding<Bool>] {
        let ids = group.members.map(\.id)
        let nameKey = group.nameKey
        return ids.map { id in
            Binding(get: { settings.isEnabled(id) }, set: { settings.setEnabled($0, for: ids, group: nameKey) })
        }
    }
}
