import CoreGraphics
import Foundation
import ImageIO
import PreviewContracts

/// The immutable bitmap is never mutated after ImageIO returns it.
struct DecodedPageImage: @unchecked Sendable {
    let image: CGImage
}

enum ImagePageDecoder {
    typealias NativeDecode = @Sendable (Data, Int) async -> DecodedPageImage?
    private struct Metadata {
        let width: Int
        let height: Int
        let sourcePixels: Int
    }

    /// Compatibility path for callers without adapter metadata. Actual source headers still govern admission.
    @concurrent
    static func decode(_ data: Data, maximumPixelSize: Int,
                       admission: ImageDecodeAdmission = .processWide,
                       nativeDecode: NativeDecode = makeThumbnail) async -> DecodedPageImage? {
        await decode(data, expected: nil, maximumPixelSize: maximumPixelSize,
                     admission: admission, nativeDecode: nativeDecode)
    }

    @concurrent
    static func decode(_ picture: PreviewImage, maximumPixelSize: Int,
                       admission: ImageDecodeAdmission = .processWide,
                       nativeDecode: NativeDecode = makeThumbnail) async -> DecodedPageImage? {
        guard picture.isValid,
              PreviewImageLimits.sourcePixelCount(width: picture.pixelWidth, height: picture.pixelHeight) != nil else { return nil }
        return await decode(picture.data, expected: picture, maximumPixelSize: maximumPixelSize,
                            admission: admission, nativeDecode: nativeDecode)
    }

    private static func decode(_ data: Data, expected: PreviewImage?, maximumPixelSize: Int,
                               admission: ImageDecodeAdmission, nativeDecode: NativeDecode) async -> DecodedPageImage? {
        guard !Task.isCancelled, let metadata = metadata(for: data) else { return nil }
        if let expected, expected.pixelWidth != metadata.width || expected.pixelHeight != metadata.height { return nil }
        let bounded = min(max(16, maximumPixelSize), ImagePagesLayout.maximumDecodeSide)
        let result = await admission.run(sourcePixelCount: metadata.sourcePixels, ifCancelled: Optional<DecodedPageImage>.none) {
            await nativeDecode(data, bounded)
        }
        return Task.isCancelled ? nil : result
    }

    /// Properties are inspected with caching disabled. No source object crosses the admission suspension;
    /// the native call reconstructs it from the same immutable bytes after acquiring its lease.
    private static func metadata(for data: Data) -> Metadata? {
        guard let format = PreviewImageFormat.sniff(data) else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) >= 1,
              let identifier = CGImageSourceGetType(source) as String?, format.accepts(imageSourceTypeIdentifier: identifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let sourcePixels = PreviewImageLimits.sourcePixelCount(width: width, height: height) else { return nil }
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return Metadata(width: width, height: height, sourcePixels: sourcePixels)
    }

    @concurrent
    private static func makeThumbnail(_ data: Data, _ maximumPixelSize: Int) async -> DecodedPageImage? {
        guard !Task.isCancelled else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard !Task.isCancelled, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedPageImage(image: image)
    }
}
