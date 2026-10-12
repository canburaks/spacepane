import Foundation
import PreviewContracts

/// Property identifiers of the 7z header grammar (7zFormat.txt).
enum SevenZipID {
    static let end: UInt64 = 0x00
    static let header: UInt64 = 0x01
    static let archiveProperties: UInt64 = 0x02
    static let additionalStreamsInfo: UInt64 = 0x03
    static let mainStreamsInfo: UInt64 = 0x04
    static let filesInfo: UInt64 = 0x05
    static let packInfo: UInt64 = 0x06
    static let unpackInfo: UInt64 = 0x07
    static let subStreamsInfo: UInt64 = 0x08
    static let size: UInt64 = 0x09
    static let crc: UInt64 = 0x0A
    static let folder: UInt64 = 0x0B
    static let codersUnpackSize: UInt64 = 0x0C
    static let numUnpackStream: UInt64 = 0x0D
    static let emptyStream: UInt64 = 0x0E
    static let emptyFile: UInt64 = 0x0F
    static let anti: UInt64 = 0x10
    static let name: UInt64 = 0x11
    static let modificationTime: UInt64 = 0x14
    static let windowsAttributes: UInt64 = 0x15
    static let encodedHeader: UInt64 = 0x17
}

extension ArchiveByteReader {
    /// 7z variable-length number: the count of leading one bits in the first byte is the number of
    /// extra little-endian bytes; the remaining low bits of the first byte are the most significant part.
    mutating func sevenZipNumber() throws -> UInt64 {
        let first = try byte()
        var mask: UInt8 = 0x80
        var value: UInt64 = 0
        for index in 0..<8 {
            if first & mask == 0 {
                return value &+ (UInt64(first & (mask &- 1)) << UInt64(8 * index))
            }
            value |= UInt64(try byte()) << UInt64(8 * index)
            mask >>= 1
        }
        return value
    }

    /// A bounded count: never larger than the bytes that remain, so it cannot size a large allocation.
    mutating func sevenZipCount(limit: Int? = nil) throws -> Int {
        try Self.bounded(try sevenZipNumber(), limit: min(limit ?? remaining, remaining))
    }

    mutating func skipSevenZipProperty() throws {
        try skip(try Self.bounded(try sevenZipNumber(), limit: remaining))
    }

    /// A sub-reader over the next `count` bytes; the parent advances past them.
    mutating func subReader(_ count: Int) throws -> ArchiveByteReader {
        let start = position
        try skip(count)
        return ArchiveByteReader(bytes, position: start, end: start + count)
    }
}

/// An MSB-first bit vector stored in the header, addressed in place without copying.
struct SevenZipBitVector {
    private let bytes: [UInt8]
    private let start: Int
    let count: Int

    init(_ reader: inout ArchiveByteReader, count: Int) throws {
        let needed = (count + 7) / 8
        guard needed <= reader.remaining else { throw PreviewFailure.malformedDocument }
        start = reader.position
        bytes = reader.bytes
        self.count = count
        try reader.skip(needed)
    }

    subscript(index: Int) -> Bool {
        precondition(index >= 0 && index < count)
        return bytes[start + index / 8] & (0x80 >> UInt8(index % 8)) != 0
    }

    var setCount: Int {
        (0..<count).reduce(0) { $0 + (self[$1] ? 1 : 0) }
    }
}

struct SevenZipCoder {
    static let copy: [UInt8] = [0x00]
    static let lzma: [UInt8] = [0x03, 0x01, 0x01]
    static let lzma2: [UInt8] = [0x21]
    static let aes: [UInt8] = [0x06, 0xF1, 0x07, 0x01]

    let id: [UInt8]
    let inputCount: Int
    let outputCount: Int
    let properties: [UInt8]
}

/// One folder: a graph of coders that turns packed streams into one unpacked stream holding one or more files.
struct SevenZipFolder {
    var coders: [SevenZipCoder] = []
    var bindPairs: [(input: Int, output: Int)] = []
    var packedStreams: [Int] = []
    var unpackSizes: [UInt64] = []
    var unpackCRC: UInt32?

