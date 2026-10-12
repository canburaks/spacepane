import Foundation
import PreviewContracts

/// Turns the `FilesInfo` header section and the folder stream map into listing entries.
/// Names are UTF-16LE; sizes come from `SubStreamsInfo`. No stream is decoded.
enum SevenZipFilesReader {
    private static let directoryAttribute: UInt32 = 0x10
    private static let unixExtensionAttribute: UInt32 = 0x8000

    static func entries(_ reader: inout ArchiveByteReader, streams: SevenZipStreamsInfo,
                        context: RequestContext) throws -> (entries: [ContainerEntry], partial: Bool) {
        let fileCount = try reader.sevenZipCount()
        var emptyStream: ArchiveByteReader?, emptyFile: ArchiveByteReader?, anti: ArchiveByteReader?
        var names: ArchiveByteReader?, modified: ArchiveByteReader?, attributes: ArchiveByteReader?
        while true {
            try context.checkpoint()
            let id = try reader.sevenZipNumber()
            if id == SevenZipID.end { break }
            let size = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: reader.remaining)
            let property = try reader.subReader(size)
            // Later duplicates replace earlier ones; unknown identifiers (times, start positions, padding) are skipped.
            switch id {
            case SevenZipID.emptyStream: emptyStream = property
            case SevenZipID.emptyFile: emptyFile = property
            case SevenZipID.anti: anti = property
            case SevenZipID.name: names = property
            case SevenZipID.modificationTime: modified = property
            case SevenZipID.windowsAttributes: attributes = property
            default: break
            }
        }
        if fileCount == 0 { return ([], false) }
        guard var names else { throw PreviewFailure.malformedDocument }
        let emptyStreamBits = try emptyStream.map { var copy = $0; return try SevenZipBitVector(&copy, count: fileCount) }
        let emptyCount = emptyStreamBits?.setCount ?? 0
        let emptyFileBits = try emptyFile.map { var copy = $0; return try SevenZipBitVector(&copy, count: emptyCount) }
        let antiBits = try anti.map { var copy = $0; return try SevenZipBitVector(&copy, count: emptyCount) }

        let limit = min(fileCount, ArchiveListing.maxEntries(context))
        guard try names.byte() == 0 else { throw PreviewFailure.unsupportedFormat } // external names
        let times = try definedValues(modified, limit: limit, fileCount: fileCount, width: 8)
        let attributeValues = try definedValues(attributes, limit: limit, fileCount: fileCount, width: 4)

        let metadataLimit = ContainerLimits(context: context).maxMetadataBytes
        var metadataBytes = 0
        var entries: [ContainerEntry] = []
        var emptyOrdinal = 0
        var folderIndex = 0
        var streamInFolder = 0
        var sizeIndex = 0
        for index in 0..<limit {
            try context.checkpoint()
            let name = try readName(&names, maximumUnits: context.budget.maxLineUTF8Bytes)
            let hasStream = !(emptyStreamBits?[index] ?? false)
            var isEmptyFile = false
            var isAnti = false
            var size: Int? = 0
            var encrypted = false
            if hasStream {
                while folderIndex < streams.folders.count, streams.streamCounts[folderIndex] == 0 { folderIndex += 1 }
                guard folderIndex < streams.folders.count, sizeIndex < streams.streamSizes.count else {
                    throw PreviewFailure.malformedDocument
                }
                size = try boundedInt(streams.streamSizes[sizeIndex])
                encrypted = streams.folders[folderIndex].hasEncryption
                sizeIndex += 1
                streamInFolder += 1
                if streamInFolder == streams.streamCounts[folderIndex] { folderIndex += 1; streamInFolder = 0 }
            } else {
                isEmptyFile = emptyFileBits?[emptyOrdinal] ?? false
                isAnti = antiBits?[emptyOrdinal] ?? false
                emptyOrdinal += 1
            }
            let attribute = attributeValues.value(at: index).flatMap { UInt32(exactly: $0) }
            let time = times.value(at: index)
            // An anti item records a deletion in an update archive; it names no file in this archive.
            if isAnti { continue }
            var kind = "file"
            if (!hasStream && !isEmptyFile) || attribute.map({ $0 & directoryAttribute != 0 }) == true {
                kind = "directory"
            } else if let attribute, attribute & unixExtensionAttribute != 0, (attribute >> 16) & 0xF000 == 0xA000 {
                kind = "symlink"
            }
            metadataBytes += name.utf8.count
            guard metadataBytes <= metadataLimit else { throw PreviewFailure.outputTooLarge }
            entries.append(ContainerEntry(path: try listableArchivePath(name), kind: kind, size: size,
                                          modified: time.flatMap { ArchiveListing.date(windowsFileTime: $0) },
                                          isEncrypted: encrypted))
        }
        return (entries, fileCount > limit)
    }

    private static func readName(_ reader: inout ArchiveByteReader, maximumUnits: Int) throws -> String {
        var units: [UInt16] = []
        while true {
            let unit = try reader.uint16()
            if unit == 0 { break }
            guard units.count < maximumUnits else { throw PreviewFailure.lineTooLong }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Values of a "defined" property (all-defined byte or bit vector, external byte, then fixed-width
    /// values for the defined files), read for the first `limit` files only.
    private static func definedValues(_ property: ArchiveByteReader?, limit: Int, fileCount: Int,
                                      width: Int) throws -> DefinedValues {
        guard var reader = property else { return DefinedValues(values: []) }
        let allDefined = try reader.byte() != 0
        let bits = allDefined ? nil : try SevenZipBitVector(&reader, count: fileCount)
        guard try reader.byte() == 0 else { throw PreviewFailure.unsupportedFormat } // external data
        var values: [UInt64?] = []
        values.reserveCapacity(limit)
        for index in 0..<limit {
            if allDefined || bits?[index] == true { values.append(try reader.littleEndian(width)) } else { values.append(nil) }
        }
        return DefinedValues(values: values)
    }

    private struct DefinedValues {
        let values: [UInt64?]
        func value(at index: Int) -> UInt64? { index < values.count ? values[index] : nil }
    }
}
