import Foundation
import CoreFoundation
import zlib
import PreviewContracts

/// One validated central-directory record. Every offset and size was checked against the
/// archive and its local header before this value exists.
struct ZIPEntry: Sendable {
    /// Validated by `safeArchivePath`: relative, no parent traversal, no control characters.
    let path: String
    /// "file", "directory" or "symlink".
    let kind: String
    let flags: UInt64
    /// 0 is stored and 8 is deflate; `ZIPArchiveReader.readMember` reads only those two.
    let method: UInt64
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let payloadOffset: Int
    /// "Version made by": its high byte names the host system that wrote the entry (3 Unix, 19 Darwin).
    let versionMadeBy: UInt64
    /// External file attributes; on Unix and Darwin hosts the high 16 bits are the mode.
    let externalAttributes: UInt64
    /// The extended-timestamp field when present, otherwise the stored MS-DOS wall-clock time
    /// interpreted as UTC. Present it in UTC so the stored digits are shown unchanged.
    let modified: Date?
    var isEncrypted: Bool { flags & 0x41 != 0 }
    /// Names and stored link targets use UTF-8 when general-purpose bit 11 is set, else code page 437.
    var nameEncoding: String.Encoding {
        flags & 0x800 != 0 ? .utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0400))
    }
}

struct ZIPArchive: Sendable {
    let isZip64: Bool
    let entries: [ZIPEntry]
    func entry(at path: String) -> ZIPEntry? { entries.first { $0.path == path } }
}

/// Shared, bounded ZIP/ZIP64 central-directory reader for every ZIP-based format (listings,
/// ebooks, comics, application packages, NumPy archives). It never extracts to disk.
enum ZIPArchiveReader {
    enum EncryptedEntryPolicy { case reject, list }
    /// `members` rejects names that would be unsafe to resolve (absolute, `..`, drive letters), which
    /// every format that reads members by name needs. `listing` keeps such names as inert text so the
    /// archive risk report can show them; nothing is ever extracted.
    enum PathPolicy { case members, listing }

