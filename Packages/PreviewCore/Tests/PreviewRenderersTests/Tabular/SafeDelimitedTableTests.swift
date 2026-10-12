import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en_US")

private func table(_ text: String, _ syntax: TextSyntax = .commaSeparated) -> SafeTable? {
    SafeDelimitedTable.table(text, syntax: syntax, locale: english)
}

private func fallbackTitle(_ number: Int) -> String {
    PreviewStrings.format(.previewTableColumn, arguments: [Int64(number)], locale: english)
}

@Suite("Safe delimited table")
struct SafeDelimitedTableTests {
    @Test func theFirstRecordTitlesColumnsAndBodyCellsKeepTheirExactSpelling() throws {
        let result = try #require(table("id,name\r\n007,=SUM(A1:A2)\r\n+1,-2 \n2026-10-04,1e999\n"))
        #expect(result.columns == ["id", "name"])
        #expect(result.rows == [["007", "=SUM(A1:A2)"], ["+1", "-2 "], ["2026-10-04", "1e999"]])
        #expect(result.truncation.isEmpty)
    }

    @Test func quotedCellsKeepDelimitersLineBreaksAndEscapedQuotes() throws {
        let result = try #require(table("a,b\n\"x, y\",\"line 1\r\nline \"\"2\"\"\"\n"))
        #expect(result.rows == [["x, y", "line 1\r\nline \"2\""]])
    }

    @Test func raggedRowsReadAsEmptyCellsAndWidenTheTable() throws {
        let result = try #require(table("a,b,c\n1\n1,2,3,4\n"))
        #expect(result.columns == ["a", "b", "c", fallbackTitle(4)])
        #expect(result.rows == [["1"], ["1", "2", "3", "4"]])
        #expect(result.cell(row: 0, column: 2) == "")
        #expect(result.cell(row: 0, column: 99) == "")
        #expect(result.cell(row: 99, column: 0) == "")
    }

    @Test func blankOrMissingTitlesUseTheLocalizedColumnLabel() throws {
        let result = try #require(table(",  ,x\n1,2,3\n"))
        #expect(result.columns == [fallbackTitle(1), fallbackTitle(2), "x"])
        #expect(fallbackTitle(2).contains("2"))
        #expect(!fallbackTitle(2).contains("%"))
    }

    @Test func tabularDialectTreatsQuotesAndCommasAsLiteralData() throws {
        let result = try #require(table("title\tnote\n5\" pipe\t\"Weird Al\" Yankovic, Jr.\n", .tabSeparated))
        #expect(result.columns == ["title", "note"])
        #expect(result.rows == [["5\" pipe", "\"Weird Al\" Yankovic, Jr."]])
    }

    @Test func concealedCellsKeepTheShapeOfTheSourceTable() throws {
        // Safe text as the privacy stage writes it: whole cells, quotes included, become the token.
        let result = try #require(table("name,password,note\nalice,••••,\"hello, world\"\nbob,••••,ok\n"))
        #expect(result.rows == [["alice", "••••", "hello, world"], ["bob", "••••", "ok"]])
        #expect(result.columns.count == 3)
        let unquoted = try #require(table("a\tb\nx\t••••\n", .tabSeparated))
        #expect(unquoted.rows == [["x", "••••"]])
    }

    @Test func aLeadingEncodingMarkIsNotPartOfTheFirstTitle() throws {
        #expect(try #require(table("\u{FEFF}name,x\n1,2\n")).columns == ["name", "x"])
    }

    @Test func emptyAndHeaderOnlyTextAreEmptyTablesNotFallbacks() throws {
        let empty = try #require(table(""))
        #expect(empty.columns.isEmpty && empty.rows.isEmpty)
        let headerOnly = try #require(table("a,b,c\n"))
        #expect(headerOnly.columns == ["a", "b", "c"] && headerOnly.rows.isEmpty)
        let blank = try #require(table("\n"))
        #expect(blank.columns == [fallbackTitle(1)] && blank.rows.isEmpty)
    }

    @Test(arguments: ["a,\"unterminated\n1,2", "a,b\"c\n1,2", "\"a\"b,c\n1,2", "a,b\n\"1\"x,2"])
    func commaStructureFailuresSelectTheSafeSourceFallback(text: String) {
        #expect(table(text) == nil)
    }

