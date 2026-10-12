import Foundation
import Compression
import zlib
import PreviewContracts

enum BoundedDecompression {
    static func gzip(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        try inflate(data, windowBits: 31, context: context, maximum: maximum, concatenated: true)
    }
    static func zlibWrapped(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        try inflate(data, windowBits: 15, context: context, maximum: maximum, concatenated: false)
    }
    /// Headerless DEFLATE, as stored in ZIP members.
    static func rawDeflate(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        try inflate(data, windowBits: -15, context: context, maximum: maximum, concatenated: false)
    }
    private static func inflate(_ data: Data, windowBits: Int32, context: RequestContext,
                                maximum: Int, concatenated: Bool) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw PreviewFailure.unavailableContent
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            guard let source = input.bindMemory(to: UInt8.self).baseAddress else { throw PreviewFailure.malformedDocument }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = uInt(data.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)
            while true {
                try context.checkpoint()
                let capacity = min(buffer.count, maximum - output.count + 1)
                guard capacity > 0 else { throw PreviewFailure.outputTooLarge }
                let before = stream.avail_in
                let status = buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(capacity)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                guard produced <= maximum - output.count else { throw PreviewFailure.outputTooLarge }
                output.append(contentsOf: buffer.prefix(produced))
                try context.checkpoint()
                if status == Z_STREAM_END {
                    if stream.avail_in == 0 { return output }
                    guard concatenated, stream.avail_in >= 2,
                          stream.next_in[0] == 0x1f, stream.next_in[1] == 0x8b,
                          inflateReset2(&stream, windowBits) == Z_OK else { throw PreviewFailure.malformedDocument }
                    continue
                }
                guard status == Z_OK, stream.avail_in != before || produced > 0 else { throw PreviewFailure.malformedDocument }
            }
        }
    }

    /// bzip2 through the system libbz2; see `BZip2Decompression` for the bounds.
    static func bzip2(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        try BZip2Decompression.decode(data, context: context, maximum: maximum)
    }

    static func xz(_ data: Data, context: RequestContext, maximum: Int) throws -> Data {
        // Bound dictionary allocation before invoking the system decoder. A stream that declares a larger
        // (but still limited) dictionary is decoded by this package's bounded LZMA2 decoder instead.
        let info = try XZPreflight.validate(data, context: context)
        if info.needsBoundedDecoder { return try XZBoundedDecoder.decode(data, info: info, context: context, maximum: maximum) }
        let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { placeholder.deallocate() }
        var stream = compression_stream(dst_ptr: placeholder, dst_size: 0, src_ptr: placeholder, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw PreviewFailure.unavailableContent
        }
        defer { compression_stream_destroy(&stream) }
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            guard let source = input.bindMemory(to: UInt8.self).baseAddress else { throw PreviewFailure.malformedDocument }
            stream.src_ptr = source
            stream.src_size = data.count
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)
            while true {
                try context.checkpoint()
                let capacity = min(buffer.count, maximum - output.count + 1)
                guard capacity > 0 else { throw PreviewFailure.outputTooLarge }
                let before = stream.src_size
                let status = buffer.withUnsafeMutableBufferPointer { target in
                    stream.dst_ptr = target.baseAddress!
                    stream.dst_size = capacity
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = capacity - stream.dst_size
                guard produced <= maximum - output.count else { throw PreviewFailure.outputTooLarge }
                output.append(contentsOf: buffer.prefix(produced))
                if status == COMPRESSION_STATUS_END {
                    guard stream.src_size == 0 else { throw PreviewFailure.malformedDocument }
                    return output
                }
                guard status == COMPRESSION_STATUS_OK, stream.src_size != before || produced > 0 else { throw PreviewFailure.malformedDocument }
            }
        }
    }
}

enum XZPreflight {
    /// LZMA2 properties 0...22 request at most 8 MiB, the most the system decoder is allowed to allocate.
    static let systemDecoderDictionaryProperty: UInt8 = 22

    static func validate(_ data: Data, context: RequestContext) throws -> XZStreamInfo {
        var info = XZStreamInfo()
        let cursor = BinaryCursor(data)
        let bytes = cursor.bytes
        guard bytes.count >= 32, Array(bytes.prefix(6)) == [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0],
              Array(bytes.suffix(2)) == [0x59, 0x5a] else { throw PreviewFailure.malformedDocument }
        let footer = bytes.count - 12
        let indexSizeValue = try cursor.integer(at: footer + 4, width: 4, littleEndian: true)
        let indexSize = try boundedInt((indexSizeValue + 1) * 4)
        guard indexSize <= footer - 12 else { throw PreviewFailure.malformedDocument }
        var index = cursor
        index.offset = footer - indexSize
        guard try index.integer(1) == 0 else { throw PreviewFailure.malformedDocument }
        let count = try variableInteger(&index)
        guard count <= UInt64(min(context.budget.maxJSONNodes, 4096)) else { throw PreviewFailure.tooManyNodes }
        var blockOffset = 12
        for _ in 0..<count {
            try context.checkpoint()
            let unpadded = try boundedInt(variableInteger(&index))
            let uncompressed = try variableInteger(&index)
            guard unpadded >= 5, blockOffset < footer - indexSize,
                  unpadded <= footer - indexSize - blockOffset else { throw PreviewFailure.malformedDocument }
            let headerSize = (Int(bytes[blockOffset]) + 1) * 4
            guard headerSize >= 8, headerSize <= unpadded, headerSize <= footer - indexSize - blockOffset else { throw PreviewFailure.malformedDocument }
            var header = cursor
            header.offset = blockOffset + 1
            let flags = try header.integer(1)
            guard flags & 0x3c == 0, flags & 3 == 0 else { throw PreviewFailure.unsupportedFormat }
            if flags & 0x40 != 0 { _ = try variableInteger(&header) }
            if flags & 0x80 != 0 { _ = try variableInteger(&header) }
            guard try variableInteger(&header) == 0x21, try variableInteger(&header) == 1 else { throw PreviewFailure.unsupportedFormat }
            let dictionary = try header.integer(1)
            // Larger dictionaries are declined even if their compressed input is very small: up to 64 MiB
            // (property 28) the bounded decoder takes over, above that nothing decodes them.
            guard dictionary <= UInt64(XZBoundedDecoder.maximumDictionaryProperty) else { throw PreviewFailure.inputTooLarge }
            guard header.offset <= blockOffset + headerSize - 4 else { throw PreviewFailure.malformedDocument }
            let rounded = unpadded.addingReportingOverflow(3)
            guard !rounded.overflow else { throw PreviewFailure.malformedDocument }
            let padded = rounded.partialValue & ~3
            guard padded <= footer - indexSize - blockOffset else { throw PreviewFailure.malformedDocument }
            info.blocks.append(.init(offset: blockOffset, headerSize: headerSize, unpaddedSize: unpadded,
                                     uncompressedSize: uncompressed, dictionaryProperty: UInt8(dictionary)))
            blockOffset += padded
        }
        guard blockOffset == footer - indexSize, index.offset <= footer - 4 else { throw PreviewFailure.malformedDocument }
        return info
    }
    private static func variableInteger(_ cursor: inout BinaryCursor) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<9 {
            let byte = try cursor.integer(1)
            value |= (byte & 0x7f) << (index * 7)
            if byte & 0x80 == 0 {
                guard index == 0 || byte != 0 else { throw PreviewFailure.malformedDocument }
                return value
            }
        }
        throw PreviewFailure.malformedDocument
    }
}
