import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewTestSupport
@testable import PreviewThumbnails

@Suite("Thumbnail image fit")
struct ThumbnailImageFitTests {
    @Test func aWideImageFitsTheWidthAndIsCentered() {
        let rect = ThumbnailImageFit.rect(imageSize: CGSize(width: 400, height: 200), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func aTallImageFitsTheHeightInsideOffsetBounds() {
        let rect = ThumbnailImageFit.rect(imageSize: CGSize(width: 100, height: 400), in: CGRect(x: 10, y: 20, width: 80, height: 40))
        #expect(abs(rect.height - 40) < 0.0001 && abs(rect.width - 10) < 0.0001)
        #expect(abs(rect.midX - 50) < 0.0001 && abs(rect.midY - 40) < 0.0001)
    }

    @Test func smallImagesAreScaledUpToFillTheBoundsOnOneAxis() {
        let rect = ThumbnailImageFit.rect(imageSize: CGSize(width: 10, height: 10), in: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(rect.width == 100 && rect.height == 100 && rect.minX == 50)
    }

    @Test func degenerateInputsGiveAnEmptyRect() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        for size in [CGSize.zero, CGSize(width: -5, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: CGFloat(Double.nan))] {
            let rect = ThumbnailImageFit.rect(imageSize: size, in: bounds)
            #expect(rect.width == 0 && rect.height == 0)
        }
        #expect(ThumbnailImageFit.rect(imageSize: CGSize(width: 10, height: 10), in: .zero).isEmpty)
    }

    @Test func fittedRectNeverLeavesTheBounds() {
        let bounds = CGRect(x: 3, y: 7, width: 90, height: 55)
        for (w, h) in [(1, 1), (3, 200), (200, 3), (1000, 999), (16_384, 1)] {
            let rect = ThumbnailImageFit.rect(imageSize: CGSize(width: w, height: h), in: bounds)
            #expect(bounds.insetBy(dx: -0.0001, dy: -0.0001).contains(rect))
        }
    }
}

@Suite("Thumbnail image decoding")
struct ThumbnailImageDecodingTests {
    private func picture(_ data: Data, width: Int, height: Int, role: PreviewImage.Role = .cover) -> PreviewImage {
        PreviewImage(data: data, pixelWidth: width, pixelHeight: height, role: role)
    }

    @Test func decodesToTheRequestedPixelBound() throws {
        let png = picture(syntheticImage(width: 600, height: 300), width: 600, height: 300)
        let image = try #require(ThumbnailImageDecoder.decode(png, maximumPixelExtent: 100, limits: .standard))
        #expect(max(image.width, image.height) <= 100)
        #expect(image.width == 100 && image.height == 50)
    }

    @Test func neverUpscales() throws {
        let png = picture(syntheticImage(width: 32, height: 16), width: 32, height: 16)
        let image = try #require(ThumbnailImageDecoder.decode(png, maximumPixelExtent: 1_024, limits: .standard))
        #expect(image.width == 32 && image.height == 16)
    }

    @Test func decodesJPEGAndOtherAllowedTypes() throws {
        for type in [UTType.jpeg, .png, .gif] {
            let data = syntheticImage(width: 40, height: 30, type: type)
            let image = ThumbnailImageDecoder.decode(picture(data, width: 40, height: 30), maximumPixelExtent: 64, limits: .standard)
            #expect(image != nil, "\(type.identifier)")
        }
    }

    @Test func realAVIFAndHEICFixturesDecodeTheirFirstImage() throws {
        for data in [EmbeddedImageFixtures.avif, EmbeddedImageFixtures.heic] {
            let image = try #require(ThumbnailImageDecoder.decode(picture(data, width: 32, height: 24),
                                                                 maximumPixelExtent: 100, limits: .standard))
            #expect(image.width == 32 && image.height == 24)
        }
    }

    @Test func dimensionsMustMatchEvenWhenBothProductsAreWithinTheLimit() {
        let png = picture(syntheticImage(width: 20, height: 30), width: 10, height: 10)
        #expect(ThumbnailImageDecoder.decode(png, maximumPixelExtent: 64, limits: .standard) == nil)
    }

