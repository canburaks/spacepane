import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Shared helpers for the markup renderer tests.
func renderMarkdown(_ source: String) throws -> SafeMarkdownDocument {
    try #require(SafeMarkdownDocument.render(source))
}

/// The marker a rendered Markdown image draws, in the language the renderer used.
func imageMarker(_ description: String) -> String {
    PreviewStrings.format(.documentImageMarker, arguments: [description])
}

extension SafeMarkdownDocument {
    func substring(_ range: NSRange) -> String { (text as NSString).substring(with: range) }
    func ranges(of style: MarkdownDecoration.Style) -> [String] {
        decorations.filter { $0.style == style }.map { substring($0.range) }
    }
    func has(_ style: MarkdownDecoration.Style, over expected: String) -> Bool { ranges(of: style).contains(expected) }
    var lines: [String] { text.components(separatedBy: "\n") }
}

@Suite("Markdown rendering: blocks")
struct MarkdownBlockTests {
    @Test func atxAndSetextHeadingsAreCollectedWithLevelsTitlesAndRanges() throws {
        let document = try renderMarkdown("# One\n\nText\n\nTwo\n===\n\nThree\n---\n\n###### Six #\n")
        #expect(document.headings.map(\.level) == [1, 1, 2, 6])
        #expect(document.headings.map(\.title) == ["One", "Two", "Three", "Six"])
        for heading in document.headings {
            #expect(document.substring(heading.range) == heading.title)
            #expect(document.decorations.contains { $0.style == .heading(heading.level) && NSIntersectionRange($0.range, heading.range).length == heading.range.length })
        }
        // Underlines are syntax, not output lines.
        #expect(!document.text.contains("==="))
        #expect(!document.text.contains("---"))
    }

    @Test func headingTitlesRenderInlineMarkupAndNeedASpaceAfterTheHashes() throws {
        let document = try renderMarkdown("## **Bold** title\n#NoSpace\n####### seven")
        #expect(document.headings.map(\.title) == ["Bold title"])
        #expect(document.text.contains("#NoSpace"))
        #expect(document.text.contains("####### seven"))
    }

    @Test func orderedBulletAndNestedListsKeepNumberingDepthAndHangingIndentation() throws {
        let document = try renderMarkdown("1. First\n2. Second\n   - nested bullet\n   - another\n     - deeper\n3. Third\n\n* top\n+ plus")
        #expect(document.lines.prefix(7) == ["1. First", "2. Second", "\u{25E6} nested bullet", "\u{25E6} another", "\u{25AA} deeper", "3. Third", ""])
        let depths = document.decorations.compactMap { decoration -> Int? in
            if case .listItem(let depth, _) = decoration.style { return depth }
            return nil
        }
        #expect(depths == [0, 0, 1, 1, 2, 0, 0, 0])
        #expect(document.decorations.contains { $0.style == .listItem(depth: 0, markerLength: 3) })
    }

    @Test func listContinuationLinesAlignWithTheirItemText() throws {
        let document = try renderMarkdown("- item\n  continued text\n- next")
        #expect(document.lines == ["\u{2022} item", "continued text", "\u{2022} next"])
        #expect(document.decorations.contains { $0.style == .listContinuation(depth: 0, markerLength: 2) })
    }

    @Test func taskListsUseBallotBoxGlyphs() throws {
        let document = try renderMarkdown("- [ ] open task\n- [x] done task\n- [X] upper\n- [y] not a task\n- [ ]no space")
        #expect(document.lines == ["\u{2610} open task", "\u{2611} done task", "\u{2611} upper", "\u{2022} [y] not a task", "\u{2022} [ ]no space"])
        #expect(document.decorations.contains { $0.style == .taskMarker(done: true) })
        #expect(document.decorations.contains { $0.style == .taskMarker(done: false) })
    }

