import Foundation
import Testing
import PreviewContracts

@Suite("Owned image format and pixel policy")
struct PreviewImageFormatsTests {
    @Test func onlyTheExistingSixRasterFamiliesAreOwned() {
        #expect(Set(PreviewImageFormat.allCases) == [.jpeg, .png, .gif, .webP, .heic, .avif])
        let identifiers: [(PreviewImageFormat, [String])] = [
            (.jpeg, ["public.jpeg"]), (.png, ["public.png"]), (.gif, ["com.compuserve.gif"]),
            (.webP, ["org.webmproject.webp"]), (.heic, ["public.heic", "public.heif", "public.heics"]),
            (.avif, ["public.avif", "public.avis"])
        ]
        for (format, accepted) in identifiers {
            for identifier in accepted { #expect(format.accepts(imageSourceTypeIdentifier: identifier)) }
            for identifier in ["public.image", "public.tiff", "com.microsoft.bmp", "com.microsoft.ico", "com.apple.icns"] {
                #expect(!format.accepts(imageSourceTypeIdentifier: identifier))
            }
        }
        #expect(!PreviewImageFormat.jpeg.accepts(imageSourceTypeIdentifier: "public.png"))
        #expect(!PreviewImageFormat.heic.accepts(imageSourceTypeIdentifier: "public.avif"))
    }

    @Test func theSuffixPolicyRemainsExactAndCaseInsensitive() {
        for suffix in ["jpg", "jpeg", "jpe", "png", "gif", "webp", "heic", "heif", "avif"] {
            #expect(PreviewImageFormat.hasImageSuffix("folder/image." + suffix.uppercased()))
        }
        for path in ["png", "image.tif", "image.tiff", "image.bmp", "image.ico", "image.icns", "image.svg", "image.avis"] {
            #expect(!PreviewImageFormat.hasImageSuffix(path))
        }
    }

    @Test func theBrandSignaturePolicyRemainsExact() {
        for brand in ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"] {
            #expect(PreviewImageFormat.sniff(Data(count: 4) + Data(("ftyp" + brand).utf8)) == .heic)
        }
        for brand in ["avif", "avis"] {
            #expect(PreviewImageFormat.sniff(Data(count: 4) + Data(("ftyp" + brand).utf8)) == .avif)
        }
        for bytes in [Data(), Data("ftypavif".utf8), Data(count: 4) + Data("ftypmp42".utf8), Data("BM".utf8)] {
            #expect(PreviewImageFormat.sniff(bytes) == nil)
        }
    }

    @Test func sourcePixelProductsAreBoundedBeforeTheyCanOverflow() {
        #expect(PreviewImageLimits.maximumSourcePixels == 40_000_000)
        #expect(PreviewImageLimits.serialDecodeThresholdPixels == 16_000_000)
        #expect(PreviewImageLimits.sourcePixelCount(width: 8_000, height: 5_000) == 40_000_000)
        #expect(PreviewImageLimits.sourcePixelCount(width: 8_000, height: 5_001) == nil)
        for (width, height) in [(0, 1), (1, -1), (16_385, 1), (Int.max, Int.max), (Int.min, 1)] {
            #expect(PreviewImageLimits.sourcePixelCount(width: width, height: height) == nil)
        }
    }
}
