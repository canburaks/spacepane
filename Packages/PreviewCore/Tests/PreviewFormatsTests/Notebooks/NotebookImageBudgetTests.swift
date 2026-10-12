import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Notebook image source budgets")
struct NotebookImageBudgetTests {
    private let budget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)

    private func source(payload: String, mime: String = "image/png", before: String = "print(1)", after: String = "print(2)") -> String {
        #"{ "nbformat" : 4, "cells" : [{"cell_type":"code","execution_count":1,"source":""# + before
            + #"","outputs":[{"output_type":"display_data","data":{""# + mime + #"": "# + payload
            + #", "text/plain":"Figure"}}]}, {"cell_type":"code","source":""# + after
            + #"","outputs":[]}], "metadata":{"untouched":"é 😀"} }"#
    }

    private func parse(_ text: String, budget: PreviewBudget? = nil) throws -> ParsedTextDocument {
        try JupyterNotebookAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                          context: RequestContext(budget: budget ?? self.budget))
    }

    @Test func realisticPNGBecomesAFigureAndOnlyItsValueChanges() throws {
        let png = TestImages.noisePNG(128, 128)
        try #require(png.count > 24_576)
        let payload = #"""# + png.base64EncodedString() + #"""#
        let original = source(payload: payload)
        let result = try parse(original)
        #expect(result.images.map(\.data) == [png])
        #expect(result.text.utf8.elementsEqual(source(payload: "null").utf8))
        #expect(result.origin == .converted)
        #expect(result.syntax == .json)
        #expect(result.usesStructuredPrivacy)
    }

    @Test func arraysUseOnePlaceholderAndRetainExactOutsideCodeUnits() throws {
        let png = TestImages.noisePNG(128, 128)
        let base64 = png.base64EncodedString(options: .lineLength64Characters)
        let pieces = base64.components(separatedBy: "\r\n")
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: pieces, options: [.prettyPrinted]), as: UTF8.self)
        let result = try parse(source(payload: payload), budget: PreviewBudget(maxInputBytes: 16_777_216,
                                                                              maxTextLines: 1, maxMilliseconds: 30_000))
        #expect(result.images.map(\.data) == [png])
        #expect(result.text.utf16.elementsEqual(source(payload: "null").utf16))
    }

    @Test func originalSecretRangesShiftAcrossImageReplacement() throws {
        let image = #"""# + TestImages.noisePNG(128, 128).base64EncodedString() + #"""#
        let result = try parse(source(payload: image, before: "password = before-canary", after: "token = after-canary"))
        let bytes = Array(result.text.utf8)
        let spans = result.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
        #expect(spans == [#""password = before-canary""#, #""token = after-canary""#])
    }

    @Test(arguments: ["image/png", "image/jpeg", "image/svg+xml", "image/gif"])
    func invalidAndUnsupportedImageStringsRemainInertPlaceholders(mime: String) throws {
        let result = try parse(source(payload: #""invalid!""#, mime: mime))
        #expect(result.images.isEmpty)
        #expect(result.text.utf8.elementsEqual(source(payload: "null", mime: mime).utf8))
        #expect(result.origin == .converted)
    }

    @Test func nonImageOutputAndMetadataAreNeverOmitted() throws {
        let text = source(payload: #""ordinary text""#, mime: "text/html")
        let result = try parse(text)
        #expect(result.text.utf16.elementsEqual(text.utf16))
        #expect(result.origin == .source)
        #expect(result.images.isEmpty)
    }

    @Test func onlySavedPNGAndJPEGOutputTypesBecomeFigures() throws {
        let png = TestImages.png().base64EncodedString()
        let text = source(payload: #"""# + png + #"""#).replacingOccurrences(of: "display_data", with: "future_output")
        #expect(try parse(text).images.isEmpty)
        let markdownCell = source(payload: #"""# + png + #"""#).replacingOccurrences(of: "\"cell_type\":\"code\"",
                                                                                      with: "\"cell_type\":\"markdown\"")
        #expect(try parse(markdownCell).images.isEmpty)
        let spoofed = source(payload: #"""# + TestImages.gif().base64EncodedString() + #"""#)
        #expect(try parse(spoofed).images.isEmpty)
        #expect(try parse(spoofed).origin == .converted)
    }

    @Test func invalidAlphabetAndPaddingCannotBecomeAValidImage() throws {
        let png = TestImages.png().base64EncodedString()
        let candidates = [png.prefix(12) + "!" + png.dropFirst(12), png + "=", "=" + png,
                          png.replacingOccurrences(of: "=", with: "") + "==="]
        for payload in candidates {
            let result = try parse(source(payload: #"""# + payload + #"""#))
            #expect(result.images.isEmpty)
            #expect(result.origin == .converted)
        }
    }

    @Test func omittedImagePrivacyDisappearsWhileCrossingAndAdjacentRangesStayExact() throws {
        let text = source(payload: #""payload""#)
        let bytes = Array(text.utf8)
        var scanner = JSONScanner(bytes: bytes, context: RequestContext(budget: budget))
        try scanner.scan()
        var builder = NotebookJSONTreeBuilder(bytes: bytes, context: RequestContext(budget: budget))
        let root = try builder.build()
        let token = try #require(text.range(of: #""payload""#))
        let lower = text.utf8.distance(from: text.utf8.startIndex, to: token.lowerBound)
        let upper = text.utf8.distance(from: text.utf8.startIndex, to: token.upperBound)
        for range in [lower..<upper, lower + 1..<upper - 1] {
            let result = try NotebookImageSource.transform(bytes, root: root,
                sensitiveRanges: [SensitiveRange(utf8Range: range)], context: RequestContext(budget: budget))
            // The sensitive original bytes are wholly omitted. Concealing the inert null would create
            // invalid JSON and spuriously withhold a safe notebook thumbnail.
            #expect(result.sensitiveRanges.isEmpty)
            #expect(result.text.utf8.elementsEqual(source(payload: "null").utf8))
        }
        let spans: [(Range<Int>, String)] = [
            (0..<lower, String(decoding: bytes[..<lower], as: UTF8.self)),
            (upper..<bytes.count, String(decoding: bytes[upper...], as: UTF8.self)),
            (lower - 1..<lower + 1, " null"), (upper - 1..<upper + 1, "null,"),
            (lower - 1..<upper + 1, " null,")
        ]
        for (range, expected) in spans {
            let result = try NotebookImageSource.transform(bytes, root: root,
                sensitiveRanges: [SensitiveRange(utf8Range: range)], context: RequestContext(budget: budget))
            let mapped = try #require(result.sensitiveRanges.first?.utf8Range)
            #expect(String(decoding: Array(result.text.utf8)[mapped], as: UTF8.self).utf16.elementsEqual(expected.utf16))
        }
    }

    @Test func hiddenCharactersAndNotebookHealthSurviveImageOmission() throws {
        let text = source(payload: #"""# + TestImages.png().base64EncodedString() + #"""#,
                          after: "é \u{202E} tail")
        let result = try parse(text)
        #expect(result.text.contains("é \u{202E} tail"))
        #expect(result.findings == [PreviewFinding(kind: .notebookUnexecutedCells, count: 1, detail: .cells([2])),
                                    PreviewFinding(kind: .notebookMayNotReproduce, count: 1)])
        #expect(result.findings.allSatisfy { $0.lines.isEmpty })
    }

    @Test func rawUnescapedControlsRemainMalformedEvenInsideImagePayloads() {
        let text = source(payload: "\"before\u{0}after\"")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(text) }
    }

    @Test func outputCeilingAppliesAfterImageOmission() throws {
        let image = #"""# + TestImages.noisePNG(128, 128).base64EncodedString() + #"""#
        let result = try parse(source(payload: image), budget: PreviewBudget(maxInputBytes: 16_777_216,
                                                                           maxOutputUTF8Bytes: 512, maxMilliseconds: 30_000))
        #expect(result.text.utf8.count <= 512)
        #expect(result.images.count == 1)
    }

    @Test func longCodeStreamAndMetadataKeepTheirLineFailures() {
        let long = String(repeating: "x", count: 40_000)
        let stream = #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"stream","text":""#
            + long + #""}]}]}"#
        let values = [source(payload: #""bad""#, before: long),
                      stream,
                      source(payload: #""bad""#).replacingOccurrences(of: "Figure", with: long),
                      source(payload: #""bad""#).replacingOccurrences(of: "é 😀", with: long)]
        for text in values { #expect(throws: PreviewFailure.lineTooLong) { try parse(text) } }
    }

    @Test func rawGrammarAndStructureBudgetsBindBeforeImageWork() throws {
        let image = #"""# + TestImages.noisePNG(128, 128).base64EncodedString() + #"""#
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source(payload: image) + " trailing") }
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parse(source(payload: image), budget: PreviewBudget(maxInputBytes: 16_777_216, maxJSONNodes: 5, maxMilliseconds: 30_000))
        }
        #expect(throws: PreviewFailure.structureTooDeep) {
            try parse(source(payload: image), budget: PreviewBudget(maxInputBytes: 16_777_216, maxJSONDepth: 3, maxMilliseconds: 30_000))
        }
    }

    @Test func activeImageParsingStopsAtInjectedCancellation() async throws {
        let text = source(payload: #"""# + TestImages.noisePNG(128, 128).base64EncodedString() + #"""#)
        try await CancellationTest.expectStopsActiveParse(budget: budget) { context in
            try JupyterNotebookAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
        }
    }
}
