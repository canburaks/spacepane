import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func har(entries: String, extra: String = "") -> Data {
    Data(#"{"log": {"version": "1.2", "creator": {"name": "T", "version": "1"}, \#(extra) "entries": [\#(entries)]}}"#.utf8)
}

private func entry(url: String, method: String = "GET", status: Int = 200, response: String = #""content": {"size": 5, "mimeType": "text/plain"}"#,
                   time: String = "1.5") -> String {
    #"{"time": \#(time), "request": {"method": "\#(method)", "url": "\#(url)"}, "response": {"status": \#(status), \#(response)}}"#
}

@Suite("HAR adapter")
struct HARAdapterTests {
    @Test func capturesBecomeASummaryAndARequestTable() throws {
        let document = try DataTest.parse(HARAdapter(), DataFixtures.har)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "HAR" && object["formatVersion"] as? String == "1.2")
        #expect(object["creator"] as? String == "Synthetic Capture 1.0")
        #expect(object["browser"] as? String == "Synthetic Browser 2.0")
        #expect(object["pageCount"] as? Int == 1 && object["entryCount"] as? Int == 3)
        let table = try DataTest.table(object)
        #expect(table.columns == ["method", "url", "status", "mimeType", "size", "time"])
        let rows = table.rows.map { $0.map(DataTest.cell) }
        #expect(rows[0] == ["GET", "https://example.com/api/items?token=x&page=x", "200", "application/json", "1234", "56.8"])
        #expect(rows[1] == ["POST", "https://example.com/login", "302", "text/html", "0", "12.5"])
        // An unknown size is empty, not zero.
        #expect(rows[2] == ["GET", "https://cdn.example.com/app.js", "304", "text/javascript", "", "3.0"])
    }

    @Test func headersCookiesBodiesCredentialsAndQueryValuesNeverEnterTheDocument() throws {
        let document = try DataTest.parse(HARAdapter(), DataFixtures.har)
        // The fixture puts its synthetic secret in an Authorization header, a cookie, a Set-Cookie header,
        // POST data, a response body, the URL's user information and a query value.
        #expect(!document.text.contains(DataFixtures.secret))
        #expect(!document.text.contains("Authorization") && !document.text.contains("Set-Cookie"))
        #expect(!document.text.contains("#section") && !document.text.contains("user:"))
        // Each query value is represented by a concealed placeholder that counts as a redaction.
        #expect(document.sensitiveRanges.count == 2)
        let text = Array(document.text.utf8)
        #expect(document.sensitiveRanges.allSatisfy { String(decoding: text[$0.utf8Range], as: UTF8.self) == "x" })
    }

    @Test func urlsKeepSchemeHostAndPathOnly() {
        func shown(_ raw: String) -> String { HARAdapter.displayURL(raw).map(\.text).joined() }
        #expect(shown("https://u:p@host:8443/a/b?x=1&y=#frag") == "https://host:8443/a/b?x=x&y=")
        #expect(shown("https://h/p?a=1&b=&c") == "https://h/p?a=x&b=&c")
        #expect(shown("https://h/p") == "https://h/p")
        #expect(shown("https://h/p#only-fragment") == "https://h/p")
        #expect(shown("data:text/plain;base64,QUJD") == "data:…")
        #expect(shown("javascript:alert(1)") == "javascript:…")
        #expect(shown("about:blank") == "about:blank")
        #expect(shown("/relative/path?k=v") == "/relative/path?k=x")
        let many = (0..<12).map { "p\($0)=v" }.joined(separator: "&")
        #expect(shown("https://h/?" + many).hasSuffix("&…"))
        let placeholders = HARAdapter.displayURL("https://h/?a=1&b=2").filter(\.sensitive)
        #expect(placeholders.map(\.text) == ["x", "x"])
        #expect(shown("https://h/" + String(repeating: "a", count: 1_000)).count == 300)
    }

    @Test func sizeFallsBackFromContentToBodyAndStatusTimeAreFormatted() throws {
        let data = har(entries: [
            entry(url: "https://h/1", response: #""bodySize": 10, "content": {"mimeType": "x/y; charset=utf-8"}"#),
            entry(url: "https://h/2", status: 0, response: #""bodySize": -1, "content": {"size": -1}"#, time: "-1"),
            entry(url: "https://h/3", response: #""content": {"size": 7}"#, time: "1e2")
        ].joined(separator: ","))
        let rows = try DataTest.rows(try DataTest.object(try DataTest.parse(HARAdapter(), data)))
        #expect(rows[0][3...] == ["x/y", "10", "1.5"])
        #expect(rows[1][2...] == ["0", "", "", ""])
        #expect(rows[2][4...] == ["7", "100.0"])
    }

    @Test func tablesAreCappedAndTheCountStaysExact() throws {
        let data = har(entries: (0..<400).map { entry(url: "https://h/\($0)") }.joined(separator: ","))
        let document = try DataTest.parse(HARAdapter(), data, budget: PreviewBudget(maxInputBytes: 4_194_304, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        let table = try DataTest.table(object)
        #expect(table.rows.count == HARAdapter.maximumRows && table.truncated)
        #expect(object["entryCount"] as? Int == 400 && object["partial"] as? Bool == true)
        #expect(document.text.utf16.count < 250_000 && DataTest.nodeCount(object) < 18_000)
    }

    @Test func longUrlsStayInsideTheOutlineLimits() throws {
        let url = "https://example.com/" + String(repeating: "segment/", count: 600) + "?" + (0..<20).map { "key\($0)=\($0)" }.joined(separator: "&")
        let data = har(entries: (0..<350).map { _ in entry(url: url) }.joined(separator: ","))
        let document = try DataTest.parse(HARAdapter(), data, budget: PreviewBudget(maxInputBytes: 8_388_608, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        #expect(document.text.utf16.count < 250_000)
        #expect(DataTest.nodeCount(object) < 18_000)
        #expect(try DataTest.table(object).truncated)
    }

    @Test func skippedMembersAreSkippedEvenWhenHugeOrDeeplyNested() throws {
        let nested = String(repeating: "[", count: 30) + String(repeating: "]", count: 30)
        let big = String(repeating: "x", count: 200_000)
        let extra = #""comment": "\#(big)", "custom": \#(nested),"#
        let data = har(entries: entry(url: "https://h/a", response: #""content": {"size": 1, "text": "\#(big)"}, "headers": \#(nested)"#), extra: extra)
        let document = try DataTest.parse(HARAdapter(), data, budget: PreviewBudget(maxInputBytes: 1_048_576, maxMilliseconds: 30_000))
        #expect(!document.text.contains("xxxxxxxx"))
        // Beyond the depth budget the skip itself fails closed.
        let tooDeep = String(repeating: "[", count: 80) + String(repeating: "]", count: 80)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try DataTest.parse(HARAdapter(), har(entries: entry(url: "https://h/a"), extra: #""custom": \#(tooDeep),"#))
        }
    }

    @Test func notHARMalformedAndOversizedInputIsRefused() throws {
        for text in ["", "{}", "[]", #"{"log": {}}"#, #"{"log": {"entries": 5}}"#, #"{"log": {"entries": []"#, "null", #"{"log": 1}"#] {
            #expect(throws: PreviewFailure.malformedDocument, "\(text)") { try DataTest.parse(HARAdapter(), Data(text.utf8)) }
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try DataTest.parse(HARAdapter(), Data(#"{"log": {"entries": [{"request": {"url": "a\u00zz"}}]}}"#.utf8))
        }
        // Raw invalid UTF-8 inside a displayed string is not silently repaired.
        var invalid = Data(#"{"log": {"entries": [{"request": {"url": "a"#.utf8)
        invalid += Data([0xFF, 0xFE])
        invalid += Data(#"b"}}]}}"#.utf8)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(HARAdapter(), invalid) }
        let budget = PreviewBudget(maxInputBytes: 100, maxMilliseconds: 30_000)
        #expect(throws: PreviewFailure.inputTooLarge) { try DataTest.parse(HARAdapter(), DataFixtures.har, budget: budget) }
    }

    @Test func escapesDecodeAndALoneSurrogateBecomesAReplacementCharacter() throws {
        let data = har(entries: entry(url: "https://h/caf\\u00e9/\\ud83d\\ude00/\\ud800"))
        let url = try DataTest.rows(try DataTest.object(try DataTest.parse(HARAdapter(), data)))[0][1]
        #expect(url == "https://h/café/😀/\u{FFFD}")
        let bom = Data([0xEF, 0xBB, 0xBF]) + har(entries: entry(url: "https://h/bom"))
        #expect(try DataTest.rows(try DataTest.object(try DataTest.parse(HARAdapter(), bom)))[0][1] == "https://h/bom")
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.har
        for length in stride(from: 0, to: data.count, by: 3) {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(HARAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 0, to: data.count, by: 5) {
            var changed = data
            changed[index] ^= 0x20
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(HARAdapter(), changed) }
        }
    }

    @Test func cancellationAndDeadlineAreHonored() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try HARAdapter().parse(FileBytes(data: DataFixtures.har), context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try HARAdapter().parse(FileBytes(data: DataFixtures.har), context: DataTest.context()); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}
