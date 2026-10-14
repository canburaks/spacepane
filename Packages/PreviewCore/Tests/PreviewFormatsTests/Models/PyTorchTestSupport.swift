import Foundation
import Synchronization
import Testing
import zlib
import PreviewContracts
@testable import PreviewFormats

/// Hand-built archives and compressed streams for the pickle tests. The members' bytes come from
/// `PickleStream`; nothing here loads or evaluates a pickle.
enum PyTorchZip {
    struct Member {
        var path: String
        var data: Data
        var deflated = false
        /// A stored checksum that does not match the data.
        var crc: UInt32?
        var flags: UInt16 = 0

        init(_ path: String, _ data: Data, deflated: Bool = false, crc: UInt32? = nil, flags: UInt16 = 0) {
            self.path = path
            self.data = data
            self.deflated = deflated
            self.crc = crc
            self.flags = flags
        }
        init(_ path: String, _ bytes: [UInt8], deflated: Bool = false, crc: UInt32? = nil, flags: UInt16 = 0) {
            self.init(path, Data(bytes), deflated: deflated, crc: crc, flags: flags)
        }
    }

    private static func little(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

    static func crc32(_ data: Data) -> UInt32 { PyTorchArchiveScanner.checksum(data) }

    /// Appends little-endian fields, each given as (value, width).
    private static func fields(_ values: [(UInt64, Int)]) -> Data {
        var data = Data()
        for (value, width) in values { data.append(little(value, width)) }
        return data
    }

    /// A ZIP archive in the layout PyTorch writes: a local header and payload per member, then the central directory.
    static func build(_ members: [Member]) -> Data {
        var archive = Data()
        var directory = Data()
        for member in members {
            let name = Data(member.path.utf8)
            let payload = member.deflated ? compress(member.data, windowBits: -15) : member.data
            let method: UInt64 = member.deflated ? 8 : 0
            let checksum = UInt64(member.crc ?? crc32(member.data))
            let flags = UInt64(member.flags)
            let sizes: [(UInt64, Int)] = [(UInt64(payload.count), 4), (UInt64(member.data.count), 4), (UInt64(name.count), 2)]
            let offset = archive.count
            archive.append(fields([(0x04034b50, 4), (20, 2), (flags, 2), (method, 2), (0, 2), (0x21, 2), (checksum, 4)] + sizes + [(0, 2)]))
            archive.append(name)
            archive.append(payload)
            directory.append(fields([(0x02014b50, 4), (20, 2), (20, 2), (flags, 2), (method, 2), (0, 2), (0x21, 2), (checksum, 4)]
                                    + sizes + [(0, 2), (0, 2), (0, 2), (0, 2), (0, 4), (UInt64(offset), 4)]))
            directory.append(name)
        }
        let directoryOffset = archive.count
        archive.append(directory)
        let count = UInt64(members.count)
        archive.append(fields([(0x06054b50, 4), (0, 2), (0, 2), (count, 2), (count, 2), (UInt64(directory.count), 4),
                               (UInt64(directoryOffset), 4), (0, 2)]))
        return archive
    }

    /// A checkpoint as `torch.save` writes it: the pickle, a version, a byte order and one 16-byte storage.
    static func checkpoint(pickle: [UInt8], storage: Int = 16, extra: [Member] = []) -> Data {
        build([Member("archive/data.pkl", pickle), Member("archive/byteorder", Array("little".utf8)),
               Member("archive/data/0", [UInt8](repeating: 0, count: storage)), Member("archive/version", Array("3\n".utf8))] + extra)
    }

    /// Deflate with the given window bits: -15 raw, 15 zlib, 31 gzip.
    static func compress(_ data: Data, windowBits: Int32) -> Data {
        var stream = z_stream()
        precondition(deflateInit2_(&stream, 6, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION,
                                   Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(data.count))) + 64)
        let produced: Int = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(out.count)
                precondition(deflate(&stream, Z_FINISH) == Z_STREAM_END)
                return Int(stream.total_out)
            }
        }
        return output.prefix(produced)
    }
}

/// A byte source that records every range read, to show what a scan never touched.
final class PickleRecordingSource: PreviewByteSource {
    private let inner: DataByteSource
    private let ranges = Mutex<[Range<Int64>]>([])
    var byteCount: Int64 { inner.byteCount }
    init(_ data: Data) { inner = DataByteSource(data) }

    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        ranges.withLock { $0.append(offset..<(offset + Int64(count))) }
        return try inner.read(offset: offset, count: count, context: context)
    }

    func touches(_ range: Range<Int>) -> Bool {
        ranges.withLock { $0.contains { $0.lowerBound < Int64(range.upperBound) && Int64(range.lowerBound) < $0.upperBound } }
    }
}

/// A scan's summary as the tests read it.
struct PickleResult {
    let document: ParsedTextDocument
    let json: [String: Any]

    init(_ document: ParsedTextDocument) {
        self.document = document
        json = PackageTestSupport.object(document)
    }

    var container: String? { json["container"] as? String }
    var protocolVersion: Int? { json["pickleProtocol"] as? Int }
    var imports: [[String: Any]] { json["imports"] as? [[String: Any]] ?? [] }
    var importNames: [String] { imports.compactMap { $0["name"] as? String } }
    func kind(of name: String) -> String? { imports.first { $0["name"] as? String == name }?["kind"] as? String }
    var findings: [PreviewFindingKind] { document.findings.map(\.kind) }
    func count(of kind: PreviewFindingKind) -> Int? { document.findings.first { $0.kind == kind }?.count }
}

extension PickleStream {
    /// Protocol 2: each pair is imported by `GLOBAL` and discarded, which names the import without calling it.
    static func imports(_ pairs: [(String, String)]) -> [UInt8] {
        join(proto2, pairs.flatMap { global($0.0, $0.1) + pop }, none, stop)
    }
}
