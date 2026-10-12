import AppKit
import SwiftUI
import PreviewContracts
import PreviewRenderers

/// Navigation for the single companion window: app identity, destinations and
/// a summary of where settings are saved.
struct CompanionSidebar: View {
    let configuration: HostedConfiguration
    let settings: CompanionSettings
    let developerMode: Bool
    @Binding var route: CompanionRoute
    @Environment(\.locale) private var locale

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(destinations(developer: false)) { destination(_: $0) }
            }
            if developerMode {
                Section(PreviewStrings.text(.navigationDeveloper)) {
                    ForEach(destinations(developer: true)) { destination(_: $0) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { identity }
        .safeAreaInset(edge: .bottom, spacing: 0) { status }
        .background(Color.companionSidebar.ignoresSafeArea())
    }

    private var selection: Binding<CompanionRoute?> {
        // The list may clear its selection; the window always shows one destination.
        Binding(get: { route }, set: { if let destination = $0 { route = destination } })
    }

    private func destinations(developer: Bool) -> [CompanionRoute] {
        CompanionRoute.available(developerMode: developerMode).filter { $0.requiresDeveloperMode == developer }
    }

    private func destination(_ destination: CompanionRoute) -> some View {
        Label { Text(PreviewStrings.text(destination.title)) } icon: { destination.symbol.image }
            .tag(destination)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: configuration.displayName).lineLimit(1)
                Text(PreviewStrings.text(.shellSubtitle))
                    .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    /// The one place the settings status is shown on every page: where choices are saved, or a verified
    /// problem. It is neutral unless something is wrong, and it never says that the extensions are on.
    private var status: some View {
        let current = settings.status
        let tone = current.tone.companionTone
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if current.tone == .caution {
                CompanionSymbol.warning.image.foregroundStyle(tone.color).accessibilityHidden(true)
            } else {
                Circle().fill(tone.color).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text(PreviewStrings.text(current.titleKey))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(10)
        .accessibilityElement(children: .combine)
    }
}
