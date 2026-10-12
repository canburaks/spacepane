import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Decision 027, Q-76 (review DM-17): the front-matter writer can state numbers the adapter measured, beside the flags.

@Suite("Front matter count lines")
struct DocumentsQ76CountLineWriterTests {
    @Test func countsFollowTheFlagsAsPlainNumberLines() {
        let writer = MarkdownWriter(context: documentContext())
        let text = MarkdownWriter.document(fields: [("title", "Book")], flags: ["partial"],
                                           counts: [(key: "chaptersShown", value: 12), (key: "chaptersTotal", value: 38)],
                                           body: writer, context: documentContext())
        #expect(text == "---\ntitle: Book\npartial: true\nchaptersShown: 12\nchaptersTotal: 38\n---\n\n")
    }

    @Test func noCountsLeaveTheFrontMatterAsItWas() {
        let writer = MarkdownWriter(context: documentContext())
        let text = MarkdownWriter.document(fields: [("title", "Book")], flags: ["partial"], body: writer, context: documentContext())
        #expect(text == "---\ntitle: Book\npartial: true\n---\n\n")
    }

    @Test func aNegativeCountIsNeverWritten() {
        var writer = MarkdownWriter(context: documentContext())
        writer.frontMatter([("title", "Book")], flags: [], counts: [(key: "chaptersShown", value: -1), (key: "chaptersTotal", value: 0)])
        #expect(writer.text == "---\ntitle: Book\nchaptersTotal: 0\n---\n\n")
    }
}
