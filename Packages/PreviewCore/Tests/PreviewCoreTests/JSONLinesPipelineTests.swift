import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewCADFormats

private let jsonLinesID = FormatID(rawValue: "data.json-lines")

private final class JSONLinesCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct JSONLinesReader: PreviewFileReading {
    let data: Data
    let reads: JSONLinesCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
}

private struct JSONLinesFixture {
    let directory: URL
    let url: URL
    init(data: Data, suffix: String = "jsonl") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("records.\(suffix)")
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func JSONLinesFixtureBytes(_ relativePath: String) throws -> Data {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: testsDirectory.appendingPathComponent("../../../../Fixtures/\(relativePath)"))
}

private let jsonLinesPipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

@Test func JSONLinesCompleteSourceUsesExistingPipeline() async {
    let source = "{\"name\":\"🌍\",\"amount\":1.234e999}\nnull\n"
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
        reader: JSONLinesReader(data: Data(source.utf8), reads: JSONLinesCounter()))
    guard case .ready(let result) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/sample.jsonl")) else {
        Issue.record("Expected a complete JSON Lines source preview")
        return
    }
    #expect(result.formatID == jsonLinesID)
    #expect(result.text == source)
    #expect(result.syntax == .json)
}

@Test(arguments: ["jsonl", "ndjson"])
func JSONLinesNormalFixtureRemainsExactAndReadOnly(suffix: String) async throws {
    let original = try JSONLinesFixtureBytes("Normal/records.jsonl")
    let fixture = try JSONLinesFixture(data: original, suffix: suffix)
    defer { fixture.remove() }
    guard case .ready(let result) = await jsonLinesPipeline.preview(url: fixture.url) else {
        Issue.record("Expected validated JSON Lines fixture")
        return
    }
    #expect(result.text == String(data: original, encoding: .utf8))
    #expect(result.formatID == jsonLinesID)
    #expect(result.encoding == .utf8)
    #expect(result.byteCount == original.count)
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test func JSONLinesPrivacyConcealsLaterUnicodeRecordValues() async throws {
    let original = try JSONLinesFixtureBytes("Sensitive/records-synthetic.jsonl")
    let fixture = try JSONLinesFixture(data: original)
    defer { fixture.remove() }
    guard case .ready(let result) = await jsonLinesPipeline.preview(url: fixture.url) else {
        Issue.record("Expected concealed JSON Lines fixture")
        return
    }
    #expect(!result.text.contains("synthetic-line-two-password"))
    #expect(!result.text.contains("synthetic-line-three-key"))
    #expect(result.text.contains("Unicode 🌍 café"))
    #expect(result.text.contains("日本語"))
    #expect(result.text.contains("visible"))
    #expect(result.redactionCount == 2)
    #expect(result.syntax == .json)
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test(arguments: ["jsonl", "ndjson"])
func JSONLinesMalformedSecretRecordIsFullyConcealedWithoutRawFallback(suffix: String) async throws {
    let original = try JSONLinesFixtureBytes("Malformed/records-invalid.jsonl")
    let fixture = try JSONLinesFixture(data: original, suffix: suffix)
    defer { fixture.remove() }
    guard case .ready(let result) = await jsonLinesPipeline.preview(url: fixture.url) else {
        Issue.record("Expected safe JSON Lines record recovery")
        return
    }
    #expect(result.invalidRecordLines == [2])
    #expect(!result.text.contains("synthetic-first-record"))
    #expect(!result.text.contains("synthetic-invalid-record"))
    #expect(result.text.contains("never displayed"))
    #expect(result.text.components(separatedBy: "\n")[1] == "••••")
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test(arguments: ["jsonl", "ndjson", "JSONL", "NDJSON"])
func JSONLinesDisabledAliasesNeverReadOrConstructAnyFallback(suffix: String) async {
    let reads = JSONLinesCounter()
    let factories = JSONLinesCounter()
    let pipeline = PreviewPipeline(registrations: [
        AdapterRegistration(formatID: .jsonLines) { factories.increment(); return JSONLinesAdapter() },
        AdapterRegistration(formatID: .json) { factories.increment(); return JSONSourceAdapter() },
        AdapterRegistration(formatID: .plainText) { factories.increment(); return TextAdapter() }
    ], reader: JSONLinesReader(data: Data(#"{"password":"synthetic-disabled"}"#.utf8), reads: reads))
    var preferences = PreviewPreferencesSnapshot.defaults
    preferences.setEnabled(false, for: .jsonLines)
    let url = URL(fileURLWithPath: "/unused/records.\(suffix)")
    #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.jsonLines))
    #expect(await pipeline.inspect(url: url, preferences: preferences) == .disabledByUser(.jsonLines))
    #expect(reads.value == 0)
    #expect(factories.value == 0)
}

@Test func JSONLinesHonorsPriorDisableAllAndIndependentJSONChoice() async {
    let reads = JSONLinesCounter()
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
        reader: JSONLinesReader(data: Data("{}\n{}".utf8), reads: reads))
    var preferences = PreviewPreferencesSnapshot.defaults
    preferences.setAllEnabled(false)
    preferences.setEnabled(true, for: .json)
    #expect(preferences.formatOverrides[.jsonLines] == nil)
    let url = URL(fileURLWithPath: "/unused/records.ndjson")
    #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.jsonLines))
    #expect(reads.value == 0)
    preferences.resetFileTypeChoices()
    preferences.setEnabled(false, for: .json)
    guard case .ready = await pipeline.preview(url: url, preferences: preferences) else {
        Issue.record("Disabling JSON must preserve the independent JSON Lines choice")
        return
    }
}

@Test func JSONLinesPipelineSharesCumulativeAndByteBudgets() async throws {
    let original = Data("{}\n{}\n{}".utf8)
    let fixture = try JSONLinesFixture(data: original)
    defer { fixture.remove() }
    #expect(await jsonLinesPipeline.preview(url: fixture.url, budget: PreviewBudget(maxJSONNodes: 2)) == .unavailable(.tooManyNodes))
    // JSON Lines is line oriented, so an oversized file shows its leading complete records and reports its
    // size (the code workstream's partial preview); only a first record that cannot fit is still refused.
    guard case .ready(let partial) = await jsonLinesPipeline.preview(url: fixture.url, budget: PreviewBudget(maxInputBytes: 7)) else {
        Issue.record("Expected a partial JSON Lines preview"); return
    }
    #expect(partial.text == "{}\n{}\n" && partial.truncatedSourceBytes == 8 && partial.byteCount == 6)
    #expect(await jsonLinesPipeline.preview(url: fixture.url, budget: PreviewBudget(maxInputBytes: 2)) == .unavailable(.inputTooLarge))
    #expect(await jsonLinesPipeline.preview(url: fixture.url, budget: PreviewBudget(maxTextLines: 2)) == .unavailable(.tooManyLines))
    #expect(await jsonLinesPipeline.preview(url: fixture.url, budget: PreviewBudget(maxOutputUTF8Bytes: 7)) == .unavailable(.outputTooLarge))
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test func JSONLinesRejectsUTF8BOMWhileJSONRetainsExistingAcceptance() async throws {
    let original = Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)
    let lines = try JSONLinesFixture(data: original)
    defer { lines.remove() }
    #expect(await jsonLinesPipeline.preview(url: lines.url) == .unavailable(.malformedDocument))
    #expect(try Data(contentsOf: lines.url) == original)
    let json = try JSONLinesFixture(data: original, suffix: "json")
    defer { json.remove() }
    guard case .ready(let result) = await jsonLinesPipeline.preview(url: json.url) else {
        Issue.record("Existing JSON BOM acceptance must remain intact")
        return
    }
    #expect(result.text == "{}")
}

@Test(arguments: [true, false])
func JSONLinesRejectsUTF16Source(littleEndian: Bool) async throws {
    var original = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
    for unit in "{}\n{}".utf16 {
        original.append(contentsOf: littleEndian ? [UInt8(unit & 255), UInt8(unit >> 8)] : [UInt8(unit >> 8), UInt8(unit & 255)])
    }
    let fixture = try JSONLinesFixture(data: original)
    defer { fixture.remove() }
    #expect(await jsonLinesPipeline.preview(url: fixture.url) == .unavailable(.unsupportedEncoding))
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test func JSONLinesCancellationPrecedesSourceAccess() async {
    let reads = JSONLinesCounter()
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
        reader: JSONLinesReader(data: Data("{}\n{}".utf8), reads: reads))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await pipeline.preview(url: URL(fileURLWithPath: "/unused/records.jsonl"))
    }
    #expect(await task.value == .cancelled)
    #expect(reads.value == 0)
}

@Test func JSONLinesStandardBindingsMatchTheSharedCatalog() {
    #expect(Set((StandardFormatAdapters.registrations + CADFormatAdapters.registrations).map(\.formatID)) == Set(FormatCatalog.standard.descriptors.map(\.id)))
}
