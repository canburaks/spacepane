import Foundation

/// The limits-strip notices of the modes that draw rather than list: Diagram and Plot. Both are pure functions of
/// the cached safe models, so the facade can ask on every display, and the Diagram mode does so without laying
/// anything out again. The one hook in `ModePresentationNotices` calls `notices(modes:mode:locale:)`; what depends on
/// the size of the view (how a diagram was fitted) is not here but in the view (`NativeDiagramView`).
enum DrawnModeNotices {
    static func notices(modes: SafePreviewModes, mode: NativePreviewMode, locale: Locale) -> [PresentationNotice] {
        switch mode {
        case .diagram: diagramNotices(modes: modes, locale: locale)
        case .plot: plotNotices(modes.plot)
        default: []
        }
    }

    /// "Diagram 2 of 3 is drawn" for a Markdown file with several diagram fences, so the others are not silently
    /// left as code. Nothing for a single fence, and nothing for a diagram that is not a fence of the document.
    private static func diagramNotices(modes: SafePreviewModes, locale: Locale) -> [PresentationNotice] {
        guard modes.diagram != nil, modes.markdown != nil, let receipt = modes.diagramReceipt, receipt.total > 1 else {
            return []
        }
        return [receipt.presentationNotice(locale: locale)]
    }

    /// That long paths show only some of their points, when the adapter thinned a path: a limit of the preview, not
    /// a caption of the drawing.
    private static func plotNotices(_ plot: SafePlot?) -> [PresentationNotice] {
        guard let plot, plot.simplified else { return [] }
        return [PresentationNotice(kind: .limit, text: PreviewStrings.text(.dataPlotSimplified))]
    }
}