    @Test func thematicBreaksBecomeARuleLine() throws {
        let document = try renderMarkdown("above\n\n***\n\n___\n\n- - -\n")
        #expect(document.decorations.filter { $0.style == .rule }.count == 3)
        #expect(!document.text.contains("***"))
        #expect(document.text.contains(String(repeating: "\u{2500}", count: 24)))
    }

    @Test func quotesNestAndKeepTheirText() throws {
        let document = try renderMarkdown("> quoted\n>> deeper\n> - item\n>no space")
        #expect(document.lines == ["quoted", "deeper", "\u{2022} item", "no space"])
        #expect(document.ranges(of: .quote) == ["quoted", "deeper", "\u{2022} item", "no space"])
        #expect(document.has(.indent(1), over: "deeper"))
    }

    @Test(arguments: [("NOTE", MarkupAlertKind.note), ("tip", .tip), ("Important", .important), ("WARNING", .warning), ("CAUTION", .caution)])
    func githubAlertsGetALocalizedTitleAndKindDecoration(marker: String, kind: MarkupAlertKind) throws {
        let document = try renderMarkdown("> [!\(marker)]\n> Body text")
        let title = MarkdownRenderer.alertTitle(kind)
        #expect(document.lines[0].hasSuffix(title))
        #expect(document.lines[0].hasPrefix(MarkdownRenderer.alertGlyph(kind)))
        #expect(document.lines[1] == "Body text")
        #expect(document.decorations.contains { $0.style == .alertTitle(kind) })
        #expect(!document.text.contains("[!"))
    }

    @Test func unknownAlertKindsAndTrailingTextStayLiteralQuotes() throws {
        let document = try renderMarkdown("> [!OTHER]\n> text\n\n> [!NOTE] inline text")
        #expect(document.text.contains("[!OTHER]"))
        #expect(document.text.contains("[!NOTE] inline text"))
        #expect(!document.decorations.contains { if case .alertTitle = $0.style { true } else { false } })
    }

    @Test func pipeTablesRenderRowsAsTabbedCellsWithoutRequiringOuterPipes() throws {
        let document = try renderMarkdown("| A | B |\n| --- | :-: |\n| one | two |\n\nx | y\n-|-\n1 | 2\n| open | row")
        #expect(document.lines[0] == "A\tB")
        #expect(document.lines[1] == "one\ttwo")
        #expect(document.has(.tableHeader, over: "A\tB"))
        #expect(document.text.contains("x\ty"))
        #expect(document.text.contains("1\t2"))
        #expect(document.text.contains("open\trow"))
        #expect(!document.text.contains("---"))
    }

    @Test func fencedCodeKeepsLinesAndDecoratesThemAsCode() throws {
        let document = try renderMarkdown("```swift\nlet x = 1\n\n  indented\n```\nafter")
        #expect(document.lines == ["let x = 1", "", "  indented", "after"])
        #expect(document.ranges(of: .code) == ["let x = 1", "  indented"])
    }

    @Test func mermaidFencesStayCodeButCarryTheDiagramSourceDecoration() throws {
        let document = try renderMarkdown("```mermaid\ngraph TD; A-->B;\n```\n```swift\nlet y = 2\n```")
        #expect(document.ranges(of: .diagramSource) == ["graph TD; A-->B;"])
        #expect(document.ranges(of: .code) == ["let y = 2"])
        #expect(document.text.contains("graph TD; A-->B;"))
    }

    @Test func htmlLinksAndImagesStayInertText() throws {
        let document = try renderMarkdown("<script>alert(1)</script> [site](https://example.invalid/a) ![logo](https://example.invalid/logo.png) <https://auto.invalid>")
        // A link keeps its target as text; an image is one localized marker and its destination is never shown.
        #expect(document.text == "<script>alert(1)</script> site (https://example.invalid/a) \(imageMarker("logo")) <https://auto.invalid>")
    }

