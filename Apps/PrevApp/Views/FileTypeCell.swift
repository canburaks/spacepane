import SwiftUI
import PreviewContracts
import PreviewRenderers

/// One catalog type: a checkbox, its localized name and a short pattern caption.
struct FileTypeCell: View {
    let format: FormatDescriptor
    let settings: CompanionSettings
    @Environment(\.locale) private var locale

    var body: some View {
        let name = PreviewStrings.text(catalogKey: format.nameKey)
        let description = PreviewStrings.text(catalogKey: format.descriptionKey)
        let filenames = FormatFilenameSummary(format)
        let patterns = filenames.text(locale: locale)
        Toggle(isOn: Binding(get: { settings.isEnabled(format.id) },
                             set: { settings.setEnabled($0, for: format.id) })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: name).lineLimit(2)
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

    private var offByDefaultBadge: some View {
        Text(PreviewStrings.text(.fileTypesOffByDefault))
            .font(CompanionTypography.note).lineLimit(1)
            .foregroundStyle(CompanionInk.hint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .fixedSize()
    }
}
