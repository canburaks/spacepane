import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func fb2(title: String = "Synthetic Story", body: String, cover: Data? = TestImages.png(30, 45), coverHref: String = "cover.png",
                 binaryID: String = "cover.png", extraDescription: String = "", encoding: String = "utf-8") -> String {
    let coverpage = cover == nil ? "" : "<coverpage><image l:href=\"#\(coverHref)\"/></coverpage>"
    let binary = cover.map { "<binary id=\"\(binaryID)\" content-type=\"image/png\">\($0.base64EncodedString(options: .lineLength76Characters))</binary>" } ?? ""
    return """
    <?xml version="1.0" encoding="\(encoding)"?>
    <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
    <description><title-info><genre>prose</genre>
    <author><first-name>Ann</first-name><middle-name>B.</middle-name><last-name>Author</last-name></author>
    <author><nickname>Pen Name</nickname></author>
    <book-title>\(title)</book-title><annotation><p>An <emphasis>annotated</emphasis> story.</p></annotation>
    <date value="2026-01-02">January 2026</date><lang>en</lang>\(coverpage)\(extraDescription)</title-info>
    <publish-info><publisher>Synthetic Press</publisher><isbn>000-0-00-000000-0</isbn></publish-info></description>
    <body>\(body)</body>\(binary)</FictionBook>
    """
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

private func parse(_ text: String, encoding: String.Encoding = .utf8, budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> ParsedTextDocument {
    try parseDocument(FictionBookAdapter(), try #require(text.data(using: encoding)), budget: budget)
}

@Suite("FictionBook adapter")
struct FictionBookAdapterTests {
    @Test func metadataBecomesFrontMatterAndSectionsBecomeMarkdown() throws {
        let body = """
        <title><p>The Book</p></title>
        <epigraph><p>An epigraph.</p><text-author>Someone</text-author></epigraph>
        <section><title><p>Chapter 1</p></title><p>First <emphasis>emphasized</emphasis> and <strong>strong</strong> text.</p><empty-line/>
        <p>Second paragraph with <code>code</code> &amp; entities.</p>
        <section><title><p>Part A</p></title><p>Nested.</p></section></section>
        <section><title><p>Chapter 2</p></title>
        <poem><stanza><v>Line one</v><v>Line two</v></stanza></poem><subtitle>Interlude</subtitle></section>
        """
        let document = try parse(fb2(body: body))
        let fields = frontMatter(document.text)
        #expect(document.syntax == .markdown)
        #expect(fields["title"] == "Synthetic Story")
        #expect(fields["author"] == "Ann B. Author; Pen Name")
        #expect(fields["language"] == "en")
        #expect(fields["publisher"] == "Synthetic Press")
        #expect(fields["date"] == "2026-01-02")
        #expect(fields["identifier"] == "000-0-00-000000-0")
        #expect(fields["description"] == "An annotated story.")
        let bodyText = document.text.components(separatedBy: "---\n\n").last ?? ""
        #expect(bodyText == """
        # The Book

        > An epigraph.
        > — Someone

        ## Chapter 1

        First *emphasized* and **strong** text.

        Second paragraph with `code` & entities.

        ### Part A

        Nested.

        ## Chapter 2

        Line one
        Line two

        **Interlude**

        """)
    }

    @Test func sectionsWithoutABodyTitleStartAtLevelOne() throws {
        let text = try parse(fb2(body: "<section><title><p>Only</p></title><p>x</p></section>", cover: nil)).text
        #expect(text.contains("\n# Only\n\nx\n"))
    }

    @Test func tablesAndInlineImagesAreTextOnly() throws {
        let body = "<section><table><tr><th>A</th><td>1 | 2</td></tr><tr><td>B</td><td>3</td></tr></table>"
            + "<p>Pic <image l:href=\"#cover.png\" alt=\"A *logo*\"/></p></section>"
        let text = try parse(fb2(body: body)).text
        #expect(text.contains("| A | 1 ¦ 2 |\n| --- | --- |\n| B | 3 |\n"))
        #expect(text.contains(#"Pic ![A \*logo\*]()"#))
    }

    @Test func windows1251DocumentsDecodeThroughTheirDeclaredEncoding() throws {
        let text = fb2(title: "Привет, мир", body: "<section><p>Это проверка кодировки.</p></section>", cover: nil, encoding: "windows-1251")
        let document = try parse(text, encoding: .windowsCP1251)
        #expect(document.text.contains("Это проверка кодировки."))
        #expect(frontMatter(document.text)["title"] == "\"Привет, мир\"" || frontMatter(document.text)["title"] == "Привет, мир")
    }

    // MARK: Cover

    @Test func theCoverBinaryBecomesTheCoverImage() throws {
        let png = TestImages.png(30, 45)
        let document = try parse(fb2(body: "<section><p>x</p></section>", cover: png))
        let cover = try #require(document.images.first)
        #expect(document.images.count == 1)
        #expect(cover.role == .cover)
        #expect(cover.pixelWidth == 30 && cover.pixelHeight == 45)
        #expect(cover.data == png)
        // The base64 payload never enters the text.
        #expect(!document.text.contains(png.base64EncodedString().prefix(40)))
    }

    @Test func missingMismatchedAndInvalidCoversYieldNoImage() throws {
        #expect(try parse(fb2(body: "<section><p>x</p></section>", cover: nil)).images.isEmpty)
        #expect(try parse(fb2(body: "<section><p>x</p></section>", coverHref: "other.png")).images.isEmpty)
        #expect(try parse(fb2(body: "<section><p>x</p></section>", cover: Data("not an image".utf8))).images.isEmpty)
    }

    @Test func aLargeFileIsReadAsHeadAndTailSoTheCoverStillAppears() throws {
        let paragraphs = (0..<400).map { "<p>\(TestImages.noiseText(30, seed: UInt32($0 + 1)))</p>" }.joined()
        let text = fb2(body: "<section><title><p>Long</p></title>\(paragraphs)</section>", cover: TestImages.png(30, 45))
        let size = text.utf8.count
        #expect(size > 60_000)
        let budget = PreviewBudget(maxInputBytes: 24_000, maxMilliseconds: 30_000)
        let document = try parse(text, budget: budget)
        #expect(document.images.count == 1)
        #expect(frontMatter(document.text)["partial"] == "true")
        #expect(document.text.contains("# Long") || document.text.contains("## Long") || document.text.contains("Long"))
    }

    // MARK: Failure modes

    @Test func otherXMLAndGarbageFailAsMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) { try parse("<?xml version=\"1.0\"?><root><body>x</body></root>") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("plain text") }
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(FictionBookAdapter(), Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("<FictionBook></FictionBook>") }
    }

    @Test func entityDeclarationsAndExternalReferencesAreInert() throws {
        let hostile = "<?xml version=\"1.0\"?><!DOCTYPE FictionBook [<!ENTITY a \"expanded\"><!ENTITY x SYSTEM \"file:///etc/passwd\">]>"
        let text = hostile + "<FictionBook><description><title-info><book-title>&x; &a;</book-title></title-info></description><body><section><p>&x;</p></section></body></FictionBook>"
        let document = try parse(text)
        #expect(!document.text.contains("expanded"))
        #expect(!document.text.contains("root:"))
    }

    @Test func outputIsBoundedAndMarkedPartial() throws {
        let paragraphs = (0..<2_000).map { "<p>\(TestImages.noiseText(60, seed: UInt32($0 + 1)))</p>" }.joined()
        let text = fb2(body: "<section>\(paragraphs)</section>", cover: nil)
        let document = try parse(text, budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        #expect(document.text.utf16.count <= 262_144)
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    @Test func cancellationAndDeadlinePrecedeAnySourceRead() async throws {
        let data = try #require(fb2(body: "<section><p>x</p></section>").data(using: .utf8))
        let source = CountingSource(data)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try FictionBookAdapter().parse(source, context: documentContext()); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(source.reads == 0)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try FictionBookAdapter().parse(CountingSource(data), context: documentContext(PreviewBudget(maxMilliseconds: 0)))
        }
    }

    @Test func theBinaryFinderOnlyReturnsCompleteElementsWithTheRequestedID() throws {
        let context = documentContext()
        let data = Data(#"<binary id="a" content-type="image/png">QUJD</binary><binary id="b">REVG</binary><binary id="c">TRUNC"#.utf8)
        #expect(try FictionBookBinaries.payload(id: "a", in: data, maximumEncodedBytes: 100, context: context) == Data("QUJD".utf8))
        #expect(try FictionBookBinaries.payload(id: "b", in: data, maximumEncodedBytes: 100, context: context) == Data("REVG".utf8))
        #expect(try FictionBookBinaries.payload(id: "c", in: data, maximumEncodedBytes: 100, context: context) == nil)
        #expect(try FictionBookBinaries.payload(id: "z", in: data, maximumEncodedBytes: 100, context: context) == nil)
        #expect(try FictionBookBinaries.payload(id: "a", in: data, maximumEncodedBytes: 2, context: context) == nil)
    }
}
