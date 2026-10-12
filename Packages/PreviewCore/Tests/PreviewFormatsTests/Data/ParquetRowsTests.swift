import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func leaf(_ type: Int?, repetition: Int = 0, converted: Int? = nil, logical: String? = nil, scale: Int? = nil,
                  length: Int? = nil) -> ParquetLeaf {
    var element = ParquetFooter.SchemaElement()
    element.name = "c"
    element.physicalType = type
    element.repetition = repetition
    element.convertedType = converted
    element.logicalType = logical
    element.scale = scale
    element.typeLength = length
    return ParquetLeaf(path: ["c"], element: element, maximumDefinition: repetition == 1 ? 1 : 0, maximumRepetition: 0)
}

private func text(_ cell: DataCell) -> String {
    switch cell {
    case .text(let value): value
    case .null: "null"
    case .binary(let count): "bytes:\(count)"
    case .segments(let parts): parts.map(\.text).joined()
    }
}

@Suite("Parquet encodings")
struct ParquetEncodingTests {
    /// The hybrid encoding, written independently: one bit-packed run padded to a multiple of eight.
    private func packed(_ values: [Int], width: Int) -> [UInt8] {
        let padded = values + [Int](repeating: 0, count: (8 - values.count % 8) % 8)
        var bytes = [UInt8](repeating: 0, count: padded.count / 8 * width)
        for (index, value) in padded.enumerated() {
            for bit in 0..<width where value >> bit & 1 == 1 {
                let position = index * width + bit
                bytes[position / 8] |= UInt8(1 << (position % 8))
            }
        }
        return [UInt8((padded.count / 8) << 1 | 1)] + bytes
    }

    private func decode(_ bytes: [UInt8], width: Int, count: Int) throws -> [Int] {
        try ParquetHybrid.decode(bytes[...], bitWidth: width, count: count, context: DataTest.context())
    }

    @Test func bitPackedAndRepeatedRunsDecode() throws {
        for width in 1...12 {
            let values = (0..<37).map { ($0 * 7 + 3) % (1 << width) }
            #expect(try decode(packed(values, width: width), width: width, count: values.count) == values, "width \(width)")
        }
        // A repeated run: header 5 << 1, one value byte.
        #expect(try decode([10, 3], width: 2, count: 5) == [3, 3, 3, 3, 3])
        // Two-byte values for widths 9...16.
        #expect(try decode([6, 0x2C, 0x01], width: 9, count: 3) == [300, 300, 300])
        // Mixed runs, stopping after `count` values.
        #expect(try decode([4, 1, 3, 0b0000_0110], width: 1, count: 4) == [1, 1, 0, 1])
        // Only the first values are produced even when the run is longer.
        #expect(try decode([0xFE, 0xFF, 0x7F, 1], width: 1, count: 3) == [1, 1, 1])
        #expect(try decode([], width: 0, count: 0) == [])
    }

    @Test func malformedRunsAreRejected() {
        #expect(throws: PreviewFailure.malformedDocument) { try decode([], width: 1, count: 1) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode([0x80], width: 1, count: 1) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode([3, 0xFF], width: 8, count: 8) }   // 1 group needs 8 bytes
        #expect(throws: PreviewFailure.malformedDocument) { try decode([2], width: 1, count: 1) }       // repeated run missing its value
        #expect(throws: PreviewFailure.malformedDocument) { try decode([0, 0], width: 1, count: 1) }     // zero-length run
        #expect(throws: PreviewFailure.malformedDocument) { try decode([1, 0], width: 33, count: 1) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode([UInt8](repeating: 0x80, count: 8), width: 1, count: 1) }
    }

    @Test func bitWidthsForLevels() {
        #expect([0, 1, 2, 3, 4, 7, 8].map(ParquetHybrid.bitWidth(forMaximum:)) == [0, 1, 2, 2, 3, 3, 4])
    }

