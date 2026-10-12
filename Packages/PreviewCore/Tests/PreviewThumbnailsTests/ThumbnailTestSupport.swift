import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewThumbnails

/// The synthetic credential used across the suite. It is never a real secret.
let syntheticSecret = "synthetic-secret-value"

/// Thumbnails run with a generous pipeline deadline in tests so a loaded machine or a debug build
/// never makes a content test flaky. The deadline itself is covered by dedicated tests.
let relaxedLimits: ThumbnailLimits = {
    var limits = ThumbnailLimits.standard
    limits.textBudget = PreviewBudget(maxInputBytes: 262_144, maxOutputUTF8Bytes: 524_288, maxJSONDepth: 32,
                                      maxJSONNodes: 100_000, maxTextLines: 20_000, maxLineUTF8Bytes: 262_144,
                                      maxMilliseconds: 10_000)
    limits.databaseBudget = PreviewBudget(maxInputBytes: 4_194_304, maxOutputUTF8Bytes: 2_097_152, maxJSONDepth: 32,
                                          maxJSONNodes: 20_000, maxTextLines: 20_000, maxLineUTF8Bytes: 32_768,
                                          maxMilliseconds: 10_000)
    limits.hardTimeout = .seconds(30)
    return limits
}()

let standardGeometry = ThumbnailGeometry(maximumSize: CGSize(width: 128, height: 128), scale: 2)!

func geometry(_ side: CGFloat, scale: CGFloat = 2) -> ThumbnailGeometry {
    ThumbnailGeometry(maximumSize: CGSize(width: side, height: side), scale: scale)!
}

final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

struct SpyReader: PreviewFileReading {
    let reads: Counter
    let inner = BoundedFileReader()
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return try inner.read(url: url, context: context)
    }
}

/// Blocks the calling thread without checking cancellation, like a stalled network volume.
func blockThread(_ seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

struct BlockingReader: PreviewFileReading {
    let seconds: TimeInterval
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        blockThread(seconds)
        return FileBytes(data: Data("late".utf8))
    }
}

struct Fixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    @discardableResult func file(_ name: String, _ text: String) throws -> URL { try file(name, Data(text.utf8)) }
    @discardableResult func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

func makeService(registrations: [AdapterRegistration] = StandardFormatAdapters.registrations,
                 snapshot: PreviewPreferencesSnapshot? = .defaults,
                 reader: any PreviewFileReading = BoundedFileReader(),
                 limits: ThumbnailLimits = relaxedLimits) -> ContentThumbnailService {
    ContentThumbnailService(registrations: registrations, preferences: .fixed(snapshot), reader: reader, limits: limits)
}

extension ThumbnailOutcome {
    var scene: ThumbnailScene? {
        if case .content(let scene) = self { return scene }
        return nil
    }
    var reason: ThumbnailFallbackReason? {
        if case .generic(let reason) = self { return reason }
        return nil
    }
}

/// An RGBA bitmap that a thumbnail is drawn into, as Quick Look supplies one: points scaled to pixels.
struct Canvas {
    let context: CGContext
    let width: Int
    let height: Int

    init(_ geometry: ThumbnailGeometry) {
        width = Int((geometry.size.width * geometry.scale).rounded())
        height = Int((geometry.size.height * geometry.scale).rounded())
        context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: geometry.scale, y: geometry.scale)
    }

    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        // Row 0 of the buffer is the top row; y here counts from the top.
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    /// Pixels in the pixel rectangle that are opaque and darker than the light sheet: ink.
    func inkCount(in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<min(height, Int(rect.maxY)) {
            for x in Int(rect.minX)..<min(width, Int(rect.maxX)) {
                let p = pixel(x: x, y: y)
                if p.a > 200, Int(p.r) + Int(p.g) + Int(p.b) < 450 { count += 1 }
            }
        }
        return count
    }

    var opaqueCount: Int {
        var count = 0
        for y in 0..<height { for x in 0..<width where pixel(x: x, y: y).a > 0 { count += 1 } }
        return count
    }

    /// Writes the bitmap for manual review when THUMBNAIL_SAMPLE_DIR names a directory.
    func dumpIfRequested(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["THUMBNAIL_SAMPLE_DIR"],
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: directory).appendingPathComponent("\(name).png") as CFURL,
                UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// A synthetic gradient raster in the requested encoding, for picture tests.
func syntheticImage(width: Int, height: Int, type: UTType = .png) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.1, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// An adapter that returns a fixed presentation, for exercising the draw path without a parser.
struct FixedAdapter: FormatAdapter {
    let document: ParsedTextDocument
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument { document }
}
