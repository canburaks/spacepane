import Foundation
import Darwin
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}
private struct SpyReader: PreviewFileReading {
    let count: Counter
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        count.increment()
        return FileBytes(data: data)
    }
}
private struct DeadlineAdapter: FormatAdapter {
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        while true { try context.checkpoint() }
    }
}
private struct CancellableAdapter: FormatAdapter {
    let started: Counter
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        started.increment()
        while true { try context.checkpoint() }
    }
}
private final class WorkerProbe: Sendable {
    private struct State { var active = 0; var maximum = 0 }
    private let state = Mutex(State())
    func enter() { state.withLock { $0.active += 1; $0.maximum = max($0.active, $0.maximum) } }
    func leave() { state.withLock { $0.active -= 1 } }
    var maximum: Int { state.withLock { $0.maximum } }
}
private struct ObservedAdapter: FormatAdapter {
    let probe: WorkerProbe
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        probe.enter()
        defer { probe.leave() }
        #expect(!Thread.isMainThread)
        Thread.sleep(forTimeInterval: 0.005)
        try context.checkpoint()
        return ParsedTextDocument(text: input.text)
    }
}
private struct Fixture {
    let directory: URL
    let url: URL
    init(_ data: Data, suffix: String = "txt") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("fixture.\(suffix)")
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

@Test func disabledJSONNeverReadsOrConstructsParser() async {
    let reads = Counter()
    let factories = Counter()
    let custom = PreviewPipeline(registrations: [AdapterRegistration(formatID: .json) {
        factories.increment()
        return JSONSourceAdapter()
    }], reader: SpyReader(count: reads, data: Data(#"{"password":"synthetic"}"#.utf8)))
    var preferences = PreviewPreferencesSnapshot.defaults
    preferences.setEnabled(false, for: .json)
    let result = await custom.preview(url: URL(fileURLWithPath: "/unused/document.JSON"), preferences: preferences)
    #expect(result == .disabledByUser(.json))
    #expect(reads.value == 0)
    #expect(factories.value == 0)
    #expect(await custom.inspect(url: URL(fileURLWithPath: "/unused/document.JSON"), preferences: preferences) == .disabledByUser(.json))
}

@Test func validTextIsReadOnlyAndUnicodeSurvives() async throws {
    let original = Data("Hello Türkçe 🌍\r\nSecond line".utf8)
    let fixture = try Fixture(original)
    defer { fixture.remove() }
    let result = await pipeline.preview(url: fixture.url)
    guard case .ready(let presentation) = result else { Issue.record("Expected ready text: \(result)"); return }
    #expect(presentation.text == "Hello Türkçe 🌍\r\nSecond line")
    #expect(presentation.lineCount == 2)
    #expect(presentation.encoding == .utf8)
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test(arguments: [true, false]) func utf16BOMAndSurrogatePairs(littleEndian: Bool) async throws {
    let source = "Unicode 🌍\nText"
    var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
    for unit in source.utf16 {
        data.append(contentsOf: littleEndian ? [UInt8(unit & 255), UInt8(unit >> 8)] : [UInt8(unit >> 8), UInt8(unit & 255)])
    }
    let fixture = try Fixture(data)
    defer { fixture.remove() }
    guard case .ready(let result) = await pipeline.preview(url: fixture.url) else { Issue.record("Expected UTF-16 preview"); return }
    #expect(result.text == source)
    #expect(result.encoding == (littleEndian ? .utf16LittleEndian : .utf16BigEndian))
}

@Test(arguments: [Data([0xFF]), Data([0xFF, 0xFE, 0x00, 0xD8]), Data([0xFE, 0xFF, 0xD8])])
func invalidEncodingIsRejected(data: Data) async throws {
    let fixture = try Fixture(data)
    defer { fixture.remove() }
    #expect(await pipeline.preview(url: fixture.url) == .unavailable(.unsupportedEncoding))
}

@Test func binaryAndOversizedInputAreRejected() async throws {
    let binary = try Fixture(Data([65, 0, 66]))
    defer { binary.remove() }
    #expect(await pipeline.preview(url: binary.url) == .unavailable(.binaryContent))
    let oversized = try Fixture(Data(repeating: 65, count: 65))
    defer { oversized.remove() }
    #expect(await pipeline.preview(url: oversized.url, budget: PreviewBudget(maxInputBytes: 64)) == .unavailable(.inputTooLarge))
}

@Test func lineAndOutputBudgetsAreEnforced() async throws {
    let long = try Fixture(Data("abcdef".utf8))
    defer { long.remove() }
    #expect(await pipeline.preview(url: long.url, budget: PreviewBudget(maxLineUTF8Bytes: 5)) == .unavailable(.lineTooLong))
    #expect(await pipeline.preview(url: long.url, budget: PreviewBudget(maxOutputUTF8Bytes: 5)) == .unavailable(.outputTooLarge))
    let many = try Fixture(Data("a\nb\nc".utf8))
    defer { many.remove() }
    #expect(await pipeline.preview(url: many.url, budget: PreviewBudget(maxTextLines: 2)) == .unavailable(.tooManyLines))
}

@Test(arguments: ["\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"])
func visualNewlineVariantsShareLimitsAndCounts(separator: String) async throws {
    let fixture = try Fixture(Data("a\(separator)b\(separator)c".utf8))
    defer { fixture.remove() }
    #expect(await pipeline.preview(url: fixture.url, budget: PreviewBudget(maxTextLines: 2)) == .unavailable(.tooManyLines))
    guard case .ready(let result) = await pipeline.preview(url: fixture.url) else { Issue.record("Expected safe newline variant"); return }
    #expect(result.lineCount == 3)
}

@Test func syntheticSecretsAreConcealedAcrossTextAndJSON() async throws {
    let text = try Fixture(Data("safe=hello\nexport API_KEY=synthetic-secret\npassword: \"unterminated synthetic-password\n-----BEGIN PRIVATE KEY-----\nSYNTHETICPRIVATEBYTES\n-----END PRIVATE KEY-----\n".utf8))
    defer { text.remove() }
    guard case .ready(let textResult) = await pipeline.preview(url: text.url) else { Issue.record("Expected safe text"); return }
    #expect(!textResult.text.contains("synthetic-secret"))
    #expect(!textResult.text.contains("synthetic-password"))
    #expect(!textResult.text.contains("SYNTHETICPRIVATEBYTES"))
    #expect(textResult.text.contains("safe=hello"))
    #expect(textResult.syntax == .plain)
    let json = try Fixture(Data(#"{"pa\u0073sword":"synthetic-json","token":{"nested":"synthetic-nested"},"name":"🌍"}"#.utf8), suffix: "json")
    defer { json.remove() }
    guard case .ready(let jsonResult) = await pipeline.preview(url: json.url) else { Issue.record("Expected safe JSON"); return }
    #expect(!jsonResult.text.contains("synthetic-json"))
    #expect(!jsonResult.text.contains("synthetic-nested"))
    #expect(jsonResult.text.contains("🌍"))
    #expect(jsonResult.redactionCount == 2)
    #expect(jsonResult.syntax == .json)
}

@Test func syntaxSurvivesPrivacyFilteringWithoutRetainingRawText() throws {
    let source = #"{"password":"synthetic-private-value","name":"🌍"}"#
    let context = RequestContext(budget: .standard)
    let parsed = try JSONSourceAdapter().parse(DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count),
                                             context: context)
    let safe = try DefaultPrivacyFilter().filter(parsed, context: context)
    #expect(safe.syntax == .json)
    #expect(safe.text == #"{"password":••••,"name":"🌍"}"#)
    #expect(safe.redactionCount == 1)
}

@Test func malformedSecretJSONHasNoRawFallback() async throws {
    let fixture = try Fixture(Data(#"{"password":"synthetic-secret" "missing":"comma"}"#.utf8), suffix: "json")
    defer { fixture.remove() }
    #expect(await pipeline.preview(url: fixture.url) == .unavailable(.malformedDocument))
}

@Test func cancellationStopsBeforeReaderAndParser() async {
    let reads = Counter()
    let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                reader: SpyReader(count: reads, data: Data("text".utf8)))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await custom.preview(url: URL(fileURLWithPath: "/unused/document.txt"))
    }
    #expect(await task.value == .cancelled)
    #expect(reads.value == 0)
}

@Test func cooperativeDeadlineStopsParser() async {
    let custom = PreviewPipeline(registrations: [AdapterRegistration(formatID: .plainText) { DeadlineAdapter() }],
                                reader: SpyReader(count: Counter(), data: Data("text".utf8)))
    #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/document.txt"), budget: PreviewBudget(maxMilliseconds: 5)) == .unavailable(.deadlineExceeded))
}

@Suite("Pipeline wall-clock liveness", .serialized)
struct PipelineWallClockTests {
    @Test func cancellationStopsAnAlreadyRunningParser() async {
        let started = Counter()
        let custom = PreviewPipeline(registrations: [AdapterRegistration(formatID: .plainText) { CancellableAdapter(started: started) }],
                                    reader: SpyReader(count: Counter(), data: Data("text".utf8)))
        let task = Task { await custom.preview(url: URL(fileURLWithPath: "/unused/document.txt"),
                                               budget: PreviewBudget(maxMilliseconds: 30_000)) }
        while started.value == 0 { await Task.yield() }
        task.cancel()
        #expect(await task.value == .cancelled)
    }
}

@Test func workerSerializesParsingOffMainActor() async {
    let probe = WorkerProbe()
    let custom = PreviewPipeline(registrations: [AdapterRegistration(formatID: .plainText) { ObservedAdapter(probe: probe) }],
                                reader: SpyReader(count: Counter(), data: Data("text".utf8)))
    await withTaskGroup(of: PreviewOutcome.self) { group in
        for _ in 0..<5 { group.addTask { await custom.preview(url: URL(fileURLWithPath: "/unused/document.txt")) } }
        for await result in group {
            guard case .ready = result else { Issue.record("Expected serialized ready result"); continue }
        }
    }
    #expect(probe.maximum == 1)
}

@Test func directoriesSymlinksAndFIFOsCannotBeReadAsContent() async throws {
    let fixture = try Fixture(Data("safe".utf8))
    defer { fixture.remove() }
    let link = fixture.directory.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url)
    #expect(await pipeline.preview(url: link) == .unavailable(.notRegularFile))
    let fifo = fixture.directory.appendingPathComponent("pipe.txt")
    let created = fifo.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
    #expect(created == 0)
    #expect(await pipeline.preview(url: fifo) == .unavailable(.notRegularFile))
    let directory = fixture.directory.appendingPathComponent("folder.txt", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(await pipeline.preview(url: directory) == .unavailable(.notRegularFile))
}

@Test func unimplementedFormatsHaveNoGenericByteFallback() async throws {
    let fixture = try Fixture(Data("looks like text".utf8), suffix: "png")
    defer { fixture.remove() }
    #expect(await pipeline.preview(url: fixture.url) == .unavailable(.unsupportedFormat))
}

@Test func longTokensAndDenseAssignmentsStayWithinBoundedPrivacyWork() async throws {
    for source in [String(repeating: "a", count: 32_000), String(repeating: "x=1;", count: 5_000)] {
        let fixture = try Fixture(Data(source.utf8))
        defer { fixture.remove() }
        guard case .ready(let result) = await pipeline.preview(url: fixture.url) else {
            Issue.record("Expected bounded ordinary text"); continue
        }
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
    }
}

@Test(arguments: [
    "password:\nsynthetic-continuation",
    "password=\"unterminated\nsynthetic-continuation",
    "token={\nvalue: synthetic-continuation\n}",
    "API_KEY=first \\\nsynthetic-continuation"
]) func ambiguousTextSecretsConcealContinuationLines(source: String) async throws {
    let fixture = try Fixture(Data(source.utf8))
    defer { fixture.remove() }
    guard case .ready(let result) = await pipeline.preview(url: fixture.url) else { Issue.record("Expected safe text"); return }
    #expect(!result.text.contains("synthetic-continuation"))
    #expect(result.redactionCount > 0)
}
