import Foundation
import BZip2Shim
import PreviewContracts

/// Streaming bzip2 decompression through the macOS system libbz2. Output is produced in 32 KiB
/// steps against a hard cap, the request deadline and cancellation are checked between steps, and
/// libbz2's own allocation is bounded by the format: one block of at most 900 KB (about four bytes
/// per block byte). Only decoding is reachable; the shim exposes no compression entry point.
enum BZip2Decompression {
    static func decode(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        try context.checkpoint()
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress, raw.count >= 4, startsStream(base) else {
                throw PreviewFailure.malformedDocument
            }
            var decoder = try Decoder()
            var consumed = 0
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)
            while true {
                try context.checkpoint()
                let capacity = min(buffer.count, maximum - output.count + 1)
                guard capacity > 0 else { throw PreviewFailure.outputTooLarge }
                var inputSize = raw.count - consumed
                var outputSize = capacity
                let status = buffer.withUnsafeMutableBufferPointer { target in
                    preview_bzip2_decode(decoder.handle, base + consumed, &inputSize, target.baseAddress, &outputSize)
                }
                consumed += inputSize
                guard outputSize <= maximum - output.count else { throw PreviewFailure.outputTooLarge }
                output.append(contentsOf: buffer.prefix(outputSize))
                try context.checkpoint()
                switch status {
                case PREVIEW_BZIP2_STREAM_END:
                    if consumed == raw.count { return output }
                    // Concatenated streams, as written by parallel compressors, each start with their own header.
                    guard raw.count - consumed >= 4, startsStream(base + consumed) else { throw PreviewFailure.malformedDocument }
                    decoder = try Decoder()
                case PREVIEW_BZIP2_OK:
                    // Without progress the input ended inside a stream.
                    guard inputSize > 0 || outputSize > 0 else { throw PreviewFailure.malformedDocument }
                case PREVIEW_BZIP2_MEMORY_ERROR:
                    throw PreviewFailure.unavailableContent
                default:
                    throw PreviewFailure.malformedDocument
                }
            }
        }
    }

    /// "BZh" followed by the block-size digit 1-9.
    private static func startsStream(_ bytes: UnsafePointer<UInt8>) -> Bool {
        bytes[0] == 0x42 && bytes[1] == 0x5A && bytes[2] == 0x68 && (0x31...0x39).contains(bytes[3])
    }

    /// Owns one libbz2 decoder; released when the last reference goes away.
    private final class Decoder {
        let handle: OpaquePointer
        init() throws {
            guard let created = preview_bzip2_create() else { throw PreviewFailure.unavailableContent }
            handle = created
        }
        deinit { preview_bzip2_destroy(handle) }
    }
}
