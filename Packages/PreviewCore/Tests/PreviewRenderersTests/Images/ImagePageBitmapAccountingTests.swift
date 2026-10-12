import AppKit
import CoreGraphics
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Image page bitmap storage accounting", .serialized)
@MainActor
struct ImagePageBitmapAccountingTests {
    private func padded16BitBitmap(width: Int, height: Int, bytesPerRow: Int) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(count: bytesPerRow * height) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                                    bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @Test func theActualRowStrideIncludesPaddingAndSixteenBitComponents() throws {
        let bitmap = try padded16BitBitmap(width: 3, height: 2, bytesPerRow: 32)
        let page = ImagePageFrameView(frame: .zero)
        page.setImage(bitmap)
        #expect(page.decodedBytes == 64)
        #expect(page.decodedBytes != bitmap.width * bitmap.height * 4)
        page.setImage(nil)
        #expect(page.decodedBytes == 0)
    }

    @Test func aBitmapThatExceedsTheActualResidentBudgetIsReleased() async throws {
        let bitmap = DecodedPageImage(image: try padded16BitBitmap(width: 100, height: 100, bytesPerRow: 832))
        let scheduler = ImagePageScheduler(decode: { _, _ in bitmap })
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), scheduler: scheduler)
        view.layoutSubtreeIfNeeded()
        view.residentByteLimit = 50_000 // The old RGBA8 estimate fits; the actual 83,200-byte storage does not.
        let deliveries = ImageDeliveryProbe()
        let deliver = scheduler.deliver
        scheduler.deliver = { index, result in deliver?(index, result); deliveries.record(index) }
        let modes = SafePreviewModes(presentation(.comicBook, images: testPages(1, width: 100, height: 100)),
                                    locale: Locale(identifier: "en_US_POSIX"))
        view.display(modes, mode: .pages, style: testStyle(locale: Locale(identifier: "en_US_POSIX")))
        await deliveries.waitForCount(1)
        #expect(view.residentBytes == 0)
        #expect(view.pageView(at: 0)?.isUnavailable == true)
        view.clear()
    }
}
