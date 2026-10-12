import Foundation
import PreviewContracts

/// Walks RAR 1.5-4.x blocks. Each block starts with a 7-byte prefix (CRC16, type, flags, header
/// size); a data area, sized by the header, follows file blocks and is skipped without being read.
enum RAR4Listing {
    private static let prefixSize = 7
    /// Size of the fixed file-header fields, up to and including the attribute word.
    private static let fileFieldsSize = 32

    private enum BlockType: UInt8 {
        case main = 0x73, file = 0x74, subBlock = 0x7A, endOfArchive = 0x7B
    }

    static func read(_ source: any PreviewByteSource, context: RequestContext) throws -> RARListing {
        var listing = RARListing(formatName: "RAR4")
        let maxEntries = ArchiveListing.maxEntries(context)
        let metadataLimit = ContainerLimits(context: context).maxMetadataBytes
        var position = Int64(RARSignature.rar4Bytes.count)
        var charged = RARSignature.rar4Bytes.count
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
            let storedCRC = UInt16(prefix[0]) | UInt16(prefix[1]) << 8
            let rawType = prefix[2]
            let flags = UInt16(prefix[3]) | UInt16(prefix[4]) << 8
            let headerSize = Int(prefix[5]) | Int(prefix[6]) << 8
            guard headerSize >= prefixSize, Int64(headerSize) <= remaining else { throw PreviewFailure.malformedDocument }
            if headerSize - prefixSize > context.budget.maxInputBytes - charged {
                guard sawMain else { throw PreviewFailure.inputTooLarge }
                listing.partial = true
                break
            }
            var block = prefix
            if headerSize > prefixSize {
                block += try source.read(offset: position + Int64(prefixSize), count: headerSize - prefixSize, context: context)
                charged += headerSize - prefixSize
            }
            let type = BlockType(rawValue: rawType)
            // CRC16 is the low half of the CRC32 of everything after the CRC field. Only the block types
            // this reader interprets are checked; blocks it merely skips keep their older, looser layouts.
            if type != nil {
                guard UInt16(truncatingIfNeeded: ArchiveCRC32.checksum(block[2...])) == storedCRC else {
                    throw PreviewFailure.malformedDocument
                }
            }
            if !sawMain && type != .main { throw PreviewFailure.unsupportedFormat }

            var dataSize: UInt64 = 0
            switch type {
            case .main:
                guard !sawMain, headerSize >= 13 else { throw PreviewFailure.malformedDocument }
                // Every header after this one is encrypted, so no entry name can be read.
                if flags & 0x0080 != 0 { throw PreviewFailure.encryptedContent }
                sawMain = true
                listing.flags.multiVolume = flags & 0x0001 != 0
                listing.flags.locked = flags & 0x0004 != 0
                listing.flags.solid = flags & 0x0008 != 0
                listing.flags.recoveryRecord = flags & 0x0040 != 0
            case .file, .subBlock:
                dataSize = try fileLayout(block, headerSize: headerSize, flags: flags)
                if type == .file {
                    if listing.entries.count >= maxEntries { listing.partial = true; break }
                    let entry = try fileEntry(block, headerSize: headerSize, flags: flags, context: context)
                    metadataBytes += entry.path.utf8.count
                    guard metadataBytes <= metadataLimit else { throw PreviewFailure.outputTooLarge }
                    listing.entries.append(entry)
                }
            case .endOfArchive:
                ended = true
            case nil:
                // Older comment, recovery and authenticity blocks: skip by the declared size.
                if flags & 0x8000 != 0 {
                    var reader = ArchiveByteReader(block, position: prefixSize, end: headerSize)
                    dataSize = UInt64(try reader.uint32())
                }
            }
            if ended || listing.partial { break }
            guard dataSize <= UInt64(remaining) - UInt64(headerSize) else { throw PreviewFailure.malformedDocument }
            position += Int64(headerSize) + Int64(dataSize)
        }
        guard sawMain else { throw PreviewFailure.malformedDocument }
        if !ended { listing.partial = true }
        return listing
    }

    /// Reads the packed size, which is the length of the data area that follows a file block.
    private static func fileLayout(_ block: [UInt8], headerSize: Int, flags: UInt16) throws -> UInt64 {
        var reader = ArchiveByteReader(block, position: prefixSize, end: headerSize)
        guard reader.remaining >= fileFieldsSize - prefixSize else { throw PreviewFailure.malformedDocument }
        var packed = UInt64(try reader.uint32())
        if flags & 0x0100 != 0 {
            // The high word sits after the attribute field, at byte 32 of the header.
            try reader.skip(fileFieldsSize - prefixSize - 4)
            packed |= UInt64(try reader.uint32()) << 32
        }
        return packed
    }

    private static func fileEntry(_ block: [UInt8], headerSize: Int, flags: UInt16,
                                  context: RequestContext) throws -> ContainerEntry {
        var reader = ArchiveByteReader(block, position: prefixSize, end: headerSize)
        _ = try reader.uint32() // packed size, read by fileLayout
        let unpackedLow = UInt64(try reader.uint32())
        let hostOS = try reader.byte()
        _ = try reader.uint32() // file CRC32
        let modified = ArchiveListing.date(dosPackedTime: try reader.uint32())
        _ = try reader.byte() // version needed to extract
        _ = try reader.byte() // method
        let nameSize = Int(try reader.uint16())
        let attributes = try reader.uint32()
        var unpackedHigh: UInt64 = 0
        if flags & 0x0100 != 0 {
            _ = try reader.uint32() // high packed size
            unpackedHigh = UInt64(try reader.uint32())
        }
        let rawName = Array(try reader.take(nameSize))
        let isDirectory = flags & 0x00E0 == 0x00E0
        var name = try decodedName(rawName, unicode: flags & 0x0200 != 0, context: context)
        // Windows-hosted archives (MS-DOS, OS/2, Win32) store backslash separators.
        if hostOS <= 2 { name = name.replacingOccurrences(of: "\\", with: "/") }
        var kind = isDirectory ? "directory" : "file"
        if !isDirectory, hostOS >= 3, attributes & 0xF000 == 0xA000 { kind = "symlink" }
        let unknownSize = unpackedLow == 0xFFFF_FFFF && unpackedHigh == 0xFFFF_FFFF
        let size: Int? = unknownSize ? nil : try boundedInt(unpackedLow | unpackedHigh << 32)
        return ContainerEntry(path: try listableArchivePath(name), kind: kind, size: size,
                              modified: modified, isEncrypted: flags & 0x0004 != 0)
    }

    /// With the Unicode flag the field holds a zero-terminated byte name followed by an encoded
    /// UTF-16 name. Without it the name uses the archiver's byte encoding: UTF-8 when valid,
    /// otherwise code page 437, the MS-DOS default.
    private static func decodedName(_ raw: [UInt8], unicode: Bool, context: RequestContext) throws -> String {
        guard !raw.isEmpty else { throw PreviewFailure.malformedDocument }
        if unicode, let terminator = raw.firstIndex(of: 0) {
            let encoded = Array(raw[(terminator + 1)...])
            if !encoded.isEmpty {
                let units = try RARUnicodeName.decode(encoded, companion: Array(raw[..<terminator]), context: context)
                return String(decoding: units, as: UTF16.self)
            }
        }
        let bytes = Array(raw.prefix(while: { $0 != 0 }))
        if let text = String(data: Data(bytes), encoding: .utf8) { return text }
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            let value = byte < 0x80 ? UInt32(byte) : UInt32(CodePage437.upperHalf[Int(byte) - 0x80])
            scalars.append(Unicode.Scalar(value) ?? "\u{FFFD}")
        }
        return String(scalars)
    }
}
