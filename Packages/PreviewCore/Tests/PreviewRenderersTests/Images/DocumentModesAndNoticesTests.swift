import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en")

private func comicSummary(pageCount: Int = 3, shown: Int = 3, extra: String = "") -> String {
    """
    {
      "title": "Synthetic \u{1F4DA}",
      "series": "Series",
      "issueNumber": "7",
      "writer": "Writer",
      "pageCount": \(pageCount),
      "shownPages": \(shown),
      "partial": \(shown < pageCount)\(extra)
    }
    """
}

private func epubText(flags: [String] = []) -> String {
    "---\ntitle: Book\nauthor: Author\n" + flags.map { "\($0): true\n" }.joined() + "---\n\n# Chapter\n\nText.\n"
}

/// Markdown as the ebook, FictionBook and web-archive adapters write it: every descriptive field, the machine
/// flags they set, and an image kept as `![description]()` without its source.
private func convertedBookText(flags: [String] = [], body: String = "# Chapter\n\nSee ![A whale](). Text.\n") -> String {
    "---\ntitle: Moby Dick\nauthor: Herman Melville\nlanguage: en\npublisher: Press\ndate: 1851\nidentifier: urn:test:1\n"
        + "description: A whale.\nsource: example.com\nresources: image/png example.com ×2\n"
        + flags.map { "\($0): true\n" }.joined() + "---\n\n" + body
}

@Suite("Document modes, labels and notices", .serialized)
@MainActor
struct DocumentModesAndNoticesTests {
    // MARK: Modes

    @Test func comicsOpenOnPagesAndKeepTheLocalizedSummary() {
        let withPages = SafePreviewModes(presentation(.comicBook, text: comicSummary(), syntax: .json, images: testPages(3)), locale: english)
        #expect(withPages.available.contains(.pages))
        #expect(withPages.available.contains(.summary))
        #expect(withPages.initialMode(for: .comicBook) == .pages)
        #expect(withPages.imagePageTotal == 3)
        #expect(withPages.images.count == 3)

        let withoutPages = SafePreviewModes(presentation(.comicBook, text: comicSummary(pageCount: 0, shown: 0), syntax: .json), locale: english)
        #expect(!withoutPages.available.contains(.pages))
        #expect(withoutPages.initialMode(for: .comicBook) == .summary)
        #expect(withoutPages.imagePageTotal == 0)
    }

    @Test func booksAndWebArchivesOpenRenderedAndOfferPagesOnlyForTheirCover() {
        for id in [FormatID.epub, .fictionBook, .webArchive] {
            let plain = SafePreviewModes(presentation(id, text: epubText(), syntax: .markdown), locale: english)
            #expect(plain.available.contains(.rendered), "\(id.rawValue)")
            #expect(!plain.available.contains(.pages))
            #expect(plain.initialMode(for: id) == .rendered)
            let covered = SafePreviewModes(presentation(id, text: epubText(), syntax: .markdown,
                                                        images: [PreviewImage(data: Data([1]), pixelWidth: 10, pixelHeight: 15, role: .cover)]), locale: english)
            #expect(covered.available.contains(.pages))
            #expect(covered.initialMode(for: id) == .rendered)
            #expect(covered.imagePageTotal == nil)
        }
    }

    @Test func notebookFiguresAddPagesWithoutChangingTheInitialMode() {
        let notebook = ##"{"nbformat":4,"cells":[{"cell_type":"markdown","source":"# Title"}]}"##
        let figure = PreviewImage(data: Data([1]), pixelWidth: 4, pixelHeight: 4, role: .figure)
        let with = SafePreviewModes(presentation(.jupyterNotebook, text: notebook, syntax: .json, images: [figure]), locale: english)
        let without = SafePreviewModes(presentation(.jupyterNotebook, text: notebook, syntax: .json), locale: english)
        #expect(with.available.contains(.pages) && !without.available.contains(.pages))
        #expect(with.initialMode(for: .jupyterNotebook) == without.initialMode(for: .jupyterNotebook))
        #expect(without.initialMode(for: .jupyterNotebook) == .rendered)
    }

