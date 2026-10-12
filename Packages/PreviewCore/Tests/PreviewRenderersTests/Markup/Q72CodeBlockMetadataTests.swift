import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 explicit whole-code metadata")
struct Q72CodeBlockMetadataTests {
    private let english = Locale(identifier: "en_US")
    static let languageCases: [(String, SourceLanguageID?)] = [
        ("Swift", .swift), ("python", .python), ("javascript", .javascript), ("shell", .shell),
        ("swift{lineNumbers=true}", .swift), ("Swift\u{00A0}options", .swift), ("js", nil), ("bash", nil), ("c++", nil),
        ("unknown-language", nil), ("\u{212A}otlin", nil), ("\u{202E}swift", nil), ("swift\u{E0061}", nil),
        ("swift" + String(repeating: "x", count: 100), nil)
    ]

    @Test func fenceBodyOffsetsFollowReflowAndKeepExactSafeUTF16AndBlankLines() throws {
        let body = "\n  let e = \"e\u{301} 👩🏽‍💻\"  \n\n  last\\\n"
        let source = "Intro 😀 **bold\nwords**\n\n```Swift\n" + body + "\n```\n\nafter\nwords"
        let expected = "Intro 😀 bold words\n\n" + body + "\n\nafter words"
        let document = try #require(SafeMarkdownDocument.render(source))
        #expect(document.text.utf16.elementsEqual(expected.utf16))
        let block = try #require(document.codeBlocks.first)
        #expect(document.codeBlocks.count == 1 && block.language == .swift)
        #expect(block.range == (expected as NSString).range(of: body))
        #expect(document.substring(block.range).utf16.elementsEqual(body.utf16))
        #expect(document.ranges(of: .code) == ["  let e = \"e\u{301} 👩🏽‍💻\"  ", "  last\\"])
        #expect(document.headings.isEmpty)
    }

    @Test func convertedDocumentFlagsAndProseCannotShiftOrEnterACodeBody() throws {
        let body = "let safe = \"•••• 😀\""
        let source = "---\ntitle: Safe book\npartial: true\n---\n\nbefore\nwords\n\n```swift\n" + body + "\n```"
        let presentation = plainPresentation(source, format: .epub, syntax: .markdown, redactions: 1)
        let document = try #require(SafeMarkdownDocument.render(presentation))
        let block = try #require(document.codeBlocks.first)
        #expect(!document.text.contains("partial: true") && document.text.contains("before words"))
        #expect(block.range == (document.text as NSString).range(of: body))
        #expect(document.substring(block.range).utf16.elementsEqual(body.utf16))
        #expect(presentation.text.utf16.elementsEqual(source.utf16))
        #expect(SafePreviewModes(presentation, locale: english).markdown?.codeBlocks == document.codeBlocks)
    }

    @Test func adjacentIdenticalBodiesRemainSeparateExplicitFences() throws {
        let source = "```swift\nsame\n```\n```python\nsame\n```"
        let document = try #require(SafeMarkdownDocument.render(source))
        #expect(document.text == "same\nsame")
        try #require(document.codeBlocks.count == 2)
        #expect(document.codeBlocks[0].range == NSRange(location: 0, length: 4))
        #expect(document.codeBlocks[1].range == NSRange(location: 5, length: 4))
        #expect(document.codeBlocks[0].language == .swift && document.codeBlocks[1].language == .python)
        #expect(document.ranges(of: .code) == ["same", "same"])
    }

    @Test func emptyBodiesAddNoTargetsButPositiveBlankLFAndTrailingBlankBodiesRemainExact() throws {
        let empty = try #require(SafeMarkdownDocument.render("before\n```swift\n```\nafter"))
        #expect(empty.text == "before\nafter" && empty.codeBlocks.isEmpty)
        let oneBlank = try #require(SafeMarkdownDocument.render("```swift\n\n```"))
        #expect(oneBlank.text.isEmpty && oneBlank.codeBlocks.isEmpty)
        let blanks = try #require(SafeMarkdownDocument.render("```swift\n\n\n\n```"))
        #expect(blanks.text == "\n\n")
        let blankBody = try #require(blanks.codeBlocks.first)
        #expect(blankBody.range == NSRange(location: 0, length: 2))
        #expect(blanks.substring(blankBody.range) == "\n\n")
        let trailing = try #require(SafeMarkdownDocument.render("```\na\n\n```\nafter"))
        #expect(trailing.text == "a\n\nafter")
        let trailingBody = try #require(trailing.codeBlocks.first)
        #expect(trailing.substring(trailingBody.range) == "a\n")
    }

    @Test(arguments: languageCases)
    func hintsAreFiniteCanonicalIDsAndUnknownOrHostileLabelsAreDiscarded(info: String, expected: SourceLanguageID?) throws {
        let document = try #require(SafeMarkdownDocument.render("```" + info + "\n# inert body\n```"))
        let block = try #require(document.codeBlocks.first)
        #expect(block.language == expected)
        #expect(document.text == "# inert body" && document.headings.isEmpty)
        #expect(document.substring(block.range) == "# inert body")
    }

    @Test func unterminatedFencesRecordOnlyTheShownEOFBody() throws {
        let body = "puts(\"safe\")\n\nlast 😀"
        let document = try #require(SafeMarkdownDocument.render("before\n```ruby\n" + body))
        let block = try #require(document.codeBlocks.first)
        #expect(block.language == .ruby)
        #expect(block.range == (document.text as NSString).range(of: body))
        #expect(document.substring(block.range).utf16.elementsEqual(body.utf16))
        #expect(NSMaxRange(block.range) == document.text.utf16.count)
    }

