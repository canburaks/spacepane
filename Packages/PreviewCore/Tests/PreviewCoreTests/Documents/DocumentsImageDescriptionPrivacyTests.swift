import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

// Decision 027, Q-07: converted documents now keep an image as `![description]()`. The description is document
// text like any other, so the shared privacy stage must still conceal a secret-looking one and must see the same
// spelling of key names as before (decision 020's underscore lesson).

private let secret = "synthetic-secret-value"

private func fictionBookData() -> Data {
    Data("""
    <?xml version="1.0" encoding="utf-8"?><FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>
    <book-title>Story</book-title></title-info></description>
    <body><section><title><p>Part</p></title><p>A map <image l:href="#m" alt="A map of the island"/> follows.</p>
    <p>Locked <image l:href="#k" alt="api_key = \(secret)"/> picture.</p>
    <image l:href="#p" alt="password: \(secret)"/></section></body></FictionBook>
    """.utf8)
}

private func webArchiveData() -> Data {
    Data(("Subject: Page\r\nContent-Type: multipart/related; boundary=\"x\"\r\n\r\n--x\r\nContent-Type: text/html\r\n"
          + "Content-Location: https://example.com/\r\n\r\n<html><body><h1>Page</h1>"
          + "<p>A map <img src=\"m.png\" alt=\"A map of the island\"> follows.</p>"
          + "<p><img src=\"k.png\" alt=\"token: \(secret)\"></p></body></html>\r\n--x--\r\n").utf8)
}

private func write(_ data: Data, named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

@Suite("Converted documents: image descriptions through the pipeline")
struct DocumentsImageDescriptionPrivacyTests {
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    @Test func aDescriptionThatLooksLikeASecretAssignmentIsConcealedAndAnOrdinaryOneIsNot() async throws {
        let fixtures: [(name: String, data: Data)] = [("book.fb2", fictionBookData()), ("page.mhtml", webArchiveData())]
        for fixture in fixtures {
            let url = try write(fixture.data, named: fixture.name)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            guard case .ready(let presentation) = await pipeline.preview(url: url) else {
                Issue.record("\(fixture.name) did not preview")
                continue
            }
            #expect(!presentation.text.contains(secret), "\(fixture.name)")
            #expect(presentation.redactionCount > 0, "\(fixture.name)")
            #expect(presentation.text.contains("••••"), "\(fixture.name)")
            // An ordinary description reaches the text as the inert image form, never as the English marker.
            #expect(presentation.text.contains("![A map of the island]()"), "\(fixture.name)")
            #expect(!presentation.text.contains("[image:"), "\(fixture.name)")
            // The adapters say the text is a conversion, and the pipeline carries it into the presentation.
            #expect(presentation.origin == .converted, "\(fixture.name)")
            #expect(presentation.syntax == .markdown, "\(fixture.name)")
        }
    }

    @Test func concealmentLeavesNoSourceBehindInAnyDerivedLine() async throws {
        let url = try write(fictionBookData(), named: "book.fb2")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("no preview"); return }
        for line in presentation.text.components(separatedBy: "\n") where line.contains("api_key") || line.contains("password") {
            #expect(line.contains("••••"), "\(line)")
            #expect(!line.contains(secret))
        }
    }
}
