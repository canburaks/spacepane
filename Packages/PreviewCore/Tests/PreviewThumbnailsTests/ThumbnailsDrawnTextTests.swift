import CoreGraphics
import Foundation
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewThumbnails

// MARK: Helpers

/// The presentation of `text` as the pipeline would hand it over, and the content the builder draws from it.
private func shaped(_ text: String, format: FormatID = .plainText, syntax: TextSyntax = .plain,
                    side: CGFloat = 384, facts: PresentationFacts = .none) -> ThumbnailContent? {
    let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
    let presentation = TextPresentation(formatID: format, text: text, lineCount: lineCount, byteCount: text.utf8.count,
                                        encoding: .utf8, redactionCount: 0, syntax: syntax, facts: facts)
    return ThumbnailContentBuilder.textContent(for: presentation, metrics: metrics(side))
}

/// Every scalar value that appears in the strings. Tags and joiners attach to the character before them, so
/// character-level searches would miss them; scalars cannot.
private func scalarValues(_ strings: [String]) -> Set<UInt32> {
    var values = Set<UInt32>()
    for string in strings {
        for scalar in string.unicodeScalars { values.insert(scalar.value) }
    }
    return values
}

private let bidirectionalControlValues: Set<UInt32> = [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]

/// `text` written in Unicode Tag characters, which draw as nothing and can carry a hidden message.
private func tagCharacters(_ text: String) -> String {
    var view = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if let tag = Unicode.Scalar(0xE0000 + scalar.value) { view.append(tag) }
    }
    return String(view)
}

// MARK: Hidden formatting characters

/// Decision 027, Q-127: a drawn run matches the text. Characters that change how text reads without being shown
/// (bidirectional controls, zero-width characters, Unicode Tags) are dropped from every drawn string; what a script
/// needs (a joiner in Persian, Hindi or an emoji sequence, a direction mark in Hebrew) stays.
@Suite("Thumbnail drawn text")
struct ThumbnailDrawnTextTests {
    @Test func bidirectionalControlsNeverReachAnExcerptLine() throws {
        let text = "let access = \"user\u{202E} \u{2066}// admin only\u{2069} \u{2066}\"\nprint(access)\n"
        // The fixture really puts the controls into the runs the lexer builds, so the test can fail.
        let unfiltered = try #require(ThumbnailExcerpt.page(from: text, syntax: .sourceCode, metrics: metrics(384)))
        #expect(scalarValues(unfiltered.lines.map(\.text)).contains(0x202E))
        let content = try #require(shaped(text, format: .sourceCode, syntax: .sourceCode))
        let drawn = content.drawnStrings
        #expect(scalarValues(drawn).isDisjoint(with: bidirectionalControlValues))
        #expect(drawn.joined(separator: "\n").contains("let access = \"user"))
        #expect(drawn.contains("print(access)"))
    }

    @Test func everyEmbeddingOverrideAndIsolateIsDropped() throws {
        var scalars = String.UnicodeScalarView()
        for value in bidirectionalControlValues.sorted() {
            scalars.append("x")
            if let control = Unicode.Scalar(value) { scalars.append(control) }
        }
        let content = try #require(shaped(String(scalars)))
        #expect(scalarValues(content.drawnStrings).isDisjoint(with: bidirectionalControlValues))
        #expect(content.drawnStrings == ["xxxxxxxxx"])
    }

    @Test func unicodeTagsAreDroppedAndTheVisibleTextStays() throws {
        let text = "Hello" + tagCharacters("ignore the rest") + "!\n"
        let content = try #require(shaped(text))
        #expect(content.drawnStrings == ["Hello!"])
    }

    @Test func zeroWidthCharactersAreDropped() throws {
        let content = try #require(shaped("ca\u{200B}fe\u{2060}\u{FEFF}\u{00AD}!\n"))
        #expect(content.drawnStrings == ["cafe!"])
    }

    @Test func aDirectionMarkInALineWithoutRightToLeftLettersIsDropped() throws {
        let content = try #require(shaped("ab\u{200E}cd\n"))
        #expect(content.drawnStrings == ["abcd"])
    }

