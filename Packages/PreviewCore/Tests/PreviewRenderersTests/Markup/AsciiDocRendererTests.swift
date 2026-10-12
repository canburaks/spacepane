import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func asciidoc(_ source: String) throws -> SafeMarkdownDocument {
    try #require(AsciiDocRenderer.render(source, limits: .init()))
}

@Suite("AsciiDoc rendering")
struct AsciiDocRendererTests {
    @Test func sectionTitlesBecomeLeveledHeadingsAndTheDocumentHeaderIsKept() throws {
        let document = try asciidoc("= Document Title\nAda Example\nv1.0, 2026\n\n== Section One\n\n=== Sub *bold*\n\n====== Deep\n\n======= Not a heading")
        #expect(document.headings.map(\.level) == [1, 2, 3, 6])
        #expect(document.headings.map(\.title) == ["Document Title", "Section One", "Sub bold", "Deep"])
        for heading in document.headings { #expect(document.substring(heading.range) == heading.title) }
        #expect(document.has(.centered, over: "Ada Example"))
        #expect(document.text.contains("======= Not a heading"))
    }

    @Test func paragraphLinesReflowAndInlineMarkupIsStyled() throws {
        let document = try asciidoc("A *bold* word, _italic_ one,\nand `mono` text; **un**constrained and snake_case_name stay sane.")
        #expect(document.lines[0] == "A bold word, italic one, and mono text; unconstrained and snake_case_name stay sane.")
        #expect(document.has(.bold, over: "bold"))
        #expect(document.has(.italic, over: "italic"))
        #expect(document.has(.code, over: "mono"))
        #expect(document.has(.bold, over: "un"))
        #expect(!document.decorations.contains { document.substring($0.range).contains("case") })
    }

    @Test func linksImagesCrossReferencesAndMathBecomeInertText() throws {
        let document = try asciidoc("See https://example.invalid/page[the page] and link:docs/a.adoc[Doc] and image:logo.png[Logo] and xref:intro[Intro] and <<anchor,Label>>, then stem:[x^2 + \\alpha] and footnote:[A note.].")
        #expect(document.lines[0] == "See the page (https://example.invalid/page) and Doc (docs/a.adoc) and Logo and Intro and Label, then x² + α and \u{00B9}.")
        #expect(document.ranges(of: .math) == ["x² + α"])
        #expect(document.text.contains("\u{00B9} A note."))
    }

    @Test func admonitionsParagraphAndBlockFormsUseLocalizedTitles() throws {
        let document = try asciidoc("NOTE: Remember this.\n\nTIP: Use that\nover two lines.\n\n[WARNING]\n====\nBlock body here.\n====\n\n[CAUTION]\nCareful\n")
        #expect(document.lines.filter { $0.hasSuffix(MarkdownRenderer.alertTitle(.note)) }.count == 1)
        #expect(document.text.contains("Remember this."))
        #expect(document.text.contains("Use that over two lines."))
        #expect(document.text.contains(MarkdownRenderer.alertTitle(.warning)))
        #expect(document.text.contains("Block body here."))
        let kinds = document.decorations.compactMap { decoration -> MarkupAlertKind? in
            if case .alertTitle(let kind) = decoration.style { return kind }
            return nil
        }
        #expect(kinds == [.note, .tip, .warning])
    }

    @Test func nestedBulletOrderedCheckAndDescriptionLists() throws {
        let document = try asciidoc("* one\n** nested\n*** deeper\n* two\n\n. first\n.. inner\n. second\n\n* [x] done\n* [ ] todo\n\nterm:: definition text\nlast term::\n  later definition\n\n3. explicit")
        #expect(document.lines.contains("\u{2022} one"))
        #expect(document.lines.contains("\u{25E6} nested"))
        #expect(document.lines.contains("\u{25AA} deeper"))
        #expect(document.lines.contains("1. first"))
        #expect(document.lines.contains("1. inner"))
        #expect(document.lines.contains("2. second"))
        #expect(document.lines.contains("\u{2611} done"))
        #expect(document.lines.contains("\u{2610} todo"))
        #expect(document.has(.definitionTerm, over: "term"))
        #expect(document.text.contains("definition text"))
        #expect(document.lines.contains("3. explicit"))
    }

    @Test func listingLiteralAndPassthroughBlocksAreCodeNotMarkup() throws {
        let document = try asciidoc("[source,swift]\n----\nlet a = *not bold*\n  indented\n----\n\n....\nliteral *text*\n....\n\n++++\n<script>alert(1)</script>\n++++\n\n [indented literal]")
        #expect(document.ranges(of: .codeBlock) == ["let a = *not bold*", "  indented", "literal *text*", "<script>alert(1)</script>", "[indented literal]"])
        #expect(document.decorations.filter { $0.style == .bold }.isEmpty)
    }

    @Test func mathBlocksQuotesAndExampleBlocks() throws {
        let document = try asciidoc("[stem]\n++++\n\\frac{a}{b}\n++++\n\n[quote]\n____\nQuoted *words* here.\n____\n\n====\nExample paragraph.\n\n* inside list\n====")
        #expect(document.ranges(of: .mathBlock) == ["a⁄b"])
        #expect(document.ranges(of: .quote).contains("Quoted words here."))
        #expect(document.text.contains("Example paragraph."))
        #expect(document.lines.contains("\u{2022} inside list"))
    }

    @Test func tablesBecomeTabSeparatedRowsWithAnOptionalHeader() throws {
        let document = try asciidoc("[options=\"header\"]\n|===\n| Name | Value\n| alpha | 1\n|===\n\n[cols=\"1,1\"]\n|===\n|a\n|b\n|c\n|d\n|===")
        #expect(document.lines.contains("Name\tValue"))
        #expect(document.lines.contains("alpha\t1"))
        #expect(document.has(.tableHeader, over: "Name\tValue"))
        #expect(document.lines.contains("a\tb"))
        #expect(document.lines.contains("c\td"))
    }

    @Test func includesImagesAndAttributesAreShownNeverFollowedOrSubstituted() throws {
        let document = try asciidoc(":project: Secret-free\n:icons: font\n\ninclude::chapter.adoc[]\nimage::diagram.png[Architecture]\n\nName is {project} here.")
        #expect(document.ranges(of: .dimmed).contains("include::chapter.adoc[]"))
        #expect(document.ranges(of: .dimmed).contains("Architecture"))
        #expect(document.ranges(of: .dimmed).contains(":project: Secret-free"))
        #expect(document.text.contains("Name is {project} here."))
    }

    @Test func commentsAreDimmed() throws {
        let document = try asciidoc("// line comment\n\n////\nblock comment\nsecond\n////\n\nVisible")
        #expect(document.ranges(of: .dimmed).contains("// line comment"))
        #expect(document.ranges(of: .dimmed).contains("block comment"))
        #expect(document.text.contains("Visible"))
    }

    @Test func blockTitlesAndRulesAndContinuations() throws {
        let document = try asciidoc(".A block title\nParagraph text.\n\n'''\n\n* item\n+\nattached paragraph")
        #expect(document.has(.bold, over: "A block title"))
        #expect(document.decorations.contains { $0.style == .rule })
        #expect(document.decorations.contains { if case .listContinuation = $0.style { true } else { false } })
    }

    @Test func unterminatedAndMalformedBlocksNeverHideTextOrHang() throws {
        for source in ["----\nunterminated listing", "====\nunterminated example\n* item", "|===\n|a |b", "////\nopen comment", "[source\nbroken attribute", "== \n=\n==x", "[[anchor]]\ntext", "stem:[unterminated", "footnote:[open", "* \n.\n::"] {
            let document = try asciidoc(source)
            #expect(document.text.utf16.count <= source.utf16.count * 2 + 100)
        }
        #expect(try asciidoc("----\nunterminated listing").text.contains("unterminated listing"))
        let nested = String(repeating: "====\n", count: 40) + "deep\n"
        _ = try asciidoc(nested)
    }

    @Test func rightToLeftParagraphsAndConcealedValues() throws {
        let document = try asciidoc("English.\n\nمرحبا بالعالم.\n\n:token: ••••\n\napi_key: ••••")
        #expect(document.ranges(of: .rightToLeft) == ["مرحبا بالعالم."])
        #expect(document.text.contains(":token: ••••"))
        #expect(document.text.contains("api_key: ••••"))
    }

    @Test func boundsReturnNil() {
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = 20
        #expect(AsciiDocRenderer.render(String(repeating: "word ", count: 30), limits: limits) == nil)
        var decorations = MarkupBuilder.Limits()
        decorations.maximumDecorations = 5
        #expect(AsciiDocRenderer.render(String(repeating: "* item\n", count: 20), limits: decorations) == nil)
    }
}

private func rst(_ source: String) throws -> SafeMarkdownDocument {
    try #require(ReStructuredTextRenderer.render(source, limits: .init()))
}

@Suite("reStructuredText rendering")
struct ReStructuredTextRendererTests {
    @Test func titleLevelsFollowTheOrderAdornmentsFirstAppear() throws {
        let document = try rst("=====\nTitle\n=====\n\nSub\n---\n\nSub two\n-------\n\nDeeper\n~~~~~~\n\nBack to sub\n-----------")
        #expect(document.headings.map(\.level) == [1, 2, 2, 3, 2])
        #expect(document.headings.map(\.title) == ["Title", "Sub", "Sub two", "Deeper", "Back to sub"])
        #expect(!document.text.contains("====") && !document.text.contains("----"))
    }

