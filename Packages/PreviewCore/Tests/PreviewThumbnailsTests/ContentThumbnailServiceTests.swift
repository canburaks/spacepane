import Foundation
import SQLite3
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewThumbnails

private struct CountingAdapter: FormatAdapter {
    let parses: Counter
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        parses.increment()
        return ParsedTextDocument(text: input.text)
    }
}

/// Registrations whose factories count construction. They stand in for the named formats.
private func spyRegistrations(replacing ids: [FormatID], factories: Counter, parses: Counter) -> [AdapterRegistration] {
    StandardFormatAdapters.registrations.filter { !ids.contains($0.formatID) }
        + ids.map { id in AdapterRegistration(formatID: id) { factories.increment(); return CountingAdapter(parses: parses) } }
}

private func shape(of content: ThumbnailContent) -> String {
    switch content {
    case .text: "text"
    case .grid: "grid"
    case .picture: "picture"
    }
}

private func makeDatabase(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    defer { sqlite3_close(database) }
    let statements = """
    CREATE TABLE people(id INTEGER, name TEXT, note TEXT);
    INSERT INTO people VALUES (1, 'Ada', 'first'), (2, 'Bob', NULL);
    """
    guard sqlite3_exec(database, statements, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
}

/// A noncooperative read held until the test releases it. All mutable state is protected by the
/// condition's lock; blocking happens on the pipeline's worker executor, never in the test task.
private final class CancellationGatedReader: PreviewFileReading, @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var entered = false
    private var returned = false

    var hasEntered: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    var hasReturned: Bool {
        condition.lock()
        defer { condition.unlock() }
        return returned
    }

    func read(url: URL, context: RequestContext) throws -> FileBytes {
        condition.lock()
        defer { condition.unlock() }
        entered = true
        while !released { condition.wait() }
        returned = true
        return FileBytes(data: Data("late content".utf8))
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

@Suite("Content thumbnails through the shared pipeline")
struct ContentThumbnailServiceTests {
    struct Sample: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let shape: String
        let expected: String
        var testDescription: String { name }
    }

    /// One fixture per catalog format whose thumbnail policy is `content`.
    static let samples: [Sample] = [
        Sample(name: "notes.txt", text: "Meeting notes\nbuy milk and eggs\n", shape: "text", expected: "Meeting notes"),
        Sample(name: "tool.swift", text: "import Foundation\nlet answer = 42\n", shape: "text", expected: "let answer = 42"),
        Sample(name: "data.json", text: "{\n  \"title\": \"Demo\",\n  \"count\": 3\n}\n", shape: "text", expected: "\"title\": \"Demo\","),
        Sample(name: "minified.json", text: "{\"title\":\"Demo\",\"items\":[{\"id\":1,\"label\":\"first\"},{\"id\":2,\"label\":\"second\"}],\"note\":\"a fairly long description\"}", shape: "text", expected: "title: \"Demo\""),
        Sample(name: "events.jsonl", text: "{\"event\":\"start\",\"n\":1}\n{\"event\":\"stop\",\"n\":2}\n", shape: "text", expected: "\"event\""),
        Sample(name: "config.yaml", text: "name: demo\nreplicas: 3\n", shape: "text", expected: "name: demo"),
        Sample(name: "project.toml", text: "[package]\nname = \"demo\"\n", shape: "text", expected: "name = \"demo\""),
        Sample(name: "README.md", text: "# Guide\n\nHow to **use** it.\n\n- one\n- two\n", shape: "text", expected: "Guide"),
        Sample(name: "change.diff", text: "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new\n", shape: "text", expected: "+new"),
        Sample(name: "feed.xml", text: "<?xml version=\"1.0\"?>\n<feed><title>Demo</title></feed>\n", shape: "text", expected: "<feed><title>Demo</title></feed>"),
        Sample(name: "info.plist", text: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>Name</key><string>Demo</string></dict></plist>\n", shape: "text", expected: "Name"),
        Sample(name: "Localizable.strings", text: "\"hello\" = \"Hello\";\n", shape: "text", expected: "\"hello\" = \"Hello\";"),
        Sample(name: "Plurals.stringsdict", text: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>items</key><dict><key>NSStringLocalizedFormatKey</key><string>%d items</string></dict></dict></plist>\n", shape: "text", expected: "items"),
        Sample(name: "outline.opml", text: "<?xml version=\"1.0\"?>\n<opml version=\"2.0\"><body><outline text=\"Feed\"/></body></opml>\n", shape: "text", expected: "outline"),
        Sample(name: "table.csv", text: "id,name\n1,Ada\n2,Bob\n", shape: "grid", expected: "name"),
        Sample(name: "table.tsv", text: "id\tname\n1\tAda\n2\tBob\n", shape: "grid", expected: "name"),
        Sample(name: "movie.srt", text: "1\n00:00:01,000 --> 00:00:02,000\nHello there\n", shape: "text", expected: "Hello there"),
        Sample(name: "movie.vtt", text: "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello there\n", shape: "text", expected: "Hello there"),
        Sample(name: "release.nfo", text: "RELEASE INFO\n============\nplain ascii notes\n", shape: "text", expected: "plain ascii notes"),
        Sample(name: "analysis.ipynb", text: "{\"cells\":[{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":[\"# Study\"]},{\"cell_type\":\"code\",\"metadata\":{},\"outputs\":[],\"execution_count\":null,\"source\":[\"value = 1\"]}],\"metadata\":{},\"nbformat\":4,\"nbformat_minor\":5}", shape: "text", expected: "Study"),
        Sample(name: "package.json", text: "{\"name\":\"demo\",\"version\":\"1.0.0\",\"scripts\":{\"build\":\"tsc\"},\"description\":\"a longer description to force a long line\"}", shape: "text", expected: "name: \"demo\"")
    ]

    @Test(arguments: samples)
    func everyContentFormatDrawsItsConcealedPresentation(sample: Sample) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file(sample.name, sample.text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(sample.name): \(String(describing: outcome.reason))")
        #expect(shape(of: scene.content) == sample.shape, "\(sample.name)")
        #expect(scene.content.drawnStrings.contains { $0.contains(sample.expected) }, "\(sample.name): \(scene.content.drawnStrings)")
        // Nothing the file system or the host knows about the file is ever drawn.
        let drawn = scene.content.drawnStrings.joined()
        #expect(!drawn.contains(sample.name) && !drawn.contains(fixture.directory.path))
    }

    /// Q-121 draws typed shape facts, never the database summary or its first cell values.
    @Test func aDatabaseSummaryDrawsOnlyAValueFreeGrid() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("people.sqlite")
        try makeDatabase(at: url)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene)
        #expect(shape(of: scene.content) == "grid")
        let strings = scene.content.drawnStrings.joined(separator: "\n")
        #expect(!strings.contains("Ada") && !strings.contains("Bob") && !strings.contains("people"))
    }

    // MARK: Policy before parsing

    @Test func contentFormatsNeverReachAnAdapterWhenTheSwitchIsOff() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "hello")
        let reads = Counter()
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.showsContentThumbnails = false
        let outcome = await makeService(snapshot: snapshot, reader: SpyReader(reads: reads)).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .contentThumbnailsOff)
        #expect(reads.value == 0)
    }

    @Test func missingSettingsKeepTheGlyphAndReadNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "hello")
        let reads = Counter()
        let outcome = await makeService(snapshot: nil, reader: SpyReader(reads: reads)).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .settingsUnavailable)
        #expect(reads.value == 0)
    }

    @Test func aDisabledTypeNeverConstructsAnAdapterOrReadsTheFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("data.json", "{\"a\":1}")
        let factories = Counter(), parses = Counter(), reads = Counter()
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setEnabled(false, for: .json)
        let service = makeService(registrations: spyRegistrations(replacing: [.json], factories: factories, parses: parses),
                                  snapshot: snapshot, reader: SpyReader(reads: reads))
        #expect(await service.outcome(for: url, geometry: standardGeometry).reason == .disabledByUser)
        #expect(factories.value == 0 && parses.value == 0 && reads.value == 0)
    }

    @Test func disablingEveryTypeLeavesOnlyTheGlyph() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setAllEnabled(false)
        for name in ["a.txt", "a.json", "a.csv", "a.md"] {
            let url = try fixture.file(name, "x,y\n1,2\n")
            #expect(await makeService(snapshot: snapshot).outcome(for: url, geometry: standardGeometry).reason == .disabledByUser, "\(name)")
        }
    }

    @Test func contentFreeFormatsNeverConstructAnAdapter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = fixture.directory.appendingPathComponent("a folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = [
            try fixture.file("archive.zip", Data([0x50, 0x4B, 0x05, 0x06])), try fixture.file("bundle.tar", Data(count: 1_024)),
            try fixture.file("stream.gz", Data([0x1F, 0x8B])), try fixture.file("secrets.env", "TOKEN=\(syntheticSecret)\n"),
            try fixture.file("tune.mid", Data("MThd".utf8)), folder
        ]
        let ids: [FormatID] = [.zip, .tar, .gzip, .xip, .environment, .midi, .folder]
        let factories = Counter(), parses = Counter(), reads = Counter()
        let service = makeService(registrations: spyRegistrations(replacing: ids, factories: factories, parses: parses),
                                  snapshot: .defaults, reader: SpyReader(reads: reads))
        for url in urls {
            let reason = await service.outcome(for: url, geometry: standardGeometry).reason
            #expect(reason == .genericPolicy, "\(url.lastPathComponent): \(String(describing: reason))")
        }
        #expect(factories.value == 0 && parses.value == 0 && reads.value == 0)
    }

    @Test func extensionFreeAndUnsupportedFilesStayGeneric() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bare = try fixture.file("notes", "plain words without a suffix")
        #expect(await makeService().outcome(for: bare, geometry: standardGeometry).reason == .genericPolicy)
        let photo = try fixture.file("photo.png", syntheticImage(width: 8, height: 8))
        #expect(await makeService().outcome(for: photo, geometry: standardGeometry).reason == .unsupportedType)
    }

    /// Version 1.0 ships without the STEP and IGES previews: such a file is an unsupported type, with no thumbnail.
    @Test func stepAndIgesFilesAreUnsupportedTypesInVersionOne() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (name, text) in [("part.step", "ISO-10303-21;\n"), ("part.stp", "ISO-10303-21;\n"),
                             ("part.igs", "IGES\n"), ("part.iges", "IGES\n")] {
            let url = try fixture.file(name, text)
            #expect(await makeService().outcome(for: url, geometry: standardGeometry).reason == .unsupportedType, "\(name)")
        }
    }

    // MARK: Privacy

    private static let secretFiles: [(name: String, text: String)] = [
        ("settings.yaml", "name: demo\npassword: \(syntheticSecret)\n"),
        ("settings.toml", "[db]\napi_key = \"\(syntheticSecret)\"\n"),
        ("data.json", "{\"user\":\"ada\",\"password\":\"\(syntheticSecret)\"}"),
        ("minified.json", "{\"user\":\"ada\",\"token\":\"\(syntheticSecret)\",\"items\":[1,2,3],\"padding\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}"),
        ("notes.txt", "remember\nsecret = \(syntheticSecret)\n"),
        ("tool.swift", "let apiKey = \"\(syntheticSecret)\"\nlet visible = 1\n"),
        ("people.csv", "name,password\nAda,\(syntheticSecret)\nBob,\(syntheticSecret)\n"),
        ("people.tsv", "name\ttoken\nAda\t\(syntheticSecret)\n"),
        ("README.md", "# Title\n\npassword: \(syntheticSecret)\n"),
        ("nb.ipynb", "{\"cells\":[{\"cell_type\":\"code\",\"metadata\":{},\"outputs\":[],\"execution_count\":null,\"source\":[\"password = \\\"\(syntheticSecret)\\\"\"]}],\"metadata\":{},\"nbformat\":4,\"nbformat_minor\":5}")
    ]

    @Test(arguments: secretFiles.map(\.name))
    func aDocumentWithConcealedValuesIsWithheldWhole(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try #require(Self.secretFiles.first { $0.name == name }).text
        let url = try fixture.file(name, text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.reason == .withheldConcealedContent, "\(name): \(String(describing: outcome.scene?.content.drawnStrings))")
    }

    /// Even when the withholding limit is lifted, only the pipeline's concealed text reaches the page.
    @Test(arguments: secretFiles.map(\.name))
    func aSyntheticSecretIsNeverInAnyDrawnString(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try #require(Self.secretFiles.first { $0.name == name }).text
        let url = try fixture.file(name, text)
        var limits = relaxedLimits
        limits.maximumConcealedValues = .max
        let outcome = await makeService(limits: limits).outcome(for: url, geometry: geometry(512))
        if let scene = outcome.scene {
            for drawn in scene.content.drawnStrings { #expect(!drawn.contains(syntheticSecret), "\(name): \(drawn)") }
        }
    }

    // MARK: Bounds

    @Test func oversizedLineTextDrawsItsStartWhileOversizedStructuredTextFallsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // Line-oriented text reads only its leading complete lines (decision 019), so its start is drawn.
        let big = try fixture.file("big.txt", String(repeating: "a line of ordinary text\n", count: 20_000))
        #expect(try Data(contentsOf: big).count > ThumbnailLimits.standard.textBudget.maxInputBytes)
        let drawn = try #require(await makeService().outcome(for: big, geometry: standardGeometry).scene)
        #expect(drawn.content.drawnStrings.contains { $0.contains("a line of ordinary text") })
        // A structured document cannot be cut safely and still falls back to the glyph.
        let json = try fixture.file("big.json", "[" + String(repeating: "\"ordinary value\",", count: 20_000) + "0]")
        #expect(try Data(contentsOf: json).count > ThumbnailLimits.standard.textBudget.maxInputBytes)
        #expect(await makeService().outcome(for: json, geometry: standardGeometry).reason == .unavailable)
    }

    @Test func binaryAndMalformedFilesFallBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let binary = try fixture.file("binary.txt", Data([0x41, 0x00, 0x42, 0x01, 0x02]))
        #expect(await makeService().outcome(for: binary, geometry: standardGeometry).reason == .unavailable)
        let invalid = try fixture.file("broken.json", "{\"a\": ")
        let result = await makeService().outcome(for: invalid, geometry: standardGeometry)
        #expect(result.scene == nil)
        #expect(await makeService().outcome(for: fixture.directory.appendingPathComponent("missing.txt"), geometry: standardGeometry).reason == .unavailable)
    }

    @Test func aTextFileThatIsOnlyWhitespaceHasNothingToDraw() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("blank.txt", "  \n\n \t\n")
        #expect(await makeService().outcome(for: url, geometry: standardGeometry).reason == .nothingToDraw)
    }

    private struct SpinningAdapter: FormatAdapter {
        func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
            while true { try context.checkpoint() }
        }
    }

    @Test func thePipelineDeadlineBecomesAGlyphNotAFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("slow.txt", "content")
        var limits = relaxedLimits
        limits.textBudget = PreviewBudget(maxInputBytes: 262_144, maxOutputUTF8Bytes: 524_288, maxMilliseconds: 50)
        let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .plainText }
            + [AdapterRegistration(formatID: .plainText) { SpinningAdapter() }]
        let outcome = await makeService(registrations: registrations, limits: limits).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .timedOut)
    }


    @Test func cancellationAnswersWithTheGlyphBeforeTheBlockedReadReturns() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("stalled.txt", "content")
        let reader = CancellationGatedReader()
        let admission = ThumbnailAdmission(maximumConcurrent: 1)
        let parses = Counter()
        let registrations = spyRegistrations(replacing: [.plainText], factories: Counter(), parses: parses)
        let service = ContentThumbnailService(registrations: registrations, preferences: .fixed(.defaults),
                                              reader: reader, limits: relaxedLimits, admission: admission)
        let replies = Counter()
        let task = Task {
            let outcome = await service.outcome(for: url, geometry: standardGeometry)
            replies.increment()
            return outcome
        }
        defer { task.cancel(); reader.release() }
        try #require(await awaitCondition { reader.hasEntered }, "the request reached its noncooperative read")
        #expect(admission.runningCount == 1)
        task.cancel()
        // Cancellation must answer without waiting for the native read. Event ordering proves this even
        // when a loaded test runner resumes this task late; elapsed wall time would include that delay.
        try #require(await awaitCondition { replies.value == 1 }, "cancellation answers while the read stays held")
        #expect(await task.value.reason == .cancelled)
        #expect(!reader.hasReturned)
        #expect(admission.runningCount == 1, "the worker is still inside the held read")
        reader.release()
        try #require(await awaitCondition { admission.runningCount == 0 }, "the cancelled worker releases its slot")
        #expect(reader.hasReturned)
        #expect(parses.value == 0, "late bytes from the cancelled read never reach the parser")
        #expect(replies.value == 1)
    }

    @Test func concurrentRequestsDoNotQueueBehindEachOther() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let urls = try (0..<24).map { try fixture.file("note\($0).txt", "note number \($0)\n") }
        let service = makeService()
        let outcomes = await withTaskGroup(of: ThumbnailOutcome.self, returning: [ThumbnailOutcome].self) { group in
            for url in urls { group.addTask { await service.outcome(for: url, geometry: standardGeometry) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outcomes.count == 24)
        #expect(outcomes.allSatisfy { $0.scene != nil })
    }

    // MARK: Pictures

    private func pictureService(images: [PreviewImage], concealing: Bool = false, limits: ThumbnailLimits = relaxedLimits) -> ContentThumbnailService {
        let ranges = concealing ? [SensitiveRange(utf8Range: 8..<14)] : []
        let document = ParsedTextDocument(text: "caption \(concealing ? "hidden" : "visible") text", sensitiveRanges: ranges, images: images)
        let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .plainText }
            + [AdapterRegistration(formatID: .plainText) { FixedAdapter(document: document) }]
        return makeService(registrations: registrations, limits: limits)
    }

    @Test func aDocumentPictureIsDrawnInPlaceOfText() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        let image = PreviewImage(data: syntheticImage(width: 300, height: 450), pixelWidth: 300, pixelHeight: 450, role: .cover)
        let scene = try #require(await pictureService(images: [image]).outcome(for: url, geometry: geometry(128)).scene)
        guard case .picture(let picture) = scene.content else { Issue.record("expected a picture"); return }
        #expect(picture.role == .cover)
        #expect(max(picture.image.width, picture.image.height) <= 256)
        #expect(scene.content.drawnStrings.isEmpty)
    }

    @Test func coversBeatFigures() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        let figure = PreviewImage(data: syntheticImage(width: 40, height: 40), pixelWidth: 40, pixelHeight: 40, role: .figure)
        let cover = PreviewImage(data: syntheticImage(width: 30, height: 30), pixelWidth: 30, pixelHeight: 30, role: .cover)
        let scene = try #require(await pictureService(images: [figure, cover]).outcome(for: url, geometry: standardGeometry).scene)
        guard case .picture(let picture) = scene.content else { Issue.record("expected a picture"); return }
        #expect(picture.role == .cover)
    }

    @Test func anUndecodablePictureFallsBackToTheExcerpt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        let broken = PreviewImage(data: Data("not an image".utf8), pixelWidth: 10, pixelHeight: 10, role: .cover)
        let scene = try #require(await pictureService(images: [broken]).outcome(for: url, geometry: standardGeometry).scene)
        #expect(shape(of: scene.content) == "text")
        #expect(scene.content.drawnStrings.joined().contains("caption visible text"))
    }

    @Test func anOversizedPictureIsNeverDecoded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        var limits = relaxedLimits
        limits.maximumImagePixels = 1_000
        let big = PreviewImage(data: syntheticImage(width: 200, height: 200), pixelWidth: 200, pixelHeight: 200, role: .cover)
        let scene = try #require(await pictureService(images: [big], limits: limits).outcome(for: url, geometry: standardGeometry).scene)
        #expect(shape(of: scene.content) == "text")
    }

    @Test func concealedValuesWithholdThePictureToo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        let image = PreviewImage(data: syntheticImage(width: 30, height: 30), pixelWidth: 30, pixelHeight: 30, role: .cover)
        let outcome = await pictureService(images: [image], concealing: true).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .withheldConcealedContent)
    }

    @Test func colorSwitchTravelsWithTheScene() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "hello")
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.syntaxStyle.usesColor = false
        #expect(await makeService(snapshot: snapshot).outcome(for: url, geometry: standardGeometry).scene?.usesColor == false)
        #expect(await makeService().outcome(for: url, geometry: standardGeometry).scene?.usesColor == true)
    }
}

@Suite("Thumbnail host wall-clock liveness", .serialized)
struct ThumbnailHostLivenessTests {
    @Test func aBlockedReadIsCutOffByTheHardTimeout() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("stalled.txt", "content")
        var limits = relaxedLimits
        limits.hardTimeout = .milliseconds(150)
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await makeService(reader: BlockingReader(seconds: 6), limits: limits).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .timedOut)
        // Well below the 6 s the read blocks, with headroom for a loaded parallel test run.
        #expect(clock.now - start < .seconds(4))
    }
}
