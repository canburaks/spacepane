import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en_US")

private func csv(_ text: String) -> SafeTable? { SafeDelimitedTable.table(text, syntax: .commaSeparated, locale: english) }

@Suite("Natural name order")
struct NaturalOrderTests {
    @Test func digitRunsCompareByValueAndLettersIgnoreCase() {
        let names = ["file10.txt", "File2.txt", "file1.txt", "File 3.txt", "a", "B", "b2", "b10", "7", "10"]
        let sorted = names.sorted { NaturalOrder.compareASCII($0, $1) == .orderedAscending }
        #expect(sorted == ["7", "10", "a", "B", "b2", "b10", "File 3.txt", "file1.txt", "File2.txt", "file10.txt"])
    }

    @Test func leadingZerosAndLongDigitRunsDoNotOverflow() {
        #expect(NaturalOrder.compareASCII("a2", "a02") == .orderedSame)
        #expect(NaturalOrder.compareASCII("a9", "a10") == .orderedAscending)
        let huge = String(repeating: "9", count: 80)
        #expect(NaturalOrder.compareASCII("a" + huge, "a1" + huge) == .orderedAscending)
        #expect(NaturalOrder.compareASCII("", "a") == .orderedAscending)
        #expect(NaturalOrder.compareASCII("a", "") == .orderedDescending)
    }

    @Test func asciiColumnsUseTheFastPathAndOthersTheLocalizedCollation() {
        let ascii = NaturalOrder.comparison(for: ["b2", "b10"])
        #expect(ascii("b2", "b10") == .orderedAscending)
        let mixed = NaturalOrder.comparison(for: ["éclair", "zebra", "apple"])
        #expect(mixed("éclair", "zebra") == .orderedAscending)
        #expect(mixed("apple", "éclair") == .orderedAscending)
        #expect(NaturalOrder.compare("a2", "a10") == .orderedAscending)
    }
}

@Suite("Table column types")
struct TableColumnTypeTests {
    @Test func strictNumbersAndDatesBecomeTypedColumnsWhileCellsKeepTheirSpelling() throws {
        let table = try #require(csv("id,price,when,name\n007,\"-1.5\",2026-10-05,beta\n10,+2,2026-01-31T10:00:00Z,alpha\n2,1e3,2025-12-31 23:59,gamma\n"))
        #expect(table.columnKinds == [.number, .number, .date, .text])
        #expect(table.rows[0] == ["007", "-1.5", "2026-10-05", "beta"], "Display text is never reinterpreted")
        #expect(table.sortKeys[0] == [7, 10, 2])
        #expect(table.sortKeys[1] == [-1.5, 2, 1_000])
        #expect(table.sortKeys[3] == nil)
    }

    @Test func oneOtherCellKeepsTheWholeColumnTextual() throws {
        let table = try #require(csv("n,d\n1,2026-01-01\n2,tomorrow\nN/A,2026-01-03\n"))
        #expect(table.columnKinds == [.text, .text])
        #expect(table.sortKeys.isEmpty)
    }

    @Test func blankCellsSortKeyIsNilAndAllBlankColumnsStayText() throws {
        let table = try #require(csv("a,b\n1,\n,\n3,\n"))
        #expect(table.columnKinds == [.number, .text])
        #expect(table.sortKeys[0] == [1, nil, 3])
    }

    @Test func aConcealedCellKeepsAColumnTextSoConcealmentCannotBeUsedToLearnOrder() throws {
        let table = try #require(csv("amount\n10\n••••\n30\n"))
        #expect(table.columnKinds == [.text])
    }

    @Test func numberParserRejectsEverythingButPlainDecimals() {
        for good in ["0", "-0", "+5", "12.5", "1e9", "1E-3", "-2.5e+4", "007"] { #expect(SafeTableColumnTypes.number(Substring(good)) != nil, Comment(rawValue: good)) }
        for bad in ["", ".5", "5.", "1,000", "1 000", "0x10", "NaN", "inf", "-", "1e", "1e+", "١٢٣", "1.2.3", "$5", String(repeating: "1", count: 41)] {
            #expect(SafeTableColumnTypes.number(Substring(bad)) == nil, Comment(rawValue: bad))
        }
    }

    @Test func dateParserReadsISOFormsAndReadsAZonelessTimeAsUTC() throws {
        let date = try #require(SafeTableColumnTypes.date("2026-10-05"))
        #expect(date == 1_791_158_400)
        #expect(SafeTableColumnTypes.date("2026-10-05T12:30:00Z") == date + 45_000)
        #expect(SafeTableColumnTypes.date("2026-10-05 12:30") == date + 45_000)
        #expect(SafeTableColumnTypes.date("2026-10-05T12:30:00+02:00") == date + 45_000 - 7_200)
        #expect(SafeTableColumnTypes.date("2026-10-05T12:30:00-0530") == date + 45_000 + 19_800)
        #expect(SafeTableColumnTypes.date("2026-10-05T12:30:00.500Z") == date + 45_000.5)
        #expect(SafeTableColumnTypes.date("2024-02-29") != nil)
        for bad in ["2026-13-01", "2026-02-30", "2025-02-29", "2026-10-05T25:00", "2026-10-05T12:30:00X", "05/10/2026", "2026-10-5", "2026-10-05T12", "20261005"] {
            #expect(SafeTableColumnTypes.date(Substring(bad)) == nil, Comment(rawValue: bad))
        }
    }
}

@Suite("Table sorting and filtering")
struct TableSortFilterTests {
    private let table = SafeTable(
        columns: ["name", "size", "when"],
        rows: [["b-10", "300", "2026-02-01"], ["B-2", "20", ""], ["a", "", "2025-12-31"], ["c", "20", "2026-02-01"], ["", "5", "2026-03-01"]],
        truncation: [],
        columnKinds: [.text, .number, .date],
        sortKeys: [1: [300, 20, nil, 20, 5], 2: [1_769_904_000, nil, 1_767_139_200, 1_769_904_000, 1_772_323_200]])

