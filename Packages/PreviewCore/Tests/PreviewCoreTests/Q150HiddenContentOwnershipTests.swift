import Foundation
import Synchronization
import Testing
import zlib
import PreviewContracts
import PreviewTestSupport
@testable import PreviewCore
@testable import PreviewFormats

private let q150Context = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))

private struct Q150DocumentAdapter: FormatAdapter, BinaryFormatAdapter, RandomAccessFormatAdapter, URLFormatAdapter {
    let document: ParsedTextDocument
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument { document }
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument { document }
    func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument { document }
    func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument { document }
}

private final class Q150Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct Q150Reader: PreviewFileReading {
    let data: Data
    let reads: Q150Counter
    let opens: Q150Counter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource {
        opens.increment()
        return RecordingByteSource(data)
    }
}

private func q150Paths(document: ParsedTextDocument) -> [(String, AdapterInputPath)] {
    let adapter = Q150DocumentAdapter(document: document)
    return [("text", .text { adapter }), ("binary", .binary { adapter }),
            ("randomAccess", .randomAccess { adapter }), ("url", .url { adapter }),
            ("geometry", .geometry { fatalError("Eligibility must not construct an adapter") })]
}

private func q150Tagged(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { Unicode.Scalar($0.value + 0xE0000)! }))
}

private func q150Finding(_ kind: PreviewFindingKind, in presentation: TextPresentation) -> PreviewFinding? {
    presentation.findings.first { $0.kind == kind }
}

private func q150HiddenFindings(_ presentation: TextPresentation) -> [PreviewFinding] {
    presentation.findings.filter { $0.kind.rawValue.hasPrefix("hidden.") }
}

