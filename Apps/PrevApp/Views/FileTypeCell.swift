import SwiftUI
import PreviewContracts
import PreviewRenderers

/// One catalog type: a checkbox, its localized name and a short pattern caption.
struct FileTypeCell: View {
    let format: FormatDescriptor
    let settings: CompanionSettings
    var overlappingProviders: [String] = []
    @Environment(\.locale) private var locale

    var body: some View {
        let name = PreviewStrings.text(catalogKey: format.nameKey)
        let description = PreviewStrings.text(catalogKey: format.descriptionKey)
        let filenames = FormatFilenameSummary(format)
        // The short form keeps a type with hundreds of patterns to two lines and a short spoken label (CO-09).
        let patterns = filenames.shortText(locale: locale)
        Toggle(isOn: Binding(get: { settings.isEnabled(format.id) },
                             set: { settings.setEnabled($0, for: format.id) })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: name).lineLimit(2)
                    primaryModeBadge
                    if !overlappingProviders.isEmpty {
                        StatusPill(text: overlappingProviders.joined(separator: ", "), tone: .caution)
                            .help(PreviewStrings.text(.providersGuidance))
                    }
                    if !format.defaultEnabled { offByDefaultBadge }
                }
                if !filenames.patterns.isEmpty {
                    Text(verbatim: patterns)
                        .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(filenames.patterns.isEmpty ? description : description + "\n" + patterns)
        .accessibilityHint(Text(verbatim: description))
    }

    private var primaryModeBadge: some View {
        Text(PreviewStrings.text(Self.primaryModeKey(for: format)))
            .font(CompanionTypography.note).lineLimit(1)
            .foregroundStyle(CompanionInk.hint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var offByDefaultBadge: some View {
        Text(PreviewStrings.text(.fileTypesOffByDefault))
            .font(CompanionTypography.note).lineLimit(1)
            .foregroundStyle(CompanionInk.hint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .fixedSize()
    }

    static func primaryModeKey(for format: FormatDescriptor) -> PreviewStrings.Key {
        if format.id == .folder {
            return .previewModeTree
        }
        if [.webVTT, .subRip, .subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD].contains(format.id) {
            return .previewModeCues
        }
        switch format.primaryView {
        case .geometry: return .cadViewportLabel
        case .rendered: return .previewModeRendered
        case .pages: return .previewModePages
        case .diagram: return .previewModeDiagram
        case .table: return .previewModeTable
        case .rows: return .summaryRows
        case .plot: return .previewModePlot
        case .records: return .previewModeRecords
        case .files: return .previewModeFiles
        case .outline: return .previewModeOutline
        case .summary: return .previewModeSummary
        case .source: return .previewModeSource
        }
    }
}
