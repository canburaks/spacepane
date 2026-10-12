import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func cues(_ text: String, _ syntax: TextSyntax, expected: Int? = nil) -> [SafeOutlineNode]? {
    SafeSubtitleCues.nodes(text, syntax: syntax, locale: Locale(identifier: "en"), expectedCueCount: expected)
}

@Suite("Cue list derived from concealed caption text")
struct SafeSubtitleCuesTests {
    @Test func subRipRowsKeepExactTimestampsIdentifiersAndJoinedLines() throws {
        let source = "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello\r\nthere\r\n\r\n2\r\n00:00:05.500 --> 01:00:08,500 X1:1\r\n\r\n\r\n3\r\n00:00:09,000 --> 00:00:10,000\r\n<i>日本語 😀</i> {\\an8}\r\n"
        let nodes = try #require(cues(source, .subRip, expected: 3))
        #expect(nodes.map(\.id) == [0, 1, 2])
        #expect(nodes.map(\.name) == ["1: 00:00:01,000 \u{2192} 00:00:04,000", "2: 00:00:05.500 \u{2192} 01:00:08,500",
                                      "3: 00:00:09,000 \u{2192} 00:00:10,000"])
        #expect(nodes.map(\.value) == ["Hello / there", "", "<i>日本語 😀</i> {\\an8}"])
        #expect(nodes.allSatisfy { $0.children.isEmpty && !$0.isIssue && !$0.isDuplicateKey })
    }

    @Test func subRipWithoutIndexOmitsThePrefix() throws {
        let nodes = try #require(cues("00:00:01,000 --> 00:00:02,000\nA\n\n  7  \n00:00:03,000-->00:00:04,000\nB", .subRip))
        #expect(nodes.map(\.name) == ["00:00:01,000 \u{2192} 00:00:02,000", "7: 00:00:03,000 \u{2192} 00:00:04,000"])
        #expect(nodes.map(\.value) == ["A", "B"])
    }

    @Test func webVTTRowsUseIdentifiersAndIgnoreHeaderNoteStyleAndRegionBlocks() throws {
        let source = "WEBVTT - demo\nKind: captions\n\nSTYLE\n::cue { color: red }\n\nREGION\nid:fred\n\nNOTE a comment\n\n"
            + "00:01.000 --> 00:04.000 align:start\nFirst <v Roger>cue</v>\n\nintro cue\n00:00:05.000 --> 100:00:08.500\nSecond\nlines\n\nNOTE\nbetween\n\n00:09.000 --> 00:10.000\n"
        let nodes = try #require(cues(source, .webVTT, expected: 3))
        #expect(nodes.map(\.id) == [0, 1, 2])
        #expect(nodes.map(\.name) == ["00:01.000 \u{2192} 00:04.000", "intro cue: 00:00:05.000 \u{2192} 100:00:08.500", "00:09.000 \u{2192} 00:10.000"])
        #expect(nodes.map(\.value) == ["First <v Roger>cue</v>", "Second / lines", ""])
    }

    @Test func concealedSecretsRemainConcealedAndStructureSurvives() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\npassword:\u{2022}\u{2022}\u{2022}\u{2022}\n\n2\n00:00:03,000 --> 00:00:04,000\nsafe\n"
        let nodes = try #require(cues(srt, .subRip, expected: 2))
        #expect(nodes[0].value == "password:\u{2022}\u{2022}\u{2022}\u{2022}")
        #expect(nodes[1].value == "safe")
        let vtt = "WEBVTT\n\nNOTE \u{2022}\u{2022}\u{2022}\u{2022}\n\n00:00.000 --> 00:01.000 token:\u{2022}\u{2022}\u{2022}\u{2022}\nx"
        #expect(try #require(cues(vtt, .webVTT, expected: 1)).first?.value == "x")
    }

    @Test func concealmentThatSwallowsCuesFallsBackThroughTheExpectedCount() {
        // A secret assignment with an empty value conceals the rest of the document, so the
        // remaining text still parses, but with fewer cues than the adapter counted.
        let swallowed = "1\n00:00:01,000 --> 00:00:02,000\npassword:\u{2022}\u{2022}\u{2022}\u{2022}"
        #expect(cues(swallowed, .subRip) != nil)
        #expect(cues(swallowed, .subRip, expected: 2) == nil)
        #expect(cues(swallowed, .subRip, expected: 1) != nil)
    }

    @Test(arguments: [
        "", " \n", "just text", "1\n", "1\n00:00:01,000 --> 00:00:02,000x\nt", "1\n00:00:60,000 --> 00:01:00,000\nt",
        "1\n00:00:02,000 --> 00:00:01,000\nt", "1\n00:01,000 --> 00:02,000\nt", "x\n00:00:01,000 --> 00:00:02,000\nt",
        "1\n00:00:01,000 --> 00:00:02,000\nt\n2\n00:00:03,000 --> 00:00:04,000\nt",
        "1\n00:00:01,000 --> 00:00:02,000\nt\n\nstray\n"
    ])
    func malformedSubRipTextHasNoCueView(source: String) {
        #expect(cues(source, .subRip) == nil)
    }

    @Test(arguments: [
        "", "WEBVTT", "WEBVTT\n\nNOTE only\n", "webvtt\n\n00:00.000 --> 00:01.000\nx", "WEBVTTX\n\n00:00.000 --> 00:01.000\nx",
        "\u{2022}\u{2022}\u{2022}\u{2022}\n\n00:00.000 --> 00:01.000\nx",
        "WEBVTT\n\n00:00.000 --> 00:60.000\nx", "WEBVTT\n\n00:00:01,000 --> 00:00:02,000\nx", "WEBVTT\n\n1:00:00.000 --> 1:00:01.000\nx",
        "WEBVTT\n\nstray block\n", "WEBVTT\n\n00:00.000 --> 00:01.000\nfirst\n00:01.000 --> 00:02.000\nsecond",
        "WEBVTT\n\n00:00.000 --> 00:01.000\nx\n\nSTYLE\n::cue{}", "WEBVTT\n\nNOTE\na\nb --> c"
    ])
    func malformedOrCuelessWebVTTHasNoCueView(source: String) {
        #expect(cues(source, .webVTT) == nil)
    }

    @Test func otherSyntaxesNeverProduceCues() {
        let source = "1\n00:00:01,000 --> 00:00:02,000\nx"
        for syntax in [TextSyntax.plain, .json, .sourceCode, .markdown, .commaSeparated, .tabSeparated] {
            #expect(cues(source, syntax) == nil)
        }
        // A SubRip body is not WebVTT and the reverse.
        #expect(cues(source, .webVTT) == nil)
        #expect(cues("WEBVTT\n\n00:00.000 --> 00:01.000\nx", .subRip) == nil)
    }

    @Test func boundsRejectLargeTextManyCuesAndLongCues() {
        let one = "1\n00:00:01,000 --> 00:00:02,000\nx\n\n"
        let many = String(repeating: one, count: SafeSubtitleCues.maximumCues + 1)
        #expect(many.utf16.count <= SafeSubtitleCues.maximumUTF16Units)
        #expect(cues(many, .subRip) == nil)
        let allowed = String(repeating: one, count: SafeSubtitleCues.maximumCues)
        #expect(cues(allowed, .subRip)?.count == SafeSubtitleCues.maximumCues)
        let lines = Array(repeating: String(repeating: "a", count: 1_024), count: 17).joined(separator: "\n")
        #expect(cues("1\n00:00:01,000 --> 00:00:02,000\n" + lines, .subRip) == nil)
        let atLimit = Array(repeating: String(repeating: "a", count: 1_024), count: 16).joined(separator: "\n")
        #expect(cues("1\n00:00:01,000 --> 00:00:02,000\n" + atLimit, .subRip)?.count == 1)
        // Seventy cues of 16,000 characters each are individually allowed but exceed the text bound.
        let long = "1\n00:00:01,000 --> 00:00:02,000\n" + String(repeating: "a", count: 16_000) + "\n\n"
        let withinText = String(repeating: long, count: 60)
        #expect(withinText.utf16.count <= SafeSubtitleCues.maximumUTF16Units)
        #expect(cues(withinText, .subRip)?.count == 60)
        let overText = String(repeating: long, count: 70)
        #expect(overText.utf16.count > SafeSubtitleCues.maximumUTF16Units)
        #expect(cues(overText, .subRip) == nil)
    }

    @Test func exactSourceSpellingSurvivesCanonicallyEquivalentText() throws {
        let precomposed = "1\n00:00:01,000 --> 00:00:02,000\nCaf\u{E9}\n"
        let decomposed = "1\n00:00:01,000 --> 00:00:02,000\nCafe\u{301}\n"
        let first = try #require(cues(precomposed, .subRip))
        let second = try #require(cues(decomposed, .subRip))
        // Outline invalidation compares exact code units, so equivalent text is still a change.
        #expect(first != second)
        #expect(second[0].value.unicodeScalars.map(\.value) == Array("Cafe\u{301}".unicodeScalars.map(\.value)))
    }

    @Test func rowsDoNotDependOnTheLocale() throws {
        let source = "1\n00:00:01,000 --> 00:00:02,000\nx\n"
        let english = SafeSubtitleCues.nodes(source, syntax: .subRip, locale: Locale(identifier: "en"))
        for identifier in ["tr", "ja", "hi", "bn", "ku-Latn", "ar"] {
            #expect(SafeSubtitleCues.nodes(source, syntax: .subRip, locale: Locale(identifier: identifier)) == english)
        }
    }
}
