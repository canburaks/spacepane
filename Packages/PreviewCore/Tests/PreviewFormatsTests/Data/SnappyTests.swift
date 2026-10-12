import Foundation
import zlib
import Testing
import PreviewContracts
@testable import PreviewFormats

/// A literal-only Snappy encoder, enough to build valid blocks independently of the decoder.
enum SnappyTestWriter {
    static func literalBlock(_ data: [UInt8]) -> [UInt8] {
        var out = Self.varint(data.count)
        var index = 0
        while index < data.count {
            let run = min(60, data.count - index)
            out.append(UInt8((run - 1) << 2))
            out += data[index..<(index + run)]
            index += run
        }
        return out
    }

    static func varint(_ value: Int) -> [UInt8] {
        var rest = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            out.append(byte)
        } while rest != 0
        return out
    }

    /// Avro's framing: the block followed by a big-endian CRC-32 of the uncompressed bytes.
    static func avroBlock(_ data: [UInt8]) -> [UInt8] {
        let crc = data.withUnsafeBufferPointer { UInt32(zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
        return literalBlock(data) + (0..<4).reversed().map { UInt8(truncatingIfNeeded: crc >> ($0 * 8)) }
    }
}

@Suite("Snappy decoder")
struct SnappyDecoderTests {
    private func decode(_ bytes: [UInt8], maximum: Int = 1_000_000) throws -> [UInt8] {
        try SnappyDecoder.decode(bytes, maximum: maximum, context: DataTest.context())
    }

    @Test func literalsAndEveryCopyKindDecode() throws {
        #expect(try decode([0x00]) == [])
        #expect(try decode([0x05, 0x10, 0x68, 0x65, 0x6C, 0x6C, 0x6F]) == Array("hello".utf8))
        // "abc" then a 2-byte-offset copy of 9 bytes at distance 3: overlapping, so it repeats.
        #expect(try decode([12, 0x08] + Array("abc".utf8) + [0x22, 3, 0]) == Array("abcabcabcabc".utf8))
        // One-byte-offset copy: "abcd" then 4 bytes back 4.
        #expect(try decode([8, 0x0C] + Array("abcd".utf8) + [0x01, 4]) == Array("abcdabcd".utf8))
        // Four-byte-offset copy.
        #expect(try decode([6, 0x04] + Array("xy".utf8) + [0x0F, 2, 0, 0, 0]) == Array("xyxyxy".utf8))
        // A long literal whose length is in the following byte.
        let hundred = [UInt8](repeating: 0x41, count: 100)
        #expect(try decode([100, 0xF0, 99] + hundred) == hundred)
        // Two-byte literal length.
        let long = [UInt8](repeating: 0x42, count: 300)
        #expect(try decode(SnappyTestWriter.varint(300) + [0xF4, 0x2B, 0x01] + long) == long)
        #expect(try decode(SnappyTestWriter.literalBlock(Array("round trip".utf8))) == Array("round trip".utf8))
    }

    @Test func invalidBlocksAreMalformedNotGuessed() {
        let cases: [(String, [UInt8])] = [
            ("empty", []),
            ("truncated length", [0x80]),
            ("overlong length", [0x80, 0x80, 0x80, 0x80, 0x80, 0x01]),
            ("literal past the input", [5, 0x10, 0x68]),
            ("literal past the declared length", [2, 0x10, 0x68, 0x65, 0x6C]),
            ("copy at distance zero", [8, 0x0C] + Array("abcd".utf8) + [0x01, 0]),
            ("copy before the beginning", [8, 0x0C] + Array("abcd".utf8) + [0x01, 9]),
            ("copy past the declared length", [6, 0x0C] + Array("abcd".utf8) + [0x01, 4]),
            ("truncated copy offset", [8, 0x0C] + Array("abcd".utf8) + [0x02, 4]),
            ("missing elements", [8, 0x0C] + Array("abcd".utf8)),
            ("trailing bytes", [1, 0x00, 0x41, 0x99]),
            ("literal length bytes cut", [0xFF, 0x7F, 0xF4, 0x01])
        ]
        for (name, bytes) in cases {
            #expect(throws: PreviewFailure.malformedDocument, "\(name)") { try decode(bytes) }
        }
    }

    @Test func theDeclaredLengthIsCheckedBeforeAnythingIsAllocated() {
        // Declares 2 GiB and carries three bytes.
        let declared = SnappyTestWriter.varint(2_147_483_647) + [0x00, 0x41]
        #expect(throws: PreviewFailure.outputTooLarge) { try decode(declared, maximum: 1_000) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode(declared, maximum: Int.max) }
    }

    @Test func randomBytesNeverCrashTheDecoder() {
        var seed: UInt64 = 0xC0FFEE
        for _ in 0..<2_000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let count = Int(seed >> 59)
            var bytes: [UInt8] = []
            for _ in 0..<count { seed = seed &* 6364136223846793005 &+ 1442695040888963407; bytes.append(UInt8(truncatingIfNeeded: seed >> 33)) }
            DataTest.expectBounded("random") { _ = try SnappyDecoder.decode(bytes, maximum: 100_000, context: DataTest.context()) }
        }
    }

    @Test func cancellationAndDeadlineAreHonored() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try SnappyDecoder.decode([0x00], maximum: 10, context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try SnappyDecoder.decode([0x00], maximum: 10, context: DataTest.context()); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}

@Suite("Avro snappy codec")
struct AvroSnappyTests {
    private let schema = #"{"type":"record","name":"R","fields":[{"name":"n","type":"long"},{"name":"s","type":"string"}]}"#

    private func container(_ block: [UInt8], count: Int) -> Data {
        AvroWriter.container(schema: schema, codec: "snappy", blocks: [(count: count, payload: block)])
    }

    private func records() -> [UInt8] {
        (0..<3).flatMap { AvroWriter.long(Int64($0)) + AvroWriter.string("value \($0)") }
    }

    @Test func snappyBlocksDecodeLikeNullBlocks() throws {
        let object = try DataTest.object(try DataTest.parse(AvroAdapter(), container(SnappyTestWriter.avroBlock(records()), count: 3)))
        #expect(object["codec"] as? String == "snappy")
        #expect(try DataTest.rows(object) == [["0", "value 0"], ["1", "value 1"], ["2", "value 2"]])
    }

    @Test func aWrongChecksumOrABrokenBlockIsRejected() throws {
        var block = SnappyTestWriter.avroBlock(records())
        block[block.count - 1] ^= 0x01
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), container(block, count: 3)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), container([1, 2], count: 3)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), container([], count: 3)) }
    }

    @Test func aSnappyBombFailsClosed() throws {
        // Declares 1 GiB in a few bytes; the codec's output limit rejects it before allocation.
        let bomb = SnappyTestWriter.varint(1_073_741_824) + [0x00, 0x41, 0, 0, 0, 0]
        #expect(throws: PreviewFailure.self) { try DataTest.parse(AvroAdapter(), container(bomb, count: 1)) }
    }
}