    var hasEncryption: Bool { coders.contains { $0.id == SevenZipCoder.aes } }
    var outputTotal: Int { coders.reduce(0) { $0 + $1.outputCount } }

    /// The one output stream that no bind pair consumes: the folder's final data.
    var mainOutputIndex: Int? {
        let bound = Set(bindPairs.map(\.output))
        let free = (0..<outputTotal).filter { !bound.contains($0) }
        return free.count == 1 ? free[0] : nil
    }

    var unpackSize: UInt64 {
        guard let index = mainOutputIndex, index < unpackSizes.count else { return 0 }
        return unpackSizes[index]
    }

    /// Coder indices ordered from the packed stream to the final output. Only chains of simple
    /// coders (one input, one output) are supported; they are all a header stream ever needs.
    func decodeOrder() throws -> [Int] {
        guard packedStreams.count == 1, coders.allSatisfy({ $0.inputCount == 1 && $0.outputCount == 1 }) else {
            throw PreviewFailure.unsupportedFormat
        }
        var order: [Int] = []
        var current = packedStreams[0]
        while true {
            guard current < coders.count, !order.contains(current) else { throw PreviewFailure.malformedDocument }
            order.append(current)
            guard let pair = bindPairs.first(where: { $0.output == current }) else { break }
            current = pair.input
        }
        guard order.count == coders.count else { throw PreviewFailure.malformedDocument }
        return order
    }
}

/// Pack streams, folders and per-folder file streams (`StreamsInfo`). Only sizes and coder
/// identities are retained; no file data is ever read for a main stream.
struct SevenZipStreamsInfo {
    var packPosition: UInt64 = 0
    var packSizes: [UInt64] = []
    var folders: [SevenZipFolder] = []
    /// Number of file streams in each folder (one unless `SubStreamsInfo` says otherwise).
    var streamCounts: [Int] = []
    /// Unpacked sizes of the file streams, folder by folder, for at most `ContainerLimits.maxEntries` streams: a
    /// listing never reads past its own entry limit, and a header can declare far more streams than it may show.
    var streamSizes: [UInt64] = []

    static func parse(_ reader: inout ArchiveByteReader, context: RequestContext) throws -> SevenZipStreamsInfo {
        var info = SevenZipStreamsInfo()
        var id = try reader.sevenZipNumber()
        if id == SevenZipID.packInfo {
            try info.parsePackInfo(&reader, context: context)
            id = try reader.sevenZipNumber()
        }
        if id == SevenZipID.unpackInfo {
            try info.parseUnpackInfo(&reader, context: context)
            id = try reader.sevenZipNumber()
        }
        var sawSubStreams = false
        if id == SevenZipID.subStreamsInfo {
            try info.parseSubStreams(&reader, context: context)
            sawSubStreams = true
            id = try reader.sevenZipNumber()
        }
        guard id == SevenZipID.end else { throw PreviewFailure.malformedDocument }
        if !sawSubStreams {
            info.streamCounts = Array(repeating: 1, count: info.folders.count)
            info.streamSizes = info.folders.map(\.unpackSize)
        }
        return info
    }

    private mutating func parsePackInfo(_ reader: inout ArchiveByteReader, context: RequestContext) throws {
        packPosition = try reader.sevenZipNumber()
        // Each size takes at least one header byte.
        let count = try Self.boundedCount(&reader, minimumRecordBytes: 1, context: context)
        var sawSizes = false
        while true {
            try context.checkpoint()
            let id = try reader.sevenZipNumber()
            if id == SevenZipID.end { break }
            if id == SevenZipID.size {
                var sizes: [UInt64] = []
                sizes.reserveCapacity(count)
                for _ in 0..<count { sizes.append(try reader.sevenZipNumber()) }
                packSizes = sizes
                sawSizes = true
            } else if id == SevenZipID.crc {
                try Self.skipDigests(&reader, count: count)
            } else {
                try reader.skipSevenZipProperty()
            }
        }
        guard sawSizes || count == 0 else { throw PreviewFailure.malformedDocument }
    }

