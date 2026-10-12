import Foundation
import PreviewContracts

public struct XIPListingAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }
    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let limits = ContainerLimits(context: context)
        let archive = try XARArchiveReader.read(source, context: context, limits: limits)
        // The payload is the one top-level `Content` entry, stored as a PBZX stream without further coding.
        let candidates = archive.entries.filter { $0.parent == nil && $0.name == "Content" }
        guard candidates.count <= 1 else { throw PreviewFailure.malformedDocument }
        guard let content = candidates.first, content.encoding == "application/octet-stream" else { throw PreviewFailure.unsupportedFormat }
        guard let contentOffset = content.offset, let contentLength = content.length else { throw PreviewFailure.malformedDocument }
        let heap = archive.heapStart
        guard Int64(contentOffset) <= source.byteCount - heap,
              Int64(contentLength) <= source.byteCount - heap - Int64(contentOffset) else { throw PreviewFailure.malformedDocument }
        let decoded = try decodePBZXSource(source, offset: heap + Int64(contentOffset), length: contentLength,
                                           alreadyRead: archive.bytesRead, context: context, limits: limits)
        let entries = try CPIOListingReader.parse(decoded.data, context: context, limits: limits, partialInput: decoded.partial)
        return try listingDocument(format: "XIP", entries: entries, context: context, partial: decoded.partial,
                                   extra: [("signatureVerified", .boolean(false)), ("innerArchiveFormat", .string("CPIO")),
                                           ("decodedBytes", .integer(decoded.data.count))], assessRisks: true)
    }

    private func decodePBZXSource(_ source: any PreviewByteSource, offset: Int64, length: Int, alreadyRead: Int,
                                  context: RequestContext, limits: ContainerLimits) throws -> (data: Data, partial: Bool) {
        guard length >= 12 else { throw PreviewFailure.malformedDocument }
        var header = BinaryCursor(try source.read(offset: offset, count: 12, context: context))
        guard try header.integer(4) == 0x70627a78 else { throw PreviewFailure.unsupportedFormat }
        var flags = try header.integer(8)
        guard flags & ~UInt64(0x01000000) == 0 else { throw PreviewFailure.unsupportedFormat }
        var position = 12
        var readBytes = alreadyRead + 12
        var output = Data()
        var chunks = 0
        while flags & 0x01000000 != 0 {
            try context.checkpoint()
            if output.count == limits.maxDecodedBytes || context.budget.maxInputBytes - readBytes < 22 { return (output, true) }
            guard position <= length - 16 else { throw PreviewFailure.malformedDocument }
            var chunkHeader = BinaryCursor(try source.read(offset: offset + Int64(position), count: 16, context: context))
            flags = try chunkHeader.integer(8)
            guard flags & ~UInt64(0x01000000) == 0 else { throw PreviewFailure.unsupportedFormat }
            let chunkLength = try boundedInt(chunkHeader.integer(8))
            guard chunkLength >= 6, chunkLength <= 16_777_216, chunkLength <= length - position - 16 else { throw PreviewFailure.malformedDocument }
            position += 16
            readBytes += 16
            chunks += 1
            guard chunks <= min(4096, context.budget.maxJSONNodes) else { throw PreviewFailure.tooManyNodes }
            let first = try source.read(offset: offset + Int64(position), count: 6, context: context)
            readBytes += 6
            let available = min(context.budget.maxInputBytes - readBytes, limits.maxDecodedBytes - output.count - 6)
            let compressed = first.starts(with: [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0])
            if chunkLength - 6 > available {
                if !compressed && chunkLength == 16_777_216 && available >= 0 {
                    output.append(first)
                    output.append(try source.read(offset: offset + Int64(position + 6), count: available, context: context))
                }
                // A compressed chunk is decoded only after its bounded XZ dictionary preflight.
                return (output, true)
            }
            var chunk = first
            chunk.append(try source.read(offset: offset + Int64(position + 6), count: chunkLength - 6, context: context))
            readBytes += chunkLength - 6
            let decoded: Data
            if !compressed && chunkLength == 16_777_216 { decoded = chunk }
            else { decoded = try BoundedDecompression.xz(chunk, context: context, maximum: min(16_777_216, limits.maxDecodedBytes - output.count)) }
            output.append(decoded)
            position += chunkLength
        }
        guard position == length else { throw PreviewFailure.malformedDocument }
        return (output, false)
    }


}

