import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private final class ReadCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct FixedReader: PreviewFileReading {
    let data: Data
    let reads: ReadCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
}

private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
private let synthetic = "synthetic-subtitle-secret"

private func ready(_ source: Data, file: String, budget: PreviewBudget? = nil) async -> TextPresentation? {
    let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                 reader: FixedReader(data: source, reads: ReadCounter()))
    guard case .ready(let presentation) = await custom.preview(url: URL(fileURLWithPath: "/unused/" + file), budget: budget) else { return nil }
    return presentation
}

private struct TemporaryFile {
    let directory: URL
    let url: URL
    init(_ name: String, _ data: Data) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("Captions and text art through the shared pipeline")
struct SubtitleTextArtPipelineTests {
    @Test func subRipSecretsAreConcealedAndRecordCountIsCarried() async throws {
        let source = "1\n00:00:01,000 --> 00:00:04,000\nPreview fixture\n\n2\n00:00:05,000 --> 00:00:08,000\npassword: \(synthetic)\n"
        let result = try #require(await ready(Data(source.utf8), file: "captions.srt"))
        #expect(result.formatID == .subRip)
        #expect(result.syntax == .subRip)
        #expect(result.encoding == .utf8)
        #expect(result.sourceRecordCount == 2)
        #expect(!result.text.contains(synthetic))
        #expect(result.text.contains("password:\u{2022}\u{2022}\u{2022}\u{2022}") || result.text.contains("password: \u{2022}\u{2022}\u{2022}\u{2022}"))
        #expect(result.text.contains("Preview fixture"))
        #expect(result.redactionCount == 1)
    }

    @Test func webVTTSecretsInCuesSettingsHeadersAndNotesAreConcealed() async throws {
        let source = "WEBVTT token=\(synthetic)-header\nApi-Key: \(synthetic)-meta\n\nNOTE reviewer\napi_key: \(synthetic)-note\nsecond comment line\n\n"
            + "00:01.000 --> 00:04.000 region:r1 token:\(synthetic)-setting\ncue text\n\n00:05.000 --> 00:08.000\nsecret = \(synthetic)-cue\nnext\n"
        let result = try #require(await ready(Data(source.utf8), file: "captions.vtt"))
        #expect(result.formatID == .webVTT)
        #expect(result.syntax == .webVTT)
        #expect(result.sourceRecordCount == 2)
        #expect(!result.text.contains(synthetic))
        #expect(!result.text.contains("second comment line"))
        #expect(result.text.contains("cue text"))
        #expect(result.text.contains("next"))
    }

    @Test func emptyValueAssignmentConcealsTheRestAndRecordCountExposesTheCollapse() async throws {
        let source = "1\n00:00:01,000 --> 00:00:02,000\nEnter your password:\n\n2\n00:00:03,000 --> 00:00:04,000\nlater cue text\n"
        let result = try #require(await ready(Data(source.utf8), file: "captions.srt"))
        // The shared policy conceals every following line when an assignment has no value.
        #expect(!result.text.contains("later cue text"))
        #expect(result.sourceRecordCount == 2)
        #expect(result.text.contains("00:00:01,000 --> 00:00:02,000"))
    }

    @Test(arguments: [
        ("captions.srt", "1\n00:00:01,000 --> 00:00:02,000\ntext\n2\n00:00:03,000 --> 00:00:04,000\ntext"),
        ("captions.srt", "no cues here"),
        ("captions.vtt", "00:00.000 --> 00:01.000\nmissing signature"),
        ("captions.vtt", "WEBVTT\n\n00:00.000 --> 00:61.000\nbad timestamp")
    ])
    func malformedCaptionsAreUnavailableNotShownAsPlainText(file: String, source: String) async {
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: FixedReader(data: Data(source.utf8), reads: ReadCounter()))
        #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/" + file)) == .unavailable(.malformedDocument))
    }

