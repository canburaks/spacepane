import Foundation
import PreviewContracts

/// How a notebook's Rendered document is composed from its concealed JSON. The original layout stays the default,
/// so nothing changes for a caller that does not ask; the preview asks for the grouped layout together with the
/// figures the adapter extracted (`SafeNotebookDocument.renderResult(for:locale:)`).
struct NotebookRenderOptions: Equatable, Sendable {
    /// Figures the adapter extracted and validated (`PreviewImage.Role.figure`). An image output reads
    /// "Figure 2, shown in Pages" only when every PNG or JPEG placeholder in the notebook has exactly one of them;
    /// when the counts differ the renderer cannot know which figure is which, so it says only that the output is not
    /// shown.
    var figureCount = 0
    /// A thematic break between a code or raw cell with its outputs and the cells beside it, so each cell's input
    /// and outputs read as one group with a visible boundary.
    var separatesCellGroups = false

    /// The layout every notebook had before cell groups and figure references.
    static let original = NotebookRenderOptions()

    static func grouped(figureCount: Int) -> NotebookRenderOptions {
        NotebookRenderOptions(figureCount: max(0, figureCount), separatesCellGroups: true)
    }
}

extension SafeNotebookDocument {
    /// The Rendered document of a notebook presentation, grouped by cell and with its saved figures referenced.
    static func renderResult(for presentation: TextPresentation, locale: Locale) -> RenderResult? {
        renderResult(presentation.text, locale: locale,
                     options: .grouped(figureCount: NotebookFigureFacts.validFigureCount(in: presentation)))
    }
}

/// What the adapter's typed image list says about a notebook's saved figures; never read from payload text.
enum NotebookFigureFacts {
    static func validFigureCount(in presentation: TextPresentation) -> Int {
        presentation.images.filter { $0.role == .figure && $0.isValid }.count
    }
}
