import Foundation
import Synchronization
import Testing
import PreviewContracts

private let generous = DelimitedRecords.Limits(maxRecords: 1_000, maxFieldsPerRecord: 1_000, maxFieldBytes: 100_000)

/// Decoded cells per record, using the shared scanner exactly as production code does.
private func records(_ text: String, _ dialect: DelimitedRecords.Dialect = .comma,
                     limits: DelimitedRecords.Limits = generous) throws -> [[String]] {
    let bytes = Array(text.utf8)
    var result: [[String]] = []
    _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: limits, checkpoint: {}) { _, fields in
        result.append(fields.map { DelimitedRecords.text(of: $0, in: bytes) })
        return .proceed
    }
    return result
}

@Suite("Delimited record grammar")
struct DelimitedRecordsTests {
    @Test func commaSeparatesRecordsWithLFCRLFAndBareCR() throws {
        let expected = [["a", "b"], ["1", "2"], ["3", "4"]]
        for separator in ["\n", "\r\n", "\r"] {
            #expect(try records(["a,b", "1,2", "3,4"].joined(separator: separator)) == expected, "separator \(separator.debugDescription)")
            // The final line break is optional and never creates an extra record.
            #expect(try records(["a,b", "1,2", "3,4"].joined(separator: separator) + separator) == expected)
        }
    }

    @Test func quotedFieldsKeepDelimitersLineBreaksAndEscapedQuotes() throws {
        let source = "name,note\r\n\"Doe, Jane\",\"line one\r\nline \"\"two\"\"\"\n\"\",\"\"\"\"\n"
        #expect(try records(source) == [["name", "note"], ["Doe, Jane", "line one\r\nline \"two\""], ["", "\""]])
    }

    @Test func blankLinesAndTrailingDelimitersAreEmptyFields() throws {
        #expect(try records("a,b\n\nc,\n,\n") == [["a", "b"], [""], ["c", ""], ["", ""]])
        #expect(try records("a,b,") == [["a", "b", ""]])
        #expect(try records("\n") == [[""]])
        #expect(try records("").isEmpty)
        #expect(try records("\u{FEFF}").isEmpty)
    }

    @Test func raggedRecordsAreReportedAsTheyAre() throws {
        #expect(try records("a,b,c\n1\n1,2,3,4\n") == [["a", "b", "c"], ["1"], ["1", "2", "3", "4"]])
    }

    @Test func exactSpellingsSurviveWithoutTrimmingOrCoercion() throws {
        let source = " =SUM(A1:A2) ,+1,-2 ,@x ,007,1e999,2026-10-04,\" padded \"\n"
        #expect(try records(source) == [[" =SUM(A1:A2) ", "+1", "-2 ", "@x ", "007", "1e999", "2026-10-04", " padded "]])
    }

    @Test func offsetsIndexTheOriginalBytesIncludingMultibyteTextAndALeadingBOM() throws {
        let source = "\u{FEFF}名前,\"é 🌍\",x\n"
        let bytes = Array(source.utf8)
        var spans: [(raw: String, content: String)] = []
        _ = try DelimitedRecords.scan(bytes, dialect: .comma, limits: generous, checkpoint: {}) { _, fields in
            spans = fields.map { (String(decoding: bytes[$0.raw], as: UTF8.self), String(decoding: bytes[$0.content], as: UTF8.self)) }
            return .proceed
        }
        #expect(spans.map(\.raw) == ["名前", "\"é 🌍\"", "x"])
        #expect(spans.map(\.content) == ["名前", "é 🌍", "x"])
    }

