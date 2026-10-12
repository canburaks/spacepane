import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Assembles `.npy` bytes from plain values, independently of the reader under test.
private func npy(descr: String, shape: String, fortran: Bool = false, values: [UInt8] = [], version: UInt8 = 1,
                 header customHeader: String? = nil) -> Data {
    let dictionary = customHeader ?? "{'descr': '\(descr)', 'fortran_order': \(fortran ? "True" : "False"), 'shape': \(shape), }"
    let preamble = version == 1 ? 10 : 12
    let padding = (64 - (preamble + dictionary.utf8.count + 1) % 64) % 64
    let header = Array((dictionary + String(repeating: " ", count: padding) + "\n").utf8)
    let length: [UInt8] = version == 1 ? [UInt8(header.count & 0xFF), UInt8(header.count >> 8)]
        : (0..<4).map { UInt8(truncatingIfNeeded: header.count >> ($0 * 8)) }
    return Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, version, 0] + length + header + values)
}

private func bytes<T: FixedWidthInteger>(_ values: [T], bigEndian: Bool = false) -> [UInt8] {
    values.flatMap { value -> [UInt8] in
        let ordered = bigEndian ? value.bigEndian : value.littleEndian
        return withUnsafeBytes(of: ordered) { Array($0) }
    }
}

private func parseHeader(_ data: Data, budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> NumPyHeader {
    try NumPyHeader.parse(available: data.count, context: RequestContext(budget: budget)) { offset, count in
        guard offset >= 0, count >= 0, offset + count <= data.count else { throw PreviewFailure.malformedDocument }
        return Array(data[offset..<(offset + count)])
    }
}

@Suite("Metadata-only NumPy grid safety")
struct NumPyGridFactSafetyTests {
    @Test func structuredAndObjectMetadataDoNotClaimAValidatedValuesGrid() throws {
        let structured = npy(descr: "", shape: "(2,)",
            header: "{'descr': [('x', '<i4'), ('y', '<f8')], 'fortran_order': False, 'shape': (2,), }")
        let object = npy(descr: "|O", shape: "(2,)", values: [UInt8](repeating: 0, count: 16))
        for bytes in [structured, object] {
            let document = try DataTest.parse(NumPyAdapter(), bytes)
            #expect(document.facts.isEmpty)
            #expect(try DataTest.object(document)[DataSummaryKeys.table] == nil)
        }
    }
}

@Suite("NumPy header")
struct NumPyHeaderTests {
    @Test func versionsOneTwoAndThreeParse() throws {
        for version: UInt8 in [1, 2, 3] {
            let header = try parseHeader(npy(descr: "<f8", shape: "(3, 4)", version: version))
            #expect(header.shape == [3, 4] && header.version == "\(version).0" && !header.fortranOrder)
            #expect(header.dtype.display == "float64 (<f8)")
        }
        #expect(throws: PreviewFailure.unsupportedFormat) { try parseHeader(npy(descr: "<f8", shape: "(1,)", version: 4)) }
    }

    @Test func shapesDtypesAndOrderCoverTheNumpyHeaderGrammar() throws {
        #expect(try parseHeader(npy(descr: "<i4", shape: "()")).shape == [])
        #expect(try parseHeader(npy(descr: "<i4", shape: "(5,)")).shape == [5])
        #expect(try parseHeader(npy(descr: "<i4", shape: "(3L, 4L)")).shape == [3, 4])
        #expect(try parseHeader(npy(descr: "<i4", shape: "( 2 ,3 , )", fortran: true)).fortranOrder)
        #expect(try parseHeader(npy(descr: "x", shape: "(1,)", header: "{\"descr\": \"|b1\", \"fortran_order\": False, \"shape\": (2,)}")).dtype.kind == .bool)
        let displays = ["<f4": "float32 (<f4)", ">i2": "int16 (>i2)", "|u1": "uint8 (|u1)", "<c16": "complex128 (<c16)",
                        "<U5": "str[5] (<U5)", "|S3": "bytes[3] (|S3)", "|O": "object (|O)", "<M8[ns]": "datetime64[ns] (<M8[ns])",
                        "<m8[s]": "timedelta64[s] (<m8[s])", "|V4": "void[4] (|V4)", "<f2": "float16 (<f2)"]
        for (descr, display) in displays {
            #expect(try parseHeader(npy(descr: descr, shape: "(1,)")).dtype.display == display, "\(descr)")
        }
    }

    @Test func structuredDtypesListTheirFieldsOnly() throws {
        let header = try parseHeader(npy(descr: "", shape: "(2,)",
            header: "{'descr': [('x', '<i4'), ('y', '<f8', (2,)), ('z', [('a', '|b1')])], 'fortran_order': False, 'shape': (2,), }"))
        #expect(header.dtype.kind == .structured)
        #expect(header.dtype.fields.map(\.name) == ["x", "y", "z"])
        #expect(header.dtype.fields[0].dtype == "int32 (<i4)")
        #expect(header.dtype.display == "structured (3)")
        #expect(header.dataByteCount == nil)
    }

    @Test func nothingIsEvaluatedAndEveryNonLiteralIsRejected() throws {
        let hostile = [
            "{'descr': __import__('os').system('true'), 'fortran_order': False, 'shape': (1,), }",
            "{'descr': '<f8', 'fortran_order': 1 == 1, 'shape': (1,), }",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (1+1,), }",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (1,), 'extra': 1}",
            "{'descr': '<f8', 'descr': '<f4', 'fortran_order': False}",
            "{'descr': '<f8', 'fortran_order': False}",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (-1,), }",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (99999999999999999999999,), }",
            "{'descr': '<f8', 'fortran_order': 'False', 'shape': (1,), }",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (1,), } # trailing",
            "{'descr': '<f8', 'fortran_order': False, 'shape': (1,), ",
            "{'descr': 'Q8', 'fortran_order': False, 'shape': (1,), }",
            "[1, 2]", "", "{", "{'descr': '<f8', 'fortran_order': Falsey, 'shape': (1,), }"
        ]
        for text in hostile {
            #expect(throws: PreviewFailure.self, "\(text)") { try parseHeader(npy(descr: "", shape: "", header: text)) }
        }
    }

    @Test func nestingAndSizeAreBounded() throws {
        let deep = String(repeating: "[", count: 12) + String(repeating: "]", count: 12)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try parseHeader(npy(descr: "", shape: "", header: "{'descr': \(deep), 'fortran_order': False, 'shape': (1,), }"))
        }
        let wide = "[" + String(repeating: "('a', '<i4'),", count: 1_100) + "]"
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parseHeader(npy(descr: "", shape: "", header: "{'descr': \(wide), 'fortran_order': False, 'shape': (1,), }"))
        }
        // A declared header length above the limit.
        var data = npy(descr: "<f8", shape: "(1,)", version: 2)
        data.replaceSubrange(8..<12, with: Data([0xFF, 0xFF, 0x7F, 0x00]))
        #expect(throws: PreviewFailure.malformedDocument) { try parseHeader(data) }
        #expect(throws: PreviewFailure.malformedDocument) { try parseHeader(Data([0x93, 0x4E])) }
        #expect(throws: PreviewFailure.malformedDocument) { try parseHeader(Data("NOTNUMPY00".utf8) + Data(count: 100)) }
    }
}

