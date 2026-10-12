import Foundation
import Testing
import PreviewContracts
@testable import PreviewThumbnails

@Suite("Markdown thumbnails")
struct ThumbnailMarkdownTests {
    @Test func aHeadingThenBodyText() throws {
        let text = "# Project Title\n\nA short paragraph with **bold** and `code` and a [link](https://example.invalid/x).\n\n- first\n- second\n"
        let page = try #require(ThumbnailMarkdown.page(from: text, syntax: .markdown, metrics: metrics(384)))
        #expect(page.lines[0].emphasis == .heading)
        #expect(page.lines[0].text == "Project Title")
        let body = page.lines.dropFirst().map(\.text).joined(separator: "\n")
        #expect(body.contains("A short paragraph with bold and code and a link."))
        #expect(!body.contains("**") && !body.contains("`") && !body.contains("example.invalid"))
        #expect(body.contains("• first") && body.contains("• second"))
    }

    @Test func frontMatterFencesAndRulesAreSkipped() throws {
        let text = "---\ntitle: hidden metadata\n---\n# Visible\n```\ncode line\n```\n---\ntext\n"
        let page = try #require(ThumbnailMarkdown.page(from: text, syntax: .markdown, metrics: metrics(384)))
        let drawn = page.lines.map(\.text)
        #expect(!drawn.contains { $0.contains("hidden metadata") })
        #expect(drawn.contains("Visible") && drawn.contains("code line") && drawn.contains("text"))
        #expect(!drawn.contains { $0.contains("```") || $0 == "---" })
    }

    @Test func taskListsQuotesAndImages() throws {
        let text = "- [ ] open\n- [x] done\n> quoted\n![alt text](https://example.invalid/i.png)\n"
        let page = try #require(ThumbnailMarkdown.page(from: text, syntax: .markdown, metrics: metrics(384)))
        let drawn = page.lines.map(\.text)
        #expect(drawn.contains { $0.contains("☐ open") })
        #expect(drawn.contains { $0.contains("☑ done") })
        #expect(drawn.contains { $0.hasPrefix("│ ") && $0.contains("quoted") })
        #expect(drawn.contains("alt text"))
    }

    @Test func rowCostNeverExceedsThePage() throws {
        let m = metrics(128)
        let text = (0..<40).map { "## Heading \($0)\nparagraph \($0)" }.joined(separator: "\n")
        let page = try #require(ThumbnailMarkdown.page(from: text, syntax: .markdown, metrics: m))
        #expect(page.lines.reduce(0) { $0 + $1.rowCost } <= Double(m.rows) + 0.001)
    }

    @Test func otherMarkupsUseTheirHeadingMarker() throws {
        let org = try #require(ThumbnailMarkdown.page(from: "* Org heading\nbody", syntax: .orgMode, metrics: metrics()))
        #expect(org.lines[0].emphasis == .heading && org.lines[0].text == "Org heading")
        let ascii = try #require(ThumbnailMarkdown.page(from: "= Doc\n\ntext", syntax: .asciidoc, metrics: metrics()))
        #expect(ascii.lines[0].emphasis == .heading)
        #expect(ThumbnailMarkdown.page(from: "x", syntax: .plain, metrics: metrics()) == nil)
    }

    @Test func inlineCleaningKeepsLoneUnderscoresInWords() {
        let cleaned = ThumbnailCells.string(ThumbnailMarkdown.clean(Array("snake_case and __bold__ ~~gone~~".unicodeScalars)))
        #expect(cleaned == "snake_case and bold gone")
    }
}

@Suite("JSON outline thumbnails")
struct ThumbnailJSONOutlineTests {
    @Test func minifiedJSONBecomesAnOutline() throws {
        let text = #"{"name":"demo","version":"1.0.0","scripts":{"build":"tsc","test":"vitest"},"private":true,"count":3,"tags":["a","b"]}"#
        #expect(ThumbnailJSONOutline.prefersOutline(text: text, lineCount: 1, columns: 20))
        let page = try #require(ThumbnailJSONOutline.page(from: text, metrics: metrics(384)))
        let drawn = page.lines.map(\.text)
        #expect(drawn.contains("name: \"demo\""))
        #expect(drawn.contains("scripts:"))
        #expect(drawn.contains("private: true"))
        #expect(drawn.contains("count: 3"))
        // Nesting is the line's indent, in cells.
        let build = try #require(page.lines.first { $0.text == "build: \"tsc\"" })
        #expect(build.indent == 2)
        let tag = try #require(page.lines.first { $0.text == "- \"a\"" })
        #expect(tag.indent == 2)
        #expect(page.lines.first { $0.text == "name: \"demo\"" }?.indent == 0)
    }

    @Test func arraysOfObjectsCarryTheDashOnTheFirstMember() throws {
        let page = try #require(ThumbnailJSONOutline.page(from: #"[{"id":1,"name":"Ada"},{"id":2,"name":"Bob"}]"#, metrics: metrics(384)))
        #expect(Array(page.lines.map(\.text).prefix(4)) == ["- id: 1", "name: \"Ada\"", "- id: 2", "name: \"Bob\""])
        #expect(Array(page.lines.map(\.indent).prefix(4)) == [0, 2, 0, 2])
    }

