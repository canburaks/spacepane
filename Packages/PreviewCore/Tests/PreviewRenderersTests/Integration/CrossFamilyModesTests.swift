import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Behavior that joins two workstreams' derived modes, owned by the integration rather than either family.
@Suite("Cross-family preview modes")
struct CrossFamilyModesTests {
    private func presentation(_ text: String, format: FormatID, syntax: TextSyntax, images: [PreviewImage] = []) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: text.components(separatedBy: "\n").count,
                         byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax, images: images)
    }

    @Test func aMermaidFenceInMarkdownAlsoOpensInDiagramWhileRenderedStaysFirst() throws {
        let source = "# Flow\n\nIntro text.\n\n```mermaid\nflowchart LR\n  A[Start] --> B[Finish]\n\n  B --> C[Done]\n```\n\nAfter.\n"
        let modes = SafePreviewModes(presentation(source, format: .markdown, syntax: .markdown), locale: Locale(identifier: "en_US"))
        let diagram = try #require(modes.diagram)
        #expect(modes.available.contains(.rendered) && modes.available.contains(.diagram))
        #expect(modes.initialMode(for: .markdown) == .rendered)
        // The blank line inside the fence does not split it: all three nodes reach the diagram.
        let document = try #require(modes.markdown)
        #expect(MarkdownDiagramFences.fenceRanges(in: document, text: document.text as NSString).count == 1)
        #expect(diagram == SafeDiagram.parse(mermaid: "flowchart LR\n  A[Start] --> B[Finish]\n\n  B --> C[Done]",
                                             environment: DiagramEnvironment(locale: Locale(identifier: "en_US"))))
    }

    @Test func markdownWithoutAParseableFenceHasNoDiagramMode() {
        let plain = SafePreviewModes(presentation("# Title\n\n```swift\nlet x = 1\n```\n", format: .markdown, syntax: .markdown),
                                     locale: Locale(identifier: "en_US"))
        #expect(plain.diagram == nil && !plain.available.contains(.diagram))
        let unsupported = SafePreviewModes(presentation("```mermaid\ngantt\n  title Plan\n```\n", format: .markdown, syntax: .markdown),
                                           locale: Locale(identifier: "en_US"))
        #expect(unsupported.diagram == nil)
    }

    @Test func applicationIconsUseTheIconModeAndNeverPages() {
        let icon = PreviewImage(data: Data([1, 2, 3]), pixelWidth: 64, pixelHeight: 64, role: .icon)
        let cover = PreviewImage(data: Data([4, 5, 6]), pixelWidth: 60, pixelHeight: 90, role: .cover)
        let app = SafePreviewModes(presentation("{}", format: .applicationBundle, syntax: .json, images: [icon]),
                                   locale: Locale(identifier: "en_US"))
        #expect(app.available.contains(.icon) && !app.available.contains(.pages) && app.pageImages.isEmpty)
        let book = SafePreviewModes(presentation("# Book\n", format: .epub, syntax: .markdown, images: [cover]),
                                    locale: Locale(identifier: "en_US"))
        #expect(book.available.contains(.pages) && !book.available.contains(.icon) && book.pageImages == [cover])
    }

    @Test func markupSourcesUseTheMarkupLexersInSourceMode() {
        for (text, syntax) in [("\\section{Intro} % note", TextSyntax.latex), ("@article{key, title = {A}}", .bibtex),
                               ("= Title\n*bold*", .asciidoc), ("Title\n=====\n", .restructuredText),
                               ("* Heading\n", .orgMode), ("INT. HOUSE - DAY\n", .fountain)] {
            #expect(SourceSyntaxTokens.tokens(in: text, syntax: syntax) == MarkupSourceTokens.tokens(in: text, syntax: syntax))
            #expect(!SourceSyntaxTokens.tokens(in: text, syntax: syntax).isEmpty)
        }
    }
}
