import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// A tiny Thrift compact writer, independent of the reader under test.
private enum Thrift {
    static func varint(_ value: UInt64) -> [UInt8] {
        var out: [UInt8] = []
        var rest = value
        repeat {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            out.append(byte)
        } while rest != 0
        return out
    }
    static func zigzag(_ value: Int64) -> [UInt8] { varint(UInt64(bitPattern: (value << 1) ^ (value >> 63))) }
    static func string(_ text: String) -> [UInt8] { varint(UInt64(text.utf8.count)) + Array(text.utf8) }
    /// Field header with a short delta.
    static func field(_ delta: UInt8, type: UInt8) -> [UInt8] { [delta << 4 | type] }
    static let stop: [UInt8] = [0]
}

private func reader(_ bytes: [UInt8], budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) -> ThriftCompactReader {
    ThriftCompactReader(bytes: bytes, context: RequestContext(budget: budget))
}

@Suite("Thrift compact reader")
struct ThriftCompactReaderTests {
    @Test func varintsDecodeAndRejectOverlongOrTruncatedEncodings() throws {
        var value = reader([0xAC, 0x02])
        #expect(try value.varint() == 300)
        var maximum = reader([UInt8](repeating: 0xFF, count: 9) + [0x01])
        #expect(try maximum.varint() == UInt64.max)
        var overflow = reader([UInt8](repeating: 0xFF, count: 9) + [0x02])
        #expect(throws: PreviewFailure.malformedDocument) { try overflow.varint() }
        var endless = reader([UInt8](repeating: 0x80, count: 11))
        #expect(throws: PreviewFailure.malformedDocument) { try endless.varint() }
        var truncated = reader([0x80])
        #expect(throws: PreviewFailure.malformedDocument) { try truncated.varint() }
    }

    @Test func zigzagIntegersAreSignedAndRangeChecked() throws {
        var values = reader([0x00, 0x01, 0x02, 0x03, 0xFE, 0xFF, 0xFF, 0xFF, 0x0F])
        #expect(try values.zigzag32() == 0)
        #expect(try values.zigzag32() == -1)
        #expect(try values.zigzag32() == 1)
        #expect(try values.zigzag32() == -2)
        #expect(try values.zigzag32() == Int32.max)
        // 2^32 does not fit a 32-bit field.
        var wide = reader(Thrift.zigzag(Int64(Int32.max) + 1))
        #expect(throws: PreviewFailure.malformedDocument) { try wide.zigzag32() }
        var wide64 = reader(Thrift.zigzag(Int64(Int32.max) + 1))
        #expect(try wide64.zigzag64() == Int64(Int32.max) + 1)
    }

    @Test func fieldsUseShortDeltasLongFormIdentifiersAndBooleanTypeNibbles() throws {
        // id 1 i32 = 5; id 3 bool true; long-form id 100 string "ab"; stop.
        let bytes: [UInt8] = Thrift.field(1, type: 5) + Thrift.zigzag(5)
            + Thrift.field(2, type: 1)
            + [0x08] + Thrift.zigzag(100) + Thrift.string("ab") + Thrift.stop
        var parser = reader(bytes)
        var seen: [String] = []
        try parser.structure(depth: 1) { id, type, reader in
            switch (id, type) {
            case (1, .i32): seen.append("i32=\(try reader.zigzag32())")
            case (3, .booleanTrue): seen.append("true")
            case (100, .binary): seen.append("string=\(try reader.string())")
            default: return false
            }
            return true
        }
        #expect(seen == ["i32=5", "true", "string=ab"])
        #expect(parser.remaining == 0)
    }

