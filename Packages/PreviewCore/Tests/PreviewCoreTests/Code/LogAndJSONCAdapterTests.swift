import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private let secret = "synthetic-secret-value"

private func concealed(_ adapter: some FormatAdapter, _ text: String, budget: PreviewBudget = .standard) throws -> (parsed: ParsedTextDocument, safe: SafeText) {
    let context = RequestContext(budget: budget)
    let parsed = try adapter.parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
    return (parsed, try DefaultPrivacyFilter().filter(parsed, context: context))
}

@Suite("Log adapter")
struct LogAdapterTests {
    private func safe(_ text: String) throws -> SafeText { try concealed(LogAdapter(), text).safe }

    @Test func ordinaryLogsKeepTheirExactTextAndSyntax() throws {
        let source = "2026-10-05T12:00:00Z INFO service started\n2026-10-05T12:00:01Z ERROR request failed\n\tat example.Service.run(Service.java:42)\n"
        let (parsed, result) = try concealed(LogAdapter(), source)
        #expect(parsed.syntax == .log && parsed.text == source)
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
    }

    @Test(arguments: [
        "Authorization: Bearer \(secret)",
        "request headers {authorization=Basic \(secret)}",
        "login failed password=\(secret) user=ann",
        "\"password\": \"\(secret)\"",
        "GET /cb?access_token=\(secret)&state=1",
        "Cookie: session=\(secret); theme=dark",
        "Set-Cookie: sid=\(secret); HttpOnly",
        "connect postgres://app:\(secret)@db.example.test/main",
        "run --password \(secret) --verbose",
        "token: \(secret)"
    ]) func credentialsInLogLinesAreConcealed(line: String) throws {
        let result = try safe("2026-10-05 12:00:00 INFO before\n\(line)\n2026-10-05 12:00:02 INFO after\n")
        #expect(!result.text.contains(secret), "\(line)")
        #expect(result.redactionCount > 0)
        // Neighbouring lines stay readable: a log secret ends at its line.
        #expect(result.text.contains("INFO before") && result.text.contains("INFO after"))
    }

    @Test func aPromptWithoutAValueDoesNotConcealTheRestOfTheFile() throws {
        let result = try safe("Enter password:\nthe installer continues\nnext line\n")
        #expect(result.text == "Enter password:\nthe installer continues\nnext line\n")
        #expect(result.redactionCount == 0)
    }

    @Test func stackFramesWithSecretWordsKeepTheirLineNumbers() throws {
        let source = "\tat org.shiro.PasswordMatcher.verify(PasswordMatcher.java:73)\n\tat app.TokenService.issue (token.js:10:5)\n\t/work/token.go:12 +0x1d\n"
        let result = try safe(source)
        #expect(result.text == source)
    }

    @Test func aLineThatOnlyLooksLikeAFrameIsStillConcealed() throws {
        let result = try safe("at password:\(secret)\n\tpassword:\(secret)\nat x (password=\(secret))\n")
        #expect(!result.text.contains(secret))
    }

    @Test func aBracketedValueContinuesUntilItIsBalanced() throws {
        let source = "2026-10-05 INFO credentials: {\n  \"user\": \"a\",\n  \"pass\": \"\(secret)\"\n}\n2026-10-05 INFO after\n"
        let result = try safe(source)
        #expect(!result.text.contains(secret))
        #expect(!result.text.contains("\"user\""))
        #expect(result.text.contains("INFO after"))
    }

    @Test func recognizableTokensAreConcealedWithoutAKey() throws {
        let result = try safe("2026-10-05 INFO using ghp_abcdefghijklmnopqrstuvwxyz0123456789 for sync\n")
        #expect(!result.text.contains("ghp_abcdefghijklmnopqrstuvwxyz"))
    }

    @Test func manyRangesCollapseToWholeTextConcealmentInsteadOfFailing() throws {
        let source = (0..<40).map { "password=v\($0)" }.joined(separator: "\n")
        let result = try concealed(LogAdapter(), source, budget: PreviewBudget(maxJSONNodes: 10)).safe
        #expect(!result.text.contains("v39"))
    }

    @Test func policyIsLineBasedPartialReading() {
        #expect(LogAdapter().textInputPolicy == .leadingRecords(.line))
    }
}