    @Test func tabFieldsThatMayStartAQuotedFieldSelectTheFallback() {
        #expect(table("a\tb\n\"x\ty\"\n", .tabSeparated) == nil)
    }

    @Test(arguments: [TextSyntax.plain, .json, .sourceCode, .markdown, .subRip])
    func otherSyntaxesNeverBecomeTables(syntax: TextSyntax) {
        #expect(table("a,b\n1,2", syntax) == nil)
    }

    @Test func columnsBeyondTheDisplayLimitAreCutAndFlagged() throws {
        let width = SafeDelimitedTable.maximumColumns + 5
        let header = (0..<width).map { "c\($0)" }.joined(separator: ",")
        let row = (0..<width).map(String.init).joined(separator: ",")
        let result = try #require(table(header + "\n" + row + "\n"))
        #expect(result.columns.count == SafeDelimitedTable.maximumColumns)
        #expect(result.rows[0].count == SafeDelimitedTable.maximumColumns)
        #expect(result.truncation == .columns)
        #expect(result.columns.last == "c\(SafeDelimitedTable.maximumColumns - 1)")
    }

    @Test func rowsBeyondTheDisplayLimitAreCutAndFlagged() throws {
        let body = String(repeating: "x\n", count: SafeDelimitedTable.maximumRows + 3)
        let result = try #require(table("h\n" + body))
        #expect(result.rows.count == SafeDelimitedTable.maximumRows)
        #expect(result.truncation == .rows)
        let exact = try #require(table("h\n" + String(repeating: "x\n", count: SafeDelimitedTable.maximumRows)))
        #expect(exact.rows.count == SafeDelimitedTable.maximumRows)
        #expect(exact.truncation.isEmpty)
    }

    @Test func totalCellsAreBoundedForWideAndTallTables() throws {
        let columns = SafeDelimitedTable.maximumColumns
        let row = Array(repeating: "a", count: columns).joined(separator: ",")
        let rows = SafeDelimitedTable.maximumCells / columns + 5
        let result = try #require(table(Array(repeating: row, count: rows + 1).joined(separator: "\n")))
        #expect(result.rows.count == SafeDelimitedTable.maximumCells / columns)
        #expect(result.rows.reduce(0) { $0 + $1.count } <= SafeDelimitedTable.maximumCells)
        #expect(result.truncation == .rows)
    }

    @Test func longCellsAreClippedAtACharacterBoundaryAndFlagged() throws {
        let limit = SafeDelimitedTable.maximumCellUTF16Units
        // A surrogate pair straddles the limit: the clip stops before it instead of splitting it.
        let pair = "a" + String(repeating: "😀", count: limit)
        // A combining mark straddles the limit: the whole composed character is dropped.
        let composed = String(repeating: "x", count: limit - 1) + "e\u{301}tail"
        let exact = String(repeating: "y", count: limit)
        let result = try #require(table("p,c,e\n\(pair),\(composed),\(exact)\n"))
        #expect(result.rows[0][0].utf16.count == limit - 1)
        #expect(result.rows[0][0].unicodeScalars.allSatisfy { $0.value != 0xFFFD })
        #expect(result.rows[0][0].hasPrefix("a😀"))
        #expect(result.rows[0][1] == String(repeating: "x", count: limit - 1))
        #expect(result.rows[0][2] == exact)
        #expect(result.truncation == .cells)
    }

    @Test func oversizedSafeTextIsNotParsedForATable() {
        let big = String(repeating: "a,\n", count: SafeDelimitedTable.maximumSourceUTF8Bytes / 3 + 1)
        #expect(big.utf8.count > SafeDelimitedTable.maximumSourceUTF8Bytes)
        #expect(table(big) == nil)
    }

    @Test func invalidationComparesExactCodeUnitsAndSkipsWorkForIdenticalStorage() throws {
        let composed = try #require(table("h\n\u{E9}\n"))
        let decomposed = try #require(table("h\ne\u{301}\n"))
        #expect("\u{E9}" == "e\u{301}", "Swift String equality folds canonical equivalents")
        #expect(composed != decomposed)
        let first = try #require(table("a,b\n1,2\n"))
        let second = try #require(table("a,b\n1,2\n"))
        #expect(first == second)
        #expect(first == first)
        let otherCell = try #require(table("a,b\n1,3\n"))
        let otherTitle = try #require(table("a,c\n1,2\n"))
        #expect(first != otherCell)
        #expect(first != otherTitle)
    }
}