    @Test func tildeAndBacktickFencesDoNotCloseEachOtherAndIgnoreLaterMarkup() throws {
        let document = try renderMarkdown("~~~\n```\n# not a heading\n~~~\n# Real")
        #expect(document.text.contains("# not a heading"))
        #expect(document.headings.map(\.title) == ["Real"])
    }

    @Test func definitionListsRenderTermsAndIndentedDefinitions() throws {
        let document = try renderMarkdown("Term *one*\n: First definition\n: Second `code` definition\n\nPlain paragraph\n: not at the start\n\n: orphan colon line")
        #expect(document.lines[0] == "Term one")
        #expect(document.has(.definitionTerm, over: "Term one"))
        #expect(document.has(.indent(1), over: "First definition"))
        #expect(document.has(.indent(1), over: "Second code definition"))
        #expect(document.has(.code, over: "code"))
        #expect(document.text.contains(": orphan colon line"))
    }

    @Test func crlfAndUnicodeLineSeparatorsSplitOnceEach() throws {
        let document = try renderMarkdown("one\r\ntwo\u{2028}three\rfour\u{85}five")
        #expect(document.lines == ["one two three four five"])
    }

    @Test func decorationRangesAreUTF16UnitsOfTheRenderedText() throws {
        let document = try renderMarkdown("😀 **bold 👩🏽‍💻** and `code` 😀")
        let length = document.text.utf16.count
        #expect(document.decorations.allSatisfy { NSMaxRange($0.range) <= length && $0.range.length > 0 })
        #expect(document.has(.bold, over: "bold 👩🏽‍💻"))
        #expect(document.has(.code, over: "code"))
    }
}

@Suite("Markdown rendering: inline")
struct MarkdownInlineTests {
    @Test func emphasisStrongAndStrikethroughNestAndPair() throws {
        let document = try renderMarkdown("*one* **two** ***three*** ~~gone~~ _four_ __five__")
        #expect(document.text == "one two three gone four five")
        #expect(document.has(.italic, over: "one"))
        #expect(document.has(.bold, over: "two"))
        #expect(document.has(.bold, over: "three") && document.has(.italic, over: "three"))
        #expect(document.has(.strikethrough, over: "gone"))
        #expect(document.has(.italic, over: "four"))
        #expect(document.has(.bold, over: "five"))
    }

    @Test func unmatchedDelimitersAndIntrawordUnderscoresStayLiteral() throws {
        let document = try renderMarkdown("2 * 3 * 4 and snake_case_name and a **b and ~one~ and ~~~three~~~")
        #expect(document.text == "2 * 3 * 4 and snake_case_name and a **b and ~one~ and ~~~three~~~")
        #expect(document.decorations.isEmpty)
    }

