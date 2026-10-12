import Foundation
import Testing
import PreviewContracts
import PreviewFormats

func parseSubtitle(_ text: String, _ variant: SubtitleAdapter.Variant, budget: PreviewBudget = .standard,
                   byteCount: Int? = nil) throws -> ParsedTextDocument {
    try SubtitleAdapter(variant: variant).parse(
        DecodedText(text: text, encoding: .utf8, byteCount: byteCount ?? text.utf8.count),
        context: RequestContext(budget: budget))
}

private func parseSRT(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try parseSubtitle(text, .subRip, budget: budget)
}

private let twoCues = "1\n00:00:01,000 --> 00:00:04,000\nHello\n\n2\n00:00:05,000 --> 00:00:08,500\nWorld\n"

@Suite("SubRip adapter")
struct SubRipAdapterTests {
    @Test func normalFileRetainsExactSourceAndReportsSyntaxAndCueCount() throws {
        let parsed = try parseSRT(twoCues)
        #expect(parsed.text == twoCues)
        #expect(parsed.syntax == .subRip)
        #expect(parsed.usesStructuredPrivacy == false)
        #expect(parsed.sourceRecordCount == 2)
        #expect(parsed.sensitiveRanges.isEmpty)
        #expect(parsed.decodedEncoding == nil)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func lineTerminatorsAreAcceptedAndNeverNormalized(separator: String) throws {
        for finalNewline in [false, true] {
            let source = twoCues.replacingOccurrences(of: "\n", with: separator)
            // "\r\n" is a single Character, so dropping one removes the whole final terminator.
            let text = finalNewline ? source : String(source.dropLast())
            let parsed = try parseSRT(text)
            #expect(parsed.text.utf8.elementsEqual(text.utf8))
            #expect(parsed.sourceRecordCount == 2)
        }
    }

    @Test(arguments: [
        "00:00:01,000 --> 00:00:02,000\nNo index",
        "7\n00:00:01.000 --> 00:00:02.000\nDot milliseconds",
        "1\n00:00:01,000 --> 00:00:02,000\nline one\nline two\n<i>markup</i> {\\an8}",
        "\n\n1\n00:00:01,000 --> 00:00:02,000\ntext\n\n\n\n2\n00:00:03,000 --> 00:00:04,000\ntext\n\n\n",
        "1\n00:00:01,000 --> 00:00:02,000\ntext\n \t \n2\n00:00:03,000 --> 00:00:04,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000 X1:100 X2:200 Y1:50 Y2:100\ntext",
        "1\n00:00:01,000-->00:00:02,000\ntext",
        "  1  \n  00:00:01,000   -->   00:00:02,000  \ntext",
        "1\n100:00:00,000 --> 100:00:01,000\nover one hundred hours",
        "1\n0:00:01,000 --> 0:00:02,000\nsingle digit hour",
        "1\n00:00:01,000 --> 00:00:01,000\nzero duration",
        "1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:02,000 --> 00:00:03,000\ntext after an empty cue",
        "1\n00:00:05,000 --> 00:00:06,000\nlater\n\n2\n00:00:01,000 --> 00:00:02,000\nearlier start is allowed",
        "1\n00:00:01,000 --> 00:00:02,000\nA --> B is ordinary text when it is not a timing line",
        "\u{FEFF}1\n00:00:01,000 --> 00:00:02,000\ntext"
    ])
    func toleratedVariantsParseWithoutChangingText(source: String) throws {
        let parsed = try parseSRT(source)
        #expect(parsed.text.utf8.elementsEqual(source.utf8))
        #expect((parsed.sourceRecordCount ?? 0) >= 1)
    }

