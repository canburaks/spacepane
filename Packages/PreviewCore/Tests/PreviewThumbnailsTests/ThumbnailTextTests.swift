import CoreGraphics
import Foundation
import Testing
import PreviewContracts
@testable import PreviewThumbnails

func metrics(_ side: CGFloat = 256, scale: CGFloat = 2) -> ThumbnailMetrics {
    ThumbnailMetrics(geometry: geometry(side, scale: scale))
}

@Suite("Thumbnail text layout")
struct ThumbnailTextTests {
    @Test func cellWidthsCoverLatinWideAndCombining() {
        #expect(ThumbnailCells.width(of: "a".unicodeScalars.first!) == 1)
        #expect(ThumbnailCells.width(of: "é".unicodeScalars.first!) == 1)
        #expect(ThumbnailCells.width(of: "漢".unicodeScalars.first!) == 2)
        #expect(ThumbnailCells.width(of: "한".unicodeScalars.first!) == 2)
        #expect(ThumbnailCells.width(of: Unicode.Scalar(0x0301)!) == 0)
        #expect(ThumbnailCells.width(of: Unicode.Scalar(0x200D)!) == 0)
        #expect(ThumbnailCells.width(of: "😀".unicodeScalars.first!) == 2)
    }

    @Test func rawLinesSplitOnEverySeparatorAndCountCRLFOnce() {
        let text = "a\nb\r\nc\rd\u{85}e\u{2028}f\u{2029}g"
        let lines = ThumbnailLines.raw(in: text, limit: 100, maxScalars: 100).map { ThumbnailCells.string($0) }
        #expect(lines == ["a", "b", "c", "d", "e", "f", "g"])
    }

    @Test func rawLinesAreBoundedByCountAndLength() {
        let many = String(repeating: "x\n", count: 10_000)
        #expect(ThumbnailLines.raw(in: many, limit: 5, maxScalars: 10).count == 5)
        let long = String(repeating: "y", count: 1_000_000)
        let lines = ThumbnailLines.raw(in: long, limit: 5, maxScalars: 40)
        #expect(lines.count == 1 && lines[0].count == 40)
        // A trailing newline does not add a phantom line.
        #expect(ThumbnailLines.raw(in: "a\n", limit: 9, maxScalars: 9).count == 1)
    }

    @Test func tabsExpandToStopsAndOtherControlsAreDropped() {
        let line = Array("a\tb\u{7}c".unicodeScalars)
        #expect(ThumbnailCells.string(ThumbnailLines.expandTabs(line)) == "a   bc")
    }

    @Test func wrappingBreaksAtSpacesAndSplitsLongWords() {
        let wrapped = ThumbnailLines.wrap(Array("hello brave new world".unicodeScalars), cells: 11, maximumPieces: 9)
        #expect(wrapped.map { ThumbnailCells.string($0) } == ["hello brave", "new world"])
        let long = ThumbnailLines.wrap(Array("abcdefghij".unicodeScalars), cells: 4, maximumPieces: 9)
        #expect(long.map { ThumbnailCells.string($0) } == ["abcd", "efgh", "ij"])
        #expect(ThumbnailLines.wrap(Array("abc def".unicodeScalars), cells: 5, maximumPieces: 1).count == 1)
        #expect(ThumbnailLines.wrap([], cells: 5, maximumPieces: 3).isEmpty)
    }

    @Test func wideScalarsCountTwoCellsWhenWrapping() {
        let wrapped = ThumbnailLines.wrap(Array("漢字漢字漢字".unicodeScalars), cells: 6, maximumPieces: 9)
        #expect(wrapped.map { ThumbnailCells.width(of: $0) }.allSatisfy { $0 <= 6 })
        #expect(wrapped.count == 2)
    }

    @Test func excerptRespectsRowAndColumnCaps() throws {
        let m = metrics()
        let text = (0..<500).map { "let value\($0) = \(String(repeating: "x", count: 200))" }.joined(separator: "\n")
        let page = try #require(ThumbnailExcerpt.page(from: text, syntax: .sourceCode, metrics: m))
        #expect(page.lines.count <= m.rows)
        for line in page.lines {
            #expect(line.indent + ThumbnailCells.width(of: line.text.unicodeScalars) <= m.columns)
        }
        #expect(page.lines[0].text.hasPrefix("let value0"))
    }

    @Test func leadingBlankLinesAreSkippedAndBlankRunsCollapse() throws {
        let page = try #require(ThumbnailExcerpt.page(from: "\n\n\nfirst\n\n\n\nsecond\n\n", syntax: .plain, metrics: metrics()))
        #expect(page.lines.map(\.text) == ["first", "", "second"])
    }

    @Test func blankOrEmptyTextHasNothingToDraw() {
        #expect(ThumbnailExcerpt.page(from: "", syntax: .plain, metrics: metrics()) == nil)
        #expect(ThumbnailExcerpt.page(from: " \n\t\n  \n", syntax: .plain, metrics: metrics()) == nil)
    }

    @Test func proseWrapsAndSourceClips() throws {
        let m = metrics()
        let sentence = Array(repeating: "word", count: 40).joined(separator: " ")
        let prose = try #require(ThumbnailExcerpt.page(from: sentence, syntax: .plain, metrics: m))
        #expect(prose.lines.count > 1)
        #expect(prose.lines.allSatisfy { ThumbnailCells.width(of: $0.text.unicodeScalars) <= m.columns })
        let source = try #require(ThumbnailExcerpt.page(from: sentence, syntax: .sourceCode, metrics: m))
        #expect(source.lines.count == 1)
    }

