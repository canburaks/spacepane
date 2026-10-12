import Foundation
import PreviewContracts

/// What a single-stream compressor (gzip, bzip2, xz) contains once it is decoded: a TAR archive is
/// listed, valid text is shown, and anything else is reported as opaque binary. One implementation
/// serves every compressor so their behavior cannot drift apart.
enum CompressedStreamPayload {
    static func document(_ decoded: Data, streamName: String, context: RequestContext) throws -> ParsedTextDocument {
        let looksLikeTAR = decoded.count >= 1024 && (decoded.prefix(512).allSatisfy { $0 == 0 }
            || String(decoding: decoded.subdata(in: 257..<263), as: UTF8.self).hasPrefix("ustar"))
        if looksLikeTAR { return try TARListingAdapter().parseDecoded(decoded, context: context) }
        guard decoded.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        var payload = decoded
        let encoding: String.Encoding
        let decodedEncoding: TextEncoding
        if payload.starts(with: [0xff, 0xfe]) {
            encoding = .utf16LittleEndian; decodedEncoding = .utf16LittleEndian; payload.removeFirst(2)
        } else if payload.starts(with: [0xfe, 0xff]) {
            encoding = .utf16BigEndian; decodedEncoding = .utf16BigEndian; payload.removeFirst(2)
        } else {
            encoding = .utf8; decodedEncoding = .utf8
            if payload.starts(with: [0xef, 0xbb, 0xbf]) { payload.removeFirst(3) }
        }
        if let text = String(data: payload, encoding: encoding), !text.unicodeScalars.contains(where: { $0.value == 0 }) {
            return ParsedTextDocument(text: text, decodedEncoding: decodedEncoding)
        }
        var writer = SummaryWriter(context: context)
        return try writer.document(.object([
            ("archiveFormat", .string(streamName)), ("decodedBytes", .integer(decoded.count)),
            ("payloadKind", .string("binary"))
        ]))
    }
}

/// bzip2 streams (`.bz2`, `.tbz`, `.tbz2`): bounded decompression through the system libbz2.
public struct BZip2PreviewAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        let limits = ContainerLimits(context: context)
        try limits.validateInput(input.data)
        let decoded = try BoundedDecompression.bzip2(input.data, context: context, maximum: limits.maxDecodedBytes)
        return try CompressedStreamPayload.document(decoded, streamName: "BZIP2", context: context)
    }
}

/// xz streams (`.xz`, `.txz`): bounded decompression through the system LZMA decoder, after the
/// dictionary preflight shared with XIP chunks.
public struct XZPreviewAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        let limits = ContainerLimits(context: context)
        try limits.validateInput(input.data)
        let decoded = try BoundedDecompression.xz(input.data, context: context, maximum: limits.maxDecodedBytes)
        return try CompressedStreamPayload.document(decoded, streamName: "XZ", context: context)
    }
}