    @Test func transitionsBecomeARuleAndShortAdornmentsAreText() throws {
        let document = try rst("Above\n\n------\n\nBelow\n\n--\n\nText")
        #expect(document.decorations.filter { $0.style == .rule }.count == 1)
        #expect(document.text.contains("--"))
    }

    @Test func inlineMarkupLiteralsRolesAndHyperlinksAreInert() throws {
        let document = try rst("Plain *emph* and **strong** and ``literal *text*`` and :math:`x^2` and :kbd:`Ctrl` and `Python <https://example.invalid/py>`_ and `title ref` and :ref:`Label <target>` and snake_case.")
        #expect(document.lines[0] == "Plain emph and strong and literal *text* and x² and Ctrl and Python (https://example.invalid/py) and title ref and Label and snake_case.")
        #expect(document.has(.italic, over: "emph"))
        #expect(document.has(.bold, over: "strong"))
        #expect(document.has(.code, over: "literal *text*"))
        #expect(document.has(.math, over: "x²"))
    }

    @Test func listsNestAndEnumeratorsAndDefinitionAndFieldLists() throws {
        let document = try rst("- one\n- two\n\n  - nested\n\n#. auto\n#. auto two\n\n3. three\n\nterm\n    The definition\n    continues.\n\n:Author: Ada\n:Version: 1.0")
        #expect(document.lines.contains("\u{2022} one"))
        #expect(document.lines.contains("\u{25E6} nested"))
        #expect(document.lines.contains("1. auto"))
        #expect(document.lines.contains("2. auto two"))
        #expect(document.lines.contains("3. three"))
        #expect(document.has(.definitionTerm, over: "term"))
        #expect(document.text.contains("The definition continues."))
        #expect(document.text.contains("Author: Ada"))
        #expect(document.has(.definitionTerm, over: "Author:"))
    }