@Suite("JSON with comments adapter")
struct JSONCAdapterTests {
    private func parse(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
        try JSONCAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: RequestContext(budget: budget))
    }

    @Test(arguments: [
        "{\n  // line comment\n  \"a\": 1, /* block */ \"b\": [1, 2, 3,],\n}\n",
        "{unquoted: 'single', $dollar: 0xFF, _under: .5, trailing: 5., plus: +1, neg: -Infinity, nan: NaN}",
        "[1, 2, 3, ]",
        "'string'",
        "{\"line\": \"continued \\\n value\"}",
        "{\"escape\": \"\\x41\\v\\0\\u0041\"}",
        "// only a comment before\nnull",
        "{\"a\": {}, \"b\": [], \"c\": [[], {}]}",
        "\u{FEFF}{}",
        "{ \"nbsp\":\u{00A0}1 }"
    ]) func lenientDocumentsKeepTheirExactSource(source: String) throws {
        let parsed = try parse(source)
        #expect(parsed.text == source)
        #expect(parsed.syntax == .jsonWithComments)
        #expect(parsed.usesStructuredPrivacy)
    }

    @Test(arguments: [
        "", "   ", "// only a comment", "{", "[1,", "{\"a\" 1}", "{\"a\":}", "{,}", "[,]", "[1,,2]", "{a b: 1}",
        "{\"a\": undefined}", "{\"a\": 01x}", "/* unterminated", "{\"a\": \"\n\"}", "{\"a\": 'x\"}", "{\"a\": \"\\9\"}",
        "{\"a\": \"\\uD800\"}", "[1] 2", "{\"a\": 1} }", "{'a': 1 'b': 2}", "[1 2]"
    ]) func malformedDocumentsAreRejectedWithoutARawFallback(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
    }

    @Test func structuralBudgetsApplyBeforeUnboundedParsing() {
        #expect(throws: PreviewFailure.structureTooDeep) { try parse("[[[1]]]", budget: PreviewBudget(maxJSONDepth: 3)) }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse("[1,2,3]", budget: PreviewBudget(maxJSONNodes: 3)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(String(repeating: " ", count: 65), budget: PreviewBudget(maxInputBytes: 64)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parse(String(repeating: " ", count: 65), budget: PreviewBudget(maxLineUTF8Bytes: 64)) }
        let deep = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(deep) }
    }

    @Test func valuesOfSecretKeysAreConcealedWhateverTheKeySyntax() throws {
        let source = """
        {
          "password": "\(secret)-1",
          'api_key': '\(secret)-2',
          token: ["\(secret)-3", {nested: 1}],
          "pa\\u0073sword2": "\(secret)-4", // note
          secret_key: 0xDEADBEEF,
          name: "visible",
        }
        """
        let result = try concealed(JSONCAdapter(), source).safe
        #expect(!result.text.contains(secret))
        #expect(!result.text.contains("0xDEADBEEF"))
        #expect(result.text.contains("\"visible\""))
        #expect(result.redactionCount == 5)
    }

    @Test func commentsThatAssignASecretAreConcealedButTheirDelimitersStay() throws {
        let result = try concealed(JSONCAdapter(), "{\n// password = \(secret)\n\"a\": 1 /* token: \(secret) */\n}").safe
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("//") && result.text.contains("/*") && result.text.contains("*/"))
        #expect(result.text.contains("\"a\": 1"))
    }

    @Test func cancellationAndDeadlinePrecedeAnyInputAccess() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try JSONCAdapter().parse(.init(text: "", encoding: .utf8, byteCount: 0), context: .init(budget: .standard)); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try JSONCAdapter().parse(.init(text: "", encoding: .utf8, byteCount: 0), context: .init(budget: .init(maxMilliseconds: 0)))
        }
    }
}