@Suite("NumPy adapter")
struct NumPyAdapterTests {
    @Test func aTwoDimensionalFloatArrayShowsExactValues() throws {
        let object = try DataTest.object(try DataTest.parse(NumPyAdapter(), DataFixtures.numpy))
        #expect(object["dataFormat"] as? String == "NumPy" && object["formatVersion"] as? String == "1.0")
        #expect(object["dtype"] as? String == "float64 (<f8)")
        #expect(object["shape"] as? String == "(3, 4)")
        #expect(object["elementCount"] as? Int == 12)
        #expect(object["fortranOrder"] as? Bool == false)
        let table = try DataTest.table(object)
        #expect(table.columns == ["#", "0", "1", "2", "3"])
        #expect(table.rows.map { $0.map(DataTest.cell) } == [["0", "0.0", "0.1", "0.2", "0.3"],
                                                              ["1", "1.0", "1.1", "1.2", "1.3"],
                                                              ["2", "2.0", "2.1", "2.2", "2.3"]])
        #expect(!table.truncated)
    }

    @Test func fortranOrderReadsColumnsContiguously() throws {
        // a = [[1, 2, 3], [4, 5, 6]] stored column by column.
        let data = npy(descr: "<i4", shape: "(2, 3)", fortran: true, values: bytes([Int32(1), 4, 2, 5, 3, 6]))
        let rows = try DataTest.rows(try DataTest.object(try DataTest.parse(NumPyAdapter(), data)))
        #expect(rows == [["0", "1", "2", "3"], ["1", "4", "5", "6"]])
    }

    @Test func everyNumericKindPrintsItsExactSpelling() throws {
        func values(_ descr: String, _ raw: [UInt8], count: Int) throws -> [String] {
            let data = npy(descr: descr, shape: "(\(count),)", values: raw)
            return try DataTest.rows(try DataTest.object(try DataTest.parse(NumPyAdapter(), data))).map { $0[1] }
        }
        #expect(try values("<i1", bytes([Int8(-128), 127]), count: 2) == ["-128", "127"])
        #expect(try values("<u2", bytes([UInt16(0), 65535]), count: 2) == ["0", "65535"])
        #expect(try values(">i4", bytes([Int32(-2), 258], bigEndian: true), count: 2) == ["-2", "258"])
        #expect(try values("<u8", bytes([UInt64.max]), count: 1) == [String(UInt64.max)])
        #expect(try values("<i8", bytes([Int64.min]), count: 1) == [String(Int64.min)])
        #expect(try values("|b1", [0, 1], count: 2) == ["False", "True"])
        #expect(try values("<f4", bytes([Float(0.1).bitPattern, Float.infinity.bitPattern, Float.nan.bitPattern]), count: 3) == ["0.1", "inf", "nan"])
        #expect(try values("<f8", bytes([Double(0.1).bitPattern, (-0.0).bitPattern, 1e22.bitPattern]), count: 3) == ["0.1", "-0.0", "1e+22"])
        #expect(try values("<f2", bytes([UInt16(0x3C00), 0x7BFF, 0xFC00]), count: 3) == ["1.0", "65504.0", "-inf"])
        #expect(try values(">f8", bytes([Double(2.5).bitPattern], bigEndian: true), count: 1) == ["2.5"])
        let complex = bytes([Float(1.5).bitPattern, Float(-2.5).bitPattern, Float(0).bitPattern, Float(3).bitPattern])
        #expect(try values("<c8", complex, count: 2) == ["1.5-2.5j", "0.0+3.0j"])
    }

    @Test func zeroDimensionalAndEmptyArrays() throws {
        let scalar = npy(descr: "<f8", shape: "()", values: bytes([Double(3.25).bitPattern]))
        let object = try DataTest.object(try DataTest.parse(NumPyAdapter(), scalar))
        #expect(object["shape"] as? String == "()" && object["elementCount"] as? Int == 1)
        #expect(try DataTest.table(object).columns == ["value"])
        #expect(try DataTest.rows(object) == [["3.25"]])
        let empty = try DataTest.object(try DataTest.parse(NumPyAdapter(), npy(descr: "<f8", shape: "(0,)")))
        #expect(empty["table"] == nil && empty["elementCount"] as? Int == 0)
    }

    @Test func largeArraysAreSampledNotLoaded() throws {
        // 1000 x 1000 doubles (8 MB): only the first 100 rows x 20 columns are read.
        let rows = 1_000, columns = 1_000
        var payload = Data(count: rows * columns * 8)
        payload.withUnsafeMutableBytes { raw in
            let doubles = raw.bindMemory(to: Double.self)
            for index in 0..<doubles.count { doubles[index] = Double(index) }
        }
        let file = npy(descr: "<f8", shape: "(\(rows), \(columns))") + payload
        let source = DataRecordingSource(file)
        let object = try DataTest.object(try NumPyAdapter().parse(source, context: DataTest.context()))
        let table = try DataTest.table(object)
        #expect(table.rows.count == 100 && table.columns.count == 21 && table.truncated)
        #expect(table.rows.map { DataTest.cell($0[1]) }.prefix(3) == ["0.0", "1000.0", "2000.0"])
        #expect(DataTest.cell(table.rows[99][20]) == "99019.0")
        #expect(source.reads.map(\.count).reduce(0, +) < 40_000)
        #expect(object["elementCount"] as? Int == 1_000_000)
    }

    @Test func objectAndStructuredArraysNeverHaveTheirDataRead() throws {
        for header in ["{'descr': '|O', 'fortran_order': False, 'shape': (3,), }",
                       "{'descr': [('a', '<i4'), ('b', '<f8')], 'fortran_order': False, 'shape': (3,), }"] {
            let file = npy(descr: "", shape: "", values: Array(repeating: 0x80, count: 64), header: header)
            let source = DataRecordingSource(file)
            let object = try DataTest.object(try NumPyAdapter().parse(source, context: DataTest.context()))
            #expect(object["table"] == nil)
            let headerEnd = 10 + (Int(file[8]) | Int(file[9]) << 8)
            #expect(source.reads.allSatisfy { $0.upperBound <= headerEnd })
        }
        let structured = try DataTest.object(try DataTest.parse(NumPyAdapter(), npy(descr: "", shape: "", header: "{'descr': [('a', '<i4'), ('api_key', '<f8')], 'fortran_order': False, 'shape': (3,), }")))
        #expect((structured["fields"] as? [[String: Any]])?.map { $0["name"] as? String } == ["a", "api_key"])
        #expect(structured["dtype"] as? String == "structured (2)")
    }

    @Test func truncatedAndOversizedShapesAreRejectedWithoutAllocation() throws {
        let truncated = npy(descr: "<f8", shape: "(100, 100)", values: bytes([UInt64](repeating: 0, count: 50)))
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(NumPyAdapter(), truncated) }
        let overflow = npy(descr: "<f8", shape: "(4611686018427387904, 4)")
        let object = try DataTest.object(try DataTest.parse(NumPyAdapter(), overflow))
        #expect(object["elementCount"] == nil && object["table"] == nil)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(NumPyAdapter(), Data()) }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.numpy
        for length in 0..<data.count {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(NumPyAdapter(), data.prefix(length)) }
        }
        for index in 0..<data.count {
            var changed = data
            changed[index] ^= 0xFF
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(NumPyAdapter(), changed) }
        }
    }

    @Test func cancellationPrecedesAnyRead() async {
        let source = DataRecordingSource(DataFixtures.numpy)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? NumPyAdapter().parse(source, context: DataTest.context())
        }
        await task.value
        #expect(source.reads.isEmpty)
    }
}

