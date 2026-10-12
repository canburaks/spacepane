import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The typed receipt behind "Diagram 2 of 3 is drawn" (decision 027, Q-77): which emitted fence the Diagram mode
/// draws, out of how many were emitted, counted from emission and never from the fences that happened to parse.
@Suite("Q77 diagram selection receipt")
struct Q77DiagramSelectionReceiptTests {
    private let english = Locale(identifier: "en_US")
    private let first = "flowchart LR\nA[One] --> B[Two]"
    private let second = "flowchart TD\nC[Three] --> D[Four]"
    private let unsupported = "gantt\n title inert"
    private func fenced(_ body: String) -> String { "```mermaid\n" + body + "\n```" }
    private let empty = "```mermaid\n```"

    private func document(_ source: String) throws -> SafeMarkdownDocument {
        try #require(SafeMarkdownDocument.render(source))
    }

    // MARK: Selection

    @Test func theSelectionNamesTheFenceThatParsedAndCountsEveryEmittedFence() throws {
        let doc = try document([empty, fenced(unsupported), fenced(first), fenced(second)].joined(separator: "\n\n"))
        let selection = try #require(MarkdownDiagramFences.selection(in: doc, locale: english))
        #expect(selection.receipt == MarkdownDiagramFences.Receipt(selectedIndex: 3, total: 4))
        #expect(selection.diagram == SafeDiagram.parse(mermaid: first, environment: DiagramEnvironment(locale: english)))
        // The old entry point is the same selection without its receipt.
        #expect(MarkdownDiagramFences.firstDiagram(in: doc, locale: english) == selection.diagram)
    }

    @Test func aSingleFenceIsOneOfOne() throws {
        let selection = try #require(MarkdownDiagramFences.selection(in: try document(fenced(first)), locale: english))
        #expect(selection.receipt == MarkdownDiagramFences.Receipt(selectedIndex: 1, total: 1))
    }

    @Test func noFenceThatParsesMeansNoSelection() throws {
        #expect(MarkdownDiagramFences.selection(in: try document(fenced(unsupported) + "\n\n" + empty), locale: english) == nil)
        #expect(MarkdownDiagramFences.selection(in: try document("# Title\n\nNo diagrams here.\n"), locale: english) == nil)
    }

    @Test func theTriedPrefixIsBoundedButTheTotalCountsEveryEmittedFence() throws {
        let emptyFences = String(repeating: empty + "\n", count: MarkdownDiagramFences.maximumFences)
        // A diagram after the sixteenth fence is never tried.
        #expect(MarkdownDiagramFences.selection(in: try document(emptyFences + fenced(first)), locale: english) == nil)
        // A diagram at the sixteenth is drawn; the total includes the fences after it.
        let almost = String(repeating: empty + "\n", count: MarkdownDiagramFences.maximumFences - 1)
        let doc = try document(almost + fenced(first) + "\n" + fenced(second) + "\n" + empty)
        let selection = try #require(MarkdownDiagramFences.selection(in: doc, locale: english))
        #expect(selection.receipt.selectedIndex == MarkdownDiagramFences.maximumFences)
        #expect(selection.receipt.total == MarkdownDiagramFences.maximumFences + 2)
    }

