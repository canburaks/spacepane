import SwiftUI
import PreviewRenderers

/// The inline Undo row: what the last overwriting action did, and one button that takes it back (or, after an
/// undo, puts it back). It stays until the next change. The model announces the same sentence to VoiceOver
/// when the row appears, so people who never press Command-Z are told what happened too.
struct SettingsUndoNotice: View {
    let settings: CompanionSettings
    let notice: CompanionSettings.UndoNotice
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: notice.text(locale: locale)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(PreviewStrings.text(isApplied ? .undo : .redo)) {
                if isApplied { settings.undoLastAction() } else { settings.redoLastAction() }
            }
            .controlSize(.small)
        }
        .font(CompanionTypography.note)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var isApplied: Bool { notice.phase == .applied }
}
