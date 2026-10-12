import CoreGraphics
import Foundation
import ImageIO
import PreviewContracts

/// Decodes a document picture through ImageIO at a bounded pixel size. Adapters validate the
/// container and declared dimensions but never decode; the actual decode happens here, after the
/// declared and the real dimensions have both been checked against the request's pixel limit.
enum ThumbnailImageDecoder {
    /// Returns nil for anything unreadable, oversized or not allowed. The first frame is used.
    static func decode(_ picture: PreviewImage, maximumPixelExtent: Int, limits: ThumbnailLimits) -> CGImage? {
        guard picture.isValid, picture.data.count <= limits.maximumImageBytes,
              let declaredPixels = PreviewImageLimits.sourcePixelCount(width: picture.pixelWidth, height: picture.pixelHeight),
              declaredPixels <= limits.maximumImagePixels, let format = PreviewImageFormat.sniff(picture.data),
              maximumPixelExtent > 0 else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(picture.data as CFData, sourceOptions),
              CGImageSourceGetCount(source) >= 1,
              let type = CGImageSourceGetType(source) as String?, format.accepts(imageSourceTypeIdentifier: type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let actualPixels = PreviewImageLimits.sourcePixelCount(width: width, height: height),
              actualPixels <= limits.maximumImagePixels else { return nil }
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard picture.pixelWidth == width, picture.pixelHeight == height else { return nil }
        // Never upscale: the bound is the smaller of the canvas and the picture itself.
        let bound = min(maximumPixelExtent, max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bound
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Aspect-fit math, kept apart from drawing so it is tested without a context.
public enum ThumbnailImageFit {
    /// The largest rectangle with the image's aspect ratio that fits `bounds`, centered in it.
    /// Degenerate inputs yield an empty rectangle at the bounds' center.
    public static func rect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else {
            return CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        }
        let ratio = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