    @Test(arguments: [
        "", " \n \t\n", "\n\n\n", "just some text",
        "1\n", "1\n\n", "1\nnot a timing line\ntext",
        "00:00:01,000 --> 00:00:02,000x\ntext",
        "1\n00:00:60,000 --> 00:01:00,000\ntext",
        "1\n00:60:00,000 --> 00:61:00,000\ntext",
        "1\n00:00:01,00 --> 00:00:02,00\ntext",
        "1\n00:00:01,0000 --> 00:00:02,000\ntext",
        "1\n00:00:02,000 --> 00:00:01,999\ntext",
        "1\n00:00:01,000 -> 00:00:02,000\ntext",
        "1\n00:00:01,000 -- 00:00:02,000\ntext",
        "1\n00:01,000 --> 00:02,000\ntext",
        "1\n00:00:01:000 --> 00:00:02:000\ntext",
        "1\n00:00:01,000 --> \ntext",
        "1\n--> 00:00:02,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000 --> 00:00:03,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000 X1:1 --> X2:2\ntext",
        "1\n1234567890:00:01,000 --> 1234567890:00:02,000\ntext",
        "x1\n00:00:01,000 --> 00:00:02,000\ntext",
        "1 2\n00:00:01,000 --> 00:00:02,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000\ntext\n\nstray text block\n\n2\n00:00:03,000 --> 00:00:04,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000\ntext\n\n2\n",
        // A missing blank separator would silently merge the second cue into the first.
        "1\n00:00:01,000 --> 00:00:02,000\ntext\n2\n00:00:03,000 --> 00:00:04,000\ntext",
        "1\n00:00:01,000 --> 00:00:02,000\ntext\n00:00:03,000 --> 00:00:04,000\ntext",
        // A blank line inside cue text makes the remainder an invalid block.
        "1\n00:00:01,000 --> 00:00:02,000\nfirst\n\nsecond\n"
    ])
    func malformedFilesFailInsteadOfBeingPresentedAsComplete(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parseSRT(source) }
    }

    @Test func unicodeCueTextAndCanonicalEquivalentsAreRetainedExactly() throws {
        // U+00E9 versus e + U+0301 compare equal as Swift strings but are different source units.
        let source = "1\n00:00:01,000 --> 00:00:02,000\nCaf\u{E9} cafe\u{301} 日本語 😀 שלום ‮RLO\n"
        let parsed = try parseSRT(source)
        #expect(parsed.text.utf8.elementsEqual(source.utf8))
    }

    @Test func cueLimitUsesTheSharedNodeBudget() throws {
        let three = "1\n00:00:01,000 --> 00:00:02,000\na\n\n2\n00:00:02,000 --> 00:00:03,000\nb\n\n3\n00:00:03,000 --> 00:00:04,000\nc\n"
        #expect(try parseSRT(three, budget: PreviewBudget(maxJSONNodes: 3)).sourceRecordCount == 3)
        #expect(throws: PreviewFailure.tooManyNodes) { try parseSRT(three, budget: PreviewBudget(maxJSONNodes: 2)) }
    }

    @Test func sourceLineAndOutputLimitsApplyBeforeParsing() {
        #expect(throws: PreviewFailure.tooManyLines) { try parseSRT(twoCues, budget: PreviewBudget(maxTextLines: 4)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parseSRT(twoCues, budget: PreviewBudget(maxLineUTF8Bytes: 20)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parseSRT(twoCues, budget: PreviewBudget(maxInputBytes: 20)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parseSubtitle(twoCues, .subRip, byteCount: 2_000_000) }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parseSRT(twoCues, budget: PreviewBudget(maxInputBytes: 1_000, maxOutputUTF8Bytes: 20))
        }
    }

    @Test func manyCuesAndHostileRepetitionStayWithinBudgetsAndTerminate() throws {
        let cues = (1...5_000).map { "\($0)\n00:00:01,000 --> 00:00:02,000\ncue \($0)\n" }.joined(separator: "\n")
        #expect(try parseSRT(cues).sourceRecordCount == 5_000)
        let arrows = String(repeating: "--> ", count: 5_000)
        #expect(throws: PreviewFailure.malformedDocument) { try parseSRT("1\n" + arrows) }
        let hugeDigits = String(repeating: "9", count: 8_000)
        #expect(throws: PreviewFailure.malformedDocument) { try parseSRT("1\n\(hugeDigits):00:01,000 --> 00:00:02,000\nx") }
    }

    @Test func preCancelledRequestsStopBeforeParsing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try parseSRT(twoCues); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
    }

    @Test func expiredDeadlineStopsLargeSources() throws {
        let cue = "1\n00:00:01,000 --> 00:00:02,000\n" + String(repeating: "x", count: 100) + "\n\n"
        let source = String(repeating: cue, count: 60_000)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                                   maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 1)
        #expect(throws: PreviewFailure.deadlineExceeded) { try parseSRT(source, budget: budget) }
    }

    @Test func cooperativeCancellationStopsAnActiveLargeSource() async throws {
        let cue = "1\n00:00:01,000 --> 00:00:02,000\n" + String(repeating: "x", count: 100) + "\n\n"
        let source = String(repeating: cue, count: 20_000)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                                   maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 30_000)
        let decoded = DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count)
        try await CancellationTest.expectStopsActiveParse(budget: budget) {
            try SubtitleAdapter(variant: .subRip).parse(decoded, context: $0)
        }
    }
}
