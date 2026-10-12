import CoreGraphics

/// Validated Quick Look request geometry. Sizes are in points; the reply context holds `scale`
/// times as many pixels. Every allocation in the thumbnail path is bounded by this check.
public struct ThumbnailGeometry: Equatable, Sendable {
    /// Largest pixel extent accepted on either axis.
    public static let maximumPixelDimension: CGFloat = 4_096

    public let size: CGSize
    public let scale: CGFloat

    public init?(maximumSize: CGSize, scale: CGFloat) {
        guard maximumSize.width.isFinite, maximumSize.height.isFinite,
              maximumSize.width > 0, maximumSize.height > 0,
              scale.isFinite, scale > 0,
              maximumSize.width * scale <= Self.maximumPixelDimension,
              maximumSize.height * scale <= Self.maximumPixelDimension else { return nil }
        size = maximumSize
        self.scale = scale
    }

    /// The larger pixel extent of the reply context; the bound for any image decode.
    public var maximumPixelExtent: Int { Int((max(size.width, size.height) * scale).rounded(.up)) }
}

/// Page proportions shared by the generic glyph and content thumbnails: one portrait sheet, centered.
public enum ThumbnailPage {
    /// The content-free glyph. These fractions of the shorter canvas side predate content thumbnails.
    public static let glyph = (width: CGFloat(0.64), height: CGFloat(0.80))
    /// Content thumbnails keep the glyph's 4:5 proportions but fill more of the canvas so text stays legible.
    public static let content = (width: CGFloat(0.76), height: CGFloat(0.95))

    public static func rect(in canvas: CGSize, fractions: (width: CGFloat, height: CGFloat)) -> CGRect {
        let unit = min(canvas.width, canvas.height)
        let width = unit * fractions.width
        let height = unit * fractions.height
        return CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
    }
}

/// Fixed-pitch layout measures. Text is laid out in cells so the model can be built and tested
/// without a font: the renderer places each run at its cell column and clips to the page.
public struct ThumbnailMetrics: Equatable, Sendable {
    /// One cell is this fraction of the font size, the advance of a typical monospaced Latin glyph.
    public static let cellAdvanceRatio: CGFloat = 0.6
    public static let lineHeightRatio: CGFloat = 1.22
    /// A heading line is drawn this much larger and occupies this many ordinary rows.
    public static let headingScale: CGFloat = 1.25
    public static let headingRowCost: Double = 1.6
    /// Font size in pixels is a fraction of the page width, bounded so small pages stay a texture
    /// of text and large pages show a readable page rather than ever-larger glyphs.
    static let fontPixelRange: ClosedRange<CGFloat> = 7...15
    static let fontToPageWidth: CGFloat = 0.052

    public let canvas: CGSize
    public let pixelScale: CGFloat
    public let page: CGRect
    public let textArea: CGRect
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public let cellWidth: CGFloat
    public let columns: Int
    public let rows: Int

    public init(geometry: ThumbnailGeometry) {
        canvas = geometry.size
        pixelScale = geometry.scale
        page = ThumbnailPage.rect(in: geometry.size, fractions: ThumbnailPage.content)
        let pagePixels = page.width * geometry.scale
        let fontPixels = min(max(pagePixels * Self.fontToPageWidth, Self.fontPixelRange.lowerBound), Self.fontPixelRange.upperBound)
        fontSize = fontPixels / geometry.scale
        lineHeight = fontSize * Self.lineHeightRatio
        cellWidth = fontSize * Self.cellAdvanceRatio
        textArea = page.insetBy(dx: page.width * 0.075, dy: page.height * 0.06)
        columns = max(1, Int((textArea.width / cellWidth).rounded(.down)))
        rows = max(1, Int((textArea.height / lineHeight).rounded(.down)))
    }
}
