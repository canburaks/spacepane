import CryptoKit
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
import zlib
import PreviewContracts
import PreviewCore
import PreviewFormats

private let secret = "synthetic-secret-value"

// MARK: Fixtures (built in memory; stored-only ZIPs are enough for the pipeline)

private func le(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

private func zip(_ files: [(String, Data)]) -> Data {
    var output = Data()
    var central = Data()
    for (name, payload) in files {
        let nameData = Data(name.utf8)
        let crc = payload.withUnsafeBytes { buffer -> UInt32 in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(crc32(0, base, uInt(buffer.count)))
        }
        let offset = output.count
        output += le(0x04034b50, 4) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(0x21, 2) + le(UInt64(crc), 4)
        output += le(UInt64(payload.count), 4) + le(UInt64(payload.count), 4) + le(UInt64(nameData.count), 2) + le(0, 2) + nameData + payload
        central += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(0x21, 2) + le(UInt64(crc), 4)
        central += le(UInt64(payload.count), 4) + le(UInt64(payload.count), 4) + le(UInt64(nameData.count), 2) + le(0, 2) + le(0, 2)
        central += le(0, 2) + le(0, 2) + le(0, 4) + le(UInt64(offset), 4) + nameData
    }
    let start = output.count
    output += central + le(0x06054b50, 4) + le(0, 2) + le(0, 2) + le(UInt64(files.count), 2) + le(UInt64(files.count), 2)
    output += le(UInt64(central.count), 4) + le(UInt64(start), 4) + le(0, 2)
    return output
}

private func png(_ width: Int, _ height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

private func comicData() -> Data {
    zip([("ComicInfo.xml", Data("<ComicInfo><Title>Issue password=\(secret)</Title><Series>Series</Series></ComicInfo>".utf8)),
         ("p1.png", png(10, 14)), ("p2.png", png(12, 14))])
}

private func epubData() -> Data {
    let package = """
    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:test</dc:identifier><dc:title>Book</dc:title><dc:creator>Author</dc:creator></metadata>
    <manifest><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>
    """
    let chapter = "<html><body><h1>One</h1><p>Plain words.</p><p>password: \(secret)</p><p>api_key = \(secret)</p><p>db_password: \(secret)</p><p>AWS_SECRET_ACCESS_KEY=\(secret)</p></body></html>"
    return zip([("mimetype", Data("application/epub+zip".utf8)),
                ("META-INF/container.xml", Data(#"<container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#.utf8)),
                ("OEBPS/content.opf", Data(package.utf8)), ("OEBPS/cover.png", png(20, 30)), ("OEBPS/c1.xhtml", Data(chapter.utf8))])
}

private func fictionBookData() -> Data {
    Data("""
    <?xml version="1.0" encoding="utf-8"?><FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>
    <book-title>Story</book-title><coverpage><image l:href="#c.png"/></coverpage></title-info></description>
    <body><section><title><p>Part</p></title><p>Words.</p><p>password: \(secret)</p></section></body>
    <binary id="c.png" content-type="image/png">\(png(8, 8).base64EncodedString())</binary></FictionBook>
    """.utf8)
}

private func webArchiveData() -> Data {
    Data(("Subject: Page\r\nContent-Type: multipart/related; boundary=\"x\"\r\n\r\n--x\r\nContent-Type: text/html\r\n"
          + "Content-Location: https://example.com/\r\n\r\n<html><body><h1>Page</h1><p>Words.</p><p>token: \(secret)</p></body></html>\r\n--x--\r\n").utf8)
}

private struct Fixture {
    let id: FormatID
    let filename: String
    let data: Data
    let hasImages: Bool
}

private let fixtures: [Fixture] = [
    Fixture(id: .comicBook, filename: "book.cbz", data: comicData(), hasImages: true),
    Fixture(id: .epub, filename: "book.epub", data: epubData(), hasImages: true),
    Fixture(id: .fictionBook, filename: "book.fb2", data: fictionBookData(), hasImages: true),
    Fixture(id: .webArchive, filename: "page.mhtml", data: webArchiveData(), hasImages: false)
]

private func write(_ data: Data, named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private func digest(_ url: URL) throws -> (String, Date?) {
    (SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(),
     try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
}

private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

// MARK: Disabled types

private final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct SpyReader: PreviewFileReading {
    let reads: Counter
    let opens: Counter
    func read(url: URL, context: RequestContext) throws -> FileBytes { reads.increment(); return FileBytes(data: Data()) }
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource { opens.increment(); throw PreviewFailure.unreadableFile }
}

@Suite("Document formats through the pipeline")
struct DocumentPipelineTests {
    @Test func aDisabledTypeIsNeverOpenedOrConstructedAndDoesNotFallBackToAnotherFormat() async {
        for fixture in fixtures {
            let reads = Counter(), opens = Counter(), factories = Counter()
            let custom = PreviewPipeline(
                registrations: DocumentFormatAdapters.registrations.map { original in
                    AdapterRegistration(formatID: original.formatID, randomAccessAdapter: { factories.increment(); return ComicBookAdapter() })
                },
                reader: SpyReader(reads: reads, opens: opens))
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: fixture.id)
            let url = URL(fileURLWithPath: "/unused/\(fixture.filename)")
            #expect(await custom.preview(url: url, preferences: preferences) == .disabledByUser(fixture.id), "\(fixture.id.rawValue)")
            #expect(await custom.inspect(url: url, preferences: preferences) == .disabledByUser(fixture.id))
            #expect(reads.value == 0 && opens.value == 0 && factories.value == 0, "\(fixture.id.rawValue)")
            // Enabled, the same request opens the file exactly once through random access and never as plain text.
            _ = await custom.preview(url: url)
            #expect(opens.value == 1 && reads.value == 0, "\(fixture.id.rawValue)")
        }
    }

    // MARK: Privacy and presentation

    @Test func presentationsCarryValidImagesAndConcealEverySecret() async throws {
        for fixture in fixtures {
            let url = try write(fixture.data, named: fixture.filename)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            guard case .ready(let presentation) = await pipeline.preview(url: url) else {
                Issue.record("\(fixture.id.rawValue) did not preview"); continue
            }
            #expect(presentation.formatID == fixture.id)
            #expect(!presentation.text.contains(secret), "\(fixture.id.rawValue)")
            #expect(presentation.redactionCount > 0, "\(fixture.id.rawValue)")
            #expect(presentation.images.isEmpty != fixture.hasImages, "\(fixture.id.rawValue)")
            #expect(presentation.images.allSatisfy { $0.isValid })
            #expect(presentation.lineCount == presentation.text.components(separatedBy: "\n").count)
            switch fixture.id {
            case .comicBook:
                #expect(presentation.syntax == .json)
                #expect(presentation.images.map(\.role) == [.page, .page])
                #expect(presentation.text.contains("••••"))
            case .epub, .fictionBook, .webArchive:
                #expect(presentation.syntax == .markdown)
                #expect(presentation.text.contains("••••"))
                if fixture.hasImages { #expect(presentation.images.first?.role == .cover) }
            default: break
            }
        }
    }

    @Test func chapterTextStaysReadableAroundConcealedLines() async throws {
        let url = try write(epubData(), named: "book.epub")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("no preview"); return }
        #expect(presentation.text.contains("# One"))
        #expect(presentation.text.contains("Plain words."))
        #expect(presentation.text.contains("title: Book"))
        #expect(presentation.text.contains("author: Author"))
    }

    // MARK: Source is never modified

    @Test func previewingNeverModifiesTheSourceFile() async throws {
        for fixture in fixtures {
            let url = try write(fixture.data, named: fixture.filename)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let before = try digest(url)
            for _ in 0..<2 { _ = await pipeline.preview(url: url) }
            let after = try digest(url)
            #expect(before.0 == after.0 && before.1 == after.1, "\(fixture.id.rawValue)")
            #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [fixture.filename])
        }
    }

    // MARK: Hostile and damaged inputs

    @Test func truncatedAndBitFlippedFilesNeverCrashAndTruncationsNeverLeakSecrets() async throws {
        for fixture in fixtures {
            // A bit flip can rewrite a secret's key (`token` becomes `tok?n`), so only truncations, which keep
            // every key intact, are held to the concealment guarantee; flips must still end in a clean state.
            var variants: [(data: Data, keepsKeys: Bool)] = [(Data(), true), (Data(fixture.data.prefix(1)), true)]
            for fraction in stride(from: 1, to: 16, by: 2) { variants.append((Data(fixture.data.prefix(fixture.data.count * fraction / 16)), true)) }
            for offset in stride(from: 0, to: fixture.data.count, by: max(1, fixture.data.count / 24)) {
                var flipped = fixture.data
                flipped[offset] ^= 0x5A
                variants.append((flipped, false))
            }
            for (index, variant) in variants.enumerated() {
                let url = try write(variant.data, named: fixture.filename)
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                switch await pipeline.preview(url: url) {
                case .ready(let presentation):
                    if variant.keepsKeys { #expect(!presentation.text.contains(secret), "\(fixture.id.rawValue) variant \(index)") }
                    #expect(presentation.images.allSatisfy { $0.isValid })
                case .unavailable: break
                case .disabledByUser, .geometryReady, .cancelled: Issue.record("\(fixture.id.rawValue) variant \(index) had an impossible outcome")
                }
            }
        }
    }

    // MARK: Notebook figures through the bounded byte path

    @Test func notebookFiguresReachThePresentationAndInvalidLargePayloadsBecomePlaceholders() async throws {
        func notebook(_ payload: String) -> Data {
            Data(#"{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"cell_type":"code","metadata":{},"execution_count":1,"source":"plot()","outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"\#(payload)","text/plain":"<Figure>"}}]}]}"#.utf8)
        }
        let small = try write(notebook(png(8, 8).base64EncodedString()), named: "plot.ipynb")
        defer { try? FileManager.default.removeItem(at: small.deletingLastPathComponent()) }
        guard case .ready(let presentation) = await pipeline.preview(url: small) else { Issue.record("no preview"); return }
        #expect(presentation.images.count == 1)
        #expect(presentation.images.first?.role == .figure)
        // An invalid large payload is omitted from Source without claiming that a figure exists.
        let huge = try write(notebook(String(repeating: "A", count: 40_000)), named: "huge.ipynb")
        defer { try? FileManager.default.removeItem(at: huge.deletingLastPathComponent()) }
        guard case .ready(let omitted) = await pipeline.preview(url: huge) else { Issue.record("no bounded preview"); return }
        #expect(omitted.origin == .converted)
        #expect(omitted.images.isEmpty)
        #expect(omitted.text.contains(#""image/png":null"#))
        #expect(!omitted.text.contains(String(repeating: "A", count: 40_000)))
    }
}
