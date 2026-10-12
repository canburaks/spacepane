import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-76 (review DM-17): a truncated e-book says how many of its chapters are shown, with the counts the
// EPUB adapter measured and wrote into its front matter. The view reads them; it never counts chapters itself.

private let enUS = Locale(identifier: "en_US")

/// Markdown as the EPUB adapter writes it: descriptive fields, the machine flags, then the chapter counts.
private func countedBook(shown: String?, total: String?, flags: [String] = ["partial"], body: String = "# Chapter 1\n\nText.\n") -> String {
    var text = "---\ntitle: Moby Dick\nauthor: Herman Melville\n"
    text += flags.map { "\($0): true\n" }.joined()
    if let shown { text += "chaptersShown: \(shown)\n" }
    if let total { text += "chaptersTotal: \(total)\n" }
    return text + "---\n\n" + body
}

private func notice(_ text: String, id: FormatID = .epub, locale: Locale = enUS) -> [String] {
    DocumentPresentationNotices.lines(for: presentation(id, text: text, syntax: .markdown), locale: locale)
}

@Suite("E-book chapter notice")
@MainActor
struct DocumentsQ76ChapterNoticeTests {
    // MARK: The counted sentence

    @Test func aPartialBookStatesTheChaptersShownAndTheTotalWithLocaleNumbers() {
        #expect(notice(countedBook(shown: "12", total: "1200")) == ["Showing 12 of 1,200 chapters."])
        #expect(notice(countedBook(shown: "12", total: "38")) == ["Showing 12 of 38 chapters."])
        // A book whose first chapter alone filled the preview shows none of its chapters in full; say so.
        #expect(notice(countedBook(shown: "0", total: "38")) == ["Showing 0 of 38 chapters."])
        // One chapter is the singular form of the plural key; the sentence still names the total.
        #expect(notice(countedBook(shown: "1", total: "38")) == ["Showing 1 of 38 chapters."])
    }

    @Test func theNumbersFollowThePresentationLocale() throws {
        let german = try #require(notice(countedBook(shown: "12", total: "1200"), locale: Locale(identifier: "de_DE")).first)
        #expect(german.contains("1.200") && german.contains("12"))
        let arabic = try #require(notice(countedBook(shown: "12", total: "38"), locale: Locale(identifier: "ar_SA")).first)
        #expect(arabic.contains("\u{0661}\u{0662}") && arabic.contains("\u{0663}\u{0668}"))
    }

    @Test func everyConvertedDocumentFormatSaysItTheSameWay() {
        for id in [FormatID.epub, .fictionBook, .webArchive] {
            #expect(notice(countedBook(shown: "3", total: "9"), id: id) == ["Showing 3 of 9 chapters."], "\(id.rawValue)")
        }
    }

    // MARK: What the sentence needs

    @Test func protectionOutranksTheCounts() {
        let drm = countedBook(shown: "3", total: "9", flags: ["drm", "partial"])
        #expect(notice(drm) == [PreviewStrings.text(.ebooksNoticeDRM)])
    }

    @Test func withoutCountsAPartialBookKeepsTheGeneralSentence() {
        let general = [PreviewStrings.text(.ebooksNoticePartialText)]
        #expect(notice(countedBook(shown: nil, total: nil)) == general)
        #expect(notice(countedBook(shown: "3", total: nil)) == general)
        #expect(notice(countedBook(shown: nil, total: "9")) == general)
    }

    @Test func countsThatDoNotDescribeAPrefixAreNotTrusted() {
        let general = [PreviewStrings.text(.ebooksNoticePartialText)]
        // Nothing is missing, or more is shown than the book has, or there is no book: not a truncation to report.
        for (shown, total) in [("9", "9"), ("10", "9"), ("0", "0"), ("1", "0")] {
            #expect(notice(countedBook(shown: shown, total: total)) == general, "\(shown) of \(total)")
        }
        // Only plain whole numbers of at most seven digits are read.
        for value in ["many", "-3", "3.5", "3 chapters", "99999999", "٣"] {
            #expect(notice(countedBook(shown: value, total: "9")) == general, "\(value)")
            #expect(notice(countedBook(shown: "3", total: value)) == general, "\(value)")
        }
        // A book above the largest chapter count taken at face value is not described by it either.
        #expect(notice(countedBook(shown: "3", total: "2000000")) == general)
    }

    @Test func countsAreOnlyReadFromTheLeadingBlockAndOnlyWithThePartialFlag() {
        let body = "# One\n\nchaptersShown: 3\nchaptersTotal: 9\n"
        #expect(notice(countedBook(shown: nil, total: nil, body: body)) == [PreviewStrings.text(.ebooksNoticePartialText)])
        // The adapters write counts only beside the flag; without it nothing is claimed.
        #expect(notice(countedBook(shown: "3", total: "9", flags: [])).isEmpty)
        // Ordinary Markdown with the same front matter is not an e-book and gets no notice.
        #expect(notice(countedBook(shown: "3", total: "9"), id: .markdown).isEmpty)
    }

    // MARK: The Rendered view and the status line

    @Test func theRenderedViewHidesTheCountsLikeTheFlags() throws {
        let text = countedBook(shown: "12", total: "38")
        let document = try #require(SafeMarkdownDocument.render(presentation(.epub, text: text, syntax: .markdown)))
        for forbidden in ["chaptersShown", "chaptersTotal", "partial", "12", "38"] {
            #expect(!document.text.contains(forbidden), "\(forbidden)")
        }
        #expect(document.text.hasPrefix(PreviewStrings.text(.documentFrontMatterTitle) + " Moby Dick"))
        // Source stays exactly the safe text, counts included.
        #expect(text.contains("chaptersShown: 12\nchaptersTotal: 38\n"))
    }

    @Test func aBlockOfOnlyFlagsAndCountsShowsNothingAndLeavesNoEmptyLine() throws {
        let text = "---\npartial: true\nchaptersShown: 3\nchaptersTotal: 9\n---\n\n# Chapter\n\nText.\n"
        let document = try #require(SafeMarkdownDocument.render(presentation(.epub, text: text, syntax: .markdown)))
        #expect(document.text.hasPrefix("Chapter"))
        #expect(!document.decorations.contains { $0.style == .frontMatterBlock })
    }

    @Test func aCountKeyWithANonNumericValueIsAnOrdinaryEntryAndStaysVisible() throws {
        let text = countedBook(shown: "many", total: "9")
        let document = try #require(SafeMarkdownDocument.render(presentation(.epub, text: text, syntax: .markdown)))
        #expect(document.text.contains("chaptersShown:"))
        #expect(!document.text.contains("chaptersTotal"))
    }

    @Test func aMarkdownFilesOwnCountKeysAreNeverFiltered() throws {
        let document = try #require(SafeMarkdownDocument.render(presentation(.markdown, text: countedBook(shown: "3", total: "9"), syntax: .markdown)))
        #expect(document.text.contains("chaptersShown: 3"))
    }

    @Test func theHostingPreviewShowsTheCountedSentenceInItsStatusAndLimits() {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.display(.ready(presentation(.epub, text: countedBook(shown: "12", total: "38"), syntax: .markdown)), locale: enUS)
        #expect(host.view.displayedStatus.contains("Showing 12 of 38 chapters."))
        #expect(!host.view.displayedStatus.contains(PreviewStrings.text(.ebooksNoticePartialText)))
        #expect(host.view.limitsLabel.stringValue == "Showing 12 of 38 chapters.")
    }
}
