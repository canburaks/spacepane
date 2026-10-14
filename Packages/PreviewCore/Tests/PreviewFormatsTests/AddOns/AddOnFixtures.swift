import Foundation
import zlib
import PreviewContracts
@testable import PreviewFormats

/// Synthetic packages for the MCP bundle, editor extension and browser extension tests. Everything is
/// built from bytes in test code: no sample is read from disk, produced by a tool or run.
enum AddOnFixtures {
    /// A marker no preview of a package may ever contain.
    static let secret = "synthetic-secret-value"

    struct Member {
        let path: String
        let data: Data
        var deflated = false
        init(_ path: String, _ data: Data, deflated: Bool = false) {
            self.path = path
            self.data = data
            self.deflated = deflated
        }
        init(_ path: String, text: String, deflated: Bool = false) { self.init(path, Data(text.utf8), deflated: deflated) }
    }

    /// Container-scan limits with a generous clock, as the adapters are registered.
    static var context: RequestContext { RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)) }

    /// The findings of a document as kind and count.
    static func counts(_ document: ParsedTextDocument) -> [PreviewFindingKind: Int] {
        Dictionary(uniqueKeysWithValues: document.findings.map { ($0.kind, $0.count) })
    }

    // MARK: JSON

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: ZIP

    static func little(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return UInt32(zlib.crc32(0, nil, 0)) }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }

    /// Raw DEFLATE, as a ZIP member stores it.
    static func rawDeflate(_ data: Data) -> Data {
        var stream = z_stream()
        precondition(deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY,
                                   ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(data.count))) + 16)
        var input = data
        let produced = output.withUnsafeMutableBytes { target in
            input.withUnsafeMutableBytes { source -> Int in
                stream.next_in = source.bindMemory(to: Bytef.self).baseAddress
                stream.avail_in = uInt(source.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(target.count)
                precondition(deflate(&stream, Z_FINISH) == Z_STREAM_END)
                return target.count - Int(stream.avail_out)
            }
        }
        return output.prefix(produced)
    }

    /// A ZIP archive with correct CRCs, sizes and offsets; members are stored unless marked `deflated`.
    static func zip(_ members: [Member]) -> Data {
        var archive = Data()
        var directory = Data()
        for member in members {
            let name = Data(member.path.utf8)
            let payload = member.deflated ? rawDeflate(member.data) : member.data
            let method: UInt64 = member.deflated ? 8 : 0
            let checksum = UInt64(crc32(member.data))
            let offset = archive.count
            archive += little(0x04034b50, 4) + little(20, 2) + little(0x800, 2) + little(method, 2) + little(0, 2) + little(0x21, 2)
            archive += little(checksum, 4) + little(UInt64(payload.count), 4) + little(UInt64(member.data.count), 4)
            archive += little(UInt64(name.count), 2) + little(0, 2) + name + payload
            directory += little(0x02014b50, 4) + little(20, 2) + little(20, 2) + little(0x800, 2) + little(method, 2) + little(0, 2) + little(0x21, 2)
            directory += little(checksum, 4) + little(UInt64(payload.count), 4) + little(UInt64(member.data.count), 4)
            directory += little(UInt64(name.count), 2) + little(0, 2) + little(0, 2) + little(0, 2) + little(0, 2)
            directory += little(0, 4) + little(UInt64(offset), 4) + name
        }
        let start = archive.count
        archive += directory
        archive += little(0x06054b50, 4) + little(0, 2) + little(0, 2) + little(UInt64(members.count), 2) + little(UInt64(members.count), 2)
        archive += little(UInt64(directory.count), 4) + little(UInt64(start), 4) + little(0, 2)
        return archive
    }

    // MARK: Chrome packages

    /// A CRX3 file: magic, version 3, the header length, a header of that many bytes and then the archive.
    static func crx3(header: Data = Data(repeating: 0x0A, count: 40), archive: Data) -> Data {
        Data("Cr24".utf8) + little(3, 4) + little(UInt64(header.count), 4) + header + archive
    }

    /// A CRX2 file: magic, version 2, the key and signature lengths, then both, then the archive.
    static func crx2(key: Data = Data(repeating: 1, count: 30), signature: Data = Data(repeating: 2, count: 20), archive: Data) -> Data {
        Data("Cr24".utf8) + little(2, 4) + little(UInt64(key.count), 4) + little(UInt64(signature.count), 4) + key + signature + archive
    }

    // MARK: Native code

    /// A 64-bit little-endian Mach-O header, enough for the signature check and nothing else.
    static var machO: Data { little(0xFEED_FACF, 4) + little(0x0100_000C, 4) + little(0, 4) + little(2, 4) + Data(repeating: 0, count: 64) }
    static var elf: Data { Data([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0]) + Data(repeating: 0, count: 64) }
}
