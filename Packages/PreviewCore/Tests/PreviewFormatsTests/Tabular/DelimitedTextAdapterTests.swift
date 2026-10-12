import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parse(_ text: String, _ dialect: DelimitedTextAdapter.Dialect = .comma, budget: PreviewBudget = .standard,
                   encoding: TextEncoding = .utf8, hasBOM: Bool = false) throws -> ParsedTextDocument {
    try DelimitedTextAdapter(dialect: dialect).parse(
        DecodedText(text: text, encoding: encoding, byteCount: text.utf8.count, hasByteOrderMark: hasBOM),
        context: RequestContext(budget: budget))
}

/// What the shared privacy filter does with structured ranges, minus its separate value heuristics.
private func concealed(_ document: ParsedTextDocument) -> String {
    var bytes = Array(document.text.utf8)
    for range in document.sensitiveRanges.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
        bytes.replaceSubrange(range.utf8Range, with: Array("••••".utf8))
    }
    return String(decoding: bytes, as: UTF8.self)
}

private func cells(_ text: String, _ dialect: DelimitedTextAdapter.Dialect = .comma) throws -> [[String]] {
    let bytes = Array(text.utf8)
    var result: [[String]] = []
    _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: .init(maxRecords: 10_000, maxFieldsPerRecord: 10_000, maxFieldBytes: 1_000_000),
                                  checkpoint: {}) { _, fields in
        result.append(fields.map { DelimitedRecords.text(of: $0, in: bytes) })
        return .proceed
    }
    return result
}

private func rawRanges(_ document: ParsedTextDocument) -> [String] {
    let bytes = Array(document.text.utf8)
    return document.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
}

@Suite("Delimited text adapter")
struct DelimitedTextAdapterTests {
    @Test func plainTablesKeepExactSourceAndDeclareStructuredPrivacy() throws {
        for (dialect, syntax, delimiter) in [(DelimitedTextAdapter.Dialect.comma, TextSyntax.commaSeparated, ","),
                                              (.tab, .tabSeparated, "\t")] {
            let source = "id\(delimiter)name\r\n1\(delimiter)Ada\r\n2\(delimiter)Grace\r\n"
            let result = try parse(source, dialect)
            #expect(result.text == source)
            #expect(result.syntax == syntax)
            #expect(result.usesStructuredPrivacy)
            #expect(result.sensitiveRanges.isEmpty)
        }
    }

    @Test func emptyAndBlankSourcesAreEmptyTablesNotFailures() throws {
        #expect(try parse("").sensitiveRanges.isEmpty)
        #expect(try parse("\n").text == "\n")
        #expect(try parse("\u{FEFF}").text == "\u{FEFF}")
    }

    @Test func sensitiveHeaderConcealsEveryCellOfTheColumnIncludingQuotedMultilineValues() throws {
        let source = "name,password,note\nalice,hunter2,\"hello, world\"\nbob,\"p,w\nd\",ok\r\ncarol,\"\"\"\",fine\n"
        let result = try parse(source)
        #expect(rawRanges(result) == ["hunter2", "\"p,w\nd\"", "\"\"\"\""])
        let safe = concealed(result)
        #expect(safe == "name,password,note\nalice,••••,\"hello, world\"\nbob,••••,ok\r\ncarol,••••,fine\n")
        #expect(!safe.contains("hunter2"))
        // Concealment replaces whole cells, so records and columns keep their shape.
        #expect(try cells(safe).map(\.count) == cells(source).map(\.count))
        #expect(try cells(safe).map { $0[0] } == ["name", "alice", "bob", "carol"])
        #expect(try cells(safe).map { $0[1] } == ["password", "••••", "••••", "••••"])
    }

    @Test(arguments: ["Password", "API Key", "client-secret", "access_token", "Authorization", "DB_PASSWD", "pwd", "private key", "token"])
    func sensitiveColumnNamesUseTheSharedPolicy(header: String) throws {
        let source = "id,\(header),other\n1,synthetic-value,visible\n"
        let result = try parse(source)
        #expect(rawRanges(result) == ["synthetic-value"])
        #expect(concealed(result) == "id,\(header),other\n1,••••,visible\n")
    }

    @Test func nonSensitiveHeadersAndEmptySensitiveCellsAreLeftAlone() throws {
        let plain = try parse("id,name,notes\n1,passport office,visible\n")
        #expect(plain.sensitiveRanges.isEmpty)
        // An empty cell holds nothing to hide, and a token would imply a value exists.
        let empties = try parse("a,password\nx,\ny,\"\"\nz,real\n")
        #expect(rawRanges(empties) == ["real"])
    }

