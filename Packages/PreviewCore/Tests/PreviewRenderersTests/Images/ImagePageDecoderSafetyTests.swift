import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewTestSupport
@testable import PreviewRenderers

@Suite("Image page decoder source validation", .serialized)
struct ImagePageDecoderSafetyTests {
    @Test func actualHeadersAboveFortyMegapixelsNeverReachTheNativeCall() async {
        let probe = NoncooperativeImageDecodeProbe()
        probe.open()
        let admission = ImageDecodeAdmission()
        // A forged small declaration cannot turn this real 40,008,000-pixel header into a small job.
        let forged = PreviewImage(data: EmbeddedImageFixtures.overFortyMegapixelsPNG,
                                  pixelWidth: 1, pixelHeight: 1, role: .page)
        #expect(await ImagePageDecoder.decode(forged, maximumPixelSize: 100, admission: admission,
                                             nativeDecode: probe.nativeDecode()) == nil)
        #expect(await ImagePageDecoder.decode(forged.data, maximumPixelSize: 100, admission: admission,
                                             nativeDecode: probe.nativeDecode()) == nil)
        #expect(probe.started == 0 && admission.runningCount == 0)
    }

    @Test func aMismatchWithinThePixelLimitStillNeverReachesTheNativeCall() async {
        let probe = NoncooperativeImageDecodeProbe()
        probe.open()
        let forged = PreviewImage(data: testPNG(20, 30), pixelWidth: 10, pixelHeight: 10, role: .page)
        #expect(await ImagePageDecoder.decode(forged, maximumPixelSize: 100,
                                             nativeDecode: probe.nativeDecode()) == nil)
        #expect(probe.started == 0)
    }

    @Test func theActualHeaderProductChoosesTheLargeExclusiveLease() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(observe: events.record)
        let largeProbe = NoncooperativeImageDecodeProbe()
        let smallProbe = NoncooperativeImageDecodeProbe()
        let largePicture = PreviewImage(data: EmbeddedImageFixtures.exactlyFortyMegapixelsPNG,
                                        pixelWidth: 8_000, pixelHeight: 5_000, role: .page)
        let smallPicture = PreviewImage(data: testPNG(4, 4), pixelWidth: 4, pixelHeight: 4, role: .page)
        let large = Task { await ImagePageDecoder.decode(largePicture, maximumPixelSize: 100, admission: admission,
                                                        nativeDecode: largeProbe.nativeDecode()) }
        await largeProbe.waitForStarted(1)
        let small = Task { await ImagePageDecoder.decode(smallPicture, maximumPixelSize: 100, admission: admission,
                                                        nativeDecode: smallProbe.nativeDecode()) }
        await events.waitForDecisions(2)
        #expect(admission.runningCount == 1 && admission.waitingCount == 1)
        #expect(smallProbe.started == 0)
        large.cancel()
        #expect(admission.runningCount == 1)
        largeProbe.open()
        #expect(await large.value == nil)
        await smallProbe.waitForStarted(1)
        smallProbe.open()
        #expect(await small.value != nil)
        #expect(admission.runningCount == 0)
    }

    @Test func orientedDimensionsMustAgreeWithTheAdapterMetadata() async throws {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, testBitmap(width: 20, height: 30),
                                  [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let data = output as Data
        let rotated = PreviewImage(data: data, pixelWidth: 30, pixelHeight: 20, role: .page)
        let image = try #require(await ImagePageDecoder.decode(rotated, maximumPixelSize: 100))
        #expect(image.image.width == 30 && image.image.height == 20)
        let unrotatedDeclaration = PreviewImage(data: data, pixelWidth: 20, pixelHeight: 30, role: .page)
        #expect(await ImagePageDecoder.decode(unrotatedDeclaration, maximumPixelSize: 100) == nil)
    }
}
