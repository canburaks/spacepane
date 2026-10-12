import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("FlatBuffers reader")
struct FlatBuffersReaderTests {
    private func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    private func u16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }

    /// A hand-built buffer: root offset, a vtable for one i32 slot, and the table.
    private func tinyTable(value: Int32) -> FlatBuffer {
        var bytes = u32(12)                     // root offset to the table at 12
        bytes += u16(6) + u16(8) + u16(4)      // vtable (length 6: header + one slot), table length 8, slot 0 at +4
        bytes += [0, 0]
        bytes += u32(UInt32(12 - 4)) + u32(UInt32(bitPattern: value))
        return FlatBuffer(bytes)
    }

    @Test func aHandBuiltTableReadsItsFieldAndDefaultsMissingSlots() throws {
        let table = try tinyTable(value: -7).rootTable()
        #expect(try table.int32(0) == -7)
        #expect(try table.int32(1, default: 9) == 9)
        #expect(try table.bool(5) == false)
        #expect(try table.table(2) == nil)
        #expect(try table.string(3) == nil)
    }

    @Test func offsetsOutsideTheBufferAreMalformed() throws {
        #expect(throws: PreviewFailure.malformedDocument) { try FlatBuffer(u32(100) + [0, 0, 0, 0]).rootTable() }
        #expect(throws: PreviewFailure.malformedDocument) { try FlatBuffer([]).rootTable() }
        // A table whose signed offset points before the buffer.
        #expect(throws: PreviewFailure.malformedDocument) { try FlatBuffer(u32(4) + u32(UInt32(bitPattern: 1_000))).rootTable() }
        // A vtable with an odd or tiny length.
        #expect(throws: PreviewFailure.malformedDocument) {
            try FlatBuffer(u32(12) + u16(3) + u16(0) + [0, 0, 0, 0] + u32(8)).rootTable()
        }
        // A vtable that runs past the end.
        #expect(throws: PreviewFailure.malformedDocument) {
            try FlatBuffer(u32(12) + u16(200) + u16(0) + [0, 0, 0, 0] + u32(8)).rootTable()
        }
    }

    @Test func stringsAndVectorsAreBoundsChecked() throws {
        // Table with slot 0 = string offset whose length claims more than the buffer holds.
        var bytes = u32(12) + u16(6) + u16(8) + u16(4) + [0, 0]
        bytes += u32(8) + u32(8)                 // table at 12: soffset, field at +4 -> uoffset 8 -> position 24
        bytes += u32(0xFFFF_FFFF) + [0x41]       // string length, one byte
        let table = try FlatBuffer(bytes).rootTable()
        #expect(throws: PreviewFailure.malformedDocument) { try table.string(0) }
        #expect(throws: PreviewFailure.malformedDocument) { try table.vector(0, elementSize: 4) }
    }
}

@Suite("Arrow adapter")
struct ArrowAdapterTests {
    private let expectedRows: [[String]] = [
        ["id", "int64", "false"], ["name", "utf8", "true"], ["seen", "timestamp[us, tz=UTC]", "true"],
        ["items", "list", "true"], ["items.item", "float32", "true"],
        ["color", "dictionary<values=utf8, indices=int8>", "true"]
    ]