    @Test func cellsWithSensitiveAssignmentsAreConcealedWhateverTheirColumn() throws {
        let source = "id,note\n1,password=abc123\n2,\"api_key: xyz, more\"\n3,safe: text\n4,12:30:00\n5,\"say \"\"token = 7\"\"\"\n"
        let result = try parse(source)
        #expect(rawRanges(result) == ["password=abc123", "\"api_key: xyz, more\"", "\"say \"\"token = 7\"\"\""])
        let safe = concealed(result)
        #expect(safe == "id,note\n1,••••\n2,••••\n3,safe: text\n4,12:30:00\n5,••••\n")
        #expect(try cells(safe).map(\.count) == cells(source).map(\.count))
    }

    @Test func rowWiseKeyValuePairsConcealTheValueAfterASensitiveKeyCell() throws {
        // Neutral headers: the secret's key lives in a cell, not in the header.
        let exported = try parse("name,value,note\napi_key,synthetic-key,kept\ncolor,blue,kept\n\"Password\",\"p,w\",kept\n")
        #expect(rawRanges(exported) == ["synthetic-key", "\"p,w\""])
        let safe = concealed(exported)
        #expect(safe == "name,value,note\napi_key,••••,kept\ncolor,blue,kept\n\"Password\",••••,kept\n")
        #expect(try cells(safe).map(\.count) == cells("name,value,note\napi_key,x,kept\ncolor,blue,kept\nPassword,x,kept\n").map(\.count))
        // A headerless two-column export: its first record is also a key/value pair.
        // Its sensitive first cell also marks column 0 under the established header rule.
        let headerless = try parse("token,abc123\nuser,alice\n")
        #expect(rawRanges(headerless) == ["abc123", "user"])
        // A concealed value that happens to contain a secret-like word is not treated as a key.
        let values = try parse("name,password,note\nbob,my-token-value,visible\n")
        #expect(rawRanges(values) == ["my-token-value"])
        // Wider header records keep their labels; long prose cells are not key names.
        let table = try parse("password,email,count\nx,y,z\n")
        #expect(rawRanges(table) == ["x"])
        // An assignment cell is concealed by its own rule and does not hide its neighbour.
        let assignment = try parse("id,note,link\n1,password=abc,https://example.invalid/\n")
        #expect(rawRanges(assignment) == ["password=abc"])
        let prose = try parse("id,note\n1,\"\(String(repeating: "the password reset flow ", count: 8))\",visible\n")
        #expect(prose.sensitiveRanges.isEmpty)
    }

    @Test func headerCellsAreConcealedOnlyWhenTheyContainAnAssignment() throws {
        let named = try parse("name,password\nx,y\n")
        #expect(rawRanges(named) == ["y"], "A sensitive header name stays visible; its column is concealed")
        let assignment = try parse("a,pwd=1\nx,y\n")
        #expect(rawRanges(assignment) == ["pwd=1", "y"])
    }

    @Test func recordsWiderThanTheHeaderAlsoConcealTheColumnsAValueCouldHaveShiftedInto() throws {
        // An unquoted comma inside free text pushes the secret one column to the right.
        let result = try parse("name,notes,password\nbob,likes red, green,hunter2\nann,fine,pw\n")
        #expect(rawRanges(result) == [" green", "hunter2", "pw"])
        let wide = try parse("a,password\n1,2,3,4,5\n")
        #expect(rawRanges(wide) == ["2", "3", "4", "5"])
        // Shorter records stay positional.
        let short = try parse("a,b,password\n1,2\n3\n")
        #expect(short.sensitiveRanges.isEmpty)
    }

    @Test func rangesUseUTF8OffsetsAcrossUnicodeAndAnEncodingMarkInText() throws {
        let source = "\u{FEFF}名前,pass\u{200B}word,\"é 🌍\"\n日本語😀,secret🌍,😀\r\n"
        let result = try parse(source)
        #expect(rawRanges(result) == ["secret🌍"])
        #expect(try cells(concealed(result)).map(\.count) == [3, 3])
        let utf8 = Array(source.utf8)
        let range = try #require(result.sensitiveRanges.first).utf8Range
        #expect(String(decoding: utf8[range], as: UTF8.self) == "secret🌍")
    }

