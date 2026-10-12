import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parseVTT(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try parseSubtitle(text, .webVTT, budget: budget)
}

private func concealedSlices(_ parsed: ParsedTextDocument) -> [String] {
    let bytes = Array(parsed.text.utf8)
    return parsed.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
}

private let basic = "WEBVTT\n\n00:01.000 --> 00:04.000\nHello\n\nintro\n00:00:05.000 --> 00:00:08.500 align:start position:10%\nWorld\n"

@Suite("WebVTT adapter")
struct WebVTTAdapterTests {
    @Test func normalFileRetainsExactSourceAndReportsSyntaxAndCueCount() throws {
        let parsed = try parseVTT(basic)
        #expect(parsed.text == basic)
        #expect(parsed.syntax == .webVTT)
        #expect(parsed.usesStructuredPrivacy == false)
        #expect(parsed.sourceRecordCount == 2)
        #expect(parsed.sensitiveRanges.isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func lineTerminatorsAreAcceptedAndNeverNormalized(separator: String) throws {
        let source = basic.replacingOccurrences(of: "\n", with: separator)
        let parsed = try parseVTT(source)
        #expect(parsed.text.utf8.elementsEqual(source.utf8))
        #expect(parsed.sourceRecordCount == 2)
    }

    @Test(arguments: [
        "WEBVTT",
        "WEBVTT\n",
        "WEBVTT\n\n",
        "WEBVTT - this file has cues\n\n00:00.000 --> 00:01.000\nx",
        "WEBVTT\tTabbed header text\n\n00:00.000 --> 00:01.000\nx",
        "\u{FEFF}WEBVTT\n\n00:00.000 --> 00:01.000\nx",
        // Header lines run to the blank line; HLS timestamp maps are ordinary header text.
        "WEBVTT\nKind: captions\nLanguage: en\nX-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000\n\n00:00.000 --> 00:01.000\nx",
        // The specification's parser starts the first cue at a `-->` line even without a blank line.
        "WEBVTT\n00:00.000 --> 00:01.000\nx",
        "WEBVTT\nheader line\n00:00.000 --> 00:01.000\nx",
        "WEBVTT\n\n\n\n00:00.000 --> 00:01.000\nx\n\n\n\n\n00:01.000 --> 00:02.000\ny\n\n\n",
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nhours present with zero value",
        "WEBVTT\n\n100:00:00.000 --> 100:00:01.000\nthree digit hours",
        "WEBVTT\n\n00:00.000 --> 00:00.000\nzero duration",
        "WEBVTT\n\n00:00.000-->00:01.000\ntightly joined arrow",
        "WEBVTT\n\n00:00.000 \t --> \t 00:01.000\ttab separated\ttokens\nx",
        "WEBVTT\n\n00:00.000 --> 00:01.000\n",
        "WEBVTT\n\n00:00.000 --> 00:01.000\n\n00:01.000 --> 00:02.000\nempty payload before this cue",
        "WEBVTT\n\n00:05.000 --> 00:06.000\nlater\n\n00:01.000 --> 00:02.000\nearlier start is allowed",
        "WEBVTT\n\n00:00.000 --> 00:01.000\nline one\n \nline two with a space-only line, which is payload",
        "WEBVTT\n\nCue 1 has spaces\n00:00.000 --> 00:01.000\n<v Roger>Hi</v> <c.loud>there</c> <i>x</i>",
        "WEBVTT\n\n00:00.000 --> 00:01.000 vertical:rl line:-1 size:80% not-a-setting region:fred\nx",
        "WEBVTT\n\n00:00.000 --> 00:01.000\n日本語 😀 Café שלום",
        "WEBVTT\n\nSTYLE\n::cue { color: red }\n\nREGION\nid:fred width:40%\n\n00:00.000 --> 00:01.000\nx",
        "WEBVTT\n\nSTYLE \t \n::cue { color: red }\n\n00:00.000 --> 00:01.000\nx"
    ])
    func validFilesParseWithoutChangingText(source: String) throws {
        let parsed = try parseVTT(source)
        #expect(parsed.text.utf8.elementsEqual(source.utf8))
        #expect(parsed.syntax == .webVTT)
    }

    @Test func fileWithoutCuesIsValidAndReportsZero() throws {
        #expect(try parseVTT("WEBVTT\n\nNOTE only a comment\n").sourceRecordCount == 0)
        #expect(try parseVTT("WEBVTT").sourceRecordCount == 0)
    }