    @Test func badRangesAreNotCounted() {
        let text = first
        let malformed = SafeMarkdownDocument(text: text, decorations: [], diagramFences: [
            .init(range: NSRange(location: Int.max, length: 2)),
            .init(range: NSRange(location: -1, length: 2)),
            .init(range: NSRange(location: 0, length: text.utf16.count))
        ])
        #expect(MarkdownDiagramFences.selection(in: malformed, locale: english)?.receipt
                == MarkdownDiagramFences.Receipt(selectedIndex: 1, total: 1))
    }

    // MARK: Receipt from a drawn diagram, without laying anything out again

    @Test func theReceiptOfTheDrawnDiagramIsFoundByItsModelAndMatchesTheSelection() throws {
        let doc = try document([fenced(unsupported), fenced(first), fenced(second), empty].joined(separator: "\n\n"))
        let selection = try #require(MarkdownDiagramFences.selection(in: doc, locale: english))
        #expect(MarkdownDiagramFences.receipt(for: selection.diagram, in: doc) == selection.receipt)
        // Re-measured with another font and locale, the same diagram still names the same fence.
        let remeasured = try #require(selection.diagram.laidOut(with: DiagramEnvironment(font: DiagramFont(size: 20), locale: Locale(identifier: "de_DE"))))
        #expect(MarkdownDiagramFences.receipt(for: remeasured, in: doc) == selection.receipt)
    }

    @Test func twoIdenticalFencesNameTheFirst() throws {
        let doc = try document(fenced(first) + "\n\n" + fenced(first))
        let selection = try #require(MarkdownDiagramFences.selection(in: doc, locale: english))
        #expect(selection.receipt == MarkdownDiagramFences.Receipt(selectedIndex: 1, total: 2))
        #expect(MarkdownDiagramFences.receipt(for: selection.diagram, in: doc) == selection.receipt)
    }

    @Test func aDiagramThatIsNotAFenceOfTheDocumentHasNoReceipt() throws {
        let doc = try document(fenced(first) + "\n\n" + fenced(second))
        let other = try #require(SafeDiagram.parse(mermaid: "flowchart LR\nX --> Y", environment: DiagramEnvironment(locale: english)))
        #expect(MarkdownDiagramFences.receipt(for: other, in: doc) == nil)
    }

    // MARK: The strip's entry point

    @Test func theEntryPointAnswersOnlyForTheDiagramModeOfAFileWithSeveralFences() throws {
        func modes(_ source: String) -> SafePreviewModes {
            SafePreviewModes(TextPresentation(formatID: .markdown, text: source, lineCount: source.components(separatedBy: "\n").count,
                                              byteCount: source.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .markdown),
                             locale: english)
        }
        let several = modes(fenced(unsupported) + "\n\n" + fenced(first) + "\n\n" + fenced(second))
        #expect(DrawnModeNotices.notices(modes: several, mode: .diagram, locale: english)
                == [MarkdownDiagramFences.Receipt(selectedIndex: 2, total: 3).presentationNotice(locale: english)])
        for mode in [NativePreviewMode.rendered, .source, .plot, .summary] {
            #expect(DrawnModeNotices.notices(modes: several, mode: mode, locale: english).isEmpty)
        }
        #expect(DrawnModeNotices.notices(modes: modes(fenced(first)), mode: .diagram, locale: english).isEmpty)
        // A diagram file that is not Markdown has no fences to qualify.
        let mermaid = SafePreviewModes(TextPresentation(formatID: .mermaid, text: first, lineCount: 2, byteCount: first.utf8.count,
                                                        encoding: .utf8, redactionCount: 0, syntax: .mermaid), locale: english)
        #expect(mermaid.diagram != nil)
        #expect(DrawnModeNotices.notices(modes: mermaid, mode: .diagram, locale: english).isEmpty)
    }

    @Test func thePlotNoticeIsTheEntryPointsAnswerForThePlotMode() {
        var modes = SafePreviewModes(TextPresentation(formatID: .gpx, text: "{}", lineCount: 1, byteCount: 2, encoding: .utf8,
                                                      redactionCount: 0, syntax: .json), locale: english)
        let path = [SafePlot.Position(longitude: 1, latitude: 2), SafePlot.Position(longitude: 3, latitude: 4)]
        modes.plot = SafePlot(paths: [path], points: [], simplified: true)
        #expect(DrawnModeNotices.notices(modes: modes, mode: .plot, locale: english)
                == [PresentationNotice(kind: .limit, text: PreviewStrings.text(.dataPlotSimplified))])
        modes.plot = SafePlot(paths: [path], points: [], simplified: false)
        #expect(DrawnModeNotices.notices(modes: modes, mode: .plot, locale: english).isEmpty)
    }

    // MARK: Wording

    @Test func bothNoticesAreTranslatedInEveryLanguageWithTheirPlaceholdersIntact() {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for language in languages {
            let drawn = PreviewStrings.count(.diagramNoticeDrawn, 3, additionalArguments: ["2"], locale: english, languagePreferences: [language])
            #expect(drawn.contains("2") && drawn.contains("3") && !drawn.contains("%") && !drawn.contains("preview.diagram"), "\(language): \(drawn)")
            let readable = PreviewStrings.format(.diagramNoticeReadable, arguments: ["63%"], locale: english, languagePreferences: [language])
            #expect(readable.contains("63%") && !readable.contains("preview.diagram"), "\(language): \(readable)")
            if language != "en" {
                #expect(drawn != PreviewStrings.count(.diagramNoticeDrawn, 3, additionalArguments: ["2"], locale: english, languagePreferences: ["en"]), "\(language)")
                #expect(readable != PreviewStrings.format(.diagramNoticeReadable, arguments: ["63%"], locale: english, languagePreferences: ["en"]), "\(language)")
            }
        }
    }
}
