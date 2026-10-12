import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Q70 changes only the derived reading document. Explicit structural and hard-break boundaries still own
/// their lines, while decorations and Contents selections use UTF-16 offsets of the final rendered text.
@Suite("Markdown paragraph reflow")
struct MarkdownReflowTests {
    static let hardBreaks: [(source: String, rendered: String)] = [
        ("one  \ntwo\nthree", "one\ntwo three"),
        ("one   \ntwo", "one\ntwo"),
        ("one\\\ntwo\nthree", "one\ntwo three"),
        ("one\\\\\ntwo", "one\\ two"),
        ("one\\\\\\\ntwo", "one\\\ntwo"),
        ("terminal\\", "terminal\\")
    ]

    static let blockBoundaries: [(source: String, rendered: String)] = [
        ("one\ntwo\n# Heading\nthree\nfour", "one two\nHeading\nthree four"),
        ("one\ntwo\nTitle\n===\nthree\nfour", "one two\nTitle\nthree four"),
        ("one\ntwo\n- item\n  continued\n- next\nthree\nfour",
         "one two\n• item\ncontinued\n• next\nthree four"),
        ("one\ntwo\n| A | B |\n| --- | --- |\n| 1 | 2 |\nthree\nfour",
         "one two\nA\tB\n1\t2\nthree four"),
        ("one\ntwo\n```swift\nlet a = 1  \nlet b = 2\\\n```\nthree\nfour",
         "one two\nlet a = 1  \nlet b = 2\\\nthree four"),
        ("one\ntwo\n~~~\n# inert\n~~~\nthree\nfour", "one two\n# inert\nthree four"),
        ("one\ntwo\nTerm\n: first definition\n: second definition\nthree\nfour",
         "one two\nTerm\nfirst definition\nsecond definition\nthree four")
    ]

    @Test func softBreaksAcrossEveryLogicalTerminatorBecomeOneParagraph() throws {
        let source = "one\r\ntwo\u{2028}three\rfour\u{85}five\u{2029}six"
        let document = try renderMarkdown(source)
        #expect(document.text == "one two three four five six")
        #expect(document.decorations.isEmpty && document.headings.isEmpty)
    }

    @Test func blankParagraphsAndInnerWhitespaceArePreservedWhileSoftEdgesAreJoined() throws {
        let source = "one  inner \n next\n\nthird\nfour\n\n\nlast\n"
        let document = try renderMarkdown(source)
        #expect(document.text == "one  inner next\n\nthird four\n\n\nlast\n")
    }

    @Test(arguments: hardBreaks)
    func explicitHardBreaksRemoveOnlyTheirMarkers(source: String, rendered: String) throws {
        #expect(try renderMarkdown(source).text == rendered)
    }

