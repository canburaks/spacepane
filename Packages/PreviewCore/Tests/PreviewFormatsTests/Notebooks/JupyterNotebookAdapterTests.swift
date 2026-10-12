import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parse(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try JupyterNotebookAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                       context: RequestContext(budget: budget))
}

/// Deterministic notebook JSON built from plain values, so tests never depend on hand-escaped text.
private func notebook(cells: [[String: Any]], nbformat: Any = 4, extra: [String: Any] = [:]) throws -> String {
    var object: [String: Any] = ["nbformat": nbformat, "nbformat_minor": 5, "metadata": [String: Any](), "cells": cells]
    object.merge(extra) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

private func code(_ source: Any, outputs: [[String: Any]] = []) -> [String: Any] {
    ["cell_type": "code", "metadata": [String: Any](), "execution_count": 1, "source": source, "outputs": outputs]
}

private func markdown(_ source: Any) -> [String: Any] { ["cell_type": "markdown", "metadata": [String: Any](), "source": source] }

/// Raw spans the adapter asks the shared filter to conceal, in source order.
private func concealedSpans(_ document: ParsedTextDocument) -> [String] {
    let bytes = Array(document.text.utf8)
    return document.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
}

@Suite("Jupyter notebook adapter")
struct JupyterNotebookAdapterTests {
    // MARK: Accepted notebooks

    @Test func validNotebookKeepsExactUnicodeSourceAndStructuredJSONPrivacy() throws {
        let source = try notebook(cells: [
            markdown("# Title 😀\nProse"),
            code(["print('héllo')\n", "x = '\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}'"],
                 outputs: [["output_type": "stream", "name": "stdout", "text": ["héllo\n"]]]),
            ["cell_type": "raw", "metadata": [String: Any](), "source": "raw text"]
        ])
        let result = try parse(source)
        #expect(result.text.utf8.elementsEqual(source.utf8))
        #expect(result.syntax == .json)
        #expect(result.usesStructuredPrivacy)
        #expect(result.sensitiveRanges.isEmpty)
    }

    @Test func escapedSurrogatePairsAndEscapedKeysAreDecodedForPrivacy() throws {
        // 😀 is one scalar; "password" decodes to a sensitive key.
        let source = #"{"nbformat":4,"cells":[{"cell_type":"code","source":"😀 password = 1"}]}"#
        let result = try parse(source)
        #expect(concealedSpans(result) == [#""😀 password = 1""#])
    }

    @Test func minimalNotebookWithoutOptionalFieldsIsAccepted() throws {
        let source = #"{"nbformat":4,"cells":[{"cell_type":"code","source":[]}]}"#
        #expect(try parse(source).text == source)
        #expect(try parse(#"{"nbformat":4,"cells":[]}"#).sensitiveRanges.isEmpty)
    }

    @Test func registrationAndCatalogBindTheNotebookIdentity() {
        #expect(StandardFormatAdapters.registrations.contains { $0.formatID == .jupyterNotebook })
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/analysis.ipynb")) == .jupyterNotebook)
    }

    // MARK: Rejected variants and shapes

    @Test(arguments: [
        #"{"nbformat":3,"nbformat_minor":0,"worksheets":[{"cells":[]}]}"#,
        #"{"nbformat":2,"cells":[]}"#,
        #"{"nbformat":5,"cells":[]}"#,
        #"{"nbformat":4.0,"cells":[]}"#,
        #"{"nbformat":40,"cells":[]}"#,
        #"{"nbformat":-4,"cells":[]}"#
    ])
    func otherNotebookVersionsAreUnsupportedNotApproximated(source: String) {
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse(source) }
    }

    @Test(arguments: [
        "[]", "{}", "null", #""text""#,
        #"{"cells":[]}"#,
        #"{"nbformat":"4","cells":[]}"#,
        #"{"nbformat":4}"#,
        #"{"nbformat":4,"cells":{}}"#,
        #"{"nbformat":4,"cells":[1]}"#,
        #"{"nbformat":4,"cells":[{"source":""}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"heading","source":""}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":5,"source":""}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code"}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":7}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":["a",1]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":{}}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{}]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"stream","text":4}]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"execute_result","data":[]}]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"error","traceback":["a",2]}]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"error","ename":3}]}]}"#,
        #"{"nbformat":4,"nbformat_minor":"x","cells":[]}"#,
        #"{"nbformat":4,"nbformat_minor":-1,"cells":[]}"#,
        #"{"nbformat":4,"nbformat_minor":05,"cells":[]}"#,
        #"{"nbformat":4,"cells":[],"cells":[]}"#,
        #"{"nbformat":4,"nbformat":4,"cells":[]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","cell_type":"raw","source":""}]}"#
    ])
    func wrongNotebookShapesAreMalformed(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
    }

    @Test(arguments: ["", "{", #"{"nbformat":4,"cells":[}"#, #"{"nbformat":4,"cells":[],}"#, #"{"nbformat":4,"cells":[]} x"#,
                      #"{"nbformat":4,"cells":["\q"]}"#, #"{"nbformat":4,"cells":["\ud800"]}"#])
    func malformedJSONIsRejectedBeforeShapeValidation(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
    }

    @Test func unknownOutputTypesAndExtraFieldsAreAcceptedAsInertData() throws {
        let source = try notebook(cells: [code("", outputs: [["output_type": "future_type", "payload": [1, 2]]])],
                                  extra: ["widgets": ["application/vnd.jupyter.widget-state+json": ["state": [String: Any]()]]])
        #expect(try parse(source).text == source)
    }

    // MARK: Budgets, cancellation and deadline

    @Test func structureAndInputBudgetsApplyBeforeAnyPreview() throws {
        let source = try notebook(cells: [code(["a\n", "b\n"])])
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(source, budget: PreviewBudget(maxInputBytes: 16)) }
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(source, budget: PreviewBudget(maxJSONDepth: 3)) }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(source, budget: PreviewBudget(maxJSONNodes: 5)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parse(source, budget: PreviewBudget(maxLineUTF8Bytes: 8)) }
        #expect(throws: PreviewFailure.tooManyLines) {
            try parse("{\n\"nbformat\":4,\n\"cells\":[]\n}", budget: PreviewBudget(maxTextLines: 3))
        }
    }

    @Test func embeddedImageBeyondTheLineBudgetBecomesAnInertPlaceholder() throws {
        let payload = String(repeating: "A", count: 40_000)
        let source = try notebook(cells: [code("", outputs: [["output_type": "display_data", "metadata": [String: Any](),
                                                              "data": ["image/png": payload]]])])
        let result = try parse(source)
        #expect(result.origin == .converted)
        #expect(result.images.isEmpty)
        #expect(!result.text.contains(payload))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
        let cells = try #require(root["cells"] as? [[String: Any]])
        let outputs = try #require(cells[0]["outputs"] as? [[String: Any]])
        let data = try #require(outputs[0]["data"] as? [String: Any])
        #expect(data["image/png"] is NSNull)
    }

    @Test func deadlineIsHonoredWhileParsing() async throws {
        let source = try notebook(cells: (0..<200).map { code(["line \($0)\n"]) })
        let context = RequestContext(budget: PreviewBudget(maxMilliseconds: 1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try JupyterNotebookAdapter().parse(DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        }
    }

    @Test func cancellationStopsParsing() async throws {
        let source = try notebook(cells: (0..<200).map { code(["line \($0)\n"]) })
        let task = Task { () throws -> ParsedTextDocument in
            while !Task.isCancelled { await Task.yield() }
            return try parse(source)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Privacy

    @Test func assignmentInOneCodeLineConcealsOnlyThatLineToken() throws {
        let source = try notebook(cells: [code(["import os\n", "password = \"synthetic-secret\"\n", "print(42)\n"])])
        let result = try parse(source)
        #expect(concealedSpans(result) == [#""password = \"synthetic-secret\"\n""#])
        for span in concealedSpans(result) { _ = try JSONSerialization.jsonObject(with: Data(span.utf8), options: .fragmentsAllowed) }
    }

    @Test func singleStringSourceConcealsTheWholeCellString() throws {
        let source = try notebook(cells: [code("import os\nAPI_KEY = 'synthetic'\nprint(1)")])
        let spans = concealedSpans(try parse(source))
        #expect(spans.count == 1)
        #expect(spans[0].hasPrefix("\"import os") && spans[0].hasSuffix("print(1)\""))
    }

    @Test func secretsInStreamResultErrorMarkdownAndRawContentAreConcealed() throws {
        let ansi = "\u{1B}[0;32m----> 1\u{1B}[0m password\u{1B}[0m \u{1B}[0;34m=\u{1B}[0m \u{1B}[0;34m'synthetic'\u{1B}[0m"
        let source = try notebook(cells: [
            code("", outputs: [
                ["output_type": "stream", "name": "stdout", "text": ["ok\n", "token: synthetic\n"]],
                ["output_type": "execute_result", "execution_count": 2, "metadata": [String: Any](),
                 "data": ["text/plain": ["{'client_secret': 'synthetic'}"]]],
                ["output_type": "error", "ename": "HTTPError", "evalue": "Authorization: Bearer synthetic",
                 "traceback": ["Traceback (most recent call last)", ansi, "HTTPError"]]
            ]),
            markdown(["# Notes\n", "api_key: synthetic\n", "Plain prose."]),
            ["cell_type": "raw", "metadata": [String: Any](), "source": ["export SECRET_TOKEN=synthetic\n"]]
        ])
        let spans = concealedSpans(try parse(source))
        #expect(spans.count == 6)
        for expected in ["token: synthetic", "client_secret", "Authorization: Bearer synthetic", "password", "api_key: synthetic", "SECRET_TOKEN"] {
            #expect(spans.contains { $0.contains(expected) }, "missing concealment for \(expected)")
        }
        #expect(!spans.contains { $0.contains("Traceback (most recent call last)") || $0.contains("Plain prose.") || $0.contains("# Notes") })
    }

    @Test func keyBasedMetadataAndTokenRangesAreMergedWithoutDuplicates() throws {
        let source = try notebook(cells: [code(["password = 'x'\n"])], extra: ["metadata": ["token": "abc", "title": "ok"]])
        let result = try parse(source)
        #expect(concealedSpans(result).sorted() == [#""abc""#, #""password = 'x'\n""#].sorted())
        // A token inside a concealed sensitive-key value is covered once, by the larger range.
        let nested = try notebook(cells: [code("")], extra: ["metadata": ["credentials": ["note": "password = 1"]]])
        let spans = concealedSpans(try parse(nested))
        #expect(spans.count == 1)
        #expect(spans[0].hasPrefix("{") && spans[0].contains("password = 1"))
    }

    @Test func nonSensitiveStringsAreUntouched() throws {
        let source = try notebook(cells: [
            markdown("The password manager stores tokens. Time: 5"),
            code(["x = 1\n", "d = {'max_len': 3, 'name': 'a'}\n", "print('ratio: 2')\n", "url = 'https://example.invalid/a?b=c'"])
        ])
        #expect(concealedSpans(try parse(source)).isEmpty)
    }

    @Test(arguments: [
        "--password=synthetic",
        "os.environ[\"API_TOKEN\"] = 'x'",
        "config['secret']: value",
        "curl 'https://example.invalid/?access_token=abc'"
    ])
    func commandFlagsSubscriptsAndQueryStringsAreRecognized(line: String) throws {
        let source = try notebook(cells: [code(["ok\n", line + "\n", "done\n"])])
        #expect(concealedSpans(try parse(source)).count == 1)
    }

    @Test func valuesThatContinuePastTheirLineConcealFollowingLines() throws {
        let source = try notebook(cells: [code([
            "before = 1\n",
            "password = \"\"\"line one\n",
            "line two\n",
            "line three\"\"\"\n",
            "tail = 2"
        ])])
        let spans = concealedSpans(try parse(source))
        #expect(spans.count == 4)
        #expect(!spans.contains { $0.contains("before") })
        #expect(spans.contains { $0.contains("line three") } && spans.contains { $0.contains("tail = 2") })
    }

    @Test func unterminatedPrivateKeyBlockConcealsItsFollowingLinesAsWholeTokens() throws {
        let source = try notebook(cells: [code(["key = '''-----BEGIN PRIVATE KEY-----\n", "MIIBVgIBADANBgkq\n", "more\n"]), markdown("after")])
        let spans = concealedSpans(try parse(source))
        #expect(spans.count == 3)
        #expect(spans.allSatisfy { $0.hasPrefix("\"") && $0.hasSuffix("\"") })
    }

    @Test func aSensitiveKeyIsConcealedAsAWholeToken() throws {
        let source = #"{"nbformat":4,"cells":[],"metadata":{"password = x":1,"ok":2}}"#
        // The key is concealed as a whole token and, being sensitive by name, so is its value.
        #expect(concealedSpans(try parse(source)) == [#""password = x""#, "1"])
    }

    @Test func largeNotebookWithManyStringsStaysWithinCheckpointedWork() throws {
        let cells = (0..<150).map { _ in
            code((0..<40).map { "value_\($0) = \($0)\n" }, outputs: [
                ["output_type": "stream", "name": "stdout", "text": (0..<20).map { "line \($0)\n" }]
            ])
        }
        let source = try notebook(cells: cells)
        let result = try parse(source)
        #expect(result.text == source)
        #expect(result.sensitiveRanges.isEmpty)
    }
}
