import Foundation

/// A sentence about how a diagram is shown, kept as a value so the wording is made in one place from the presentation
/// locale. A diagram never stops fitting without one of these saying so (decision 027, Q-77). The values carry
/// numbers only, never file text. What a Markdown file holds (which of several diagram fences is drawn) is worded
/// with its receipt, `MarkdownDiagramFences.Receipt`.
enum DiagramNotice: Equatable, Sendable {
    /// The diagram is drawn at `scale` times its natural size, the smallest size that stays readable, and continues
    /// beyond the view.
    case readable(scale: Double)

    func text(locale: Locale) -> String {
        switch self {
        case .readable(let scale):
            return PreviewStrings.format(.diagramNoticeReadable, arguments: [Self.percentText(scale, locale: locale)],
                                         locale: locale)
        }
    }

    /// The notice as the preview's typed notice: what is not shown goes to the limits slot at the bottom.
    func presentationNotice(locale: Locale) -> PresentationNotice {
        PresentationNotice(kind: .limit, text: text(locale: locale))
    }

    /// A scale as a whole-number percentage in the presentation locale ("60%"; "60 %" in German).
    static func percentText(_ scale: Double, locale: Locale) -> String {
        let percent = NumberFormatter()
        percent.numberStyle = .percent
        percent.locale = locale
        percent.maximumFractionDigits = 0
        return percent.string(from: NSNumber(value: scale)) ?? ""
    }
}
