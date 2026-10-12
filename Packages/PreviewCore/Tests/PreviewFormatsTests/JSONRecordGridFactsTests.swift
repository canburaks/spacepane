import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parseJSONRecords(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try JSONSourceAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                  context: RequestContext(budget: budget))
}

@Suite("JSON record-array shape facts")
struct JSONRecordGridFactsTests {
    @Test func heterogeneousRootRecordsCountTheirExactUnionWithoutNestedColumns() throws {
        let source = #"[{"id":1,"name":"Ada","nested":{"a":1,"a":2}},{"id":2,"note":"ordinary"},{"id":3}]"#
        let document = try parseJSONRecords(source)
        #expect(document.text == source)
        #expect(document.facts == PresentationFacts([.grid(rows: 3, columns: 4, rowsAreLowerBound: false)]))
    }

    @Test func canonicallyEquivalentKeysRemainDistinctCodeUnits() throws {
        let source = #"[{"\u00e9":1,"e\u0301":2},{"\u00e9":3}]"#
        #expect(try parseJSONRecords(source).facts == PresentationFacts([.grid(rows: 2, columns: 2, rowsAreLowerBound: false)]))
    }

    @Test func identicalDecodedDuplicateKeysKeepOnlyAnUnambiguousRecordCount() throws {
        let source = #"[{"id":1,"\u0069d":2,"name":"Ada"},{"id":3}]"#
        let document = try parseJSONRecords(source)
        #expect(document.text == source, "Duplicate keys remain valid exact source, even when a grid cannot represent them")
        #expect(document.facts == PresentationFacts([.records(2, .records)]))
    }

    @Test func theDistinctKeyLimitRetainsExactCountsAtItsBoundaryAndFallsBackAboveIt() throws {
        func object(_ keys: Range<Int>) -> String { "{" + keys.map { "\"field\($0)\":\($0)" }.joined(separator: ",") + "}" }
        let boundary = "[" + object(0..<128) + "," + object(128..<256) + "]"
        #expect(try parseJSONRecords(boundary).facts == PresentationFacts([.grid(rows: 2, columns: 256, rowsAreLowerBound: false)]))
        let overflow = "[" + object(0..<256) + "," + object(256..<257) + "]"
        #expect(try parseJSONRecords(overflow).facts == PresentationFacts([.records(2, .records)]))
    }

    @Test(arguments: [#"{"rows":[{"id":1}]}"#, #"[{"id":1},2]"#, #"[null,{"id":1}]"#, #"[[{"id":1}]]"#, "[]", "42"])
    func onlyAProvenRootArrayOfObjectsProducesRecordFacts(source: String) throws {
        #expect(try parseJSONRecords(source).facts == .none)
    }

    @Test func emptyRecordsHaveNoInventedColumns() throws {
        #expect(try parseJSONRecords("[{},{}]").facts == PresentationFacts([.records(2, .records)]))
        #expect(try parseJSONRecords(#"[{}, {"id":1}]"#).facts == PresentationFacts([.grid(rows: 2, columns: 1, rowsAreLowerBound: false)]))
    }

    @Test func reformattingPreservesTheSameParserFacts() throws {
        let source = "[{" + (0..<6).map { "\"f\($0)\":\($0)" }.joined(separator: ",") + "},{\"f0\":7}]"
        let document = try parseJSONRecords(source, budget: PreviewBudget(maxLineUTF8Bytes: 24))
        #expect(document.isReformatted && document.origin == .reformatted)
        #expect(document.facts == PresentationFacts([.grid(rows: 2, columns: 6, rowsAreLowerBound: false)]))
    }

    @Test func countingDoesNotReplaceStructuredCredentialAnnotations() throws {
        let source = #"[{"id":1,"pa\u0073sword":"synthetic-private-value"},{"id":2,"note":"ordinary"}]"#
        let document = try parseJSONRecords(source)
        #expect(document.facts == PresentationFacts([.grid(rows: 2, columns: 3, rowsAreLowerBound: false)]))
        #expect(document.usesStructuredPrivacy && document.sensitiveRanges.count == 1)
        let range = try #require(document.sensitiveRanges.first).utf8Range
        #expect(String(decoding: Array(source.utf8)[range], as: UTF8.self) == #""synthetic-private-value""#)
    }

    @Test func recordTrackingDoesNotChangeJSONLinesOrBypassTheNodeBudget() throws {
        let text = #"[{"id":1}]"# + "\n" + #"{"id":2}"# + "\n"
        let document = try JSONLinesAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                                     context: RequestContext(budget: .standard))
        #expect(document.facts == .none && document.sourceRecordCount == 2)
        #expect(throws: PreviewFailure.tooManyNodes) { try parseJSONRecords(#"[{"id":1},{"id":2}]"#, budget: PreviewBudget(maxJSONNodes: 4)) }
    }
}