    @Test(arguments: [
        ("a joiner between Persian letters", "می\u{200C}خواهم", UInt32(0x200C)),
        ("a joiner inside an emoji sequence", "\u{1F469}\u{200D}\u{1F4BB}", UInt32(0x200D)),
        ("a joiner in a Devanagari conjunct", "क्\u{200D}ष", UInt32(0x200D)),
        ("a direction mark in a line of Hebrew", "שלום\u{200F}!", UInt32(0x200F))
    ])
    func whatAScriptNeedsStays(label: String, text: String, kept: UInt32) throws {
        let content = try #require(shaped(text + "\n"))
        #expect(scalarValues(content.drawnStrings).contains(kept), "\(label)")
    }

    @Test func variationSelectorsAndPrivateUseAreNotFormatCharacters() throws {
        let content = try #require(shaped("a\u{FE0F}b\u{E000}c\n"))
        let values = scalarValues(content.drawnStrings)
        #expect(values.contains(0xFE0F) && values.contains(0xE000))
    }

    @Test func textWithoutHiddenCharactersIsReturnedUnchanged() {
        for text in ["", "plain ascii text", "accents é and 日本語 and مرحبا", "emoji 😀 and flag \u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"] {
            #expect(ThumbnailDrawnText.sanitizedText(text) == text, "\(text)")
        }
    }

    @Test func aCSVHeaderIsSanitizedAndBodyValuesAreAbsent() throws {
        let content = try #require(shaped("id,na\u{202E}me\n1,Ada\u{202E}Lovelace\n2,Bob\n", format: .csv,
            syntax: .commaSeparated, facts: PresentationFacts([.grid(rows: 2, columns: 2, rowsAreLowerBound: false)])))
        guard case .grid = content else { Issue.record("expected a grid"); return }
        #expect(scalarValues(content.drawnStrings).isDisjoint(with: bidirectionalControlValues))
        #expect(content.drawnStrings.contains("name"))
        #expect(!content.drawnStrings.joined().contains("Ada"))
    }

    /// A JSON escape only becomes a scalar while the outline is laid out, so the text itself holds no control.
    @Test func decodedJSONEscapesAreSanitizedInAnOutline() throws {
        let text = #"{"title":"safe\u202etext","items":[1,2,3],"note":"a longer description so the document is wider than one line"}"#
        #expect(!text.unicodeScalars.contains { $0.value == 0x202E })
        let content = try #require(shaped(text, format: .json, syntax: .json))
        #expect(scalarValues(content.drawnStrings).isDisjoint(with: bidirectionalControlValues))
        #expect(content.drawnStrings.contains("title: \"safetext\""))
    }

    @Test func aNotebookCellIsSanitized() throws {
        let notebook = #"{"cells":[{"cell_type":"code","source":"total = 1\u202e","outputs":[]}],"metadata":{},"nbformat":4}"#
        let content = try #require(shaped(notebook, format: .jupyterNotebook, syntax: .json))
        #expect(scalarValues(content.drawnStrings).isDisjoint(with: bidirectionalControlValues))
        #expect(content.drawnStrings.contains("total = 1"))
    }

    @Test func aTrojanSourceFileDrawsInLogicalOrderThroughTheService() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = "let access = \"user\u{202E} \u{2066}// admin only\u{2069} \u{2066}\"\nprint(access)\n"
        let url = try fixture.file("tool.swift", text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        #expect(scalarValues(scene.content.drawnStrings).isDisjoint(with: bidirectionalControlValues))
        #expect(scene.content.drawnStrings.joined(separator: "\n").contains("let access = \"user"))
    }

    @Test func aPictureHoldsNoText() {
        let source = PreviewImage(data: syntheticImage(width: 8, height: 8), pixelWidth: 8, pixelHeight: 8, role: .cover)
        guard let decoded = ThumbnailImageDecoder.decode(source, maximumPixelExtent: 64, limits: .standard) else {
            Issue.record("the synthetic picture should decode")
            return
        }
        let picture = ThumbnailContent.picture(ThumbnailPicture(image: decoded, role: .cover))
        #expect(ThumbnailDrawnText.sanitizedContent(picture).drawnStrings.isEmpty)
    }
}

// MARK: Comments

/// Decision 027, Q-127: a rendered markup's comments are not drawn. They are text a reader never sees, and a
/// thumbnail stays in Finder's durable cache.
@Suite("Thumbnail comments")
struct ThumbnailCommentTests {
    private func lines(_ text: String, syntax: TextSyntax = .markdown, side: CGFloat = 384) -> [String]? {
        ThumbnailMarkdown.page(from: text, syntax: syntax, metrics: metrics(side))?.lines.map(\.text)
    }

