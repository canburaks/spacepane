import Foundation
import PreviewContracts

/// Provenance comes from the adapter's typed origin and validated figure list, never payload text.
enum NotebookPresentationNotices {
    static func notices(for presentation: TextPresentation, locale: Locale) -> [PresentationNotice] {
        guard presentation.formatID == .jupyterNotebook else { return [] }
        var notices: [PresentationNotice] = []
        if presentation.origin == .converted {
            notices.append(PresentationNotice(kind: .provenance, text: PreviewStrings.text(.notebookImageOutputsOmitted)))
        }
        if presentation.images.contains(where: { $0.role == .figure && $0.isValid }) {
            notices.append(PresentationNotice(kind: .provenance, text: PreviewStrings.text(.notebookFiguresInPages)))
        }
        return notices
    }
}