    @Test func otherFormatsNeverGainPagesOrNewInitialModes() {
        let plain = SafePreviewModes(presentation(.plainText, text: "text"), locale: english)
        #expect(plain.available == [.source])
        #expect(plain.initialMode(for: .plainText) == .source)
        let markdown = SafePreviewModes(presentation(.markdown, text: "# Title", syntax: .markdown), locale: english)
        // Markdown opens in Rendered (decision 015); ebooks add no Pages mode to it.
        #expect(markdown.initialMode(for: .markdown) == .rendered)
        #expect(!markdown.available.contains(.pages))
    }

    @Test func aBookAtTheAdaptersOutputLimitsStillRendersNatively() {
        // The adapters stop at 240,000 UTF-16 units and 19,876 lines so the Rendered view (262,144 units, 20,000
        // lines) never falls back to source for ordinary books.
        let paragraph = String(repeating: "word ", count: 20) + "\n\n"
        let longText = String((epubText() + String(repeating: paragraph, count: 2_400)).prefix(240_000))
        let long = SafePreviewModes(presentation(.epub, text: longText, syntax: .markdown), locale: english)
        #expect(long.markdown != nil)
        #expect(long.initialMode(for: .epub) == .rendered)
        let manyLines = epubText() + String(repeating: "x\n", count: 19_850)
        let tall = SafePreviewModes(presentation(.epub, text: manyLines, syntax: .markdown), locale: english)
        #expect(tall.markdown != nil)
    }

    // MARK: Summary labels

    @Test func comicSummaryFieldNamesAreLocalizedAndDocumentValuesStayVerbatim() throws {
        #expect(SafeSchemaLabels.formats.contains(.comicBook))
        let nodes = try #require(SafeStructuredText.json(comicSummary(pageCount: 1_234, shown: 3)))
        let localized = SafeSchemaLabels.localize(nodes, formatID: .comicBook, locale: Locale(identifier: "en_US"))
        let root = try #require(localized.first)
        let byName = Dictionary(uniqueKeysWithValues: root.children.map { ($0.name, $0.value) })
        #expect(byName[PreviewStrings.text(.ebooksSummaryTitle)]?.contains("Synthetic \u{1F4DA}") == true)
        #expect(byName[PreviewStrings.text(.ebooksSummaryPageCount)] == "1,234")
        #expect(byName[PreviewStrings.text(.ebooksSummaryShownPages)] == "3")
        #expect(byName[PreviewStrings.text(.ebooksSummaryPartial)] == PreviewStrings.text(.summaryBooleanTrue))
        #expect(byName["title"] == nil && byName["pageCount"] == nil)
    }