    @Test func textColumnsSortNaturallyWithBlanksLastInBothDirections() {
        #expect(SafeTableOrdering.sorted(table, by: 0, ascending: true) == [2, 1, 0, 3, 4])
        #expect(SafeTableOrdering.sorted(table, by: 0, ascending: false) == [3, 0, 1, 2, 4])
    }

    @Test func numberAndDateColumnsSortByValueAndKeepSourceOrderForTies() {
        #expect(SafeTableOrdering.sorted(table, by: 1, ascending: true) == [4, 1, 3, 0, 2])
        #expect(SafeTableOrdering.sorted(table, by: 1, ascending: false) == [0, 1, 3, 4, 2])
        #expect(SafeTableOrdering.sorted(table, by: 2, ascending: true) == [2, 0, 3, 4, 1])
        #expect(SafeTableOrdering.sorted(table, by: 2, ascending: false) == [4, 0, 3, 2, 1])
    }

    @Test func aColumnOutsideTheTableOrWithoutKeysFallsBackSafely() {
        #expect(SafeTableOrdering.sorted(table, by: 9, ascending: true) == [0, 1, 2, 3, 4])
        #expect(SafeTableOrdering.sorted(table, by: -1, ascending: true) == [0, 1, 2, 3, 4])
        let untyped = SafeTable(columns: ["n"], rows: [["10"], ["9"], ["x"]], truncation: [], columnKinds: [.number], sortKeys: [:])
        #expect(SafeTableOrdering.sorted(untyped, by: 0, ascending: true) == [1, 0, 2], "Without keys the text order is used")
    }

    @Test func sortingNeverChangesTheTableItself() {
        let before = table
        _ = SafeTableOrdering.sorted(table, by: 1, ascending: false)
        #expect(table == before)
    }

    @Test func sortingTwentyThousandRowsStaysFast() {
        let rows = (0..<20_000).map { ["name \($0 * 7919 % 20_000)", "\($0)"] }
        let big = SafeTable(columns: ["n", "v"], rows: rows, truncation: [])
        let clock = ContinuousClock()
        let elapsed = clock.measure { #expect(SafeTableOrdering.sorted(big, by: 0, ascending: true).count == 20_000) }
        #expect(elapsed < .seconds(2))
    }

    @Test func filterIgnoresCaseAccentsAndWidthAndKeepsTheCurrentOrder() {
        let rows = SafeTable(columns: ["a", "b"], rows: [["Résumé", "x"], ["RESUME", "y"], ["other", "ｒｅｓｕｍｅ"], ["日本語", "z"], ["none", "none"]], truncation: [])
        var filter = SafeTableFilter()
        let order = [4, 3, 2, 1, 0]
        #expect(filter.rows(in: order, of: rows, matching: "resume") == [2, 1, 0])
        #expect(filter.rows(in: order, of: rows, matching: "RÉSUMÉ") == [2, 1, 0])
        #expect(filter.rows(in: order, of: rows, matching: "日本") == [3])
        #expect(filter.rows(in: order, of: rows, matching: "zzz").isEmpty)
        #expect(filter.rows(in: order, of: rows, matching: "") == order)
        #expect(filter.rows(in: order, of: rows, matching: "ES") == [2, 1, 0], "Substring, not prefix")
    }

    @Test func filterSearchesOnlyTheDisplayedCellsSoConcealedTextCannotMatch() {
        let rows = SafeTable(columns: ["user", "password"], rows: [["alice", "••••"], ["bob", "••••"]], truncation: [])
        var filter = SafeTableFilter()
        #expect(filter.rows(in: [0, 1], of: rows, matching: "hunter2").isEmpty)
        #expect(filter.rows(in: [0, 1], of: rows, matching: "••").count == 2)
    }

    @Test func aVeryLongNeedleIsCappedAndRaggedRowsAreTolerated() {
        let rows = SafeTable(columns: ["a", "b", "c"], rows: [["abc"], ["abc", "x", "needle"]], truncation: [])
        var filter = SafeTableFilter()
        let long = String(repeating: "q", count: 10_000)
        #expect(filter.rows(in: [0, 1], of: rows, matching: long).isEmpty)
        #expect(filter.rows(in: [0, 1], of: rows, matching: "needle") == [1])
        #expect(filter.rows(in: [0, 1, 99], of: rows, matching: "abc") == [0, 1], "Unknown row indexes are dropped")
        #expect(SafeTableFilter.maximumNeedleCharacters == 256)
    }

    @Test func nonASCIICellsAreFoldedOnceAndReusedAcrossQueries() {
        let rows = SafeTable(columns: ["a"], rows: (0..<500).map { ["Ünïcode entry \($0)"] }, truncation: [])
        var filter = SafeTableFilter()
        let order = Array(0..<500)
        #expect(filter.rows(in: order, of: rows, matching: "unicode entry 49").count == 11)
        #expect(filter.rows(in: order, of: rows, matching: "UNICODE ENTRY 499") == [499])
        filter.reset()
        #expect(filter.rows(in: order, of: rows, matching: "entry 7").count == 11)
    }
}
