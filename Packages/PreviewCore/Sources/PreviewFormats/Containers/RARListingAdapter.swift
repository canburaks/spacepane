import Foundation
import PreviewContracts

/// Lists RAR 1.5-4.x and RAR 5.0 archives from their block headers only. Written from the
/// public RAR technical notes: member data areas are skipped by their declared sizes and are
/// never read, decompressed or decrypted. Header CRCs are verified before any field is trusted.
public struct RARListingAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        return try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let listing: RARListing
        switch try RARSignature.detect(source, context: context) {
        case .rar5: listing = try RAR5Listing.read(source, context: context)
        case .rar4: listing = try RAR4Listing.read(source, context: context)
        }
        return try listingDocument(format: listing.formatName, entries: listing.entries, context: context,
                                   partial: listing.partial, extra: listing.summaryFields, assessRisks: true)
    }
}

/// The two on-disk generations. RAR 1.4 (`RE~^`) and executables carrying an embedded archive
/// are recognized only to report them as unsupported.
enum RARSignature {
    case rar5, rar4

    static let rar5Bytes: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    static let rar4Bytes: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    private static let legacyBytes: [UInt8] = [0x52, 0x45, 0x7E, 0x5E]

    static func detect(_ source: any PreviewByteSource, context: RequestContext) throws -> RARSignature {
        guard source.byteCount >= 4 else { throw PreviewFailure.malformedDocument }
        let head = Array(try source.read(offset: 0, count: Int(min(8, source.byteCount)), context: context))
        if head.starts(with: rar5Bytes) { return .rar5 }
        if head.starts(with: rar4Bytes) { return .rar4 }
        if head.starts(with: legacyBytes) || ArchiveListing.looksLikeExecutable(head) {
            throw PreviewFailure.unsupportedFormat
        }
        throw PreviewFailure.malformedDocument
    }
}

/// Archive-level flags reported as summary fields. Only facts the headers state are recorded.
struct RARArchiveFlags {
    var solid = false
    var multiVolume = false
    var locked = false
    var recoveryRecord = false
    /// One-based volume number when the archive states it (RAR 5 volumes after the first).
    var volumeNumber: Int?
}

struct RARListing {
    let formatName: String
    var entries: [ContainerEntry] = []
    var partial = false
    var flags = RARArchiveFlags()

    var summaryFields: [(String, SummaryValue)] {
        var fields: [(String, SummaryValue)] = [
            ("solid", .boolean(flags.solid)), ("multiVolume", .boolean(flags.multiVolume))
        ]
        if let number = flags.volumeNumber { fields.append(("volumeNumber", .integer(number))) }
        fields.append(("locked", .boolean(flags.locked)))
        fields.append(("recoveryRecord", .boolean(flags.recoveryRecord)))
        return fields
    }
}

extension ArchiveByteReader {
    /// RAR 5.0 variable-length integer: seven payload bits per byte, least significant group
    /// first, high bit set while more bytes follow. At most ten bytes and 64 significant bits.
    mutating func rarVariableInteger() throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            let byte = try self.byte()
            let payload = UInt64(byte & 0x7F)
            guard index < 9 || payload <= 1 else { throw PreviewFailure.malformedDocument }
            value |= payload << UInt64(index * 7)
            if byte & 0x80 == 0 { return value }
        }
        throw PreviewFailure.malformedDocument
    }
}