@Suite("Minified JSON reformatting")
struct MinifiedJSONTests {
    private func format(_ text: String, budget: PreviewBudget = PreviewBudget(maxLineUTF8Bytes: 64)) throws -> ParsedTextDocument {
        try JSONSourceAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: RequestContext(budget: budget))
    }

    @Test func aLongLineIsPrettyPrintedAndMarkedAsReformatted() throws {
        let source = #"{"name":"a long enough value to pass the line budget","items":[1,2,3],"nested":{"x":true,"y":null},"empty":{},"list":[]}"#
        #expect(source.utf8.count > 64)
        let parsed = try format(source)
        #expect(parsed.isReformatted && parsed.syntax == .json && parsed.usesStructuredPrivacy)
        #expect(parsed.text == """
        {
          "name": "a long enough value to pass the line budget",
          "items": [1, 2, 3],
          "nested": {
            "x": true,
            "y": null
          },
          "empty": {},
          "list": []
        }
        """)
    }

    @Test func formattedTextIsStructurallyEquivalentToTheSource() throws {
        let source = #"{"b":[{"k":"v","n":-0.5e+3},[true,false,null],"x\u00e9\n\"q\""],"a":{"d":{"e":{"f":[]}}},"big":9007199254740993123456789,"s":"padding padding padding padding padding"}"#
        let parsed = try format(source)
        let original = try JSONSerialization.jsonObject(with: Data(source.utf8), options: [.fragmentsAllowed])
        let reformatted = try JSONSerialization.jsonObject(with: Data(parsed.text.utf8), options: [.fragmentsAllowed])
        #expect((original as AnyObject).isEqual(reformatted))
        // Key order, number lexemes and escapes are preserved byte for byte.
        #expect(parsed.text.contains("\"b\"") && parsed.text.range(of: "\"b\"")!.lowerBound < parsed.text.range(of: "\"a\"")!.lowerBound)
        #expect(parsed.text.contains("9007199254740993123456789") && parsed.text.contains("-0.5e+3") && parsed.text.contains("\\u00e9"))
        #expect(parsed.text.contains(#""x\u00e9\n\"q\"""#))
    }

    @Test func duplicateKeysAndDocumentsThatAreScalarsSurvive() throws {
        let parsed = try format(#"{"k":1,"k":2,"a":"padding padding padding padding","b":"padding padding padding padding"}"#)
        #expect(parsed.text.contains("\"k\": 1") && parsed.text.contains("\"k\": 2"))
        let scalar = try format("\"" + String(repeating: "x", count: 70) + "\"", budget: PreviewBudget(maxLineUTF8Bytes: 80))
        #expect(!scalar.isReformatted)
    }

    @Test func structuralConcealmentCarriesOverToTheFormattedText() throws {
        let source = #"{"user":"visible","password":"\#(secret)","creds":{"token":["\#(secret)","two"],"keep":1},"tail":"padding padding padding padding"}"#
        let parsed = try format(source)
        #expect(parsed.isReformatted)
        let bytes = Array(parsed.text.utf8)
        let hidden = parsed.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }.sorted()
        #expect(hidden == [#"["\#(secret)","two"]"#.replacingOccurrences(of: "\",\"", with: "\", \""), "\"\(secret)\""].sorted())
        let safe = try DefaultPrivacyFilter().filter(parsed, context: RequestContext(budget: PreviewBudget(maxLineUTF8Bytes: 64)))
        #expect(!safe.text.contains(secret))
        #expect(safe.text.contains("\"user\": \"visible\"") && safe.text.contains("\"keep\": 1"))
    }

    @Test func sourcesWhoseLinesFitAreNeverReformatted() throws {
        let source = "{\"a\":1}\n"
        let parsed = try format(source, budget: .standard)
        #expect(parsed.text == source && !parsed.isReformatted)
    }

    @Test func formattedOutputHonorsTheOutputLineAndStructureBudgets() {
        let wide = "[" + (0..<100).map { "{\"n\":\($0)}" }.joined(separator: ",") + "]"
        #expect(throws: PreviewFailure.tooManyLines) { try format(wide, budget: PreviewBudget(maxTextLines: 50, maxLineUTF8Bytes: 64)) }
        let giantString = "{\"s\":\"" + String(repeating: "x", count: 200) + "\"}"
        #expect(throws: PreviewFailure.lineTooLong) { try format(giantString) }
        #expect(throws: PreviewFailure.outputTooLarge) { try format(wide, budget: PreviewBudget(maxOutputUTF8Bytes: 400, maxLineUTF8Bytes: 399)) }
        #expect(throws: PreviewFailure.malformedDocument) { try format("{\"a\":" + String(repeating: "x", count: 80) + "}") }
    }

    @Test func policyDeclaresLongLinesAndNoPartialRead() {
        let policy = JSONSourceAdapter().textInputPolicy
        #expect(policy.allowsLongLines && policy.partialBoundary == nil)
    }
}
