import CoreGraphics
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Image pages layout")
struct ImagePagesLayoutTests {
    private func layout(_ sizes: [(Int, Int)], width: CGFloat = 600, scale: CGFloat = 2) -> ImagePagesLayout {
        ImagePagesLayout(pixelSizes: sizes.map { CGSize(width: $0.0, height: $0.1) }, viewportWidth: width, backingScale: scale)
    }

    @Test func pagesFitTheColumnWidthAndKeepTheirAspectRatio() {
        // 2,000 x 3,000 px at 2x is 1,000 points wide natively; the 600-point viewport leaves a 568-point column.
        let result = layout([(2_000, 3_000)])
        let frame = result.frames[0]
        #expect(frame.width == 568)
        #expect(result.pictureHeights[0] == 852)
        #expect(frame.height == 852 + ImagePagesLayout.captionHeight)
        #expect(frame.minX == 16)   // Centered: (600 - 568) / 2.
        #expect(frame.minY == ImagePagesLayout.verticalInset)
    }

    @Test func smallPicturesAreNeverMagnifiedBeyondTwiceTheirPointSize() {
        // 100 px at 2x is 50 points; at most 2x that is 100 points, centered in the wide column.
        let result = layout([(100, 150)], width: 1_200)
        #expect(result.frames[0].width == 100)
        #expect(result.pictureHeights[0] == 150)
        #expect(result.frames[0].midX == 600)
    }

    @Test func framesStackWithSpacingAndContentSizeCoversThemAll() {
        let result = layout([(1_000, 1_000), (1_000, 2_000), (500, 500)])
        for index in 1..<result.frames.count {
            #expect(result.frames[index].minY - result.frames[index - 1].maxY == ImagePagesLayout.pageSpacing)
        }
        #expect(result.contentSize.height == result.frames.last!.maxY + ImagePagesLayout.verticalInset)
        #expect(result.contentSize.width == 600)
        #expect(layout([]).contentSize.height == 0)
        #expect(layout([]).frames.isEmpty)
    }

    @Test func placeholdersAreSizedFromPixelDimensionsAloneAndSurviveDegenerateSizes() {
        let result = layout([(0, 0), (1, 100_000), (100_000, 1)], width: 10)
        #expect(result.frames.count == 3)
        #expect(result.frames.allSatisfy { $0.width >= 1 && $0.height >= 1 && $0.minX.isFinite && $0.minY.isFinite })
    }

    @Test func narrowerViewportsRelayoutProportionally() {
        let wide = layout([(2_000, 3_000)], width: 1_000)
        let narrow = layout([(2_000, 3_000)], width: 400)
        #expect(wide.frames[0].width == 968)
        #expect(narrow.frames[0].width == 368)
        #expect(abs(narrow.pictureHeights[0] / narrow.frames[0].width - 1.5) < 0.01)
    }

    @Test func binarySearchFindsExactlyThePagesIntersectingARange() {
        let result = layout(Array(repeating: (1_000, 1_000), count: 50))
        let frame = result.frames
        // Brute-force reference over many windows, including gaps between pages.
        for minY in stride(from: -50 as CGFloat, to: result.contentSize.height + 50, by: 137) {
            for span in [0, 1, 40, 400, 5_000] as [CGFloat] {
                let maxY = minY + span
                let expected = frame.indices.filter { frame[$0].maxY >= minY && frame[$0].minY <= maxY }
                let found = result.indices(intersecting: minY, maxY)
                #expect(Array(found) == expected, "window \(minY)...\(maxY)")
            }
        }
        #expect(result.indices(intersecting: 10, 5).isEmpty)
        #expect(ImagePagesLayout.empty.indices(intersecting: 0, 100).isEmpty)
    }

    @Test func lastIndexAtOrBeforeFollowsPageTops() {
        let result = layout(Array(repeating: (1_000, 1_000), count: 5))
        #expect(result.lastIndex(startingAtOrBefore: 0) == nil)
        #expect(result.lastIndex(startingAtOrBefore: result.frames[0].minY) == 0)
        #expect(result.lastIndex(startingAtOrBefore: result.frames[2].minY - 1) == 1)
        #expect(result.lastIndex(startingAtOrBefore: 1_000_000) == 4)
    }

    // MARK: Decode bounds

    @Test func decodeSizeNeverExceedsFourThousandNinetySixOrEightMegapixels() {
        let tall = ImagePagesLayout.decodePixelSize(pixelWidth: 800, pixelHeight: 16_000, displayWidth: 800, backingScale: 2)
        #expect(tall <= ImagePagesLayout.maximumDecodeSide)
        let huge = ImagePagesLayout.decodePixelSize(pixelWidth: 12_000, pixelHeight: 9_000, displayWidth: 5_000, backingScale: 2)
        let factor = Double(huge) / 12_000
        #expect(huge <= 4_096)
        #expect(12_000 * 9_000 * factor * factor <= Double(ImagePagesLayout.maximumDecodeArea) * 1.02)
        let square = ImagePagesLayout.decodePixelSize(pixelWidth: 16_000, pixelHeight: 16_000, displayWidth: 8_000, backingScale: 2)
        #expect(Double(square) * Double(square) <= Double(ImagePagesLayout.maximumDecodeArea) * 1.02)
    }

    @Test func decodeSizeFillsTheDisplayWidthWithoutUpscalingBeyondTheImage() {
        // A 2,000 x 3,000 page shown 500 points wide at 2x needs 1,000 px of width: the longer side is 1,500.
        #expect(ImagePagesLayout.decodePixelSize(pixelWidth: 2_000, pixelHeight: 3_000, displayWidth: 500, backingScale: 2) == 1_500)
        // A small image is never asked for more than its own size.
        #expect(ImagePagesLayout.decodePixelSize(pixelWidth: 100, pixelHeight: 200, displayWidth: 900, backingScale: 2) == 200)
        // Degenerate inputs stay positive and bounded.
        let minimum = ImagePagesLayout.decodePixelSize(pixelWidth: 1, pixelHeight: 1, displayWidth: 1, backingScale: 1)
        #expect(minimum >= 16 && minimum <= 4_096)
    }
}