    private mutating func parseUnpackInfo(_ reader: inout ArchiveByteReader, context: RequestContext) throws {
        guard try reader.sevenZipNumber() == SevenZipID.folder else { throw PreviewFailure.malformedDocument }
        // A folder needs two bytes of coder description and at least one byte of unpack size.
        let count = try Self.boundedCount(&reader, minimumRecordBytes: 3, context: context)
        guard try reader.byte() == 0 else { throw PreviewFailure.unsupportedFormat } // external folder data
        for _ in 0..<count {
            try context.checkpoint()
            folders.append(try Self.folder(&reader))
        }
        guard try reader.sevenZipNumber() == SevenZipID.codersUnpackSize else { throw PreviewFailure.malformedDocument }
        for index in folders.indices {
            try context.checkpoint()
            for _ in 0..<folders[index].outputTotal { folders[index].unpackSizes.append(try reader.sevenZipNumber()) }
            guard folders[index].mainOutputIndex != nil else { throw PreviewFailure.malformedDocument }
        }
        while true {
            let id = try reader.sevenZipNumber()
            if id == SevenZipID.end { break }
            if id == SevenZipID.crc {
                let values = try Self.digests(&reader, count: count)
                for index in folders.indices { folders[index].unpackCRC = values[index] }
            } else {
                try reader.skipSevenZipProperty()
            }
        }
    }