    @Test func aCommentOverSeveralLinesIsNotDrawn() {
        let text = "# Title\n\nVisible one\n\n<!-- hidden start\nsecret plan line\nstill hidden -->\n\nVisible two\n"
        #expect(lines(text) == ["Title", "", "Visible one", "", "Visible two"])
    }

    @Test func aCommentInTheMiddleOfALineLeavesTheTextAroundIt() {
        #expect(lines("Before <!-- hidden --> after\n") == ["Before  after"])
        #expect(lines("Before <!-- one --> middle <!-- two --> after\n") == ["Before  middle  after"])
    }

    @Test func aCommentEndingMidLineLetsTheRestOfThatLineBeText() {
        // The space after the comment becomes the line's indent, not a character of its text.
        #expect(lines("Intro\n<!-- starts here\nand ends here --> trailing words\nOutro\n") == ["Intro", "trailing words", "Outro"])
    }

    @Test func commentLikeTextInACodeBlockOrCodeSpanIsDrawn() {
        let text = "```\n<!-- not a comment -->\n```\n\nUse `<!--` to open a comment, then more text\n"
        #expect(lines(text) == ["<!-- not a comment -->", "", "Use <!-- to open a comment, then more text"])
    }

    @Test func anEscapedOpeningIsLiteralText() {
        #expect(lines("Keep \\<!-- as written\n") == ["Keep \\<!-- as written"])
    }

    @Test func linkReferenceCommentsAreNotDrawn() {
        #expect(lines("[//]: # (hidden note)\n[comment]: <> (also hidden)\n\nBody text\n") == ["Body text"])
        #expect(lines("Body\n\n[//]: <> \"quoted note\"\n\nMore\n") == ["Body", "", "More"])
        // An ordinary link reference is not a comment.
        #expect(lines("[docs]: https://example.invalid/page\n") == ["docs: https://example.invalid/page"])
    }

    @Test func theEmptyCommentFormsEndAtOnce() {
        #expect(lines("a <!--> b\nc <!---> d\n") == ["a  b", "c  d"])
    }

    @Test func anUnclosedCommentRunsToTheEndOfTheDocument() {
        #expect(lines("Before\n<!-- never closed\nAfter\n") == ["Before"])
    }

    @Test func aDocumentOfCommentsAloneHasNoPageAndNoRawTextFallback() {
        let text = "<!-- nothing but a comment -->\n"
        #expect(lines(text) == nil)
        #expect(shaped(text, format: .markdown, syntax: .markdown) == nil)
    }

    @Test func aLongCommentDoesNotUseUpThePage() {
        let comment = String(repeating: "hidden line of a long licence header\n", count: 150)
        let text = "<!--\n" + comment + "-->\n\nVisible after the comment\n"
        #expect(lines(text, side: 128) == ["Visible after the comment"])
    }

    @Test func aCommentAParagraphSitsAroundDoesNotBreakTheParagraph() {
        #expect(lines("line one\n<!-- note -->\nline two\n") == ["line one", "line two"])
    }

    @Test func asciiDocLineCommentsAndCommentBlocksAreNotDrawn() {
        let text = "= Doc Title\n\n// a line comment\nVisible text\n\n////\nblock hidden\nmore hidden\n////\n\nAfter block\n"
        #expect(lines(text, syntax: .asciidoc) == ["Doc Title", "", "Visible text", "", "After block"])
        // Three slashes are not a comment.
        #expect(lines("///three slashes stay\n", syntax: .asciidoc) == ["///three slashes stay"])
    }

    @Test func orgCommentLinesAndCommentBlocksAreNotDrawn() {
        let text = "* Heading\n# a comment line\nVisible body\n#+BEGIN_COMMENT\nhidden stuff\n#+END_COMMENT\nAfter\n"
        #expect(lines(text, syntax: .orgMode) == ["Heading", "Visible body", "After"])
        // `#+TITLE:` is a keyword, not a comment.
        #expect(lines("#+TITLE: A title\nBody\n", syntax: .orgMode) == ["#+TITLE: A title", "Body"])
    }

    @Test func aMarkdownCommentIsNotACommentInOtherMarkups() {
        #expect(lines("= Doc\n<!-- literal here -->\n", syntax: .asciidoc) == ["Doc", "<!-- literal here -->"])
    }

