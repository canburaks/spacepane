import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parse(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try JSONSourceAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                  context: RequestContext(budget: budget))
}

@Test func numbersAndDuplicateKeysRemainExactSource() throws {
    let source = #"{"big":9007199254740993123456789,"float":1.234567890123456789e999,"key":1,"key":2}"#
    #expect(try parse(source).text == source)
}

@Test(arguments: ["", "[1,]", "{\"x\":1,}", "01", "1.", "1e", "true false", #""\uD800""#, #""\uDC00""#, #"{"x":"\q"}"#])
func malformedJSONIsRejected(source: String) {
    #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
}

@Test func JSONStructureBudgetsRunBeforeUnboundedParsing() {
    #expect(throws: PreviewFailure.structureTooDeep) { try parse("[[[1]]]", budget: PreviewBudget(maxJSONDepth: 3)) }
    #expect(throws: PreviewFailure.tooManyNodes) { try parse("[1,2,3]", budget: PreviewBudget(maxJSONNodes: 3)) }
}

@Test func escapedSecretKeysAndCompositeValuesAreAnnotated() throws {
    let source = #"{"pa\u0073sword":"hidden","API_KEY":["one","two"],"safe":"visible"}"#
    let result = try parse(source)
    #expect(result.syntax == .json)
    #expect(result.sensitiveRanges.count == 2)
    #expect(result.usesStructuredPrivacy)
    let bytes = Array(source.utf8)
    #expect(String(decoding: bytes[result.sensitiveRanges[0].utf8Range], as: UTF8.self) == #""hidden""#)
    #expect(String(decoding: bytes[result.sensitiveRanges[1].utf8Range], as: UTF8.self) == #"["one","two"]"#)
}