    private mutating func parseSubStreams(_ reader: inout ArchiveByteReader, context: RequestContext) throws {
        let storedLimit = ContainerLimits(context: context).maxEntries
        var counts = Array(repeating: 1, count: folders.count)
        var id = try reader.sevenZipNumber()
        while id != SevenZipID.crc, id != SevenZipID.size, id != SevenZipID.end {
            if id == SevenZipID.numUnpackStream {
                var total = 0
                for index in counts.indices {
                    // Each stream but the last needs a stored size byte, bounding the claim by the header.
                    counts[index] = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: reader.remaining + 1)
                    total += counts[index]
                    guard total <= reader.remaining + folders.count else { throw PreviewFailure.malformedDocument }
                }
            } else {
                try reader.skipSevenZipProperty()
            }
            id = try reader.sevenZipNumber()
        }
        // Every stored size is still read and summed, so the header stays in step and each folder is checked,
        // but only the first `storedLimit` are kept: a header of one byte per stream must not size an array
        // eight bytes per stream.
        var sizes: [UInt64] = []
        if id == SevenZipID.size {
            for (index, folder) in folders.enumerated() where counts[index] > 0 {
                try context.checkpoint()
                var sum: UInt64 = 0
                for position in 1..<counts[index] {
                    if position.isMultiple(of: 4_096) { try context.checkpoint() }
                    let size = try reader.sevenZipNumber()
                    let (next, overflow) = sum.addingReportingOverflow(size)
                    guard !overflow else { throw PreviewFailure.malformedDocument }
                    sum = next
                    if sizes.count < storedLimit { sizes.append(size) }
                }
                guard folder.unpackSize >= sum else { throw PreviewFailure.malformedDocument }
                if sizes.count < storedLimit { sizes.append(folder.unpackSize - sum) }
            }
            id = try reader.sevenZipNumber()
        } else {
            for (index, folder) in folders.enumerated() {
                guard counts[index] <= 1 else { throw PreviewFailure.malformedDocument }
                if counts[index] == 1 { sizes.append(folder.unpackSize) }
            }
        }
        // Digests are read to stay in sync with the header and are not used: no payload is decoded.
        var digestCount = 0
        for (index, folder) in folders.enumerated() where counts[index] != 1 || folder.unpackCRC == nil {
            digestCount += counts[index]
        }
        while id != SevenZipID.end {
            if id == SevenZipID.crc { try Self.skipDigests(&reader, count: digestCount) }
            else { try reader.skipSevenZipProperty() }
            id = try reader.sevenZipNumber()
        }
        streamCounts = counts
        streamSizes = sizes
    }

    /// A count taken from the header, checked before it sizes any array. A count the remaining header bytes cannot
    /// hold at `minimumRecordBytes` each is malformed; one that could fit but exceeds the entries a listing may
    /// show is `tooManyNodes`. Either way nothing has been allocated for it.
    private static func boundedCount(_ reader: inout ArchiveByteReader, minimumRecordBytes: Int,
                                     context: RequestContext) throws -> Int {
        let value = try reader.sevenZipNumber()
        guard value <= UInt64(reader.remaining / max(1, minimumRecordBytes)) else { throw PreviewFailure.malformedDocument }
        guard value <= UInt64(max(0, ContainerLimits(context: context).maxEntries)) else { throw PreviewFailure.tooManyNodes }
        return Int(value)
    }

    /// The digests of `count` entries: an all-defined byte or a bit vector, then four bytes per defined digest. The
    /// count is a folder count that parsing has already bounded, and the bytes the vector needs are checked before
    /// any array is sized.
    private static func digests(_ reader: inout ArchiveByteReader, count: Int) throws -> [UInt32?] {
        let allDefined = try reader.byte() != 0
        if allDefined { guard count <= reader.remaining / 4 else { throw PreviewFailure.malformedDocument } }
        let bits = allDefined ? nil : try SevenZipBitVector(&reader, count: count)
        var values: [UInt32?] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            if allDefined || bits?[index] == true { values.append(try reader.uint32()) } else { values.append(nil) }
        }
        return values
    }

    /// Reads past a digest vector without keeping it: no payload is decoded, so the values are never used. Nothing is
    /// allocated for `count`, which a bit vector lets a few header bytes declare in the millions; the bytes the digests
    /// occupy must still be present.
    private static func skipDigests(_ reader: inout ArchiveByteReader, count: Int) throws {
        let allDefined = try reader.byte() != 0
        let defined = allDefined ? count : try SevenZipBitVector(&reader, count: count).setCount
        guard defined <= reader.remaining / 4 else { throw PreviewFailure.malformedDocument }
        try reader.skip(defined * 4)
    }

    private static func folder(_ reader: inout ArchiveByteReader) throws -> SevenZipFolder {
        var folder = SevenZipFolder()
        let coderCount = try reader.sevenZipNumber()
        guard (1...32).contains(coderCount) else { throw PreviewFailure.malformedDocument }
        var inputTotal = 0
        var outputTotal = 0
        for _ in 0..<Int(coderCount) {
            let flags = try reader.byte()
            // Bit 7 announced alternative methods in early drafts; no current writer sets it.
            guard flags & 0x80 == 0 else { throw PreviewFailure.unsupportedFormat }
            let id = Array(try reader.take(Int(flags & 0x0F)))
            guard id.count <= 8 else { throw PreviewFailure.malformedDocument }
            var inputs = 1, outputs = 1
            if flags & 0x10 != 0 {
                inputs = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: 32)
                outputs = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: 32)
            }
            var properties: [UInt8] = []
            if flags & 0x20 != 0 { properties = Array(try reader.take(try reader.sevenZipCount())) }
            folder.coders.append(SevenZipCoder(id: id, inputCount: inputs, outputCount: outputs, properties: properties))
            inputTotal += inputs
            outputTotal += outputs
        }
        guard outputTotal >= 1, inputTotal >= outputTotal else { throw PreviewFailure.malformedDocument }
        let bindCount = outputTotal - 1
        for _ in 0..<bindCount {
            let input = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: inputTotal - 1)
            let output = try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: outputTotal - 1)
            folder.bindPairs.append((input, output))
        }
        let packedCount = inputTotal - bindCount
        if packedCount == 1 {
            let bound = Set(folder.bindPairs.map(\.input))
            guard let free = (0..<inputTotal).first(where: { !bound.contains($0) }) else { throw PreviewFailure.malformedDocument }
            folder.packedStreams = [free]
        } else {
            for _ in 0..<packedCount {
                folder.packedStreams.append(try ArchiveByteReader.bounded(try reader.sevenZipNumber(), limit: inputTotal - 1))
            }
        }
        return folder
    }
}
