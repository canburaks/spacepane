import CoreGraphics
import Foundation

/// Geometry of the continuous page column: one frame per image, sized from its pixel dimensions before any
/// pixel is decoded, so placeholders hold the final layout while images load lazily. Pure value logic with no
/// AppKit state, so the rules are testable without a window.
///
/// Rules (document coordinates have a top-left origin):
/// - Pages fit the available width, centered, and are never magnified beyond `maximumUpscale` times their
///   native size in points, so a small cover does not stretch across a wide window.
/// - Each page frame includes a caption band below the picture.
/// - `decodePixelSize` bounds the pixels a decode may produce: the longer side never exceeds 4,096 and the
///   area never exceeds 8 megapixels, whatever the display size.
struct ImagePagesLayout: Equatable, Sendable {
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 16
    static let pageSpacing: CGFloat = 16
    static let captionHeight: CGFloat = 22
    static let maximumUpscale: CGFloat = 2
    static let maximumDecodeSide = 4_096
    static let maximumDecodeArea = 8_000_000

    /// Full frame of each page (picture plus caption band).
    let frames: [CGRect]
    /// Height of the picture inside each frame.
    let pictureHeights: [CGFloat]
    let contentSize: CGSize

    static let empty = ImagePagesLayout(frames: [], pictureHeights: [], contentSize: .zero)

    init(frames: [CGRect], pictureHeights: [CGFloat], contentSize: CGSize) {
        self.frames = frames
        self.pictureHeights = pictureHeights
        self.contentSize = contentSize
    }

    /// - Parameters:
    ///   - pixelSizes: validated pixel dimensions of each page (already in display orientation).
    ///   - viewportWidth: width of the visible column in points.
    ///   - backingScale: pixels per point of the window's screen.
    init(pixelSizes: [CGSize], viewportWidth: CGFloat, backingScale: CGFloat) {
        let scale = max(1, backingScale)
        let column = max(1, viewportWidth - 2 * Self.horizontalInset)
        var frames: [CGRect] = []
        var heights: [CGFloat] = []
        var y = Self.verticalInset
        for size in pixelSizes {
            let width = max(1, size.width)
            let height = max(1, size.height)
            let displayWidth = max(1, min(column, (width / scale * Self.maximumUpscale).rounded(.down)))
            let pictureHeight = max(1, (displayWidth * height / width).rounded())
            let x = ((viewportWidth - displayWidth) / 2).rounded(.down)
            frames.append(CGRect(x: x, y: y, width: displayWidth, height: pictureHeight + Self.captionHeight))
            heights.append(pictureHeight)
            y += pictureHeight + Self.captionHeight + Self.pageSpacing
        }
        let contentHeight = pixelSizes.isEmpty ? 0 : y - Self.pageSpacing + Self.verticalInset
        self.init(frames: frames, pictureHeights: heights, contentSize: CGSize(width: viewportWidth, height: contentHeight))
    }

    /// Indices of pages whose frame intersects `minY...maxY`, found by binary search on the page tops.
    func indices(intersecting minY: CGFloat, _ maxY: CGFloat) -> Range<Int> {
        guard !frames.isEmpty, maxY >= minY else { return 0..<0 }
        // First page whose bottom edge is at or below `minY`.
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].maxY < minY { low = middle + 1 } else { high = middle }
        }
        let first = low
        // First page that starts after `maxY`.
        low = first
        high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].minY <= maxY { low = middle + 1 } else { high = middle }
        }
        return first..<max(first, low)
    }

    /// Index of the last page whose top edge is at or above `y`, or `nil` when `y` is above the first page.
    func lastIndex(startingAtOrBefore y: CGFloat) -> Int? {
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].minY <= y { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }

    /// Largest decoded side, in pixels, to request for a page shown `displayWidth` points wide.
    static func decodePixelSize(pixelWidth: Int, pixelHeight: Int, displayWidth: CGFloat, backingScale: CGFloat) -> Int {
        let width = CGFloat(max(1, pixelWidth))
        let height = CGFloat(max(1, pixelHeight))
        let longest = max(width, height)
        // Enough pixels to fill the display width, but never more than the image has.
        var factor = min(1, max(1, displayWidth * max(1, backingScale)) / width)
        factor = min(factor, CGFloat(maximumDecodeSide) / longest)
        let area = width * height * factor * factor
        if area > CGFloat(maximumDecodeArea) { factor *= (CGFloat(maximumDecodeArea) / area).squareRoot() }
        return max(16, min(maximumDecodeSide, Int((longest * factor).rounded(.up))))
    }
}
