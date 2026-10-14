import Foundation
import zlib
import PreviewContracts

/// Reads the beginning of one ZIP member without reading or inflating the rest (decision 030). Wheels
/// have headers that come first (METADATA), path files that are small and binaries that are recognized
/// by their first bytes, so none of them needs the whole member, and a member much larger than the part
/// wanted costs only a bounded read. The result is not CRC-checked: a damaged or truncated stream gives
/// the bytes decoded before the damage, which is all a caller looking for a fact needs.
///
/// Stored and deflated members are read; any other method, an encrypted member and anything that is not
/// a regular file give nothing. Reads go through the request's byte source and so count against its budget.
enum ZIPMemberPrefix {
    /// Compressed bytes read for `maximumBytes` of output: the output, a deflate block header's worth of
    /// slack, and one eighth for incompressible input. A stream that needs more yields a shorter prefix.
    static func compressedReadSize(of entry: ZIPEntry, maximumBytes: Int) -> Int {
        guard entry.method == 8 else { return min(entry.compressedSize, maximumBytes) }
        return min(entry.compressedSize, maximumBytes + maximumBytes / 8 + 4_096)
    }

    static func read(_ entry: ZIPEntry, from source: any PreviewByteSource, maximumBytes: Int,
                     context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard entry.kind == "file", !entry.isEncrypted, maximumBytes > 0, entry.uncompressedSize > 0,
              entry.method == 0 || entry.method == 8 else { return Data() }
        let wanted = min(entry.uncompressedSize, maximumBytes)
        let payload = try source.read(offset: Int64(entry.payloadOffset),
                                      count: compressedReadSize(of: entry, maximumBytes: wanted), context: context)
        guard entry.method == 8 else { return payload.prefix(wanted) }
        return try inflatePrefix(payload, wanted: wanted, context: context)
    }

    private static func inflatePrefix(_ data: Data, wanted: Int, context: RequestContext) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return Data() }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: min(wanted, 32_768))
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            guard let source = input.bindMemory(to: UInt8.self).baseAddress else { return Data() }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = uInt(data.count)
            while output.count < wanted {
                try context.checkpoint()
                let capacity = min(buffer.count, wanted - output.count)
                let status = buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(capacity)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                output.append(contentsOf: buffer.prefix(produced))
                // The end of the stream, a damaged stream and input that ran out all end the prefix.
                if status != Z_OK || produced == 0 { break }
            }
            return output
        }
    }
}
