import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// MARK: Fixture builders

private let containerXML = """
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
"""

private func xhtml(_ body: String, head: String = "") -> String {
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>t</title>\(head)</head><body>\(body)</body></html>"
}

/// An OPF with `chapters` as manifest ids c1, c2, … listed in the same order in the spine.
private func opf(title: String? = "Synthetic Book", creators: [String] = ["Ann Author"], chapters: [String],
                 cover: String? = nil, coverMeta: Bool = false, navigation: String? = nil, ncx: String? = nil,
                 metadataExtra: String = "", spineExtra: String = "") -> String {
    var manifest = chapters.enumerated().map { #"<item id="c\#($0.offset + 1)" href="\#($0.element)" media-type="application/xhtml+xml"/>"# }
    if let cover {
        manifest.append(#"<item id="cover" href="\#(cover)" media-type="image/png"\#(coverMeta ? "" : #" properties="cover-image""#)/>"#)
    }
    if let navigation { manifest.append(#"<item id="nav" href="\#(navigation)" media-type="application/xhtml+xml" properties="nav"/>"#) }
    if let ncx { manifest.append(#"<item id="ncx" href="\#(ncx)" media-type="application/x-dtbncx+xml"/>"#) }
    let spine = chapters.indices.map { #"<itemref idref="c\#($0 + 1)"/>"# }.joined() + spineExtra
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    \(title.map { "<dc:title>\($0)</dc:title>" } ?? "")
    \(creators.map { "<dc:creator opf:role=\"aut\">\($0)</dc:creator>" }.joined())
    <dc:language>en</dc:language><dc:publisher>Synthetic Press</dc:publisher><dc:date>2026-01-02</dc:date>
    <dc:identifier id="other">urn:other</dc:identifier><dc:identifier id="bookid">urn:uuid:1234</dc:identifier>
    <dc:description>&lt;p&gt;A &lt;b&gt;synthetic&lt;/b&gt; description.&lt;/p&gt;</dc:description>
    \(coverMeta ? #"<meta name="cover" content="cover"/>"# : "")\(metadataExtra)
    </metadata>
    <manifest>\(manifest.joined())</manifest>
    <spine\(ncx == nil ? "" : #" toc="ncx""#)>\(spine)</spine></package>
    """
}

private func epub(opf package: String, chapters: [(String, String)], extra: [TestZIPEntry] = [],
                  container: String? = containerXML, deflate: Bool = true) -> Data {
    var entries = [TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8))]
    if let container { entries.append(TestZIPEntry(name: "META-INF/container.xml", data: Data(container.utf8), deflate: deflate)) }
    entries.append(TestZIPEntry(name: "OEBPS/content.opf", data: Data(package.utf8), deflate: deflate))
    for (path, content) in chapters { entries.append(TestZIPEntry(name: "OEBPS/" + path, data: Data(content.utf8), deflate: deflate)) }
    return TestZIP.make(entries + extra)
}

private func frontMatter(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    var lines = text.components(separatedBy: "\n").makeIterator()
    guard lines.next() == "---" else { return result }
    while let line = lines.next(), line != "---" {
        if let colon = line.firstIndex(of: ":") { result[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
    }
    return result
}

private func encryption(_ entries: [(algorithm: String, uri: String)]) -> TestZIPEntry {
    let items = entries.map {
        "<enc:EncryptedData xmlns:enc=\"http://www.w3.org/2001/04/xmlenc#\"><enc:EncryptionMethod Algorithm=\"\($0.algorithm)\"/>"
            + "<enc:CipherData><enc:CipherReference URI=\"\($0.uri)\"/></enc:CipherData></enc:EncryptedData>"
    }.joined()
    return TestZIPEntry(name: "META-INF/encryption.xml", data: Data("<encryption>\(items)</encryption>".utf8))
}

private let aes = "http://www.w3.org/2001/04/xmlenc#aes128-cbc"

@Suite("EPUB adapter")
struct EPUBAdapterTests {
    // MARK: Package, metadata and chapters

    @Test func readsMetadataAndChaptersInSpineOrderAsMarkdownWithFrontMatter() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml", "b.xhtml"]),
                        chapters: [("a.xhtml", xhtml("<h1>First</h1><p>Alpha &amp; <em>omega</em>.</p>")),
                                   ("b.xhtml", xhtml("<h1>Second</h1><ul><li>One</li><li>Two</li></ul>"))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(document.syntax == .markdown)
        #expect(!document.usesStructuredPrivacy)
        let fields = frontMatter(document.text)
        #expect(fields["title"] == "Synthetic Book")
        #expect(fields["author"] == "Ann Author")
        #expect(fields["language"] == "en")
        #expect(fields["publisher"] == "Synthetic Press")
        #expect(fields["date"] == "2026-01-02")
        // The identifier named by `unique-identifier` wins over the first one.
        #expect(fields["identifier"] == "urn:uuid:1234")
        // Escaped HTML in the description is reduced to its words.
        #expect(fields["description"] == "A synthetic description.")
        #expect(document.text.hasSuffix("---\n\n# First\n\nAlpha & *omega*.\n\n# Second\n\n- One\n- Two\n"))
        #expect(fields["partial"] == nil)
        #expect(fields["drm"] == nil)
    }

    @Test func spineOrderDecidesNotManifestOrderAndSkipsDanglingReferences() throws {
        let package = opf(chapters: ["a.xhtml", "b.xhtml"]).replacingOccurrences(
            of: "<itemref idref=\"c1\"/><itemref idref=\"c2\"/>", with: "<itemref idref=\"c2\"/><itemref idref=\"missing\"/><itemref idref=\"c1\" linear=\"no\"/>")
        let book = epub(opf: package, chapters: [("a.xhtml", xhtml("<p>AAA</p>")), ("b.xhtml", xhtml("<p>BBB</p>"))])
        let text = try parseDocument(EPUBAdapter(), book).text
        let b = try #require(text.range(of: "BBB"))
        let a = try #require(text.range(of: "AAA"))
        #expect(b.lowerBound < a.lowerBound)
    }

    @Test func manifestOrderIsTheFallbackWhenTheSpineIsEmpty() throws {
        let package = opf(chapters: ["a.xhtml", "b.xhtml"]).replacingOccurrences(of: "<itemref idref=\"c1\"/><itemref idref=\"c2\"/>", with: "")
        let book = epub(opf: package, chapters: [("a.xhtml", xhtml("<p>AAA</p>")), ("b.xhtml", xhtml("<p>BBB</p>"))])
        let text = try parseDocument(EPUBAdapter(), book).text
        #expect(text.contains("AAA") && text.contains("BBB"))
    }

    @Test func percentEncodedAndSubdirectoryReferencesResolveRelativeToThePackage() throws {
        let package = opf(chapters: ["text/Chapter%201.xhtml"])
        let book = epub(opf: package, chapters: [("text/Chapter 1.xhtml", xhtml("<p>Found it</p>"))])
        #expect(try parseDocument(EPUBAdapter(), book).text.contains("Found it"))
    }

    @Test func traversalAndExternalReferencesAreNeverFollowed() throws {
        let package = opf(chapters: ["../../outside.xhtml", "https://example.com/remote.xhtml", "ok.xhtml"])
        let book = epub(opf: package, chapters: [("ok.xhtml", xhtml("<p>Only this</p>"))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(document.text.contains("Only this"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    // MARK: Table of contents

    @Test func navigationTitlesBecomeHeadingsForChaptersWithoutOne() throws {
        let nav = xhtml("<nav epub:type=\"toc\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><ol><li><a href=\"a.xhtml\">Opening</a></li>"
                        + "<li><a href=\"b.xhtml#part\">Closing</a></li></ol></nav>")
        let book = epub(opf: opf(chapters: ["a.xhtml", "b.xhtml"], navigation: "nav.xhtml"),
                        chapters: [("a.xhtml", xhtml("<p>no heading here</p>")), ("b.xhtml", xhtml("<h2>Own heading</h2><p>x</p>")),
                                   ("nav.xhtml", nav)])
        let text = try parseDocument(EPUBAdapter(), book).text
        #expect(text.contains("# Opening\n\nno heading here\n"))
        #expect(text.contains("## Own heading\n\nx\n"))
        #expect(!text.contains("Closing"))
    }

    @Test func ncxTitlesAreUsedWhenThereIsNoNavigationDocument() throws {
        let ncx = """
        <?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
        <navPoint id="p1"><navLabel><text>Prologue</text></navLabel><content src="a.xhtml"/></navPoint></navMap></ncx>
        """
        let book = epub(opf: opf(chapters: ["a.xhtml"], ncx: "toc.ncx"),
                        chapters: [("a.xhtml", xhtml("<p>words</p>")), ("toc.ncx", ncx)])
        #expect(try parseDocument(EPUBAdapter(), book).text.contains("# Prologue\n\nwords\n"))
    }

    @Test func missingNavigationAndCoverFilesAreNotErrors() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml"], cover: "gone.png", navigation: "gone.xhtml"),
                        chapters: [("a.xhtml", xhtml("<p>text</p>"))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(document.images.isEmpty)
        #expect(document.text.contains("text"))
    }

    // MARK: Cover

    @Test func coverImageIsExtractedFromThePropertyOrTheLegacyMetaHint() throws {
        let png = TestImages.png(30, 40)
        for legacy in [false, true] {
            let book = epub(opf: opf(chapters: ["a.xhtml"], cover: "cover.png", coverMeta: legacy),
                            chapters: [("a.xhtml", xhtml("<p>x</p>"))],
                            extra: [TestZIPEntry(name: "OEBPS/cover.png", data: png)])
            let document = try parseDocument(EPUBAdapter(), book)
            let cover = try #require(document.images.first)
            #expect(document.images.count == 1)
            #expect(cover.role == .cover)
            #expect(cover.pixelWidth == 30 && cover.pixelHeight == 40)
            #expect(cover.data == png)
        }
    }

    @Test func aCoverThatIsNotARasterImageIsIgnored() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml"], cover: "cover.png"), chapters: [("a.xhtml", xhtml("<p>x</p>"))],
                        extra: [TestZIPEntry(name: "OEBPS/cover.png", data: Data("<svg/>".utf8))])
        #expect(try parseDocument(EPUBAdapter(), book).images.isEmpty)
    }

    @Test func aCoverLargerThanItsShareOfTheReadBudgetIsSkipped() throws {
        let noise = TestImages.noisePNG(100, 100)   // About 40 KB, incompressible.
        let book = epub(opf: opf(chapters: ["a.xhtml"], cover: "cover.png"), chapters: [("a.xhtml", xhtml("<p>x</p>"))],
                        extra: [TestZIPEntry(name: "OEBPS/cover.png", data: noise)])
        #expect(noise.count > 20_000)
        // 60% of the read budget caps a cover so the text keeps most of it.
        let small = try parseDocument(EPUBAdapter(), book, budget: PreviewBudget(maxInputBytes: book.count + 8_000, maxMilliseconds: 30_000))
        #expect(small.images.isEmpty)
        #expect(small.text.contains("x"))
        let roomy = try parseDocument(EPUBAdapter(), book, budget: PreviewBudget(maxInputBytes: 400_000, maxMilliseconds: 30_000))
        #expect(roomy.images.count == 1)
    }

    // MARK: Missing and malformed packages

    @Test func notAnEPUBFailsAsMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(EPUBAdapter(), Data("not a zip at all".utf8)) }
        let noContainer = epub(opf: opf(chapters: []), chapters: [], container: nil)
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(EPUBAdapter(), noContainer) }
        let danglingContainer = TestZIP.make([("META-INF/container.xml", Data(containerXML.utf8))])
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(EPUBAdapter(), danglingContainer) }
        let noPackage = epub(opf: "<html/>", chapters: [])
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(EPUBAdapter(), noPackage) }
    }

    @Test func aMissingChapterIsSkippedAndReportedAsPartial() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml", "gone.xhtml", "c.xhtml"]),
                        chapters: [("a.xhtml", xhtml("<p>AAA</p>")), ("c.xhtml", xhtml("<p>CCC</p>"))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(document.text.contains("AAA") && document.text.contains("CCC"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    @Test func aBookWithOnlyMetadataStillPreviews() throws {
        let book = epub(opf: opf(chapters: []), chapters: [])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(frontMatter(document.text)["title"] == "Synthetic Book")
    }

    @Test func aBookWithNothingToShowFailsInsteadOfReturningEmptyText() {
        let book = epub(opf: opf(title: nil, creators: [], chapters: ["a.xhtml"]).replacingOccurrences(of: "<dc:language>en</dc:language>", with: "")
            .replacingOccurrences(of: "<dc:publisher>Synthetic Press</dc:publisher><dc:date>2026-01-02</dc:date>", with: "")
            .replacingOccurrences(of: "<dc:identifier id=\"other\">urn:other</dc:identifier><dc:identifier id=\"bookid\">urn:uuid:1234</dc:identifier>", with: "")
            .replacingOccurrences(of: "<dc:description>&lt;p&gt;A &lt;b&gt;synthetic&lt;/b&gt; description.&lt;/p&gt;</dc:description>", with: ""),
            chapters: [("a.xhtml", "<html><body><script>x</script></body></html>")])
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(EPUBAdapter(), book) }
    }

    @Test func aCorruptChapterMemberIsSkipped() throws {
        var book = epub(opf: opf(chapters: ["a.xhtml", "b.xhtml"]),
                        chapters: [("a.xhtml", xhtml("<p>MARKERAAA</p>")), ("b.xhtml", xhtml("<p>BBB</p>"))], deflate: false)
        let range = try #require(book.range(of: Data("MARKERAAA".utf8)))
        book[range.lowerBound] ^= 0x01   // The stored bytes no longer match their CRC-32.
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(!document.text.contains("AAA"))
        #expect(document.text.contains("BBB"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    // MARK: Safety: nothing active, nothing external

    @Test func scriptsStylesFramesAndExternalResourcesNeverReachTheText() throws {
        let page = xhtml("""
        <p>Visible</p><script>alert('boom')</script><iframe src="https://evil.example/x"></iframe>
        <img src="https://evil.example/pixel.gif" alt="logo"/><link rel="stylesheet" href="https://evil.example/a.css"/>
        <object data="x.swf">obj</object><form action="https://evil.example"><input name="q"/>formtext</form>
        <a href="https://evil.example/?token=1">link text</a>
        """, head: "<style>body{background:url(https://evil.example/bg.png)}</style>")
        let text = try parseDocument(EPUBAdapter(), epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", page)])).text
        for forbidden in ["boom", "evil.example", "formtext", "obj", "background", "token"] { #expect(!text.contains(forbidden), "\(forbidden)") }
        #expect(text.contains("Visible") && text.contains("![logo]()") && text.contains("link text"))
    }

    @Test func entityDeclarationsInPackageFilesAreNeverExpanded() throws {
        let hostile = "<?xml version=\"1.0\"?><!DOCTYPE package [<!ENTITY a \"aaaaaaaaaa\"><!ENTITY b \"&a;&a;&a;&a;&a;&a;&a;&a;\">]>"
        let package = opf(title: "&b;", chapters: ["a.xhtml"]).replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"utf-8\"?>", with: hostile)
        let document = try parseDocument(EPUBAdapter(), epub(opf: package, chapters: [("a.xhtml", xhtml("<p>x</p>"))]))
        #expect(frontMatter(document.text)["title"] == "\"&b;\"")
    }

    // MARK: DRM

    @Test func protectedChaptersAreOmittedAndFlagged() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml", "b.xhtml"]),
                        chapters: [("a.xhtml", "ciphertext not markup"), ("b.xhtml", xhtml("<p>Readable</p>"))],
                        extra: [encryption([(aes, "OEBPS/a.xhtml")])])
        let document = try parseDocument(EPUBAdapter(), book)
        let fields = frontMatter(document.text)
        #expect(fields["drm"] == "true")
        #expect(fields["title"] == "Synthetic Book")
        #expect(document.text.contains("Readable"))
        #expect(!document.text.contains("ciphertext"))
    }

    @Test func aFullyProtectedBookShowsItsMetadataAndTheFlag() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", "binary ciphertext")],
                        extra: [encryption([(aes, "OEBPS/a.xhtml")])])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(frontMatter(document.text)["drm"] == "true")
        #expect(frontMatter(document.text)["title"] == "Synthetic Book")
        #expect(!document.text.contains("ciphertext"))
    }

    @Test func aFullyProtectedBookWithoutMetadataFailsAsEncrypted() {
        let bare = opf(title: nil, creators: [], chapters: ["a.xhtml"])
            .replacingOccurrences(of: "<dc:language>en</dc:language><dc:publisher>Synthetic Press</dc:publisher><dc:date>2026-01-02</dc:date>", with: "")
            .replacingOccurrences(of: "<dc:identifier id=\"other\">urn:other</dc:identifier><dc:identifier id=\"bookid\">urn:uuid:1234</dc:identifier>", with: "")
            .replacingOccurrences(of: "<dc:description>&lt;p&gt;A &lt;b&gt;synthetic&lt;/b&gt; description.&lt;/p&gt;</dc:description>", with: "")
        let book = epub(opf: bare, chapters: [("a.xhtml", "ciphertext")], extra: [encryption([(aes, "OEBPS/a.xhtml")])])
        #expect(throws: PreviewFailure.encryptedContent) { try parseDocument(EPUBAdapter(), book) }
    }

    @Test func fontObfuscationIsNotDigitalRightsManagement() throws {
        let book = epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", xhtml("<p>Readable</p>"))],
                        extra: [encryption([("http://www.idpf.org/2008/embedding", "OEBPS/font.otf"),
                                            ("http://ns.adobe.com/pdf/enc#RC", "OEBPS/font2.otf")])])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(frontMatter(document.text)["drm"] == nil)
        #expect(document.text.contains("Readable"))
    }

    @Test func aRightsDescriptorMarksTheBookProtectedWhileReadableChaptersStayVisible() throws {
        for descriptor in ["META-INF/rights.xml", "META-INF/sinf.xml"] {
            let book = epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", xhtml("<p>Readable</p>"))],
                            extra: [TestZIPEntry(name: descriptor, data: Data("<rights/>".utf8))])
            let document = try parseDocument(EPUBAdapter(), book)
            #expect(frontMatter(document.text)["drm"] == "true")
            #expect(document.text.contains("Readable"))
        }
    }

    @Test func ciphertextWithoutADescriptorIsNeverShownAsText() throws {
        // A scheme that lists nothing in encryption.xml still leaves non-markup bytes; they must not be decoded.
        let book = epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", String(decoding: [UInt8](repeating: 0xA5, count: 200), as: UTF8.self))],
                        extra: [TestZIPEntry(name: "META-INF/rights.xml", data: Data("<rights/>".utf8))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(frontMatter(document.text)["drm"] == "true")
        #expect(!document.text.contains("\u{FFFD}"))
    }

    @Test func zipLevelEncryptionOfAChapterCountsAsProtected() throws {
        var entries = [TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                       TestZIPEntry(name: "META-INF/container.xml", data: Data(containerXML.utf8)),
                       TestZIPEntry(name: "OEBPS/content.opf", data: Data(opf(chapters: ["a.xhtml"]).utf8))]
        entries.append(TestZIPEntry(name: "OEBPS/a.xhtml", data: Data("secret bytes".utf8), encrypted: true))
        let document = try parseDocument(EPUBAdapter(), TestZIP.make(entries))
        #expect(frontMatter(document.text)["drm"] == "true")
    }

    // MARK: Budgets

    @Test func outputStopsBelowTheRenderedViewLimitAndIsMarkedPartial() throws {
        let paragraph = "<p>" + String(repeating: "lorem ipsum dolor sit amet ", count: 40) + "</p>"
        let chapters = (0..<30).map { ("c\($0).xhtml", xhtml(String(repeating: paragraph, count: 60))) }
        let book = epub(opf: opf(chapters: chapters.map(\.0)), chapters: chapters)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)
        let document = try parseDocument(EPUBAdapter(), book, budget: budget)
        #expect(document.text.utf16.count <= 262_144)
        #expect(document.text.utf16.count > 200_000)
        #expect(frontMatter(document.text)["partial"] == "true")
        #expect(document.text.hasPrefix("---\n"))
    }

    @Test func anExhaustedReadBudgetKeepsEarlierChaptersAndMarksTheRestPartial() throws {
        let chapters = (0..<8).map { ("c\($0).xhtml", xhtml("<h1>Chapter \($0)</h1><p>" + TestImages.noiseText(900, seed: UInt32($0 + 1)) + "</p>")) }
        let book = epub(opf: opf(chapters: chapters.map(\.0)), chapters: chapters)
        let measuring = CountingSource(book)
        let full = try EPUBAdapter().parse(measuring, context: documentContext(PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)))
        #expect(frontMatter(full.text)["partial"] == nil)
        #expect(full.text.contains("# Chapter 7"))
        // Withhold the last chapter's payload from the budget: earlier chapters still read.
        let document = try parseDocument(EPUBAdapter(), book,
                                         budget: PreviewBudget(maxInputBytes: measuring.bytesRequested - 2_000, maxMilliseconds: 30_000))
        #expect(document.text.contains("# Chapter 0"))
        #expect(!document.text.contains("# Chapter 7"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    @Test func aChapterLargerThanTheMemberLimitIsSkipped() throws {
        let huge = xhtml("<p>" + String(repeating: "x", count: 40_000) + "</p>")
        let book = epub(opf: opf(chapters: ["a.xhtml", "b.xhtml"]), chapters: [("a.xhtml", huge), ("b.xhtml", xhtml("<p>small</p>"))])
        // Members may be 4 x maxInputBytes uncompressed: 32,000 bytes here.
        let document = try parseDocument(EPUBAdapter(), book, budget: PreviewBudget(maxInputBytes: 8_000, maxMilliseconds: 30_000))
        #expect(document.text.contains("small"))
        #expect(!document.text.contains("xxxx"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    // MARK: Cancellation

    @Test func cancellationAndExpiredDeadlinePrecedeAnySourceRead() async {
        let book = epub(opf: opf(chapters: ["a.xhtml"]), chapters: [("a.xhtml", xhtml("<p>x</p>"))])
        let source = CountingSource(book)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try EPUBAdapter().parse(source, context: documentContext()); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(source.reads == 0)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try EPUBAdapter().parse(CountingSource(book), context: documentContext(PreviewBudget(maxMilliseconds: 0)))
        }
    }
}