    @Test func orientedDimensionsMustMatchAndAreTransformed() throws {
        let data = syntheticImage(width: 20, height: 30)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let rotated = try #require(ThumbnailImageDecoder.decode(picture(output as Data, width: 30, height: 20),
                                                               maximumPixelExtent: 100, limits: .standard))
        #expect(rotated.width == 30 && rotated.height == 20)
        #expect(ThumbnailImageDecoder.decode(picture(output as Data, width: 20, height: 30),
                                            maximumPixelExtent: 100, limits: .standard) == nil)
    }

    @Test func thumbnailOnlyRasterFamiliesAreRefused() throws {
        func recognize(_ data: Data, as type: UTType) throws {
            let source = try #require(CGImageSourceCreateWithData(data as CFData,
                                      [kCGImageSourceShouldCache: false] as CFDictionary))
            #expect(CGImageSourceGetType(source) as String? == type.identifier)
            #expect(CGImageSourceGetCount(source) == 1)
            #expect(CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete)
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 16)
            #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 16)
        }
        for type in [UTType.tiff] {
            let data = syntheticImage(width: 16, height: 16, type: type)
            try recognize(data, as: type)
            #expect(ThumbnailImageDecoder.decode(picture(data, width: 16, height: 16),
                                                maximumPixelExtent: 64, limits: .standard) == nil)
        }
        func little32(_ value: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
        func big32(_ value: Int) -> Data { Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
        let png = syntheticImage(width: 16, height: 16)
        let ico = Data([0, 0, 1, 0, 1, 0, 16, 16, 0, 0, 1, 0, 32, 0]) + little32(png.count) + little32(22) + png
        let icns = Data("icns".utf8) + big32(png.count + 16) + Data("icp4".utf8) + big32(png.count + 8) + png
        let bmpParts: [Data] = [Data("BM".utf8), little32(822), Data(count: 4), little32(54), little32(40),
                               little32(16), little32(16), Data([1, 0, 24, 0]), Data(count: 4), little32(768),
                               Data(count: 16), Data(count: 768)]
        let bmp = bmpParts.reduce(into: Data()) { $0.append($1) }
        for (data, type) in [(ico, UTType.ico), (icns, UTType.icns), (bmp, UTType.bmp)] {
            try recognize(data, as: type)
            #expect(ThumbnailImageDecoder.decode(picture(data, width: 16, height: 16),
                                                maximumPixelExtent: 64, limits: .standard) == nil)
        }
    }

    @Test func refusesDeclaredDimensionsOverThePixelLimit() {
        var limits = ThumbnailLimits.standard
        limits.maximumImagePixels = 10_000
        let png = picture(syntheticImage(width: 90, height: 90), width: 200, height: 200)
        #expect(ThumbnailImageDecoder.decode(png, maximumPixelExtent: 64, limits: limits) == nil)
    }

    @Test func refusesImagesWhoseRealDimensionsExceedTheLimitWhateverIsDeclared() {
        var limits = ThumbnailLimits.standard
        limits.maximumImagePixels = 10_000
        // The adapter declared 10 x 10; the bytes hold 200 x 200.
        let png = picture(syntheticImage(width: 200, height: 200), width: 10, height: 10)
        #expect(ThumbnailImageDecoder.decode(png, maximumPixelExtent: 64, limits: limits) == nil)
    }

    @Test func refusesOversizedEncodedDataInvalidDimensionsAndNonImages() {
        var limits = ThumbnailLimits.standard
        limits.maximumImageBytes = 100
        let png = syntheticImage(width: 64, height: 64)
        #expect(png.count > 100)
        #expect(ThumbnailImageDecoder.decode(picture(png, width: 64, height: 64), maximumPixelExtent: 64, limits: limits) == nil)
        #expect(ThumbnailImageDecoder.decode(picture(png, width: 0, height: 64), maximumPixelExtent: 64, limits: .standard) == nil)
        #expect(ThumbnailImageDecoder.decode(picture(png, width: 64, height: 64), maximumPixelExtent: 0, limits: .standard) == nil)
        let notAnImage = Data("<svg xmlns='http://www.w3.org/2000/svg' width='9' height='9'/>".utf8)
        #expect(ThumbnailImageDecoder.decode(picture(notAnImage, width: 9, height: 9), maximumPixelExtent: 64, limits: .standard) == nil)
        let garbage = Data((0..<256).map { UInt8($0 & 0xFF) })
        #expect(ThumbnailImageDecoder.decode(picture(garbage, width: 9, height: 9), maximumPixelExtent: 64, limits: .standard) == nil)
    }

    @Test func truncatedImageDataIsRefusedOrBoundedNeverCrashes() {
        let png = syntheticImage(width: 64, height: 64)
        let truncated = png.prefix(png.count / 3)
        _ = ThumbnailImageDecoder.decode(picture(Data(truncated), width: 64, height: 64), maximumPixelExtent: 64, limits: .standard)
    }

    @Test func candidatesPreferCoverThenIconThenPageThenFigureAndAreBounded() {
        let data = Data([1])
        func image(_ role: PreviewImage.Role, valid: Bool = true) -> PreviewImage {
            PreviewImage(data: valid ? data : Data(), pixelWidth: 4, pixelHeight: 4, role: role)
        }
        let order = ThumbnailImageSelection.candidates(from: [image(.figure), image(.page), image(.icon), image(.cover), image(.cover, valid: false)])
        #expect(order.map(\.role) == [.cover, .icon, .page])
        #expect(ThumbnailImageSelection.candidates(from: []).isEmpty)
        #expect(ThumbnailImageSelection.candidates(from: [image(.figure, valid: false)]).isEmpty)
        let many = ThumbnailImageSelection.candidates(from: Array(repeating: image(.page), count: 20))
        #expect(many.count == ThumbnailImageSelection.maximumAttempts)
    }
}
