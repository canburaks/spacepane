import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
import SQLite3
import PreviewTestSupport
@testable import PreviewThumbnails

private func makeGridDatabase(_ url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw CocoaError(.fileWriteUnknown) }
    defer { sqlite3_close(database) }
    let sql = "CREATE TABLE people(id INTEGER, name TEXT, note TEXT); INSERT INTO people VALUES (1,'Ada','first'),(2,'Bob',NULL);"
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
}

@Suite("Value-free grid thumbnails")
struct ThumbnailGridShapeTests {
    @Test func realCSVAndTSVDrawHeadersAndCountsButNeverOrdinaryCellValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (suffix, separator) in [("csv", ","), ("tsv", "\t")] {
            let text = ["id\(separator)name\(separator)note", "1\(separator)Ada\(separator)private customer detail",
                        "2\(separator)Bob\(separator)another customer detail"].joined(separator: "\n") + "\n"
            let url = try fixture.file("ordinary.\(suffix)", text)
            let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
            let drawn = scene.content.drawnStrings.joined(separator: "\n")
            #expect(!drawn.contains("Ada") && !drawn.contains("Bob") && !drawn.contains("customer detail"))
            #expect(drawn.contains("id") && drawn.contains("name"))
            // Symbol-only count line is locale formatted; no cell data or app schema keys.
            #expect(drawn.contains("3 × 2"))
        }
    }

    @Test func aRealSQLitePageBecomesAShapeWithoutTableNamesOrCellValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("ordinary.sqlite")
        try makeGridDatabase(url)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        let drawn = scene.content.drawnStrings.joined(separator: "\n")
        #expect(!drawn.contains("Ada") && !drawn.contains("Bob") && !drawn.contains("people"))
        #expect(!drawn.contains("databaseFormat") && !drawn.contains("sourceReadOnly"))
        #expect(drawn.contains("3 × 2"))
    }

    @Test func credentialBearingGridStillWithholdsBeforeShapeDerivation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("ordinary.csv", "name,password\nAda,synthetic-private-value\n")
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene == nil)
        #expect(outcome.reason == .withheldConcealedContent)
    }

    @Test func realDataAdaptersDrawSourceCountsWithoutMetadataOrBodyValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        func ordinaryMetadata(_ source: Data) -> Data {
            var data = source
            for (key, replacement) in [("api_key", "comment"), ("password", "ordinary")] {
                while let range = data.range(of: Data(key.utf8)) {
                    data.replaceSubrange(range, with: Data(replacement.utf8))
                }
            }
            return data
        }
        for (name, bytes, columns, rows) in [
            ("ordinary.arrow", ordinaryMetadata(DataFixtures.arrowFile), 5, 7),
            ("ordinary.parquet", ordinaryMetadata(DataFixtures.parquet), 4, 3),
            ("ordinary.avro", ordinaryMetadata(DataFixtures.avro), 8, 3),
            ("ordinary.npy", DataFixtures.numpy, 4, 3)
        ] {
            let url = try fixture.file(name, bytes)
            let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene, "\(name)")
            guard case .grid(let grid) = scene.content else { Issue.record("Expected value-free data grid: \(name)"); continue }
            #expect(grid.columnCount == columns && grid.rowCount == rows, "\(name)")
            let drawn = scene.content.drawnStrings.joined(separator: "\n")
            #expect(!drawn.contains(DataFixtures.secret) && !drawn.contains("dataFormat") && !drawn.contains("formatVersion"), "\(name)")
            #expect(try Data(contentsOf: url) == bytes, "The thumbnail must not modify its source")
            if name.hasSuffix("arrow") || name.hasSuffix("parquet") || name.hasSuffix("npy") {
                #expect(grid.headers.isEmpty, "Technical schema labels have no document-header provenance")
            }
        }
    }

    @Test func sqliteRowProbeMarksItsCountAsALowerBoundWithoutAFullCountScan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("ordinary.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        let handle = try #require(database)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TABLE t(id INTEGER); WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<205) INSERT INTO t SELECT x FROM n;", nil, nil, nil) == SQLITE_OK)
        let before = try Data(contentsOf: url)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        guard case .grid(let grid) = scene.content else { Issue.record("Expected bounded SQLite grid"); return }
        #expect(grid.rowCount == 200 && grid.rowsAreLowerBound)
        #expect(grid.countLine.contains("200+"))
        #expect(grid.tableCount == 1)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test(arguments: [("en_US", "1,204"), ("de_DE", "1.204"), ("tr_TR", "1.204"), ("hi_IN", "1,204")])
    func countsUsePresentationLocaleAndRetainLowerBounds(identifier: String, expected: String) throws {
        let grid = try #require(ThumbnailGrid(headers: [], columnKinds: [.numeric], rowCount: 1_204,
            columnCount: 8, rowsAreLowerBound: true, sampleRowCount: 6, tableCount: 3,
            tablesAreLowerBound: true, locale: Locale(identifier: identifier)))
        #expect(grid.countLine == "8 × \(expected)+ · ⊞ 3+")
    }

    @Test func shapesRejectInvalidCountsAndBoundEveryDrawableHeader() throws {
        #expect(ThumbnailGrid(headers: [], columnKinds: [], rowCount: -1, columnCount: 1,
                              rowsAreLowerBound: false, sampleRowCount: 0) == nil)
        #expect(ThumbnailGrid(headers: [], columnKinds: [], rowCount: 1, columnCount: 0,
                              rowsAreLowerBound: false, sampleRowCount: 0) == nil)
        let grid = try #require(ThumbnailGrid(headers: Array(repeating: "h\u{202E}" + String(repeating: "x", count: 300), count: 30),
            columnKinds: Array(repeating: .numeric, count: 30), rowCount: 5_000, columnCount: 30,
            rowsAreLowerBound: false, sampleRowCount: 10_000))
        #expect(grid.headers.count == 8 && grid.columnKinds.count == 8 && grid.sampleRowCount == 6)
        #expect(grid.headers.allSatisfy { ThumbnailCells.width(of: $0.unicodeScalars) <= 16 && !$0.contains("\u{202E}") })
    }

    @Test func aPartialPlainTabProbeMarksBothColumnAndRowLowerBounds() throws {
        let rows = ["a\tb", "1\ttext", "2\ttext", Array(repeating: "text", count: 9).joined(separator: "\t")]
            + (3..<30).map { "\($0)\ttext" }
        let grid = try #require(ThumbnailGridBuilder.tabSeparatedGrid(fromPlainText: rows.joined(separator: "\n"),
            metrics: ThumbnailMetrics(geometry: geometry(384)), locale: Locale(identifier: "en_US")))
        #expect(grid.countLine == "9+ × 6+")
    }

    @Test func opaqueValuesAreUnknownKindsRatherThanInventedTextOrEmptyCells() throws {
        for (format, text, columns, expected) in [
            (FormatID.sqlite, "{\"pages\":[{\"columns\":[\"photo\",\"note\"],\"rows\":[{\"photo\":{\"blobBytes\":8},\"note\":null}]}]}", 2,
             [ThumbnailGrid.ColumnKind.unknown, .empty]),
            (FormatID.json, "[{\"empty\":null,\"flag\":true,\"opaque\":{\"bytes\":12}}]", 3,
             [ThumbnailGrid.ColumnKind.empty, .unknown, .unknown])
        ] {
            let presentation = TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: text.utf8.count,
                encoding: .utf8, redactionCount: 0, syntax: .json,
                facts: PresentationFacts([.grid(rows: 1, columns: columns, rowsAreLowerBound: false)]))
            let grid = try #require(ThumbnailGridBuilder.grid(for: presentation, metrics: ThumbnailMetrics(geometry: geometry(384))))
            #expect(grid.columnKinds == expected)
        }
    }
}