    @Test func backslashEscapesOnlyAsciiPunctuation() throws {
        let document = try renderMarkdown(#"\*not italic\* and C:\Users and \$5"#)
        #expect(document.text == #"*not italic* and C:\Users and $5"#)
    }

    @Test func codeSpansDoNotInterpretMarkup() throws {
        let document = try renderMarkdown("`**not bold**` and ``a ` b`` and `unterminated")
        #expect(document.text == "**not bold** and a ` b and `unterminated")
        #expect(document.has(.code, over: "**not bold**"))
        #expect(!document.decorations.contains { $0.style == .bold })
    }

    @Test func footnoteReferencesNumberInOrderAndBuildAFootnotesSection() throws {
        let source = "Claim[^b] and more[^a] again[^b] missing[^zzz]\n\n[^a]: Note A\n    continued\n[^b]: Note **B**\n[^unused]: Never cited\n"
        let document = try renderMarkdown(source)
        #expect(document.lines[0] == "Claim\u{00B9} and more\u{00B2} again\u{00B9} missing[^zzz]")
        let title = PreviewStrings.text(.markupFootnotes)
        #expect(document.lines.contains(title))
        #expect(document.text.contains("\u{00B9} Note B"))
        #expect(document.text.contains("\u{00B2} Note A continued"))
        #expect(document.text.contains("\u{00B3} Never cited"))
        #expect(document.headings.last?.title == title)
        #expect(document.ranges(of: .footnoteMark) == ["\u{00B9}", "\u{00B2}", "\u{00B9}"])
        #expect(!document.text.contains("[^a]:"))
    }

    @Test func footnoteDefinitionsInsideFencesAreCodeNotNotes() throws {
        let document = try renderMarkdown("```\n[^a]: literal\n```\ntext[^a]")
        #expect(document.text.contains("[^a]: literal"))
        #expect(document.text.hasSuffix("text[^a]"))
        #expect(document.headings.isEmpty)
    }

    @Test func manyDefinitionsAreBoundedNotUnbounded() throws {
        var source = ""
        for index in 0..<1_200 { source += "[^n\(index)]: note \(index)\n" }
        let document = try renderMarkdown(source)
        let numbered = document.lines.filter { $0.first.map { "⁰¹²³⁴⁵⁶⁷⁸⁹".contains($0) } == true }
        #expect(numbered.count == MarkupFootnotes.maximumCount)
        // Definitions past the bound are ordinary text, never silently dropped.
        #expect(document.text.contains("[^n1100]: note 1100"))
    }
}

@Suite("Markdown rendering: front matter")
struct MarkdownFrontMatterTests {
    @Test func yamlFrontMatterBecomesACompactKeyValueBlock() throws {
        let source = "---\ntitle: \"Quarterly report\"\ntags: [a, b]\nauthors:\n  - Ada\n  - Grace\nsummary: >\n  long\n  text\n# comment\n---\n# Body\n"
        let document = try renderMarkdown(source)
        #expect(document.lines.prefix(5) == ["title: Quarterly report", "tags: a, b", "authors: Ada, Grace", "summary: long text", ""])
        #expect(document.ranges(of: .frontMatterKey) == ["title:", "tags:", "authors:", "summary:"])
        #expect(document.decorations.contains { $0.style == .frontMatterBlock })
        #expect(document.headings.map(\.title) == ["Body"])
        #expect(!document.text.contains("---"))
    }

    @Test func tomlFrontMatterReadsTopLevelKeysAndMultilineArrays() throws {
        let document = try renderMarkdown("+++\ntitle = \"Plan\"\ndraft = false\ntags = [\n  \"x\",\n  \"y\"\n]\n[extra]\n+++\nBody")
        #expect(document.lines.prefix(5) == ["title: Plan", "draft: false", "tags: x, y", "[extra]", ""])
        #expect(document.text.hasSuffix("Body"))
    }

    @Test func unterminatedFrontMatterAndProseBetweenBreaksAreNotMetadata() throws {
        let unterminated = try renderMarkdown("---\ntitle: never closed\nBody text")
        #expect(unterminated.decorations.filter { $0.style == .frontMatterBlock }.isEmpty)
        #expect(unterminated.text.contains("title: never closed"))
        let prose = try renderMarkdown("---\njust some words\n---\nafter")
        #expect(prose.decorations.filter { $0.style == .frontMatterBlock }.isEmpty)
        #expect(prose.text.contains("just some words"))
    }

    @Test func frontMatterOnlyAppliesAtTheStartOfTheDocument() throws {
        let document = try renderMarkdown("Intro\n\n---\ntitle: late\n---\n")
        #expect(document.decorations.filter { $0.style == .frontMatterBlock }.isEmpty)
    }

    @Test func concealedValuesRemainConcealedInTheKeyValueBlock() throws {
        let document = try renderMarkdown("---\napi_key: ••••\ntitle: Safe\n---\n")
        #expect(document.text.contains("api_key: ••••"))
        #expect(!document.text.contains("synthetic"))
    }
}

@Suite("Markdown rendering: math")
struct MarkdownMathTests {
    @Test func inlineMathIsApproximatedAndStyledDistinctly() throws {
        let document = try renderMarkdown("Euler: $e^{i\\pi} + 1 = 0$ and $x^2 + \\alpha_1$ and $a\\leq b$")
        #expect(document.text == "Euler: e^(iπ) + 1 = 0 and x² + α₁ and a ≤ b")
        #expect(document.ranges(of: .math) == ["e^(iπ) + 1 = 0", "x² + α₁", "a ≤ b"])
    }

