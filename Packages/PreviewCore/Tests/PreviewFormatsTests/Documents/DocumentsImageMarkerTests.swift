import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Decision 027, Q-07 (review DM-01 and DM-18): converted documents keep an image as the inert Markdown form
// `![description]()` so the renderer can draw one localized marker, and mark their text as converted.

private func convert(_ html: String) throws -> String {
    let context = documentContext()
    var writer = MarkdownWriter(context: context)
    var nodes = context.budget.maxJSONNodes * 4
    try HTMLMarkdownConverter.convert(html, into: &writer, nodeBudget: &nodes, context: context)
    return writer.text
}

private func epubData(chapter: String) -> Data {
    let container = """
    <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>\
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
    """
    let package = """
    <?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">\
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Book</dc:title><dc:identifier id="bookid">urn:uuid:1</dc:identifier></metadata>\
    <manifest><item id="c1" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>
    """
    let page = "<?xml version=\"1.0\" encoding=\"utf-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>t</title></head><body>\(chapter)</body></html>"
    return TestZIP.make([
        TestZIPEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
        TestZIPEntry(name: "META-INF/container.xml", data: Data(container.utf8)),
        TestZIPEntry(name: "OEBPS/content.opf", data: Data(package.utf8)),
        TestZIPEntry(name: "OEBPS/a.xhtml", data: Data(page.utf8))
    ])
}

private func fictionBookData(body: String) -> Data {
    Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
    <description><title-info><book-title>Story</book-title></title-info></description>
    <body>\(body)</body></FictionBook>
    """.utf8)
}

private func webArchiveData(html: String) -> Data {
    Data(("Subject: Page\r\nContent-Type: multipart/related; boundary=\"b0undary\"\r\n\r\n--b0undary\r\n"
          + "Content-Type: text/html; charset=utf-8\r\nContent-Location: https://example.com/\r\n\r\n\(html)\r\n--b0undary--\r\n").utf8)
}

@Suite("Converted documents: image form and origin")
struct DocumentsImageMarkerTests {
    // MARK: The inert image

    @Test func descriptionsAreEscapedAsProseWithTheClosingBracketToo() {
        #expect(MarkdownEscaping.image(description: "A *cat*") == #"![A \*cat\*]()"#)
        #expect(MarkdownEscaping.image(description: "a [b] c") == #"![a \[b\] c]()"#)
        #expect(MarkdownEscaping.image(description: #"C:\dir"#) == #"![C:\\dir]()"#)
        #expect(MarkdownEscaping.image(description: "`code` and `more`") == #"![\`code\` and \`more\`]()"#)
        #expect(MarkdownEscaping.image(description: "  two\n lines\t") == "![two lines]()")
        #expect(MarkdownEscaping.image(description: "") == nil)
        #expect(MarkdownEscaping.image(description: " \n\t ") == nil)
    }

    @Test func anIntrawordUnderscoreStaysAsWrittenSoTheSharedFilterStillRecognizesKeyNames() {
        // Decision 020: escaping every underscore once hid `api_key = value` from the privacy filter.
        #expect(MarkdownEscaping.image(description: "api_key = x") == "![api_key = x]()")
        #expect(MarkdownEscaping.image(description: "_leading") == #"![\_leading]()"#)
    }

    @Test func longDescriptionsAreBoundedSoTheWholeImageStaysInsideTheRenderersScan() throws {
        let image = try #require(MarkdownEscaping.image(description: String(repeating: "a", count: 1_000)))
        #expect(image.hasPrefix("![") && image.hasSuffix("…]()"))
        #expect(image.count == 2 + MarkdownEscaping.maximumImageDescriptionCharacters + 1 + 3)
        // Even when every character needs an escape the image is far below the renderer's 2,000-character span scan.
        let escaped = try #require(MarkdownEscaping.image(description: String(repeating: "*", count: 1_000)))
        #expect(escaped.count < 1_000)
    }

    @Test func htmlImagesBecomeInertMarkdownImagesAtTheirPlaceInTheText() throws {
        #expect(try convert(#"<p><img src="https://example.com/pixel.png?token=abc" alt="a]b"/></p>"#) == #"![a\]b]()"# + "\n")
        #expect(try convert(#"<p>See <a href="x"><img src="y" alt="logo"></a> now</p>"#) == "See ![logo]() now\n")
        #expect(try convert(#"<img src="x.png" alt=""><img src="y.png">"#).isEmpty)
        let table = try convert(#"<table><tr><th>A</th></tr><tr><td><img src="x" alt="pic"></td></tr></table>"#)
        #expect(table == "| A |\n| --- |\n| ![pic]() |\n")
    }

    @Test func noImageSourceEverReachesTheText() throws {
        let text = try convert(#"<p><img src="https://evil.example/pixel.gif?token=1" alt="logo"/><img src="data:image/png;base64,AAAA" alt="inline"/></p>"#)
        #expect(text == "![logo]()![inline]()\n")
        for forbidden in ["evil.example", "pixel.gif", "token", "base64", "AAAA", "[image:"] { #expect(!text.contains(forbidden), "\(forbidden)") }
    }

    // MARK: Each adapter

    @Test func ebooksKeepImagesInTheInertFormAndMarkTheirTextConverted() throws {
        let chapter = #"<h1>One</h1><p>Look <img src="https://evil.example/pixel.gif" alt="logo"/> here.</p>"#
        let document = try parseDocument(EPUBAdapter(), epubData(chapter: chapter))
        #expect(document.origin == .converted)
        #expect(document.syntax == .markdown)
        #expect(document.text.contains("Look ![logo]() here."))
        #expect(!document.text.contains("[image:") && !document.text.contains("evil.example"))
    }

    @Test func fictionBooksKeepInlineAndBlockImagesInTheInertFormAndMarkTheirTextConverted() throws {
        let body = ##"<section><p>Pic <image l:href="#a" alt="A *logo* [x]"/> end</p><image l:href="#b" title="Block title"/></section>"##
        let document = try parseDocument(FictionBookAdapter(), fictionBookData(body: body))
        #expect(document.origin == .converted)
        #expect(document.text.contains(#"Pic ![A \*logo\* \[x\]]() end"#))
        #expect(document.text.contains("\n![Block title]()\n"))
        #expect(!document.text.contains("[image:"))
    }

    @Test func savedWebPagesKeepImagesInTheInertFormAndMarkTheirTextConverted() throws {
        let html = #"<html><head><title>Saved</title></head><body><h1>Heading</h1><p>Body.</p><img src="logo.png" alt="Logo"></body></html>"#
        let document = try parseDocument(WebArchiveAdapter(), webArchiveData(html: html))
        #expect(document.origin == .converted)
        #expect(document.text.hasSuffix("# Heading\n\nBody.\n\n![Logo]()\n"))
        #expect(!document.text.contains("[image:") && !document.text.contains("logo.png"))
    }

    @Test func theMachineFlagsStayInTheFrontMatterForTheStatusLine() throws {
        // The renderer hides `partial: true` and `drm: true`; the adapters still write them (decision 020).
        let writer = MarkdownWriter(context: documentContext())
        let text = MarkdownWriter.document(fields: [("title", "Book")], flags: ["partial"], body: writer, context: documentContext())
        #expect(text == "---\ntitle: Book\npartial: true\n---\n\n")
    }
}
