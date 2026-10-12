import Foundation
import PreviewContracts

/// Lists 7z archives from the signature header and the (possibly LZMA-compressed) header database.
/// Written from the public 7z format description. Member payloads are never decoded: only the
/// header stream may be decompressed, with LZMA or LZMA2 under bounded limits, and a header that
/// is encrypted is reported as such instead of being guessed at.
public struct SevenZipListingAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        return try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let archive = try SevenZipArchiveReader.read(source, context: context)
        return try listingDocument(format: "7Z", entries: archive.entries, context: context,
                                   partial: archive.partial, extra: [("solid", .boolean(archive.isSolid))], assessRisks: true)
    }
}

struct SevenZipArchive {
    var entries: [ContainerEntry] = []
    var partial = false
    var isSolid = false
}

enum SevenZipArchiveReader {
    private static let signature: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
    private static let startHeaderSize = 32
    /// A header may be wrapped in `EncodedHeader` more than once; real writers use one level.
    private static let maximumEncodedHeaderDepth = 4

    static func read(_ source: any PreviewByteSource, context: RequestContext) throws -> SevenZipArchive {
        let limits = ContainerLimits(context: context)
        guard source.byteCount >= 6 else { throw PreviewFailure.malformedDocument }
        let head = Array(try source.read(offset: 0, count: min(startHeaderSize, Int(source.byteCount)), context: context))
        guard head.starts(with: signature) else {
            // An executable that carries the archive after a stub is a self-extracting archive.
            throw ArchiveListing.looksLikeExecutable(head) ? PreviewFailure.unsupportedFormat : PreviewFailure.malformedDocument
        }
        guard head.count == startHeaderSize else { throw PreviewFailure.malformedDocument }
        var start = ArchiveByteReader(head, position: 6)
        let majorVersion = try start.byte()
        _ = try start.byte() // minor version
        let startHeaderCRC = try start.uint32()
        guard ArchiveCRC32.checksum(head[12..<32]) == startHeaderCRC else { throw PreviewFailure.malformedDocument }
        guard majorVersion == 0 else { throw PreviewFailure.unsupportedFormat }
        let nextOffset = try start.uint64()
        let nextSize = try start.uint64()
        let nextCRC = try start.uint32()
        // An archive without files stores no header at all.
        if nextSize == 0 { return SevenZipArchive() }
        let available = UInt64(source.byteCount) - UInt64(startHeaderSize)
        guard nextOffset <= available, nextSize <= available - nextOffset else { throw PreviewFailure.malformedDocument }
        guard nextSize <= UInt64(max(0, min(limits.maxDirectoryBytes, context.budget.maxInputBytes - startHeaderSize))) else {
            throw PreviewFailure.inputTooLarge
        }
        var header = Array(try source.read(offset: Int64(startHeaderSize) + Int64(nextOffset), count: Int(nextSize), context: context))
        guard ArchiveCRC32.checksum(header) == nextCRC else { throw PreviewFailure.malformedDocument }

        var depth = 0
        while true {
            try context.checkpoint()
            var reader = ArchiveByteReader(header)
            let id = try reader.sevenZipNumber()
            if id == SevenZipID.header { return try parseHeader(&reader, context: context) }
            guard id == SevenZipID.encodedHeader, depth < maximumEncodedHeaderDepth else {
                throw id == SevenZipID.encodedHeader ? PreviewFailure.structureTooDeep : PreviewFailure.malformedDocument
            }
            depth += 1
            let streams = try SevenZipStreamsInfo.parse(&reader, context: context)
            header = try decodeHeader(streams, source: source, context: context, limits: limits)
        }
    }

    private static func parseHeader(_ reader: inout ArchiveByteReader, context: RequestContext) throws -> SevenZipArchive {
        var id = try reader.sevenZipNumber()
        if id == SevenZipID.archiveProperties {
            while true {
                try context.checkpoint()
                if try reader.sevenZipNumber() == SevenZipID.end { break }
                try reader.skipSevenZipProperty()
            }
            id = try reader.sevenZipNumber()
        }
        if id == SevenZipID.additionalStreamsInfo {
            _ = try SevenZipStreamsInfo.parse(&reader, context: context)
            id = try reader.sevenZipNumber()
        }
        var streams = SevenZipStreamsInfo()
        if id == SevenZipID.mainStreamsInfo {
            streams = try SevenZipStreamsInfo.parse(&reader, context: context)
            id = try reader.sevenZipNumber()
        }
        var archive = SevenZipArchive()
        archive.isSolid = streams.streamCounts.contains { $0 > 1 }
        if id == SevenZipID.filesInfo {
            let result = try SevenZipFilesReader.entries(&reader, streams: streams, context: context)
            archive.entries = result.entries
            archive.partial = result.partial
            id = try reader.sevenZipNumber()
        }
        guard id == SevenZipID.end else { throw PreviewFailure.malformedDocument }
        return archive
    }

    /// Decodes the first folder of an `EncodedHeader`. Only Copy, LZMA and LZMA2 are supported;
    /// AES means the header is encrypted. The packed bytes, the decoded size and the dictionary
    /// are all checked against the request budget before anything is allocated.
    private static func decodeHeader(_ streams: SevenZipStreamsInfo, source: any PreviewByteSource,
                                     context: RequestContext, limits: ContainerLimits) throws -> [UInt8] {
        guard let folder = streams.folders.first, !streams.packSizes.isEmpty else { throw PreviewFailure.malformedDocument }
        if folder.hasEncryption { throw PreviewFailure.encryptedContent }
        let order = try folder.decodeOrder()
        let packedLimit = UInt64(max(0, min(limits.maxDirectoryBytes, context.budget.maxInputBytes - startHeaderSize)))
        let available = UInt64(source.byteCount) - UInt64(startHeaderSize)
        let packedSize = streams.packSizes[0]
        guard streams.packPosition <= available, packedSize <= available - streams.packPosition else {
            throw PreviewFailure.malformedDocument
        }
        guard packedSize <= packedLimit else { throw PreviewFailure.inputTooLarge }
        var data = Array(try source.read(offset: Int64(startHeaderSize) + Int64(streams.packPosition),
                                         count: Int(packedSize), context: context))
        let outputLimit = min(8_388_608, limits.maxDirectoryBytes * 8)
        let coderLimits = LZMALimits(maximumOutputBytes: outputLimit)
        for index in order {
            try context.checkpoint()
            let coder = folder.coders[index]
            guard folder.unpackSizes[index] <= UInt64(outputLimit) else { throw PreviewFailure.outputTooLarge }
            let outputSize = Int(folder.unpackSizes[index])
            switch coder.id {
            case SevenZipCoder.copy:
                guard data.count == outputSize else { throw PreviewFailure.malformedDocument }
            case SevenZipCoder.lzma:
                data = try LZMADecoder.decode(data, properties: coder.properties, outputSize: outputSize,
                                              limits: coderLimits, context: context)
            case SevenZipCoder.lzma2:
                guard coder.properties.count == 1 else { throw PreviewFailure.malformedDocument }
                data = try LZMA2Decoder.decode(data, dictionaryProperty: coder.properties[0], outputSize: outputSize,
                                               limits: coderLimits, context: context)
            default:
                throw PreviewFailure.unsupportedFormat
            }
        }
        if let crc = folder.unpackCRC, ArchiveCRC32.checksum(data) != crc { throw PreviewFailure.malformedDocument }
        return data
    }
}
