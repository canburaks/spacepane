import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct PartialFixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    func file(_ name: String, _ text: String) throws -> URL { try file(name, Data(text.utf8)) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let partialPipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
private func budget(_ bytes: Int, lines: Int = 20_000, line: Int = 32_768) -> PreviewBudget {
    PreviewBudget(maxInputBytes: bytes, maxTextLines: lines, maxLineUTF8Bytes: line)
}
private func ready(_ outcome: PreviewOutcome) -> TextPresentation? {
    if case .ready(let presentation) = outcome { return presentation }
    return nil
}
/// "line 00\n" style lines, each exactly `width` bytes.
private func lines(_ count: Int, width: Int = 10, terminator: String = "\n") -> String {
    (0..<count).map { index in
        let body = "line \(index)"
        return body + String(repeating: "x", count: max(0, width - terminator.utf8.count - body.utf8.count)) + terminator
    }.joined()
}

@Suite("Partial previews of large line-oriented text")
struct PartialReadPipelineTests {
    @Test func plainTextOverTheBudgetShowsItsLeadingCompleteLinesAndReportsTheFullSize() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let source = lines(100)                       // 1,000 bytes
        let url = try fixture.file("big.txt", source)
        let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(95))))
        // 95 bytes hold nine 10-byte lines and half of the tenth.
        #expect(result.text == String(source.prefix(90)))
        #expect(result.byteCount == 90 && result.truncatedSourceBytes == 1_000)
        #expect(result.lineCount == 10 && !result.isReformatted)
        #expect(try Data(contentsOf: url) == Data(source.utf8))
    }

    @Test func aFileThatFitsIsNotMarkedTruncatedAndOneByteOverIs() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file("fit.txt", lines(10))
        let exact = try #require(ready(await partialPipeline.preview(url: url, budget: budget(100))))
        #expect(exact.truncatedSourceBytes == nil && exact.byteCount == 100)
        let over = try #require(ready(await partialPipeline.preview(url: url, budget: budget(99))))
        #expect(over.truncatedSourceBytes == 100 && over.byteCount == 90)
    }

    @Test(arguments: ["\r\n", "\r", "\n"]) func theCutFollowsEveryLineTerminator(terminator: String) async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let source = lines(50, width: 10, terminator: terminator)
        let url = try fixture.file("a.log", source)
        let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(45))))
        #expect(result.text.hasSuffix(terminator))
        #expect(source.hasPrefix(result.text))
        #expect(result.truncatedSourceBytes == 500)
        // A cut that lands between CR and LF keeps the CR as a complete line ending.
        let split = try fixture.file("split.txt", "ab\r\ncd\r\nef")
        let half = try #require(ready(await partialPipeline.preview(url: split, budget: budget(8))))
        #expect(half.text == "ab\r\ncd\r\n")
    }

    @Test func utf8CutsNeverSplitAMultiByteScalar() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        // Every line is "日本語\n" = 10 bytes; a cut inside a character must fall back to a line end.
        let source = String(repeating: "日本語\n", count: 40)
        let url = try fixture.file("jp.txt", source)
        for limit in 31...39 {
            let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(limit))), "limit \(limit)")
            #expect(result.text == String(repeating: "日本語\n", count: 3), "limit \(limit)")
        }
    }

    @Test(arguments: [true, false]) func utf16TextCutsAtWholeUnitsAfterATerminator(littleEndian: Bool) async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let text = String(repeating: "a😀b\n", count: 30)     // supplementary character: a surrogate pair per line
        var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
        for unit in text.utf16 { data.append(contentsOf: littleEndian ? [UInt8(unit & 255), UInt8(unit >> 8)] : [UInt8(unit >> 8), UInt8(unit & 255)]) }
        let url = try fixture.file("wide.txt", data)
        // Each line is 5 units (10 bytes); limits that fall inside a pair or a unit still end on a line.
        for limit in 45...53 {
            let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(limit))), "limit \(limit)")
            #expect(result.encoding == (littleEndian ? .utf16LittleEndian : .utf16BigEndian))
            #expect(result.text == String(repeating: "a😀b\n", count: (limit - 2) / 10), "limit \(limit)")
            #expect(result.truncatedSourceBytes == data.count)
        }
    }

    @Test func aSingleLineLongerThanTheBudgetCannotBeShownPartially() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file("one.txt", String(repeating: "x", count: 500))
        #expect(await partialPipeline.preview(url: url, budget: budget(100)) == .unavailable(.inputTooLarge))
    }

    @Test func theCutAlsoStopsBeforeTheLineAndLengthLimits() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file("limits.txt", lines(100))
        let byLines = try #require(ready(await partialPipeline.preview(url: url, budget: budget(500, lines: 7))))
        #expect(byLines.lineCount == 7 && byLines.text == String(lines(100).prefix(60)))
        let tail = "short\n" + String(repeating: "y", count: 50) + "\nshort\n" + String(repeating: "z", count: 400)
        let long = try fixture.file("long-line.txt", tail)
        let byLength = try #require(ready(await partialPipeline.preview(url: long, budget: budget(200, line: 20))))
        #expect(byLength.text == "short\n")
        // A file that fits is still held to the line budget: only an oversized file is cut by it.
        let small = try fixture.file("small.txt", lines(10))
        #expect(await partialPipeline.preview(url: small, budget: budget(1_000, lines: 3)) == .unavailable(.tooManyLines))
    }

    @Test func sourceLogJSONLinesAndConfigurationFilesAreAllPartial() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let records = String(repeating: "{\"a\":1}\n", count: 60)
        let cases: [(String, String, SourceLanguageID?)] = [
            ("big.swift", String(repeating: "let value = 1\n", count: 60), .swift),
            ("big.log", String(repeating: "2026-10-05 INFO line\n", count: 60), nil),
            ("big.jsonl", records, nil),
            ("big.ini", String(repeating: "key = value\n", count: 60), nil),
            ("big.sbv", String(repeating: "0:00:01.000,0:00:02.000\ntext\n\n", count: 40), nil),
            ("big.lrc", String(repeating: "[00:01.00]lyric\n", count: 60), nil),
            ("big.ass", "[Script Info]\n[Events]\n" + String(repeating: "Dialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,x\n", count: 30), nil),
            ("big.tsv", String(repeating: "a\tb\tc\n", count: 100), nil)
        ]
        for (name, source, language) in cases {
            let url = try fixture.file(name, source)
            let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(300))), "\(name)")
            #expect(result.truncatedSourceBytes == source.utf8.count, "\(name)")
            #expect(source.hasPrefix(result.text) && result.text.hasSuffix("\n"), "\(name)")
            #expect(result.sourceLanguage == language, "\(name)")
        }
    }

    @Test func subtitleCutsFallOnBlankLinesSoNoCueIsHalfShown() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let block = "1\n00:00:01,000 --> 00:00:02,000\ntext\n\n"             // 41 bytes
        let url = try fixture.file("big.srt", String(repeating: block, count: 20))
        let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(130))))
        #expect(result.text == String(repeating: block, count: 3))
        #expect(result.sourceRecordCount == 3)
    }

    @Test func csvCutsFallOutsideQuotedFields() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let record = "a,\"multi\nline\",c\n"                                  // 17 bytes, one record
        let url = try fixture.file("big.csv", "h1,h2,h3\n" + String(repeating: record, count: 20))
        for limit in 30...60 {
            let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(limit))), "limit \(limit)")
            let quotes = result.text.filter { $0 == "\"" }.count
            #expect(quotes.isMultiple(of: 2), "limit \(limit): a record was cut inside its quoted field")
            #expect(result.text.hasSuffix("c\n") || result.text == "h1,h2,h3\n", "limit \(limit)")
        }
    }

    @Test(arguments: [
        ("a.json", "{\"a\":1,\n\"b\":2,\n\"c\":3}\n"), ("a.yaml", "a: 1\nb: 2\nc: 3\n"), ("a.toml", "a = 1\nb = 2\nc = 3\n"),
        ("a.xml", "<r>\n<a/>\n<b/>\n</r>\n"), ("a.ipynb", "{\n\"cells\": []\n}\n"), ("a.env", "A=1\nB=2\nC=3\n"),
        ("a.jsonc", "{\n\"a\": 1\n}\n")
    ]) func structuredFormatsKeepFailingWithInputTooLarge(name: String, body: String) async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file(name, body + String(repeating: " ", count: 400) + "\n")
        #expect(await partialPipeline.preview(url: url, budget: budget(100)) == .unavailable(.inputTooLarge), "\(name)")
    }

    @Test func archivesAndBinaryInputsKeepTheirStrictBudget() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file("a.sub", String(repeating: "{1}{2}x\n", count: 100))
        // MicroDVD receives bytes on the binary path and is never read partially.
        #expect(await partialPipeline.preview(url: url, budget: budget(100)) == .unavailable(.inputTooLarge))
    }

    @Test func readersWithoutTheLeadingBytesCapabilityStayStrict() async throws {
        struct WholeFileReader: PreviewFileReading {
            let data: Data
            func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
        }
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: WholeFileReader(data: Data(lines(100).utf8)))
        #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/a.txt"), budget: budget(95)) == .unavailable(.inputTooLarge))
    }

    @Test func partialReadsHonorCancellationAndDisabledTypes() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let url = try fixture.file("big.log", lines(100))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .log)
        #expect(await partialPipeline.preview(url: url, preferences: preferences, budget: budget(95)) == .disabledByUser(.log))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await partialPipeline.preview(url: url, budget: budget(95))
        }
        #expect(await task.value == .cancelled)
    }

    @Test func privacyStillConcealsSecretsInThePartialPrefixAndAnUnterminatedKeyBlock() async throws {
        let fixture = try PartialFixture()
        defer { fixture.remove() }
        let key = "-----BEGIN PRIVATE KEY-----\nSYNTHETICPRIVATEBYTES\nMORESYNTHETICBYTES\n-----END PRIVATE KEY-----\n"
        let source = "password=synthetic-secret-value\n" + key + lines(100)
        let url = try fixture.file("secrets.txt", source)
        // The budget ends inside the key block: the shared filter conceals an unterminated key to the end.
        let result = try #require(ready(await partialPipeline.preview(url: url, budget: budget(70))))
        #expect(!result.text.contains("synthetic-secret-value") && !result.text.contains("SYNTHETICPRIVATEBYTES"))
        #expect(result.truncatedSourceBytes == source.utf8.count)
    }
}
