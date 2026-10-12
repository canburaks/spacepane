import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func frontMatter(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    var lines = text.components(separatedBy: "\n").makeIterator()
    guard lines.next() == "---" else { return result }
    while let line = lines.next(), line != "---" {
        if let colon = line.firstIndex(of: ":") { result[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
    }
    return result
}

private func mhtml(_ headers: String = "", parts: [String]) -> Data {
    let head = "From: <Saved by test>\r\nSubject: Fallback subject\r\nMIME-Version: 1.0\r\n"
        + "Content-Type: multipart/related; type=\"text/html\"; boundary=\"b0undary\"\r\n\(headers)\r\n"
    let body = parts.map { "--b0undary\r\n" + $0 + "\r\n" }.joined() + "--b0undary--\r\n"
    return Data((head + body).utf8)
}

private func htmlPart(_ html: String, extra: String = "Content-Type: text/html; charset=\"utf-8\"\r\nContent-Transfer-Encoding: 7bit\r\n") -> String {
    extra + "Content-Location: https://example.com/index.html\r\n\r\n" + html
}

@Suite("Web archive adapter")
struct WebArchiveAdapterTests {
    @Test func theMainHTMLPartBecomesMarkdownAndOtherPartsAreListedByTypeAndHost() throws {
        let data = mhtml(parts: [
            htmlPart("<html><head><title>Saved Page</title><style>p{}</style></head><body><h1>Heading</h1><p>Body <b>text</b> &amp; more.</p>"
                     + "<script>alert(1)</script><img src=\"logo.png\" alt=\"Logo\"></body></html>"),
            "Content-Type: image/png\r\nContent-Transfer-Encoding: base64\r\nContent-Location: https://cdn.example.net/a/logo.png?token=secret123\r\n\r\n"
                + TestImages.png().base64EncodedString(),
            "Content-Type: image/png\r\nContent-Location: https://cdn.example.net/b/other.png\r\n\r\nxx",
            "Content-Type: text/css\r\nContent-Location: https://example.com/site.css\r\n\r\nbody{}",
            "Content-Type: application/javascript\r\n\r\nvar secret=1;"
        ])
        let document = try parseDocument(WebArchiveAdapter(), data)
        let fields = frontMatter(document.text)
        #expect(document.syntax == .markdown)
        #expect(document.images.isEmpty)
        #expect(fields["title"] == "Saved Page")
        #expect(fields["source"] == "example.com")
        // Hosts and content types only: never a path, a query or the body of another part.
        #expect(fields["resources"] == "image/png cdn.example.net ×2; text/css example.com; application/javascript")
        #expect(document.text.hasSuffix("# Heading\n\nBody **text** & more.\n\n![Logo]()\n"))
        for forbidden in ["alert", "secret123", "/a/logo.png", "var secret", "p{}"] { #expect(!document.text.contains(forbidden), "\(forbidden)") }
    }

    @Test func quotedPrintableBodiesDecodeEscapesAndSoftLineBreaks() throws {
        let html = "<html><body><p>caf=C3=A9 =E2=80=94 a=3Db and a very long line that is wrapped by the encoder with a soft br=\r\neak here</p></body></html>"
        let document = try parseDocument(WebArchiveAdapter(), mhtml(parts: [htmlPart(html, extra: "Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n")]))
        #expect(document.text.contains("café — a=b and a very long line that is wrapped by the encoder with a soft break here"))
    }

    @Test func base64BodiesDecodeInTheirDeclaredCharset() throws {
        let latin = try #require("<html><body><p>Ünïcödé façade</p></body></html>".data(using: .isoLatin1))
        let part = "Content-Type: text/html; charset=iso-8859-1\r\nContent-Transfer-Encoding: base64\r\n\r\n" + latin.base64EncodedString(options: .lineLength64Characters)
        let document = try parseDocument(WebArchiveAdapter(), mhtml(parts: [part]))
        #expect(document.text.contains("Ünïcödé façade"))
    }

    @Test func windows1251QuotedPrintableDecodes() throws {
        let cyrillic = try #require("Привет".data(using: .windowsCP1251))
        let encoded = cyrillic.map { String(format: "=%02X", $0) }.joined()
        let part = "Content-Type: text/html; charset=windows-1251\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<p>\(encoded)</p>"
        #expect(try parseDocument(WebArchiveAdapter(), mhtml(parts: [part])).text.contains("Привет"))
    }

    @Test func aSinglePartHTMLMessageIsAccepted() throws {
        let message = "Subject: Single\r\nContent-Type: text/html; charset=utf-8\r\nContent-Location: https://example.org/a\r\n\r\n<html><body><p>Only part</p></body></html>"
        let document = try parseDocument(WebArchiveAdapter(), Data(message.utf8))
        #expect(document.text.contains("Only part"))
        #expect(frontMatter(document.text)["title"] == "Single")
        #expect(frontMatter(document.text)["source"] == "example.org")
    }

    @Test func nestedMultipartAndTheStartParameterSelectTheMainPart() throws {
        let inner = "Content-Type: multipart/alternative; boundary=\"inner\"\r\n\r\n--inner\r\nContent-Type: text/plain\r\n\r\nplain version\r\n"
            + "--inner\r\nContent-Type: text/html\r\nContent-ID: <wanted>\r\n\r\n<p>Wanted html</p>\r\n--inner--"
        let data = Data(("Content-Type: multipart/related; start=\"<wanted>\"; boundary=\"outer\"\r\n\r\n"
            + "--outer\r\nContent-Type: text/html\r\nContent-ID: <decoy>\r\n\r\n<p>Decoy</p>\r\n--outer\r\n" + inner + "\r\n--outer--\r\n").utf8)
        let text = try parseDocument(WebArchiveAdapter(), data).text
        #expect(text.contains("Wanted html"))
        #expect(!text.contains("Decoy"))
    }

    @Test func foldedHeadersAndEncodedWordsDecode() throws {
        let subject = "=?utf-8?B?" + Data("Gr\u{FC}\u{DF}e".utf8).base64EncodedString() + "?=\r\n =?utf-8?Q?_aus_Z=C3=BCrich?="
        let message = "Subject: \(subject)\r\nContent-Type: text/html\r\n\r\n<p>No title element</p>"
        let document = try parseDocument(WebArchiveAdapter(), Data(message.utf8))
        #expect(frontMatter(document.text)["title"] == "Grüße aus Zürich")
    }

    @Test func aBoundaryPrefixInsideContentIsNotADelimiter() throws {
        let data = mhtml(parts: [htmlPart("<p>one</p>\r\n--b0undaryX is not a delimiter\r\n<p>two</p>")])
        let text = try parseDocument(WebArchiveAdapter(), data).text
        #expect(text.contains("one") && text.contains("two"))
    }

    @Test func noHTMLPartOrNoMessageFails() {
        let textOnly = mhtml(parts: ["Content-Type: text/plain\r\n\r\njust text"])
        #expect(throws: PreviewFailure.unsupportedFormat) { try parseDocument(WebArchiveAdapter(), textOnly) }
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(WebArchiveAdapter(), Data("no headers here".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(WebArchiveAdapter(), Data()) }
        let empty = mhtml(parts: ["Content-Type: text/html\r\nContent-Transfer-Encoding: base64\r\n\r\n"])
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(WebArchiveAdapter(), empty) }
    }

    @Test func partCountAndDepthAreBounded() throws {
        let many = (0..<600).map { "Content-Type: image/png\r\nContent-Location: https://h\($0).example/x\r\n\r\nx" }
        let data = mhtml(parts: [htmlPart("<p>Main</p>")] + many)
        let document = try parseDocument(WebArchiveAdapter(), data)
        #expect(document.text.contains("Main"))
        // At most 40 distinct resource entries are listed.
        let resources = frontMatter(document.text)["resources"] ?? ""
        #expect(resources.components(separatedBy: "; ").count <= 40)
    }

    @Test func aFileLargerThanTheInputBudgetIsReadAsItsBeginningAndMarkedPartial() throws {
        let filler = String(repeating: "<p>word word word word</p>", count: 4_000)
        let data = mhtml(parts: [htmlPart("<html><body><h1>Big</h1>" + filler + "</body></html>")])
        let document = try parseDocument(WebArchiveAdapter(), data, budget: PreviewBudget(maxInputBytes: 20_000, maxMilliseconds: 30_000))
        #expect(document.text.contains("# Big"))
        #expect(frontMatter(document.text)["partial"] == "true")
    }

    @Test func entityDeclarationsAndResourceLoadingElementsAreInert() throws {
        let html = "<!DOCTYPE html [<!ENTITY e SYSTEM \"file:///etc/passwd\">]><html><body><p>&e;</p><link rel=stylesheet href=\"http://evil.example/a.css\">"
            + "<iframe src=\"http://evil.example\"></iframe><object data=\"http://evil.example/x\"></object></body></html>"
        let text = try parseDocument(WebArchiveAdapter(), mhtml(parts: [htmlPart(html)])).text
        #expect(text.contains("&e;"))
        #expect(!text.contains("evil.example"))
        #expect(!text.contains("root:"))
    }

    @Test func quotedPrintableAndHeaderHelpersHandleMalformedInput() throws {
        let context = documentContext()
        let broken = Array("a=\r\nb=ZZ=4=".utf8)
        let decoded = try MIMEMessage.quotedPrintable(broken[...], context: context)
        #expect(String(decoding: decoded, as: UTF8.self) == "ab=ZZ=4")
        #expect(MIMEMessage.decodeHeaderText("=?bogus?X?abc?= plain") == "=?bogus?X?abc?= plain")
        #expect(MIMEContentType("text/html; charset=\"UTF-8\"; x=y").parameters["charset"] == "UTF-8")
        #expect(MIMEContentType(nil).essence == "text/plain")
    }

    @Test func cancellationAndDeadlinePrecedeAnySourceRead() async {
        let data = mhtml(parts: [htmlPart("<p>x</p>")])
        let source = CountingSource(data)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try WebArchiveAdapter().parse(source, context: documentContext()); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(source.reads == 0)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try WebArchiveAdapter().parse(CountingSource(data), context: documentContext(PreviewBudget(maxMilliseconds: 0)))
        }
    }
}
