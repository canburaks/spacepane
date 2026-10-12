import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

private final class FactsReader: PreviewFileReading, Sendable {
    let reads = Mutex(0)
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.withLock { $0 += 1 }
        return FileBytes(data: Data("ignored synthetic input".utf8))
    }
}

private struct FactsAdapter: BinaryFormatAdapter {
    let document: ParsedTextDocument
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument { document }
}

@Suite("Value-free parser facts")
struct PresentationFactsPipelineTests {
    @Test func parserFactsSurviveConcealmentWithoutAdditionalSourceReads() async throws {
        let reader = FactsReader()
        let facts = PresentationFacts([.grid(rows: 12, columns: 3, rowsAreLowerBound: true)])
        let document = ParsedTextDocument(text: "password=synthetic-private-value\n", facts: facts)
        let pipeline = PreviewPipeline(registrations: [
            .init(formatID: .plainText, binaryAdapter: { FactsAdapter(document: document) })
        ], reader: reader)
        let result = await pipeline.preview(url: URL(fileURLWithPath: "/unused/facts.txt"))
        guard case .ready(let presentation) = result else { Issue.record("Expected safe text"); return }
        #expect(presentation.facts == facts)
        #expect(!presentation.text.contains("synthetic-private-value"))
        #expect(presentation.redactionCount == 1)
        #expect(reader.reads.withLock { $0 } == 1)
    }

    @Test func oldModelInitializersKeepEmptyFactsAndFactsInvalidateDisplay() {
        let document = ParsedTextDocument(text: "ordinary")
        #expect(document.facts == .none)
        func presentation(_ text: String, facts: PresentationFacts = .none) -> TextPresentation {
            TextPresentation(formatID: .plainText, text: text, lineCount: 1, byteCount: 8,
                             encoding: .utf8, redactionCount: 0, facts: facts)
        }
        #expect(presentation("ordinary").facts == .none)
        #expect(presentation("ordinary") != presentation("ordinary", facts: PresentationFacts([.lines(1)])))
        #expect(presentation("\u{00e9}") != presentation("e\u{0301}"), "Facts must not weaken code-unit equality")
    }

    @Test func disabledRequestsNeverReadToDiscoverFacts() async {
        let reader = FactsReader()
        let pipeline = PreviewPipeline(registrations: [
            .init(formatID: .plainText, binaryAdapter: { FactsAdapter(document: ParsedTextDocument(text: "ordinary")) })
        ], reader: reader)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .plainText)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/facts.txt"), preferences: preferences) == .disabledByUser(.plainText))
        #expect(reader.reads.withLock { $0 } == 0)
    }
}
