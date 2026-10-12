import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Decision 027, Q-76 (review DM-17): an e-book that stops early records how many chapters contributed text and how
// many the book has, beside `partial: true`, so the status line can say "Showing 12 of 38 chapters" without the
// view ever counting. The renderer's `EbookChapterFacts` reads these two keys; the spelling here is independent.

private let q76Container = """
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
"""

private func q76Chapter(_ body: String) -> String {
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>t</title></head><body>\(body)</body></html>"
}

/// An EPUB whose spine lists `hrefs` in order; only the chapters in `present` are stored in the archive.
private func q76Book(hrefs: [String], present: [(String, String)], title: String = "Counted Book") -> Data {
    let manifest = hrefs.enumerated().map { #"<item id="c\#($0.offset + 1)" href="\#($0.element)" media-type="application/xhtml+xml"/>"# }.joined()
    let spine = hrefs.indices.map { #"<itemref idref="c\#($0 + 1)"/>"# }.joined()
    let package = """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(title)</dc:title><dc:identifier id="bookid">urn:uuid:1</dc:identifier></metadata>
    <manifest>\(manifest)</manifest><spine>\(spine)</spine></package>
    """
    var entries = [TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                   TestZIPEntry(name: "META-INF/container.xml", data: Data(q76Container.utf8)),
                   TestZIPEntry(name: "OEBPS/content.opf", data: Data(package.utf8))]
    for (href, content) in present { entries.append(TestZIPEntry(name: "OEBPS/" + href, data: Data(content.utf8))) }
    return TestZIP.make(entries)
}

private func q76FrontMatter(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    var lines = text.components(separatedBy: "\n").makeIterator()
    guard lines.next() == "---" else { return result }
    while let line = lines.next(), line != "---" {
        if let colon = line.firstIndex(of: ":") { result[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
    }
    return result
}

@Suite("EPUB chapter counts")
struct DocumentsQ76ChapterFactsTests {
    // MARK: The adapter

    @Test func aBookThatStoppedAtItsOutputCeilingRecordsTheChaptersThatContributedAndTheTotal() throws {
        let paragraph = "<p>" + String(repeating: "lorem ipsum dolor sit amet ", count: 40) + "</p>"
        let chapters = (0..<30).map { ("c\($0).xhtml", q76Chapter("<h1>Chapter \($0)</h1>" + String(repeating: paragraph, count: 60))) }
        let book = q76Book(hrefs: chapters.map(\.0), present: chapters)
        let document = try parseDocument(EPUBAdapter(), book, budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        let fields = q76FrontMatter(document.text)
        #expect(fields["partial"] == "true")
        #expect(fields["chaptersTotal"] == "30")
        let shown = try #require(fields["chaptersShown"].flatMap { Int($0) })
        #expect((1..<30).contains(shown))
        // The count is the chapters whose text begins in the document, give or take one that was cut off at the ceiling.
        let headings = document.text.components(separatedBy: "\n# Chapter ").count - 1
        #expect(abs(headings - shown) <= 1)
        #expect(!document.text.contains("# Chapter 29"))
    }

    @Test func anExhaustedReadBudgetStillCountsTheChaptersAlreadyRead() throws {
        let chapters = (0..<8).map { ("c\($0).xhtml", q76Chapter("<h1>Chapter \($0)</h1><p>" + TestImages.noiseText(900, seed: UInt32($0 + 1)) + "</p>")) }
        let book = q76Book(hrefs: chapters.map(\.0), present: chapters)
        let measuring = CountingSource(book)
        _ = try EPUBAdapter().parse(measuring, context: documentContext(PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)))
        let document = try parseDocument(EPUBAdapter(), book,
                                         budget: PreviewBudget(maxInputBytes: measuring.bytesRequested - 2_000, maxMilliseconds: 30_000))
        let fields = q76FrontMatter(document.text)
        #expect(fields["partial"] == "true")
        #expect(fields["chaptersTotal"] == "8")
        let shown = try #require(fields["chaptersShown"].flatMap { Int($0) })
        #expect((1..<8).contains(shown))
        #expect(document.text.contains("# Chapter 0") && !document.text.contains("# Chapter 7"))
    }

    @Test func aChapterThatCannotBeReadIsNotCountedAsShown() throws {
        let book = q76Book(hrefs: ["a.xhtml", "gone.xhtml", "c.xhtml"],
                           present: [("a.xhtml", q76Chapter("<p>AAA</p>")), ("c.xhtml", q76Chapter("<p>CCC</p>"))])
        let document = try parseDocument(EPUBAdapter(), book)
        #expect(document.text.contains("AAA") && document.text.contains("CCC"))
        let fields = q76FrontMatter(document.text)
        #expect(fields["partial"] == "true")
        #expect(fields["chaptersShown"] == "2")
        #expect(fields["chaptersTotal"] == "3")
    }

    @Test func aWholeBookCarriesNoCounts() throws {
        let book = q76Book(hrefs: ["a.xhtml", "b.xhtml"],
                           present: [("a.xhtml", q76Chapter("<p>AAA</p>")), ("b.xhtml", q76Chapter("<p>BBB</p>"))])
        let fields = q76FrontMatter(try parseDocument(EPUBAdapter(), book).text)
        #expect(fields["partial"] == nil)
        #expect(fields["chaptersShown"] == nil && fields["chaptersTotal"] == nil)
    }

    @Test func aBookWithoutChaptersCarriesNoCounts() throws {
        let fields = q76FrontMatter(try parseDocument(EPUBAdapter(), q76Book(hrefs: [], present: [])).text)
        #expect(fields["title"] == "Counted Book")
        #expect(fields["chaptersShown"] == nil && fields["chaptersTotal"] == nil)
    }

    @Test func aTitleThatImitatesTheCountLinesStaysOneLineOfTheTitle() throws {
        // Numeric references decode to line breaks, which the writer collapses: a title cannot become a count line.
        let book = q76Book(hrefs: ["a.xhtml"], present: [("a.xhtml", q76Chapter("<p>AAA</p>"))],
                           title: "X&#10;chaptersShown: 1&#10;chaptersTotal: 2")
        let document = try parseDocument(EPUBAdapter(), book)
        let fields = q76FrontMatter(document.text)
        #expect(fields["chaptersShown"] == nil && fields["chaptersTotal"] == nil)
        #expect(fields["title"]?.contains("chaptersShown: 1 chaptersTotal: 2") == true)
        #expect(document.text.components(separatedBy: "\n").filter { $0.hasPrefix("chapters") }.isEmpty)
    }
}
