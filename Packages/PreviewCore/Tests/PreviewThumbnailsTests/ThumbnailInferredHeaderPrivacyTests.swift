import Foundation
import Testing
@testable import PreviewThumbnails

@Suite("Inferred grids have no header provenance")
struct ThumbnailInferredHeaderPrivacyTests {
    @Test func ordinaryFirstRowValuesNeverBecomeHeadersAndCountAsARecord() throws {
        let source = "1\tAda\n2\tBob\n3\tCal\n"
        let grid = try #require(ThumbnailGridBuilder.tabSeparatedGrid(fromPlainText: source,
            metrics: ThumbnailMetrics(geometry: geometry(384)), locale: Locale(identifier: "en_US")))
        #expect(grid.headers.isEmpty)
        #expect(grid.rowCount == 3 && grid.columnCount == 2 && !grid.rowsAreLowerBound)
        #expect(grid.countLine == "2 × 3")
        #expect(ThumbnailContent.grid(grid).drawnStrings == [grid.countLine])
    }

    @Test func textualFirstRowsStillHaveNoProvenHeaderMeaning() throws {
        let source = "name\tquantity\nAda\t2\nBob\t3\n"
        let grid = try #require(ThumbnailGridBuilder.tabSeparatedGrid(fromPlainText: source,
            metrics: ThumbnailMetrics(geometry: geometry(384))))
        #expect(grid.headers.isEmpty && grid.rowCount == 3)
        #expect(grid.columnKinds == [.text, .text], "All sampled records participate; no first record is silently excluded")
    }

    @Test func theRealPipelineSeparatesInferredRowsFromTheCSVHeaderConvention() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (name, source, expectedRows, expectedHeaders) in [
            ("ordinary.txt", "name\tquantity\nAda\t2\nBob\t3\n", 3, [String]()),
            ("ordinary.csv", "name,quantity\nAda,2\nBob,3\n", 2, ["name", "quantity"]),
            ("ordinary.tsv", "name\tquantity\nAda\t2\nBob\t3\n", 2, ["name", "quantity"])
        ] {
            let url = try fixture.file(name, source)
            let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene, "\(name)")
            guard case .grid(let grid) = scene.content else { Issue.record("Expected a grid for \(name)"); continue }
            #expect(grid.rowCount == expectedRows && grid.headers == expectedHeaders, "\(name)")
            #expect(!scene.content.drawnStrings.joined().contains("Ada") && !scene.content.drawnStrings.joined().contains("Bob"))
            #expect(try Data(contentsOf: url) == Data(source.utf8))
        }
    }

    @Test func aRecognizedGridRefusedByItsFieldBudgetNeverFallsBackToDrawingBodyValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = "1\t" + String(repeating: "v", count: 5_000) + "\n2\tBob\n3\tCal\n"
        let url = try fixture.file("ordinary.txt", source)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene == nil && outcome.reason == .nothingToDraw)
        #expect(try Data(contentsOf: url) == Data(source.utf8))
    }
}
