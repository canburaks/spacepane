import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private let tablePipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
private let syntheticSecret = "synthetic-table-secret"

private struct TableFixture {
    let directory: URL
    let url: URL
    let original: Data
    init(_ data: Data, name: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        original = data
        try data.write(to: url)
    }
    init(_ text: String, name: String) throws { try self.init(Data(text.utf8), name: name) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    /// The preview must neither change the source nor leave anything beside it.
    func expectUntouched() throws {
        #expect(try Data(contentsOf: url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
    }
}

private final class TableReads: PreviewFileReading, Sendable {
    private let count = Mutex(0)
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        count.withLock { $0 += 1 }
        return FileBytes(data: Data("name,password\nx,\(syntheticSecret)\n".utf8))
    }
    var value: Int { count.withLock { $0 } }
}

/// Decoded cells of safe text, read with the grammar that the renderer shares.
private func cells(_ text: String, _ dialect: DelimitedRecords.Dialect = .comma) throws -> [[String]] {
    let bytes = Array(text.utf8)
    var result: [[String]] = []
    _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: .init(maxRecords: 100_000, maxFieldsPerRecord: 100_000, maxFieldBytes: 4_194_304),
                                  checkpoint: {}) { _, fields in
        result.append(fields.map { DelimitedRecords.text(of: $0, in: bytes) })
        return .proceed
    }
    return result
}

private func ready(_ outcome: PreviewOutcome) -> TextPresentation? {
    if case .ready(let presentation) = outcome { return presentation }
    return nil
}

