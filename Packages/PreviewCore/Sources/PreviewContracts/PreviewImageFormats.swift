import Foundation
import UniformTypeIdentifiers

/// The encoded raster families that adapters may produce and renderers may decode.
/// Signatures and ImageIO identifiers must agree; broad image conformance is insufficient.
public enum PreviewImageFormat: CaseIterable, Hashable, Sendable {
    case jpeg, png, gif, webP, heic, avif

    public static func sniff(_ data: Data) -> Self? {
        let head = [UInt8](data.prefix(12))
        func has(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            head.count >= offset + bytes.count && head[offset..<(offset + bytes.count)].elementsEqual(bytes)
        }
        if has([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if has([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if has(Array("GIF87a".utf8)) || has(Array("GIF89a".utf8)) { return .gif }
        if has(Array("RIFF".utf8)), has(Array("WEBP".utf8), at: 8) { return .webP }
        if has(Array("ftyp".utf8), at: 4), head.count >= 12 {
            switch String(decoding: head[8..<12], as: UTF8.self) {
            case "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1": return .heic
            case "avif", "avis": return .avif
            default: return nil
            }
        }
        return nil
    }

    public func accepts(imageSourceTypeIdentifier identifier: String) -> Bool {
        switch self {
        case .jpeg: identifier == UTType.jpeg.identifier
        case .png: identifier == UTType.png.identifier
        case .gif: identifier == UTType.gif.identifier
        case .webP: identifier == UTType.webP.identifier
        case .heic: [UTType.heic.identifier, UTType.heif.identifier, "public.heics"].contains(identifier)
        case .avif: ["public.avif", "public.avis"].contains(identifier)
        }
    }

    /// Candidate selection before archive bytes are read; it never establishes the actual format.
    public static func hasImageSuffix(_ path: String) -> Bool {
        let suffix = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "jpe", "png", "gif", "webp", "heic", "heif", "avif"].contains(suffix)
    }
}

/// Source-pixel bounds are independent of the smaller bitmap a renderer requests from ImageIO.
public enum PreviewImageLimits {
    public static let maximumSourcePixels = 40_000_000
    public static let serialDecodeThresholdPixels = 16_000_000

    public static func sourcePixelCount(width: Int, height: Int) -> Int? {
        let sides = 1...PreviewImage.maximumPixelDimension
        guard sides.contains(width), sides.contains(height) else { return nil }
        let product = width.multipliedReportingOverflow(by: height)
        guard !product.overflow, product.partialValue <= maximumSourcePixels else { return nil }
        return product.partialValue
    }
}
