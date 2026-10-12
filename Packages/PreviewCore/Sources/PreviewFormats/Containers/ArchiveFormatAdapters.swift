import Foundation
import zlib
import PreviewContracts

/// Registrations for the archive family added by the competitor-parity program (decision 013).
/// Every adapter lists names and metadata only: member payloads are never decompressed or extracted.
public enum ArchiveFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .rar, defaultBudget: .containerScan, randomAccessAdapter: { RARListingAdapter() }),
        AdapterRegistration(formatID: .sevenZip, defaultBudget: .containerScan, randomAccessAdapter: { SevenZipListingAdapter() }),
        AdapterRegistration(formatID: .bzip2, defaultBudget: .containerScan, binaryAdapter: { BZip2PreviewAdapter() }),
        AdapterRegistration(formatID: .xz, defaultBudget: .containerScan, binaryAdapter: { XZPreviewAdapter() })
    ]
}

/// Listing rules shared by the archive adapters in this family and by the TAR reader.
enum ArchiveListing {
    /// The largest number of summary JSON nodes one listed entry can add: its object plus the
    /// path, type, bytes, modified and encrypted key/value pairs.
    static let nodesPerEntry = 11
    /// Nodes reserved for the root object and the optional archive-level fields.
    static let reservedNodes = 40

    /// Entries a listing may contain before it is reported as partial. Derived from the node
    /// budget so the summary writer can never fail with `tooManyNodes` after a successful scan.
    static func maxEntries(_ context: RequestContext) -> Int {
        let byNodes = max(1, (context.budget.maxJSONNodes - reservedNodes) / nodesPerEntry)
        return min(ContainerLimits(context: context).maxEntries, byNodes)
    }

    /// Timestamps outside 1970...2200 are treated as unknown rather than displayed.
    private static let plausibleSeconds: ClosedRange<Double> = 0...7_258_118_400

    static func date(unixSeconds seconds: Double) -> Date? {
        plausibleSeconds.contains(seconds) ? Date(timeIntervalSince1970: seconds.rounded(.down)) : nil
    }

    /// FILETIME counts 100 ns ticks since 1601-01-01 UTC.
    static func date(windowsFileTime ticks: UInt64) -> Date? {
        date(unixSeconds: Double(ticks / 10_000_000) - 11_644_473_600)
    }

    /// MS-DOS date and time packed as `date << 16 | time`. The archive stores no zone, so UTC is used.
    static func date(dosPackedTime value: UInt32) -> Date? {
        let time = value & 0xFFFF
        let day = (value >> 16) & 31, month = (value >> 21) & 15, year = 1980 + Int(value >> 25)
        let second = Int(time & 31) * 2, minute = Int((time >> 5) & 63), hour = Int(time >> 11)
        guard (1...31).contains(Int(day)), (1...12).contains(Int(month)), hour < 24, minute < 60, second < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: Int(month), day: Int(day),
                                                  hour: hour, minute: minute, second: second))
    }

    /// Leading bytes of executables that can carry a self-extracting archive after a stub.
    /// Such files are unsupported rather than malformed: the archive is not at offset zero.
    static func looksLikeExecutable(_ head: [UInt8]) -> Bool {
        let magics: [[UInt8]] = [[0x4D, 0x5A], [0x7F, 0x45, 0x4C, 0x46], [0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE],
                                 [0xFE, 0xED, 0xFA, 0xCF], [0xFE, 0xED, 0xFA, 0xCE], [0xCA, 0xFE, 0xBA, 0xBE]]
        return magics.contains { head.starts(with: $0) }
    }
}

/// CRC-32 (IEEE 802.3), the checksum RAR headers and 7z headers use.
enum ArchiveCRC32 {
    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(truncatingIfNeeded: zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }
    static func checksum(_ bytes: [UInt8]) -> UInt32 { checksum(bytes[...]) }
}

/// Bounds-checked cursor over one in-memory header. Every failure is `malformedDocument`; the
/// cursor never reads beyond `end`, so field sizes taken from the file cannot cause overreads.
struct ArchiveByteReader {
    let bytes: [UInt8]
    private(set) var position: Int
    let end: Int

    init(_ bytes: [UInt8], position: Int = 0, end: Int? = nil) {
        self.bytes = bytes
        self.position = position
        self.end = min(end ?? bytes.count, bytes.count)
    }

    var remaining: Int { max(0, end - position) }
    var isAtEnd: Bool { position >= end }

    mutating func byte() throws -> UInt8 {
        guard position < end else { throw PreviewFailure.malformedDocument }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw PreviewFailure.malformedDocument }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    mutating func skip(_ count: Int) throws { _ = try take(count) }

    mutating func littleEndian(_ width: Int) throws -> UInt64 {
        precondition((1...8).contains(width))
        return try take(width).reversed().reduce(0) { ($0 << 8) | UInt64($1) }
    }
    mutating func uint16() throws -> UInt16 { UInt16(try littleEndian(2)) }
    mutating func uint32() throws -> UInt32 { UInt32(try littleEndian(4)) }
    mutating func uint64() throws -> UInt64 { try littleEndian(8) }

    /// Converts an untrusted count to an `Int` no larger than `limit`, before it sizes an allocation.
    static func bounded(_ value: UInt64, limit: Int) throws -> Int {
        guard value <= UInt64(max(0, limit)) else { throw PreviewFailure.malformedDocument }
        return Int(value)
    }
}