    @Test func plainValuesDecodeForEveryPhysicalType() throws {
        func raws(_ type: Int, _ bytes: [UInt8], count: Int, length: Int? = nil) throws -> [ParquetRaw] {
            try ParquetPlain.decode(type: type, typeLength: length, bytes[...], count: count, context: DataTest.context())
        }
        guard case .boolean(let a) = try raws(0, [0b0000_0101], count: 3)[2], a else { Issue.record("bool"); return }
        guard case .int32(let b) = try raws(1, [0xFE, 0xFF, 0xFF, 0xFF], count: 1)[0], b == -2 else { Issue.record("int32"); return }
        guard case .int64(let c) = try raws(2, [1, 0, 0, 0, 0, 0, 0, 0x80], count: 1)[0], c == Int64.min + 1 else { Issue.record("int64"); return }
        guard case .float(let d) = try raws(4, [0, 0, 0xC0, 0x3F], count: 1)[0], d == 1.5 else { Issue.record("float"); return }
        guard case .double(let e) = try raws(5, [0, 0, 0, 0, 0, 0, 0xF8, 0x3F], count: 1)[0], e == 1.5 else { Issue.record("double"); return }
        guard case .bytes(let prefix, let length) = try raws(6, [3, 0, 0, 0, 0x61, 0x62, 0x63, 1, 0, 0, 0, 0x7A], count: 2)[1],
              prefix == [0x7A], length == 1 else { Issue.record("bytes"); return }
        guard case .bytes(_, let fixed) = try raws(7, [1, 2, 3, 4], count: 2, length: 2)[1], fixed == 2 else { Issue.record("fixed"); return }
        let julianDay: [UInt8] = (0..<4).map { UInt8(truncatingIfNeeded: 2_461_042 >> ($0 * 8)) }
        guard case .int96(let day, let nanos) = try raws(3, [1, 0, 0, 0, 0, 0, 0, 0] + julianDay, count: 1)[0],
              nanos == 1, day == 2_461_042 else { Issue.record("int96"); return }
        // Truncation and unknown types.
        #expect(throws: PreviewFailure.malformedDocument) { try raws(1, [1, 2, 3], count: 1) }
        #expect(throws: PreviewFailure.malformedDocument) { try raws(6, [9, 0, 0, 0, 1], count: 1) }
        #expect(throws: PreviewFailure.malformedDocument) { try raws(0, [1], count: 9) }
        #expect(throws: PreviewFailure.malformedDocument) { try raws(7, [1, 2], count: 1) }
        #expect(throws: PreviewFailure.unsupportedFormat) { try raws(9, [1, 2, 3, 4], count: 1) }
    }

    @Test func leafLevelsFollowOptionalAndRepeatedAncestors() throws {
        func element(_ name: String, type: Int? = nil, repetition: Int? = nil, children: Int = 0) -> ParquetFooter.SchemaElement {
            var value = ParquetFooter.SchemaElement()
            value.name = name
            value.physicalType = type
            value.repetition = repetition
            value.childCount = children
            return value
        }
        let good = [element("root", children: 3), element("a", type: 1, repetition: 0),
                    element("opt", repetition: 1, children: 1), element("deep", type: 1, repetition: 1),
                    element("rep", type: 2, repetition: 2)]
        let leaves = try #require(ParquetLeaf.leaves(of: good))
        #expect(leaves.map(\.name) == ["a", "opt.deep", "rep"])
        #expect(leaves.map(\.maximumDefinition) == [0, 2, 1] && leaves.map(\.maximumRepetition) == [0, 0, 1])
        #expect(ParquetLeaf.leaves(of: [element("root", children: 2), element("only", type: 1, repetition: 0)]) != nil)
        #expect(ParquetLeaf.leaves(of: [element("root", children: 1), element("a", type: 1), element("extra", type: 1)]) == nil)
    }