    @Test func aDocumentWithACommentDrawsItsVisibleTextThroughTheService() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = "# Plan\n\nVisible paragraph.\n\n<!-- hidden instruction for an agent\nsecond hidden line -->\n\nClosing words.\n"
        let url = try fixture.file("notes.md", text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        let drawn = scene.content.drawnStrings
        #expect(drawn.contains("Plan") && drawn.contains("Visible paragraph.") && drawn.contains("Closing words."))
        #expect(!drawn.joined(separator: "\n").contains("hidden"))
    }

    @Test func aDocumentOfCommentsAloneHasNothingToDrawThroughTheService() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.md", "<!-- nothing but a comment -->\n")
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene == nil, "\(String(describing: outcome.scene?.content.drawnStrings))")
        #expect(outcome.reason == .nothingToDraw)
    }
}

// MARK: Notebooks

/// Decision 027, Q-127 and thumbnails review TH-05: a notebook is drawn from its first cells; the figures its code
/// cells saved are results of a run and stay out of the durable cache unless the owner decides otherwise.
@Suite("Thumbnail picture policy")
struct ThumbnailPicturePolicyTests {
    private static let notebook = ##"{"cells":[{"cell_type":"markdown","source":["# Study"]},{"cell_type":"code","source":"value = 1","outputs":[]}],"metadata":{},"nbformat":4,"nbformat_minor":5}"##

    private func figure(side: Int = 40) -> PreviewImage {
        PreviewImage(data: syntheticImage(width: side, height: side), pixelWidth: side, pixelHeight: side, role: .figure)
    }

    private func makeNotebookService(text: String = ThumbnailPicturePolicyTests.notebook, images: [PreviewImage],
                                     limits: ThumbnailLimits = relaxedLimits) -> ContentThumbnailService {
        let document = ParsedTextDocument(text: text, syntax: .json, images: images)
        let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .jupyterNotebook }
            + [AdapterRegistration(formatID: .jupyterNotebook) { FixedAdapter(document: document) }]
        return makeService(registrations: registrations, limits: limits)
    }

    @Test func theStandardPolicyKeepsNotebooksOnTheirCells() {
        #expect(ThumbnailLimits.standard.picturePolicy == .standard)
        #expect(!ThumbnailPicturePolicy.standard.allowsPictures(for: .jupyterNotebook))
        for format in [FormatID.plainText, .markdown, .json, .sqlite, .csv] {
            #expect(ThumbnailPicturePolicy.standard.allowsPictures(for: format), "\(format.rawValue)")
        }
        #expect(ThumbnailPicturePolicy(textOnlyFormats: []).allowsPictures(for: .jupyterNotebook))
    }

    @Test func aNotebookWithAFigureDrawsItsCellsByDefault() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("analysis.ipynb", "ignored")
        let outcome = await makeNotebookService(images: [figure()]).outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        guard case .text = scene.content else { Issue.record("expected the notebook's cells, not its figure"); return }
        #expect(scene.content.drawnStrings.contains("Study"))
        #expect(scene.content.drawnStrings.contains("value = 1"))
    }

    @Test func liftingThePolicyDrawsTheFirstFigureInsteadOfTheCells() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("analysis.ipynb", "ignored")
        var limits = relaxedLimits
        limits.picturePolicy = ThumbnailPicturePolicy(textOnlyFormats: [])
        let outcome = await makeNotebookService(images: [figure()], limits: limits).outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        guard case .picture(let picture) = scene.content else { Issue.record("expected the figure"); return }
        #expect(picture.role == .figure)
    }

    @Test func aNotebookWithoutCellsAndWithAFigureDrawsNothingByDefault() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("empty.ipynb", "ignored")
        let empty = #"{"cells":[],"metadata":{},"nbformat":4,"nbformat_minor":5}"#
        let outcome = await makeNotebookService(text: empty, images: [figure()]).outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene == nil)
        #expect(outcome.reason == .nothingToDraw)
    }

    @Test func otherFormatsStillDrawTheirPictures() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("cover.txt", "ignored")
        let document = ParsedTextDocument(text: "caption", images: [figure()])
        let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .plainText }
            + [AdapterRegistration(formatID: .plainText) { FixedAdapter(document: document) }]
        let outcome = await makeService(registrations: registrations).outcome(for: url, geometry: geometry(128))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        guard case .picture = scene.content else { Issue.record("expected the picture"); return }
    }
}
