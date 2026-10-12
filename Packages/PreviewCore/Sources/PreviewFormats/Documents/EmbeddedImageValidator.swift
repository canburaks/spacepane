import Foundation
import ImageIO
import PreviewContracts

/// Validates encoded raster bytes taken from a document before they may become a `PreviewImage`.
///
/// Only JPEG, PNG, GIF, WebP, HEIC and AVIF are accepted, recognized by their signature rather than by a
/// file name or declared media type. Validation reads the container header through ImageIO to obtain the
/// pixel dimensions; it never decodes pixels, so a small file cannot make an adapter allocate a large
/// bitmap. Decoding is the renderer's job, at a bounded size and off the main actor.
enum EmbeddedImageValidator {
    typealias Format = PreviewImageFormat

    static func sniff(_ data: Data) -> Format? { Format.sniff(data) }

    /// A `PreviewImage` for `data`, or `nil` when it is not a valid accepted image within the bounds.
    ///
    /// - Throws: only cancellation or an expired deadline.
    static func validate(_ data: Data, role: PreviewImage.Role, context: RequestContext) throws -> PreviewImage? {
        try context.checkpoint()
        guard !data.isEmpty, data.count <= DocumentLimits.maximumEncodedImageBytes, let format = sniff(data) else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) >= 1,
              let identifier = CGImageSourceGetType(source) as String?, format.accepts(imageSourceTypeIdentifier: identifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        // EXIF orientations 5 through 8 rotate by a quarter turn; the renderer applies the transform, so
        // the layout dimensions are the displayed ones.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard PreviewImageLimits.sourcePixelCount(width: width, height: height) != nil else { return nil }
        try context.checkpoint()
        return PreviewImage(data: data, pixelWidth: width, pixelHeight: height, role: role)
    }

    /// Case-insensitive suffix check used to pick candidate archive members before any bytes are read.
    static func hasImageSuffix(_ path: String) -> Bool {
        Format.hasImageSuffix(path)
    }
}