    @Test func valuesConvertUsingTheirAnnotations() {
        func cell(_ raw: ParquetRaw, _ leaf: ParquetLeaf) -> String { text(ParquetCells.cell(raw, leaf: leaf)) }
        #expect(cell(.int32(20_454), leaf(1, converted: 6)) == "2026-01-01")
        #expect(cell(.int32(-1), leaf(1, logical: "DATE")) == "1969-12-31")
        #expect(cell(.int32(12_345), leaf(1, converted: 5, scale: 2)) == "123.45")
        #expect(cell(.int32(-5), leaf(1, logical: "DECIMAL(9, 2)")) == "-0.05")
        #expect(cell(.int64(7), leaf(2, converted: 5, scale: 0)) == "7")
        #expect(cell(.int32(-1), leaf(1, converted: 13)) == "4294967295")
        #expect(cell(.int64(-1), leaf(2, converted: 14)) == "18446744073709551615")
        #expect(cell(.int32(-1), leaf(1, converted: 15)) == "-1")
        #expect(cell(.int64(1_767_225_600_500), leaf(2, converted: 9)) == "2026-01-01T00:00:00.5Z")
        #expect(cell(.int64(1_767_225_600_000_123), leaf(2, converted: 10)) == "2026-01-01T00:00:00.000123Z")
        #expect(cell(.int64(1_767_225_600_000_000_001), leaf(2, logical: "TIMESTAMP(NANOS, UTC)")) == "2026-01-01T00:00:00.000000001Z")
        #expect(cell(.int64(-1_500), leaf(2, converted: 9)) == "1969-12-31T23:59:58.5Z")
        #expect(cell(.int96(julianDay: 2_461_042, nanosecondsOfDay: 3_600_000_000_000), leaf(3)) == "2026-01-01T01:00:00Z")
        #expect(cell(.boolean(true), leaf(0)) == "true" && cell(.float(0.1), leaf(4)) == "0.1" && cell(.double(2.5), leaf(5)) == "2.5")
        #expect(cell(.bytes(prefix: Array("héllo".utf8), length: 6), leaf(6, converted: 0)) == "héllo")
        #expect(cell(.bytes(prefix: Array("abc".utf8), length: 9), leaf(6, logical: "STRING")) == "abc…")
        #expect(cell(.bytes(prefix: [1, 2], length: 2), leaf(6)) == "bytes:2")
        #expect(cell(.bytes(prefix: [1], length: 16), leaf(7, converted: 5, scale: 2, length: 16)) == "bytes:16")
        // A multi-byte character cut by the retained prefix is dropped, not split.
        let cut = Array("aé".utf8.prefix(2))
        #expect(cell(.bytes(prefix: cut, length: 3), leaf(6, converted: 0)) == "a…")
    }
}

@Suite("Parquet row sample")
struct ParquetRowSampleTests {
    private let columns = ["id", "name", "score", "flag", "day", "amount", "ts", "api_token", "blob"]

    @Test func everySupportedPageShapeDecodesToTheFirstRows() throws {
        let document = try DataTest.parse(ParquetAdapter(), DataFixtures.parquetRows)
        let object = try DataTest.object(document)
        let sample = try #require(object["rowSample"] as? [String: Any])
        #expect(sample["columnNames"] as? [String] == columns)
        // The repeated (LIST) column is not one-entry-per-row, so it is left out and the table says so.
        #expect(sample["truncated"] as? Bool == true)
        let rows = (sample["rows"] as? [[Any]] ?? []).map { $0.map(DataTest.cell) }
        let secret = DataFixtures.secret
        #expect(rows.count == 5)
        #expect(rows[0] == ["10", "alpha", "1.5", "true", "2026-01-01", "123.45", "2026-01-01T00:00:00.5Z", secret, "bytes:3"])
        #expect(rows[1] == ["20", "null", "2.5", "false", "2026-01-02", "-0.05", "2026-01-01T00:00:01.5Z", "null", "bytes:3"])
        #expect(rows[2] == ["30", "gamma", "null", "true", "2026-01-03", "0.00", "2026-01-01T00:00:02.5Z", secret, "bytes:3"])
        #expect(rows[3] == ["40", "alpha", "4.5", "true", "2026-01-04", "1.00", "2026-01-01T00:00:03.5Z", secret, "bytes:3"])
        #expect(rows[4] == ["50", "null", "5.5", "false", "2026-01-05", "999.99", "2026-01-01T00:00:04.5Z", secret, "bytes:3"])
        // The footer summary and schema table are unchanged beside it.
        #expect(object["rowCount"] as? Int == 5 && object["columnCount"] as? Int == 10)
        #expect(try DataTest.table(object).rows.count == 12)
    }