    @Test func unknownFieldsAreSkippedIncludingListsMapsAndNestedStructures() throws {
        var bytes: [UInt8] = []
        // 1: list<struct> with two one-field structs
        bytes += Thrift.field(1, type: 9) + [0x2C]
        bytes += Thrift.field(1, type: 5) + Thrift.zigzag(7) + Thrift.stop
        bytes += Thrift.field(1, type: 5) + Thrift.zigzag(8) + Thrift.stop
        // 2: map<i32, binary> with one entry
        bytes += Thrift.field(1, type: 11) + [0x01, 0x58] + Thrift.zigzag(9) + Thrift.string("v")
        // 3: list<bool> of three, one byte each
        bytes += Thrift.field(1, type: 9) + [0x31, 0x01, 0x02, 0x01]
        // 4: double
        bytes += Thrift.field(1, type: 7) + [UInt8](repeating: 0, count: 8)
        // 5: i64 that is read
        bytes += Thrift.field(1, type: 6) + Thrift.zigzag(-42) + Thrift.stop
        var parser = reader(bytes)
        var value: Int64?
        try parser.structure(depth: 1) { id, type, reader in
            guard id == 5, type == .i64 else { return false }
            value = try reader.zigzag64()
            return true
        }
        #expect(value == -42)
        #expect(parser.remaining == 0)
    }

    @Test func lengthsBeyondTheInputAreRejectedBeforeAllocation() throws {
        var binary = reader(Thrift.varint(1_000_000) + [1, 2, 3])
        #expect(throws: PreviewFailure.malformedDocument) { try binary.binary(maximumBytes: 10) }
        // A list that claims more elements than there are bytes left.
        var list = reader([0xF5] + Thrift.varint(1_000_000) + [0])
        #expect(throws: PreviewFailure.malformedDocument) { try list.listHeader() }
        var map = reader(Thrift.varint(500_000) + [0x55])
        #expect(throws: PreviewFailure.malformedDocument) { try map.skip(.map, depth: 1, inCollection: false) }
        // The cap on retained bytes still consumes the whole value.
        var clipped = reader(Thrift.string("abcdefghij") + [0xEE])
        let (kept, wasClipped) = try clipped.binary(maximumBytes: 4)
        #expect(Array(kept) == Array("abcd".utf8) && wasClipped && clipped.remaining == 1)
    }

    @Test func nestingBeyondTheLimitFailsClosed() throws {
        // Each header opens a struct field (type 12) inside the previous one.
        let bytes = [UInt8](repeating: 0x1C, count: 64) + [UInt8](repeating: 0, count: 65)
        var parser = reader(bytes)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try parser.structure(depth: 1) { _, _, _ in false }
        }
    }

    @Test func truncatedStructuresAndReservedTypesAreMalformed() throws {
        var cut = reader(Thrift.field(1, type: 5))
        #expect(throws: PreviewFailure.malformedDocument) { try cut.structure(depth: 1) { _, _, _ in false } }
        var reserved = reader([0x1D, 0x00])
        #expect(throws: PreviewFailure.malformedDocument) { try reserved.structure(depth: 1) { _, _, _ in false } }
        var stopInField = reader([0x10, 0x00])
        #expect(throws: PreviewFailure.malformedDocument) { try stopInField.structure(depth: 1) { _, _, _ in false } }
    }

    @Test func anExpiredDeadlineStopsASkipThroughLargeValues() {
        let bytes = Thrift.field(1, type: 8) + Thrift.varint(2_500) + [UInt8](repeating: 0x41, count: 2_500) + Thrift.stop
        var parser = ThriftCompactReader(bytes: bytes, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 0)))
        #expect(throws: PreviewFailure.deadlineExceeded) { try parser.structure(depth: 1) { _, _, _ in false } }
    }
}

@Suite("Parquet adapter")
struct ParquetAdapterTests {
    @Test func footerBecomesSummaryAndFlattenedSchemaTable() throws {
        let document = try DataTest.parse(ParquetAdapter(), DataFixtures.parquet)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "Parquet")
        #expect(object["formatVersion"] as? Int == 2)
        #expect(object["rowCount"] as? Int == 3)
        #expect(object["rowGroupCount"] as? Int == 1)
        #expect(object["columnCount"] as? Int == 4)
        #expect(object["createdBy"] as? String == "synthetic-writer version 1.0")
        #expect(document.syntax == .json && document.usesStructuredPrivacy)

