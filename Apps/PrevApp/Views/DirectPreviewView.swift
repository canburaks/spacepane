import SwiftUI
import PreviewContracts
import PreviewRenderers

struct DirectPreviewView: View {
    let session: PreviewSession
    let settings: CompanionSettings
    var overlappingProvidersByFormat: [FormatID: [String]] = [:]
    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var contrast
    @CompanionState private var dropFeedback: DirectPreviewDropFeedback = .idle
    /// The configured display name for the "Preview by …" caption; the same source the shell uses.
    private let providerName = HostedConfiguration().displayName

    var body: some View {
        CompanionPage(title: PreviewStrings.text(.tryPreview), subtitle: PreviewStrings.text(.previewEmptyDescription),
                      scrolls: false) {
            Button(PreviewStrings.text(.openFile)) { session.presentsFileImporter = true }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if hasActiveOrLoadedPreview {
                    dropStrip
                }
                if let url = session.sourceURL {
                    fileInspectorBar(for: url)
                }
                previewPane
            }
        }
        .onChange(of: session.generation) { dropFeedback = .idle }
        // A failed picker only changes what is drawn, which VoiceOver does not speak; every failure is announced.
        .onChange(of: session.pickerFailureCount) {
            CompanionAnnouncer.announce(PreviewStrings.text(.pickerFailed))
        }
        // Live reload runs only while this page is on screen.
        .onAppear { session.previewVisibilityChanged(true) }
        .onDisappear { session.previewVisibilityChanged(false) }
    }

    private func fileInspectorBar(for url: URL) -> some View {
        let (formatID, concealedCount): (FormatID?, Int) = switch session.outcome {
        case .ready(let presentation):
            (presentation.formatID, presentation.redactionCount)
        case .geometryReady(let presentation):
            (presentation.formatID, 0)
        case .disabledByUser(let formatID):
            (formatID, 0)
        case .unavailable, .cancelled, nil:
            (nil, 0)
        }
        let descriptor = formatID.flatMap { FormatCatalog.standard.descriptor(for: $0) }
        return HStack(spacing: 8) {
            Text(verbatim: url.lastPathComponent)
                .font(CompanionTypography.sectionHeading)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if let descriptor {
                Text(verbatim: PreviewStrings.formatTitle(descriptor))
                    .font(CompanionTypography.note)
                    .foregroundStyle(CompanionInk.hint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Text(verbatim: PreviewStrings.groupTitle(descriptor.group))
                    .font(CompanionTypography.note)
                    .foregroundStyle(CompanionInk.hint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Text(PreviewStrings.text(FileTypeCell.primaryModeKey(for: descriptor)))
                    .font(CompanionTypography.note)
                    .foregroundStyle(CompanionInk.hint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 8)
            if let formatID, let providers = overlappingProvidersByFormat[formatID], !providers.isEmpty {
                StatusPill(text: providers.joined(separator: ", "), tone: .caution)
                    .help(PreviewStrings.text(.providersGuidance))
            }
            if concealedCount > 0 {
                StatusPill(text: PreviewStrings.count(.previewInfoConcealedCount, concealedCount, locale: locale),
                           tone: .informational)
            }
            if let formatID, !settings.isEnabled(formatID) {
                StatusPill(text: PreviewStrings.text(.disabledTitle), tone: .caution)
                Button(PreviewStrings.text(.stateActionEnableFormat)) {
                    settings.setEnabled(true, for: formatID)
                    session.open(url, preferences: settings.snapshot)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: paneShape)
    }

    private var hasActiveOrLoadedPreview: Bool {
        session.result != nil || session.isLoading
    }

    @ViewBuilder private var previewPane: some View {
        if hasActiveOrLoadedPreview {
            NativePreviewPane(outcome: session.outcome, isLoading: session.isLoading,
                              typography: settings.snapshot.typography, generation: session.generation,
                              theme: settings.snapshot.theme, syntaxStyle: settings.snapshot.syntaxStyle,
                              providerName: providerName, limits: session.result?.effectiveBudget)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(paneShape)
                .overlay(paneShape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.12)))
        } else {
            emptyDropCanvas
        }
    }

    private var emptyDropCanvas: some View {
        let rejected = dropFeedback == .rejected
        let targeted = dropFeedback == .targeted
        return ZStack {
            VStack(spacing: 12) {
                (rejected ? CompanionSymbol.warning.image : Image(systemName: DropSymbol.hint.rawValue))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(rejected ? CompanionTone.caution.color : (targeted ? Color.accentColor : CompanionInk.hint))
                    .accessibilityHidden(true)
                Text(PreviewStrings.text(session.pickerFailed ? .pickerFailed : .previewEmptyTitle))
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text(PreviewStrings.text(rejected ? .previewDropRejected : .previewDropHint))
                    .foregroundStyle(rejected ? .primary : CompanionInk.hint)
                    .multilineTextAlignment(.center)
                Button(PreviewStrings.text(.openFile)) { session.presentsFileImporter = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.08) : Color.clear, in: paneShape)
        .clipShape(paneShape)
        .overlay(paneShape.strokeBorder(outlineColor(rejected: rejected, targeted: targeted),
                                        style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [6, 4])))
        .overlay {
            dropTargetOverlay
        }
    }

    private var paneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
    }

    private var dropStrip: some View {
        let rejected = dropFeedback == .rejected
        let targeted = dropFeedback == .targeted
        let outline = RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
        return HStack(spacing: 8) {
            (rejected ? CompanionSymbol.warning.image : Image(systemName: DropSymbol.hint.rawValue))
                .foregroundStyle(rejected ? CompanionTone.caution.color : (targeted ? Color.accentColor : CompanionInk.hint))
                .accessibilityHidden(true)
            Text(PreviewStrings.text(rejected ? .previewDropRejected : .previewDropHint))
                .font(CompanionTypography.note)
                .foregroundStyle(rejected ? .primary : CompanionInk.hint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.clear, in: outline)
        .overlay(outline.strokeBorder(outlineColor(rejected: rejected, targeted: targeted),
                                      style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [6, 4])))
        .overlay {
            dropTargetOverlay
        }
    }

    private var dropTargetOverlay: some View {
        // A refused drop is announced once per drop; hovering over the target says nothing.
        DirectPreviewDropTarget(feedback: $dropFeedback, rejected: {
            CompanionAnnouncer.announce(PreviewStrings.text(.previewDropRejected))
        }, open: { url in
            session.open(url, preferences: settings.snapshot)
        })
    }

    private func outlineColor(rejected: Bool, targeted: Bool) -> Color {
        if targeted { return .accentColor }
        if rejected { return CompanionTone.caution.color }
        return Color.primary.opacity(contrast == .increased ? 0.55 : 0.25)
    }
}

private enum DropSymbol: String {
    case hint = "arrow.down.doc"
}

private extension PreviewStrings {
    static func formatTitle(_ descriptor: FormatDescriptor) -> String {
        PreviewStrings.text(catalogKey: descriptor.nameKey)
    }

    static func groupTitle(_ group: FormatGroup) -> String {
        switch group {
        case .text: PreviewStrings.text(.fileTypeGroupText)
        case .structured: PreviewStrings.text(.fileTypeGroupStructured)
        case .database: PreviewStrings.text(.fileTypeGroupDatabase)
        case .containers: PreviewStrings.text(.fileTypeGroupContainers)
        case .media: PreviewStrings.text(.fileTypeGroupMedia)
        }
    }
}
