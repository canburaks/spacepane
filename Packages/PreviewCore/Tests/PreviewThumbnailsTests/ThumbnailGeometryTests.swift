import CoreGraphics
import Testing
@testable import PreviewThumbnails

@Suite("Thumbnail geometry and metrics")
struct ThumbnailGeometryTests {
    @Test func acceptsOrdinaryRequests() throws {
        let geometry = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 128, height: 128), scale: 2))
        #expect(geometry.maximumPixelExtent == 256)
        let wide = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 256, height: 100), scale: 1))
        #expect(wide.maximumPixelExtent == 256)
    }

    @Test(arguments: [
        (CGFloat.nan, CGFloat(10), CGFloat(1)), (CGFloat(10), CGFloat.infinity, CGFloat(1)),
        (CGFloat(0), CGFloat(10), CGFloat(1)), (CGFloat(10), CGFloat(-3), CGFloat(1)),
        (CGFloat(10), CGFloat(10), CGFloat(0)), (CGFloat(10), CGFloat(10), CGFloat.nan),
        (CGFloat(2_049), CGFloat(10), CGFloat(2)), (CGFloat(10), CGFloat(4_097), CGFloat(1))
    ])
    func rejectsInvalidOrUnboundedRequests(width: CGFloat, height: CGFloat, scale: CGFloat) {
        #expect(ThumbnailGeometry(maximumSize: CGSize(width: width, height: height), scale: scale) == nil)
    }

    @Test func pixelLimitIsInclusive() {
        #expect(ThumbnailGeometry(maximumSize: CGSize(width: 2_048, height: 2_048), scale: 2) != nil)
    }

    @Test func contentPageKeepsTheGlyphAspectRatio() {
        let canvas = CGSize(width: 200, height: 200)
        let glyph = ThumbnailPage.rect(in: canvas, fractions: ThumbnailPage.glyph)
        let content = ThumbnailPage.rect(in: canvas, fractions: ThumbnailPage.content)
        #expect(abs(glyph.width / glyph.height - content.width / content.height) < 0.001)
        #expect(content.width > glyph.width)
        #expect(CGRect(origin: .zero, size: canvas).contains(content))
        // Centered on both axes.
        #expect(abs(content.midX - 100) < 0.001 && abs(content.midY - 100) < 0.001)
    }

    @Test func glyphPageMatchesTheOriginalProviderGeometry() {
        // The pre-content provider drew a 0.64 x 0.80 page of the shorter side, centered.
        let size = CGSize(width: 300, height: 200)
        let page = ThumbnailPage.rect(in: size, fractions: ThumbnailPage.glyph)
        #expect(abs(page.width - 200 * 0.64) < 0.001)
        #expect(abs(page.height - 200 * 0.80) < 0.001)
        #expect(abs(page.minX - (300 - 200 * 0.64) / 2) < 0.001)
    }

    @Test(arguments: [64, 96, 128, 256, 512, 1_024])
    func metricsStayInsideThePageAndAreNeverEmpty(side: Int) {
        for scale in [CGFloat(1), 2] {
            guard let geometry = ThumbnailGeometry(maximumSize: CGSize(width: side, height: side), scale: scale) else { continue }
            let metrics = ThumbnailMetrics(geometry: geometry)
            #expect(metrics.columns >= 1 && metrics.rows >= 1)
            #expect(metrics.page.contains(metrics.textArea))
            #expect(CGFloat(metrics.columns) * metrics.cellWidth <= metrics.textArea.width + 0.001)
            #expect(CGFloat(metrics.rows) * metrics.lineHeight <= metrics.textArea.height + 0.001)
            let fontPixels = metrics.fontSize * scale
            #expect(fontPixels >= 6.99 && fontPixels <= 15.01)
        }
    }

    @Test func largerThumbnailsShowMoreTextNotLargerGlyphs() {
        let small = ThumbnailMetrics(geometry: geometry(128))
        let large = ThumbnailMetrics(geometry: geometry(512))
        #expect(large.columns > small.columns)
        #expect(large.rows > small.rows)
    }

    @Test func degenerateCanvasesStillProduceUsableMetrics() throws {
        let tiny = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 1, height: 1), scale: 1))
        let metrics = ThumbnailMetrics(geometry: tiny)
        #expect(metrics.columns >= 1 && metrics.rows >= 1)
    }
}