    @Test func fileFooterGivesSchemaBatchesAndMetadata() throws {
        let document = try DataTest.parse(ArrowAdapter(), DataFixtures.arrowFile)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "Arrow IPC file")
        #expect(object["formatVersion"] as? String == "V5")
        #expect(object["columnCount"] as? Int == 5)
        #expect(object["rowCount"] as? Int == 7)
        #expect(object["recordBatchCount"] as? Int == 2)
        #expect(object["dictionaryCount"] as? Int == 0)
        #expect(object["partial"] == nil)
        let table = try DataTest.table(object)
        #expect(table.columns == ["name", "type", "nullable"])
        #expect(table.rows.map { $0.map(DataTest.cell) } == expectedRows)
        let metadata = try #require(object["metadata"] as? [[String: Any]])
        #expect(metadata.first?["key"] as? String == "api_key")
        #expect(document.sensitiveRanges.count == 1)
        let text = Array(document.text.utf8)
        #expect(String(decoding: text[document.sensitiveRanges[0].utf8Range], as: UTF8.self) == DataFixtures.secret)
    }

    @Test func streamsAreScannedMessageByMessage() throws {
        let object = try DataTest.object(try DataTest.parse(ArrowAdapter(), DataFixtures.arrowStream))
        #expect(object["dataFormat"] as? String == "Arrow IPC stream")
        #expect(object["rowCount"] as? Int == 7 && object["recordBatchCount"] as? Int == 2)
        #expect(try DataTest.rows(object) == expectedRows)
    }

    @Test func manyBatchesAreCountedButOnlyTheFirstSixtyFourAreMeasured() throws {
        let source = DataRecordingSource(DataFixtures.arrowManyBatches)
        let object = try DataTest.object(try ArrowAdapter().parse(source, context: DataTest.context()))
        #expect(object["recordBatchCount"] as? Int == 70)
        #expect(object["rowCount"] as? Int == 64)
        #expect(object["partial"] as? Bool == true)
        #expect(source.reads.count == 2 + 1 + 64)
    }

    @Test func aLongStreamIsScannedWithinALimitAndFlaggedPartial() throws {
        // Repeat the first record-batch message; walk the stream's own framing to find it.
        let stream = DataFixtures.arrowStream
        func message(at offset: Int) -> Range<Int> {
            let length = stream[(offset + 4)..<(offset + 8)].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
            return offset..<(offset + 8 + length)
        }
        let schema = message(at: 0)
        let batch = message(at: schema.upperBound)
        var long = stream[schema]
        for _ in 0..<1_100 { long += stream[batch] }
        long += Data([0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0])
        let object = try DataTest.object(try DataTest.parse(ArrowAdapter(), long))
        #expect(object["partial"] as? Bool == true)
        #expect((object["recordBatchCount"] as? Int ?? 0) < 1_100)
    }

    @Test func featherV1AndOtherNonArrowInputIsRefused() throws {
        #expect(throws: PreviewFailure.unsupportedFormat) { try DataTest.parse(ArrowAdapter(), Data("FEA1".utf8) + Data(count: 64)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), Data("ARROW1".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), Data(count: 200)) }
        // A stream length prefix far beyond the metadata limit.
        let huge = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]) + Data(count: 64)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), huge) }
    }

    @Test func fileEnvelopesAreValidatedBeforeTheFooterIsTrusted() throws {
        var data = DataFixtures.arrowFile
        data[data.count - 1] = 0x00
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), data) }
        var oversized = DataFixtures.arrowFile
        oversized.replaceSubrange((oversized.count - 10)..<(oversized.count - 6), with: Data([0xFF, 0xFF, 0xFF, 0x7F]))
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), oversized) }
        let budget = PreviewBudget(maxInputBytes: 64, maxMilliseconds: 30_000)
        #expect(throws: PreviewFailure.inputTooLarge) { try DataTest.parse(ArrowAdapter(), DataFixtures.arrowFile, budget: budget) }
    }

    @Test func aStreamNeedsExactlyOneLeadingSchema() throws {
        // Record batch first.
        let stream = DataFixtures.arrowStream
        let schemaLength = stream[4..<8].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) } + 8
        let batchOnly = stream.subdata(in: schemaLength..<stream.count)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), batchOnly) }
        // Schema twice.
        let twice = stream.prefix(schemaLength) + stream
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), twice) }
    }

    @Test func sharedSubtreesCannotMultiplyIntoAHugeWalk() throws {
        // 4**14 field visits without a budget; the decoder stops at its field limit.
        #expect(throws: PreviewFailure.tooManyNodes) { try DataTest.parse(ArrowAdapter(), DataFixtures.arrowSharing) }
        #expect(throws: PreviewFailure.structureTooDeep) { try DataTest.parse(ArrowAdapter(), DataFixtures.arrowDeep) }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        for data in [DataFixtures.arrowFile, DataFixtures.arrowStream] {
            for length in 0..<data.count {
                DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(ArrowAdapter(), data.prefix(length)) }
            }
            for index in 0..<data.count {
                var changed = data
                changed[index] ^= 0xA5
                DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(ArrowAdapter(), changed) }
                var maximal = data
                maximal[index] = 0xFF
                DataTest.expectBounded("max \(index)") { _ = try DataTest.parse(ArrowAdapter(), maximal) }
            }
        }
    }

    @Test func cancellationAndDeadlinePrecedeAnyRead() async {
        let source = DataRecordingSource(DataFixtures.arrowFile)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? ArrowAdapter().parse(source, context: DataTest.context())
        }
        await task.value
        #expect(source.reads.isEmpty)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try ArrowAdapter().parse(source, context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
    }
}