    @Test func dollarsThatAreNotMathStayText() throws {
        let document = try renderMarkdown("It costs $5 and $6 today, or $ 7 $ spaced, or \\$8 escaped")
        #expect(document.text == "It costs $5 and $6 today, or $ 7 $ spaced, or $8 escaped")
        #expect(document.decorations.isEmpty)
    }

    @Test func displayMathBlocksAndMathFencesUseTheBlockStyle() throws {
        let document = try renderMarkdown("$$\n\\frac{a}{b} = \\sqrt{x}\n$$\n\n```math\n\\sum_{i=1}^{n} i\n```\n\n$$ \\alpha + \\beta $$\n")
        #expect(document.ranges(of: .mathBlock) == ["a⁄b = √x", "∑ᵢ₌₁ⁿ i", "α + β"])
        #expect(!document.text.contains("$$"))
        #expect(!document.text.contains("math"))
    }

    @Test func unterminatedDisplayMathIsShownAsWrittenText() throws {
        let document = try renderMarkdown("$$\n\\alpha\nno closing")
        #expect(document.text.contains("$$"))
        #expect(document.decorations.filter { $0.style == .mathBlock }.isEmpty)
        #expect(document.text.contains("no closing"))
    }

    @Test func mathNeverTriggersLinkOrResourceBehavior() throws {
        let document = try renderMarkdown("$\\href{https://example.invalid}{x}$ and $\\includegraphics{secret.png}$")
        #expect(document.text.contains("\\href{https://example.invalid}{x}") || document.text.contains("\\href"))
        #expect(document.text.contains("\\includegraphics"))
    }
}

@Suite("Markdown rendering: direction and bounds")
struct MarkdownDirectionAndBoundsTests {
    @Test func rightToLeftParagraphsAreTaggedAndLeftToRightOnesAreNot() throws {
        let document = try renderMarkdown("English paragraph\n\nمرحبا بالعالم هذا نص عربي\n\n- שלום עולם\n\n```\nمرحبا code\n```\n\nباللغة 123")
        let marked = document.ranges(of: .rightToLeft)
        #expect(marked.count >= 2)
        let joined = marked.joined(separator: "|")
        #expect(joined.contains("مرحبا بالعالم"))
        #expect(joined.contains("שלום עולם"))
        #expect(joined.contains("باللغة 123"))
        #expect(!joined.contains("English"))
        // Code blocks keep their natural left-to-right layout even when they contain Arabic.
        #expect(!marked.contains { $0.contains("code") })
    }

    @Test func mixedParagraphsFollowTheirFirstStrongCharacter() throws {
        let document = try renderMarkdown("123 ... English first, ثم عربي\n\nعربي أولا then English")
        #expect(document.ranges(of: .rightToLeft) == ["عربي أولا then English"])
    }

    @Test func oversizedInputAndOutputReturnNil() {
        #expect(SafeMarkdownDocument.render(String(repeating: "x", count: 65), maximumUTF16Units: 64) == nil)
        // A rule expands to 24 characters, so tiny sources can exceed a small output bound.
        #expect(SafeMarkdownDocument.render(String(repeating: "---\n", count: 1), maximumUTF16Units: 10) == nil)
        #expect(SafeMarkdownDocument.render("x", maximumUTF16Units: 0) == nil)
    }

    @Test func tooManyLinesAndTooManyDecorationsReturnNil() {
        #expect(SafeMarkdownDocument.render(String(repeating: "a\n", count: 20_001)) == nil)
        let bold = String(repeating: "**a** ", count: 25)
        let many = Array(repeating: bold, count: 1_000).joined(separator: "\n") // 25,000 decorations
        #expect(many.utf16.count < 262_144)
        #expect(SafeMarkdownDocument.render(many) == nil)
    }