    @Test func textArtIsClippedNotWrapped() throws {
        let art = String(repeating: "█", count: 200)
        let page = try #require(ThumbnailExcerpt.page(from: art + "\n" + art, syntax: .plain, metrics: metrics()))
        #expect(page.lines.count == 2)
    }

    @Test func indentationIsKeptAndCapped() throws {
        let m = metrics()
        let page = try #require(ThumbnailExcerpt.page(from: "    indented\n" + String(repeating: " ", count: 40) + "deep", syntax: .sourceCode, metrics: m))
        #expect(page.lines.count == 2)
        #expect(page.lines[0].indent == 4)
        #expect(page.lines[1].indent == m.columns / 2)
        // A line indented past what is kept reads as blank rather than as misplaced text.
        let swallowed = ThumbnailExcerpt.page(from: String(repeating: " ", count: 500) + "deep", syntax: .sourceCode, metrics: m)
        #expect(swallowed == nil)
    }

    @Test func unicodeAndRightToLeftTextSurvivesAsScalars() throws {
        let page = try #require(ThumbnailExcerpt.page(from: "مرحبا بالعالم\n日本語のテキスト\ne\u{301}clair", syntax: .plain, metrics: metrics()))
        #expect(page.lines.count >= 3)
        #expect(page.lines.contains { $0.text.contains("مرحبا") })
        #expect(page.lines.contains { $0.text.contains("e\u{301}clair") })
    }

    @Test func hugeInputsAreCutOffEarly() throws {
        let huge = String(repeating: "line of text that goes on\n", count: 200_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            #expect(ThumbnailExcerpt.page(from: huge, syntax: .plain, metrics: metrics()) != nil)
        }
        #expect(elapsed < .seconds(2))
    }
}

@Suite("Thumbnail lexer")
struct ThumbnailLexerTests {
    private func runs(_ line: String, _ syntax: TextSyntax) -> [ThumbnailRun] {
        var state = ThumbnailLexer.State()
        return ThumbnailLexer(syntax: syntax).runs(in: Array(line.unicodeScalars), state: &state)
    }

    @Test func jsonKeysStringsNumbersAndLiterals() {
        let result = runs(#"  "name": "demo", "n": -12.5, "ok": true"#, .json)
        #expect(result.first { $0.text == "\"name\"" }?.tone == .key)
        #expect(result.first { $0.text == "\"demo\"" }?.tone == .string)
        #expect(result.first { $0.text == "-12.5" }?.tone == .number)
        #expect(result.first { $0.text == "true" }?.tone == .literal)
    }

    @Test func runsAlwaysReassembleTheLine() {
        let line = #"func greet(_ name: String) -> String { return "hi \(name)" } // done"#
        for syntax in [TextSyntax.sourceCode, .json, .yaml, .toml, .xml, .diff, .plain, .markdown, .strings, .ini, .environment] {
            #expect(runs(line, syntax).map(\.text).joined() == line, "\(syntax)")
        }
    }

    @Test func sourceCommentsKeywordsAndBlockComments() {
        #expect(runs("// note", .sourceCode).first?.tone == .comment)
        #expect(runs("# note", .sourceCode).first?.tone == .comment)
        #expect(runs("return value", .sourceCode).first { $0.text == "return" }?.tone == .keyword)
        var state = ThumbnailLexer.State()
        let lexer = ThumbnailLexer(syntax: .sourceCode)
        _ = lexer.runs(in: Array("/* open".unicodeScalars), state: &state)
        #expect(state.inBlockComment)
        let inside = lexer.runs(in: Array("still comment */ let".unicodeScalars), state: &state)
        #expect(inside.first?.tone == .comment)
        #expect(!state.inBlockComment)
        #expect(inside.contains { $0.text == "let" && $0.tone == .keyword })
    }

    @Test func yamlAndEnvironmentKeys() {
        #expect(runs("name: demo", .yaml).first?.tone == .key)
        #expect(runs("TOKEN_NAME=abc", .environment).first?.tone == .key)
        #expect(runs("[section]", .toml).first?.tone == .heading)
        #expect(runs("; comment", .ini).first?.tone == .comment)
    }

    @Test func diffLinesAndSubtitles() {
        #expect(runs("+added", .diff).first?.tone == .addition)
        #expect(runs("-removed", .diff).first?.tone == .deletion)
        #expect(runs("@@ -1 +1 @@", .diff).first?.tone == .heading)
        #expect(runs("00:00:01,000 --> 00:00:02,000", .subRip).first?.tone == .muted)
        #expect(runs("12", .subRip).first?.tone == .muted)
        #expect(runs("Hello there", .subRip).first?.tone == .text)
    }

    @Test func xmlTagsAndUnknownSyntaxesStayOneInk() {
        #expect(runs("<a href=\"x\">text</a>", .xml).first?.tone == .tag)
        #expect(runs("anything at all", .commaSeparated).map(\.tone) == [.text])
        #expect(runs("", .json).isEmpty)
    }

    @Test func unterminatedStringsStayInsideTheLine() {
        let result = runs(#"let s = "unterminated \"#, .sourceCode)
        #expect(result.map(\.text).joined() == #"let s = "unterminated \"#)
    }
}
