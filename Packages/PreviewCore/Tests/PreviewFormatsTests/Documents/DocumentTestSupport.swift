import Foundation
import ImageIO
import UniformTypeIdentifiers
import zlib
import PreviewContracts
@testable import PreviewFormats

/// A generous deadline keeps these tests independent of machine speed; budgets are varied explicitly.
func documentContext(_ budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) -> RequestContext {
    RequestContext(budget: budget)
}

struct TestZIPEntry {
    let name: String
    let data: Data
    var deflate = false
    var encrypted = false
}

/// Builds small, valid ZIP archives from memory: stored or raw-deflate members with CRC-32 and a central directory.
enum TestZIP {
    static func make(_ entries: [TestZIPEntry]) -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let payload = entry.deflate ? rawDeflate(entry.data) : entry.data
            let crc = entry.data.withUnsafeBytes { buffer -> UInt32 in
                guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
                return UInt32(crc32(0, base, uInt(buffer.count)))
            }
            let flags: UInt64 = 0x800 | (entry.encrypted ? 1 : 0)
            let method: UInt64 = entry.deflate ? 8 : 0
            let offset = output.count
            output += le(0x04034b50, 4) + le(20, 2) + le(flags, 2) + le(method, 2) + le(0, 2) + le(0x21, 2)
            output += le(UInt64(crc), 4) + le(UInt64(payload.count), 4) + le(UInt64(entry.data.count), 4)
            output += le(UInt64(name.count), 2) + le(0, 2) + name + payload
            central += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(flags, 2) + le(method, 2) + le(0, 2) + le(0x21, 2)
            central += le(UInt64(crc), 4) + le(UInt64(payload.count), 4) + le(UInt64(entry.data.count), 4)
            central += le(UInt64(name.count), 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 4) + le(UInt64(offset), 4) + name
        }
        let start = output.count
        output += central
        output += le(0x06054b50, 4) + le(0, 2) + le(0, 2) + le(UInt64(entries.count), 2) + le(UInt64(entries.count), 2)
        output += le(UInt64(central.count), 4) + le(UInt64(start), 4) + le(0, 2)
        return output
    }

    static func make(_ files: [(String, Data)], deflate: Bool = false) -> Data {
        make(files.map { TestZIPEntry(name: $0.0, data: $0.1, deflate: deflate) })
    }

    private static func le(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private static func rawDeflate(_ data: Data) -> Data {
        var stream = z_stream()
        precondition(deflateInit2_(&stream, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        var result = Data(count: max(64, data.count * 2 + 64))
        let capacity = result.count
        var written = 0
        data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = output.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = uInt(capacity)
                precondition(deflate(&stream, Z_FINISH) == Z_STREAM_END)
                written = capacity - Int(stream.avail_out)
            }
        }
        return result.prefix(written)
    }
}

/// Encodes tiny synthetic bitmaps with ImageIO so tests never ship image fixtures.
enum TestImages {
    static func data(type: UTType, width: Int, height: Int, orientation: Int? = nil) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 2), height: max(1, height / 2)))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func png(_ width: Int = 8, _ height: Int = 12) -> Data { data(type: .png, width: width, height: height) }

    /// A PNG of deterministic pseudo-random pixels: it does not compress, so its size is predictable.
    static func noisePNG(_ width: Int, _ height: Int) -> Data {
        var state: UInt32 = 0x1234_5678
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in pixels.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Deterministic lowercase words: they compress only partly, so archive size grows with the text.
    static func noiseText(_ count: Int, seed: UInt32 = 7) -> String {
        var state = seed
        return (0..<count).map { _ -> String in
            state = state &* 1_664_525 &+ 1_013_904_223
            return String((0..<5).map { index in Character(UnicodeScalar(97 + UInt8((state >> UInt32(index * 5 + 3)) % 26))) })
        }.joined(separator: " ")
    }
    static func jpeg(_ width: Int = 8, _ height: Int = 12, orientation: Int? = nil) -> Data {
        data(type: .jpeg, width: width, height: height, orientation: orientation)
    }
    static func gif(_ width: Int = 8, _ height: Int = 12) -> Data { data(type: .gif, width: width, height: height) }
}

/// Reads of this source are counted so tests can prove nothing was read before a decision was made.
final class CountingSource: PreviewByteSource, @unchecked Sendable {
    // Test-only mutable counter: tests read it after the single-threaded parse returns.
    private let inner: DataByteSource
    private(set) var reads = 0
    private(set) var bytesRequested = 0
    var byteCount: Int64 { inner.byteCount }
    init(_ data: Data) { inner = DataByteSource(data) }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        reads += 1
        bytesRequested += count
        return try inner.read(offset: offset, count: count, context: context)
    }
}

func parseDocument(_ adapter: some RandomAccessFormatAdapter, _ data: Data,
           budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> ParsedTextDocument {
    try adapter.parse(DataByteSource(data), context: documentContext(budget))
}
