import AppKit
import SwiftUI
import PreviewRenderers

/// A row in the About page's Acknowledgements card that opens one bundled notice folder in Finder. It is built
/// only for a folder this run carries (see `BundledNotices`), in the look of the page's link rows. If the system
/// cannot open the folder, the row says so in words under itself and VoiceOver announces the same sentence.
struct AboutNoticeRow: View {
    let folder: BundledNotices.Folder
    let url: URL
    @State private var openFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { openFolder() } label: { rowLabel }
                .buttonStyle(.plain)
                .help(hint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityHint(Text(verbatim: hint))
                .accessibilityAddTraits(.isButton)
            if openFailed { failureNote }
        }
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIconBadge(image: Image(systemName: NoticeSymbol.folder.rawValue), tone: .informational, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).foregroundStyle(CompanionInk.link)
                Text(verbatim: hint).font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: NoticeSymbol.open.rawValue)
                .foregroundStyle(.secondary)
                .flipsForRightToLeftLayoutDirection(true)
                .accessibilityHidden(true)
        }
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
        .contentShape(Rectangle())
    }

    private var failureNote: some View {
        Text(PreviewStrings.text(.aboutNoticesOpenFailed))
            .font(CompanionTypography.note)
            .foregroundStyle(CompanionInk.hint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, CompanionMetrics.rowVerticalPadding)
    }

    private func openFolder() {
        let opened = NSWorkspace.shared.open(url)
        openFailed = !opened
        if !opened { CompanionAnnouncer.announce(PreviewStrings.text(.aboutNoticesOpenFailed)) }
    }

    private var title: String {
        switch folder {
        case .openCascade: PreviewStrings.text(.aboutNoticesOpenCascadeTitle)
        case .colorSchemes: PreviewStrings.text(.aboutNoticesColorSchemesTitle)
        }
    }

    private var hint: String { PreviewStrings.text(.aboutNoticesOpenHint) }
}

private enum NoticeSymbol: String {
    case folder = "folder"
    case open = "arrow.up.right"
}
