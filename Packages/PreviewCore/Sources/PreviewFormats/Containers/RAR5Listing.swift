import Foundation
import PreviewContracts

/// Walks RAR 5.0 blocks: CRC32, header size (vint), then the header; a data area, whose size the
/// header declares, follows and is skipped without being read.
enum RAR5Listing {
    /// The technote caps a header at three size bytes: 2 MiB.
    private static let maximumHeaderSize = 2_097_152
    /// CRC32 (4) plus the largest header-size field (3).
    private static let prefixSize = 7

    private enum BlockType: UInt64 {
        case main = 1, file = 2, service = 3, archiveEncryption = 4, endOfArchive = 5
    }
    private enum ExtraRecord: UInt64 { case fileEncryption = 1, fileTime = 3, redirection = 5 }

    static func read(_ source: any PreviewByteSource, context: RequestContext) throws -> RARListing {
        var listing = RARListing(formatName: "RAR5")
        let maxEntries = ArchiveListing.maxEntries(context)
        let metadataLimit = ContainerLimits(context: context).maxMetadataBytes
        var position = Int64(RARSignature.rar5Bytes.count)
        var charged = RARSignature.rar5Bytes.count
        var metadataBytes = 0
        var sawMain = false
        var ended = false
        while position < source.byteCount {
            try context.checkpoint()
            let remaining = source.byteCount - position
            guard remaining >= Int64(prefixSize) else { throw PreviewFailure.malformedDocument }
            guard context.budget.maxInputBytes - charged >= prefixSize else {
                guard sawMain else { throw PreviewFailure.inputTooLarge }
                listing.partial = true
                break
            }
            let prefix = Array(try source.read(offset: position, count: prefixSize, context: context))
            charged += prefixSize
            var sizeLength = 0
            var headerSize = 0
            for index in 0..<3 {
                let byte = prefix[4 + index]
                headerSize |= Int(byte & 0x7F) << (7 * index)
                sizeLength += 1
                if byte & 0x80 == 0 { break }
                guard index < 2 else { throw PreviewFailure.malformedDocument }
            }
            guard (2...maximumHeaderSize).contains(headerSize) else { throw PreviewFailure.malformedDocument }
            let total = 4 + sizeLength + headerSize
            guard Int64(total) <= remaining else { throw PreviewFailure.malformedDocument }
            if total - prefixSize > context.budget.maxInputBytes - charged {
                guard sawMain else { throw PreviewFailure.inputTooLarge }
                listing.partial = true
                break
            }
            var block = prefix
            if total > prefixSize {
                block += try source.read(offset: position + Int64(prefixSize), count: total - prefixSize, context: context)
                charged += total - prefixSize
            }
            let storedCRC = UInt32(block[0]) | UInt32(block[1]) << 8 | UInt32(block[2]) << 16 | UInt32(block[3]) << 24
            guard ArchiveCRC32.checksum(block[4...]) == storedCRC else { throw PreviewFailure.malformedDocument }

            var common = ArchiveByteReader(block, position: 4 + sizeLength, end: total)
            let rawType = try common.rarVariableInteger()
            let flags = try common.rarVariableInteger()
            let extraSize = flags & 0x01 != 0 ? try common.rarVariableInteger() : 0
            let dataSize = flags & 0x02 != 0 ? try common.rarVariableInteger() : 0
            guard extraSize <= UInt64(common.remaining) else { throw PreviewFailure.malformedDocument }
            let fieldsEnd = total - Int(extraSize)
            var fields = ArchiveByteReader(block, position: common.position, end: fieldsEnd)
            var extra = ArchiveByteReader(block, position: fieldsEnd, end: total)
            let type = BlockType(rawValue: rawType)

            if !sawMain {
                // The archive-encryption header precedes everything it protects, so no entry names are readable.
                if type == .archiveEncryption { throw PreviewFailure.encryptedContent }
                // A volume or fragment without its main header cannot be interpreted on its own.
                guard type == .main else { throw PreviewFailure.unsupportedFormat }
            }
            switch type {
            case .archiveEncryption:
                throw PreviewFailure.encryptedContent
            case .main:
                guard !sawMain else { throw PreviewFailure.malformedDocument }
                sawMain = true
                let archiveFlags = try fields.rarVariableInteger()
                listing.flags.multiVolume = archiveFlags & 0x01 != 0
                listing.flags.solid = archiveFlags & 0x04 != 0
                listing.flags.recoveryRecord = archiveFlags & 0x08 != 0
                listing.flags.locked = archiveFlags & 0x10 != 0
                if archiveFlags & 0x02 != 0 {
                    let number = try fields.rarVariableInteger()
                    guard number < UInt64(Int32.max) else { throw PreviewFailure.malformedDocument }
                    listing.flags.volumeNumber = Int(number) + 1
                } else if listing.flags.multiVolume {
                    listing.flags.volumeNumber = 1
                }
            case .file:
                if listing.entries.count >= maxEntries { listing.partial = true; break }
                let entry = try fileEntry(&fields, extra: &extra, context: context)
                metadataBytes += entry.path.utf8.count
                guard metadataBytes <= metadataLimit else { throw PreviewFailure.outputTooLarge }
                listing.entries.append(entry)
            case .endOfArchive:
                ended = true
            case .service, nil:
                // Service blocks (comments, quick open, recovery data, NTFS streams) and block types
                // added by later versions describe no listed member; only their data area is skipped.
                break
            }
            if ended || listing.partial { break }
            guard dataSize <= UInt64(remaining) - UInt64(total) else { throw PreviewFailure.malformedDocument }
            position += Int64(total) + Int64(dataSize)
        }
        guard sawMain else { throw PreviewFailure.malformedDocument }
        // A missing end-of-archive block means the file stops mid-archive; say so instead of claiming completeness.
        if !ended { listing.partial = true }
        return listing
    }

