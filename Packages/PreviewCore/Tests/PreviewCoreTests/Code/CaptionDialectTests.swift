import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private let secret = "synthetic-secret-value"

private func parse(_ text: String, _ dialect: CaptionDialect, limits: CaptionLimits = CaptionLimits()) throws -> CaptionDocument {
    try CaptionParser.parse(Array(text.utf8), dialect: dialect, limits: limits)
}

private func adapt(_ text: String, _ dialect: CaptionDialect, budget: PreviewBudget = .standard) throws -> (ParsedTextDocument, SafeText) {
    let context = RequestContext(budget: budget)
    let parsed = try CaptionAdapter(dialect: dialect).parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
    return (parsed, try DefaultPrivacyFilter().filter(parsed, context: context))
}

private let ass = """
[Script Info]
Title: Fixture
ScriptType: v4.00+

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Arial,20

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\i1}Hello{\\i0}, world\\Nsecond line
Comment: 0,0:00:02.00,0:00:03.00,Default,,0,0,0,,a note
Dialogue: 0,1:02:03.50,1:02:05.00,Sign,Ann,0,0,0,,line\\none and\\hmore

"""

@Suite("SubStation Alpha captions")
struct SubStationAlphaTests {
    @Test func dialogueBecomesCuesWithOverridesRemovedOnlyInTheCueView() throws {
        let document = try parse(ass, .subStationAlpha)
        #expect(document.cues.count == 2)
        #expect(document.cues[0] == CaptionCue(label: "Default", start: "0:00:01.00", end: "0:00:04.00", lines: ["Hello, world", "second line"]))
        #expect(document.cues[1].label == "Sign / Ann" && document.cues[1].start == "1:02:03.50")
        #expect(document.cues[1].lines == ["line one and more"])
        // The adapter shows the source untouched.
        let (parsed, _) = try adapt(ass, .subStationAlpha)
        #expect(parsed.text == ass && parsed.syntax == .subStationAlpha && parsed.sourceRecordCount == 2)
    }

    @Test func formatLineAndSsaSixColumnFilesAreHonored() throws {
        let ssa = "[Script Info]\nTitle: x\n[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Text, with, commas\n"
        let document = try parse(ssa, .subStationAlpha)
        #expect(document.cues.first?.lines == ["Text, with, commas"])
        // Without a Format line the SSA v4+ column list applies.
        let bare = "[Script Info]\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,x\n"
        #expect(try parse(bare, .subStationAlpha).cues.count == 1)
    }

    @Test(arguments: [
        "", "Title: no header\n", "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,x\n",
        "[Script Info]\nnot a key value line\n",
        "[Script Info]\n[Events]\nFormat: Start, End\nDialogue: 0,0:00:01.00\n",
        "[Script Info]\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:05.00,0:00:01.00,D,,0,0,0,,backwards\n",
        "[Script Info]\n[Events]\nDialogue: 0,0:00:01.00,00:02.00,D,,0,0,0,,bad time\n",
        "[Script Info]\n[Events]\nUnknown: 1\n",
        "[Script Info]\n[Events]\nFormat: Start, Text, End\n"
    ]) func malformedFilesAreRejected(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source, .subStationAlpha) }
    }

    @Test func fontsAndGraphicsSectionsAndCommentsAreSkipped() throws {
        let source = "; leading comment\n[Script Info]\n; another\nTitle: x\n[Fonts]\nfontname: font.ttf\n!!!!0123\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,hi\n[Graphics]\nanything at all $%^\n"
        #expect(try parse(source, .subStationAlpha).cues.count == 1)
    }

    @Test func cueLimitAndTextLimitAreEnforced() {
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(ass, .subStationAlpha, limits: CaptionLimits(maximumCues: 1)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(ass, .subStationAlpha, limits: CaptionLimits(maximumCueTextUTF8Bytes: 4)) }
    }

    @Test func secretsInDialogueCommentsAndMetadataAreConcealed() throws {
        let source = ass.replacingOccurrences(of: "a note", with: "token = \(secret)")
            .replacingOccurrences(of: "Title: Fixture", with: "; password: \(secret)\nTitle: Fixture")
            + "Dialogue: 0,0:00:06.00,0:00:07.00,Default,,0,0,0,,password: \(secret)\n"
        let (parsed, safe) = try adapt(source, .subStationAlpha)
        #expect(!safe.text.contains(secret))
        #expect(parsed.sourceRecordCount == 3)
        // The comment ranges alone (not only the heuristic) cover comments and Comment: events.
        #expect(parsed.sensitiveRanges.count == 2)
    }
}

