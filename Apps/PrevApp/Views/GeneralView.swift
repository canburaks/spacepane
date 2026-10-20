import AppKit
import SwiftUI
import PreviewContracts
import PreviewRenderers

struct GeneralView: View {
    let configuration: HostedConfiguration
    let settings: CompanionSettings
    let diagnostics: QuickLookProviderDiagnostics
    @Environment(\.locale) private var locale
    /// Set by the first press of Open System Settings; the manual route stays under the button from then on.
    @State private var systemSettingsAttempt: SystemSettingsOpening.Result?

    var body: some View {
        // The status has one home, the sidebar footer, so the header carries no pill of its own.
        CompanionPage(title: PreviewStrings.text(.navigationGeneral), subtitle: PreviewStrings.text(.generalSubtitle)) {
            VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
                banner
                AdaptiveColumns {
                    leadingColumn
                    trailingColumn
                }
            }
        }
    }

    private var leadingColumn: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
            PreviewBehaviorSection(settings: settings)
            FolderPreviewSection(settings: settings)
        }
    }

    private var trailingColumn: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
            SettingsSection(PreviewStrings.text(.generalLimitsTitle)) {
                SettingsCard {
                    limitRow(.generalLimitFileSize, subtitle: .generalLimitFileSizeHint,
                             value: Int64(PreviewBudget.standard.maxInputBytes)
                                 .formatted(.byteCount(style: .file).locale(locale)))
                    limitRow(.generalLimitLines,
                             value: PreviewBudget.standard.maxTextLines.formatted(.number.locale(locale)))
                    limitRow(.generalLimitTime,
                             value: Duration.milliseconds(PreviewBudget.standard.maxMilliseconds)
                                 .formatted(.units(allowed: [.seconds, .milliseconds], width: .wide).locale(locale)))
                }
                caption(.generalLimitsFootnote)
            }
            // The banner states the storage problems; the card adds the others (a failed save, a recovered file).
            // A healthy state is the footer's one neutral sentence, not a card.
            let problems = settings.status.problemKeys.filter { $0 != bannerContent.body }
            if !problems.isEmpty {
                SettingsSection(PreviewStrings.text(.generalStorageTitle)) {
                    SettingsCard { SettingsStorageStatusView(keys: problems, settings: settings) }
                }
            }
            QuickLookProviderDiagnosticsView(diagnostics: diagnostics)
        }
    }

    private func limitRow(_ title: PreviewStrings.Key, subtitle: PreviewStrings.Key? = nil, value: String) -> some View {
        SettingsRow(PreviewStrings.text(title), subtitle: subtitle.map { PreviewStrings.text($0) }) {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(CompanionInk.hint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ key: PreviewStrings.Key) -> some View {
        Text(PreviewStrings.text(key))
            .font(CompanionTypography.note)
            .foregroundStyle(CompanionInk.hint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }

    private var banner: some View {
        let content = bannerContent
        return SettingsCard(separatesRows: false) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        bannerLead(content)
                        Spacer(minLength: 8)
                        openSystemSettingsButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        bannerLead(content)
                        openSystemSettingsButton
                            .padding(.leading, BannerLayout.badgeSize + 12)
                    }
                }
                // macOS cannot confirm which pane opened, so the way there is written out after every attempt.
                if let attempt = systemSettingsAttempt, let route = SystemSettingsOpening.manualRouteKey(after: attempt) {
                    Text(PreviewStrings.text(route))
                        .font(CompanionTypography.note)
                        .foregroundStyle(CompanionInk.hint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, BannerLayout.badgeSize + 12)
                }
            }
            .padding(.vertical, CompanionMetrics.rowVerticalPadding + 4)
            Divider()
            SettingsRow(PreviewStrings.text(.generalSetupTitle), subtitle: PreviewStrings.text(.setupSteps))
            caption(.setupUnverified)
                .padding(.bottom, 6)
        }
    }

    private func bannerLead(_ content: BannerContent) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIconBadge(image: content.symbol.image, tone: content.tone, size: BannerLayout.badgeSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(PreviewStrings.text(content.title)).font(CompanionTypography.sectionHeading)
                Text(PreviewStrings.text(content.body)).foregroundStyle(CompanionInk.hint)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: BannerLayout.minimumTextWidth, idealWidth: BannerLayout.idealTextWidth, alignment: .leading)
        }
    }

    private var openSystemSettingsButton: some View {
        Button(PreviewStrings.text(.openSystemSettings)) { systemSettingsAttempt = SystemSettingsDestination.open() }
            .fixedSize()
            .help(PreviewStrings.text(.openSystemSettings))
    }

    private var bannerContent: BannerContent {
        switch settings.storageMode {
        case .shared:
            // A location, not a verdict: the app cannot know whether the extensions are on, so this is neutral.
            BannerContent(symbol: .info, tone: .neutral, title: .generalBannerSharedTitle, body: .generalBannerSharedBody)
        case .privateOnly:
            BannerContent(symbol: .warning, tone: .caution, title: .generalBannerAppOnlyTitle, body: .setupNotConfigured)
        case .unavailable:
            BannerContent(symbol: .warning, tone: .caution, title: .generalBannerUnavailableTitle, body: .storageUnavailable)
        }
    }
}

private enum BannerLayout {
    static let badgeSize: CGFloat = 40
    static let minimumTextWidth: CGFloat = 240
    /// Ideal width decides when the button moves below the text instead of squeezing it.
    static let idealTextWidth: CGFloat = 320
}

private struct BannerContent {
    let symbol: CompanionSymbol
    let tone: CompanionTone
    let title: PreviewStrings.Key
    let body: PreviewStrings.Key
}

/// Opening System Settings is allowed; the app never changes a system setting.
private enum SystemSettingsDestination {
    /// The Login Items & Extensions pane. The link is not documented for macOS 15 and may open System Settings on
    /// another pane, which the app cannot tell, so the page shows the manual route after every attempt.
    static let loginItemsAndExtensions = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    static let applicationIdentifier = "com.apple.systempreferences"

    @MainActor static func open() -> SystemSettingsOpening.Result {
        let workspace = NSWorkspace.shared
        return SystemSettingsOpening.open(
            link: loginItemsAndExtensions,
            openLink: { workspace.open($0) },
            applicationURL: { workspace.urlForApplication(withBundleIdentifier: applicationIdentifier) },
            openApplication: { workspace.open($0) })
    }
}