    /// File header fields after the common block fields, followed by the extra-area records.
    private static func fileEntry(_ fields: inout ArchiveByteReader, extra: inout ArchiveByteReader,
                                  context: RequestContext) throws -> ContainerEntry {
        let fileFlags = try fields.rarVariableInteger()
        let unpackedSize = try fields.rarVariableInteger()
        _ = try fields.rarVariableInteger() // attributes
        var modified: Date?
        if fileFlags & 0x02 != 0 { modified = ArchiveListing.date(unixSeconds: Double(try fields.uint32())) }
        if fileFlags & 0x04 != 0 { _ = try fields.uint32() } // data CRC32
        _ = try fields.rarVariableInteger() // compression information
        _ = try fields.rarVariableInteger() // host operating system
        let nameLength = try fields.rarVariableInteger()
        guard nameLength > 0, nameLength <= UInt64(fields.remaining) else { throw PreviewFailure.malformedDocument }
        guard let name = String(data: Data(try fields.take(Int(nameLength))), encoding: .utf8) else {
            throw PreviewFailure.unsupportedEncoding
        }
        var kind = fileFlags & 0x01 != 0 ? "directory" : "file"
        var encrypted = false
        while !extra.isAtEnd {
            try context.checkpoint()
            let recordSize = try extra.rarVariableInteger()
            guard recordSize > 0, recordSize <= UInt64(extra.remaining) else { throw PreviewFailure.malformedDocument }
            let recordEnd = extra.position + Int(recordSize)
            var record = ArchiveByteReader(extra.bytes, position: extra.position, end: recordEnd)
            let recordType = try record.rarVariableInteger()
            switch ExtraRecord(rawValue: recordType) {
            case .fileEncryption:
                encrypted = true
            case .fileTime:
                // Header time wins when present; otherwise take the modification time if it is stored as
                // seconds or FILETIME. The nanosecond variant is not decoded rather than guessed.
                if modified == nil {
                    let timeFlags = try record.rarVariableInteger()
                    if timeFlags & 0x02 != 0, timeFlags & 0x10 == 0 {
                        modified = timeFlags & 0x01 != 0
                            ? ArchiveListing.date(unixSeconds: Double(try record.uint32()))
                            : ArchiveListing.date(windowsFileTime: try record.uint64())
                    }
                }
            case .redirection:
                switch try record.rarVariableInteger() {
                case 1, 2, 3: kind = "symlink"
                case 4: kind = "hardlink"
                default: break
                }
            case nil:
                break
            }
            try extra.skip(recordEnd - extra.position)
        }
        let size: Int? = fileFlags & 0x08 != 0 ? nil : try boundedInt(unpackedSize)
        return ContainerEntry(path: try listableArchivePath(name), kind: kind, size: size,
                              modified: modified, isEncrypted: encrypted)
    }
}
