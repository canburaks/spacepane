import AppKit

/// Rendered prose has a system text face and a comfortable measure. This is a presentation rule,
/// not a preference: source/code typography and persisted settings retain their existing meaning.
@MainActor
struct ReadingLayout {
    let font: NSFont
    let paragraphStyle: NSParagraphStyle
    let measure: CGFloat

    init(typography: NativeTextTypography) {
        font = .systemFont(ofSize: typography.font.pointSize)
        let paragraph = typography.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4
        paragraph.lineSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping
        paragraphStyle = paragraph
        let advances = ("abcdefghijklmnopqrstuvwxyz" as NSString).size(withAttributes: [.font: font]).width
        measure = max(1, advances / 26) * 70
    }

    func horizontalInset(viewportWidth: CGFloat) -> CGFloat {
        max(PreviewChrome.inset, (viewportWidth - measure) / 2)
    }
}
