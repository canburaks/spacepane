import Foundation
import Testing
import PreviewContracts
import PreviewCore
@testable import PreviewThumbnails

@Suite("Q153 classification thumbnail refusal")
struct Q153ClassificationThumbnailTests {
    @Test(arguments: [PreviewFailure.unavailableContent, .missingFile])
    func typedInspectionFailureUsesExistingGlyph(failure: PreviewFailure) {
        #expect(ThumbnailPolicyEvaluator.resolve(.unavailable(failure)) == .fallback(.unavailable))
    }

    @Test func actualMissingUnknownClassificationStopsBeforeContentWork() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("absent.unknown-type")
        let reads = Counter(), factories = Counter(), parses = Counter()
        let pipeline = PreviewPipeline(registrations: [])
        let inspection = await pipeline.inspect(url: url)
        #expect(inspection == .unavailable(.missingFile))
        #expect(ThumbnailPolicyEvaluator.resolve(inspection) == .fallback(.unavailable))
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let service = ContentThumbnailService(registrations: [AdapterRegistration(formatID: .plainText) {
            factories.increment(); return Q153ThumbnailAdapter(parses: parses)
        }], preferences: .fixed(.defaults), reader: SpyReader(reads: reads), admission: admission)
        #expect(await service.result(for: url, geometry: standardGeometry).outcome.reason == .unavailable)
        #expect(reads.value == 0 && factories.value == 0 && parses.value == 0)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }
}
private struct Q153ThumbnailAdapter: FormatAdapter {
    let parses: Counter
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        parses.increment(); return ParsedTextDocument(text: input.text)
    }
}
