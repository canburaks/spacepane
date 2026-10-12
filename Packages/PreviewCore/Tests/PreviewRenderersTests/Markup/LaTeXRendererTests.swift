import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func latex(_ source: String) throws -> SafeMarkdownDocument {
    try #require(LaTeXRenderer.render(source, limits: .init()))
}

private func body(_ source: String) -> String { "\\begin{document}\n" + source + "\n\\end{document}" }

@Suite("LaTeX rendering")
struct LaTeXRendererTests {
    @Test func sectioningCommandsBecomeHeadingsWithCompressedLevels() throws {
        let article = try latex(body("\\section{One}\n\\subsection*{Two}\n\\subsubsection[short]{Three}\n\\paragraph{Four}"))
        #expect(article.headings.map(\.level) == [1, 2, 3, 4])
        #expect(article.headings.map(\.title) == ["One", "Two", "Three", "Four"])
        for heading in article.headings { #expect(article.substring(heading.range) == heading.title) }
        let book = try latex(body("\\part{P}\n\\chapter{C}\n\\section{S}"))
        #expect(book.headings.map(\.level) == [1, 2, 3])
        let onlyChapters = try latex(body("\\chapter{C}\n\\section{S}"))
        #expect(onlyChapters.headings.map(\.level) == [1, 2])
    }

    @Test func headingTitlesRenderInlineCommands() throws {
        let document = try latex(body("\\section{Using \\emph{Emphasis} and \\texttt{code}}"))
        #expect(document.headings.first?.title == "Using Emphasis and code")
        #expect(document.has(.italic, over: "Emphasis"))
    }

    @Test func textCommandsStyleTheirArgumentsAndDeclarationsStyleTheirGroup() throws {
        let document = try latex(body("Plain \\emph{italic} \\textbf{bold} \\texttt{mono} \\textit{it2} and {\\bfseries declared} then \\verb|a_b| end"))
        #expect(document.text.contains("Plain italic bold mono it2 and declared then a_b end"))
        #expect(document.has(.italic, over: "italic"))
        #expect(document.has(.bold, over: "bold"))
        #expect(document.has(.code, over: "mono"))
        #expect(document.has(.bold, over: "declared"))
        #expect(document.has(.code, over: "a_b"))
    }

    @Test func paragraphsReflowLikeLaTeXAndBlankLinesSeparateThem() throws {
        let document = try latex(body("first line\nsecond line\n\nnext   paragraph\\\\forced break"))
        #expect(document.lines.contains("first line second line"))
        #expect(document.lines.contains("next paragraph"))
        #expect(document.lines.contains("forced break"))
    }

    @Test func listsNestAndNumberAndDescriptionsUseTheirLabels() throws {
        let document = try latex(body("\\begin{itemize}\n\\item One\n\\item Two\n\\begin{enumerate}\n\\item Inner a\n\\item Inner b\n\\end{enumerate}\n\\item Three\n\\end{itemize}\n\\begin{description}\n\\item[Term] Meaning\n\\end{description}"))
        #expect(document.lines.contains("\u{2022} One"))
        #expect(document.lines.contains("\u{2022} Two"))
        #expect(document.lines.contains("1. Inner a"))
        #expect(document.lines.contains("2. Inner b"))
        #expect(document.lines.contains("\u{2022} Three"))
        #expect(document.lines.contains("Term Meaning"))
        #expect(document.has(.definitionTerm, over: "Term"))
        let depths = document.decorations.compactMap { decoration -> Int? in
            if case .listItem(let depth, _) = decoration.style { return depth }
            return nil
        }
        #expect(depths.contains(0) && depths.contains(1))
    }

    @Test func quoteAndCenterEnvironmentsAreStyled() throws {
        let document = try latex(body("\\begin{quote}\nQuoted words.\n\\end{quote}\n\\begin{center}\nCentered\n\\end{center}"))
        #expect(document.ranges(of: .quote).contains { $0.contains("Quoted words.") })
        #expect(document.ranges(of: .indent(1)).contains { $0.contains("Quoted words.") })
        #expect(document.ranges(of: .centered).contains { $0.contains("Centered") })
    }

    @Test func verbatimLikeEnvironmentsBecomeCodeBlocksAndNeverInterpretContent() throws {
        let source = body("\\begin{verbatim}\n\\section{not a heading} $x$\n  indented\n\\end{verbatim}\n\\begin{lstlisting}[language=C]\nint x;\n\\end{lstlisting}\n\\begin{minted}{python}\nprint(1)\n\\end{minted}")
        let document = try latex(source)
        #expect(document.ranges(of: .codeBlock) == ["\\section{not a heading} $x$", "  indented", "int x;", "print(1)"])
        #expect(document.headings.isEmpty)
    }

    @Test func unterminatedVerbatimRunsToTheEndAsCode() throws {
        let document = try latex("\\begin{verbatim}\nunterminated \\input{x}\nmore")
        #expect(document.ranges(of: .codeBlock) == ["unterminated \\input{x}", "more"])
    }

    @Test func mathIsApproximatedInlineAndDisplay() throws {
        let document = try latex(body("Inline $a \\leq b$ and \\(x^2\\) and\n\\[ \\frac{a}{b} \\]\n$$ \\alpha $$\n\\begin{equation}\n e = mc^2 \\label{eq}\n\\end{equation}\n\\begin{align*}\n a &= b \\\\\n c &= d\n\\end{align*}"))
        #expect(document.ranges(of: .math) == ["a ≤ b", "x²"])
        #expect(document.ranges(of: .mathBlock) == ["a⁄b", "α", "e = mc²", "a = b", "c = d"])
        #expect(!document.text.contains("\\"))
    }

    @Test func unterminatedMathStaysText() throws {
        let document = try latex(body("costs $5 and more"))
        #expect(document.text.contains("costs $5 and more"))
        #expect(document.decorations.filter { $0.style == .math }.isEmpty)
    }

    @Test func commentsAreDimmedWithoutHidingFollowingText() throws {
        let document = try latex(body("before % hidden note: secret-free\nafter\n% whole line comment\nend"))
        #expect(document.ranges(of: .dimmed) == ["% hidden note: secret-free", "% whole line comment"])
        #expect(document.text.contains("before"))
        #expect(document.text.contains("after"))
        #expect(document.text.contains("end"))
    }

    @Test func fileReferencesAreShownAsDimmedTextAndNeverFollowed() throws {
        let document = try latex(body("\\input{chapter-two}\n\\include{appendix}\n\\includegraphics[width=3cm]{figure.png}\n\\bibliography{refs}\nText"))
        let dimmed = document.ranges(of: .dimmed)
        #expect(dimmed.contains("\\input{chapter-two}"))
        #expect(dimmed.contains("\\include{appendix}"))
        #expect(dimmed.contains("\\includegraphics[width=3cm]{figure.png}"))
        #expect(dimmed.contains("\\bibliography{refs}"))
        #expect(document.text.contains("Text"))
    }

    @Test func thePreambleIsHiddenButTitleAuthorAndDateAreKept() throws {
        let source = "\\documentclass{article}\n\\usepackage{amsmath}\n\\title{My \\emph{Title}}\n\\author{Ada Example}\n\\date{2026}\n\\begin{document}\n\\maketitle\nBody text\n\\end{document}\nAfter the end"
        let document = try latex(source)
        #expect(document.lines.first == "My Title")
        #expect(document.text.contains("Ada Example"))
        #expect(document.text.contains("2026"))
        #expect(document.text.contains("Body text"))
        #expect(!document.text.contains("amsmath"))
        #expect(!document.text.contains("documentclass"))
        #expect(!document.text.contains("After the end"))
    }

    @Test func fragmentsAndStyleFilesShowDirectivesAsDimmedSource() throws {
        let document = try latex("\\ProvidesPackage{demo}\n\\RequirePackage{xcolor}\n\\newcommand{\\foo}[1]{#1}\nPlain text here.")
        #expect(document.ranges(of: .dimmed).contains("\\RequirePackage{xcolor}"))
        #expect(document.ranges(of: .dimmed).contains { $0.hasPrefix("\\newcommand") })
        #expect(document.text.contains("Plain text here."))
    }

    @Test func unknownCommandsKeepTheirArgumentsAndSpecialCharactersDecode() throws {
        let document = try latex(body("\\mystery{kept text} R\\&D 50\\% a~b \\LaTeX\\ and M\\\"uller, \\'{e}, ``quote'' --- done -- ok \\ss"))
        #expect(document.text.contains("kept text"))
        #expect(document.text.contains("R&D 50% a\u{00A0}b LaTeX and Müller, é, “quote” — done – ok ß"))
    }

    @Test func tabularRowsBecomeTabSeparatedLines() throws {
        let document = try latex(body("\\begin{tabular}{|l|r|}\n\\hline\nName & Value \\\\ \\hline\nalpha & 1 \\\\\n\\multicolumn{2}{c}{span} \\\\\n\\end{tabular}"))
        #expect(document.lines.contains("Name\tValue"))
        #expect(document.lines.contains("alpha\t1"))
        #expect(document.lines.contains("span"))
    }

    @Test func footnotesNumberAndCollectAtTheEnd() throws {
        let document = try latex(body("One\\footnote{First note.} two\\footnote{Second \\emph{note}.}"))
        #expect(document.text.contains("One\u{00B9} two\u{00B2}"))
        #expect(document.text.contains("\u{00B9} First note."))
        #expect(document.text.contains("\u{00B2} Second note."))
        #expect(document.headings.last?.title == PreviewStrings.text(.markupFootnotes))
    }

    @Test func citationsAndReferencesBecomeBracketedKeysAndLinksAreInert() throws {
        let document = try latex(body("See \\cite{a,b} and \\ref{sec:x} at \\url{https://example.invalid} or \\href{https://example.invalid/p}{the page}."))
        #expect(document.text.contains("See [a, b] and [sec:x] at https://example.invalid or the page (https://example.invalid/p)."))
    }

    @Test func malformedAndUnterminatedConstructsNeverLoseTextOrHang() throws {
        for source in [
            "\\begin{itemize}\n\\item open list",
            "\\emph{unterminated group",
            "stray } brace and { another",
            "\\section{unterminated title",
            "\\begin{tabular}{ll} a & b",
            "\\begin{equation} x^2",
            "\\", "\\begin{", "$", "\\verb|unterminated"
        ] {
            let document = try latex(body(source))
            #expect(document.text.utf16.count < 10_000)
        }
        let nested = String(repeating: "{\\emph{", count: 200) + "deep" + String(repeating: "}}", count: 200)
        // Nesting beyond the bound is read as flat text rather than recursed into.
        #expect(try latex(body(nested)).text.contains("deep"))
    }

    @Test func rightToLeftParagraphsAreTaggedAndConcealedValuesSurvive() throws {
        let document = try latex(body("English first.\n\nשלום עולם, זו פסקה בעברית.\n\npassword: ••••"))
        #expect(document.ranges(of: .rightToLeft) == ["שלום עולם, זו פסקה בעברית."])
        #expect(document.text.contains("password: ••••"))
    }

    @Test func boundsReturnNilInsteadOfPartialOutput() {
        #expect(LaTeXRenderer.render(String(repeating: "x", count: 100), limits: { var l = MarkupBuilder.Limits(); l.maximumUTF16Units = 50; return l }()) == nil)
        #expect(LaTeXRenderer.render(String(repeating: "\\section{x}\n", count: 30), limits: { var l = MarkupBuilder.Limits(); l.maximumDecorations = 10; return l }()) == nil)
    }

    @Test func largeDocumentsRenderInBoundedTime() throws {
        let paragraph = "Some \\emph{text} with $x^2$ and a \\cite{k}. "
        let source = body(String(repeating: paragraph, count: 4_000))
        let started = ContinuousClock.now
        _ = LaTeXRenderer.render(source, limits: .init())
        #expect(ContinuousClock.now - started < .seconds(10))
    }
}