    @Test func literalBlocksQuotesLineBlocksAndDoctests() throws {
        let document = try rst("Example::\n\n    code *not emph*\n      deeper\n\nAfter paragraph.\n\n    A block quote.\n\n| line one\n| line two\n\n>>> print(1)\n1")
        #expect(document.text.contains("Example:"))
        #expect(document.ranges(of: .codeBlock) == ["code *not emph*", "  deeper", ">>> print(1)", "1"])
        #expect(document.ranges(of: .quote).contains("A block quote."))
        #expect(document.lines.contains("line one") && document.lines.contains("line two"))
    }

    @Test func admonitionsCodeAndMathDirectives() throws {
        let document = try rst(".. note:: First line\n   continues here.\n\n.. warning::\n\n   Careful now.\n\n.. code-block:: python\n   :linenos:\n\n   print('hi')\n\n.. math::\n\n   \\frac{a}{b}\n")
        #expect(document.text.contains(MarkdownRenderer.alertTitle(.note)))
        #expect(document.text.contains("First line continues here."))
        #expect(document.text.contains(MarkdownRenderer.alertTitle(.warning)))
        #expect(document.text.contains("Careful now."))
        #expect(document.ranges(of: .codeBlock) == ["print('hi')"])
        #expect(document.ranges(of: .mathBlock) == ["a⁄b"])
        #expect(!document.text.contains(":linenos:"))
    }