    static func read(_ source: any PreviewByteSource, context: RequestContext,
                     encryptedEntries: EncryptedEntryPolicy = .reject, paths: PathPolicy = .members) throws -> ZIPArchive {
        let limits = ContainerLimits(context: context)
        try context.checkpoint()
        guard source.byteCount >= 22 else { throw PreviewFailure.malformedDocument }
        let tailCount = Int(min(source.byteCount, 65_557))
        let tailStart = source.byteCount - Int64(tailCount)
        let tail = BinaryCursor(try source.read(offset: tailStart, count: tailCount, context: context))
        var end: Int?
        for offset in stride(from: tail.bytes.count - 22, through: 0, by: -1) {
            if offset.isMultiple(of: 1024) { try context.checkpoint() }
            if try tail.integer(at: offset, width: 4, littleEndian: true) == 0x06054b50,
               offset + 22 + (try boundedInt(tail.integer(at: offset + 20, width: 2, littleEndian: true))) == tail.bytes.count {
                end = offset
                break
            }
        }
        guard let end else { throw PreviewFailure.malformedDocument }
        guard try tail.integer(at: end + 4, width: 2, littleEndian: true) == 0,
              try tail.integer(at: end + 6, width: 2, littleEndian: true) == 0,
              try tail.integer(at: end + 8, width: 2, littleEndian: true) == tail.integer(at: end + 10, width: 2, littleEndian: true) else {
            throw PreviewFailure.unsupportedFormat
        }
        var count = try tail.integer(at: end + 10, width: 2, littleEndian: true)
        var directorySize = try tail.integer(at: end + 12, width: 4, littleEndian: true)
        var directoryOffset = try tail.integer(at: end + 16, width: 4, littleEndian: true)
        var directoryEnd = tailStart + Int64(end)
        let zip64 = count == 0xffff || directorySize == 0xffffffff || directoryOffset == 0xffffffff
        if zip64 {
            guard end >= 20, try tail.integer(at: end - 20, width: 4, littleEndian: true) == 0x07064b50,
                  try tail.integer(at: end - 16, width: 4, littleEndian: true) == 0,
                  try tail.integer(at: end - 4, width: 4, littleEndian: true) == 1 else { throw PreviewFailure.unsupportedFormat }
            let recordOffset = try boundedInt(tail.integer(at: end - 12, width: 8, littleEndian: true))
            guard Int64(recordOffset) <= directoryEnd - 76 else { throw PreviewFailure.malformedDocument }
            let record = BinaryCursor(try source.read(offset: Int64(recordOffset), count: 56, context: context))
            guard try record.integer(at: 0, width: 4, littleEndian: true) == 0x06064b50 else { throw PreviewFailure.malformedDocument }
            let recordSize = try boundedInt(record.integer(at: 4, width: 8, littleEndian: true))
            guard recordSize >= 44, Int64(recordSize) == directoryEnd - 20 - Int64(recordOffset) - 12,
                  try record.integer(at: 16, width: 4, littleEndian: true) == 0,
                  try record.integer(at: 20, width: 4, littleEndian: true) == 0,
                  try record.integer(at: 24, width: 8, littleEndian: true) == record.integer(at: 32, width: 8, littleEndian: true) else { throw PreviewFailure.unsupportedFormat }
            count = try record.integer(at: 32, width: 8, littleEndian: true)
            directorySize = try record.integer(at: 40, width: 8, littleEndian: true)
            directoryOffset = try record.integer(at: 48, width: 8, littleEndian: true)
            directoryEnd = Int64(recordOffset)
        }
        let entryCount = try boundedInt(count)
        let size = try boundedInt(directorySize)
        let start = try boundedInt(directoryOffset)
        guard entryCount <= limits.maxEntries else { throw PreviewFailure.tooManyNodes }
        guard size <= limits.maxDirectoryBytes else { throw PreviewFailure.inputTooLarge }
        guard Int64(start) <= directoryEnd, Int64(size) == directoryEnd - Int64(start) else { throw PreviewFailure.malformedDocument }
        var directory = BinaryCursor(try source.read(offset: Int64(start), count: size, context: context))
        var entries: [ZIPEntry] = []
        var memberRanges: [Range<Int>] = []
        var metadataBytes = 0
        for _ in 0..<entryCount {
            try context.checkpoint()
            let record = directory.offset
            guard try directory.integer(4, littleEndian: true) == 0x02014b50 else { throw PreviewFailure.malformedDocument }
            let versionMadeBy = try directory.integer(2, littleEndian: true)
            _ = try directory.read(2)
            let flags = try directory.integer(2, littleEndian: true)
            let method = try directory.integer(2, littleEndian: true)
            let dosTime = try directory.integer(2, littleEndian: true)
            let dosDate = try directory.integer(2, littleEndian: true)
            let crc = try directory.integer(4, littleEndian: true)
            var compressed = try directory.integer(4, littleEndian: true)
            var uncompressed = try directory.integer(4, littleEndian: true)
            let nameLength = try boundedInt(directory.integer(2, littleEndian: true))
            let extraLength = try boundedInt(directory.integer(2, littleEndian: true))
            let commentLength = try boundedInt(directory.integer(2, littleEndian: true))
            var disk = try directory.integer(2, littleEndian: true)
            _ = try directory.read(2)
            let attributes = try directory.integer(4, littleEndian: true)
            var local = try directory.integer(4, littleEndian: true)
            let needsZip64 = uncompressed == 0xffffffff || compressed == 0xffffffff || local == 0xffffffff || disk == 0xffff
            // Bit 13 masks the central directory itself, so names cannot be listed at all.
            guard flags & 0x2000 == 0 else { throw PreviewFailure.unsupportedFormat }
            if encryptedEntries == .reject { guard flags & 0x41 == 0 else { throw PreviewFailure.unsupportedFormat } }
            metadataBytes += nameLength + extraLength + commentLength
            guard metadataBytes <= limits.maxMetadataBytes else { throw PreviewFailure.outputTooLarge }
            let name = try directory.read(nameLength)
            let extra = try directory.read(extraLength)
            _ = try directory.read(commentLength)
            guard directory.offset <= size else { throw PreviewFailure.malformedDocument }
            var field = BinaryCursor(Data(extra))
            var sawZip64 = false
            var unixModified: Date?
            while field.remaining > 0 {
                guard field.remaining >= 4 else { throw PreviewFailure.malformedDocument }
                let kind = try field.integer(2, littleEndian: true)
                let length = try boundedInt(field.integer(2, littleEndian: true))
                var value = BinaryCursor(Data(try field.read(length)))
                if kind == 1 {
                    guard !sawZip64 else { throw PreviewFailure.malformedDocument }
                    sawZip64 = true
                    if uncompressed == 0xffffffff { uncompressed = try value.integer(8, littleEndian: true) }
                    if compressed == 0xffffffff { compressed = try value.integer(8, littleEndian: true) }
                    if local == 0xffffffff { local = try value.integer(8, littleEndian: true) }
                    if disk == 0xffff { disk = try value.integer(4, littleEndian: true) }
                } else if kind == 0x5455, length >= 5, try value.integer(1) & 1 != 0 {
                    // Extended timestamp: the central copy carries only the UTC modification time.
                    let seconds = Int32(bitPattern: UInt32(try value.integer(4, littleEndian: true)))
                    unixModified = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            }
            guard !needsZip64 || sawZip64 else { throw PreviewFailure.malformedDocument }
            guard disk == 0 else { throw PreviewFailure.unsupportedFormat }
            let localOffset = try boundedInt(local)
            let compressedSize = try boundedInt(compressed)
            guard localOffset <= start - 30 else { throw PreviewFailure.malformedDocument }
            let localHeader = BinaryCursor(try source.read(offset: Int64(localOffset), count: 30, context: context))
            guard try localHeader.integer(at: 0, width: 4, littleEndian: true) == 0x04034b50,
                  try localHeader.integer(at: 6, width: 2, littleEndian: true) == flags,
                  try localHeader.integer(at: 8, width: 2, littleEndian: true) == method else { throw PreviewFailure.malformedDocument }
            let localNameLength = try boundedInt(localHeader.integer(at: 26, width: 2, littleEndian: true))
            let localExtraLength = try boundedInt(localHeader.integer(at: 28, width: 2, littleEndian: true))
            guard localNameLength + localExtraLength <= start - localOffset - 30 else { throw PreviewFailure.malformedDocument }
            let payloadOffset = localOffset + 30 + localNameLength + localExtraLength
            guard payloadOffset <= start, compressedSize <= start - payloadOffset,
                  localNameLength == nameLength else { throw PreviewFailure.malformedDocument }
            let localName = try source.read(offset: Int64(localOffset + 30), count: localNameLength, context: context)
            guard localName == Data(name) else { throw PreviewFailure.malformedDocument }
            if flags & 8 == 0 {
                let localCompressed = try localHeader.integer(at: 18, width: 4, littleEndian: true)
                let localUncompressed = try localHeader.integer(at: 22, width: 4, littleEndian: true)
                var validatedCompressed = localCompressed
                var validatedUncompressed = localUncompressed
                if localCompressed == 0xffffffff || localUncompressed == 0xffffffff {
                    var localExtra = BinaryCursor(try source.read(offset: Int64(localOffset + 30 + localNameLength), count: localExtraLength, context: context))
                    var found = false
                    while localExtra.remaining > 0 {
                        let key = try localExtra.integer(2, littleEndian: true)
                        let length = try boundedInt(localExtra.integer(2, littleEndian: true))
                        var value = BinaryCursor(Data(try localExtra.read(length)))
                        if key == 1 {
                            guard !found else { throw PreviewFailure.malformedDocument }
                            found = true
                            if localUncompressed == 0xffffffff { validatedUncompressed = try value.integer(8, littleEndian: true) }
                            if localCompressed == 0xffffffff { validatedCompressed = try value.integer(8, littleEndian: true) }
                        }
                    }
                    guard found else { throw PreviewFailure.malformedDocument }
                }
                guard validatedCompressed == compressed, validatedUncompressed == uncompressed else { throw PreviewFailure.malformedDocument }
            }
            memberRanges.append(localOffset..<(payloadOffset + compressedSize))
            let encoding = flags & 0x800 != 0 ? String.Encoding.utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0400))
            guard let path = String(data: Data(name), encoding: encoding) else { throw PreviewFailure.malformedDocument }
            let safePath = try paths == .members ? safeArchivePath(path) : listableArchivePath(path)
            let mode = (attributes >> 16) & 0xf000
            let kind = safePath.hasSuffix("/") || mode == 0x4000 ? "directory" : mode == 0xa000 ? "symlink" : "file"
            entries.append(ZIPEntry(path: safePath, kind: kind, flags: flags, method: method, crc32: UInt32(truncatingIfNeeded: crc),
                                    compressedSize: compressedSize, uncompressedSize: try boundedInt(uncompressed),
                                    payloadOffset: payloadOffset, versionMadeBy: versionMadeBy, externalAttributes: attributes,
                                    modified: unixModified ?? msDOSDate(date: dosDate, time: dosTime)))
            guard directory.offset > record else { throw PreviewFailure.malformedDocument }
        }
        guard directory.offset == size else { throw PreviewFailure.malformedDocument }
        let sortedRanges = memberRanges.sorted { $0.lowerBound < $1.lowerBound }
        for index in 1..<max(1, sortedRanges.count) {
            guard sortedRanges[index - 1].upperBound <= sortedRanges[index].lowerBound else { throw PreviewFailure.malformedDocument }
        }
        return ZIPArchive(isZip64: zip64, entries: entries)
    }

    /// Reads one member through bounded inflation and verifies its CRC-32. Encrypted members,
    /// methods other than stored/deflate and members larger than `maximumBytes` are rejected
    /// before any payload byte is read.
    static func readMember(_ entry: ZIPEntry, from source: any PreviewByteSource, maximumBytes: Int,
                           context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard !entry.isEncrypted else { throw PreviewFailure.encryptedContent }
        guard entry.kind == "file" else { throw PreviewFailure.notRegularFile }
        guard entry.method == 0 || entry.method == 8 else { throw PreviewFailure.unsupportedFormat }
        guard maximumBytes >= 0, entry.uncompressedSize <= maximumBytes else { throw PreviewFailure.inputTooLarge }
        let payload = try source.read(offset: Int64(entry.payloadOffset), count: entry.compressedSize, context: context)
        let data: Data
        if entry.method == 0 {
            guard entry.compressedSize == entry.uncompressedSize else { throw PreviewFailure.malformedDocument }
            data = payload
        } else {
            data = try BoundedDecompression.rawDeflate(payload, context: context, maximum: entry.uncompressedSize)
            guard data.count == entry.uncompressedSize else { throw PreviewFailure.malformedDocument }
        }
        let checksum = data.withUnsafeBytes { buffer -> UInt32 in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return UInt32(zlib.crc32(0, nil, 0)) }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
        guard checksum == entry.crc32 else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return data
    }

    private static func msDOSDate(date: UInt64, time: UInt64) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = 1980 + Int(date >> 9)
        components.month = Int((date >> 5) & 0x0f)
        components.day = Int(date & 0x1f)
        components.hour = Int(time >> 11)
        components.minute = Int((time >> 5) & 0x3f)
        components.second = Int(time & 0x1f) * 2
        guard (1...12).contains(components.month ?? 0), (1...31).contains(components.day ?? 0),
              (0...23).contains(components.hour ?? -1), (0...59).contains(components.minute ?? -1),
              (0...59).contains(components.second ?? -1) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}
