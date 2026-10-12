import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func spans(_ source: String, _ syntax: TextSyntax) -> [(String, PreviewSyntaxRole)] {
    let units = source as NSString
    return (MarkupSourceTokens.tokens(in: source, syntax: syntax) ?? []).map { (units.substring(with: $0.range), $0.role) }
}

@Suite("Markup source highlighting")
struct MarkupSourceTokensTests {
    @Test func latexCommentsCommandsAndMath() {
        let tokens = spans("\\section{Intro} % note\nText $x^2$ \\textbf{b}", .latex)
        #expect(tokens.contains { $0 == ("\\section", .keyword) })
        #expect(tokens.contains { $0 == ("% note", .comment) })
        #expect(tokens.contains { $0 == ("$x^2$", .number) })
        #expect(tokens.contains { $0 == ("\\textbf", .keyword) })
    }

    @Test func bibtexTypesKeysFieldsAndValues() {
        let tokens = spans("@article{key1,\n  author = {Doe, Jane},\n  year = 2020,\n  title = \"Quoted\"\n}", .bibtex)
        #expect(tokens.contains { $0 == ("@article", .keyword) })
        #expect(tokens.contains { $0 == ("key1", .type) })
        #expect(tokens.contains { $0 == ("author", .key) })
        #expect(tokens.contains { $0 == ("{Doe, Jane}", .string) })
        #expect(tokens.contains { $0 == ("2020", .number) })
        #expect(tokens.contains { $0 == ("\"Quoted\"", .string) })
    }

    @Test func asciidocHeadingsAttributesCommentsAndDelimiters() {
        let tokens = spans("= Title\n:attr: value\n// comment\n[source,swift]\n----\ncode\n----\n", .asciidoc)
        #expect(tokens.contains { $0 == ("= Title", .heading) })
        #expect(tokens.contains { $0 == (":attr: value", .key) })
        #expect(tokens.contains { $0 == ("// comment", .comment) })
        #expect(tokens.contains { $0 == ("[source,swift]", .tag) })
        #expect(tokens.filter { $0 == ("----", .operator) }.count == 2)
    }

    @Test func restructuredTextTitlesDirectivesAndFields() {
        let tokens = spans("Title\n=====\n\n.. note:: Heads up\n\n.. a comment\n\n:field: value\n", .restructuredText)
        #expect(tokens.contains { $0 == ("Title", .heading) })
        #expect(tokens.contains { $0 == ("=====", .operator) })
        #expect(tokens.contains { $0 == (".. note:: Heads up", .keyword) })
        #expect(tokens.contains { $0 == (".. a comment", .comment) })
        #expect(tokens.contains { $0 == (":field: value", .key) })
    }

    @Test func orgHeadingsKeywordsCommentsAndDrawers() {
        let tokens = spans("* Heading\n#+TITLE: T\n# comment\n:PROPERTIES:\n#+BEGIN_SRC sh\n", .orgMode)
        #expect(tokens.contains { $0 == ("* Heading", .heading) })
        #expect(tokens.contains { $0 == ("#+TITLE: T", .keyword) })
        #expect(tokens.contains { $0 == ("# comment", .comment) })
        #expect(tokens.contains { $0 == (":PROPERTIES:", .key) })
        #expect(tokens.contains { $0 == ("#+BEGIN_SRC sh", .keyword) })
    }

    @Test func fountainScenesCuesParentheticalsAndTitleKeys() {
        let tokens = spans("Title: Sample\n\nINT. ROOM - DAY\n\nBOB\n(softly)\nHi\n\nCUT TO:\n", .fountain)
        #expect(tokens.contains { $0 == ("Title", .key) })
        #expect(tokens.contains { $0 == ("INT. ROOM - DAY", .heading) })
        #expect(tokens.contains { $0 == ("BOB", .key) })
        #expect(tokens.contains { $0 == ("(softly)", .comment) })
        #expect(tokens.contains { $0 == ("CUT TO:", .keyword) })
    }

    @Test func otherSyntaxesAreNotHandledSoTheGenericLexerStaysInCharge() {
        for syntax in [TextSyntax.plain, .json, .markdown, .sourceCode, .yaml, .xml] {
            #expect(MarkupSourceTokens.tokens(in: "text", syntax: syntax) == nil)
        }
    }

    @Test func rangesAreUTF16UnitsOfTheSourceAndStayInBounds() {
        let source = "😀 % комментарий 日本語\n\\π \\command{😀}"
        for syntax in [TextSyntax.latex, .bibtex, .asciidoc, .restructuredText, .orgMode, .fountain] {
            let tokens = MarkupSourceTokens.tokens(in: source, syntax: syntax) ?? []
            #expect(tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= source.utf16.count && $0.range.length > 0 })
        }
        #expect(spans(source, .latex).contains { $0 == ("% комментарий 日本語", .comment) })
    }