    @Test func emphasisCanPairAcrossSoftBreaksAndAllFinalOffsetsRemainExactUTF16() throws {
        let source = "intro 😀 **bold\n👩🏽‍💻** and e\u{301}\n\n# Next 😀"
        let expected = "intro 😀 bold 👩🏽‍💻 and e\u{301}\n\nNext 😀"
        let document = try renderMarkdown(source)
        #expect(document.text.utf16.elementsEqual(expected.utf16))
        #expect(document.has(.bold, over: "bold 👩🏽‍💻"))
        let heading = try #require(document.headings.first)
        let expectedRange = (expected as NSString).range(of: "Next 😀")
        #expect(heading.range == expectedRange && document.substring(heading.range) == heading.title)
        #expect(document.decorations.allSatisfy {
            $0.range.location >= 0 && $0.range.length > 0 && NSMaxRange($0.range) <= document.text.utf16.count
        })
    }

    @Test(arguments: blockBoundaries)
    func structuralBoundariesDoNotBecomePartOfAdjacentProse(source: String, rendered: String) throws {
        let document = try renderMarkdown(source)
        #expect(document.text == rendered)
        #expect(document.decorations.allSatisfy { NSMaxRange($0.range) <= document.text.utf16.count })
        for heading in document.headings { #expect(document.substring(heading.range) == heading.title) }
    }

    @Test func quoteParagraphsReflowWithinTheirDepthButKeepBlankHardAndStructuralBoundaries() throws {
        let source = "> one\n> **two\n> three**\n>\n> hard  \n> break\n>> deeper\n> # Heading\n> - item\n> last\n> words"
        let document = try renderMarkdown(source)
        #expect(document.text == "one two three\n\nhard\nbreak\ndeeper\nHeading\n• item\nlast words")
        #expect(document.has(.bold, over: "two three"))
        #expect(document.has(.quote, over: "one two three"))
        #expect(document.has(.quote, over: "hard\nbreak"))
        #expect(document.has(.indent(1), over: "deeper"))
        #expect(document.headings.map(\.title) == ["Heading"])
        let heading = try #require(document.headings.first)
        #expect(document.substring(heading.range) == "Heading")
        let alert = try renderMarkdown("> [!NOTE]\n> body\n> continues\n\nafter\nwords")
        #expect(alert.text.hasPrefix(MarkdownRenderer.alertGlyph(.note) + " " + MarkdownRenderer.alertTitle(.note) + "\nbody continues"))
        #expect(alert.text.hasSuffix("\n\nafter words"))
    }

    @Test func metadataMathAndFootnoteDefinitionsRemainSeparateBlocks() throws {
        let metadata = try renderMarkdown("---\ntitle: Safe\ncount: 2\n---\none\ntwo")
        #expect(metadata.text == "title: Safe\ncount: 2\n\none two")
        #expect(metadata.ranges(of: .frontMatterKey) == ["title:", "count:"])
        let math = try renderMarkdown("before\nwords\n$$\nx + y\n$$\nafter\nwords")
        #expect(math.text.hasPrefix("before words\n") && math.text.hasSuffix("\nafter words"))
        #expect(math.decorations.contains { $0.style == .mathBlock })
        let footnotes = try renderMarkdown("one\n[^n]: Note\ntwo")
        #expect(footnotes.text.hasPrefix("one\ntwo\n\n" + PreviewStrings.text(.markupFootnotes)))
        #expect(footnotes.text.hasSuffix("¹ Note"))
    }

    @Test func paragraphDirectionUsesItsFirstStrongCharacterAndCodeKeepsItsDirection() throws {
        let document = try renderMarkdown("مرحبا\nEnglish continuation\n\nEnglish\nمرحبا\n\n```\nمرحبا code\n```")
        #expect(document.text.hasPrefix("مرحبا English continuation\n\nEnglish مرحبا"))
        #expect(document.ranges(of: .rightToLeft) == ["مرحبا English continuation"])
        let code = try #require(document.decorations.first { $0.style == .code })
        #expect(document.decorations.filter { $0.style == .rightToLeft }.allSatisfy {
            NSIntersectionRange($0.range, code.range).length == 0
        })
    }

    @Test func concealmentCharactersAndExactSafeSourceRemainIntact() throws {
        let source = "e\u{301} ••••\nsecond 😀"
        let presentation = plainPresentation(source, format: .markdown, syntax: .markdown, redactions: 1)
        let document = try #require(SafeMarkdownDocument.render(presentation))
        #expect(document.text.utf16.elementsEqual("e\u{301} •••• second 😀".utf16))
        #expect(presentation.text.utf16.elementsEqual(source.utf16))
        #expect(presentation.redactionCount == 1)
    }

    @Test func reflowRetainsInputOutputDecorationAndSourceLineBounds() {
        #expect(SafeMarkdownDocument.render("abc\ndef", maximumUTF16Units: 6) == nil)
        #expect(SafeMarkdownDocument.render(String(repeating: "line\n", count: 20_001)) == nil)
        var limits = MarkupBuilder.Limits()
        limits.maximumDecorations = 2
        #expect(MarkdownRenderer.render("**a**\n**b**\n**c**", limits: limits) == nil)
        limits.maximumUTF16Units = 10
        #expect(MarkdownRenderer.render("***", limits: limits) == nil, "A rule may expand beyond its source size")
    }

    @Test func anAlreadyCancelledTaskDoesNotBuildAReadingDocument() async {
        let source = String(repeating: "ordinary paragraph line\n", count: 1_000)
        let rendered = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return SafeMarkdownDocument.render(source)
        }.value
        #expect(rendered == nil)
    }

    @Test func notebookMarkdownCellsDelegateReflowAndCodeCellsKeepTheirExactLines() throws {
        let cells: [[String: Any]] = [
            ["cell_type": "markdown", "metadata": [String: Any](), "source": ["one\n", "two"]],
            ["cell_type": "markdown", "metadata": [String: Any](), "source": "three\nfour"],
            ["cell_type": "code", "metadata": [String: Any](), "source": "a = 1  \nb = 2\\", "execution_count": 1, "outputs": []]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["nbformat": 4, "nbformat_minor": 5,
                                                              "metadata": [String: Any](), "cells": cells])
        let json = String(decoding: data, as: UTF8.self)
        let document = try #require(SafeNotebookDocument.render(json, locale: Locale(identifier: "en_US")))
        #expect(document.text.contains("one two\n\nthree four"))
        #expect(document.text.contains("a = 1  \nb = 2\\"))
        #expect(document.has(.code, over: "a = 1  ") && document.has(.code, over: "b = 2\\"))
        #expect(document.decorations.allSatisfy { NSMaxRange($0.range) <= document.text.utf16.count })
    }
}
