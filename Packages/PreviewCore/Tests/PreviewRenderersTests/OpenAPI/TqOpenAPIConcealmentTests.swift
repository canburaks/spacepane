import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewRenderers

/// The endpoint table reads only concealed text (tier 1 item 5, workstream tq-openapi): a recognizable credential in a
/// summary reaches the table only as the concealment token, and the source file on disk is never read again for it.
@Suite("OpenAPI endpoint concealment", .serialized)
struct TqOpenAPIConcealmentTests {
    /// Synthetic: the same shape the privacy policy's cloud-key recognizer accepts (see SecretInventoryTests).
    private static let cloudKey = "AKIAABCDEFGHIJKLMNOP"

    @Test @MainActor func aCredentialInASummaryNeverReachesTheEndpointTable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tq-openapi-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("openapi.json")
        let spec = #"{"openapi": "3.0.3", "paths": {"/keys": {"post": {"summary": "Rotate AKIAABCDEFGHIJKLMNOP now", "operationId": "rotateKey"}}}}"#
        try Data(spec.utf8).write(to: file)

        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        let outcome = await pipeline.preview(url: file, budget: PreviewBudget(maxMilliseconds: 30_000))
        guard case .ready(let presentation) = outcome else {
            Issue.record("The synthetic specification did not preview: \(outcome)")
            return
        }
        #expect(presentation.syntax == .json)
        #expect(presentation.redactionCount > 0)
        #expect(!presentation.text.contains(Self.cloudKey))

        let modes = SafePreviewModes(presentation, locale: Locale(identifier: "en_US"))
        let endpoints = try #require(modes.endpoints)
        let cells = endpoints.table.rows.flatMap { $0 }
        #expect(!cells.contains { $0.contains(Self.cloudKey) })
        #expect(cells.contains { $0.contains(SecretFieldPolicy.concealmentToken) })
        #expect(endpoints.table.rows.count == 1)
    }
}
