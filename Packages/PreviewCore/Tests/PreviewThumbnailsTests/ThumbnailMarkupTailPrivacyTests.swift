import Foundation
import Testing
import PreviewContracts
@testable import PreviewThumbnails

private func tailMarkupPage(_ source: String) -> ThumbnailTextPage? {
    ThumbnailMarkdown.page(from: source, syntax: .markdown, metrics: ThumbnailMetrics(geometry: geometry(384)))
}

private func markupLongPrefix() -> String {
    let columns = ThumbnailMetrics(geometry: geometry(384)).columns
    return String(repeating: "v ", count: columns * 8)
}

@Suite("Markup tails preserve comment state")
struct ThumbnailMarkupTailPrivacyTests {
    @Test func anOpeningPastTheDisplayPrefixCannotExposeTheNextCommentLine() throws {
        let source = markupLongPrefix() + "<!--\nCOMMENT-BODY-NOT-DRAWN\n-->\nVisible after\n"
        let page = try #require(tailMarkupPage(source))
        let drawn = page.lines.map(\.text).joined(separator: "\n")
        #expect(!drawn.contains("COMMENT-BODY-NOT-DRAWN"))
        #expect(drawn.contains("Visible after"))
    }

    @Test func aClosingPastTheDisplayPrefixDoesNotHideTheVisibleBodyAfterIt() throws {
        let source = "<!--" + markupLongPrefix() + "-->\nVisible after\n"
        let page = try #require(tailMarkupPage(source))
        #expect(page.lines.map(\.text) == ["Visible after"])
    }

    @Test func codeAndEscapedOpeningsKeepTheirLiteralMeaning() throws {
        let escaped = markupLongPrefix() + "\\<!--\nVisible after\n"
        let escapedPage = try #require(tailMarkupPage(escaped))
        #expect(escapedPage.lines.map(\.text).joined().contains("Visible after"))
        let code = "```\n" + markupLongPrefix() + "<!--\nCOMMENT-LIKE-CODE-IS-VISIBLE\n```\nVisible after\n"
        let drawn = try #require(tailMarkupPage(code)).lines.map(\.text).joined(separator: "\n")
        #expect(drawn.contains("COMMENT-LIKE-CODE-IS-VISIBLE") && drawn.contains("Visible after"))
    }

    @Test func anInspectionBoundNeverFallsBackToAnUnsafeClippedPage() {
        let source = String(repeating: "v ", count: 40_000) + "<!--\nCOMMENT-BODY-NOT-DRAWN\n-->\nVisible after\n"
        #expect(tailMarkupPage(source) == nil, "Uncertain state beyond a bounded inspection keeps the generic glyph")
    }

    @Test func theRealMarkdownThumbnailNeverDrawsAnUnseenCommentTailAndKeepsItsSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = markupLongPrefix() + "<!--\nCOMMENT-BODY-NOT-DRAWN\n-->\nVisible after\n"
        let url = try fixture.file("ordinary.md", source)
        let scene = try #require(await makeService().outcome(for: url, geometry: geometry(384)).scene)
        let drawn = scene.content.drawnStrings.joined(separator: "\n")
        #expect(!drawn.contains("COMMENT-BODY-NOT-DRAWN") && drawn.contains("Visible after"))
        #expect(try Data(contentsOf: url) == Data(source.utf8))
    }
}