@Suite("TTML captions")
struct TimedTextTests {
    private let ttml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en"><head><styling/></head><body><div>
    <p begin="00:00:01.000" end="00:00:04.000">Hello<br/>  spaced   world </p>
    <p begin="5s" dur="2.5s"><span>one</span> <span>two</span></p>
    <p begin="10f" end="00:00:12:05">frames</p>
    </div></body></tt>
    """

    @Test func paragraphsBecomeCuesWithTimesShownAsWritten() throws {
        let document = try parse(ttml, .timedText)
        #expect(document.cues == [
            CaptionCue(start: "00:00:01.000", end: "00:00:04.000", lines: ["Hello", "spaced world"]),
            CaptionCue(start: "5s", end: "+2.5s", lines: ["one two"]),
            CaptionCue(start: "10f", end: "00:00:12:05", lines: ["frames"])
        ])
        let (parsed, _) = try adapt(ttml, .timedText)
        #expect(parsed.text == ttml && parsed.syntax == .timedText && parsed.sourceRecordCount == 3 && parsed.usesStructuredPrivacy)
    }

    @Test(arguments: [
        "", "<tt", "<tt><body><p begin=\"bad\">x</p></body></tt>", "<root><p begin=\"1s\">x</p></root>",
        "<tt><body><p begin=\"1\">x</p></body></tt>", "<tt><body><p begin=\"00:61:00.000\">x</p></body></tt>",
        "<!DOCTYPE tt [<!ENTITY x \"y\">]><tt><body><p>&x;</p></body></tt>", "<tt><body><p>unclosed</body></tt>",
        "<tt><body><p begin=\"1s\">x</p></body></tt><tt/>"
    ]) func malformedDocumentsAreRejected(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source, .timedText) }
    }

    @Test func nestingAndCueLimitsAreEnforced() {
        let deep = String(repeating: "<div>", count: 10) + "<p begin=\"1s\">x</p>" + String(repeating: "</div>", count: 10)
        #expect(throws: PreviewFailure.structureTooDeep) { try parse("<tt><body>" + deep + "</body></tt>", .timedText, limits: CaptionLimits(maximumDepth: 5)) }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(ttml, .timedText, limits: CaptionLimits(maximumCues: 2)) }
    }

    @Test func textRunsAttributesAndCommentsThatHoldSecretsAreConcealedWithTheMarkupIntact() throws {
        let source = "<?xml version=\"1.0\"?><tt><body><div><!-- password: \(secret) -->"
            + "<p begin=\"1s\" end=\"2s\">token = \(secret)</p><p begin=\"3s\" end=\"4s\" api_key=\"\(secret)\">visible</p></div></body></tt>"
        let (parsed, safe) = try adapt(source, .timedText)
        #expect(!safe.text.contains(secret))
        #expect(safe.text.contains("visible"))
        let reparsed = try parse(safe.text, .timedText)
        #expect(reparsed.cues.count == parsed.sourceRecordCount)
        #expect(XMLParser(data: Data(safe.text.utf8)).parse())
    }

    @Test func policyIsStrictBecauseATruncatedXmlDocumentIsNotValid() {
        #expect(CaptionAdapter(dialect: .timedText).textInputPolicy == .strict)
    }
}

@Suite("SubViewer, lyrics and MicroDVD captions")
struct LineCaptionDialectTests {
    @Test func subViewerBlocksBecomeCues() throws {
        let source = "0:00:01.000,0:00:04.000\nHello\nworld\n\n10:00:05.000,10:00:08.500\nLater\n"
        let document = try parse(source, .subViewer)
        #expect(document.cues == [
            CaptionCue(start: "0:00:01.000", end: "0:00:04.000", lines: ["Hello", "world"]),
            CaptionCue(start: "10:00:05.000", end: "10:00:08.500", lines: ["Later"])
        ])
        let (parsed, _) = try adapt(source, .subViewer)
        #expect(parsed.text == source && parsed.syntax == .subViewer && parsed.sourceRecordCount == 2)
    }

    @Test(arguments: ["", "text only\n", "0:00:01.000 --> 0:00:02.000\nx", "0:00:05.000,0:00:01.000\nbackwards", "0:0:01.000,0:00:02.000\nx",
                      "0:00:01.00,0:00:02.00\nshort fraction"])
    func malformedSubViewerIsRejected(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source, .subViewer) }
    }

    @Test func lyricsWithTagsMultipleStampsAndEnhancedWordTimes() throws {
        let source = "[ti:Song]\n[ar:Artist]\n[offset:+250]\n\n[00:12.00]First line\n[00:15.30][01:20.5]Chorus <00:15.50>word\n[1:02:03]Plain\n[00:30.00][Bridge] annotation\n"
        let document = try parse(source, .lyrics)
        #expect(document.metadata == [CaptionMetadata(key: "ti", value: "Song"), CaptionMetadata(key: "ar", value: "Artist"),
                                      CaptionMetadata(key: "offset", value: "+250")])
        #expect(document.cues.map(\.start) == ["00:12.00", "00:15.30", "01:20.5", "1:02:03", "00:30.00"])
        #expect(document.cues[1].lines == ["Chorus word"] && document.cues[2].lines == ["Chorus word"])
        #expect(document.cues[4].lines == ["[Bridge] annotation"])
    }

    @Test(arguments: ["", "[ti:Only a tag]\n", "no brackets\n", "[00:12.00]ok\nplain line\n", "[ti:Song][00:12.00]mixed\n", "[ti:Song] trailing\n",
                      "[00:12.00 unclosed\n", "[12:3]bad seconds\n"])
    func malformedLyricsAreRejected(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source, .lyrics) }
    }

    @Test func microDVDConvertsFramesAtTheStatedOrDefaultRate() throws {
        let stated = try parse("{1}{1}23.976\n{24}{48}Hello|world {y:i}styled{y:n}\n", .microDVD)
        #expect(stated.cues == [CaptionCue(start: "0:00:01.001", end: "0:00:02.002", lines: ["Hello", "world styled"])])
        let defaulted = try parse("{25}{100}One\n\n{125}{250}Two\n", .microDVD)
        #expect(defaulted.cues.map(\.start) == ["0:00:01.000", "0:00:05.000"])
        #expect(defaulted.cues.map(\.end) == ["0:00:04.000", "0:00:10.000"])
        // A first line that is not a rate stays a cue.
        #expect(try parse("{1}{1}not a number\n{2}{3}x\n", .microDVD).cues.count == 2)
    }

    @Test(arguments: ["", "{1}{1}25\n", "plain\n", "{10}{5}backwards\n", "{10}text without end\n", "{a}{b}x\n"])
    func malformedMicroDVDIsRejected(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source, .microDVD) }
    }

    @Test(arguments: [CaptionDialect.subViewer, .lyrics, .microDVD, .subStationAlpha])
    func secretsInCuesAreConcealed(dialect: CaptionDialect) throws {
        let source: String
        switch dialect {
        case .subViewer: source = "0:00:01.000,0:00:02.000\nok\n\n0:00:03.000,0:00:04.000\npassword: \(secret)\n"
        case .lyrics: source = "[00:01.00]ok\n[00:03.00]password: \(secret)\n"
        case .microDVD: source = "{25}{50}ok\n{75}{100}password: \(secret)\n"
        default: source = "[Script Info]\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,ok\nDialogue: 0,0:00:03.00,0:00:04.00,D,,0,0,0,,password: \(secret)\n"
        }
        let (parsed, safe) = try adapt(source, dialect)
        #expect(!safe.text.contains(secret))
        #expect(parsed.sourceRecordCount == 2)
        #expect(safe.redactionCount == 1)
    }

    @Test func cancellationAndExpiredDeadlinePrecedeInputAccess() async {
        for dialect in [CaptionDialect.subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD] {
            let task = Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                do { _ = try CaptionAdapter(dialect: dialect).parse(.init(text: "", encoding: .utf8, byteCount: 0), context: .init(budget: .standard)); return false }
                catch is CancellationError { return true } catch { return false }
            }
            #expect(await task.value, "\(dialect)")
            #expect(throws: PreviewFailure.deadlineExceeded) {
                try CaptionAdapter(dialect: dialect).parse(.init(text: "", encoding: .utf8, byteCount: 0), context: .init(budget: .init(maxMilliseconds: 0)))
            }
        }
    }

    @Test func dialectsThatAreLineBasedOptIntoPartialReads() {
        #expect(CaptionAdapter(dialect: .subViewer).textInputPolicy == .leadingRecords(.blankLine))
        #expect(CaptionAdapter(dialect: .lyrics).textInputPolicy == .leadingRecords(.line))
        #expect(CaptionAdapter(dialect: .subStationAlpha).textInputPolicy == .leadingRecords(.line))
    }
}

@Suite("MicroDVD binary guard")
struct MicroDVDBinaryTests {
    private func parse(_ bytes: [UInt8]) throws -> ParsedTextDocument {
        try MicroDVDAdapter().parse(FileBytes(data: Data(bytes)), context: RequestContext(budget: .standard))
    }

    @Test func textDecodesAndReportsItsEncoding() throws {
        let parsed = try parse(Array("{25}{50}hello\n".utf8))
        #expect(parsed.syntax == .microDVD && parsed.decodedEncoding == .utf8 && parsed.sourceRecordCount == 1)
        var utf16: [UInt8] = [0xFF, 0xFE]
        for unit in "{25}{50}héllo\n".utf16 { utf16 += [UInt8(unit & 255), UInt8(unit >> 8)] }
        let wide = try parse(utf16)
        #expect(wide.decodedEncoding == .utf16LittleEndian && wide.text.contains("héllo"))
    }

    @Test func vobSubProgramStreamsNulBytesAndBinaryBlobsAreNeverMisread() {
        #expect(throws: PreviewFailure.binaryContent) { try parse([0x00, 0x00, 0x01, 0xBA, 0x44, 0x00, 0x04]) }
        #expect(throws: PreviewFailure.binaryContent) { try parse(Array("{1}{2}ok".utf8) + [0, 1, 2]) }
        #expect(throws: PreviewFailure.unsupportedEncoding) { try parse([0x7B, 0x31, 0x7D, 0xFF, 0xFE, 0x41]) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Array("SubViewer 2\n[INFORMATION]\n".utf8)) }
    }

    @Test func budgetCancellationAndDeadlineAreChecked() {
        #expect(throws: PreviewFailure.inputTooLarge) {
            try MicroDVDAdapter().parse(FileBytes(data: Data(repeating: 65, count: 65)), context: .init(budget: .init(maxInputBytes: 64)))
        }
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try MicroDVDAdapter().parse(FileBytes(data: Data()), context: .init(budget: .init(maxMilliseconds: 0)))
        }
    }
}
