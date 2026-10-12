import SwiftUI
import PreviewRenderers

struct DirectPreviewView: View {
    let session: PreviewSession
    let settings: CompanionSettings
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
                dropArea
                if let url = session.sourceURL {
                    Text(verbatim: url.lastPathComponent)
                        .font(CompanionTypography.sectionHeading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder private var previewPane: some View {
        Group {
            if let result = session.result {
                NativePreviewPane(result: result, typography: settings.snapshot.typography,
                                  generation: session.generation, theme: settings.snapshot.theme,
                                  syntaxStyle: settings.snapshot.syntaxStyle, providerName: providerName)
            } else if session.isLoading {
                ProgressView(PreviewStrings.text(.loading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Text(PreviewStrings.text(session.pickerFailed ? .pickerFailed : .previewEmptyTitle))
                        .font(.title2)
                        .multilineTextAlignment(.center)
                    Button(PreviewStrings.text(.openFile)) { session.presentsFileImporter = true }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(paneShape)
        .overlay(paneShape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.12)))
    }

    private var paneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
    }

    private var dropArea: some View {
        let rejected = dropFeedback == .rejected
        let targeted = dropFeedback == .targeted
        let outline = RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
        return HStack(spacing: 8) {
            (rejected ? CompanionSymbol.warning.image : Image(systemName: DropSymbol.hint.rawValue))
                .foregroundStyle(rejected ? CompanionTone.caution.color : (targeted ? Color.accentColor : CompanionInk.hint))
                .accessibilityHidden(true)
            Text(PreviewStrings.text(rejected ? .previewDropRejected : .previewDropHint))
                .foregroundStyle(rejected ? .primary : CompanionInk.hint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.clear, in: outline)
        .overlay(outline.strokeBorder(outlineColor(rejected: rejected, targeted: targeted),
                                      style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [6, 4])))
        .overlay {
            // A refused drop is announced once per drop; hovering over the target says nothing.
            DirectPreviewDropTarget(feedback: $dropFeedback, rejected: {
                CompanionAnnouncer.announce(PreviewStrings.text(.previewDropRejected))
            }, open: { url in
                session.open(url, preferences: settings.snapshot)
            })
        }
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
