import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

private final class Q52SizeReader: PreviewFileReading, Sendable {
    let reads = Mutex(0)
    let opens = Mutex(0)
    let bytes: FileBytes
    let source: Q52ByteSource
    init(total: Int? = nil, randomSize: Int64 = 9_000_000_000) {
        bytes = FileBytes(data: Data("safe".utf8), totalByteCount: total)
        source = Q52ByteSource(byteCount: randomSize)
    }
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.withLock { $0 += 1 }; return bytes
    }
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource {
        opens.withLock { $0 += 1 }; return source
    }
}
private final class Q52ByteSource: PreviewByteSource, Sendable {
    let byteCount: Int64
    let contentReads = Mutex(0)
    init(byteCount: Int64) { self.byteCount = byteCount }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        contentReads.withLock { $0 += 1 }
        Issue.record("Facts must not add source reads")
        throw PreviewFailure.unreadableFile
    }
}
private struct Q52SummaryAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter, URLFormatAdapter {
    let facts: PresentationFacts
    private var document: ParsedTextDocument { .init(text: "safe summary", origin: .summary, facts: facts) }
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument { document }
    func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument { document }
    func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument { document }
}

private struct Q52GeometryAdapter: GeometryFormatAdapter {
    func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        try PreviewMesh(positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: .init(minimum: .zero, maximum: SIMD3<Double>(1, 1, 0)), faceCount: 1)
    }
}

@Suite("Q52 source size provenance at the read boundary")
struct Q52SourceSizeFactsTests {
    private let url = URL(fileURLWithPath: "/unused/q52-size.txt")
    @Test func completeBinaryReadCarriesSourceBytesAfterParserFacts() async throws {
        let reader = Q52SizeReader()
        let parserFacts = PresentationFacts([.records(3, .events)])
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            binaryAdapter: { Q52SummaryAdapter(facts: parserFacts) })], reader: reader)
        let p = try ready(await pipeline.preview(url: url))
        #expect(p.origin == .summary)
        #expect(p.facts.facts == [.records(3, .events), .size(4)])
        #expect(reader.reads.withLock { $0 } == 1 && reader.opens.withLock { $0 } == 0)
    }
    @Test func aKnownPartialBinaryReadNeverClaimsTheReadSizeIsTheWholeFile() async throws {
        let reader = Q52SizeReader(total: 500)
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            binaryAdapter: { Q52SummaryAdapter(facts: .none) })], reader: reader)
        #expect(try ready(await pipeline.preview(url: url)).facts.facts == [.shownSize(shown: 4, total: 500)])
    }
    @Test func randomAccessUsesExistingInt64MetadataWithoutReadingContent() async throws {
        let reader = Q52SizeReader(randomSize: .max)
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            randomAccessAdapter: { Q52SummaryAdapter(facts: .none) })], reader: reader)
        #expect(try ready(await pipeline.preview(url: url)).facts.facts == [.size(.max)])
        #expect(reader.opens.withLock { $0 } == 1 && reader.reads.withLock { $0 } == 0)
        #expect(reader.source.contentReads.withLock { $0 } == 0)
    }
    @Test func urlSummariesNeverTurnTheDirectorySentinelIntoZeroBytes() async throws {
        let reader = Q52SizeReader()
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            urlAdapter: { Q52SummaryAdapter(facts: .none) })], reader: reader)
        #expect(try ready(await pipeline.preview(url: url)).facts == .none)
        #expect(reader.reads.withLock { $0 } == 0 && reader.opens.withLock { $0 } == 0)
    }
    @Test func geometryCarriesReadBoundaryFactsInsteadOfReusingTheLegacyField() async throws {
        let reader = Q52SizeReader(total: 500)
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            defaultBudget: .standard, geometryAdapter: { Q52GeometryAdapter() })], reader: reader)
        let outcome = await pipeline.preview(url: url)
        guard case .geometryReady(let presentation) = outcome else { Issue.record("Expected geometry"); return }
        #expect(presentation.facts.facts == [.shownSize(shown: 4, total: 500)])
        #expect(reader.reads.withLock { $0 } == 1)
        let legacy = GeometryPresentation(formatID: .plainText, mesh: presentation.mesh, byteCount: 999)
        #expect(legacy.facts == .none)
    }

    @Test func disabledInputStillStopsBeforeSizeInspection() async throws {
        let reader = Q52SizeReader()
        let pipeline = PreviewPipeline(registrations: [.init(formatID: .plainText,
            binaryAdapter: { Q52SummaryAdapter(facts: .none) })], reader: reader)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .plainText)
        #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.plainText))
        #expect(reader.reads.withLock { $0 } == 0 && reader.opens.withLock { $0 } == 0)
    }
    private func ready(_ outcome: PreviewOutcome) throws -> TextPresentation {
        guard case .ready(let p) = outcome else { throw PreviewFailure.unreadableFile }; return p
    }
}
