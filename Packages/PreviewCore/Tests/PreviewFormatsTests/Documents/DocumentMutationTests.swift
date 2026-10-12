import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private struct LCG { var state: UInt64
    mutating func next() -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int(truncatingIfNeeded: state >> 33) } }

private func epubSeed() -> Data {
    let package = """
    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:test</dc:identifier><dc:title>Book</dc:title><dc:creator>Author</dc:creator><meta name="cover" content="cover"/></metadata>
    <manifest><item id="cover" href="cover.png" media-type="image/png"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>
    """
    let chapter = "<html><body><h1>One</h1><p>Plain <b>words</b> &amp; <i>more</i>.</p><ul><li>a</li><li>b<ul><li>c</li></ul></li></ul><table><tr><td>1</td><td>2</td></tr></table><pre>code</pre></body></html>"
    return TestZIP.make([TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
        TestZIPEntry(name: "META-INF/container.xml", data: Data(#"<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"#.utf8), deflate: true),
        TestZIPEntry(name: "OEBPS/content.opf", data: Data(package.utf8), deflate: true), TestZIPEntry(name: "OEBPS/cover.png", data: TestImages.png(20, 30)),
        TestZIPEntry(name: "OEBPS/nav.xhtml", data: Data("<nav><ol><li><a href=\"c1.xhtml\">One</a></li></ol></nav>".utf8)),
        TestZIPEntry(name: "OEBPS/c1.xhtml", data: Data(chapter.utf8), deflate: true)])
}

/// Deterministic mutation testing: byte flips, truncation, insertion, duplication, removal and runs of 0x00/0xFF applied
/// to whole files, and markup-breaking edits applied to the inner documents of freshly built archives (so ZIP checksums
/// stay valid and the parsers behind them are reached). The only acceptable outcomes are a result or a typed
/// `PreviewFailure`; a trap would end the whole test process.
@Suite("Document mutation robustness")
struct DocumentMutationTests {
    @Test func wholeFileMutationsEndInAResultOrATypedFailure() throws {
        let fb2 = Data("""
        <?xml version="1.0" encoding="utf-8"?><FictionBook xmlns:l="x"><description><title-info><book-title>T</book-title><coverpage><image l:href="#c"/></coverpage></title-info></description>
        <body><title><p>B</p></title><section><title><p>S</p></title><p>text <emphasis>e</emphasis></p><poem><stanza><v>v</v></stanza></poem><table><tr><td>1</td></tr></table></section></body>
        <binary id="c" content-type="image/png">\(TestImages.png(8, 8).base64EncodedString())</binary></FictionBook>
        """.utf8)
        let mht = Data("Subject: =?utf-8?B?SGk=?=\r\nContent-Type: multipart/related; boundary=\"b\"\r\n\r\n--b\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<p>caf=C3=A9 =3D x</p>\r\n--b\r\nContent-Type: image/png\r\nContent-Location: http://h/x\r\n\r\nxx\r\n--b--\r\n".utf8)
        let comic = TestZIP.make([TestZIPEntry(name: "ComicInfo.xml", data: Data("<ComicInfo><Title>T</Title><PageCount>2</PageCount></ComicInfo>".utf8)),
                                  TestZIPEntry(name: "1.png", data: TestImages.png(8, 8)), TestZIPEntry(name: "2.jpg", data: TestImages.jpeg(8, 8), deflate: true)])
        let seeds: [(String, Data, any RandomAccessFormatAdapter)] = [("epub", epubSeed(), EPUBAdapter()), ("fb2", fb2, FictionBookAdapter()),
                                                                       ("mht", mht, WebArchiveAdapter()), ("cbz", comic, ComicBookAdapter())]
        var rng = LCG(state: 42)
        var outcomes = 0
        for (name, seed, adapter) in seeds {
            for iteration in 0..<2_000 {
                var data = seed
                switch rng.next() % 6 {
                case 0: for _ in 0..<(1 + rng.next() % 8) { data[rng.next() % data.count] ^= UInt8(truncatingIfNeeded: 1 << (rng.next() % 8)) }
                case 1: data = data.prefix(rng.next() % data.count)
                case 2: let at = rng.next() % data.count; data.insert(contentsOf: (0..<(rng.next() % 64)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }, at: at)
                case 3: let at = rng.next() % data.count; let end = min(data.count, at + rng.next() % 32); for i in at..<end { data[i] = rng.next() % 2 == 0 ? 0xFF : 0 }
                case 4: let at = rng.next() % data.count; let end = min(data.count, at + rng.next() % 200); data.append(data[at..<end])
                default: let at = rng.next() % data.count; data.removeSubrange(at..<min(data.count, at + 1 + rng.next() % 50))
                }
                _ = iteration
                do { _ = try parseDocument(adapter, Data(data), budget: PreviewBudget(maxMilliseconds: 30_000)); outcomes += 1 }
                catch is PreviewFailure { outcomes += 1 }
                catch { Issue.record("\(name) iteration \(iteration): unexpected \(error)") }
            }
        }
        #expect(outcomes == 8_000)
    }

    @Test func innerDocumentMutationsEndInAResultOrATypedFailure() throws {
        var rng = LCG(state: 7)
        func mutate(_ text: String) -> Data {
            var data = Data(text.utf8)
            switch rng.next() % 5 {
            case 0: for _ in 0..<(1 + rng.next() % 6) { data[rng.next() % data.count] = [60, 62, 38, 59, 34, 39, 47, 61, 0, 255][rng.next() % 10] }
            case 1: data = data.prefix(rng.next() % data.count)
            case 2: let at = rng.next() % data.count; data.insert(contentsOf: Array("<p><ul><li><table><td>&#x;&amp<!--<![CDATA[</>".utf8).prefix(rng.next() % 40), at: at)
            case 3: let at = rng.next() % data.count; let end = min(data.count, at + rng.next() % 300); data.append(data[at..<end])
            default: let at = rng.next() % data.count; data.removeSubrange(at..<min(data.count, at + 1 + rng.next() % 40))
            }
            return data
        }
        let package = """
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:test</dc:identifier><dc:title>Book</dc:title><meta name="cover" content="cover"/></metadata>
        <manifest><item id="cover" href="cover.png" media-type="image/png"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="c1"/></spine></package>
        """
        let chapter = "<?xml version=\"1.0\"?><html><head><title>t</title><style>p{}</style></head><body><h1>One</h1><p>Plain <b>words</b> &amp; <i>more</i> <a href=\"x\">l</a><br/>x</p><ul><li>a</li><li>b<ul><li>c</li></ul></li></ul><table><tr><th>h</th><td>2</td></tr></table><pre>code\nline</pre><blockquote><p>q</p></blockquote><img alt=\"a\" src=\"b\"/></body></html>"
        var count = 0
        for _ in 0..<1_500 {
            let mutatedChapter = mutate(chapter)
            let mutatedPackage = rng.next() % 4 == 0 ? mutate(package) : Data(package.utf8)
            let zip = TestZIP.make([TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                TestZIPEntry(name: "META-INF/container.xml", data: Data(#"<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"#.utf8)),
                TestZIPEntry(name: "OEBPS/content.opf", data: mutatedPackage), TestZIPEntry(name: "OEBPS/cover.png", data: TestImages.png(8, 8)),
                TestZIPEntry(name: "OEBPS/c1.xhtml", data: mutatedChapter)])
            do { _ = try parseDocument(EPUBAdapter(), zip); count += 1 } catch is PreviewFailure { count += 1 }
            // The same chapter as a web page and as FictionBook body text exercises the other consumers of the tokenizer.
            let page = Data("Content-Type: text/html\r\n\r\n".utf8) + mutatedChapter
            do { _ = try parseDocument(WebArchiveAdapter(), page); count += 1 } catch is PreviewFailure { count += 1 }
            let book = Data("<FictionBook><description><title-info><book-title>T</book-title></title-info></description><body>".utf8) + mutatedChapter + Data("</body></FictionBook>".utf8)
            do { _ = try parseDocument(FictionBookAdapter(), book); count += 1 } catch is PreviewFailure { count += 1 }
            let info = TestZIP.make([TestZIPEntry(name: "ComicInfo.xml", data: mutatedChapter), TestZIPEntry(name: "1.png", data: TestImages.png(8, 8))])
            do { _ = try parseDocument(ComicBookAdapter(), info); count += 1 } catch is PreviewFailure { count += 1 }
        }
        #expect(count == 6_000)
    }
}
