import Foundation
import zlib
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

/// Hand-assembled RAR 4, RAR 5 and plain-header 7z containers. The layouts follow the public format
/// descriptions and mirror script/archive_fixtures.py; independent readers (libarchive, py7zr) were
/// used once to check the Python equivalents. Members are stored, never compressed.
enum ArchiveFixtures {
    /// 2026-01-01T00:00:00Z.
    static let modified: UInt32 = 1_767_225_600
    static let modifiedISO = "2026-01-01T00:00:00Z"

    struct Member {
        var path: String
        /// nil is a directory.
        var payload: [UInt8]?
        var encrypted = false
        var symlink = false
        init(_ path: String, _ payload: String? = "", encrypted: Bool = false, symlink: Bool = false) {
            self.path = path
            self.payload = payload.map { Array($0.utf8) }
            self.encrypted = encrypted
            self.symlink = symlink
        }
        static func directory(_ path: String) -> Member { Member(path, nil) }
    }

    static let sampleMembers: [Member] = [
        .directory("Example"), Member("Example/readme.txt", "synthetic archive payload\n"),
        Member("Example/日本語.txt", "unicode name\n")
    ]

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(truncatingIfNeeded: zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }
    static func le(_ value: UInt64, _ width: Int) -> [UInt8] { (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }

    // MARK: RAR 5

    static func vint(_ value: UInt64) -> [UInt8] {
        var value = value, out: [UInt8] = []
        while true {
            let byte = UInt8(value & 0x7F)
            value >>= 7
            if value == 0 { out.append(byte); return out }
            out.append(byte | 0x80)
        }
    }

    static func rar5Block(type: UInt64, flags: UInt64 = 0, fields: [UInt8], extra: [UInt8] = [], data: [UInt8]? = nil) -> [UInt8] {
        var body = vint(type) + vint(flags | (extra.isEmpty ? 0 : 1) | (data == nil ? 0 : 2))
        if !extra.isEmpty { body += vint(UInt64(extra.count)) }
        if let data { body += vint(UInt64(data.count)) }
        body += fields + extra
        let size = vint(UInt64(body.count))
        return le(UInt64(crc32(size + body)), 4) + size + body + (data ?? [])
    }

    struct RAR5Options {
        var solid = false, locked = false, recovery = false
        /// Zero-based volume number; nil is a single-volume archive.
        var volume: UInt64?
        var encryptedHeaders = false
        var endBlock = true
        var serviceBlock = false
    }

    static func rar5(_ members: [Member] = sampleMembers, options: RAR5Options = .init()) -> Data {
        var out: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
        if options.encryptedHeaders {
            out += rar5Block(type: 4, fields: vint(0) + vint(0) + [15] + [UInt8](repeating: 0, count: 16))
            return Data(out)
        }
        let flags: UInt64 = (options.volume == nil ? 0 : 1) | ((options.volume ?? 0) > 0 ? 2 : 0) | (options.solid ? 4 : 0)
            | (options.recovery ? 8 : 0) | (options.locked ? 0x10 : 0)
        out += rar5Block(type: 1, fields: vint(flags) + ((options.volume ?? 0) > 0 ? vint(options.volume!) : []))
        for member in members {
            out += rar5File(member)
            if options.serviceBlock {
                // A comment service block with a data area: skipped, never listed.
                out += rar5Block(type: 3, fields: vint(0) + vint(4) + vint(0x20) + vint(0) + vint(1) + vint(3) + Array("CMT".utf8), data: Array("note".utf8))
            }
        }
        if options.endBlock { out += rar5Block(type: 5, fields: vint(0)) }
        return Data(out)
    }

    enum TimeRecord { case windows(UInt64), unix(UInt32), unixNanoseconds }

    static func rar5File(_ member: Member, unknownSize: Bool = false, timeRecord: TimeRecord? = nil) -> [UInt8] {
        let name = Array(member.path.utf8)
        let isDirectory = member.payload == nil
        let data = member.payload ?? []
        var fileFlags: UInt64 = isDirectory ? 0x01 : 0x04
        if timeRecord == nil { fileFlags |= 0x02 }
        if unknownSize { fileFlags |= 0x08 }
        var fields = vint(fileFlags) + vint(UInt64(data.count)) + vint(isDirectory ? 0x10 : 0x20)
        if timeRecord == nil { fields += le(UInt64(modified), 4) }
        if !isDirectory { fields += le(UInt64(crc32(data)), 4) }
        fields += vint(0) + vint(1) + vint(UInt64(name.count)) + name
        var extra: [UInt8] = []
        func append(_ record: [UInt8]) { extra += vint(UInt64(record.count)) + record }
        if member.encrypted { append(vint(1) + vint(0) + vint(0) + [15] + [UInt8](repeating: 0, count: 32)) }
        switch timeRecord {
        case .windows(let ticks): append(vint(3) + vint(0x02) + le(ticks, 8))
        case .unix(let seconds): append(vint(3) + vint(0x03) + le(UInt64(seconds), 4))
        case .unixNanoseconds: append(vint(3) + vint(0x13) + le(UInt64(modified), 4) + le(0, 4))
        case nil: break
        }
        if member.symlink {
            let target = Array("target".utf8)
            append(vint(5) + vint(1) + vint(0) + vint(UInt64(target.count)) + target)
        }
        return rar5Block(type: 2, fields: fields, extra: extra, data: data)
    }

    // MARK: RAR 4

    static func rar4Block(type: UInt8, flags: UInt16, body: [UInt8]) -> [UInt8] {
        let rest = [type] + le(UInt64(flags), 2) + le(UInt64(7 + body.count), 2) + body
        return le(UInt64(crc32(rest) & 0xFFFF), 2) + rest
    }

    static func dosTime(_ timestamp: UInt32) -> UInt32 {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UInt32(c.year! - 1980) << 25 | UInt32(c.month!) << 21 | UInt32(c.day!) << 16
            | UInt32(c.hour!) << 11 | UInt32(c.minute!) << 5 | UInt32(c.second! / 2)
    }

    struct RAR4Options {
        var solid = false, locked = false, recovery = false, volume = false
        var encryptedHeaders = false
        var endBlock = true
        var hostOS: UInt8 = 2
        var unicodeNames = false
        var highSizes = false
    }

    /// Compact UTF-16 name: each four units share one operation byte using operation 2 (a whole unit).
    static func rar4UnicodeName(_ name: String) -> [UInt8] {
        let ansi = name.unicodeScalars.map { $0.value < 256 ? UInt8($0.value) : UInt8(ascii: "?") }
        var encoded: [UInt8] = [0]
        let units = Array(name.utf16)
        var index = 0
        while index < units.count {
            let chunk = units[index..<min(index + 4, units.count)]
            var flags: UInt8 = 0
            for position in 0..<chunk.count { flags |= 2 << UInt8(6 - 2 * position) }
            encoded.append(flags)
            for unit in chunk { encoded += le(UInt64(unit), 2) }
            index += 4
        }
        return ansi + [0] + encoded
    }

    static func rar4(_ members: [Member] = sampleMembers, options: RAR4Options = .init()) -> Data {
        var out: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
        let flags: UInt16 = (options.volume ? 1 : 0) | (options.locked ? 4 : 0) | (options.solid ? 8 : 0)
            | (options.recovery ? 0x40 : 0) | (options.encryptedHeaders ? 0x80 : 0)
        out += rar4Block(type: 0x73, flags: flags, body: [UInt8](repeating: 0, count: 6))
        if options.encryptedHeaders { return Data(out) }
        for member in members { out += rar4File(member, options: options) }
        if options.endBlock { out += [0xC4, 0x3D, 0x7B, 0x00, 0x40, 0x07, 0x00] }
        return Data(out)
    }

    static func rar4File(_ member: Member, options: RAR4Options = .init(), nameBytes: [UInt8]? = nil,
                         blockType: UInt8 = 0x74) -> [UInt8] {
        let isDirectory = member.payload == nil
        let data = member.payload ?? []
        let name = nameBytes ?? (options.unicodeNames ? rar4UnicodeName(member.path) : Array(member.path.utf8))
        var flags: UInt16 = 0x8000 | (isDirectory ? 0xE0 : 0) | (member.encrypted ? 4 : 0) | (options.unicodeNames ? 0x200 : 0)
        if options.highSizes { flags |= 0x100 }
        let attributes: UInt32 = member.symlink ? 0xA1FF : (isDirectory ? 0x10 : 0x20)
        var body = le(UInt64(data.count), 4) + le(UInt64(data.count), 4) + [options.hostOS] + le(UInt64(crc32(data)), 4)
        body += le(UInt64(dosTime(modified)), 4) + [29, 0x30] + le(UInt64(name.count), 2) + le(UInt64(attributes), 4)
        if options.highSizes { body += le(0, 4) + le(0, 4) }
        body += name
        return rar4Block(type: blockType, flags: flags, body: body) + data
    }

    // MARK: 7z (plain header)

    static func sevenZipNumber(_ value: UInt64) -> [UInt8] {
        var first: UInt8 = 0, mask: UInt8 = 0x80, index = 0
        while index < 8 {
            if value < (UInt64(1) << UInt64(7 * (index + 1))) { first |= UInt8(truncatingIfNeeded: value >> UInt64(8 * index)); break }
            first |= mask
            mask >>= 1
            index += 1
        }
        return [first] + (0..<index).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
    }

    static func bitVector(_ bits: [Bool]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (index, bit) in bits.enumerated() where bit { out[index / 8] |= 0x80 >> UInt8(index % 8) }
        return out
    }

    static func sevenZipProperty(_ id: UInt8, _ payload: [UInt8]) -> [UInt8] { [id] + sevenZipNumber(UInt64(payload.count)) + payload }

    struct SevenZipOptions {
        /// Names that are anti items (deletion markers).
        var anti: Set<String> = []
        var attributes: [String: UInt32] = [:]
        /// Replaces the folder's coder identifier (for example the AES coder) to test coder handling.
        var folderCoder: [UInt8] = [0x00]
        var omitTimes = false
    }

    static func sevenZipHeader(_ members: [Member], options: SevenZipOptions = .init()) -> (header: [UInt8], packed: [UInt8]) {
        let streams = members.compactMap { $0.payload }.filter { !$0.isEmpty }
        let packed = streams.flatMap { $0 }
        var header: [UInt8] = [0x01]
        if !streams.isEmpty {
            header += [0x04]
            header += [0x06] + sevenZipNumber(0) + sevenZipNumber(1) + [0x09] + sevenZipNumber(UInt64(packed.count)) + [0x00]
            header += [0x07, 0x0B] + sevenZipNumber(1) + [0x00] + sevenZipNumber(1)
            header += [UInt8(options.folderCoder.count)] + options.folderCoder
            header += [0x0C] + sevenZipNumber(UInt64(packed.count)) + [0x00]
            header += [0x08, 0x0D] + sevenZipNumber(UInt64(streams.count))
            if streams.count > 1 { header += [0x09] + streams.dropLast().flatMap { sevenZipNumber(UInt64($0.count)) } }
            header += [0x0A, 0x01] + streams.flatMap { le(UInt64(crc32($0)), 4) }
            header += [0x00, 0x00]
        }
        header += [0x05] + sevenZipNumber(UInt64(members.count))
        let empty = members.map { $0.payload?.isEmpty ?? true }
        if empty.contains(true) {
            header += sevenZipProperty(0x0E, bitVector(empty))
            let emptyMembers = members.filter { $0.payload?.isEmpty ?? true }
            header += sevenZipProperty(0x0F, bitVector(emptyMembers.map { $0.payload != nil }))
            if !options.anti.isEmpty { header += sevenZipProperty(0x10, bitVector(emptyMembers.map { options.anti.contains($0.path) })) }
        }
        var names: [UInt8] = [0]
        for member in members { names += member.path.utf16.flatMap { le(UInt64($0), 2) } + [0, 0] }
        header += sevenZipProperty(0x11, names)
        if !options.omitTimes {
            let ticks = (UInt64(modified) + 11_644_473_600) * 10_000_000
            header += sevenZipProperty(0x14, [0x01, 0x00] + members.flatMap { _ in le(ticks, 8) })
        }
        header += sevenZipProperty(0x15, [0x01, 0x00] + members.flatMap { member in
            le(UInt64(options.attributes[member.path] ?? (member.payload == nil ? 0x10 : (member.symlink ? 0xA1FF_8000 : 0x20))), 4)
        })
        header += [0x00, 0x00]
        return (header, packed)
    }

    /// A 7z container; `nextHeader` replaces the plain header when given (for encoded headers).
    static func sevenZip(_ members: [Member] = sampleMembers, options: SevenZipOptions = .init(),
                         trailer: (body: [UInt8], nextHeader: [UInt8])? = nil) -> Data {
        let (header, packed) = sevenZipHeader(members, options: options)
        let body = trailer?.body ?? packed
        let next = trailer?.nextHeader ?? header
        return Data(sevenZipContainer(body: body, nextHeader: next))
    }

    static func sevenZipContainer(body: [UInt8], nextHeader: [UInt8]) -> [UInt8] {
        let start = le(UInt64(body.count), 8) + le(UInt64(nextHeader.count), 8) + le(UInt64(crc32(nextHeader)), 4)
        return [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04] + le(UInt64(crc32(start)), 4) + start + body + nextHeader
    }

    /// An `EncodedHeader` whose single folder uses `coder` and unpacks to `unpackSize` bytes.
    static func sevenZipEncodedHeader(packedPosition: UInt64, packedSize: Int, coder: [UInt8], unpackSize: UInt64, crc: UInt32? = nil) -> [UInt8] {
        var out: [UInt8] = [0x17, 0x06] + sevenZipNumber(packedPosition) + sevenZipNumber(1)
        out += [0x09] + sevenZipNumber(UInt64(packedSize)) + [0x00]
        out += [0x07, 0x0B] + sevenZipNumber(1) + [0x00] + sevenZipNumber(1) + coder
        out += [0x0C] + sevenZipNumber(unpackSize)
        if let crc { out += [0x0A, 0x01] + le(UInt64(crc), 4) }
        return out + [0x00, 0x00]
    }
    static func lzmaCoder(dictionary: UInt32, properties: UInt8 = 0x5D) -> [UInt8] {
        [0x23, 0x03, 0x01, 0x01, 0x05, properties] + le(UInt64(dictionary), 4)
    }
    static func lzma2Coder(property: UInt8) -> [UInt8] { [0x21, 0x21, 0x01, property] }
}

/// Archive tests keep their local name while sharing the bounded, thread-safe read recorder.
typealias RecordingSource = RecordingByteSource
