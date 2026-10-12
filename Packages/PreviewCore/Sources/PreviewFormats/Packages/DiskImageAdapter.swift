import Foundation
import PreviewContracts

/// Summarizes a UDIF disk image (`.dmg`) from its 512-byte trailer and partition table.
///
/// Only the trailer ("koly") and the XML property list it points at are read. Partition data is never
/// read or decompressed and nothing is mounted. Encrypted images are reported as encrypted without any
/// attempt to unlock them, and images without a UDIF trailer (raw or sparse images) are unsupported.
public struct DiskImageAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let trailerLength = 512
    static let sectorLength: UInt64 = 512
    static let maximumPartitionTableBytes = 786_432
    static let maximumPartitions = 128
    static let maximumChunkRecords = 100_000

    private static let udifSignature: [UInt8] = Array("koly".utf8)
    private static let encryptionSignatures: [[UInt8]] = [Array("encrcdsa".utf8), Array("cdsaencr".utf8)]
    private static let internetEnabledFlag: UInt64 = 0x4
    private static let blockMapSignature: [UInt8] = Array("mish".utf8)
    private static let blockMapHeaderLength = 204
    private static let blockChunkLength = 40

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size >= 8 else { throw PreviewFailure.unsupportedFormat }
        let head = [UInt8](try source.read(offset: 0, count: 8, context: context))
        if Self.encryptionSignatures.contains(head) { throw PreviewFailure.encryptedContent }
        guard size >= Int64(Self.trailerLength) else { throw PreviewFailure.unsupportedFormat }
        let trailerStart = size - Int64(Self.trailerLength)
        let trailer = BinaryCursor(try source.read(offset: trailerStart, count: Self.trailerLength, context: context))
        guard Array(trailer.bytes.prefix(4)) == Self.udifSignature else {
            if Self.encryptionSignatures.contains(where: { containsSubsequence(trailer.bytes, $0) }) { throw PreviewFailure.encryptedContent }
            throw PreviewFailure.unsupportedFormat
        }
        guard try trailer.integer(at: 8, width: 4) == UInt64(Self.trailerLength) else { throw PreviewFailure.malformedDocument }

        let version = try trailer.integer(at: 4, width: 4)
        let flags = try trailer.integer(at: 12, width: 4)
        let dataOffset = try trailer.integer(at: 24, width: 8)
        let dataLength = try trailer.integer(at: 32, width: 8)
        let segmentCount = try trailer.integer(at: 60, width: 4)
        let xmlOffset = try trailer.integer(at: 216, width: 8)
        let xmlLength = try trailer.integer(at: 224, width: 8)
        let sectors = try trailer.integer(at: 492, width: 8)
        let limit = UInt64(trailerStart)
        guard dataOffset <= limit, dataLength <= limit - dataOffset, xmlOffset <= limit, xmlLength <= limit - xmlOffset else {
            throw PreviewFailure.malformedDocument
        }

        var fields = SummaryFields()
        fields.number("udifVersion", Int(clamping: version))
        let (imageBytes, overflow) = sectors.multipliedReportingOverflow(by: Self.sectorLength)
        if !overflow { fields.number("imageBytes", Int64(clamping: imageBytes)) }
        fields.number("sectorCount", Int64(clamping: sectors))
        fields.number("dataForkBytes", Int64(clamping: dataLength))
        fields.number("segmentCount", Int(clamping: segmentCount))
        fields.flag("internetEnabled", flags & Self.internetEnabledFlag != 0)

        var partial = false
        if xmlLength > 0 {
            let allowance = min(UInt64(Self.maximumPartitionTableBytes), UInt64(max(0, context.budget.maxInputBytes - Self.trailerLength - 8)))
            if xmlLength <= allowance {
                let table = try source.read(offset: Int64(xmlOffset), count: Int(xmlLength), context: context)
                let parsed = try Self.partitions(from: table, context: context)
                if !parsed.partitions.isEmpty {
                    fields.add("partitions", .array(parsed.partitions.map { $0.summaryValue() }))
                }
                fields.list("compressions", parsed.compressions)
                partial = parsed.isPartial
            } else {
                // The table is larger than a preview may read: the trailer facts above still stand.
                partial = true
            }
        }
        fields.flag("partial", partial)
        // Image checksums are not computed: nothing about the image's integrity is claimed.
        return try PackageSummary.document(fields.value, context: context)
    }

    // MARK: Partition table

    struct Partition: Equatable {
        let name: String
        let bytes: Int64?
        func summaryValue() -> SummaryValue {
            var fields = SummaryFields()
            fields.text("name", name)
            fields.number("bytes", bytes)
            return fields.value
        }
    }

    static func partitions(from data: Data, context: RequestContext) throws -> (partitions: [Partition], compressions: [String], isPartial: Bool) {
        let list = try BoundedPropertyList.dictionary(data, context: context)
        guard let resourceFork = list["resource-fork"] as? [String: Any] else { return ([], [], false) }
        let blocks = PlistAccess.dictionaries(resourceFork, "blkx")
        var partitions: [Partition] = []
        var compressions: [String] = []
        var partial = blocks.count > maximumPartitions
        for block in blocks.prefix(maximumPartitions) {
            try context.checkpoint()
            let name = PlistAccess.string(block, "Name") ?? PlistAccess.string(block, "CFName") ?? ""
            var bytes: Int64?
            if let map = block["Data"] as? Data {
                let summary = try blockMap(map, context: context)
                bytes = summary.bytes
                for method in summary.methods where !compressions.contains(method) { compressions.append(method) }
                partial = partial || summary.isPartial
            } else {
                partial = true
            }
            partitions.append(Partition(name: PackageSummary.clipped(name, limit: 256), bytes: bytes))
        }
        return (partitions, compressions, partial)
    }

    /// Reads one block-map ("mish") header and its run types. Compressed runs are only classified.
    private static func blockMap(_ data: Data, context: RequestContext) throws -> (bytes: Int64?, methods: [String], isPartial: Bool) {
        let cursor = BinaryCursor(data)
        guard cursor.bytes.count >= blockMapHeaderLength, Array(cursor.bytes.prefix(4)) == blockMapSignature else { return (nil, [], true) }
        let sectors = try cursor.integer(at: 16, width: 8)
        let (bytes, overflow) = sectors.multipliedReportingOverflow(by: sectorLength)
        let runCount = Int(clamping: try cursor.integer(at: 200, width: 4))
        let available = (cursor.bytes.count - blockMapHeaderLength) / blockChunkLength
        var partial = runCount > available || runCount > maximumChunkRecords
        var methods: [String] = []
        for index in 0..<min(runCount, available, maximumChunkRecords) {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            let type = UInt32(truncatingIfNeeded: try cursor.integer(at: blockMapHeaderLength + index * blockChunkLength, width: 4))
            guard let method = compressionName(type), !methods.contains(method) else { continue }
            methods.append(method)
        }
        if runCount == 0 { partial = true }
        return (overflow ? nil : Int64(clamping: bytes), methods, partial)
    }

    /// Run types that carry data, named as imaging tools name them; zero-fill, ignore, comment and
    /// terminator runs carry none and are skipped.
    private static func compressionName(_ type: UInt32) -> String? {
        switch type {
        case 0x0000_0001: "raw"
        case 0x8000_0004: "ADC"
        case 0x8000_0005: "zlib"
        case 0x8000_0006: "bzip2"
        case 0x8000_0007: "LZFSE"
        case 0x8000_0008: "LZMA"
        default: nil
        }
    }

    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where haystack[start..<(start + needle.count)].elementsEqual(needle) { return true }
        return false
    }
}
