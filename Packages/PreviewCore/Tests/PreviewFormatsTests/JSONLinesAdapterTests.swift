import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parseJSONLines(_ text: String, budget: PreviewBudget = .standard,
                            encoding: TextEncoding = .utf8, hasBOM: Bool = false) throws -> ParsedTextDocument {
    try JSONLinesAdapter().parse(DecodedText(text: text, encoding: encoding, byteCount: text.utf8.count,
                                           hasByteOrderMark: hasBOM), context: RequestContext(budget: budget))
}

@Test(arguments: ["\n", "\r\n"])
func JSONLinesPreservesNumbersDuplicateKeysAndTerminators(separator: String) throws {
    let first = #"{"number":9007199254740993123456789,"float":1.234567890123456789e999,"key":1,"key":2}"#
    let values = [first, "null", "true", "-0.00e+003", #""🌍""#, "[1,2]"]
    for finalNewline in [false, true] {
        let source = values.joined(separator: separator) + (finalNewline ? separator : "")
        let parsed = try parseJSONLines(source)
        #expect(parsed.text == source)
        #expect(parsed.usesStructuredPrivacy)
        #expect(parsed.syntax == .json)
    }
}

@Test(arguments: ["", "\n", "\r\n", " \t", "null\n\n", "null\n \t", "{}\n[1,]", "{}\ntrue false", "true\rfalse", "{\n\"x\":1\n}", #""\uD800""#, "\u{FEFF}{}"])
func JSONLinesRejectsBlankOrMalformedRecords(source: String) {
    #expect(throws: PreviewFailure.malformedDocument) { try parseJSONLines(source) }
}

@Test func JSONLinesRetainsAbsoluteUnicodeSensitiveRangesAcrossRecords() throws {
    let source = "{\"label\":\"é 🌍\",\"safe\":1}\r\n"
        + #"{"pa\u0073sword":"synthetic-one","safe":"日本語"}"# + "\r\n"
        + #"{"API_KEY":["synthetic-two","🌍"],"safe":true}"#
    let parsed = try parseJSONLines(source)
    let bytes = Array(source.utf8)
    let concealed = parsed.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
    #expect(concealed == [#""synthetic-one""#, #"["synthetic-two","🌍"]"#])
}

@Test func JSONLinesNodeBudgetIsCumulativeAcrossAllRecords() throws {
    #expect(try parseJSONLines("{}\n{}", budget: PreviewBudget(maxJSONNodes: 2)).text == "{}\n{}")
    #expect(throws: PreviewFailure.tooManyNodes) {
        try parseJSONLines("{}\n{}\n{}", budget: PreviewBudget(maxJSONNodes: 2))
    }
    #expect(throws: PreviewFailure.tooManyNodes) {
        try parseJSONLines("[1]\n[2]", budget: PreviewBudget(maxJSONNodes: 3))
    }
    #expect(throws: PreviewFailure.structureTooDeep) {
        try parseJSONLines("{}\n[[[1]]]", budget: PreviewBudget(maxJSONDepth: 3))
    }
}

@Test func JSONLinesBoundsRecordsLineBytesAndSourceBeforeScanning() {
    #expect(throws: PreviewFailure.tooManyLines) {
        try parseJSONLines("null\nnull\nnull", budget: PreviewBudget(maxTextLines: 2))
    }
    #expect(throws: PreviewFailure.lineTooLong) {
        try parseJSONLines(#""🌍🌍""#, budget: PreviewBudget(maxLineUTF8Bytes: 9))
    }
    #expect(throws: PreviewFailure.inputTooLarge) {
        try parseJSONLines("null\nnull", budget: PreviewBudget(maxInputBytes: 8))
    }
    #expect(throws: PreviewFailure.outputTooLarge) {
        try parseJSONLines("null\nnull", budget: PreviewBudget(maxOutputUTF8Bytes: 8))
    }
}

@Test(arguments: [TextEncoding.utf16LittleEndian, .utf16BigEndian])
func JSONLinesRequiresUTF8(encoding: TextEncoding) {
    #expect(throws: PreviewFailure.unsupportedEncoding) { try parseJSONLines("{}", encoding: encoding) }
}

@Test func JSONLinesRejectsConsumedBOMProvenance() {
    #expect(throws: PreviewFailure.malformedDocument) { try parseJSONLines("{}", hasBOM: true) }
}

@Test func JSONLinesCooperativeCancellationStopsActiveLargeSource() async throws {
    let record = "\"" + String(repeating: "a", count: 900_000) + "\""
    let source = Array(repeating: record, count: 12).joined(separator: "\n")
    let decoded = DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count)
    let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                               maxLineUTF8Bytes: 1_048_576, maxMilliseconds: 30_000)
    let completed = try await CancellationTest.expectStopsActiveParse(budget: budget) {
        try JSONLinesAdapter().parse(decoded, context: $0)
    }
    #expect(completed.text == source)
}