    @Test func eachSummaryFieldHasOneTypedKey() {
        let set = SummaryLabelSet.comicBook
        let fields = set.fields([]) ?? []
        #expect(fields == ["title", "series", "issueNumber", "writer", "pageCount", "declaredPageCount", "shownPages", "partial"])
        for field in fields { #expect(set.keys[field] != nil, "\(field)") }
        #expect(set.fields(["entries", "[]"]) == nil)
        #expect(set.formats == [.comicBook])
    }

    // MARK: Notices

    @Test func frontMatterFlagsAreReadOnlyFromTheLeadingBlock() {
        #expect(FrontMatterFlags.parse(epubText(flags: ["drm", "partial"])) == ["drm", "partial"])
        #expect(FrontMatterFlags.parse(epubText()) == [])
        // A flag-looking line in the body, or without the opening fence, is ordinary text.
        #expect(FrontMatterFlags.parse("---\ntitle: x\n---\n\ndrm: true\n") == [])
        #expect(FrontMatterFlags.parse("drm: true\n---\n") == [])
        #expect(FrontMatterFlags.parse("---\ndrm: false\npartial: yes\n---\n") == [])
        #expect(FrontMatterFlags.parse("") == [])
        let long = "---\n" + String(repeating: "k: v\n", count: 500) + "drm: true\n---\n"
        #expect(FrontMatterFlags.parse(long) == [])
    }

    @Test func protectedBooksShowTheDRMNoticeAndPartialOnesTheTruncationNotice() {
        let drm = presentation(.epub, text: epubText(flags: ["drm", "partial"]), syntax: .markdown)
        #expect(DocumentPresentationNotices.lines(for: drm, locale: english) == [PreviewStrings.text(.ebooksNoticeDRM)])
        let partial = presentation(.fictionBook, text: epubText(flags: ["partial"]), syntax: .markdown)
        #expect(DocumentPresentationNotices.lines(for: partial, locale: english) == [PreviewStrings.text(.ebooksNoticePartialText)])
        #expect(DocumentPresentationNotices.lines(for: presentation(.webArchive, text: epubText(), syntax: .markdown), locale: english).isEmpty)
        // Ordinary Markdown with the same text is not an ebook and gets no notice.
        #expect(DocumentPresentationNotices.lines(for: presentation(.markdown, text: epubText(flags: ["drm"]), syntax: .markdown), locale: english).isEmpty)
    }

    @Test func comicNoticeReportsShownAndTotalPagesWithLocaleAwareNumbers() {
        let partial = presentation(.comicBook, text: comicSummary(pageCount: 1_200, shown: 3), syntax: .json, images: testPages(3))
        let lines = DocumentPresentationNotices.lines(for: partial, locale: Locale(identifier: "en_US"))
        #expect(lines == ["Showing the first 3 of 1,200 pages."])
        let complete = presentation(.comicBook, text: comicSummary(), syntax: .json, images: testPages(3))
        #expect(DocumentPresentationNotices.lines(for: complete, locale: english).isEmpty)
        let none = presentation(.comicBook, text: comicSummary(pageCount: 9, shown: 0), syntax: .json)
        #expect(DocumentPresentationNotices.lines(for: none, locale: english).isEmpty)
        #expect(ComicPageFacts.pageCount(in: presentation(.comicBook, text: "not json", syntax: .json)) == nil)
        #expect(ComicPageFacts.pageCount(in: presentation(.zip, text: comicSummary(), syntax: .json)) == nil)
    }

    // MARK: Rendered metadata and images of converted documents (decision 027, Q-07; review DM-01 and DM-18)

    private func renderedBook(_ id: FormatID, flags: [String] = []) throws -> SafeMarkdownDocument {
        try #require(SafeMarkdownDocument.render(presentation(id, text: convertedBookText(flags: flags), syntax: .markdown)), "\(id.rawValue)")
    }

    @Test func renderedBooksAndSavedPagesNeverShowMachineFlagsOrEnglishImageMarkers() throws {
        for id in [FormatID.epub, .fictionBook, .webArchive] {
            let document = try renderedBook(id, flags: ["drm", "partial"])
            for forbidden in ["partial: true", "drm: true", "partial", "drm", "[image:"] {
                #expect(!document.text.contains(forbidden), "\(id.rawValue) shows \(forbidden)")
            }
            // The image is one dimmed marker that carries the description and none of the source.
            let marker = imageMarker("A whale")
            #expect(document.text.contains(marker), "\(id.rawValue)")
            #expect(document.has(.dimmed, over: marker), "\(id.rawValue)")
        }
    }

    @Test func renderedBooksLabelTheirMetadataFieldsInTheInterfaceLanguage() throws {
        // The adapters write the fields in this order (`convertedBookText`).
        let order: [DocumentFrontMatterField] = [.title, .author, .language, .publisher, .date, .identifier, .summary, .source, .resources]
        let values = ["Moby Dick", "Herman Melville", "en", "Press", "1851", "urn:test:1", "A whale.", "example.com", "image/png example.com ×2"]
        for id in [FormatID.epub, .fictionBook, .webArchive] {
            let document = try renderedBook(id, flags: ["partial"])
            // Each label replaces its raw key and the value stays the book's own.
            let expected = zip(order, values).map { field, value in PreviewStrings.text(field.label) + " " + value }
            #expect(Array(document.lines.prefix(order.count)) == expected, "\(id.rawValue)")
            #expect(document.ranges(of: .frontMatterKey) == order.map { PreviewStrings.text($0.label) }, "\(id.rawValue)")
            #expect(document.decorations.contains { $0.style == .frontMatterBlock }, "\(id.rawValue)")
            for field in order where PreviewStrings.text(field.label) != field.rawValue + ":" {
                #expect(!document.lines.contains { $0.hasPrefix(field.rawValue + ":") }, "\(id.rawValue) still shows the key \(field.rawValue)")
            }
        }
    }

    @Test func theLabelsAreTheCatalogsEnglishWords() {
        let words = ["title": "Title:", "author": "Author:", "language": "Language:", "publisher": "Publisher:", "date": "Date:",
                     "identifier": "Identifier:", "description": "Description:", "source": "Source:", "resources": "Resources:"]
        #expect(Set(DocumentFrontMatterField.allCases.map(\.rawValue)) == Set(words.keys))
        for field in DocumentFrontMatterField.allCases {
            #expect(PreviewStrings.text(field.label, languagePreferences: ["en"]) == words[field.rawValue], "\(field.rawValue)")
        }
    }

    @Test func aMarkdownFilesOwnFrontMatterIsNeverRelabelledOrFiltered() throws {
        let document = try #require(SafeMarkdownDocument.render(presentation(.markdown, text: convertedBookText(flags: ["draft"]), syntax: .markdown)))
        #expect(document.lines.prefix(3) == ["title: Moby Dick", "author: Herman Melville", "language: en"])
        #expect(document.text.contains("draft: true"))
        #expect(document.ranges(of: .frontMatterKey).first == "title:")
    }

    @Test func aBlockOfOnlyFlagsShowsNothingAndLeavesNoEmptyLineAboveTheBook() throws {
        let text = "---\ndrm: true\npartial: true\n---\n\n# Chapter\n\nText.\n"
        let value = presentation(.epub, text: text, syntax: .markdown)
        let document = try #require(SafeMarkdownDocument.render(value))
        #expect(document.lines.first == "Chapter")
        #expect(!document.decorations.contains { $0.style == .frontMatterBlock })
        // The status line reads the safe text, not the rendered text, so the notice still says it.
        #expect(DocumentPresentationNotices.lines(for: value, locale: english) == [PreviewStrings.text(.ebooksNoticeDRM)])
        #expect(FrontMatterFlags.parse(value.text) == ["drm", "partial"])
    }

    @Test func aFieldWhoseValueReadsTrueIsStillAFieldAndNotAFlag() throws {
        let text = "---\ntitle: \"true\"\npartial: true\n---\n\nBody\n"
        let document = try #require(SafeMarkdownDocument.render(presentation(.fictionBook, text: text, syntax: .markdown)))
        #expect(document.lines.first == PreviewStrings.text(.documentFrontMatterTitle) + " true")
        #expect(!document.text.contains("partial"))
    }

    @Test func descriptionsThatLookLikeFormattingNeverBecomeFormattingInAConvertedBook() throws {
        // The adapters escape prose, so the renderer reads the description as text; the marker keeps it escaped.
        let body = "Before ![A \\*logo\\* \\[one\\] \\\\ end]() after\n"
        let document = try #require(SafeMarkdownDocument.render(presentation(.epub, text: convertedBookText(body: body), syntax: .markdown)))
        #expect(document.text.contains("Before \(imageMarker("A *logo* [one] \\ end")) after"))
        #expect(!document.decorations.contains { $0.style == .italic || $0.style == .bold })
    }

    @Test func thePreviewModesRenderConvertedBooksWithTheirFormatsFrontMatterStyle() {
        // Goes through `SafePreviewModes`, which passes the whole presentation to `SafeMarkdownDocument.render`.
        for id in [FormatID.epub, .fictionBook, .webArchive] {
            let modes = SafePreviewModes(presentation(id, text: convertedBookText(flags: ["drm"]), syntax: .markdown), locale: english)
            let text = modes.markdown?.text ?? ""
            #expect(!text.contains("drm: true"), "\(id.rawValue)")
            #expect(text.hasPrefix(PreviewStrings.text(.documentFrontMatterTitle) + " Moby Dick"), "\(id.rawValue)")
        }
        // Another Markdown format with the very same text keeps its keys as written.
        let plain = SafePreviewModes(presentation(.markdown, text: convertedBookText(flags: ["drm"]), syntax: .markdown), locale: english)
        #expect(plain.markdown?.text.contains("drm: true") == true)
    }

    // MARK: The hosting preview view

    private func nativeView() -> NativePreviewView { NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 480)) }
    private func pagesView(in view: NativePreviewView) -> NativeImagePagesView? { descendants(of: NativeImagePagesView.self, in: view).first }
    private func segmentLabels(in view: NativePreviewView) -> [String] {
        let control = view.modeControl
        return (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
    }
    private func status(in view: NativePreviewView) -> String {
        view.displayedStatus
    }

    @Test func aComicPresentationHostsThePagesViewWithItsModeAndNotice() throws {
        let view = nativeView()
        view.display(.ready(presentation(.comicBook, text: comicSummary(pageCount: 40, shown: 3), syntax: .json, images: testPages(3))), locale: english)
        let pages = try #require(pagesView(in: view))
        #expect(!pages.isHidden)
        #expect(pages.pageCount == 3)
        #expect(segmentLabels(in: view).contains(PreviewStrings.text(.previewModePages)))
        #expect(status(in: view).contains("Showing the first 3 of 40 pages."))
        view.display(.cancelled)
        #expect(pages.pageCount == 0)
        #expect(pagesView(in: view)?.isHidden == true)
    }

    @Test func aReplacementPresentationNeverShowsThePreviousPages() throws {
        let view = nativeView()
        view.display(.ready(presentation(.comicBook, text: comicSummary(), syntax: .json, images: testPages(3))), locale: english)
        let pages = try #require(pagesView(in: view))
        #expect(pages.pageCount == 3)
        view.display(.ready(presentation(.plainText, text: "plain")), locale: english)
        #expect(pages.pageCount == 0)
        #expect(pages.isHidden)
        view.display(.disabledByUser(.comicBook), locale: english)
        #expect(pages.pageCount == 0)
    }

    @Test func aBookOpensRenderedWithItsDRMNoticeInTheStatusLine() {
        let view = nativeView()
        view.display(.ready(presentation(.epub, text: epubText(flags: ["drm"]), syntax: .markdown)), locale: english)
        #expect(status(in: view).contains(PreviewStrings.text(.ebooksNoticeDRM)))
        #expect(segmentLabels(in: view).first == PreviewStrings.text(.previewModeSource) || segmentLabels(in: view).contains(PreviewStrings.text(.previewModeRendered)))
    }

    // MARK: Localization

    @Test func everyNewInterfaceStringIsTranslatedForEveryOtherLanguage() {
        let keys: [PreviewStrings.Key] = [
            .ebooksPagesPage, .ebooksPagesCover, .ebooksPagesFigure, .ebooksPagesImage, .ebooksPagesHelp, .ebooksPagesUnavailable,
            .ebooksNoticePartialPages, .ebooksNoticePartialText, .ebooksNoticeDRM, .ebooksSummaryTitle, .ebooksSummarySeries,
            .ebooksSummaryIssueNumber, .ebooksSummaryWriter, .ebooksSummaryPageCount, .ebooksSummaryDeclaredPageCount,
            .ebooksSummaryShownPages, .ebooksSummaryPartial
        ]
        let languages = ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for key in keys {
            let source = PreviewStrings.text(key, languagePreferences: ["en"])
            for language in languages {
                let translated = PreviewStrings.text(key, languagePreferences: [language])
                #expect(translated != source || key == .ebooksSummarySeries, "\(key.rawValue) \(language)")
                #expect(!translated.isEmpty)
                if source.contains("%1$@") { #expect(translated.contains("%1$@") && translated.contains("%2$@"), "\(key.rawValue) \(language)") }
            }
        }
    }

    @Test func formatNamesAndDescriptionsForTheNewTypesResolveInEveryLanguage() throws {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for id in [FormatID.comicBook, .epub, .fictionBook, .webArchive] {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: id))
            for language in languages {
                for key in [descriptor.nameKey, descriptor.descriptionKey] {
                    let value = PreviewStrings.text(catalogKey: key, languagePreferences: [language])
                    #expect(!value.isEmpty && value != key, "\(key) \(language)")
                }
            }
        }
    }
}