        let table = try DataTest.table(object)
        #expect(table.columns == ["name", "repetition", "physicalType", "convertedType", "logicalType"])
        let rows = table.rows.map { $0.map(DataTest.cell) }
        #expect(rows.map { $0[0] } == ["id", "name", "amount", "address", "address.city"])
        #expect(rows[0] == ["id", "REQUIRED", "INT64", "", ""])
        #expect(rows[1] == ["name", "OPTIONAL", "BYTE_ARRAY", "UTF8", "STRING"])
        #expect(rows[2] == ["amount", "OPTIONAL", "FIXED_LEN_BYTE_ARRAY(16)", "DECIMAL", "DECIMAL(18, 2)"])
        #expect(rows[3] == ["address", "OPTIONAL", "", "", ""])
        #expect(rows[4][2] == "BYTE_ARRAY")
    }

    @Test func rowGroupsAndColumnChunksCarryCodecEncodingsSizesAndNullCounts() throws {
        let object = try DataTest.object(try DataTest.parse(ParquetAdapter(), DataFixtures.parquet))
        let groups = try #require(object["rowGroups"] as? [[String: Any]])
        #expect(groups.count == 1)
        #expect(groups[0]["rows"] as? Int == 3)
        #expect(groups[0]["uncompressedBytes"] as? Int == 275)
        #expect(groups[0]["compressedBytes"] as? Int == 190)
        let chunks = try #require(groups[0]["columnChunks"] as? [[String: Any]])
        #expect(chunks.map { $0["path"] as? String } == ["id", "name", "amount", "address.city"])
        #expect(chunks[0]["codec"] as? String == "SNAPPY")
        #expect(chunks[2]["codec"] as? String == "ZSTD")
        #expect(chunks[0]["encodings"] as? [String] == ["PLAIN", "RLE"])
        #expect(chunks[1]["nullCount"] as? Int == 1)
        #expect(chunks[3]["nullCount"] as? Int == 2)
        #expect(chunks[0]["valueCount"] as? Int == 3)
    }

    @Test func keyValueMetadataKeepsKeysAndConcealsValuesOfSecretKeys() throws {
        let document = try DataTest.parse(ParquetAdapter(), DataFixtures.parquet)
        let object = try DataTest.object(document)
        let metadata = try #require(object["metadata"] as? [[String: Any]])
        #expect(metadata.map { $0["key"] as? String } == ["writer.note", "password"])
        // The adapter marks the secret value; the shared filter replaces it (see the pipeline tests).
        #expect(document.sensitiveRanges.count >= 1)
        let secret = Array(DataFixtures.secret.utf8)
        let text = Array(document.text.utf8)
        let range = try #require(document.sensitiveRanges.first?.utf8Range)
        #expect(Array(text[range]) == secret)
    }

    @Test func theHeadTailAndFooterAreReadFirstAndOnlySmallPageWindowsFollow() throws {
        let source = DataRecordingSource(DataFixtures.parquet)
        _ = try ParquetAdapter().parse(source, context: DataTest.context())
        let size = DataFixtures.parquet.count
        #expect(source.reads[0] == 0..<4)
        #expect(source.reads[1] == (size - 8)..<size)
        #expect(source.reads[2].upperBound == size - 8)
        // Row sampling then asks only for the start of each column chunk, never past its recorded size
        // and never into the footer; this file's chunks are a few dozen bytes.
        let footerStart = source.reads[2].lowerBound
        for read in source.reads.dropFirst(3) {
            #expect(read.lowerBound >= 4 && read.upperBound <= footerStart && read.count <= 2_048)
        }
        #expect(source.reads.map(\.count).reduce(0, +) < 1_024)
    }

    @Test func hostileBytesBeforeTheFooterNeverEndTheSummary() throws {
        var data = DataFixtures.parquet
        for index in 4..<12 { data[index] = 0xFF }
        #expect(try DataTest.parse(ParquetAdapter(), data).text.contains("Parquet"))
    }

    @Test func encryptedFootersFailAsEncryptedContent() throws {
        var data = DataFixtures.parquet
        data.replaceSubrange((data.count - 4)..<data.count, with: Data("PARE".utf8))
        #expect(throws: PreviewFailure.encryptedContent) { try DataTest.parse(ParquetAdapter(), data) }
        var head = DataFixtures.parquet
        head.replaceSubrange(0..<4, with: Data("PARE".utf8))
        #expect(throws: PreviewFailure.encryptedContent) { try DataTest.parse(ParquetAdapter(), head) }
    }

    @Test func invalidEnvelopesAreMalformed() throws {
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), Data("PAR1PAR1".utf8)) }
        var data = DataFixtures.parquet
        data[0] = 0x58
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), data) }
        // A footer length larger than the file.
        var oversized = DataFixtures.parquet
        oversized.replaceSubrange((oversized.count - 8)..<(oversized.count - 4), with: Data([0xFF, 0xFF, 0xFF, 0x7F]))
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), oversized) }
        // A zero-length footer.
        var empty = DataFixtures.parquet
        empty.replaceSubrange((empty.count - 8)..<(empty.count - 4), with: Data(repeating: 0, count: 4))
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), empty) }
    }

    @Test func aFooterBeyondTheInputBudgetFailsBeforeItIsRead() throws {
        let source = DataRecordingSource(DataFixtures.parquet)
        let budget = PreviewBudget(maxInputBytes: 64, maxMilliseconds: 30_000)
        #expect(throws: PreviewFailure.inputTooLarge) { try ParquetAdapter().parse(source, context: DataTest.context(budget)) }
        #expect(source.reads.count == 2)
    }

    @Test func everyTruncationAndSingleByteCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.parquet
        for length in 0..<data.count {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(ParquetAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 12, to: data.count - 8, by: 1) {
            var changed = data
            changed[index] ^= 0xA5
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(ParquetAdapter(), changed) }
        }
    }

    @Test func aFooterClaimingAMillionSchemaElementsIsCorruptNotHuge() throws {
        // FileMetaData: version, then field 2 as a list of one million structs in a few bytes.
        let footer: [UInt8] = Thrift.field(1, type: 5) + Thrift.zigzag(1)
            + Thrift.field(1, type: 9) + [0xFC] + Thrift.varint(1_000_000) + Thrift.stop
        var file = Data("PAR1".utf8) + Data(footer)
        file += DataTest.little(UInt64(footer.count), width: 4) + Data("PAR1".utf8)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ParquetAdapter(), file) }
    }

    @Test func wideSchemasAreCutAndFlaggedWithinTheTableLimit() throws {
        let leafCount = 5_000
        // The root names itself and declares its children (field 5); then N required INT32 leaves.
        var schema: [UInt8] = Thrift.field(4, type: 8) + Thrift.string("schema")
            + Thrift.field(1, type: 5) + Thrift.zigzag(Int64(leafCount)) + Thrift.stop
        for index in 0..<leafCount {
            schema += Thrift.field(1, type: 5) + Thrift.zigzag(1) + Thrift.field(2, type: 5) + Thrift.zigzag(1)
                + Thrift.field(1, type: 8) + Thrift.string("c\(index)") + Thrift.stop
        }
        let footer: [UInt8] = Thrift.field(1, type: 5) + Thrift.zigzag(1)
            + Thrift.field(1, type: 9) + [0xFC] + Thrift.varint(UInt64(leafCount + 1)) + schema
            + Thrift.field(1, type: 6) + Thrift.zigzag(10)
            + Thrift.field(1, type: 9) + [0x0C] + Thrift.stop
        var file = Data("PAR1".utf8) + Data(footer)
        file += DataTest.little(UInt64(footer.count), width: 4) + Data("PAR1".utf8)
        let document = try DataTest.parse(ParquetAdapter(), file, budget: PreviewBudget(maxInputBytes: 1_048_576, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        let table = try DataTest.table(object)
        #expect(table.rows.count == 500)
        #expect(table.truncated)
        #expect(object["columnCount"] as? Int == leafCount)
        #expect(document.text.utf16.count < 250_000)
        #expect(DataTest.nodeCount(object) < 18_000)
    }

    @Test func cancellationAndExpiredDeadlinePrecedeAnySourceRead() async {
        let source = DataRecordingSource(DataFixtures.parquet)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? ParquetAdapter().parse(source, context: DataTest.context())
        }
        await task.value
        #expect(source.reads.isEmpty)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try ParquetAdapter().parse(source, context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        #expect(source.reads.isEmpty)
    }
}
