import AppKit
import SwiftUI
import PreviewRenderers

struct AboutView: View {
    let configuration: HostedConfiguration
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    private let acknowledgements = AboutAcknowledgements(notices: BundledNotices())

    var body: some View {
        // The identity card below names the app once; the page is titled like the other pages.
        CompanionPage(title: PreviewStrings.text(.navigationAbout), subtitle: PreviewStrings.text(.aboutSubtitle)) {
            AdaptiveColumns {
                leadingColumn
                trailingColumn
            }
        }
    }

    private var leadingColumn: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
            SettingsCard(separatesRows: false) { identity }
            helpSection
            SettingsSection(PreviewStrings.text(.aboutAcknowledgementsTitle)) {
                SettingsCard {
                    bodyText(PreviewStrings.text(.schemeAcknowledgements))
                    // The notice folders exist only in a staged build; a run without them shows no button.
                    if let url = acknowledgements.colorSchemeNotices { AboutNoticeRow(folder: .colorSchemes, url: url) }
                }
            }
        }
    }

    /// A short help section inside the window. The Help menu item opens this page; the section sits next to the
    /// identity card, so it is in view without scrolling at the default window size.
    private var helpSection: some View {
        SettingsSection(PreviewStrings.text(.help)) {
            SettingsCard {
                SettingsRow(PreviewStrings.text(.generalSetupTitle), subtitle: PreviewStrings.text(.setupSteps))
                SettingsRow(PreviewStrings.text(.providersTitle), subtitle: PreviewStrings.text(.setupUnverified))
                SettingsRow(PreviewStrings.text(.generalLimitsTitle), subtitle: PreviewStrings.text(.generalLimitsFootnote))
                SettingsRow(PreviewStrings.text(.helpKeyboardTitle), subtitle: PreviewStrings.text(.helpKeyboardBody))
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: AboutLayout.iconSize, height: AboutLayout.iconSize)
                .accessibilityHidden(true)
            Text(verbatim: configuration.displayName).font(CompanionTypography.pageTitle)
            if let version = configuration.version, let build = configuration.build {
                StatusPill(
                    text: PreviewStrings.format(.aboutVersion, arguments: [version, build], locale: locale),
                    tone: .neutral
                )
            }
            Text(PreviewStrings.text(.aboutDescription))
                .foregroundStyle(CompanionInk.hint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CompanionMetrics.cardPadding + 6)
    }

    private var trailingColumn: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.sectionSpacing) {
            SettingsSection(PreviewStrings.text(.aboutHowItWorksTitle)) {
                SettingsCard { bodyText(PreviewStrings.text(.aboutHowItWorksBody)) }
            }
            SettingsSection(PreviewStrings.text(.aboutPrivacyTitle)) {
                SettingsCard {
                    bodyText(PreviewStrings.format(.aboutPrivacyBody, arguments: [configuration.displayName], locale: locale))
                }
            }
            if !resources.isEmpty {
                SettingsSection(PreviewStrings.text(.aboutResourcesTitle)) {
                    SettingsCard {
                        ForEach(resources) { resource in linkRow(resource) }
                    }
                }
            }
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(verbatim: text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, CompanionMetrics.rowVerticalPadding + 2)
    }

    private func linkRow(_ resource: Resource) -> some View {
        Button { openURL(resource.url) } label: {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconBadge(image: Image(systemName: resource.kind.symbol.rawValue), tone: .informational, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PreviewStrings.text(resource.kind.titleKey)).foregroundStyle(CompanionInk.link)
                    Text(verbatim: resource.destination).font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: AboutSymbol.openLink.rawValue)
                    .foregroundStyle(.secondary)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, CompanionMetrics.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(PreviewStrings.text(resource.kind.titleKey))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }

    private var resources: [Resource] {
        let links = configuration.links
        let candidates: [(ResourceKind, URL?)] = [
            (.website, links.website), (.support, links.support), (.documentation, links.documentation),
            (.privacyPolicy, links.privacyPolicy), (.feedback, links.feedback),
        ]
        return candidates.compactMap { kind, url in url.map { Resource(kind: kind, url: $0) } }
    }

    private struct Resource: Identifiable {
        let kind: ResourceKind
        let url: URL
        var id: ResourceKind { kind }

        /// The host for web links and the address for mail links, shown as written.
        var destination: String {
            if let host = url.host(), !host.isEmpty { return host }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.absoluteString
        }
    }

    private enum ResourceKind: Hashable {
        case website, support, documentation, privacyPolicy, feedback

        var titleKey: PreviewStrings.Key {
            switch self {
            case .website: .aboutLinkWebsite
            case .support: .aboutLinkSupport
            case .documentation: .aboutLinkDocumentation
            case .privacyPolicy: .aboutLinkPrivacyPolicy
            case .feedback: .aboutLinkFeedback
            }
        }

        var symbol: AboutSymbol {
            switch self {
            case .website: .website
            case .support: .support
            case .documentation: .documentation
            case .privacyPolicy: .privacyPolicy
            case .feedback: .feedback
            }
        }
    }
}

private enum AboutLayout {
    static let iconSize: CGFloat = 72
}

private enum AboutSymbol: String {
    case website = "globe"
    case support = "lifepreserver"
    case documentation = "book"
    case privacyPolicy = "hand.raised"
    case feedback = "bubble.left"
    case openLink = "arrow.up.right"
}
