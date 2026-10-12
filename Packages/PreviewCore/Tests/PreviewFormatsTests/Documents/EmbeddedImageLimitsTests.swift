import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

@Suite("Embedded image source pixel limits")
struct EmbeddedImageLimitsTests {
    @Test func aCompleteCompactPNGAboveFortyMegapixelsIsRefusedBeforePixelDecoding() throws {
        let bytes = EmbeddedImageFixtures.overFortyMegapixelsPNG
        #expect(bytes.count < 8_192)
        // This is a complete 8,000 by 5,001 PNG, not a patched or truncated header.
        #expect(try EmbeddedImageValidator.validate(bytes, role: .page, context: documentContext()) == nil)
    }

    @Test func aCompletePNGExactlyAtFortyMegapixelsKeepsItsRealDimensions() throws {
        let image = try #require(try EmbeddedImageValidator.validate(
            EmbeddedImageFixtures.exactlyFortyMegapixelsPNG, role: .page, context: documentContext()))
        #expect(image.pixelWidth == 8_000 && image.pixelHeight == 5_000)
    }
    @Test func realAVIFAndHEICHeadersUseTheSameOwnedFamilyPolicy() throws {
        for (data, format) in [(EmbeddedImageFixtures.avif, PreviewImageFormat.avif),
                               (EmbeddedImageFixtures.heic, PreviewImageFormat.heic)] {
            #expect(EmbeddedImageValidator.sniff(data) == format)
            let image = try #require(try EmbeddedImageValidator.validate(data, role: .cover, context: documentContext()))
            #expect(image.pixelWidth == 32 && image.pixelHeight == 24)
            #expect(PackageIconImages.validatedPNG(data) == nil)
        }
    }
}
