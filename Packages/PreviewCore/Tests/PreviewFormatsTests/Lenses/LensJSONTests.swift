import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func parse(_ text: String, budget: PreviewBudget = .standard) throws -> LensJSONNode? {
    try LensJSON.parse(text, context: RequestContext(budget: budget))
}

private func root(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> LensJSONNode {
    try #require(try parse(text), "expected a document", sourceLocation: sourceLocation)
}

@Suite("Lens JSON reader")
struct LensJSONTests {
    // MARK: Structure and lines

    @Test func recordsTheLineOfEveryValueAndKey() throws {
        let node = try root("""
        {
          "a": 1,
          "list": [
            true,
            null
          ],
          "nested": {"deep": "x"}
        }
        """)
        #expect(node.line == 1)
        #expect(node.member("a")?.line == 2)
        #expect(node.member("list")?.line == 3)
        #expect(node.member("list")?.value.line == 3)
        #expect(node.member("list")?.value.elements?.map(\.line) == [4, 5])
        #expect(node.member("nested")?.line == 7)
        #expect(node.member("nested")?.value.member("deep")?.line == 7)
        #expect(node.member("a")?.value.number == 1)
        #expect(node.member("list")?.value.elements?.first?.bool == true)
        #expect(node.member("list")?.value.elements?.last?.isNull == true)
        #expect(node.member("nested")?.value.member("deep")?.value.string == "x")
    }

    /// Every break the gutter counts moves the line by one, CRLF once; the reader and `LogicalLines` agree.
    @Test(arguments: ["\n", "\r\n", "\r", "\u{85}"])
    func lineBreaksFollowTheGutterDefinition(separator: String) throws {
        let text = ["{", "\"a\": 1,", "", "\"b\": 2,", "\"c\": 3", "}"].joined(separator: separator)
        let node = try root(text)
        for key in ["a", "b", "c"] {
            let offset = try #require(text.range(of: "\"\(key)\"")).lowerBound.utf16Offset(in: text)
            let expected = try #require(LogicalLines.lineNumbers(forUTF16Offsets: [offset], in: text).first)
            #expect(node.member(key)?.line == expected, "key \(key)")
        }
        #expect(node.member("c")?.line == 5)
    }

    @Test func separatorsInsideStringsCommentsAndContinuationsCountAsLines() throws {
        let text = "{\"a\": \"x\u{2028}y\",\n/* one\ntwo\u{2029}three */\n\"b\": 'line \\\r\nnext',\n// comment\n\"c\": 1}"
        let node = try root(text)
        for key in ["a", "b", "c"] {
            let offset = try #require(text.range(of: "\"\(key)\"")).lowerBound.utf16Offset(in: text)
            #expect(node.member(key)?.line == LogicalLines.lineNumbers(forUTF16Offsets: [offset], in: text).first, "key \(key)")
        }
        #expect(node.member("b")?.value.string == "line next")
    }

    // MARK: Tolerated syntax

    @Test func toleratesCommentsTrailingCommasSingleQuotesUnquotedKeysAndABOM() throws {
        let node = try root("""
        \u{FEFF}// header
        {
          /* block */ unquoted: 'single',
          "list": [1, 2, ],
          "last": {"k": true,},
        }
        """)
        #expect(node.member("unquoted")?.value.string == "single")
        #expect(node.member("unquoted")?.line == 3)
        #expect(node.member("list")?.value.elements?.count == 2)
        #expect(node.member("last")?.value.member("k")?.value.bool == true)
    }

    @Test func decodesEscapesInKeysAndValues() throws {
        let node = try root(#"{"pa\u0073s": "line\nbreak \ud83d\ude00", "q\"uote": "\\"}"#)
        #expect(node.member("pass")?.value.string == "line\nbreak \u{1F600}")
        #expect(node.member("q\"uote")?.value.string == "\\")
    }

    @Test func acceptsTheConcealmentTokenWhereAValueWas() throws {
        let token = SecretFieldPolicy.concealmentToken
        let node = try root("{\"password\": \(token), \"items\": [\(token), 1], \"secret\":\(token)}")
        #expect(node.member("password")?.value.isConcealed == true)
        #expect(node.member("password")?.value.hasContent == true)
        #expect(node.member("items")?.value.elements?.first?.isConcealed == true)
        #expect(node.member("secret")?.value.isConcealed == true)
    }

    @Test func numbersKeepTheirValue() throws {
        let node = try root("[0, -3, 2.5, 1e3, 0x10]")
        #expect(node.elements?.compactMap(\.number) == [0, -3, 2.5, 1000, 16])
    }

    // MARK: Lookups

    @Test func lastDuplicateKeyWins() throws {
        let node = try root(#"{"a": 1, "a": 2}"#)
        #expect(node.member("a")?.value.number == 2)
    }

    @Test func keysCompareByCodeUnits() throws {
        // U+212A KELVIN SIGN is canonically equivalent to "K" in Swift, but not the same key in a file.
        let node = try root("{\"\u{212A}eepAlive\": true}")
        #expect(node.member("KeepAlive") == nil)
        #expect(node.member("\u{212A}eepAlive") != nil)
        #expect(!"\u{212A}".equalsExactly("K"))
    }

    @Test func hasContentIgnoresEmptyValues() throws {
        let node = try root(#"{"a": null, "b": "", "c": [], "d": {}, "e": "x", "f": 0, "g": false, "h": [1]}"#)
        let expected = ["a": false, "b": false, "c": false, "d": false, "e": true, "f": true, "g": true, "h": true]
        for (key, hasContent) in expected {
            #expect(node.member(key)?.value.hasContent == hasContent, "key \(key)")
        }
    }

    // MARK: Malformed input

    @Test(arguments: [
        "", "   ", "{", "[", "{\"a\"", "{\"a\":", "{\"a\": }", "{\"a\" 1}", "{,}", "[,]", "[1 2]", "{\"a\": 1,, }",
        "true false", "{\"a\": 1} x", "\"open", "{\"a\": 'x\"}", "/* open", "{\"a\": tru}", "{\"a\": 1.2.3}",
        "{\"a\": \"\\u12\"}", "{\"a\": \"\\ud800\"}", "}", "]", ":"
    ])
    func malformedDocumentsProduceNothing(text: String) throws {
        #expect(try parse(text) == nil)
    }

    @Test func documentsBeyondTheBudgetsProduceNothing() throws {
        #expect(try parse("[[1]]", budget: PreviewBudget(maxJSONDepth: 3)) != nil)
        #expect(try parse("[[[1]]]", budget: PreviewBudget(maxJSONDepth: 3)) == nil)
        #expect(try parse("[1,2,3]", budget: PreviewBudget(maxJSONNodes: 4)) != nil)
        #expect(try parse("[1,2,3,4]", budget: PreviewBudget(maxJSONNodes: 4)) == nil)
    }

    @Test func deepNestingFailsInsteadOfOverflowingTheStack() throws {
        let text = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(try parse(text) == nil)
    }

    // MARK: Cancellation

    @Test func cancellationStopsAnActiveRead() async throws {
        var text = "{\n"
        for index in 0..<400 { text += "  \"key\(index)\": {\"a\": [1, 2, 3], \"b\": \"value\"},\n" }
        text += "  \"end\": null\n}\n"
        let source = text
        let completed = try await CancellationTest.expectStopsActiveParse(budget: PreviewBudget(maxJSONNodes: 20_000)) { context in
            let node = try LensJSON.parse(source, context: context)
            return ParsedTextDocument(text: node == nil ? "" : "parsed")
        }
        #expect(completed.text == "parsed")
    }
}
