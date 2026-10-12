import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Decision 027, Q-77 and review DM-24: a Markdown file with several Mermaid fences says which one the Diagram
/// mode draws ("Diagram 2 of 3 is drawn"), counted from the fences the renderer emitted, in the one limits strip.
/// Read through the strip's own entry point (`ModePresentationNotices`), so these fail until the hook that asks
/// `DrawnModeNotices` is in place as well as the wording.
@Suite("Q77 diagram selection receipt in the limits strip")
struct Q77DiagramReceiptNoticeTests {
    private let english = Locale(identifier: "en_US")
    private let first = "flowchart LR\nA[One] --> B[Two]"
    private let second = "flowchart TD\nC[Three] --> D[Four]"
    private let unsupported = "gantt\n title inert"
    private func fenced(_ body: String) -> String { "```mermaid\n" + body + "\n```" }

    private func markdown(_ source: String) -> TextPresentation {
        TextPresentation(formatID: .markdown, text: source, lineCount: source.components(separatedBy: "\n").count,
                         byteCount: source.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .markdown)
    }

    private func notices(_ source: String, mode: NativePreviewMode = .diagram, locale: Locale? = nil) -> [PresentationNotice] {
        let locale = locale ?? english
        let presentation = markdown(source)
        let modes = SafePreviewModes(presentation, locale: locale)
        return ModePresentationNotices.notices(for: presentation, modes: modes, mode: mode, locale: locale)
    }

    @Test func theDrawnDiagramIsNamedAmongAllTheFencesTheRendererEmitted() {
        // The first fence is an unsupported type, so it stays code and the second is the one drawn.
        let source = fenced(unsupported) + "\n\n" + fenced(first) + "\n\n" + fenced(second)
        #expect(notices(source) == [PresentationNotice(kind: .limit, text: "Diagram 2 of 3 is drawn.")])
    }

    @Test func theFirstFenceIsOneOfThreeWhenItIsTheDrawnOne() {
        let source = fenced(first) + "\n\n" + fenced(second) + "\n\n" + fenced(unsupported)
        #expect(notices(source) == [PresentationNotice(kind: .limit, text: "Diagram 1 of 3 is drawn.")])
    }

    @Test func emptyAndUnsupportedFencesCountEvenThoughTheyDidNotParse() {
        let source = "```mermaid\n```\n\n" + fenced(first) + "\n\n" + fenced(unsupported)
        #expect(notices(source) == [PresentationNotice(kind: .limit, text: "Diagram 2 of 3 is drawn.")])
    }

    @Test func aSingleFenceHasNothingToQualify() {
        #expect(notices(fenced(first)).isEmpty)
        #expect(notices(fenced(unsupported) + "\n\n" + fenced(first)).count == 1)
    }

    @Test func onlyTheDiagramModeCarriesTheReceipt() {
        let source = fenced(first) + "\n\n" + fenced(second)
        for mode in [NativePreviewMode.rendered, .source, .contents, .plot] {
            #expect(notices(source, mode: mode).isEmpty)
        }
    }

    @Test func noParseableFenceMeansNoDiagramAndNoReceipt() {
        #expect(notices(fenced(unsupported) + "\n\n" + fenced("flowchart LR\nA -->")).isEmpty)
    }

    @Test func aFenceBeyondTheTriedPrefixIsCountedButNeverDrawn() {
        // Sixteen empty fences use the whole bounded prefix; the diagram after them is not tried.
        let empties = String(repeating: "```mermaid\n```\n", count: MarkdownDiagramFences.maximumFences)
        #expect(notices(empties + fenced(first)).isEmpty)
        // A diagram inside the prefix is drawn, and the total still counts every emitted fence.
        let within = String(repeating: "```mermaid\n```\n", count: MarkdownDiagramFences.maximumFences - 1) + fenced(first)
            + "\n" + fenced(second) + "\n" + fenced(second)
        #expect(notices(within).map(\.text) == ["Diagram 16 of 18 is drawn."])
    }

    @Test func bothNumbersFollowThePresentationLocale() throws {
        let source = fenced(unsupported) + "\n\n" + fenced(first) + "\n\n" + fenced(second)
        // Persian has non-Latin digits by default, so the index and the total are visibly the locale's.
        let persian = Locale(identifier: "fa")
        let index = 2.formatted(.number.locale(persian))
        let total = 3.formatted(.number.locale(persian))
        let notice = try #require(notices(source, locale: persian).first)
        #expect(notice.kind == .limit)
        #expect(notice.text.contains(index) && notice.text.contains(total), "\(notice.text)")
        // As `PluralStringsTests` does: the locale's rendering of both numbers is present and no directive leaks.
        // Which other characters Foundation's plural engine emits for a locale is not this test's claim.
        #expect(!notice.text.contains("%"), "\(notice.text)")
    }
}