@Suite("Delimited table pipeline")
struct DelimitedTablePipelineTests {
    @Test func csvSensitiveColumnIsConcealedThroughTheStandardPipelineAndShapeSurvives() async throws {
        let source = "name,password,note\r\nAda,\(syntheticSecret),\"line one\r\nline, two\"\r\nGrace,\"\(syntheticSecret)-2\",ok\r\n"
        let fixture = try TableFixture(source, name: "people.csv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.formatID == .csv)
        #expect(result.syntax == .commaSeparated)
        #expect(result.encoding == .utf8)
        #expect(!result.text.contains("synthetic-"))
        #expect(result.redactionCount == 2)
        #expect(result.text == "name,password,note\r\nAda,••••,\"line one\r\nline, two\"\r\nGrace,••••,ok\r\n")
        // The safe text still parses into the source's record/column shape, so a table can be built from it.
        #expect(try cells(result.text).map(\.count) == cells(source).map(\.count))
        #expect(try cells(result.text).map { $0[2] } == ["note", "line one\r\nline, two", "ok"])
        try fixture.expectUntouched()
    }

    @Test func tsvUsesTheSameColumnRulesAndKeepsQuotesLiteral() async throws {
        let source = "title\tpassword\tcount\n5\" pipe\t\(syntheticSecret)\t7\n\"Quoted\" word\t\(syntheticSecret)\t8\n"
        let fixture = try TableFixture(source, name: "items.tsv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.formatID == .tsv)
        #expect(result.syntax == .tabSeparated)
        #expect(result.text == "title\tpassword\tcount\n5\" pipe\t••••\t7\n\"Quoted\" word\t••••\t8\n")
        try fixture.expectUntouched()
    }

    @Test func assignmentsAndRecognizableValuesInOtherColumnsAreConcealedWithoutBreakingStructure() async throws {
        let token = "ghp_" + String(repeating: "a", count: 24)
        let source = "id,note,link\n1,password=\(syntheticSecret),https://example.com/a?b=1\n2,\"token: \(syntheticSecret), more\",\(token)\n3,fine,ok\n"
        let fixture = try TableFixture(source, name: "notes.csv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(!result.text.contains(syntheticSecret))
        #expect(!result.text.contains(token))
        #expect(try cells(result.text) == [["id", "note", "link"], ["1", "••••", "https://example.com/a?b=1"],
                                           ["2", "••••", "••••"], ["3", "fine", "ok"]])
        try fixture.expectUntouched()
    }

    @Test func formulasStayLiteralAndNothingIsEvaluatedOrCoerced() async throws {
        let source = "a,b,c\n=HYPERLINK,+1,-2\n@SUM(A1),007,1e999\n"
        let fixture = try TableFixture(source, name: "formulas.csv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
        try fixture.expectUntouched()
    }

    @Test func utf16SourcesDecodeBeforeTheAdapterAndKeepTheirEncodingInTheResult() async throws {
        let text = "name\tpassword\nuna\t\(syntheticSecret)\n"
        var data = Data([0xFF, 0xFE])
        for unit in text.utf16 { data.append(contentsOf: [UInt8(unit & 255), UInt8(unit >> 8)]) }
        let fixture = try TableFixture(data, name: "unicode.tsv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.encoding == .utf16LittleEndian)
        #expect(result.text == "name\tpassword\nuna\t••••\n")
        try fixture.expectUntouched()
    }

    @Test func utf8BOMIsConsumedByTheDecoderAndNeverBecomesPartOfTheFirstTitle() async throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        // Three columns: a two-column first record is also read as a possible key/value pair.
        data.append(Data("password,x,y\n\(syntheticSecret),1,2\n".utf8))
        let fixture = try TableFixture(data, name: "bom.csv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.text == "password,x,y\n••••,1,2\n")
        try fixture.expectUntouched()
    }

    @Test func structuralFailuresNeverFallBackToUnconcealedSource() async throws {
        for (name, source) in [("unterminated.csv", "name,password\nx,\"\(syntheticSecret)\n"),
                               ("stray.csv", "name,password\nx,pass\"word\(syntheticSecret)\n"),
                               ("quoted.tsv", "name\tpassword\nx\t\"\(syntheticSecret)\nmore\"\n")] {
            let fixture = try TableFixture(source, name: name)
            defer { fixture.remove() }
            #expect(await tablePipeline.preview(url: fixture.url) == .unavailable(.malformedDocument), "\(name)")
            try fixture.expectUntouched()
        }
    }

    @Test func emptyFilesAreReadyEmptyTables() async throws {
        let fixture = try TableFixture("", name: "empty.csv")
        defer { fixture.remove() }
        let result = try #require(ready(await tablePipeline.preview(url: fixture.url)))
        #expect(result.text.isEmpty)
        #expect(result.redactionCount == 0)
    }

    @Test func requestBudgetsApplyAcrossTheWholePipeline() async throws {
        let source = "a,password\n1,x\n2,y\n3,z\n"
        let fixture = try TableFixture(source, name: "budget.csv")
        defer { fixture.remove() }
        #expect(await tablePipeline.preview(url: fixture.url, budget: PreviewBudget(maxInputBytes: 8)) == .unavailable(.inputTooLarge))
        #expect(await tablePipeline.preview(url: fixture.url, budget: PreviewBudget(maxTextLines: 3)) == .unavailable(.tooManyLines))
        #expect(await tablePipeline.preview(url: fixture.url, budget: PreviewBudget(maxJSONNodes: 2)) == .unavailable(.tooManyNodes))
        #expect(await tablePipeline.preview(url: fixture.url, budget: PreviewBudget(maxLineUTF8Bytes: 8)) == .unavailable(.lineTooLong))
        try fixture.expectUntouched()
    }

    @Test func disabledTypesNeverReadOrFallBackToText() async {
        let reads = TableReads()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: reads)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .csv)
        let csv = URL(fileURLWithPath: "/unused/table.csv")
        #expect(await pipeline.preview(url: csv, preferences: preferences) == .disabledByUser(.csv))
        #expect(reads.value == 0)
        // CSV and TSV are independent logical types even though they share an adapter.
        guard case .ready = await pipeline.preview(url: URL(fileURLWithPath: "/unused/table.tsv"), preferences: preferences) else {
            Issue.record("Disabling CSV must not disable TSV")
            return
        }
        #expect(reads.value == 1)
    }

    @Test func cancellationPrecedesSourceAccess() async {
        let reads = TableReads()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: reads)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.preview(url: URL(fileURLWithPath: "/unused/table.csv"))
        }
        #expect(await task.value == .cancelled)
        #expect(reads.value == 0)
    }

    /// The structured cell rule replaces the line heuristic, so it must classify like that heuristic.
    @Test(arguments: [
        "password=abc", "Password: abc", "'api_key' = x", "\"token\": \"x\"", "export SECRET_KEY=abc", "db.password=hunter2",
        "a.b-c_token : x", "client_secret=x y z", "tokens=5", "my-token-count: 3", "note then password=abc",
        "note: hello", "12:30:00", "key=value", "https://example.com/x", "pass word=abc", "passphrase=abc", "a=b", "x = y"
    ])
    func sensitiveAssignmentRuleMatchesTheLineHeuristic(cell: String) throws {
        let context = RequestContext(budget: .standard)
        let heuristic = try DefaultPrivacyFilter().filter(ParsedTextDocument(text: cell), context: context)
        let quoted = "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let source = "h\n\(quoted)\n"
        let parsed = try DelimitedTextAdapter(dialect: .comma).parse(
            DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        #expect(parsed.sensitiveRanges.isEmpty == (heuristic.redactionCount == 0), "cell: \(cell)")
    }
}