    @Test func sharedWriterRecordsOneBodyPerCallOutsideParagraphSeparators() throws {
        var writer = MarkupBlockWriter(limits: .init())
        writer.paragraph(.init(text: "before 😀", decorations: []))
        writer.codeBlock(["", "  one", "", "e\u{301} 👩🏽‍💻", ""])
        writer.codeBlock(["second"])
        writer.paragraph(.init(text: "after", decorations: []))
        let document = try #require(writer.finish { .init(text: $0, decorations: []) })
        try #require(document.codeBlocks.count == 2)
        let bodies = document.codeBlocks.map { document.substring($0.range) }
        #expect(bodies[0].utf16.elementsEqual("\n  one\n\ne\u{301} 👩🏽‍💻\n".utf16))
        #expect(bodies[1] == "second")
        #expect(document.codeBlocks.allSatisfy { $0.language == nil })
        #expect(document.ranges(of: .codeBlock) == ["  one", "e\u{301} 👩🏽‍💻", "second"])
        let first = document.codeBlocks[0].range
        #expect(first.location == "before 😀\n\n".utf16.count)
        #expect(document.substring(NSRange(location: NSMaxRange(first), length: 1)) == "\n")
        #expect(document.codeBlocks.allSatisfy { NSMaxRange($0.range) <= document.text.utf16.count })
    }

    @Test func metadataOverflowFallsBackEvenWhenBlankBodiesHaveNoLineDecorations() {
        var limits = MarkupBuilder.Limits()
        limits.maximumDecorations = 1
        let source = "```\n\n\n```\n```\n\n\n```"
        #expect(MarkdownRenderer.render(source, limits: limits) == nil)
    }

    @Test func inertDiagramSourceHasAnExplicitBodyButDisplayMathIsNotACodeTarget() throws {
        let document = try #require(SafeMarkdownDocument.render("```mermaid\ngraph TD; A-->B;\n```\n```math\nx + y\n```"))
        let block = try #require(document.codeBlocks.first)
        #expect(document.codeBlocks.count == 1 && block.language == nil)
        #expect(document.substring(block.range) == "graph TD; A-->B;")
        #expect(document.ranges(of: .diagramSource) == ["graph TD; A-->B;"])
        #expect(document.decorations.contains { $0.style == .mathBlock })
    }

    @Test func notebookCompositionKeepsCodeOutputsAndMarkdownFenceOffsetsDistinct() throws {
        let codeBody = "  x = \"e\u{301} 😀\"\n\nlast"
        let outputBody = "out\n\n  end"
        let cells: [[String: Any]] = [
            code(codeBody, outputs: [["output_type": "stream", "name": "stdout", "text": outputBody + "\n"]]),
            ["cell_type": "markdown", "metadata": [String: Any](), "source": "prefix\nwords\n\n```swift\nlet a = 1\n```"]
        ]
        let document = try #require(SafeNotebookDocument.render(try notebook(cells, language: "python"), locale: english))
        try #require(document.codeBlocks.count == 3)
        let blocks = document.codeBlocks
        #expect(document.substring(blocks[0].range).utf16.elementsEqual(codeBody.utf16))
        #expect(document.substring(blocks[1].range) == outputBody)
        #expect(document.substring(blocks[2].range) == "let a = 1")
        #expect(blocks[0].language == .python && blocks[1].language == nil && blocks[2].language == .swift)
        #expect(blocks[0].range.location > 0 && NSMaxRange(blocks[0].range) < blocks[1].range.location)
        #expect(document.text.contains("prefix words"))
        #expect(blocks.allSatisfy { $0.range.length > 0 && NSMaxRange($0.range) <= document.text.utf16.count })
    }

    @Test func truncatedNotebookOutputsAndOmittedCellsCannotLeakOutsideShownBodies() throws {
        let output = Array(repeating: "output", count: 400).joined(separator: "\n")
        let outputCell = code("visible", outputs: [["output_type": "stream", "name": "stdout", "text": output]])
        let outputDocument = try #require(SafeNotebookDocument.render(try notebook([outputCell]), locale: english))
        try #require(outputDocument.codeBlocks.count == 2)
        let shownOutput = outputDocument.codeBlocks[1]
        #expect(outputDocument.substring(shownOutput.range) == Array(repeating: "output", count: 300).joined(separator: "\n"))
        let outputNotice = PreviewStrings.format(.notebookOutputMoreLines, arguments: [Int64(100)], locale: english)
        #expect(outputDocument.text.contains(outputNotice))
        #expect(NSIntersectionRange(shownOutput.range, (outputDocument.text as NSString).range(of: outputNotice)).length == 0)

        let cells = [code("kept 😀"), code(String(repeating: "Z", count: 270_000)), code("not reached")]
        let document = try #require(SafeNotebookDocument.render(try notebook(cells), locale: english))
        let block = try #require(document.codeBlocks.first)
        #expect(document.codeBlocks.count == 1 && document.substring(block.range) == "kept 😀")
        #expect(!document.text.contains("not reached"))
        let notice = PreviewStrings.format(.notebookTruncated, arguments: [Int64(1), Int64(3)], locale: english)
        #expect(document.text.contains(notice))
        #expect(NSIntersectionRange(block.range, (document.text as NSString).range(of: notice)).length == 0)
        #expect(NSMaxRange(block.range) <= document.text.utf16.count)
    }

    private func code(_ source: String, outputs: [[String: Any]] = []) -> [String: Any] {
        ["cell_type": "code", "metadata": [String: Any](), "execution_count": NSNull(), "source": source, "outputs": outputs]
    }

    private func notebook(_ cells: [[String: Any]], language: String? = nil) throws -> String {
        let metadata: [String: Any] = language.map { ["language_info": ["name": $0]] } ?? [:]
        let root: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": metadata, "cells": cells]
        return String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), as: UTF8.self)
    }
}
