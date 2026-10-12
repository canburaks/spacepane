import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Debug-build smoke bounds for documents near the 262,144-unit render limit. They guard against
/// accidental quadratic behavior; they are not performance measurements.
@Suite("Markup rendering near the size limit")
struct MarkupPerformanceTests {
    private func elapsed(_ label: String, _ work: () -> Bool) -> Duration {
        let started = ContinuousClock.now
        let produced = work()
        let duration = ContinuousClock.now - started
        #expect(produced, "\(label) produced no document")
        print("MARKUP-TIMING \(label): \(duration)")
        return duration
    }

    @Test func everyRendererHandlesALargeDocumentInBoundedTime() {
        let limit = Duration.seconds(10)
        let markdown = String(repeating: "## Heading\n\nParagraph with *emphasis*, `code`, a [link](https://example.invalid) and $x^2$.\n\n- item one\n  - nested item\n- [x] task\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n", count: 1_300)
        #expect(elapsed("markdown", { SafeMarkdownDocument.render(markdown) != nil }) < limit)
        let latex = "\\begin{document}\n" + String(repeating: "\\section{Part}\nText \\emph{here} with $a_i^2$ and \\cite{k}.\n\\begin{itemize}\n\\item one\n\\item two\n\\end{itemize}\n\n", count: 2_000) + "\\end{document}"
        #expect(elapsed("latex", { LaTeXRenderer.render(latex, limits: .init()) != nil }) < limit)
        let adoc = String(repeating: "== Section\n\nText with *bold* and _italic_.\n\n* item\n** nested\n\n", count: 1_500)
        #expect(elapsed("asciidoc", { AsciiDocRenderer.render(adoc, limits: .init()) != nil }) < limit)
        let rst = String(repeating: "Section\n=======\n\nText with *emphasis* and ``literal``.\n\n- item\n\n  - nested\n\n", count: 1_500)
        #expect(elapsed("rst", { ReStructuredTextRenderer.render(rst, limits: .init()) != nil }) < limit)
        let org = String(repeating: "* Heading\nText with *bold* and /italic/.\n- item\n  - nested\n\n", count: 2_000)
        #expect(elapsed("org", { OrgRenderer.render(org, limits: .init()) != nil }) < limit)
        let fountain = String(repeating: "INT. ROOM - DAY\n\nAction line one.\nAction line two.\n\nBOB\n(softly)\nHello there.\n\n", count: 1_500)
        #expect(elapsed("fountain", { FountainRenderer.render(fountain, limits: .init()) != nil }) < limit)
        let bib = (0..<1_500).map { "@article{k\($0), author = {Author\($0), First and Other, Second}, title = {Title \($0)}, journal = {Journal}, year = {2000}, pages = {1--9}}" }.joined(separator: "\n")
        #expect(elapsed("bibtex", { SafeBibliography.parse(bib).flatMap { BibliographyFormatter.document($0, style: .apa) } != nil }) < limit)
    }
}