    @Test(arguments: ["a,\"unterminated", "\"", "a,\"b\"\"", "a,b\"c", "\"abc\"def,x", "a, \"b\"", "\"a\" ,b", "\"a\"\"b"])
    func commaStructuralErrorsFailClosed(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try records(source) }
    }

    @Test func tabQuotesAreLiteralDataPerTheIANARegistration() throws {
        #expect(try records("5\" pipe\t\"Weird Al\" Yankovic\t\"x\"\n", .tab) == [["5\" pipe", "\"Weird Al\" Yankovic", "\"x\""]])
        // A comma is ordinary data in TSV, and a tab-embedded RFC quote is not supported.
        #expect(try records("a,b\tc\n", .tab) == [["a,b", "c"]])
    }

    @Test(arguments: ["\"first\tsecond", "a\t\"line one\nline two\"", "\"a\"\"b\tc\"", "ok\t\"unbalanced"])
    func tabFieldThatMayStartAnRFCQuotedFieldFailsClosedInsteadOfMisaligningColumns(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try records(source, .tab) }
    }

    @Test func limitsFailBeforeStoringUnboundedData() {
        #expect(throws: PreviewFailure.tooManyLines) {
            try records("a\nb\nc", limits: .init(maxRecords: 2, maxFieldsPerRecord: 10, maxFieldBytes: 10))
        }
        #expect(throws: PreviewFailure.tooManyNodes) {
            try records("a,b,c,d", limits: .init(maxRecords: 10, maxFieldsPerRecord: 3, maxFieldBytes: 10))
        }
        #expect(throws: PreviewFailure.lineTooLong) {
            try records("abcdef", limits: .init(maxRecords: 10, maxFieldsPerRecord: 10, maxFieldBytes: 5))
        }
        #expect(throws: PreviewFailure.lineTooLong) {
            // Each physical line is short; the quoted field as a whole is not.
            try records("\"aaa\nbbb\nccc\"", limits: .init(maxRecords: 10, maxFieldsPerRecord: 10, maxFieldBytes: 8))
        }
        #expect(throws: PreviewFailure.lineTooLong) {
            try records(String(repeating: "x", count: 50), .tab, limits: .init(maxRecords: 10, maxFieldsPerRecord: 10, maxFieldBytes: 10))
        }
        // The boundaries themselves are accepted.
        #expect(throws: Never.self) {
            _ = try records("a,b\nc,d", limits: .init(maxRecords: 2, maxFieldsPerRecord: 2, maxFieldBytes: 1))
        }
    }

    @Test func visitorCanStopAndReportsWhetherInputRemained() throws {
        let bytes = Array("a\nb\nc\n".utf8)
        var seen = 0
        let stopped = try DelimitedRecords.scan(bytes, dialect: .comma, limits: generous, checkpoint: {}) { _, _ in
            seen += 1
            return seen == 2 ? .stop : .proceed
        }
        #expect(stopped.recordCount == 2)
        #expect(stopped.stoppedEarly)
        seen = 0
        let lastRecord = try DelimitedRecords.scan(bytes, dialect: .comma, limits: generous, checkpoint: {}) { _, _ in
            seen += 1
            return seen == 3 ? .stop : .proceed
        }
        #expect(lastRecord.recordCount == 3)
        #expect(!lastRecord.stoppedEarly)
    }

    @Test func checkpointsRunRegularlyAndItsFailuresPropagate() {
        let source = Array(String(repeating: String(repeating: "abcdefgh,", count: 99) + "x\n", count: 40).utf8)
        let calls = Mutex(0)
        #expect(throws: Never.self) {
            _ = try DelimitedRecords.scan(source, dialect: .comma, limits: generous, checkpoint: {
                calls.withLock { $0 += 1 }
            }) { _, _ in .proceed }
        }
        #expect(calls.withLock { $0 } >= source.count / 1_024)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try DelimitedRecords.scan(source, dialect: .comma, limits: generous, checkpoint: {
                throw PreviewFailure.deadlineExceeded
            }) { _, _ in .proceed }
        }
        #expect(throws: CancellationError.self) {
            _ = try DelimitedRecords.scan(Array("a".utf8), dialect: .tab, limits: generous, checkpoint: {
                throw CancellationError()
            }) { _, _ in .proceed }
        }
    }
}