    @Test func deepContainersCollapse() throws {
        let page = try #require(ThumbnailJSONOutline.page(from: #"{"a":{"b":{"c":{"d":{"e":1}}}}}"#, metrics: metrics(384)))
        #expect(page.lines.map(\.text).contains { $0.contains("{…}") })
        let empty = try #require(ThumbnailJSONOutline.page(from: #"{"o":{},"a":[]}"#, metrics: metrics(384)))
        #expect(empty.lines.map(\.text) == ["o: {}", "a: []"])
    }

    @Test func escapesAreFlattenedToOneLine() throws {
        let page = try #require(ThumbnailJSONOutline.page(from: #"{"t":"a\nb\t\"q\" é"}"#, metrics: metrics(384)))
        #expect(page.lines[0].text == "t: \"a b \"q\" é\"")
    }

    @Test func longValuesAreClippedWithAnEllipsis() throws {
        let m = metrics(128)
        let page = try #require(ThumbnailJSONOutline.page(from: "{\"k\":\"\(String(repeating: "v", count: 500))\"}", metrics: m))
        #expect(ThumbnailCells.width(of: page.lines[0].text.unicodeScalars) <= m.columns)
        #expect(page.lines[0].text.hasSuffix("…"))
    }

    @Test func notExactlyOneValueIsNotAnOutline() {
        #expect(ThumbnailJSONOutline.page(from: "{\"a\":1}\n{\"a\":2}\n", metrics: metrics()) == nil)
        #expect(ThumbnailJSONOutline.page(from: "{\"a\":", metrics: metrics()) == nil)
        #expect(ThumbnailJSONOutline.page(from: "{\"a\" 1}", metrics: metrics()) == nil)
        #expect(ThumbnailJSONOutline.page(from: "", metrics: metrics()) == nil)
        #expect(ThumbnailJSONOutline.page(from: "[1,,2]", metrics: metrics()) == nil)
    }

    @Test func scanningStopsOncePageIsFull() throws {
        let m = metrics(128)
        let items = (0..<200_000).map(String.init).joined(separator: ",")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            #expect(ThumbnailJSONOutline.page(from: "[\(items)]", metrics: m)?.lines.count == m.rows)
        }
        #expect(elapsed < .seconds(2))
    }

    @Test func prettyPrintedJSONKeepsItsOwnLines() {
        let pretty = "{\n  \"a\": 1,\n  \"b\": 2\n}"
        #expect(!ThumbnailJSONOutline.prefersOutline(text: pretty, lineCount: 4, columns: 20))
    }
}

@Suite("Grid thumbnail probes")
struct ThumbnailTableTests {
    private func grid(_ text: String, rows: Int, columns: Int, syntax: TextSyntax = .commaSeparated) -> ThumbnailGrid? {
        let presentation = TextPresentation(formatID: syntax == .commaSeparated ? .csv : .tsv, text: text,
            lineCount: 1, byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax,
            facts: PresentationFacts([.grid(rows: rows, columns: columns, rowsAreLowerBound: false)]))
        return ThumbnailGridBuilder.grid(for: presentation, metrics: metrics(384))
    }

    @Test func quotedCSVProducesKindsWithoutCellValues() throws {
        let shape = try #require(grid("id,name,note\n1,\"Ada, Countess\",\"line\nbreak\"\n2,Bob,plain\n", rows: 2, columns: 3))
        #expect(shape.headers == ["id", "name", "note"])
        #expect(shape.columnKinds == [.numeric, .text, .text])
        #expect(ThumbnailContent.grid(shape).drawnStrings == ["id", "name", "note", shape.countLine])
    }

    @Test func sampleCapsDoNotChangeSourceCounts() throws {
        let header = (0..<30).map { "c\($0)" }.joined(separator: "\t")
        let rows = (0..<500).map { r in (0..<30).map { "v\(r)_\($0)" }.joined(separator: "\t") }
        let shape = try #require(grid(([header] + rows).joined(separator: "\n"), rows: 500, columns: 30, syntax: .tabSeparated))
        #expect(shape.headers.count == 8 && shape.columnKinds.count == 8 && shape.sampleRowCount == 6)
        #expect(shape.columnCount == 30 && shape.rowCount == 500)
    }

    @Test func longBodyValuesAreNeverPartOfTheShape() throws {
        let value = String(repeating: "w", count: 900)
        let shape = try #require(grid("a,b\n\(value),x\n", rows: 1, columns: 2))
        #expect(!ThumbnailContent.grid(shape).drawnStrings.joined().contains(value))
        #expect(shape.columnKinds == [.text, .text])
    }

    @Test func raggedAndEmptyCellsHaveHonestKinds() throws {
        let shape = try #require(grid("a,b,c\n1\n2,,x\n", rows: 2, columns: 3))
        #expect(shape.columnKinds == [.numeric, .empty, .text])
    }