    @Test func headingCollectionIsBoundedWithoutDroppingTheDocument() throws {
        let source = (0..<5_100).map { "# H\($0)" }.joined(separator: "\n")
        let document = try renderMarkdown(source)
        #expect(document.headings.count == 5_000)
        #expect(document.headings.last?.title == "H4999")
    }

    @Test func pathologicalDelimiterRunsStayLinear() throws {
        let line = String(repeating: "*a ", count: 3_000)
        let started = ContinuousClock.now
        let document = try renderMarkdown(line)
        #expect(document.text.contains("*a"))
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func alternatingDelimitersAndHugeRunCountsStayFastAndBounded() throws {
        let started = ContinuousClock.now
        let alternating = String(repeating: "*a _b ", count: 5_000) + "*"
        _ = SafeMarkdownDocument.render(alternating)
        let closers = String(repeating: "a* ", count: 8_000)
        _ = SafeMarkdownDocument.render(closers)
        // More pairs on one line than the decoration bound allows is declined, not truncated.
        #expect(SafeMarkdownDocument.render(String(repeating: "*a* ", count: 21_000)) == nil)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func emptyAndWhitespaceOnlyInputRendersAnEmptyDocument() throws {
        #expect(try renderMarkdown("").text == "")
        #expect(try renderMarkdown("  \n \t\n").headings.isEmpty)
    }
}

@Suite("Markdown rendering: images")
struct MarkdownImageTests {
    @Test func anImageIsOneDimmedLocalizedMarkerCarryingItsDescription() throws {
        let document = try renderMarkdown("Before ![A diagram of the plan](assets/plan.png) after")
        let marker = imageMarker("A diagram of the plan")
        #expect(document.text == "Before \(marker) after")
        #expect(document.has(.dimmed, over: marker))
        #expect(!document.text.contains("plan.png") && !document.text.contains("assets"))
        // The description is substituted exactly as the document gives it.
        #expect(marker.contains("A diagram of the plan"))
    }

    @Test func theDescriptionIsPlainTextWithItsEmphasisMarkersResolved() throws {
        let document = try renderMarkdown("![A *cat* and `code` and **bold**](pic.png)")
        #expect(document.text == imageMarker("A cat and code and bold"))
        #expect(document.ranges(of: .dimmed) == [imageMarker("A cat and code and bold")])
        #expect(!document.text.contains("*") && !document.text.contains("`"))
    }

    @Test func aLinkStillShowsItsTargetAndAnImageInsideALinkKeepsBoth() throws {
        let document = try renderMarkdown("[![badge](https://img.example/b.svg)](https://example.invalid/home)")
        #expect(document.text == "\(imageMarker("badge")) (https://example.invalid/home)")
        #expect(document.omitted == OmittedResources(remoteImages: 1))
    }

    @Test func anImageWithoutADescriptionDrawsNoMarkerButIsStillCounted() throws {
        let document = try renderMarkdown("Text ![](a.png) ![ ](b.png) end")
        #expect(document.text == "Text   end")
        #expect(document.omitted == OmittedResources(localImages: 2))
    }