    @Test func disabledCaptionAndNFOTypesAreNeverReadOrFallBackToText() async {
        for (id, file) in [(FormatID.subRip, "a.srt"), (.webVTT, "a.vtt"), (.nfo, "a.nfo"), (.nfo, "FILE_ID.DIZ")] {
            let reads = ReadCounter()
            let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                         reader: FixedReader(data: Data("x".utf8), reads: reads))
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: id)
            #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/" + file), preferences: preferences) == .disabledByUser(id))
            #expect(reads.value == 0)
        }
        // Independent choices: disabling one caption format leaves the other and plain text enabled.
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .subRip)
        let source = "WEBVTT\n\n00:00.000 --> 00:01.000\nx"
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: FixedReader(data: Data(source.utf8), reads: ReadCounter()))
        if case .ready(let result) = await custom.preview(url: URL(fileURLWithPath: "/unused/a.vtt"), preferences: preferences) {
            #expect(result.formatID == .webVTT)
        } else {
            Issue.record("WebVTT must remain enabled when SubRip is disabled")
        }
    }

    @Test func cancellationPrecedesSourceAccess() async {
        let reads = ReadCounter()
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: FixedReader(data: Data("x".utf8), reads: reads))
        for file in ["a.srt", "a.vtt", "a.nfo"] {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await custom.preview(url: URL(fileURLWithPath: "/unused/" + file))
            }
            #expect(await task.value == .cancelled)
        }
        #expect(reads.value == 0)
    }

    @Test func nfoCodePage437ReportsEncodingConcealsSecretsAndLeavesTheSourceUntouched() async throws {
        var original = Data([0xC9, 0xCD, 0xCD, 0xCD, 0xBB, 0x0D, 0x0A, 0xBA, 0x20])
        original.append(Data("Preview fixture ".utf8))
        original.append(contentsOf: [0xBA, 0x0D, 0x0A, 0xC8, 0xCD, 0xCD, 0xCD, 0xBC, 0x0D, 0x0A])
        original.append(Data("password=\(synthetic)\r\n".utf8))
        let file = try TemporaryFile("release.nfo", original)
        defer { file.remove() }
        guard case .ready(let result) = await pipeline.preview(url: file.url) else {
            Issue.record("Expected a CP437 NFO preview")
            return
        }
        #expect(result.formatID == .nfo)
        #expect(result.encoding == .codePage437)
        #expect(result.syntax == .plain)
        #expect(result.byteCount == original.count)
        #expect(result.text.hasPrefix("\u{2554}\u{2550}\u{2550}\u{2550}\u{2557}"))
        #expect(result.text.contains("\u{2551} Preview fixture \u{2551}"))
        #expect(!result.text.contains(synthetic))
        #expect(result.redactionCount == 1)
        #expect(try Data(contentsOf: file.url) == original)
    }

    @Test func nfoUTF8AndDIZAliasUseTheSameAdapter() async throws {
        let original = Data(("Caf\u{E9} \u{2554}\u{2550}\u{2557}\r\n").utf8)
        let file = try TemporaryFile("FILE_ID.DIZ", original)
        defer { file.remove() }
        guard case .ready(let result) = await pipeline.preview(url: file.url) else {
            Issue.record("Expected a UTF-8 DIZ preview")
            return
        }
        #expect(result.formatID == .nfo)
        #expect(result.encoding == .utf8)
        #expect(result.text.utf8.elementsEqual(original))
        #expect(try Data(contentsOf: file.url) == original)
    }

    @Test(arguments: [
        [0x41, 0x00, 0x42],
        [0xFF, 0xFE, 0x41, 0x00],
        [0x41, 0x1B, 0x5B, 0x30, 0x6D]
    ] as [[UInt8]])
    func nfoBinarySignalsAreUnavailableAndSourceBytesRemain(bytes: [UInt8]) async throws {
        let original = Data(bytes)
        let file = try TemporaryFile("binary.nfo", original)
        defer { file.remove() }
        #expect(await pipeline.preview(url: file.url) == .unavailable(.binaryContent))
        #expect(try Data(contentsOf: file.url) == original)
    }

    @Test func nfoInputAndOutputBudgetsAreEnforcedByThePipeline() async throws {
        let original = Data(repeating: 0xDB, count: 700_000)
        let file = try TemporaryFile("big.nfo", original)
        defer { file.remove() }
        // 700,000 bytes fit the 1 MiB input limit but decode to 2.1 MB, over the 2 MiB output limit.
        #expect(await pipeline.preview(url: file.url) == .unavailable(.outputTooLarge))
        #expect(await pipeline.preview(url: file.url, budget: PreviewBudget(maxInputBytes: 1_024)) == .unavailable(.inputTooLarge))
        #expect(try Data(contentsOf: file.url) == original)
    }

    @Test func binaryAdaptersWithoutProvenanceStillReportUTF8() async {
        struct Plain: BinaryFormatAdapter {
            func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument { ParsedTextDocument(text: "plain") }
        }
        struct Legacy: BinaryFormatAdapter {
            func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
                ParsedTextDocument(text: "legacy", decodedEncoding: .codePage437)
            }
        }
        for (adapter, expected) in [(Plain() as any BinaryFormatAdapter, TextEncoding.utf8), (Legacy(), .codePage437)] {
            let custom = PreviewPipeline(registrations: [AdapterRegistration(formatID: .nfo, binaryAdapter: { adapter })],
                                         reader: FixedReader(data: Data([1]), reads: ReadCounter()))
            guard case .ready(let result) = await custom.preview(url: URL(fileURLWithPath: "/unused/a.nfo")) else {
                Issue.record("Expected ready")
                return
            }
            #expect(result.encoding == expected)
            #expect(result.byteCount == 1)
        }
    }
}
