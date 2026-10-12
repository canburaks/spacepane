import SwiftUI
import PreviewContracts
import PreviewRenderers

/// An on-demand look at other installed apps whose Quick Look extensions declare some of the same file types.
/// It reads app bundles only. It cannot say which provider macOS or Finder uses, and never claims to.
struct QuickLookProviderDiagnosticsView: View {
    let diagnostics: QuickLookProviderDiagnostics
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsSection(PreviewStrings.text(.providersTitle)) {
            SettingsCard {
                SettingsRow(PreviewStrings.text(.providersScanTitle), subtitle: PreviewStrings.text(.providersScanSubtitle)) {
                    scanButton
                }
                switch diagnostics.state {
                case .idle: EmptyView()
                case .scanning: scanningRow
                case .finished(let report): results(report)
                }
                Text(PreviewStrings.text(.providersGuidance))
                    .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CompanionMetrics.rowVerticalPadding)
            }
        }
        // A scan ends by changing what is drawn, which VoiceOver does not speak, so its two counts are announced.
        .onChange(of: diagnostics.state) {
            if case .finished(let report) = diagnostics.state {
                CompanionAnnouncer.announce(report.announcement(locale: locale))
            }
        }
    }

    @ViewBuilder private var scanButton: some View {
        if diagnostics.isScanning {
            Button(PreviewStrings.text(.providersCancel)) { diagnostics.cancel() }
        } else {
            Button(PreviewStrings.text(isFinished ? .providersRescan : .providersScan)) { diagnostics.startScan() }
        }
    }

    private var isFinished: Bool {
        if case .finished = diagnostics.state { return true }
        return false
    }

    private var scanningRow: some View {
        ProgressView(PreviewStrings.text(.providersScanning))
            .controlSize(.small)
            .padding(.vertical, CompanionMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private func results(_ report: QuickLookProviderReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PreviewStrings.format(.providersChecked, arguments: [report.scannedApplications], locale: locale))
            if report.providers.isEmpty {
                Text(PreviewStrings.text(.providersNone))
            } else {
                Text(PreviewStrings.format(.providersFound, arguments: [report.providers.count], locale: locale))
            }
            if report.reachedApplicationLimit {
                caveat(PreviewStrings.format(.providersLimit, arguments: [report.scannedApplications], locale: locale))
            }
            if !report.unreadableLocations.isEmpty {
                caveat(PreviewStrings.format(.providersUnreadable, arguments: [locations(report.unreadableLocations)],
                                             locale: locale))
            }
            if report.skippedApplications > 0 {
                caveat(PreviewStrings.format(.providersSkipped, arguments: [report.skippedApplications], locale: locale))
            }
        }
        .font(CompanionTypography.note)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        ForEach(report.providers) { provider in providerRow(provider) }
    }

    /// A limit or an access problem is shown with an icon as well as text, so it never relies on color.
    private func caveat(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            CompanionSymbol.warning.image.foregroundStyle(CompanionTone.caution.color).accessibilityHidden(true)
            Text(verbatim: text)
        }
    }

    private func providerRow(_ provider: QuickLookProviderApp) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: provider.name)
                Text(verbatim: kindsText(provider.kinds)).foregroundStyle(CompanionInk.hint).font(CompanionTypography.note)
            }
            Text(verbatim: formatsText(provider.overlappingFormats))
                .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private func locations(_ labels: [String]) -> String {
        labels.formatted(.list(type: .and, width: .standard).locale(locale))
    }

    private func kindsText(_ kinds: QuickLookProviderApp.Kinds) -> String {
        var names: [String] = []
        if kinds.contains(.preview) { names.append(PreviewStrings.text(.providersKindPreview)) }
        if kinds.contains(.thumbnail) { names.append(PreviewStrings.text(.providersKindThumbnail)) }
        return names.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// Catalog names of the overlapping formats. A long list shows its first names and the count of the rest,
    /// so one app that declares many types cannot fill the page.
    private func formatsText(_ formats: [FormatID]) -> String {
        let names = formats.compactMap { FormatCatalog.standard.descriptor(for: $0) }
            .map { PreviewStrings.text(catalogKey: $0.nameKey) }
        let shown = Array(names.prefix(Self.visibleFormatNames)).formatted(.list(type: .and, width: .standard).locale(locale))
        let hidden = names.count - Self.visibleFormatNames
        let list = hidden > 0
            ? PreviewStrings.format(.providersFormatsMore, arguments: [shown, hidden], locale: locale)
            : shown
        return PreviewStrings.format(.providersFormats, arguments: [list], locale: locale)
    }

    private static let visibleFormatNames = 6
}