    @Test func destinationsAreClassifiedFromTheirSpellingAndNothingElseIsKept() throws {
        let cases: [(destination: String, expected: OmittedResources)] = [
            ("https://example.invalid/a.png", .init(remoteImages: 1)),
            ("HTTP://EXAMPLE.INVALID/A.PNG", .init(remoteImages: 1)),
            ("//cdn.example.invalid/a.png", .init(remoteImages: 1)),
            ("ftp://example.invalid/a.png", .init(remoteImages: 1)),
            ("data:image/png;base64,iVBORw0KGgo=", .init()),
            ("DATA:image/gif;base64,R0lGODlh", .init()),
            ("file:///Users/someone/a.png", .init(localImages: 1)),
            ("a.png", .init(localImages: 1)),
            ("./images/a.png", .init(localImages: 1)),
            ("../a.png", .init(localImages: 1)),
            ("/absolute/a.png", .init(localImages: 1)),
            ("images/a:b.png", .init(localImages: 1)),
            ("C:/pictures/a.png", .init(localImages: 1)),
            ("<my picture.png>", .init(localImages: 1)),
            ("a.png \"A title\"", .init(localImages: 1)),
            ("", .init())
        ]
        for (destination, expected) in cases {
            let document = try renderMarkdown("![alt](\(destination))")
            #expect(document.omitted == expected, "\(destination)")
            // The destination never reaches the text, in any form.
            #expect(document.text == imageMarker("alt"), "\(destination)")
        }
    }

    @Test func countsAddUpAcrossBlocksListsTablesQuotesAndFootnotes() throws {
        let source = "# ![h](a.png)\n\n![p](https://x.invalid/b.png)\n\n- ![l](c.png)\n\n| A |\n| - |\n| ![t](d.png) |\n\n> ![q](e.png)\n\nNote[^1]\n\n[^1]: ![n](https://x.invalid/f.png)\n"
        let document = try renderMarkdown(source)
        #expect(document.omitted == OmittedResources(remoteImages: 2, localImages: 4))
    }

    @Test func linksCodeFencesMathAndHTMLAreNeverCounted() throws {
        let source = "[site](https://example.invalid/a.png)\n\n`![a](b.png)`\n\n```\n![a](b.png)\n```\n\n$![a](b.png)$\n\n<img src=\"a.png\">\n\n\\![a](b.png)\n"
        let document = try renderMarkdown(source)
        #expect(document.omitted.isEmpty)
    }

    @Test func classificationStaysInsideTheExistingScanLimits() throws {
        let limit = MarkdownInline.maximumSpanScan
        // Within the scan a long destination is classified from its first characters only.
        let longPath = String(repeating: "d/", count: (limit - 200) / 2) + "a.png"
        #expect(try renderMarkdown("![alt](\(longPath))").omitted == OmittedResources(localImages: 1))
        let longRemote = "https://example.invalid/" + String(repeating: "p", count: limit - 300)
        #expect(try renderMarkdown("![alt](\(longRemote))").omitted == OmittedResources(remoteImages: 1))
        // Beyond the scan the image is not recognized at all: literal text, nothing counted, nothing widened.
        let tooLong = "![alt](" + String(repeating: "x", count: limit + 10) + ")"
        let literal = try renderMarkdown(tooLong)
        #expect(literal.omitted.isEmpty)
        #expect(literal.text == tooLong)
        let longDescription = "![" + String(repeating: "a", count: limit + 10) + "](b.png)"
        let undescribed = try renderMarkdown(longDescription)
        #expect(undescribed.omitted.isEmpty)
        #expect(undescribed.text == longDescription)
    }

    @Test func aHostileDestinationNeverEntersTheMarkerOrTheCounts() throws {
        let document = try renderMarkdown("![ok](javascript:alert(1)) ![ok2](https://u:p@example.invalid/a.png?token=abc)")
        #expect(document.text == "\(imageMarker("ok")) \(imageMarker("ok2"))")
        #expect(document.omitted == OmittedResources(remoteImages: 2))
    }

    @Test func manyImagesStayWithinTheDecorationBound() throws {
        let line = String(repeating: "![a](b.png) ", count: 21)
        let many = Array(repeating: line, count: 1_000).joined(separator: "\n") // 21,000 markers
        #expect(many.utf16.count < 262_144)
        // Each marker is a decoration, so the existing bound declines the document instead of truncating it.
        #expect(SafeMarkdownDocument.render(many) == nil)
        let some = Array(repeating: line, count: 10).joined(separator: "\n")
        #expect(try renderMarkdown(some).omitted == OmittedResources(localImages: 210))
    }
}