    @Test func singleColumnAndHeaderOnlyDocumentsHaveShapes() throws {
        let shape = try #require(grid("only\none\ntwo\n", rows: 2, columns: 1))
        #expect(shape.columnCount == 1)
        let empty = try #require(grid("a,b\n", rows: 0, columns: 2))
        #expect(empty.rowCount == 0 && empty.columnKinds == [.unknown, .unknown])
    }

    @Test func malformedProbeWithoutACompleteRecordYieldsNothing() {
        #expect(grid("\"unterminated,field\n", rows: 1, columns: 2) == nil)
        #expect(grid("", rows: 0, columns: 2) == nil)
    }

    @Test func autoDetectedPlainTextGridsAlsoDropCellValues() throws {
        let text = "name\tqty\tprice\napple\t3\t1.20\npear\t5\t0.80\nplum\t9\t2.10\n"
        let shape = try #require(ThumbnailGridBuilder.tabSeparatedGrid(fromPlainText: text, metrics: metrics(384)))
        #expect(shape.headers.isEmpty)
        #expect(shape.rowCount == 4 && !shape.rowsAreLowerBound)
        #expect(!ThumbnailContent.grid(shape).drawnStrings.joined().contains("apple"))
    }

    @Test func ordinaryTabsAreNotTreatedAsGrids() {
        for text in ["just prose\nwith no\ncolumns\n", "\tindented\n\tcode\n\tblock\n", "a\tb\nc\n",
                     "a\tb\nc\td\nplain line\nanother plain\nx\ty\n"] {
            #expect(ThumbnailGridBuilder.tabSeparatedGrid(fromPlainText: text, metrics: metrics()) == nil)
        }
    }

    @Test func headersBecomeOneBoundedVisibleLine() {
        #expect(ThumbnailGridText.cell("  a\tb\nc  ") == "a b c")
        #expect(ThumbnailGridText.cell(String(repeating: "z", count: 500)).count == 64)
    }
}

@Suite("Structured presentations")
struct ThumbnailStructuredShapeTests {
    private let databaseJSON = """
    {"databaseFormat":"SQLite","pages":[
      {"table":"empty","columns":["a"],"rows":[]},
      {"table":"people","columns":["id","name","photo","note"],"rows":[
        {"id":{"value":"1","sourceType":"integer"},"name":{"value":"Ada","sourceType":"text"},"photo":{"blobBytes":2048},"note":null},
        {"id":{"value":"2","sourceType":"integer"},"name":{"value":"Bob","sourceType":"text"},"photo":{"blobBytes":9},"note":{"value":"hi","sourceType":"text"}}]}]}
    """

    private func databaseGrid(_ text: String) -> ThumbnailGrid? {
        let presentation = TextPresentation(formatID: .sqlite, text: text, lineCount: 1, byteCount: text.utf8.count,
            encoding: .utf8, redactionCount: 0, syntax: .json, origin: .summary,
            facts: PresentationFacts([.grid(rows: 2, columns: 4, rowsAreLowerBound: false)]))
        return ThumbnailGridBuilder.grid(for: presentation, metrics: metrics(384))
    }

    @Test func databaseGridUsesTheFirstTableWithRowsWithoutItsValues() throws {
        let grid = try #require(databaseGrid(databaseJSON))
        #expect(grid.headers == ["id", "name", "photo", "note"])
        #expect(grid.columnKinds == [.numeric, .text, .unknown, .text])
        #expect(!ThumbnailContent.grid(grid).drawnStrings.joined().contains("Ada"))
    }

    @Test func aDatabaseShapeMismatchDrawsNothing() {
        for text in ["{\"x\":1}", "not json", "{\"pages\":[]}"] { #expect(databaseGrid(text) == nil) }
    }

    @Test func notebookCellsBecomeHeadingProseAndCode() throws {
        let notebook = """
        {"cells":[
          {"cell_type":"markdown","source":["# Analysis\\n","Some intro text."]},
          {"cell_type":"code","source":"import numpy as np\\nvalue = 1  # note","outputs":[{"data":{"text/plain":"OUTPUT-NOT-DRAWN"}}]},
          {"cell_type":"raw","source":"raw"}],"metadata":{},"nbformat":4}
        """
        let page = try #require(ThumbnailStructuredShapes.notebookPage(from: notebook, metrics: metrics(384)))
        let drawn = page.lines.map(\.text)
        #expect(drawn.first == "Analysis")
        #expect(drawn.contains("Some intro text."))
        #expect(drawn.contains("import numpy as np"))
        #expect(!drawn.joined().contains("OUTPUT-NOT-DRAWN"))
        #expect(page.lines.reduce(0) { $0 + $1.rowCost } <= Double(metrics(384).rows))
    }

    @Test func aNotebookShapeMismatchDrawsNothing() {
        #expect(ThumbnailStructuredShapes.notebookPage(from: "{\"cells\":[]}", metrics: metrics()) == nil)
        #expect(ThumbnailStructuredShapes.notebookPage(from: "[1]", metrics: metrics()) == nil)
    }
}
