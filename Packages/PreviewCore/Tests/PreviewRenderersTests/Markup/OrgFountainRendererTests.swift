import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func org(_ source: String) throws -> SafeMarkdownDocument {
    try #require(OrgRenderer.render(source, limits: .init()))
}

@Suite("Org rendering")
struct OrgRendererTests {
    @Test func headingsKeepKeywordsAndLevelsAndFeedContents() throws {
        let document = try org("* Top\n** TODO Task :tag:\n*** DONE Finished\n**** Deep\n*not a heading\n")
        #expect(document.headings.map(\.level) == [1, 2, 3, 4])
        #expect(document.headings.map(\.title) == ["Top", "TODO Task :tag:", "DONE Finished", "Deep"])
        for heading in document.headings { #expect(document.substring(heading.range) == heading.title) }
        #expect(document.text.contains("*not a heading"))
    }

    @Test func titleAuthorAndOtherKeywords() throws {
        let document = try org("#+TITLE: The Title\n#+AUTHOR: Ada\n#+OPTIONS: toc:nil\n#+INCLUDE: \"other.org\"\n#+STARTUP: overview\n\n* Body")
        #expect(document.lines[0] == "The Title")
        #expect(document.has(.centered, over: "Ada"))
        #expect(document.ranges(of: .dimmed).contains("#+INCLUDE: \"other.org\""))
        #expect(document.ranges(of: .dimmed).contains("#+OPTIONS: toc:nil"))
        // The title is not a navigation heading.
        #expect(document.headings.map(\.title) == ["Body"])
    }

    @Test func inlineMarkupFollowsOrgBoundaryRules() throws {
        let document = try org("A *bold* and /italic/ and =verbatim= and ~code~ and +struck+ and /usr/bin/env path and 2*3*4 math and snake_case_name.")
        #expect(document.has(.bold, over: "bold"))
        #expect(document.has(.italic, over: "italic"))
        #expect(document.has(.code, over: "verbatim"))
        #expect(document.has(.code, over: "code"))
        #expect(document.has(.strikethrough, over: "struck"))
        #expect(document.text.contains("/usr/bin/env"))
        #expect(document.text.contains("2*3*4"))
        #expect(document.text.contains("snake_case_name"))
    }

    @Test func linksAreInertTextAndFootnotesNumber() throws {
        let document = try org("See [[https://example.invalid][the site]] and [[file:notes.org]] and [fn:1] and [fn:2:inline note].\n\n[fn:1] First definition.\n")
        #expect(document.lines[0] == "See the site (https://example.invalid) and file:notes.org and \u{00B9} and \u{00B2}.")
        #expect(document.text.contains("\u{00B9} First definition."))
        #expect(document.text.contains("\u{00B2} inline note"))
    }

    @Test func listsNestAndCheckboxesAndDescriptionLists() throws {
        let document = try org("- one\n  - nested\n- two\n\n1. first\n2. second\n\n- [X] done\n- [ ] open\n\n- term :: definition\n")
        #expect(document.lines.contains("\u{2022} one"))
        #expect(document.lines.contains("\u{25E6} nested"))
        #expect(document.lines.contains("1. first"))
        #expect(document.lines.contains("2. second"))
        #expect(document.lines.contains("\u{2611} done"))
        #expect(document.lines.contains("\u{2610} open"))
        #expect(document.lines.contains("\u{2022} term: definition"))
        #expect(document.has(.definitionTerm, over: "term"))
    }

    @Test func blocksSourceExampleQuoteCenterAndComment() throws {
        let document = try org("#+BEGIN_SRC python\nprint(1)  # *not bold*\n#+END_SRC\n\n#+begin_example\nraw /text/\n#+end_example\n\n#+BEGIN_QUOTE\nQuoted /words/.\n#+END_QUOTE\n\n#+BEGIN_CENTER\nCentered\n#+END_CENTER\n\n#+BEGIN_COMMENT\nhidden note\n#+END_COMMENT\n\n: fixed width")
        #expect(document.ranges(of: .codeBlock) == ["print(1)  # *not bold*", "raw /text/", "fixed width"])
        #expect(document.ranges(of: .quote).contains("Quoted words."))
        #expect(document.has(.centered, over: "Centered"))
        #expect(document.ranges(of: .dimmed).contains("hidden note"))
        #expect(document.decorations.filter { $0.style == .bold }.isEmpty)
    }

    @Test func unterminatedBlocksRunToTheEnd() throws {
        let document = try org("#+BEGIN_SRC sh\nunterminated *block*\nmore")
        #expect(document.ranges(of: .codeBlock) == ["unterminated *block*", "more"])
    }

    @Test func tablesHaveHeadersAndDrawersAndPlanningAreDimmed() throws {
        let document = try org("| Name | Value |\n|------+-------|\n| a | 1 |\n\n* Task\nSCHEDULED: <2026-01-01 Thu>\n:PROPERTIES:\n:ID: abc\n:END:\n\n# a comment\n\n-----")
        #expect(document.has(.tableHeader, over: "Name\tValue"))
        #expect(document.lines.contains("a\t1"))
        let dimmed = document.ranges(of: .dimmed)
        #expect(dimmed.contains("SCHEDULED: <2026-01-01 Thu>"))
        #expect(dimmed.contains(":PROPERTIES:") && dimmed.contains(":ID: abc") && dimmed.contains(":END:"))
        #expect(dimmed.contains("# a comment"))
        #expect(document.decorations.contains { $0.style == .rule })
    }

    @Test func mathIsApproximated() throws {
        let document = try org("Inline $x^2$ and \\(\\alpha\\) here.\n\n\\begin{equation}\n\\frac{a}{b}\n\\end{equation}\n\n\\[\ny \\leq z\n\\]")
        #expect(document.ranges(of: .math) == ["x²", "α"])
        #expect(document.ranges(of: .mathBlock) == ["a⁄b", "y ≤ z"])
    }

    @Test func malformedConstructsNeverHideTextOrHang() throws {
        for source in ["#+BEGIN_", "#+BEGIN_SRC", "[[unterminated link", "[fn:", "* ", "| |", "- ", ":PROPERTIES:\nno end", "\\begin{equation}\nopen", "#+", "=open verbatim", "*unclosed bold text"] {
            let document = try org(source)
            #expect(document.text.utf16.count <= source.utf16.count * 2 + 100)
        }
    }

    @Test func rightToLeftAndConcealedValuesAndBounds() throws {
        let document = try org("English.\n\nمرحبا بالعالم.\n\n:PASSWORD: ••••")
        #expect(document.ranges(of: .rightToLeft).first == "مرحبا بالعالم.")
        #expect(document.text.contains(":PASSWORD: ••••"))
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = 20
        #expect(OrgRenderer.render(String(repeating: "word ", count: 30), limits: limits) == nil)
    }
}

private func fountain(_ source: String) throws -> SafeMarkdownDocument {
    try #require(FountainRenderer.render(source, limits: .init()))
}

@Suite("Fountain rendering")
struct FountainRendererTests {
    private let script = """
    Title: _**THE SAMPLE**_
    Credit: Written by
    Author: Ada Example
    Draft date: 1/2/2026
    Contact:
        ada@example.invalid

    INT. WORKSHOP - DAY #1#

    Gears turn on a wooden bench.
    ADA studies a drawing.

    ADA (V.O.)
    (quietly)
    It should work.
    Really.

    BABBAGE
    You said that [[a private note]] before.

    CUT TO:

    .FLASHBACK

    > THE END <
    """