    @Test func secretNamedColumnsAreConcealedInEveryRow() throws {
        let document = try DataTest.parse(ParquetAdapter(), DataFixtures.parquetRows)
        let text = Array(document.text.utf8)
        let concealed = document.sensitiveRanges.map { String(decoding: text[$0.utf8Range], as: UTF8.self) }
        // Four non-null cells of the api_token column; the null cell has nothing to hide.
        #expect(concealed == Array(repeating: DataFixtures.secret, count: 4))
    }

    @Test func pagesAreReadOnlyInsideTheColumnChunks() throws {
        let data = DataFixtures.parquetRows
        let source = DataRecordingSource(data)
        _ = try ParquetAdapter().parse(source, context: DataTest.context())
        let footerLength = Int(data[(data.count - 8)..<(data.count - 4)].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) })
        let footerStart = data.count - 8 - footerLength
        #expect(source.reads[0] == 0..<4 && source.reads[1] == (data.count - 8)..<data.count)
        let pageReads = source.reads.dropFirst(3)
        #expect(!pageReads.isEmpty)
        #expect(pageReads.allSatisfy { $0.lowerBound >= 4 && $0.upperBound <= footerStart })
        #expect(source.reads.map(\.count).reduce(0, +) < data.count * 3)
    }

    @Test func unsupportedColumnsAreLeftOutWithoutLosingTheSummary() throws {
        // The first fixture's pages are zeros and its codecs include ZSTD: nothing can be sampled.
        let object = try DataTest.object(try DataTest.parse(ParquetAdapter(), DataFixtures.parquet))
        #expect(object["rowSample"] == nil && object["rowCount"] as? Int == 3)
    }

    @Test func sampleReadsStayInsideAHalfBudget() throws {
        // With only a few hundred bytes left over, no page is read but the footer summary is complete.
        let data = DataFixtures.parquetRows
        let source = DataRecordingSource(data)
        let budget = PreviewBudget(maxInputBytes: 700, maxMilliseconds: 30_000)
        let object = try DataTest.object(try ParquetAdapter().parse(source, context: DataTest.context(budget)))
        #expect(object["rowSample"] == nil && object["dataFormat"] as? String == "Parquet")
        #expect(source.reads.map(\.count).reduce(0, +) <= 700)
    }

    @Test func corruptPagesNeverEndTheSummaryOrEscapeTheLimits() throws {
        let data = DataFixtures.parquetRows
        let footerLength = Int(data[(data.count - 8)..<(data.count - 4)].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) })
        let footerStart = data.count - 8 - footerLength
        for index in 4..<footerStart {
            for value: UInt8 in [0x00, 0xFF, data[index] ^ 0x5A] {
                var changed = data
                changed[index] = value
                // The footer is untouched, so the summary always survives; a damaged sample is simply absent or shorter.
                do {
                    let object = try DataTest.object(try DataTest.parse(ParquetAdapter(), changed))
                    #expect(object["dataFormat"] as? String == "Parquet", "byte \(index)")
                } catch { Issue.record("byte \(index): \(error)") }
            }
        }
    }

    @Test func everyTruncationEndsBoundedAndTyped() {
        let data = DataFixtures.parquetRows
        for length in 0..<data.count {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(ParquetAdapter(), data.prefix(length)) }
        }
    }

    @Test func gzipBombsAndOversizedPageClaimsAreContained() throws {
        // A GZIP page whose header lies about its uncompressed size is rejected by the bounded inflater.
        var data = DataFixtures.parquetRows
        let range = try #require(data.range(of: Data([0x1F, 0x8B, 0x08])))
        data[range.lowerBound + 12] ^= 0xFF
        let object = try DataTest.object(try DataTest.parse(ParquetAdapter(), data))
        let sample = object["rowSample"] as? [String: Any]
        #expect((sample?["columnNames"] as? [String])?.contains("score") != true)
    }
}