    @Test func tokenAndSizeBoundsReturnNoDecorationInsteadOfPartialOnes() {
        let many = String(repeating: "\\a ", count: 100)
        #expect(MarkupSourceTokens.tokens(in: many, syntax: .latex, maximumTokens: 10) == [])
        #expect(MarkupSourceTokens.tokens(in: many, syntax: .latex, maximumUTF16Units: 10) == [])
        #expect(MarkupSourceTokens.tokens(in: many, syntax: .latex, maximumUTF16Units: 0) == [])
    }

    @Test func malformedInputNeverTrapsOrHangs() {
        let inputs = ["\\", "$", "@", "@a{", "@a{k,\n x = {", "{{{{{{", "\"", "=", "#", ":", "[", "////", "::", "*", "\u{0}", String(repeating: "{", count: 10_000), String(repeating: "@a{", count: 3_000)]
        for syntax in [TextSyntax.latex, .bibtex, .asciidoc, .restructuredText, .orgMode, .fountain] {
            for input in inputs { _ = MarkupSourceTokens.tokens(in: input, syntax: syntax) }
        }
    }
}

@Suite("Markup builder and direction")
struct MarkupBuilderTests {
    @Test func firstStrongCharacterDecidesTheParagraphDirection() {
        #expect(MarkupDirection.isRightToLeft("مرحبا"))
        #expect(MarkupDirection.isRightToLeft("שלום"))
        #expect(MarkupDirection.isRightToLeft("• 123 — مرحبا hello"))
        #expect(MarkupDirection.isRightToLeft("\u{200F}123"))
        #expect(!MarkupDirection.isRightToLeft("hello مرحبا"))
        #expect(!MarkupDirection.isRightToLeft("123 ... "))
        #expect(!MarkupDirection.isRightToLeft(""))
        #expect(!MarkupDirection.isRightToLeft("日本語"))
        #expect(!MarkupDirection.isRightToLeft(String(repeating: "1", count: 300) + "مرحبا"))
    }

    @Test func builderBoundsAreEnforcedAndOverflowIsSticky() {
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = 10
        var builder = MarkupBuilder(limits: limits)
        builder.append("12345")
        #expect(!builder.isOverflowed)
        builder.append("1234567")
        #expect(builder.isOverflowed)
        builder.append("x")
        #expect(builder.finish() == nil)
        var decorations = MarkupBuilder.Limits()
        decorations.maximumDecorations = 2
        var second = MarkupBuilder(limits: decorations)
        second.append("abcdef")
        second.decorate(.bold, range: NSRange(location: 0, length: 1))
        second.decorate(.bold, range: NSRange(location: 1, length: 1))
        #expect(!second.isOverflowed)
        second.decorate(.bold, range: NSRange(location: 2, length: 1))
        #expect(second.isOverflowed)
    }

    @Test func invalidDecorationRangesAndHeadingsAreIgnored() {
        var builder = MarkupBuilder()
        builder.append("abc")
        builder.decorate(.bold, range: NSRange(location: 2, length: 5))
        builder.decorate(.bold, range: NSRange(location: -1, length: 1))
        builder.decorate(.bold, range: NSRange(location: 1, length: 0))
        builder.addHeading(level: 1, title: "x", range: NSRange(location: 2, length: 5))
        let document = builder.finish()
        #expect(document?.decorations.isEmpty == true)
        #expect(document?.headings.isEmpty == true)
    }

    @Test func rightToLeftRunsMergeAcrossBlankLinesButNotAcrossLeftToRightOrCodeLines() throws {
        var builder = MarkupBuilder()
        builder.append("مرحبا\n\nعالم\nHello\nمرحبا\nمرحبا code\nمرحبا")
        builder.decorate(.codeBlock, range: NSRange(location: (builder.text as NSString).range(of: "مرحبا code").location, length: 10))
        let document = try #require(builder.finish())
        let marked = document.ranges(of: .rightToLeft)
        #expect(marked == ["مرحبا\n\nعالم", "مرحبا", "مرحبا"])
    }

    @Test func footnoteNumbersUseSuperscriptDigits() {
        #expect(MarkupFootnotes.superscript(1) == "¹")
        #expect(MarkupFootnotes.superscript(10) == "¹⁰")
        #expect(MarkupFootnotes.superscript(987_654_321) == "⁹⁸⁷⁶⁵⁴³²¹")
        #expect(MarkupFootnotes.superscript(-5) == "⁰")
    }

    @Test func lineSplittingHandlesEveryTerminator() {
        #expect(MarkupLines.split("a\nb") == ["a", "b"])
        #expect(MarkupLines.split("a\r\nb\rc\u{85}d\u{2028}e\u{2029}f") == ["a", "b", "c", "d", "e", "f"])
        #expect(MarkupLines.split("a\n") == ["a", ""])
        #expect(MarkupLines.split("") == [""])
        #expect(MarkupLines.split("\r\n\r\n") == ["", "", ""])
    }
}
