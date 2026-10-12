import Foundation
import ImageIO
import PreviewContracts

/// Picks and validates one application icon as encoded PNG bytes. Pixels are never decoded here: the
/// renderer decodes lazily with its own pixel bound. An icon is document content (the picture the
/// developer shipped) and carries no text this app interprets, so it may bypass text concealment.
enum PackageIconImages {
    /// Encoded icon bytes above this are skipped rather than carried through the presentation.
    static let maximumEncodedBytes = 262_144
    /// Larger icons would only add decode cost to a preview that shows them at a few hundred points.
    static let maximumPixelDimension = 2_048

    /// Accepts PNG data that ImageIO recognizes as one decodable image of bounded size. Apple's
    /// size-optimized (`CgBI`) iOS PNGs that ImageIO declines simply yield `nil`.
    static func validatedPNG(_ data: Data) -> PreviewImage? {
        guard data.count >= 33, data.count <= maximumEncodedBytes, PreviewImageFormat.sniff(data) == .png else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source) as String?,
              PreviewImageFormat.png.accepts(imageSourceTypeIdentifier: identifier),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...maximumPixelDimension).contains(width), (1...maximumPixelDimension).contains(height) else { return nil }
        return PreviewImage(data: data, pixelWidth: width, pixelHeight: height, role: .icon)
    }
}

/// Reads the PNG-encoded representations of an Apple icon (`.icns`) container. The container is a
/// big-endian header followed by typed, length-prefixed elements; legacy bitmap and JPEG 2000
/// elements are ignored, as are elements whose payload is not a PNG.
enum ICNSIcon {
    private static let magic: [UInt8] = Array("icns".utf8)
    private static let headerLength = 8
    private static let maximumElements = 64

    /// The largest bounded PNG representation, or `nil` when none is usable.
    static func largestImage(in data: Data, context: RequestContext) throws -> PreviewImage? {
        try context.checkpoint()
        let bytes = [UInt8](data)
        guard bytes.count >= headerLength, Array(bytes.prefix(4)) == magic,
              let declared = bigEndian(bytes, 4), Int(declared) <= bytes.count, Int(declared) >= headerLength else { return nil }
        let end = Int(declared)
        var offset = headerLength
        var best: PreviewImage?
        var elements = 0
        while offset + headerLength <= end {
            try context.checkpoint()
            elements += 1
            guard elements <= maximumElements, let length = bigEndian(bytes, offset + 4),
                  Int(length) >= headerLength, Int(length) <= end - offset else { break }
            let payload = Data(bytes[(offset + headerLength)..<(offset + Int(length))])
            if let image = PackageIconImages.validatedPNG(payload),
               best.map({ image.pixelWidth * image.pixelHeight > $0.pixelWidth * $0.pixelHeight }) ?? true {
                best = image
            }
            offset += Int(length)
        }
        return best
    }

    private static func bigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        return bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