@Suite("NumPy archive adapter")
struct NumPyArchiveAdapterTests {
    @Test func theArchiveListsArraysAndShowsTheFirstPrintableOne() throws {
        let object = try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), DataFixtures.numpyArchive))
        #expect(object["dataFormat"] as? String == "NumPy archive" && object["arrayCount"] as? Int == 3)
        let arrays = try #require(object["arrays"] as? [[String: Any]])
        #expect(arrays.map { $0["name"] as? String } == ["weights", "api_key", "labels"])
        #expect(arrays.map { $0["dtype"] as? String } == ["float32 (<f4)", "int32 (<i4)", "int64 (<i8)"])
        #expect(arrays.map { $0["shape"] as? String } == ["(2, 3)", "(3,)", "(4,)"])
        #expect(object["shownArray"] as? String == "weights")
        #expect(try DataTest.rows(object) == [["0", "0.5", "1.5", "2.5"], ["1", "3.5", "4.5", "5.5"]])
    }

    @Test func arraysWhoseNamesLookSecretContributeNoValues() throws {
        let secret = npy(descr: "<i4", shape: "(3,)", values: bytes([Int32(11), 22, 33]))
        let plain = npy(descr: "<i4", shape: "(2,)", values: bytes([Int32(7), 8]))
        let archive = DataTest.zip([("access_token.npy", Array(secret), false), ("plain.npy", Array(plain), false)])
        let object = try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), archive))
        #expect(object["shownArray"] as? String == "plain")
        #expect(try DataTest.rows(object) == [["0", "7"], ["1", "8"]])
        // With only a secret-named array there is no table at all.
        let onlySecret = DataTest.zip([("access_token.npy", Array(secret), false)])
        #expect(try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), onlySecret))["table"] == nil)
    }

    @Test func aHugeDeflatedMemberIsOnlyReadAndInflatedAtItsBeginning() throws {
        // 4,000,000 float64 zeros (32 MB) compress to about 30 KB but must never be expanded.
        let header = Array(npy(descr: "<f8", shape: "(4000000,)"))
        let archive = DataTest.zip([("zeros.npy", header + [UInt8](repeating: 0, count: 32_000_000), true)])
        let source = DataRecordingSource(archive)
        let object = try DataTest.object(try NumPyArchiveAdapter().parse(source, context: DataTest.context()))
        #expect(object["shownArray"] as? String == "zeros")
        let table = try DataTest.table(object)
        #expect(table.rows.count == 100 && table.truncated)
        #expect(table.rows.allSatisfy { DataTest.cell($0[1]) == "0.0" })
        #expect(source.reads.map(\.count).reduce(0, +) < 120_000)
    }

    @Test func aMemberWithAHeaderBeyondTheFirstWindowIsStillListed() throws {
        // Pseudo-random names keep the header from compressing below the first read window.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        let names = (0..<150).map { _ -> String in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return String(seed >> 20, radix: 36)
        }
        let fields = names.map { "('\($0)', '<i4')" }.joined(separator: ", ")
        let wide = npy(descr: "", shape: "", header: "{'descr': [\(fields)], 'fortran_order': False, 'shape': (1,), }")
        #expect(wide.count > 2_048)
        let archive = DataTest.zip([("records.npy", Array(wide), true)])
        let arrays = try #require(try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), archive))["arrays"] as? [[String: Any]])
        #expect(arrays.first?["dtype"] as? String == "structured (150)")
    }

    @Test func unreadableMembersAreListedByNameAndHugeArchivesAreCut() throws {
        let broken = DataTest.zip([("broken.npy", Array("not an array".utf8), false)])
        let single = try #require(try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), broken))["arrays"] as? [[String: Any]])
        #expect(single.first?["name"] as? String == "broken" && single.first?["dtype"] == nil)
        let tiny = Array(npy(descr: "<i1", shape: "(1,)", values: [1]))
        let many = DataTest.zip((0..<150).map { ("a\($0).npy", tiny, false) })
        let object = try DataTest.object(try DataTest.parse(NumPyArchiveAdapter(), many))
        #expect(object["arrayCount"] as? Int == 150 && (object["arrays"] as? [Any])?.count == 100)
        #expect(object["partial"] as? Bool == true)
    }

    @Test func nonNumpyArchivesAndNonArchivesAreRefused() throws {
        #expect(throws: PreviewFailure.malformedDocument) {
            try DataTest.parse(NumPyArchiveAdapter(), DataTest.zip([("readme.txt", Array("hello".utf8), false)]))
        }
        #expect(throws: PreviewFailure.self) { try DataTest.parse(NumPyArchiveAdapter(), Data(count: 300)) }
        #expect(throws: PreviewFailure.self) { try DataTest.parse(NumPyArchiveAdapter(), Data()) }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.numpyArchive
        for length in 0..<data.count {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(NumPyArchiveAdapter(), data.prefix(length)) }
        }
        for index in 0..<data.count {
            var changed = data
            changed[index] ^= 0x33
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(NumPyArchiveAdapter(), changed) }
        }
    }

    @Test func prefixInflationStopsAtItsCapAndToleratesCutInput() throws {
        let packed = Data(DataTest.rawDeflate([UInt8](repeating: 7, count: 5_000_000)))
        let capped = try PrefixInflater.inflate(packed, maximumOutput: 1_000, context: DataTest.context())
        #expect(capped == [UInt8](repeating: 7, count: 1_000))
        let cut = try PrefixInflater.inflate(packed.prefix(packed.count / 2), maximumOutput: 10_000_000, context: DataTest.context())
        #expect(cut.allSatisfy { $0 == 7 })
        #expect(throws: PreviewFailure.malformedDocument) {
            try PrefixInflater.inflate(Data([0xFF, 0xFF, 0xFF, 0xFF]), maximumOutput: 100, context: DataTest.context())
        }
    }

    @Test func cancellationPrecedesAnyRead() async {
        let source = DataRecordingSource(DataFixtures.numpyArchive)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? NumPyArchiveAdapter().parse(source, context: DataTest.context())
        }
        await task.value
        #expect(source.reads.isEmpty)
    }
}