    @Test(arguments: [
        "", "\n", "WEBVT", "webvtt\n\n00:00.000 --> 00:01.000\nx", "WEBVTTX\n", "WEBVTT-x\n", " WEBVTT\n",
        "\nWEBVTT\n", "00:00.000 --> 00:01.000\nx",
        // SubRip content is not WebVTT.
        "1\n00:00:01,000 --> 00:00:02,000\nx",
        "WEBVTT\n\n00:00:01,000 --> 00:00:02,000\nSubRip comma separator is invalid"
    ])
    func signatureIsRequiredAndExact(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parseVTT(source) }
    }

    @Test(arguments: [
        "WEBVTT\n\n00:00.000 --> 00:60.000\nx",
        "WEBVTT\n\n00:60.000 --> 00:61.000\nx",
        "WEBVTT\n\n60:00.000 --> 61:00.000\nminutes cannot exceed 59 without hours",
        "WEBVTT\n\n0:00.000 --> 0:01.000\nsingle digit minutes",
        "WEBVTT\n\n1:00:00.000 --> 1:00:01.000\nhours need two digits",
        "WEBVTT\n\n00:00:00.000 --> 00:00:00.00\nmilliseconds need three digits",
        "WEBVTT\n\n00:00.0000 --> 00:01.000\nx",
        "WEBVTT\n\n00:00.000 --> 00:01\nx",
        "WEBVTT\n\n00:01.000 --> 00:00.999\nend before start",
        "WEBVTT\n\n00:00.000 -> 00:01.000\nx",
        "WEBVTT\n\n00:00.000 --> 00:01.000x\nx",
        "WEBVTT\n\n00:00.000 --> 00:01.000 setting:--> bad\nx",
        "WEBVTT\n\n00:00.000 --> 00:01.000 --> 00:02.000\nx",
        "WEBVTT\n\n--> 00:01.000\nx",
        "WEBVTT\n\nidentifier only\n",
        "WEBVTT\n\nidentifier\nstill not timings\ntext\n",
        "WEBVTT\n\njust text\n",
        "WEBVTT\n\nNOTEBOOK\nbody",
        "WEBVTT\n\nSTYLE x\nbody",
        "WEBVTT\n\nREGIONS\nbody",
        "WEBVTT\n\nstyle\nlowercase keywords are invalid",
        // Cue payloads must not contain the arrow, which also catches a missing blank line.
        "WEBVTT\n\n00:00.000 --> 00:01.000\nfirst\n00:01.000 --> 00:02.000\nsecond",
        "WEBVTT\n\n00:00.000 --> 00:01.000\nA --> B",
        // A whitespace-only line is payload, not a separator, so the next cue merges and is rejected.
        "WEBVTT\n\n00:00.000 --> 00:01.000\nfirst\n \n00:01.000 --> 00:02.000\nsecond",
        "WEBVTT\n\nNOTE\ncomment\nwith --> arrow",
        "WEBVTT\n\nSTYLE\n::cue { color: red }\n::cue { content: \"-->\" }\n",
        "WEBVTT\n\nREGION\nid:a\nwidth:40% --> b\n",
        // STYLE and REGION blocks are valid only before the first cue.
        "WEBVTT\n\n00:00.000 --> 00:01.000\nx\n\nSTYLE\n::cue { color: red }",
        "WEBVTT\n\n00:00.000 --> 00:01.000\nx\n\nREGION\nid:fred"
    ])
    func malformedFilesFailInsteadOfBeingPresentedAsComplete(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parseVTT(source) }
    }

    @Test func noteBlocksCanAppearBeforeBetweenAndAfterCues() throws {
        let source = "WEBVTT\n\nNOTE\n\nNOTE before\n\n00:00.000 --> 00:01.000\nx\n\nNOTE between\nsecond line\n\n00:01.000 --> 00:02.000\ny\n\nNOTE\tafter\n"
        #expect(try parseVTT(source).sourceRecordCount == 2)
    }

    @Test func identifierMayLookLikeAKeywordWhenTimingsFollow() throws {
        let source = "WEBVTT\n\nNOTE\n00:00.000 --> 00:01.000\ncue whose identifier is NOTE\n\nSTYLE\n00:01.000 --> 00:02.000\nx"
        #expect(try parseVTT(source).sourceRecordCount == 2)
    }

    @Test func commentBodiesWithSecretAssignmentsAreConcealedWithoutBreakingStructure() throws {
        let inline = "WEBVTT\n\nNOTE api_key: synthetic-note\nsecond line\n\n00:00.000 --> 00:01.000\nx\n"
        #expect(concealedSlices(try parseVTT(inline)) == ["api_key: synthetic-note\nsecond line"])
        let separated = "WEBVTT\n\nNOTE\r\npassword = synthetic-note\r\n\r\n00:00.000 --> 00:01.000\r\nx\r\n"
        #expect(concealedSlices(try parseVTT(separated)) == ["password = synthetic-note"])
        let tabbed = "WEBVTT\n\nNOTE\ttoken=synthetic-note"
        #expect(concealedSlices(try parseVTT(tabbed)) == ["token=synthetic-note"])
        let harmless = "WEBVTT\n\nNOTE reviewed by Dana: fine\n\n00:00.000 --> 00:01.000\nx\n"
        #expect(try parseVTT(harmless).sensitiveRanges.isEmpty)
        let bare = "WEBVTT\n\nNOTE\n\n00:00.000 --> 00:01.000\nx\n"
        #expect(try parseVTT(bare).sensitiveRanges.isEmpty)
    }

    @Test func absoluteUTF8OffsetsSurviveByteOrderMarkAndMultibyteText() throws {
        let source = "\u{FEFF}WEBVTT é\n\nNOTE 日本語 secret: 😀 value\n\n00:00.000 --> 00:01.000\nx\n"
        #expect(concealedSlices(try parseVTT(source)) == ["日本語 secret: 😀 value"])
    }

    @Test func cueLimitUsesTheSharedNodeBudget() throws {
        let three = "WEBVTT\n\n00:00.000 --> 00:01.000\na\n\n00:01.000 --> 00:02.000\nb\n\n00:02.000 --> 00:03.000\nc\n"
        #expect(try parseVTT(three, budget: PreviewBudget(maxJSONNodes: 3)).sourceRecordCount == 3)
        #expect(throws: PreviewFailure.tooManyNodes) { try parseVTT(three, budget: PreviewBudget(maxJSONNodes: 2)) }
    }

    @Test func sourceLineAndOutputLimitsApplyBeforeParsing() {
        #expect(throws: PreviewFailure.tooManyLines) { try parseVTT(basic, budget: PreviewBudget(maxTextLines: 5)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parseVTT(basic, budget: PreviewBudget(maxLineUTF8Bytes: 30)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parseVTT(basic, budget: PreviewBudget(maxInputBytes: 20)) }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parseVTT(basic, budget: PreviewBudget(maxInputBytes: 1_000, maxOutputUTF8Bytes: 20))
        }
    }

    @Test func hostileRepetitionTerminatesQuickly() {
        #expect(throws: PreviewFailure.malformedDocument) { try parseVTT("WEBVTT\n\n" + String(repeating: "-->", count: 5_000)) }
        #expect(throws: PreviewFailure.malformedDocument) {
            try parseVTT("WEBVTT\n\n" + String(repeating: "9", count: 8_000) + ":00:01.000 --> 00:00:02.000\nx")
        }
        let notes = String(repeating: "NOTE x\n\n", count: 5_000)
        #expect((try? parseVTT("WEBVTT\n\n" + notes))?.sourceRecordCount == 0)
    }

    @Test func preCancelledRequestsStopBeforeParsing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try parseVTT(basic); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
    }

    @Test func expiredDeadlineStopsLargeSources() {
        let cue = "00:01.000 --> 00:02.000\n" + String(repeating: "x", count: 100) + "\n\n"
        let source = "WEBVTT\n\n" + String(repeating: cue, count: 60_000)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                                   maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 1)
        #expect(throws: PreviewFailure.deadlineExceeded) { try parseVTT(source, budget: budget) }
    }

    @Test func cooperativeCancellationStopsAnActiveLargeSource() async throws {
        let cue = "00:01.000 --> 00:02.000\n" + String(repeating: "x", count: 100) + "\n\n"
        let source = "WEBVTT\n\n" + String(repeating: cue, count: 20_000)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                                   maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 30_000)
        let decoded = DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count)
        try await CancellationTest.expectStopsActiveParse(budget: budget) {
            try SubtitleAdapter(variant: .webVTT).parse(decoded, context: $0)
        }
    }
}
