import CryptoKit
import Foundation
import PreviewContracts

/// Facts the xz preflight reads from the stream index and block headers before any decoding.
struct XZStreamInfo {
    struct Block {
        /// Offset of the block header from the start of the file.
        let offset: Int
        let headerSize: Int
        /// Header, compressed data and check, without the block padding.
        let unpaddedSize: Int
        let uncompressedSize: UInt64
        /// The single LZMA2 filter's dictionary-size property byte.
        let dictionaryProperty: UInt8
    }
    var blocks: [Block] = []
    /// True when a block declares a dictionary larger than the system decoder is allowed to allocate.
    var needsBoundedDecoder: Bool { blocks.contains { $0.dictionaryProperty > XZPreflight.systemDecoderDictionaryProperty } }
}

extension ArchiveByteReader {
    /// xz variable-length integer: seven bits per byte, least significant first, at most nine bytes,
    /// with no redundant trailing zero group.
    mutating func xzVariableInteger() throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<9 {
            let byte = try self.byte()
            value |= UInt64(byte & 0x7F) << UInt64(index * 7)
            if byte & 0x80 == 0 {
                guard index == 0 || byte != 0 else { throw PreviewFailure.malformedDocument }
                return value
            }
        }
        throw PreviewFailure.malformedDocument
    }
}

/// Decodes xz streams with this package's bounded LZMA2 decoder. It is used for streams that declare
/// a dictionary above the 8 MiB the system decoder may allocate, such as `xz -9`, whose header records
/// 64 MiB even for tiny inputs. Memory follows the declared output size, which the index states and
/// the request budget bounds; the dictionary only limits how far back a match may reach. Dictionaries
/// above 64 MiB are still declined. Block checks (CRC32, CRC64, SHA-256) and every header CRC are verified.
enum XZBoundedDecoder {
    /// LZMA2 property 28: 64 MiB.
    static let maximumDictionaryProperty: UInt8 = 28
    private static let checkSizes: [Int: Int] = [0: 0, 1: 4, 4: 8, 10: 32]

    static func decode(_ data: Data, info: XZStreamInfo, context: RequestContext, maximum: Int) throws -> Data {
        try context.checkpoint()
        let bytes = [UInt8](data)
        guard bytes.count >= 32, bytes[6] == 0, bytes[7] & 0xF0 == 0 else { throw PreviewFailure.unsupportedFormat }
        guard let checkSize = checkSizes[Int(bytes[7] & 0x0F)] else { throw PreviewFailure.unsupportedFormat }
        let checkType = Int(bytes[7] & 0x0F)
        guard ArchiveCRC32.checksum(bytes[6..<8]) == littleEndian32(bytes, 8),
              ArchiveCRC32.checksum(bytes[(bytes.count - 8)..<(bytes.count - 2)]) == littleEndian32(bytes, bytes.count - 12),
              Array(bytes[(bytes.count - 4)..<(bytes.count - 2)]) == Array(bytes[6..<8]) else {
            throw PreviewFailure.malformedDocument
        }
        // The index states every block's output size, so the total is checked before any allocation.
        var total: UInt64 = 0
        for block in info.blocks {
            guard block.dictionaryProperty <= maximumDictionaryProperty else { throw PreviewFailure.inputTooLarge }
            let (sum, overflow) = total.addingReportingOverflow(block.uncompressedSize)
            guard !overflow, sum <= UInt64(maximum) else { throw PreviewFailure.outputTooLarge }
            total = sum
        }
        var output = Data()
        output.reserveCapacity(Int(total))
        let limits = LZMALimits(maximumOutputBytes: maximum)
        for block in info.blocks {
            try context.checkpoint()
            var header = ArchiveByteReader(bytes, position: block.offset, end: block.offset + block.headerSize)
            guard ArchiveCRC32.checksum(bytes[block.offset..<(block.offset + block.headerSize - 4)])
                    == littleEndian32(bytes, block.offset + block.headerSize - 4) else { throw PreviewFailure.malformedDocument }
            _ = try header.byte() // size byte, already read by the preflight
            let flags = try header.byte()
            var storedCompressed: UInt64?
            var storedUncompressed: UInt64?
            if flags & 0x40 != 0 { storedCompressed = try header.xzVariableInteger() }
            if flags & 0x80 != 0 { storedUncompressed = try header.xzVariableInteger() }
            _ = try header.xzVariableInteger() // filter identifier: LZMA2, checked by the preflight
            _ = try header.xzVariableInteger() // property size: one byte
            _ = try header.byte()
            while header.remaining > 4 { guard try header.byte() == 0 else { throw PreviewFailure.malformedDocument } }
            let compressedSize = block.unpaddedSize - block.headerSize - checkSize
            guard compressedSize >= 0, storedCompressed.map({ $0 == UInt64(compressedSize) }) ?? true,
                  storedUncompressed.map({ $0 == block.uncompressedSize }) ?? true else { throw PreviewFailure.malformedDocument }
            let dataStart = block.offset + block.headerSize
            let padding = (4 - (block.unpaddedSize & 3)) & 3
            guard dataStart + compressedSize + padding + checkSize <= bytes.count - 12 else { throw PreviewFailure.malformedDocument }
            guard bytes[(dataStart + compressedSize)..<(dataStart + compressedSize + padding)].allSatisfy({ $0 == 0 }) else {
                throw PreviewFailure.malformedDocument
            }
            let decoded = try LZMA2Decoder.decode(Array(bytes[dataStart..<(dataStart + compressedSize)]),
                                                  dictionaryProperty: block.dictionaryProperty,
                                                  outputSize: Int(block.uncompressedSize), limits: limits, context: context)
            let checkStart = dataStart + compressedSize + padding
            try verify(decoded, check: bytes[checkStart..<(checkStart + checkSize)], type: checkType, context: context)
            output.append(contentsOf: decoded)
        }
        return output
    }

    private static func littleEndian32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func verify(_ decoded: [UInt8], check: ArraySlice<UInt8>, type: Int, context: RequestContext) throws {
        switch type {
        case 0: return
        case 1:
            guard ArchiveCRC32.checksum(decoded) == littleEndian32(Array(check), 0) else { throw PreviewFailure.malformedDocument }
        case 4:
            let stored = check.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard try XZCRC64.checksum(decoded, context: context) == stored else { throw PreviewFailure.malformedDocument }
        default:
            guard Array(SHA256.hash(data: decoded)) == Array(check) else { throw PreviewFailure.malformedDocument }
        }
    }
}

/// CRC-64/XZ: the ECMA-182 polynomial, reflected, with all-ones initial value and final inversion.
enum XZCRC64 {
    private static let table: [UInt64] = (0..<256).map { value in
        var crc = UInt64(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xC96C_5795_D787_0F42 : crc >> 1 }
        return crc
    }

    static func checksum(_ bytes: [UInt8], context: RequestContext) throws -> UInt64 {
        var crc = ~UInt64(0)
        var index = 0
        while index < bytes.count {
            try context.checkpoint()
            let end = min(bytes.count, index + 1 << 20)
            while index < end {
                crc = table[Int((crc ^ UInt64(bytes[index])) & 0xFF)] ^ (crc >> 8)
                index += 1
            }
        }
        return ~crc
    }
}