/// Stored, UTF-8 ZIP entries: bounded synthetic EPUB bytes, never copied from a book.
private func q150ZIP(_ files: [(String, Data)]) -> Data {
    func little(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    var output = Data(), central = Data()
    for (name, payload) in files {
        let encodedName = Data(name.utf8), offset = output.count
        let crc = payload.withUnsafeBytes { buffer -> UInt32 in
            UInt32(crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
        output += little(0x04034b50, 4) + little(20, 2) + little(0x800, 2) + little(0, 2)
        output += little(0, 2) + little(0x21, 2) + little(UInt64(crc), 4)
        output += little(UInt64(payload.count), 4) + little(UInt64(payload.count), 4)
        output += little(UInt64(encodedName.count), 2) + little(0, 2) + encodedName + payload
        central += little(0x02014b50, 4) + little(20, 2) + little(20, 2) + little(0x800, 2) + little(0, 2)
        central += little(0, 2) + little(0x21, 2) + little(UInt64(crc), 4)
        central += little(UInt64(payload.count), 4) + little(UInt64(payload.count), 4)
        central += little(UInt64(encodedName.count), 2) + Data(repeating: 0, count: 12)
        central += little(UInt64(offset), 4) + encodedName
    }
    let start = output.count
    output += central + little(0x06054b50, 4) + Data(repeating: 0, count: 4)
    output += little(UInt64(files.count), 2) + little(UInt64(files.count), 2)
    output += little(UInt64(central.count), 4) + little(UInt64(start), 4) + little(0, 2)
    return output
}

private func q150GZIP(_ data: Data) throws -> Data {
    var stream = z_stream()
    guard deflateInit2_(&stream, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION,
                       Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw PreviewFailure.unavailableContent }
    defer { deflateEnd(&stream) }
    var output = Data(count: data.count + 128)
    let capacity = output.count
    return try data.withUnsafeBytes { input in
        try output.withUnsafeMutableBytes { target in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            stream.next_out = target.bindMemory(to: UInt8.self).baseAddress!
            stream.avail_out = uInt(capacity)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw PreviewFailure.malformedDocument }
            return Data(target.prefix(capacity - Int(stream.avail_out)))
        }
    }
}

private struct Q150Fixture {
    let formatID: FormatID
    let name: String
    let bytes: Data
}

private func q150ConvertedFixtures() -> [Q150Fixture] {
    let paragraphs = "<p>First paragraph.</p><p>password=synthetic\u{200B}credential</p><p>Visible\u{200B} note.</p>"
    let chapter = Data("<html><body>\(paragraphs)</body></html>".utf8)
    let package = Data("""
    <package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Synthetic Book</dc:title></metadata><manifest>
    <item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
    <spine><itemref idref="c1"/></spine></package>
    """.utf8)
    let epub = q150ZIP([
        ("META-INF/container.xml", Data(#"<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"#.utf8)),
        ("OEBPS/content.opf", package), ("OEBPS/chapter.xhtml", chapter)
    ])
    let fb2 = Data("<FictionBook><description><title-info><book-title>Synthetic Book</book-title></title-info></description>"
        .appending("<body><section>\(paragraphs)</section></body></FictionBook>").utf8)
    let mhtml = Data(("Subject: Synthetic Page\r\nContent-Type: multipart/related; boundary=\"q150\"\r\n\r\n"
        + "--q150\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<html><body>\(paragraphs)</body></html>"
        + "\r\n--q150--\r\n").utf8)
    return [.init(formatID: .epub, name: "synthetic.epub", bytes: epub),
            .init(formatID: .fictionBook, name: "synthetic.fb2", bytes: fb2),
            .init(formatID: .webArchive, name: "synthetic.mhtml", bytes: mhtml)]
}

private func q150Write(_ bytes: Data, name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try bytes.write(to: url)
    return url
}

private func q150ConvertedPipeline(_ text: String, randomAccess: Bool,
                                   privacy: any PreviewPrivacyFiltering = DefaultPrivacyFilter()) -> PreviewPipeline {
    let document = ParsedTextDocument(text: text, syntax: .markdown, origin: .converted)
    let registration = randomAccess
        ? AdapterRegistration(formatID: .fictionBook, randomAccessAdapter: { Q150DocumentAdapter(document: document) })
        : AdapterRegistration(formatID: .gzip, binaryAdapter: { Q150DocumentAdapter(document: document) })
    return PreviewPipeline(registrations: [registration],
                           reader: Q150Reader(data: Data([1]), reads: Q150Counter(), opens: Q150Counter()), privacy: privacy)
}

@Suite("Q150 hidden-character ownership and decoded text")
struct Q150HiddenContentOwnershipTests {
    @Test func convertedTextParticipatesWithoutInventingSourceEncoding() {
        let document = ParsedTextDocument(text: "visible\u{200B}", origin: .converted)
        #expect(document.decodedEncoding == nil)
        for (name, path) in q150Paths(document: document) {
            #expect(HiddenContentScanner.appliesTo(path, document: document) == ["text", "binary", "randomAccess"].contains(name), "\(name)")
        }
    }

    @Test func decodedTextParticipatesButSummariesAndNontextPathsStayExcluded() {
        let decoded = ParsedTextDocument(text: "visible\u{200B}", decodedEncoding: .utf16LittleEndian)
        for (name, path) in q150Paths(document: decoded) {
            #expect(HiddenContentScanner.appliesTo(path, document: decoded) == ["text", "binary", "randomAccess"].contains(name), "\(name)")
        }
        for encoding in ([nil, .utf8] as [TextEncoding?]) {
            let summary = ParsedTextDocument(text: "derived\u{200B}", decodedEncoding: encoding, origin: .summary)
            for (name, path) in q150Paths(document: summary) {
                #expect(!HiddenContentScanner.appliesTo(path, document: summary), "\(name)")
            }
        }
        let source = ParsedTextDocument(text: "source\u{200B}")
        for (name, path) in q150Paths(document: source) {
            #expect(HiddenContentScanner.appliesTo(path, document: source) == (name == "text"), "\(name)")
        }
    }

    @Test func realConvertedDocumentsScanOnlyConcealedDisplayedTextWithoutChangingTheSource() async throws {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        for fixture in q150ConvertedFixtures() {
            let url = try q150Write(fixture.bytes, name: fixture.name)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard case .ready(let presentation) = await pipeline.preview(url: url) else {
                Issue.record("No converted preview for \(fixture.name)"); continue
            }
            #expect(presentation.formatID == fixture.formatID)
            #expect(presentation.origin == .converted && presentation.encoding == .utf8)
            #expect(!presentation.text.contains("synthetic\u{200B}credential"))
            #expect(presentation.redactionCount == 1)
            let finding = try #require(q150Finding(.hiddenZeroWidth, in: presentation), "\(fixture.name)")
            let line = try #require(presentation.text.components(separatedBy: "\n").firstIndex { $0.contains("Visible\u{200B}") }) + 1
            #expect(finding.count == 1 && finding.lines == [line], "\(fixture.name)")
            #expect(finding.detail == .none)
            #expect(try Data(contentsOf: url) == fixture.bytes)
            #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
            #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [fixture.name])
        }
    }

    @Test func convertedBinaryAndRandomAccessLinesFollowMultilineConcealment() async throws {
        let privateKey = "-----BEGIN PRIVATE KEY-----\nc3ludGhldGlj\nc3ludGhldGlj\n-----END PRIVATE KEY-----"
        let source = "first\n\(privateKey)\nmiddle\nlast\u{200B}\n"
        for randomAccess in [false, true] {
            let name = randomAccess ? "synthetic.fb2" : "synthetic.gz"
            let outcome = await q150ConvertedPipeline(source, randomAccess: randomAccess).preview(url: URL(fileURLWithPath: "/fixtures/\(name)"))
            guard case .ready(let presentation) = outcome else { Issue.record("No converted preview"); continue }
            #expect(presentation.text == "first\n••••\nmiddle\nlast\u{200B}\n")
            let finding = try #require(q150Finding(.hiddenZeroWidth, in: presentation))
            #expect(finding.count == 1 && finding.lines == [4])
            #expect(q150Finding(.secretPrivateKey, in: presentation)?.lines == [2])
        }
    }

    @Test func convertedTagDetailsUseTheInjectedPrivacyFilter() async throws {
        final class Filter: PreviewPrivacyFiltering {
            let calls = Q150Counter()
            func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText {
                calls.increment()
                return try DefaultPrivacyFilter().filter(document, context: context)
            }
        }
        let text = "Visible note." + q150Tagged("do this: password=hunter2-synthetic") + "\n"
        for randomAccess in [false, true] {
            let filter = Filter(), name = randomAccess ? "synthetic.fb2" : "synthetic.gz"
            let outcome = await q150ConvertedPipeline(text, randomAccess: randomAccess, privacy: filter)
                .preview(url: URL(fileURLWithPath: "/fixtures/\(name)"))
            guard case .ready(let presentation) = outcome else { Issue.record("No converted preview"); continue }
            guard case .decodedText(let decoded)? = q150Finding(.hiddenUnicodeTags, in: presentation)?.detail else {
                Issue.record("No filtered Tag detail"); continue
            }
            #expect(decoded.hasPrefix("do this: ") && decoded.contains("••••"))
            #expect(!decoded.contains("hunter2"))
            #expect(filter.calls.value == 2)
            #expect(presentation.text.unicodeScalars.elementsEqual(text.unicodeScalars))
        }
    }

    @Test func gzipRetainsTheActualDecodedEncodingAndScansItsConcealedText() async throws {
        let text = "password=synthetic\u{200B}credential\nVisible\u{200B} note.\n"
        let payloads: [(Data, TextEncoding)] = [
            (Data(text.utf8), .utf8), (Data([0xef, 0xbb, 0xbf]) + Data(text.utf8), .utf8),
            (Data([0xff, 0xfe]) + (try #require(text.data(using: .utf16LittleEndian))), .utf16LittleEndian),
            (Data([0xfe, 0xff]) + (try #require(text.data(using: .utf16BigEndian))), .utf16BigEndian)
        ]
        for (payload, encoding) in payloads {
            let compressed = try q150GZIP(payload)
            let document = try GZIPPreviewAdapter().parse(FileBytes(data: compressed), context: q150Context)
            #expect(document.text.unicodeScalars.elementsEqual(text.unicodeScalars))
            #expect(document.decodedEncoding == encoding)
            #expect(document.origin == .source)
            let url = try q150Write(compressed, name: "synthetic.gz")
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: url)
            guard case .ready(let presentation) = outcome else { Issue.record("No gzip preview"); continue }
            #expect(presentation.encoding == encoding)
            #expect(presentation.text == "password=••••\nVisible\u{200B} note.\n")
            let finding = try #require(q150Finding(.hiddenZeroWidth, in: presentation))
            #expect(finding.count == 1 && finding.lines == [2])
            #expect(try Data(contentsOf: url) == compressed)
        }
    }

    @Test func compressedBinaryAndTARPayloadsRemainUnscannedSummaries() throws {
        for bytes in [Data([0, 0xff]), Data(repeating: 0, count: 1024)] {
            let document = try CompressedStreamPayload.document(bytes, streamName: "GZIP", context: q150Context)
            #expect(document.origin == .summary && document.decodedEncoding == nil)
            let path = AdapterRegistration(formatID: .gzip, binaryAdapter: { GZIPPreviewAdapter() }).inputPath
            #expect(!HiddenContentScanner.appliesTo(path, document: document))
        }
    }

    @Test func summaryTextCannotProduceHiddenFindingsEvenWhenItReportsAnEncoding() async throws {
        let document = ParsedTextDocument(text: "derived\u{200B} fact", decodedEncoding: .utf8, origin: .summary)
        let registrations = [AdapterRegistration(formatID: .plainText) { Q150DocumentAdapter(document: document) },
                             AdapterRegistration(formatID: .gzip, binaryAdapter: { Q150DocumentAdapter(document: document) }),
                             AdapterRegistration(formatID: .fictionBook, randomAccessAdapter: { Q150DocumentAdapter(document: document) })]
        let pipeline = PreviewPipeline(registrations: registrations,
            reader: Q150Reader(data: Data("input".utf8), reads: Q150Counter(), opens: Q150Counter()))
        for name in ["synthetic.txt", "synthetic.gz", "synthetic.fb2"] {
            guard case .ready(let presentation) = await pipeline.preview(url: URL(fileURLWithPath: "/fixtures/\(name)")) else {
                Issue.record("No summary preview"); continue
            }
            #expect(presentation.origin == .summary)
            #expect(q150HiddenFindings(presentation).isEmpty)
        }
    }

    @Test func disabledConvertedAndCompressedTypesNeverReadOrConstructAdapters() async {
        for (formatID, name, randomAccess) in [(FormatID.epub, "synthetic.epub", true), (.fictionBook, "synthetic.fb2", true),
                                              (.webArchive, "synthetic.mhtml", true), (.gzip, "synthetic.gz", false)] {
            let reads = Q150Counter(), opens = Q150Counter(), factories = Q150Counter()
            let document = ParsedTextDocument(text: "hidden\u{200B}", origin: .converted)
            let registration = randomAccess
                ? AdapterRegistration(formatID: formatID, randomAccessAdapter: { factories.increment(); return Q150DocumentAdapter(document: document) })
                : AdapterRegistration(formatID: formatID, binaryAdapter: { factories.increment(); return Q150DocumentAdapter(document: document) })
            let pipeline = PreviewPipeline(registrations: [registration], reader: Q150Reader(data: Data([1]), reads: reads, opens: opens))
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: formatID)
            #expect(await pipeline.preview(url: URL(fileURLWithPath: "/fixtures/\(name)"), preferences: preferences) == .disabledByUser(formatID))
            #expect(reads.value == 0 && opens.value == 0 && factories.value == 0)
        }
    }

    @Test func archiveNamesRetainScalarOnlyBidiEvidenceIncludingMarksInRTLScripts() throws {
        let values: [UInt32] = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
        for value in values { #expect(HiddenCharacters.isBidirectionalControl(Unicode.Scalar(value)!)) }
        for value: UInt32 in [0x061B, 0x061D, 0x200D, 0x2010, 0x2029, 0x202F, 0x2065, 0x206A, 0xE0001] {
            #expect(!HiddenCharacters.isBidirectionalControl(Unicode.Scalar(value)!))
        }
        let names = values.map { "שלום\(Unicode.Scalar($0)!).txt" }
        let report = try ArchiveRiskAnalyzer.analyze(names.map { ContainerEntry(path: $0, kind: .file, size: 1) }, context: q150Context)
        #expect(report.entryRisks.allSatisfy { $0 == [.directionalName] })
        let finding = try #require(report.findings.first { $0.kind == .archiveDirectionalName })
        #expect(finding.count == values.count && finding.lines.isEmpty && finding.detail == .none)
        // Text context exempts direction marks in RTL lines; filename risk deliberately retains them.
        for mark in ["\u{061C}", "\u{200E}", "\u{200F}"] {
            #expect(HiddenCharacters.spans(in: "שלום\(mark)").isEmpty)
        }
        let ordinary = ["שלום.txt", "emoji👩‍💻.txt", "zero\u{200B}width.txt", "symbol\u{E0A0}.txt"]
        let clean = try ArchiveRiskAnalyzer.analyze(ordinary.map { ContainerEntry(path: $0, kind: .file, size: 1) }, context: q150Context)
        #expect(clean.entryRisks.allSatisfy { !$0.contains(.directionalName) })
    }

    @Test func compressedTextStillStopsAtTheOutputBudgetAndCancellation() async throws {
        let compressed = try q150GZIP(Data("Visible\u{200B} note.\n".utf8))
        #expect(throws: PreviewFailure.outputTooLarge) {
            try GZIPPreviewAdapter().parse(FileBytes(data: compressed),
                context: RequestContext(budget: PreviewBudget(maxOutputUTF8Bytes: 8, maxMilliseconds: 30_000)))
        }
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try GZIPPreviewAdapter().parse(FileBytes(data: compressed), context: q150Context)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
    }
}