    @Test func includesRawImagesAndUnknownDirectivesAreShownNeverRun() throws {
        let document = try rst(".. include:: other.rst\n\n.. raw:: html\n\n   <script>alert(1)</script>\n\n.. image:: picture.png\n\n.. mystery:: argument\n\n   Body text.\n\n.. toctree::\n   :maxdepth: 2\n\n   intro\n   usage")
        let dimmed = document.ranges(of: .dimmed)
        #expect(dimmed.contains(".. include:: other.rst"))
        #expect(dimmed.contains(".. raw:: html"))
        #expect(!document.text.contains("<script>"))
        #expect(dimmed.contains("picture.png"))
        #expect(dimmed.contains(".. mystery:: argument"))
        #expect(document.text.contains("Body text."))
        #expect(dimmed.contains("intro") && dimmed.contains("usage"))
        #expect(!document.text.contains(":maxdepth:"))
    }

    @Test func tablesGridSimpleAndDirectiveForms() throws {
        let document = try rst("+------+-------+\n| Name | Value |\n+======+=======+\n| a    | 1     |\n+------+-------+\n\n=====  =====\nLeft   Right\n=====  =====\none    two\n=====  =====\n\n.. list-table::\n   :header-rows: 1\n\n   * - H1\n     - H2\n   * - c1\n     - c2\n\n.. csv-table::\n\n   x, \"y, z\"\n")
        #expect(document.lines.contains("Name\tValue"))
        #expect(document.has(.tableHeader, over: "Name\tValue"))
        #expect(document.lines.contains("a\t1"))
        #expect(document.lines.contains("Left\tRight"))
        #expect(document.lines.contains("one\ttwo"))
        #expect(document.lines.contains("H1\tH2"))
        #expect(document.lines.contains("c1\tc2"))
        #expect(document.lines.contains("x\ty, z"))
    }

    @Test func commentsTargetsSubstitutionsAndFootnotes() throws {
        let document = try rst(".. a plain comment\n\n.. _target: https://example.invalid\n\n.. |sub| replace:: replaced text\n\n.. [1] Footnote text here.\n\nBody |sub| [1]_")
        #expect(document.ranges(of: .dimmed).contains(".. a plain comment"))
        #expect(!document.text.contains("replaced text"))
        #expect(!document.text.contains("example.invalid"))
        #expect(document.text.contains("[1] Footnote text here."))
        #expect(document.text.contains("Body |sub| [1]_"))
    }

    @Test func malformedConstructsNeverHideTextOrHang() throws {
        for source in ["Title\n==", "=====\nOverline only\n----", ".. note::", "::", "* ", ".. [", "+---+\n| x", "=== ===\na b", "Term\n  ", ":field", ":field:", ".. code-block::\n"] {
            let document = try rst(source)
            #expect(document.text.utf16.count <= source.utf16.count * 2 + 100)
        }
    }

    @Test func rightToLeftAndConcealedValues() throws {
        let document = try rst("English.\n\nمرحبا بالعالم.\n\n:password: ••••")
        #expect(document.ranges(of: .rightToLeft) == ["مرحبا بالعالم."])
        #expect(document.text.contains("password: ••••"))
    }

    @Test func boundsReturnNil() {
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = 20
        #expect(ReStructuredTextRenderer.render(String(repeating: "word ", count: 30), limits: limits) == nil)
    }
}
