import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Safetensors malformed, oversized and bounded input")
struct SafetensorsFailureTests {
    private func parse(_ data: Data, budget: PreviewBudget = SafetensorsTestSupport.budget()) throws -> ParsedTextDocument {
        try SafetensorsTestSupport.parse(data, budget: budget).1
    }

    private func parse(json: String, dataBytes: Int = 0) throws -> ParsedTextDocument {
        try parse(SafetensorsFixtures.file(json: json, dataBytes: dataBytes))
    }

    private let valid = "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}"

    @Test func theValidBaselineParses() throws {
        _ = try parse(json: valid, dataBytes: 4)
    }

    @Test func notSafetensorsAtAllFailsClosed() {
        let ordinary = SafetensorsFixtures.ordinary()
        let samples: [Data] = [Data(), Data([1, 2, 3]), Data(count: 8), Data(repeating: 0xFF, count: 64), Data("not a model, just text".utf8),
                               Data(repeating: 0, count: 8) + Data("{}".utf8), Data(ordinary.dropFirst())]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try parse(data) }
        }
    }

    @Test func everyTruncationInsideTheHeaderFailsAndNeverCrashes() throws {
        let data = SafetensorsFixtures.ordinary()
        let headerEnd = 8 + Int(data.prefix(8).reversed().reduce(0) { $0 << 8 | Int($1) })
        for length in 0..<headerEnd {
            #expect(throws: PreviewFailure.malformedDocument, "length \(length)") { try parse(data.prefix(length)) }
        }
        // A cut after the header is a partial download, not a malformed file.
        let document = try parse(data.prefix(headerEnd))
        #expect(document.findings.map(\.kind) == [.modelIncomplete])
    }

    @Test func headerLengthsOutsideTheLimitsAreRejectedBeforeAnyAllocation() {
        let cases: [(UInt64, Int, PreviewFailure)] = [
            (0, 100, .malformedDocument), (UInt64.max, 100, .malformedDocument), (1 << 40, 100, .malformedDocument),
            (500, 100, .malformedDocument),
            // Larger than the 16 MiB cap, though the file really holds that many bytes.
            (16 * 1_048_576 + 1, 16 * 1_048_576 + 64, .inputTooLarge)
        ]
        for (declared, size, failure) in cases {
            let data = SafetensorsFixtures.file(header: Data(count: size - 8), dataBytes: 0, declaredLength: declared)
            #expect(throws: failure, "declared \(declared)") { try parse(data) }
        }
    }

    @Test func aHeaderBeyondTheReadBudgetIsRejected() {
        let tensors = SafetensorsFixtures.laidOut((0..<100).map { ("tensor.number.\($0)", "U8", [UInt64(4)]) })
        let data = SafetensorsFixtures.file(tensors)
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: SafetensorsTestSupport.budget(input: 1_000)) }
    }

    @Test func structuralErrorsAreMalformed() {
        let broken = [
            "[]", "\"w\"", "{", "{\"w\"", "{\"w\":}",
            valid + "x", valid + "{}", valid.replacingOccurrences(of: "}}", with: "},}"),
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]},\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[4,8]}}",
            "{\"w\":{\"dtype\":\"U8\",\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}",
            "{\"__metadata__\":{\"a\":\"1\",\"a\":\"2\"}}", "{\"__metadata__\":{\"a\":1}}", "{\"__metadata__\":[]}", "{\"__metadata__\":{}, \"__metadata__\":{}}",
            "{\"w\":{}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4]}}", "{\"w\":{\"dtype\":\"U8\",\"data_offsets\":[0,4]}}",
            "{\"w\":{\"shape\":[4],\"data_offsets\":[0,4]}}", "{\"w\":{\"dtype\":8,\"shape\":[4],\"data_offsets\":[0,4]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":4,\"data_offsets\":[0,4]}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,2,4]}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[4,0]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[-4],\"data_offsets\":[0,4]}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4.0],\"data_offsets\":[0,4]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[1e1],\"data_offsets\":[0,4]}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[04],\"data_offsets\":[0,4]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[99999999999999999999],\"data_offsets\":[0,4]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]},}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4,],\"data_offsets\":[0,4]}}",
            "{\"w\\q\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}", "{\"w\\ud800\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}",
            "{\"w\\udc00\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}", "{\"w\\u12\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}",
            "{\"w\u{1}\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4]}}",
            "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4],\"x\":tru}}", "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4],\"x\":-}}"
        ]
        for json in broken {
            #expect(throws: PreviewFailure.self, "\(json)") { try parse(json: json) }
        }
    }

    @Test func invalidUTF8InAStringIsMalformed() {
        var header = Data(valid.utf8)
        header.replaceSubrange(2..<3, with: [0xFF])
        #expect(throws: PreviewFailure.malformedDocument) { try parse(SafetensorsFixtures.file(header: header, dataBytes: 4)) }
        var overlong = Data(valid.utf8)
        overlong.replaceSubrange(2..<3, with: [0xC0, 0x80])
        #expect(throws: PreviewFailure.malformedDocument) { try parse(SafetensorsFixtures.file(header: overlong, dataBytes: 4)) }
    }

    @Test func shapesThatOverflowAreMalformed() {
        let json = "{\"w\":{\"dtype\":\"U8\",\"shape\":[1099511627776,1099511627776],\"data_offsets\":[0,0]}}"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(json: json) }
        let rank = "{\"w\":{\"dtype\":\"U8\",\"shape\":[\((0..<65).map { _ in "1" }.joined(separator: ","))],\"data_offsets\":[0,1]}}"
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(json: rank, dataBytes: 1) }
    }

    @Test func nestingInIgnoredFieldsStopsAtFourLevels() throws {
        func descriptor(extra: String) -> String { "{\"w\":{\"dtype\":\"U8\",\"shape\":[4],\"data_offsets\":[0,4],\"x\":\(extra)}}" }
        _ = try parse(json: descriptor(extra: "[[1]]"), dataBytes: 4)
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(json: descriptor(extra: "[[[1]]]"), dataBytes: 4) }
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(json: descriptor(extra: "{\"a\":{\"b\":{\"c\":1}}}"), dataBytes: 4) }
    }

    @Test func moreThanTwoHundredThousandTensorsAreRejected() {
        let entries = (0...200_000).map { "\"t\($0)\":{\"dtype\":\"U8\",\"shape\":[],\"data_offsets\":[0,1]}" }
        let json = "{" + entries.joined(separator: ",") + "}"
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(SafetensorsFixtures.file(json: json, dataBytes: 1), budget: SafetensorsTestSupport.budget()) }
    }

    @Test func tensorDataIsNeverRequestedFromAHugeFile() throws {
        final class SparseSource: PreviewByteSource {
            let header: Data
            let byteCount: Int64
            let ranges = Mutex<[Range<Int64>]>([])
            init(header: Data, byteCount: Int64) { self.header = header; self.byteCount = byteCount }
            func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
                ranges.withLock { $0.append(offset..<(offset + Int64(count))) }
                var data = Data(count: count)
                let overlap = max(offset, 0)..<min(offset + Int64(count), Int64(header.count))
                if overlap.lowerBound < overlap.upperBound {
                    data.replaceSubrange(Int(overlap.lowerBound - offset)..<Int(overlap.upperBound - offset),
                                         with: header[Int(overlap.lowerBound)..<Int(overlap.upperBound)])
                }
                return data
            }
        }
        let tensor = SafetensorsFixtures.Tensor(name: "huge", dtype: "F16", shape: [100_000, 250_000], begin: 0, end: 50_000_000_000)
        let header = SafetensorsFixtures.file(header: Data(SafetensorsFixtures.headerJSON([tensor]).utf8), dataBytes: 0)
        let source = SparseSource(header: header, byteCount: Int64(header.count) + 50_000_000_000)
        let document = try SafetensorsAdapter().parse(source, context: RequestContext(budget: SafetensorsTestSupport.budget()))
        #expect(PackageTestSupport.object(document)["parameters"] as? Int == 25_000_000_000)
        #expect(document.findings.isEmpty)
        let ranges = source.ranges.withLock { $0 }
        #expect(ranges.map(\.upperBound).max() ?? 0 <= Int64(header.count))
    }

    @Test func cancellationStopsAnActiveParse() async throws {
        let specs = SafetensorsFixtures.laidOut((0..<5_000).map { ("blk.\($0).w", "U8", [UInt64(4)]) })
        let data = SafetensorsFixtures.file(specs)
        let document = try await CancellationTest.expectStopsActiveParse(budget: SafetensorsTestSupport.budget()) { context in
            try SafetensorsAdapter().parse(DataByteSource(data), context: context)
        }
        #expect(PackageTestSupport.object(document)["tensorCount"] as? Int == 5_000)
    }

    @Test func aCancelledRequestThrowsCancellation() async {
        let data = SafetensorsFixtures.ordinary()
        let cancelled = await PackageTestSupport.parseIsCancelled {
            _ = try SafetensorsAdapter().parse(DataByteSource(data), context: PackageTestSupport.context)
        }
        #expect(cancelled)
    }
}
