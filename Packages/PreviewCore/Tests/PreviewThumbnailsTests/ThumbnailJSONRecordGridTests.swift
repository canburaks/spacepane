import Foundation
import Testing
import PreviewContracts
@testable import PreviewThumbnails

@Suite("JSON record thumbnails")
struct ThumbnailJSONRecordGridTests {
    @Test func realRecordArraysDrawOnlyHeadersKindsAndExactCounts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = #"[{"id":1,"name":"Ada"},{"id":2,"note":"ordinary body value"},{"id":3}]"#
        let url = try fixture.file("records.json", source)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        guard case .grid(let grid) = scene.content else { Issue.record("Expected a value-free JSON record grid"); return }
        #expect(grid.rowCount == 3 && grid.columnCount == 3 && !grid.rowsAreLowerBound)
        #expect(grid.headers == ["id", "name", "note"])
        #expect(grid.columnKinds == [.numeric, .text, .text])
        let drawn = scene.content.drawnStrings.joined(separator: "\n")
        #expect(!drawn.contains("Ada") && !drawn.contains("ordinary body value") && !drawn.contains("records.json"))
        #expect(try Data(contentsOf: url) == Data(source.utf8))
    }

    @Test func anEmptyFirstRecordDoesNotHideLaterDocumentHeaders() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("records.json", #"[{}, {"id":1,"name":"Ada"}]"#)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        guard case .grid(let grid) = scene.content else { Issue.record("Expected record facts despite an empty first record"); return }
        #expect(grid.rowCount == 2 && grid.columnCount == 2)
        #expect(grid.headers == ["id", "name"])
        #expect(!scene.content.drawnStrings.joined().contains("Ada"))
    }

    @Test func keysBeyondTheBoundedSampleDoNotBecomeBodyTextOrInventedEmptyKinds() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = "[" + Array(repeating: "{}", count: 6).joined(separator: ",") + #",{"late":"ordinary body value"}]"#
        let url = try fixture.file("records.json", source)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        guard case .grid(let grid) = scene.content else { Issue.record("Expected counts even when the bounded sample has no fields"); return }
        #expect(grid.rowCount == 7 && grid.columnCount == 1 && grid.headers.isEmpty)
        #expect(grid.columnKinds == [.unknown])
        #expect(!scene.content.drawnStrings.joined().contains("ordinary body value"))
    }

    @Test func ambiguousOrSchemaFreeRecordsKeepTheGenericGlyphInsteadOfDrawingValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wide = "[{" + (0..<257).map { "\"field\($0)\":\"ordinary body value\"" }.joined(separator: ",") + "}]"
        for source in [#"[{"id":1,"\u0069d":2,"note":"ordinary body value"}]"#, wide, "[{},{}]"] {
            let url = try fixture.file("records.json", source)
            let outcome = await makeService().outcome(for: url, geometry: geometry(384))
            #expect(outcome.scene == nil && outcome.reason == .nothingToDraw)
        }
    }

    @Test func credentialRecordsAreStillWithheldWholeAndOrdinaryObjectsKeepTheirExistingShape() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secret = try fixture.file("records.json", #"[{"id":1,"password":"synthetic-private-value"}]"#)
        #expect(await makeService().outcome(for: secret, geometry: geometry(384)).reason == .withheldConcealedContent)
        let object = try fixture.file("ordinary.json", "{\n  \"title\": \"Demo\",\n  \"count\": 3\n}\n")
        let scene = try #require(await makeService().outcome(for: object, geometry: geometry(384)).scene)
        guard case .text = scene.content else { Issue.record("An ordinary object is not a root record grid"); return }
        #expect(scene.content.drawnStrings.joined().contains("Demo"))
    }
}