private enum CPIOListingReader {
    /// Longest symbolic link target read from the already decoded bytes.
    private static let maximumLinkTargetBytes = 4_096
    static func parse(_ data: Data, context: RequestContext, limits: ContainerLimits, partialInput: Bool = false) throws -> [ContainerEntry] {
        var cursor = BinaryCursor(data)
        var entries: [ContainerEntry] = []
        var metadataBytes = 0
        while cursor.remaining > 0 {
            try context.checkpoint()
            if partialInput && cursor.remaining < 110 { return entries }
            let start = cursor.offset
            let magic = String(decoding: try cursor.read(6), as: UTF8.self)
            let nameSize: Int
            let fileSize: Int
            let mode: Int
            let checksum: Int?
            let alignment: Int
            switch magic {
            case "070701", "070702":
                var fields: [Int] = []
                for _ in 0..<13 { fields.append(try number(try cursor.read(8), radix: 16)) }
                mode = fields[1]; fileSize = fields[6]; nameSize = fields[11]
                checksum = magic == "070702" ? fields[12] : nil
                alignment = 4
            case "070707":
                _ = try cursor.read(12)
                mode = try number(try cursor.read(6), radix: 8)
                _ = try cursor.read(24)
                _ = try number(try cursor.read(11), radix: 8)
                nameSize = try number(try cursor.read(6), radix: 8)
                fileSize = try number(try cursor.read(11), radix: 8)
                checksum = nil
                alignment = 1
            default: throw PreviewFailure.unsupportedFormat
            }
            guard nameSize > 0, nameSize <= limits.maxMetadataBytes - metadataBytes else { throw PreviewFailure.outputTooLarge }
            let name = try cursor.read(nameSize)
            metadataBytes += nameSize
            guard name.last == 0, !name.dropLast().contains(0),
                  let path = String(data: Data(name.dropLast()), encoding: .utf8) else { throw PreviewFailure.malformedDocument }
            _ = try cursor.read((alignment - ((cursor.offset - start) % alignment)) % alignment)
            if path != "TRAILER!!!" {
                guard entries.count < min(limits.maxEntries, max(1, context.budget.maxJSONNodes / 8)) else { throw PreviewFailure.tooManyNodes }
                let kind: ContainerEntryKind = mode & 0xf000 == 0x4000 ? .directory : mode & 0xf000 == 0xa000 ? .symlink : mode & 0xf000 == 0x8000 ? .file : .special
                // A symbolic link's payload is its target. Peeking leaves the cursor, and so the budget, as before.
                var target: String?
                if kind == .symlink, (1...maximumLinkTargetBytes).contains(fileSize), fileSize <= cursor.remaining,
                   let text = String(data: Data(cursor.bytes[cursor.offset..<(cursor.offset + fileSize)]), encoding: .utf8),
                   !text.unicodeScalars.contains(where: { $0.value == 0 }) {
                    target = text
                }
                entries.append(ContainerEntry(path: try listableArchivePath(path), kind: kind, size: fileSize,
                                              mode: UInt32(truncatingIfNeeded: mode), linkTarget: target))
            }
            if partialInput && fileSize > cursor.remaining { return entries }
            let payload = try cursor.read(fileSize)
            if let checksum {
                var sum: UInt32 = 0
                for (index, byte) in payload.enumerated() {
                    if index.isMultiple(of: 32_768) { try context.checkpoint() }
                    sum &+= UInt32(byte)
                }
                guard UInt32(truncatingIfNeeded: checksum) == sum else { throw PreviewFailure.malformedDocument }
            }
            _ = try cursor.read((alignment - (fileSize % alignment)) % alignment)
            if path == "TRAILER!!!" {
                guard fileSize == 0, cursor.bytes[cursor.offset...].allSatisfy({ $0 == 0 }) else { throw PreviewFailure.malformedDocument }
                return entries
            }

        }
        if partialInput { return entries }
        throw PreviewFailure.malformedDocument
    }
    private static func number(_ bytes: ArraySlice<UInt8>, radix: Int) throws -> Int {
        guard let value = Int(String(decoding: bytes, as: UTF8.self), radix: radix), value >= 0 else { throw PreviewFailure.malformedDocument }
        return value
    }
}