    @Test func titlePageSceneHeadingsAndContents() throws {
        let document = try fountain(script)
        #expect(document.lines[0] == "THE SAMPLE")
        #expect(document.has(.bold, over: "THE SAMPLE"))
        #expect(document.has(.centered, over: "Written by"))
        #expect(document.has(.centered, over: "Ada Example"))
        #expect(document.ranges(of: .dimmed).contains("Draft date: 1/2/2026"))
        #expect(document.headings.map(\.title) == ["INT. WORKSHOP - DAY", "FLASHBACK"])
        for heading in document.headings { #expect(document.substring(heading.range) == heading.title) }
        #expect(!document.text.contains("#1#"))
    }

    @Test func dialogueElementsGetTheirOwnLayout() throws {
        let document = try fountain(script)
        #expect(document.has(.indent(4), over: "ADA (V.O.)"))
        #expect(document.has(.bold, over: "ADA (V.O.)"))
        #expect(document.has(.indent(3), over: "(quietly)"))
        #expect(document.has(.italic, over: "(quietly)"))
        #expect(document.has(.indent(2), over: "It should work."))
        #expect(document.has(.indent(2), over: "Really."))
        #expect(document.has(.indent(4), over: "BABBAGE"))
    }

    @Test func actionKeepsItsLineBreaksAndNotesAreDimmed() throws {
        let document = try fountain(script)
        #expect(document.lines.contains("Gears turn on a wooden bench."))
        #expect(document.lines.contains("ADA studies a drawing."))
        #expect(document.ranges(of: .dimmed).contains("[a private note]"))
        #expect(document.text.contains("You said that [a private note] before."))
    }

    @Test func transitionsAndCenteredTextAlign() throws {
        let document = try fountain(script)
        #expect(document.has(.trailing, over: "CUT TO:"))
        #expect(document.has(.centered, over: "THE END"))
        let forced = try fountain("Text\n\n> FADE OUT.\n\n~Lyrics line\n\n!SHOUTING ACTION\n\n@mcCLANE\nYippee")
        #expect(forced.has(.trailing, over: "FADE OUT."))
        #expect(forced.has(.italic, over: "Lyrics line"))
        #expect(forced.text.contains("SHOUTING ACTION"))
        #expect(forced.has(.indent(4), over: "mcCLANE"))
        #expect(forced.has(.indent(2), over: "Yippee"))
    }

    @Test func sectionsSynopsesBoneyardAndPageBreaks() throws {
        let document = try fountain("# Act One\n\n= A synopsis line\n\n## Sequence\n\nINT. ROOM - NIGHT\n\n/* boneyard\nsecond line */\n\n===\n\nExt. street - day\n\nplain")
        #expect(document.headings.map(\.level) == [1, 2, 2, 2])
        #expect(document.headings.map(\.title) == ["Act One", "Sequence", "INT. ROOM - NIGHT", "Ext. street - day"])
        #expect(document.ranges(of: .dimmed).contains("/* boneyard"))
        #expect(document.ranges(of: .dimmed).contains("second line */"))
        #expect(document.decorations.contains { $0.style == .rule })
    }

    @Test func emphasisMarksStyleActionAndDialogue() throws {
        let document = try fountain("Plain *italic* and **bold** and ***both*** and _under_.")
        #expect(document.has(.italic, over: "italic"))
        #expect(document.has(.bold, over: "bold"))
        #expect(document.has(.bold, over: "both") && document.has(.italic, over: "both"))
        #expect(document.has(.italic, over: "under"))
    }

    @Test func ambiguousAndMalformedInputIsShownAsActionNeverDropped() throws {
        for source in ["ALONE", "ALONE\n", "(paren only)", "INT.", "/* open boneyard", "Title: \n\n", "> ", "#", "=", "@", "!", "~", "FOO\n  \nBAR"] {
            let document = try fountain(source)
            #expect(document.text.utf16.count <= source.utf16.count * 2 + 100)
        }
        #expect(try fountain("A lone cue\n\nBOB").text.contains("BOB"))
        #expect(try fountain("Some words: with a colon in prose.").text.contains("Some words"))
    }

    @Test func dualDialogueMarkersAreStrippedAndBlankLinesWithTwoSpacesKeepDialogueOpen() throws {
        let document = try fountain("INT. A - DAY\n\nBOB ^\nHello\n  \nStill Bob.\n\nEND")
        #expect(document.has(.indent(4), over: "BOB"))
        #expect(document.has(.indent(2), over: "Still Bob."))
        #expect(!document.text.contains("^"))
    }

    @Test func rightToLeftActionAndBounds() throws {
        let document = try fountain("INT. ROOM - DAY\n\nمرحبا بالعالم هذا نص.\n\nEnglish action.")
        #expect(document.ranges(of: .rightToLeft) == ["مرحبا بالعالم هذا نص."])
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = 20
        #expect(FountainRenderer.render(String(repeating: "word ", count: 30), limits: limits) == nil)
    }

    @Test func titlePageSecretsStayConcealed() throws {
        let document = try fountain("Title: Safe\nPassword: ••••\n\nINT. A - DAY\n\nText")
        #expect(document.text.contains("Password: ••••"))
    }
}
