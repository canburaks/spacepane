import CoreGraphics

/// Where the symbol and the words of a page frame whose picture could not be shown sit inside the picture rectangle
/// (top-left origin, the page column's coordinates). Pure value logic, so the rules are testable without a window.
///
/// - The pair is centered in the frame: the symbol above, the words below.
/// - A frame too narrow or too short for the words keeps the symbol alone; one too small for the symbol keeps only
///   its border, which every failed frame draws, so a small frame is never an empty gap.
struct PageFailureLayout: Equatable, Sendable {
    /// Space kept between the border and the symbol or words.
    static let inset: CGFloat = 8
    /// Largest side of the symbol.
    static let symbolSide: CGFloat = 24
    /// A symbol smaller than this is not recognizable, so it is left out.
    static let minimumSymbolSide: CGFloat = 12
    /// Gap between the symbol and the words.
    static let gap: CGFloat = 6
    /// Room for two lines of caption text.
    static let labelHeight: CGFloat = 32
    /// Narrowest frame that still gets words; narrower ones read badly wrapped.
    static let minimumLabelWidth: CGFloat = 72

    /// Frame of the symbol; zero when the picture is too small for one.
    let symbol: CGRect
    /// Frame of the words; nil when they do not fit.
    let label: CGRect?

    init(picture: CGRect) {
        let width = picture.width - 2 * Self.inset
        let height = picture.height - 2 * Self.inset
        let side = min(Self.symbolSide, width, height)
        guard width > 0, height > 0, side >= Self.minimumSymbolSide else {
            symbol = .zero
            label = nil
            return
        }
        let fitsLabel = width >= Self.minimumLabelWidth && height >= side + Self.gap + Self.labelHeight
        let groupHeight = fitsLabel ? side + Self.gap + Self.labelHeight : side
        let top = (picture.minY + Self.inset + (height - groupHeight) / 2).rounded()
        symbol = CGRect(x: (picture.midX - side / 2).rounded(), y: top, width: side, height: side)
        label = fitsLabel
            ? CGRect(x: picture.minX + Self.inset, y: top + side + Self.gap, width: width, height: Self.labelHeight)
            : nil
    }
}
