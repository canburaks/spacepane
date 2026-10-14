import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("GGUF malformed, oversized and bounded input")
struct GGUFFailureTests {
    private func parse(_ data: Data, budget: PreviewBudget = GGUFTestSupport.budget()) throws -> ParsedTextDocument {
        try GGUFAdapter().parse(DataByteSource(data), context: RequestContext(budget: budget))
    }

    /// A header written field by field, for inputs the fixture builder would not produce.
    private func raw(version: UInt32 = 3, tensors: UInt64 = 0, entries: UInt64 = 1,
                     _ body: (inout GGUFFixtures.Writer) -> Void) -> Data {
        var writer = GGUFFixtures.Writer(bigEndian: false)
        writer.bytes(GGUFFixtures.magic)
        writer.u32(version)
        writer.u64(tensors)
        writer.u64(entries)
        body(&writer)
        // Zeros after the body, so the declared counts are not rejected as truncation before the check under test.
        writer.bytes([UInt8](repeating: 0, count: 64))
        return Data(writer.output)
    }

    @Test func notGGUFAtAllFailsClosed() {
        let ordinary = GGUFFixtures.ordinary().data
        let samples: [Data] = [Data(), Data("GGU".utf8), Data("GGUF".utf8), Data("GGUX".utf8) + Data(repeating: 0, count: 64),
                               Data(repeating: 0xFF, count: 512), Data(repeating: 0, count: 512), Data("not a model".utf8),
                               Data(ordinary.dropFirst())]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try parse(data) }
        }
    }

    @Test func everyTruncationInsideTheHeaderFailsAndNeverCrashes() throws {
        let built = GGUFFixtures.ordinary()
        for length in 0..<built.headerEnd {
            #expect(throws: PreviewFailure.malformedDocument, "length \(length)") { try parse(built.data.prefix(length)) }
        }
        // A cut after the header is a partial download, not a malformed file.
        let document = try parse(built.data.prefix(built.headerEnd))
        #expect(GGUFTestSupport.kinds(document) == [.modelIncomplete])
    }

    @Test func countsBeyondTheCapsAreRejectedBeforeAnythingIsAllocated() {
        let over: [(UInt64, UInt64)] = [(100_001, 0), (0, 10_001), (UInt64.max, 0), (0, UInt64.max), (UInt64.max, UInt64.max)]
        for (tensors, entries) in over {
            let data = raw(tensors: tensors, entries: entries) { _ in }
            #expect(throws: PreviewFailure.tooManyNodes) { try parse(data) }
        }
    }

    @Test func countsThatCannotFitTheFileAreTruncation() {
        let data = raw(tensors: 5_000, entries: 9_000) { _ in }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(data) }
    }

    @Test func lengthsBeyondTheirCapsOrTheFileAreMalformed() {
        let hugeKey = raw { $0.u64(65_537); $0.bytes([UInt8](repeating: 0x61, count: 65_537)); $0.u32(7); $0.bytes([1]) }
        let farKey = raw { $0.u64(1 << 40) }
        let farString = raw { $0.string("k"); $0.u32(8); $0.u64(1 << 40) }
        let negativeLooking = raw { $0.string("k"); $0.u32(8); $0.u64(UInt64.max) }
        for data in [hugeKey, farKey, farString, negativeLooking] {
            #expect(throws: PreviewFailure.malformedDocument) { try parse(data) }
        }
    }

    @Test func arrayCountsThatOverrunTheFileAreMalformed() {
        let counts: [(UInt32, UInt64)] = [(8, UInt64.max), (8, 1 << 40), (6, UInt64.max), (6, 1 << 40), (4, UInt64.max / 2), (9, 1 << 40), (0, 1 << 62)]
        for (type, count) in counts {
            let data = raw { $0.string("k"); $0.u32(9); $0.u32(type); $0.u64(count) }
            #expect(throws: PreviewFailure.malformedDocument, "type \(type) count \(count)") { try parse(data) }
        }
    }

    @Test func arraysNestToDepthFourAndNoFurther() throws {
        let inner = GGUFFixtures.Value.zeros(type: 4, count: 3)
        func nest(_ levels: Int) -> GGUFFixtures.Value { (1..<max(levels, 1)).reduce(inner) { value, _ in .nested([value]) } }
        _ = try parse(GGUFFixtures.build(metadata: [("k", nest(4))]).data)
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(GGUFFixtures.build(metadata: [("k", nest(5))]).data) }
    }

    @Test func unknownValueTypesAndBadTensorShapesAreMalformed() {
        let unknownType = raw { $0.string("k"); $0.u32(13); $0.bytes([0, 0, 0, 0]) }
        let tooManyDimensions = raw(tensors: 1, entries: 0) { $0.string("t"); $0.u32(5); for _ in 0..<5 { $0.u64(1) }; $0.u32(0); $0.u64(0) }
        let noDimensions = raw(tensors: 1, entries: 0) { $0.string("t"); $0.u32(0); $0.u32(0); $0.u64(0) }
        let overflowingShape = raw(tensors: 1, entries: 0) { $0.string("t"); $0.u32(2); $0.u64(1 << 40); $0.u64(1 << 40); $0.u32(0); $0.u64(0) }
        let longName = raw(tensors: 1, entries: 0) { $0.u64(65_537); $0.bytes([UInt8](repeating: 0x61, count: 65_537)); $0.u32(1); $0.u64(1); $0.u32(0); $0.u64(0) }
        for data in [unknownType, tooManyDimensions, noDimensions, overflowingShape, longName] {
            #expect(throws: PreviewFailure.malformedDocument) { try parse(data) }
        }
    }

    @Test(arguments: [UInt32(0), 3, 24, 48, 1 << 31])
    func anInvalidAlignmentIsMalformed(alignment: UInt32) {
        let built = GGUFFixtures.build(metadata: [("general.alignment", .u32(alignment))])
        #expect(throws: PreviewFailure.malformedDocument) { try parse(built.data) }
    }

    // MARK: Budget

    @Test func aBudgetEndingInsideTheVocabularyGivesAPartialSummary() throws {
        let tokens = (0..<100_000).map { "token\($0)" }
        let built = GGUFFixtures.build(metadata: [
            ("general.name", .string("Cut Short")), ("general.architecture", .string("llama")),
            ("tokenizer.ggml.tokens", .strings(tokens))
        ], tensors: GGUFFixtures.laidOut([("w", [32], 0)]))
        let document = try parse(built.data, budget: GGUFTestSupport.budget(input: 300_000))
        let summary = PackageTestSupport.object(document)
        #expect(summary["partial"] as? Bool == true)
        #expect(summary["name"] as? String == "Cut Short" && summary["architecture"] as? String == "llama")
        #expect(summary["parameters"] == nil && summary["bitsPerWeight"] == nil && summary["tensorTypes"] == nil)
        #expect(summary["vocabularySize"] == nil && summary["tensors"] == nil)
        #expect(document.findings.isEmpty, "A partial read cannot say the file is incomplete")
    }

    @Test func aBudgetEndingInsideTheTensorTableKeepsTheTensorsReadSoFar() throws {
        let specs = (0..<2_000).map { ("blk.\($0).weight", [UInt64(32)], UInt32(0)) }
        let built = GGUFFixtures.build(metadata: [("general.name", .string("Cut Short"))], tensors: GGUFFixtures.laidOut(specs))
        let document = try parse(built.data, budget: GGUFTestSupport.budget(input: 20_000))
        let summary = PackageTestSupport.object(document)
        let listed = (summary["tensors"] as? [[String: Any]])?.count ?? 0
        #expect(summary["partial"] as? Bool == true)
        #expect(listed > 0 && listed < 2_000)
        #expect(summary["parameters"] == nil && summary["tensorTypes"] == nil)
        #expect(document.findings.isEmpty)
    }

    @Test func aBudgetTooSmallForTheFirstBytesFails() {
        for input in [1, 10, 23] {
            #expect(throws: PreviewFailure.inputTooLarge) { try parse(GGUFFixtures.ordinary().data, budget: GGUFTestSupport.budget(input: input)) }
        }
    }

    @Test func aSourceThatRunsOutOfBudgetOnItsOwnAlsoGivesAPartialSummary() throws {
        final class StingySource: PreviewByteSource {
            let inner: DataByteSource
            let limit: Int
            let used = Mutex(0)
            init(inner: DataByteSource, limit: Int) { self.inner = inner; self.limit = limit }
            var byteCount: Int64 { inner.byteCount }
            func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
                try used.withLock { total in
                    guard total + count <= limit else { throw PreviewFailure.inputTooLarge }
                    total += count
                }
                return try inner.read(offset: offset, count: count, context: context)
            }
        }
        let built = GGUFFixtures.build(metadata: [("general.name", .string("Stingy")), ("tokenizer.ggml.tokens", .strings((0..<50_000).map { "t\($0)" }))])
        let source = StingySource(inner: DataByteSource(built.data), limit: 100_000)
        let document = try GGUFAdapter().parse(source, context: RequestContext(budget: GGUFTestSupport.budget()))
        #expect(PackageTestSupport.object(document)["partial"] as? Bool == true)
    }

    // MARK: Reads

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
        let tensors = GGUFFixtures.laidOut([("huge.weight", [100_000, 250_000], 1)])
        let built = GGUFFixtures.build(metadata: [("general.name", .string("Fifty Gigabytes"))], tensors: tensors, dataBytes: 0)
        let size = Int64(built.dataStart) + 50_000_000_000
        let source = SparseSource(header: built.data, byteCount: size)
        let document = try GGUFAdapter().parse(source, context: RequestContext(budget: GGUFTestSupport.budget()))
        let summary = PackageTestSupport.object(document)
        #expect(summary["parameters"] as? Int == 25_000_000_000)
        #expect(document.findings.isEmpty, "The file is exactly as large as its tensors need")
        let ranges = source.ranges.withLock { $0 }
        #expect(ranges.map(\.upperBound).max() ?? 0 <= Int64(built.headerEnd + GGUFByteReader.firstWindow))
        #expect(ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } <= Int64(GGUFByteReader.firstWindow))
    }

    // MARK: Cancellation

    @Test func cancellationStopsAnActiveParse() async throws {
        let metadata = (0..<400).map { ("zz.key\($0)", GGUFFixtures.Value.u32(UInt32($0))) }
        let built = GGUFFixtures.build(metadata: metadata, tensors: GGUFFixtures.laidOut([("w", [32], 0)]))
        let document = try await CancellationTest.expectStopsActiveParse(budget: GGUFTestSupport.budget()) { context in
            try GGUFAdapter().parse(DataByteSource(built.data), context: context)
        }
        #expect(PackageTestSupport.object(document)["metadataCount"] as? Int == 400)
    }

    @Test func aCancelledRequestThrowsCancellation() async {
        let data = GGUFFixtures.ordinary().data
        let cancelled = await PackageTestSupport.parseIsCancelled {
            _ = try GGUFAdapter().parse(DataByteSource(data), context: PackageTestSupport.context)
        }
        #expect(cancelled)
    }
}