    @Test(arguments: [TextEncoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func decodedInputIsEncodingAgnosticBecauseTheDecoderConsumedAnyBOM(encoding: TextEncoding) throws {
        let source = "name\tpassword\nuna\tsecret\n"
        let result = try parse(source, .tab, encoding: encoding, hasBOM: encoding != .utf8)
        #expect(result.text == source)
        #expect(rawRanges(result) == ["secret"])
    }

    @Test func formulaLikeTextStaysInertLiteralText() throws {
        let source = "a,b,c,d\n=SUM(A1:A2),+1,-2,@cmd\n\"=1+1\",=,+,-\n"
        let result = try parse(source)
        #expect(result.text == source)
        #expect(result.sensitiveRanges.isEmpty)
        #expect(try cells(source)[1] == ["=SUM(A1:A2)", "+1", "-2", "@cmd"])
        #expect(try cells(source)[2] == ["=1+1", "=", "+", "-"])
    }

    @Test func tabularQuotesAreLiteralAndTheSameColumnRulesApply() throws {
        let source = "title\tpassword\tnote\n5\" pipe\thunter2\t\"Weird Al\" Yankovic\n"
        let result = try parse(source, .tab)
        #expect(rawRanges(result) == ["hunter2"])
        #expect(try cells(concealed(result), .tab) == [["title", "password", "note"], ["5\" pipe", "••••", "\"Weird Al\" Yankovic"]])
    }

    @Test(arguments: ["a,\"b", "a,b\"c", "\"a\"b,c", "name,password\nx,\"never closed\nmore,\nlines", "a, \"b\""])
    func malformedCommaStructureFailsClosedWithoutAnyDocument(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
    }

    @Test func malformedTabStructureFailsClosed() {
        #expect(throws: PreviewFailure.malformedDocument) { try parse("name\tpassword\nx\t\"line one\nline two\"\n", .tab) }
    }

    @Test func concealedOutputPreservesShapeForTrickyDocuments() throws {
        let documents = [
            "id,secret,note\r\n1,\"multi\r\nline, with \"\"quotes\"\"\",x\r\n2,,y\r\n\r\n3,tail\r\n",
            "api_key,v\nk1,1\n\"k2\",2\n",
            "h,token\n\"a,b\",\"x\"\n,\n",
            "name,password\nx,secret1,extra,more\ny\n",
            "a,b\n\"note: password=\"\"x y\"\"\",plain\n"
        ]
        for source in documents {
            let before = try cells(source)
            let result = try parse(source)
            let after = try cells(concealed(result))
            #expect(after.map(\.count) == before.map(\.count), "Shape changed for \(source.debugDescription)")
            #expect(!result.sensitiveRanges.isEmpty)
            for (original, safe) in zip(before, after) {
                for (a, b) in zip(original, safe) where a != b { #expect(b == "••••") }
            }
        }
    }

    @Test func budgetsRunBeforeScanningAndBoundEveryDimension() {
        #expect(throws: PreviewFailure.inputTooLarge) { try parse("a,b\n1,2", budget: PreviewBudget(maxInputBytes: 5)) }
        #expect(throws: PreviewFailure.outputTooLarge) { try parse("a,b\n1,2", budget: PreviewBudget(maxOutputUTF8Bytes: 5)) }
        #expect(throws: PreviewFailure.tooManyLines) { try parse("a\nb\nc", budget: PreviewBudget(maxTextLines: 2)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parse("abcdefghi", budget: PreviewBudget(maxLineUTF8Bytes: 8)) }
        // Short physical lines do not excuse one oversized multi-line quoted field.
        #expect(throws: PreviewFailure.lineTooLong) { try parse("\"aaaa\nbbbb\ncccc\"", budget: PreviewBudget(maxLineUTF8Bytes: 8)) }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse("a,b,c,d\n1,2,3,4", budget: PreviewBudget(maxJSONNodes: 3)) }
        // Concealed cells share the filter's range ceiling, so fail here with a typed error.
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parse("a,password\n1,x\n2,y\n3,z\n", budget: PreviewBudget(maxJSONNodes: 2))
        }
        #expect(throws: Never.self) { _ = try parse("a,password\n1,x\n2,y\n", budget: PreviewBudget(maxJSONNodes: 2)) }
    }

    @Test func manyColumnsAreBoundedByTheStructureBudget() throws {
        let width = 5_000
        let source = (0..<width).map(String.init).joined(separator: ",") + "\n"
        #expect(try parse(source).text == source)
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parse(source, budget: PreviewBudget(maxJSONNodes: width - 1))
        }
    }

    @Test func cancelledRequestsStopBeforeAnyWork() async {
        let result = await Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try parse("a,b\n1,2"); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(result)
    }

    @Test func expiredDeadlinesStopBeforeAnyWork() {
        #expect(throws: PreviewFailure.deadlineExceeded) { try parse("a,b\n1,2", budget: PreviewBudget(maxMilliseconds: 0)) }
        #expect(throws: PreviewFailure.deadlineExceeded) { try parse("a\tb\n1\t2", .tab, budget: PreviewBudget(maxMilliseconds: 0)) }
    }

    @Test func cooperativeCancellationStopsAnActiveLargeScan() async throws {
        let row = String(repeating: "abcdefghij,", count: 90) + "tail\n"
        let text = String(repeating: row, count: 1_500)
        let source = DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 16_777_216,
                                   maxJSONNodes: 1_000_000, maxTextLines: 100_000, maxMilliseconds: 30_000)
        try await CancellationTest.expectStopsActiveParse(budget: budget) {
            try DelimitedTextAdapter(dialect: .comma).parse(source, context: $0)
        }
    }
}
