import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en_US")
private let german = Locale(identifier: "de_DE")
private let token = "••••"
private let sparkBars = "▁▂▃▄▅▆▇█"

private typealias Field = SafeDataProfile.Field
private typealias Column = SafeDataProfile.Column

private func parse(_ text: String, syntax: TextSyntax = .commaSeparated) throws -> SafeTable {
    try #require(SafeDelimitedTable.table(text, syntax: syntax, locale: english))
}

private func profile(_ text: String, limits: SafeDataProfile.Limits = .init()) throws -> SafeDataProfile {
    SafeDataProfile.make(from: try parse(text), limits: limits)
}

/// A one-column table taken verbatim, so cells with commas, spaces and tokens need no CSV quoting.
private func values(_ cells: [String], name: String = "v", limits: SafeDataProfile.Limits = .init()) -> SafeDataProfile {
    SafeDataProfile.make(from: SafeTable(columns: [name], rows: cells.map { [$0] }, truncation: []), limits: limits)
}

private func only(_ cells: [String], name: String = "v") -> Column { values(cells, name: name).columns[0] }

private func cell(_ table: SafeTable, _ row: Int, _ field: Field) -> String { table.cell(row: row, column: field.rawValue) }

/// Every string the profile can put in front of a reader: cells, headers, spoken descriptions and status.
private func everyVisibleString(_ profile: SafeDataProfile, locale: Locale = english) -> [String] {
    let table = profile.displayTable(locale: locale)
    return table.columns + table.rows.flatMap { $0 } + Array(table.cellDescriptions.values) + profile.statusLines(locale: locale)
}

private func facts(_ text: String) -> DataProfileValueClassifier.Facts {
    withUTF8Bytes(of: text) { DataProfileValueClassifier.classify($0) }
}

@Suite("Data profile value classifier")
struct DataProfileValueClassifierTests {
    @Test(arguments: ["0", "7", "-12", "+3", "007", "-0", "00", "9007199254740993"])
    func wholeNumbersAreIntegers(text: String) {
        let result = facts(text)
        #expect(result.kind == .integer)
        #expect(result.number != nil)
    }

    @Test(arguments: ["1.5", "-0.50", ".5", "1e3", "1E-3", "+1.0e+2", "007.5", "0.0", "1.5e300"])
    func fractionsAndExponentsAreDecimals(text: String) {
        #expect(facts(text).kind == .decimal)
    }

    @Test func parsedValuesFollowTheSpelling() {
        #expect(facts("1e3").number == 1_000)
        #expect(facts("-0.50").number == -0.5)
        #expect(facts(".5").number == 0.5)
        #expect(facts("+1.5e3").number == 1_500)
        #expect(facts("0.1").number == 0.1)
        #expect(facts("12345678901234567890123").number == Double("12345678901234567890123"))
        #expect(facts("-007").number == -7)
        #expect(facts("2.5E-3").number == 0.0025)
    }

    @Test(arguments: ["1,234", "1.", "e5", "1e", "1e+", "--1", "+", "-", ".", "5%", "$5", "NaN", "Infinity", "inf",
                      "0x1F", "1 000", "1_000", "٣٢١", "1.2.3.4", "12abc", "abc12"])
    func everythingElseIsText(text: String) {
        #expect(facts(text).kind == .text)
        #expect(facts(text).number == nil)
    }

    @Test func aNumberThatOverflowsADoubleStillReadsAsANumberWithoutAValue() {
        let overflow = facts("1e999")
        #expect(overflow.kind == .decimal)
        #expect(overflow.number == nil)
    }

    @Test func leadingZerosNeedAnIntegerPartLongerThanOneDigit() {
        for text in ["007", "-007", "00", "+01", "007.5", "00.5", "02134"] { #expect(facts(text).hasLeadingZeros, "\(text)") }
        for text in ["0", "-0", "0.5", "0e3", "10", "100", ".5", "1.05", "abc", "007a"] { #expect(!facts(text).hasLeadingZeros, "\(text)") }
    }

    @Test(arguments: ["true", "FALSE", "Yes", "nO", "TRUE", "false", "yes", "No"])
    func booleansAreFourWordsInAnyCase(text: String) {
        #expect(facts(text).kind == .boolean)
    }

    @Test(arguments: ["y", "n", "t", "f", "1", "0", "truee", "tru", "yess", "nope", "on", "off", "t rue"])
    func otherWordsAreNotBooleans(text: String) {
        #expect(facts(text).kind != .boolean)
    }

    @Test(arguments: ["2024-01-05", "2024-01-05T10:30", "2024-01-05 10:30:15", "2024-01-05T10:30:15.250Z", "2024-01-05t10:30z",
                      "2024-01-05T10:30:15+02:00", "2024-01-05T10:30:15-0500", "2024-01-05T10:30+02", "2024-02-29", "2000-02-29",
                      "0001-01-01", "2024-01-05T10:30:15,5Z"])
    func isoDatesWithOptionalTimeAndZone(text: String) {
        let result = facts(text)
        #expect(result.kind == .date)
        #expect(result.dateFormat == .iso)
        #expect(result.timestamp != nil)
    }

    @Test(arguments: ["01/05/2024", "1/5/2024", "12/31/1999", "05/13/2024"])
    func monthFirstSlashDates(text: String) {
        #expect(facts(text).dateFormat == .monthDayYear)
        #expect(facts(text).kind == .date)
        // Ambiguous with day-first, so no ordering key is offered.
        #expect(facts(text).timestamp == nil)
    }

    @Test(arguments: ["05.01.2024", "5.1.2024", "31.12.1999", "29.02.2024"])
    func dottedDayFirstDates(text: String) {
        #expect(facts(text).dateFormat == .dotted)
        #expect(facts(text).kind == .date)
    }

    @Test(arguments: ["2024-13-01", "2024-00-10", "2024-02-30", "2023-02-29", "2100-02-29", "2024-04-31", "2024-01-00",
                      "2024-01-05T25:00", "2024-01-05T10:60", "2024-01-05T10:30:60", "2024-01-05T", "2024-01-05T10",
                      "2024-01-05X10:30", "2024-01-05T10:30:15+25:00", "2024-01-05T10:30junk", "2024/01/05", "2024-1-5",
                      "13/05/2024", "00/05/2024", "05/32/2024", "31.04.2024", "05.01.24", "05/01/24", "5/1/20244", "01-05-2024"])
    func invalidOrUnlistedDatesAreNotDates(text: String) {
        #expect(facts(text).kind != .date)
    }

    @Test func isoTimestampsAreUTCSeconds() {
        #expect(facts("1970-01-01").timestamp == 0)
        #expect(facts("1970-01-02").timestamp == 86_400)
        #expect(facts("1970-01-01T00:00:00+01:00").timestamp == -3_600)
        #expect(facts("1970-01-01T00:00:01.5Z").timestamp == 1.5)
        #expect(facts("2000-03-01").timestamp == 951_868_800)
        #expect(facts("1969-12-31T23:59:59Z").timestamp == -1)
    }

    @Test func emptyAndWhitespaceOnlyCellsAreBlank() {
        for text in ["", " ", "   ", "\t", "\r\n", "\u{00A0}", "\u{2003}\u{2003}", "\u{3000}", " \u{0085} "] {
            #expect(facts(text).isBlank, "\(text.unicodeScalars.map(\.value))")
        }
        for text in ["0", "-", "\u{200B}", "x"] { #expect(!facts(text).isBlank) }
    }

    @Test func surroundingWhitespaceDoesNotChangeTheKindButIsReported() {
        let padded = facts("  42  ")
        #expect(padded.kind == .integer)
        #expect(padded.number == 42)
        #expect(padded.hasSurroundingWhitespace)
        #expect(facts("\u{2003}7\u{2003}").kind == .integer)
        #expect(facts("\u{2003}7\u{2003}").hasSurroundingWhitespace)
        #expect(facts(" true\n").kind == .boolean)
        #expect(facts("a b").kind == .text)
        #expect(!facts("a b").hasSurroundingWhitespace)
        #expect(!facts("42").hasSurroundingWhitespace)
        #expect(facts("é ").kind == .text)
        #expect(facts("é ").hasSurroundingWhitespace)
    }
}

@Suite("Data profile tally")
struct DataProfileTallyTests {
    private func record(_ tally: inout DataProfileTally, _ text: String, row: Int = 0) {
        withUTF8Bytes(of: text) { tally.record(text, bytes: $0, row: row) }
    }

    @Test func spellingsGrowThroughSeveralResizesWithExactCounts() {
        var tally = DataProfileTally(maximumDistinct: 100_000)
        for round in 0..<3 {
            for index in 0..<5_000 { record(&tally, "value-\(index)", row: round * 5_000 + index) }
        }
        #expect(tally.distinctCount == 5_000)
        #expect(tally.entries.allSatisfy { $0.count == 3 })
        #expect(tally.entries.map(\.first) == Array(0..<5_000), "The first occurrence is the first row seen")
        #expect(!tally.reachedLimit)
    }

    @Test func spellingsAreComparedByCodeUnitsAndTheEmptyStringIsOneSpelling() {
        var tally = DataProfileTally(maximumDistinct: 10)
        record(&tally, "\u{E9}")
        record(&tally, "e\u{301}")
        record(&tally, "\u{E9}")
        record(&tally, "")
        record(&tally, "")
        #expect(tally.distinctCount == 3)
        #expect(tally.entries.map(\.count) == [2, 1, 2])
    }

    @Test func theLimitStopsNewSpellingsButTrackedOnesKeepCountingExactly() {
        var tally = DataProfileTally(maximumDistinct: 2)
        for text in ["a", "b", "c", "a", "d", "b", "a"] { record(&tally, text) }
        #expect(tally.reachedLimit)
        #expect(tally.entries.map(\.text) == ["a", "b"])
        #expect(tally.entries.map(\.count) == [3, 2])
        var none = DataProfileTally(maximumDistinct: 0)
        record(&none, "x")
        #expect(none.distinctCount == 0 && none.reachedLimit)
    }

    @Test func mostFrequentOrdersByCountThenFirstOccurrence() {
        var tally = DataProfileTally(maximumDistinct: 100)
        for (row, text) in ["z", "y", "x", "y", "z", "x", "w"].enumerated() { record(&tally, text, row: row) }
        #expect(tally.mostFrequent(3).map(\.text) == ["z", "y", "x"])
        #expect(tally.mostFrequent(10).map(\.text) == ["z", "y", "x", "w"])
        #expect(tally.mostFrequent(0).isEmpty)
        #expect(tally.mostFrequent(1).map(\.count) == [2])
    }

    @Test func longAndShortSpellingsThatShareAPrefixStayApart() {
        var tally = DataProfileTally(maximumDistinct: 100)
        for text in ["abcdefgh", "abcdefgh1", "abcdefg", "abcdefghabcdefgh", "abcdefghabcdefgh", "abcdefghabcdefghX"] { record(&tally, text) }
        #expect(tally.distinctCount == 5)
        #expect(tally.entries.map(\.count) == [1, 1, 1, 2, 1])
    }
}

@Suite("Safe data profile")
struct SafeDataProfileTests {
    // MARK: Types

    @Test func everyKindOfColumnGetsItsType() throws {
        let csv = """
        i,d,b,dt,t,m,e
        1,1.5,true,2024-01-05,hello,1,
        -2,.5,No,2024-01-06T10:30:00Z,world,x,
        +3,1e3,YES,2024-01-07 10:30,hello,2024-01-01,
        """
        let result = try profile(csv)
        #expect(result.columns.map(\.name) == ["i", "d", "b", "dt", "t", "m", "e"])
        #expect(result.columns.map(\.type) == [.integer, .decimal, .boolean, .date, .text, .mixed, .empty])
    }

    @Test func integersAndDecimalsTogetherAreDecimalAndNumbersWithTextAreMixed() {
        #expect(only(["1", "2", "3.5"]).type == .decimal)
        #expect(only(["1", "2", "abc"]).type == .mixed)
        #expect(only(["true", "1"]).type == .mixed)
        #expect(only(["2024-01-05", "2024"]).type == .mixed)
        #expect(only(["", "  ", "\t"]).type == .empty)
        #expect(SafeDataProfile.make(from: SafeTable(columns: [], rows: [], truncation: [])).columns.isEmpty)
    }

    @Test func aThousandsSeparatorOrAnUnreadableNumberMakesATextColumn() {
        #expect(only(["1,234", "2,345"]).type == .text)
        #expect(only(["$5", "$6"]).type == .text)
        #expect(only(["NaN", "Infinity"]).type == .text)
        #expect(only(["1e999", "2"]).type == .decimal)
        // The overflowing value is counted as a number but has no value, so statistics skip it.
        let column = only(["1e999", "2", "4"])
        #expect(column.mean == 3)
        #expect(column.minimum == "2")
        #expect(column.maximum == "4")
    }

    // MARK: Missing

    @Test func missingCountsEmptyWhitespaceOnlyAndAbsentCellsAsAShareOfProfiledRows() throws {
        let column = only(["a", "", "b", " ", "c", "d", "e", "f"])
        #expect(column.missing == 2)
        let ragged = try profile("a,b\nx\ny\nz,1\n")
        #expect(ragged.columns[1].missing == 2)
        let table = SafeDataProfile.make(from: SafeTable(columns: ["v"], rows: ["a", "", "b", " ", "c", "d", "e", "f"].map { [$0] },
                                                         truncation: [])).displayTable(locale: english)
        #expect(cell(table, 0, .missing) == "2 (25%)")
    }

    @Test func missingPercentagesUseThePresentationLocale() throws {
        let result = try profile("a,b\nx\ny\nz,1\n")
        #expect(cell(result.displayTable(locale: english), 1, .missing) == "2 (66.7%)")
        let german = cell(result.displayTable(locale: german), 1, .missing)
        #expect(german.hasPrefix("2 (66,7"))
        #expect(german.contains("%"))
    }

    @Test func aTinyShareOfMissingValuesNeverRoundsToNone() {
        let rows = (0..<5_000).map { [$0 == 0 ? "" : "\($0)"] }
        let table = SafeDataProfile.make(from: SafeTable(columns: ["v"], rows: rows, truncation: [])).displayTable(locale: english)
        #expect(cell(table, 0, .missing) == "1 (0.02%)")
        let none = SafeDataProfile.make(from: SafeTable(columns: ["v"], rows: [], truncation: [])).displayTable(locale: english)
        #expect(cell(none, 0, .missing) == "0 (0%)")
    }

    @Test func anEmptyTableHasNoColumnsAndAHeaderOnlyTableHasEmptyOnes() throws {
        #expect(try profile("").columns.isEmpty)
        let headerOnly = try profile("a,b\n")
        #expect(headerOnly.columns.map(\.type) == [.empty, .empty])
        #expect(headerOnly.profiledRows == 0)
        #expect(cell(headerOnly.displayTable(locale: english), 0, .missing) == "0 (0%)")
        #expect(headerOnly.tableNotes.isEmpty)
    }

    // MARK: Distinct values

    @Test func distinctCountsAreExactAndEmptyCellsDoNotCount() {
        let column = only(["a", "b", "a", "", " ", "c", "b"])
        #expect(column.distinct == .init(count: 3, isLowerBound: false))
    }

    @Test func distinctCountsStopAtTheCapAndSayAtLeast() {
        let limits = SafeDataProfile.Limits(maximumDistinctValues: 3)
        let capped = values(["a", "b", "c", "d", "e", "a"], limits: limits)
        #expect(capped.columns[0].distinct == .init(count: 3, isLowerBound: true))
        #expect(cell(capped.displayTable(locale: english), 0, .distinct) == "At least 3")
        let exact = values(["a", "b", "c", "a", "b"], limits: limits)
        #expect(exact.columns[0].distinct == .init(count: 3, isLowerBound: false))
        #expect(cell(exact.displayTable(locale: english), 0, .distinct) == "3")
        // Counts that were already kept stay exact after the cap is reached.
        #expect(values(["a", "b", "c", "d", "a", "a"], limits: limits).columns[0].commonValues.first == .init(value: "a", count: 3))
    }

    @Test func aTallColumnOfUniqueValuesStaysExactBecauseTheDefaultCapMatchesTheRowSample() {
        #expect(SafeDataProfile.Limits().maximumDistinctValues == 10_000)
        #expect(SafeDataProfile.Limits().maximumRows == 10_000)
        let rows = (0..<12_000).map { ["id-\($0)"] }
        let result = SafeDataProfile.make(from: SafeTable(columns: ["id"], rows: rows, truncation: []))
        #expect(result.profiledRows == 10_000)
        #expect(result.columns[0].distinct == .init(count: 10_000, isLowerBound: false))
    }

    @Test func spellingsThatDifferOnlyByCanonicalEquivalenceAreDistinctValues() {
        let composed = "\u{E9}"
        let decomposed = "e\u{301}"
        #expect(composed == decomposed, "Swift folds these; the profile must not")
        let column = only([composed, decomposed, composed])
        #expect(column.distinct?.count == 2)
        #expect(column.commonValues.map(\.count) == [2, 1])
        #expect(column.commonValues[0].value.utf8.elementsEqual(composed.utf8))
        #expect(column.commonValues[1].value.utf8.elementsEqual(decomposed.utf8))
    }

    // MARK: Minimum, maximum and mean

    @Test func extremesKeepTheExactSourceSpelling() {
        let column = only(["007", "1e3", "-0.50", " 12 ", "0.5"])
        #expect(column.type == .decimal)
        #expect(column.minimum == "-0.50")
        #expect(column.maximum == "1e3")
        let integers = only(["007", "12", " 9 "])
        #expect(integers.minimum == "007")
        #expect(integers.maximum == "12")
        let padded = only([" 5 ", "3"])
        #expect(padded.maximum == " 5 ")
        let table = values(["007", "1e3", "-0.50"]).displayTable(locale: english)
        #expect(cell(table, 0, .minimum) == "-0.50")
        #expect(cell(table, 0, .maximum) == "1e3")
    }

    @Test func equalNumbersKeepTheFirstSpelling() {
        let column = only(["1.0", "1", "1e0", "1.00"])
        #expect(column.minimum == "1.0")
        #expect(column.maximum == "1.0")
    }

    @Test func isoDateExtremesOrderByInstantAndKeepTheirSpelling() {
        let column = only(["2024-03-01", "2023-12-31T23:59:59Z", "2024-01-15 10:00", "2024-01-01T00:00:00+02:00"])
        #expect(column.type == .date)
        // 2024-01-01T00:00+02:00 is 2023-12-31T22:00Z, which is earlier than 23:59:59Z.
        #expect(column.minimum == "2024-01-01T00:00:00+02:00")
        #expect(column.maximum == "2024-03-01")
        #expect(column.mean == nil)
        #expect(column.histogram == nil)
    }

    @Test func nonISODateColumnsOfferNoExtremes() {
        #expect(only(["01/05/2024", "03/05/2024"]).minimum == nil)
        #expect(only(["05.01.2024", "06.01.2024"]).maximum == nil)
        // Mixing spellings leaves the order undefined as well.
        let mixed = only(["2024-01-05", "01/05/2024"])
        #expect(mixed.type == .date)
        #expect(mixed.minimum == nil && mixed.maximum == nil)
    }

    @Test func textAndBooleanColumnsOfferNoExtremesOrMean() {
        let text = only(["b", "a"])
        #expect(text.minimum == nil && text.maximum == nil && text.mean == nil && text.histogram == nil)
        #expect(only(["true", "no"]).mean == nil)
        #expect(only(["1", "x"]).minimum == nil)
    }

    @Test func meanIsFormattedForThePresentationLocale() {
        let result = values(["1000", "1469"])
        #expect(result.columns[0].mean == 1_234.5)
        #expect(cell(result.displayTable(locale: english), 0, .mean) == "1,234.5")
        #expect(cell(result.displayTable(locale: german), 0, .mean) == "1.234,5")
    }

    @Test func meanKeepsSensibleDigitsAtEveryMagnitude() {
        func mean(_ cells: [String]) -> String { cell(values(cells).displayTable(locale: english), 0, .mean) }
        #expect(mean(["1", "2", "2"]) == "1.67")
        #expect(mean(["0.5"]) == "0.5")
        #expect(mean(["0.000123"]) == "0.000123")
        #expect(mean(["0.333333333"]) == "0.333")
        #expect(mean(["-2", "2"]) == "0")
        #expect(mean(["1e20"]).contains("E"))
        #expect(mean(["1e-12"]).contains("E"))
    }

    // MARK: Most common values

    @Test func commonValuesAreTheTopThreeWithCountsAndTiesKeepTheFirstSeen() {
        let column = only(["b", "a", "b", "a", "c", "d", "a", "c"])
        #expect(column.commonValues == [.init(value: "a", count: 3), .init(value: "b", count: 2), .init(value: "c", count: 2)])
        // A tie goes to the value that appeared first, whatever the dictionary order.
        let tie = only(["x", "y", "z", "w", "y", "z", "x"])
        #expect(tie.commonValues.map(\.value) == ["x", "y", "z"])
        #expect(tie.commonValues.map(\.count) == [2, 2, 2])
    }

    @Test func commonValuesAreExactCaseSensitiveAndSkipEmptyCells() {
        let column = only(["A", "a", "a", "", " ", "a "])
        #expect(column.commonValues == [.init(value: "a", count: 2), .init(value: "A", count: 1), .init(value: "a ", count: 1)])
    }

    @Test func numericAndEmptyColumnsListNoCommonValuesButBooleansAndDatesDo() {
        #expect(only(["1", "1", "2"]).commonValues.isEmpty)
        #expect(only(["", ""]).commonValues.isEmpty)
        #expect(only(["true", "true", "no"]).commonValues == [.init(value: "true", count: 2), .init(value: "no", count: 1)])
        #expect(only(["2024-01-05", "2024-01-05"]).commonValues == [.init(value: "2024-01-05", count: 2)])
    }

    @Test func commonValuesAppearInTheTableWithLocaleFormattedCountsAndAListedSpokenForm() {
        let rows = (0..<1_234).map { _ in ["a"] } + [["b"], ["b"]]
        let result = SafeDataProfile.make(from: SafeTable(columns: ["v"], rows: rows, truncation: []))
        let table = result.displayTable(locale: english)
        #expect(cell(table, 0, .common) == "a (1,234) · b (2)")
        #expect(table.description(row: 0, column: Field.common.rawValue) == "a (1,234) and b (2)")
        #expect(cell(result.displayTable(locale: german), 0, .common) == "a (1.234) · b (2)")
        // One value needs no separate spoken form.
        #expect(cell(values(["a"]).displayTable(locale: english), 0, .common) == "a (1)")
        #expect(values(["a"]).displayTable(locale: english).description(row: 0, column: Field.common.rawValue) == nil)
    }

    // MARK: Distribution

    @Test func eightBinsSpreadBetweenTheExtremesAndTheLastValueLandsInTheLastBin() {
        let column = only((0...10).map(String.init))
        #expect(column.histogram == .init(bins: [2, 1, 1, 1, 2, 1, 1, 2], lower: "0", upper: "10"))
        #expect(SafeDataProfile.sparkline(for: column.histogram!.bins) == "█▅▅▅█▅▅█")
    }

    @Test func aSparseBinStaysDistinctFromAnEmptyOne() {
        let column = only(Array(repeating: "0", count: 20) + ["100"])
        #expect(column.histogram?.bins == [20, 0, 0, 0, 0, 0, 0, 1])
        #expect(SafeDataProfile.sparkline(for: column.histogram!.bins) == "█▁▁▁▁▁▁▂")
    }

    @Test func aSingleValueFillsTheFirstBin() {
        let column = only(["5", "5", "5"])
        #expect(column.histogram?.bins == [3, 0, 0, 0, 0, 0, 0, 0])
        #expect(SafeDataProfile.sparkline(for: column.histogram!.bins) == "█▁▁▁▁▁▁▁")
        #expect(SafeDataProfile.sparkline(for: [0, 0, 0]) == "▁▁▁")
    }

    @Test func extremeMagnitudesDoNotOverflowTheBinning() {
        let column = only(["-1e308", "0", "1e308", "1.7e308"])
        #expect(column.histogram?.bins.reduce(0, +) == 4)
        #expect(column.histogram?.bins.count == 8)
    }

    @Test func theSparklineHasASpokenDescriptionWithoutBlockCharacters() {
        let table = values((0...10).map(String.init)).displayTable(locale: english)
        let visible = cell(table, 0, .distribution)
        #expect(visible == "█▅▅▅█▅▅█")
        let spoken = table.description(row: 0, column: Field.distribution.rawValue)
        #expect(spoken == "Distribution from 0 to 10 in 8 ranges, with counts 2, 1, 1, 1, 2, 1, 1, and 2")
        #expect(spoken?.contains { sparkBars.contains($0) } == false)
        // Only the described cell differs; every other cell is read as its text.
        #expect(table.description(row: 0, column: Field.mean.rawValue) == nil)
    }

    @Test func theSpokenCountsFollowThePresentationLocale() {
        let spoken = values((0...10).map(String.init)).displayTable(locale: german)
            .description(row: 0, column: Field.distribution.rawValue)
        #expect(spoken?.hasPrefix("Distribution from 0 to 10 in 8 ranges") == true)
        #expect(spoken?.contains(" und ") == true, "German list formatting joins the last count with und")
    }

    @Test func onlyNumericColumnsHaveADistribution() throws {
        let result = try profile("n,t\n1,a\n2,b\n")
        #expect(result.columns[0].histogram != nil)
        #expect(result.columns[1].histogram == nil)
        #expect(cell(result.displayTable(locale: english), 1, .distribution) == "")
        #expect(result.displayTable(locale: english).description(row: 1, column: Field.distribution.rawValue) == nil)
    }

    // MARK: Quality notes

    @Test func mixedTypesListTheKindsWithCountsLargestFirst() {
        let column = only(["1", "2", "3", "x", "2024-01-01", "y", "z"])
        #expect(column.type == .mixed)
        #expect(column.notes == [.mixedTypes([.init(type: .integer, count: 3), .init(type: .text, count: 3), .init(type: .date, count: 1)])])
        let table = values(["1", "2", "3", "x", "2024-01-01", "y", "z"]).displayTable(locale: english)
        #expect(cell(table, 0, .notes) == "Mixed types: Integer: 3, Text: 3, and Date: 1")
    }

    @Test func leadingZerosAreCountedOnNumericLookingValues() {
        let column = only(["007", "12", "0", "0.5", "00", "02134"])
        #expect(column.notes == [.leadingZeros(3)])
        #expect(cell(values(["007", "12", "02134"]).displayTable(locale: english), 0, .notes)
            == "Values with leading zeros: 2 (a spreadsheet may drop the zeros)")
        #expect(only(["0", "10", "100", "0.5"]).notes.isEmpty)
        #expect(only(["abc", "0", "10"]).notes.allSatisfy { if case .mixedTypes = $0 { true } else { false } })
    }

    @Test func inconsistentDateFormatsListTheSpellingsInUse() {
        let column = only(["2024-01-05", "01/05/2024", "05.01.2024", "2024-01-06T10:00"])
        #expect(column.type == .date)
        #expect(column.notes == [.inconsistentDateFormats([.iso, .monthDayYear, .dotted])])
        #expect(cell(values(["2024-01-05", "01/05/2024"]).displayTable(locale: english), 0, .notes)
            == "Date formats differ: yyyy-mm-dd and mm/dd/yyyy")
        // Date-only and date-time ISO spellings are one format.
        #expect(only(["2024-01-05", "2024-01-06T10:00:00Z", "2024-01-07 11:00"]).notes.isEmpty)
        // The note also applies when other values make the column mixed.
        #expect(only(["2024-01-05", "01/05/2024", "x"]).notes.contains(.inconsistentDateFormats([.iso, .monthDayYear])))
    }

    @Test func surroundingWhitespaceIsCountedButWhitespaceOnlyCellsAreMissing() {
        let column = only(["a ", " b", "c", "   ", "\u{2003}d\u{2003}"])
        #expect(column.notes == [.surroundingWhitespace(3)])
        #expect(column.missing == 1)
        #expect(cell(values(["a ", " b", "c"]).displayTable(locale: english), 0, .notes) == "Values with surrounding spaces: 2")
        // Whitespace around a number leaves it a number.
        #expect(only([" 1 ", "2"]).type == .integer)
        #expect(only([" 1 ", "2"]).notes == [.surroundingWhitespace(1)])
    }

    @Test func noteOrderIsStableAndEachNoteAppearsOnce() {
        let column = only([" 007", "x", "2024-01-05", "01/05/2024"], name: "id")
        #expect(column.notes.count == 4)
        if case .mixedTypes = column.notes[0] {} else { Issue.record("mixed types first") }
        #expect(column.notes[1] == .leadingZeros(1))
        #expect(column.notes[2] == .inconsistentDateFormats([.iso, .monthDayYear]))
        #expect(column.notes[3] == .surroundingWhitespace(1))
    }

    @Test func notesFromSeveralKindsJoinWithASeparatorAndAreSpokenAsAList() {
        let table = values(["007 ", "x"]).displayTable(locale: english)
        #expect(cell(table, 0, .notes) == "Mixed types: Integer: 1 and Text: 1 · Values with leading zeros: 1 (a spreadsheet may drop the zeros) · Values with surrounding spaces: 1")
        #expect(table.description(row: 0, column: Field.notes.rawValue)?.hasSuffix(", and Values with surrounding spaces: 1") == true)
    }

    // MARK: Table-level notes

    @Test func duplicateHeaderNamesAreNotedPerColumnAndForTheTable() throws {
        let result = try profile("id,name,id,Name\n1,a,2,b\n")
        #expect(result.columns.map { $0.notes.contains(.duplicateName) } == [true, false, true, false])
        #expect(result.tableNotes == [.duplicateNames(2)])
        #expect(cell(result.displayTable(locale: english), 0, .notes) == "Column name is used more than once")
        #expect(result.statusLines(locale: english) == ["Columns that share a name with another column: 2"])
        #expect(try profile("a,b\n1,2\n").tableNotes.isEmpty)
    }

    @Test func titlesComparedByCodeUnitsKeepCanonicalLookalikesApart() {
        let result = SafeDataProfile.make(from: SafeTable(columns: ["\u{E9}", "e\u{301}", "\u{E9}"], rows: [], truncation: []))
        #expect(result.columns.map { $0.notes.contains(.duplicateName) } == [true, false, true])
    }

    @Test func aConcealedHeaderNeverCountsAsADuplicateName() {
        let result = SafeDataProfile.make(from: SafeTable(columns: [token, token, "a"], rows: [["1", "2", "3"]], truncation: []))
        #expect(!result.tableNotes.contains { if case .duplicateNames = $0 { true } else { false } })
    }

    @Test func raggedRowsDifferFromTheHeaderWidthInEitherDirection() throws {
        let result = try profile("a,b\n1\n1,2\n1,2,3\n")
        #expect(result.tableNotes == [.raggedRows(2)])
        #expect(result.statusLines(locale: english) == ["Rows with a different number of fields than the header: 2"])
        let shortRows = try profile("a,b,c\n1,2,3\n1,2\n")
        #expect(shortRows.tableNotes == [.raggedRows(1)])
        #expect(try profile("a,b\n1,2\n3,4\n").tableNotes.isEmpty)
        // Without a known header width the table width is the reference.
        let direct = SafeDataProfile.make(from: SafeTable(columns: ["a", "b"], rows: [["1"], ["1", "2"]], truncation: []))
        #expect(direct.tableNotes == [.raggedRows(1)])
    }

    @Test func raggedRowsAreCountedAmongTheProfiledRowsOnly() throws {
        let limits = SafeDataProfile.Limits(maximumRows: 2)
        let result = SafeDataProfile.make(from: try parse("a,b\n1,2\n3,4\n5\n6\n"), limits: limits)
        #expect(result.tableNotes == [.sampled(profiled: 2, total: 4)])
    }

    @Test func aTallTableIsSampledFromItsFirstRowsAndSaysSo() {
        let rows = (0..<25).map { [String($0)] }
        let limits = SafeDataProfile.Limits(maximumRows: 10)
        let result = SafeDataProfile.make(from: SafeTable(columns: ["n"], rows: rows, truncation: []), limits: limits)
        #expect(result.profiledRows == 10 && result.totalRows == 25)
        #expect(result.tableNotes == [.sampled(profiled: 10, total: 25)])
        #expect(result.columns[0].maximum == "9")
        #expect(result.statusLines(locale: english) == ["Rows profiled: 10 of 25"])
        let defaults = SafeDataProfile.make(from: SafeTable(columns: ["n"], rows: (0..<10_001).map { [String($0)] }, truncation: []))
        #expect(defaults.tableNotes == [.sampled(profiled: 10_000, total: 10_001)])
        #expect(defaults.statusLines(locale: english) == ["Rows profiled: 10,000 of 10,001"])
        #expect(defaults.statusLines(locale: german) == ["Rows profiled: 10.000 of 10.001"])
        let whole = SafeDataProfile.make(from: SafeTable(columns: ["n"], rows: rows, truncation: []))
        #expect(whole.tableNotes.isEmpty)
    }

    @Test func theShortenedTableNoticeCarriesOverToTheProfile() throws {
        let table = SafeTable(columns: ["a"], rows: [["1"]], truncation: [.rows, .cells])
        let result = SafeDataProfile.make(from: table)
        #expect(result.displayTable(locale: english).truncation == [.rows, .cells])
        #expect(try profile("a\n1\n").displayTable(locale: english).truncation.isEmpty)
    }

    // MARK: Concealment

    @Test func aColumnWithASensitiveHeaderShowsOnlyItsMissingCount() throws {
        let secret = "hunter2-synthetic"
        let result = SafeDataProfile.make(from: SafeTable(
            columns: ["name", "password", "API_KEY", "Client Secret"],
            rows: [["alice", secret, secret, secret], ["bob", "", "7", "007"], ["carol", secret, " ", "1e3"]], truncation: []))
        #expect(result.columns[0].type == .text)
        for column in result.columns[1...] {
            #expect(column.type == .concealed)
            #expect(column.distinct == nil && column.minimum == nil && column.maximum == nil && column.mean == nil)
            #expect(column.commonValues.isEmpty && column.histogram == nil && column.notes.isEmpty)
        }
        #expect(result.columns.map(\.missing) == [0, 1, 1, 0])
        let visible = everyVisibleString(result)
        #expect(!visible.contains { $0.contains(secret) })
        let table = result.displayTable(locale: english)
        for row in 1...3 {
            #expect(cell(table, row, .type) == "Concealed")
            for field in [Field.distinct, .minimum, .maximum, .mean, .common, .distribution, .notes] { #expect(cell(table, row, field) == "") }
            #expect(table.description(row: row, column: Field.common.rawValue) == nil)
            #expect(table.description(row: row, column: Field.notes.rawValue) == nil)
        }
        #expect(cell(table, 1, .missing) == "1 (33.3%)")
        #expect(cell(table, 2, .missing) == "1 (33.3%)")
        #expect(cell(table, 3, .missing) == "0 (0%)")
    }

    @Test func aConcealmentTokenInAnyCellConcealsThatColumnOnly() throws {
        let result = try profile("name,note,count\nalice,fine,1\nbob,••••,2\ncarol,,3\n")
        #expect(result.columns.map(\.type) == [.text, .concealed, .integer])
        #expect(result.columns[1].missing == 1)
        #expect(result.columns[2].mean == 2)
        let visible = everyVisibleString(result)
        #expect(!visible.contains { $0.contains("fine") })
        #expect(!visible.contains { $0.contains(token) })
        #expect(result.tableNotes == [.concealedColumns(1)])
        #expect(result.statusLines(locale: english) == ["Columns with concealed values show only how many cells are empty."])
    }

    @Test func aColumnConcealedByTheTokenAlonePassesNoStatisticOrValueThrough() {
        let cells = ["red", "red", "••••", "blue", "007", "12 ", ""]
        let result = values(cells, name: "colour")
        let column = result.columns[0]
        #expect(column.type == .concealed)
        #expect(column.missing == 1)
        #expect(column.distinct == nil && column.mean == nil && column.minimum == nil && column.maximum == nil)
        #expect(column.commonValues.isEmpty && column.histogram == nil && column.notes.isEmpty)
        let visible = everyVisibleString(result).filter { $0 != "colour" }
        for hidden in ["red", "blue", "007", "12", token, "Mixed", "Leading", "Surrounding"] {
            #expect(!visible.contains { $0.contains(hidden) }, "leaked \(hidden)")
        }
    }

    @Test func theTokenIsFoundByCodeUnitsEvenWhenACombiningMarkFollowsIt() {
        // The combining acute joins the last bullet into one grapheme, so a character search misses the token.
        let merged = "••••\u{301}"
        let tokenBytes = Array(token.utf8)
        #expect(SafeDataProfile.containsToken(merged, tokenBytes))
        #expect(only(["fine", merged], name: "x").type == .concealed)
        #expect(only(["a\u{301}••••\u{301}b"], name: "x").type == .concealed)
        #expect(only(["token: ••••"], name: "x").type == .concealed)
        // Three bullets, or bullets separated by something, are not the token.
        #expect(only(["•••"], name: "x").type == .text)
        #expect(only(["•••• •"], name: "x").type == .concealed)
        #expect(only(["••• •"], name: "x").type == .text)
        #expect(!SafeDataProfile.containsToken("", tokenBytes))
        #expect(SafeDataProfile.containsToken("\(token)", tokenBytes))
    }

    @Test func aTokenInTheHeaderCellConcealsItsColumn() {
        let result = SafeDataProfile.make(from: SafeTable(columns: [token, "n"], rows: [["secret-a", "1"], ["secret-b", "2"]], truncation: []))
        #expect(result.columns.map(\.type) == [.concealed, .integer])
        #expect(!everyVisibleString(result).contains { $0.contains("secret-") })
    }

    @Test func aTokenBeyondTheProfiledRowsStillConcealsTheColumn() {
        let rows = [["a"], ["b"], ["c"], ["d"], [token]]
        let result = SafeDataProfile.make(from: SafeTable(columns: ["note"], rows: rows, truncation: []),
                                          limits: .init(maximumRows: 2))
        #expect(result.columns[0].type == .concealed)
        #expect(result.profiledRows == 2)
        #expect(!everyVisibleString(result).contains { $0 == "a" || $0 == "b" })
    }

    @Test func overflowCellsConcealedBeyondTheHeaderWidthConcealTheirColumns() throws {
        let result = try profile("name,password\nalice,••••,••••\nbob,••••\n")
        #expect(result.columns.map(\.type) == [.text, .concealed, .concealed])
        #expect(result.tableNotes == [.raggedRows(1), .concealedColumns(2)])
    }

    @Test func concealmentDoesNotTouchEmptyCellsOrOtherColumns() throws {
        let result = try profile("token,visible\n••••,1\n,2\n  ,3\n••••,4\n")
        #expect(result.columns[0].type == .concealed)
        #expect(result.columns[0].missing == 2)
        #expect(result.columns[1].type == .integer)
        #expect(result.columns[1].minimum == "1" && result.columns[1].maximum == "4")
    }

    @Test func aColumnThatIsAllEmptyUnderASensitiveHeaderIsStillConcealed() {
        let result = SafeDataProfile.make(from: SafeTable(columns: ["password"], rows: [[""], [""]], truncation: []))
        #expect(result.columns[0].type == .concealed)
        #expect(result.columns[0].missing == 2)
        #expect(cell(result.displayTable(locale: english), 0, .missing) == "2 (100%)")
    }

    @Test func aConcealedColumnNeverReceivesTheDuplicateNameNote() {
        let result = SafeDataProfile.make(from: SafeTable(columns: ["password", "password"], rows: [], truncation: []))
        #expect(result.columns.allSatisfy { $0.type == .concealed && $0.notes.isEmpty })
        // The table-level count still reports the shared name, which is metadata, not content.
        #expect(result.tableNotes.contains(.duplicateNames(2)))
    }

    @Test func pipelineStyleConcealedCsvNeverShowsTheRawSecretOrTheToken() throws {
        let csv = "name,password,note\nalice,••••,\"hello, world\"\nbob,••••,ok\ncarol,,\n"
        let result = try profile(csv)
        let table = result.displayTable(locale: english)
        #expect(result.columns.map(\.type) == [.text, .concealed, .text])
        #expect(cell(table, 1, .missing) == "1 (33.3%)")
        #expect(!everyVisibleString(result).contains { $0.contains(token) })
        #expect(cell(table, 2, .common) == "hello, world (1) · ok (1)")
    }

    // MARK: Table integration

    @Test func theProfileTableHasOneRowPerSourceColumnAndTheDocumentedHeaders() throws {
        let result = try profile("a,b,c\n1,x,true\n")
        let table = result.displayTable(locale: english)
        #expect(table.columns == ["Column", "Type", "Missing", "Distinct", "Minimum", "Maximum", "Mean", "Most common", "Distribution", "Notes"])
        #expect(table.columns.count == Field.allCases.count)
        #expect(table.rows.count == 3)
        #expect(table.rows.allSatisfy { $0.count == 10 })
        #expect(table.rows.map { $0[0] } == ["a", "b", "c"])
        #expect(table.rows.map { $0[Field.type.rawValue] } == ["Integer", "Text", "Boolean"])
        #expect(table.headerFieldCount == 10)
    }

    @Test func aSampleProfileReadsAsText() throws {
        let csv = """
        id,price,state,joined,zip,password
        1,10.5,open,2024-01-05,02134,••••
        2,12,open,2024-02-10,10001,••••
        3,,closed,2024-02-11,,••••
        4,8.25,open,2024-03-01,94105,••••
        """
        let result = try profile(csv)
        let table = result.displayTable(locale: english)
        #expect(table.rows == [
            ["id", "Integer", "0 (0%)", "4", "1", "4", "2.5", "", "█▁█▁▁█▁█", ""],
            ["price", "Decimal", "1 (25%)", "3", "8.25", "12", "10.25", "", "█▁▁▁█▁▁█", ""],
            ["state", "Text", "0 (0%)", "2", "", "", "", "open (3) · closed (1)", "", ""],
            ["joined", "Date", "0 (0%)", "4", "2024-01-05", "2024-03-01", "",
             "2024-01-05 (1) · 2024-02-10 (1) · 2024-02-11 (1)", "", ""],
            ["zip", "Integer", "1 (25%)", "3", "02134", "94105", "35,413.33", "", "█▁▁▁▁▁▁▅",
             "Values with leading zeros: 1 (a spreadsheet may drop the zeros)"],
            ["password", "Concealed", "0 (0%)", "", "", "", "", "", "", ""]
        ])
        #expect(result.statusLines(locale: english) == ["Columns with concealed values show only how many cells are empty."])
    }

    @Test func aSampleLargerThanTheCapIsBoundedByTheRowLimit() {
        let rows = (0..<30_000).map { [String($0 % 7), "x"] }
        let result = SafeDataProfile.make(from: SafeTable(columns: ["n", "t"], rows: rows, truncation: [.rows]))
        #expect(result.profiledRows == 10_000)
        #expect(result.totalRows == 30_000)
        #expect(result.columns[0].distinct == .init(count: 7, isLowerBound: false))
        #expect(result.columns[1].commonValues == [.init(value: "x", count: 10_000)])
    }

    @Test func profilesAreValueTypesThatCompareByExactContent() throws {
        let one = try profile("a,b\n1,2\n")
        let same = try profile("a,b\n1,2\n")
        #expect(one == same)
        #expect(one != (try profile("a,b\n1,3\n")))
        #expect(one.displayTable(locale: english) == same.displayTable(locale: english))
    }

    @Test func theParserRecordsTheHeaderWidthBeforeTheColumnCap() throws {
        #expect(try parse("a,b\n1,2,3\n").headerFieldCount == 2)
        #expect(try parse("a,b\n1,2,3\n").columns.count == 3)
        #expect(try parse("").headerFieldCount == nil)
        let wide = (0..<70).map { "c\($0)" }.joined(separator: ",")
        let table = try parse(wide + "\n" + (0..<70).map(String.init).joined(separator: ",") + "\n")
        #expect(table.headerFieldCount == 70)
        #expect(table.columns.count == 64)
        // Both the header and the row are cut to 64 fields, so the cap alone is not a ragged row.
        #expect(SafeDataProfile.make(from: table).tableNotes.isEmpty)
        #expect(try parse("a\t\tb\n1\t2\t3\n", syntax: .tabSeparated).headerFieldCount == 3)
    }

    /// Timing harness: `PREV_PROFILE_BENCHMARK=1 swift test -c release -Xswiftc -enable-testing --filter timesAFullSizedTable`.
    @Test func timesAFullSizedTable() {
        let columns = 64
        let rows = 20_000
        let header = (0..<columns).map { "col\($0)" }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int { state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; return Int(truncatingIfNeeded: state >> 33) }
        let body: [[String]] = (0..<rows).map { _ in
            (0..<columns).map { column in
                switch column % 8 {
                case 0: return String(next() % 100_000)
                case 1: return "\(next() % 1_000).\(next() % 100)"
                case 2: return ["true", "false", "yes", "no"][next() % 4]
                case 3: return "2024-\(String(format: "%02d", 1 + next() % 12))-\(String(format: "%02d", 1 + next() % 28))"
                case 4: return ["north", "south", "east", "west", "up", "down"][next() % 6]
                case 5: return next() % 11 == 0 ? "" : "name-\(next() % 5_000)"
                case 6: return String(format: "%07d", next() % 100_000)
                default: return "free text value number \(next() % 10_000)"
                }
            }
        }
        let table = SafeTable(columns: header, rows: body, truncation: [])
        let clock = ContinuousClock()
        var result: SafeDataProfile?
        let profiling = clock.measure { result = SafeDataProfile.make(from: table) }
        // The first rendering loads the string resources, which the host has done long before a preview.
        _ = result?.displayTable(locale: english)
        let rendering = clock.measure { _ = result?.displayTable(locale: english) }
        #expect(result?.profiledRows == 10_000)
        #expect(result?.columns.count == 64)
        if ProcessInfo.processInfo.environment["PREV_PROFILE_BENCHMARK"] != nil {
            print("PROFILE-TIMING 20000x64 profile=\(profiling) table=\(rendering)")
        }
        // A loose ceiling that a debug build also meets; the Release target is recorded by the benchmark above.
        #expect(profiling < .seconds(60))
    }
}

@Suite("Data profile mode", .serialized)
@MainActor
struct DataProfileModeTests {
    private func presentation(_ text: String, format: FormatID = .csv, syntax: TextSyntax = .commaSeparated,
                              redactions: Int = 0) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: text.split(separator: "\n").count, byteCount: text.utf8.count,
                         encoding: .utf8, redactionCount: redactions, syntax: syntax)
    }

    private func makeView() -> NativePreviewView { NativePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 360)) }

    private func modeControl(_ view: NativePreviewView) throws -> NSSegmentedControl {
        view.modeControl
    }

    private func titles(_ view: NativePreviewView) throws -> [String] {
        let control = try modeControl(view)
        guard !control.isHidden else { return [] }
        return (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
    }

    private func select(_ key: PreviewStrings.Key, in view: NativePreviewView) throws {
        let control = try modeControl(view)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == PreviewStrings.text(key) })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }

    private func pane(_ view: NativePreviewView) throws -> NativeTablePreviewView {
        try #require(descendants(of: NativeTablePreviewView.self, in: view).first)
    }

    private func statusText(_ view: NativePreviewView) throws -> String {
        view.displayedStatus
    }

    private func field(_ pane: NativeTablePreviewView, _ row: Int, _ column: Int) throws -> NSTextField {
        try #require(pane.tableView(pane.tableView, viewFor: pane.tableView.tableColumns[column], row: row) as? NSTextField)
    }

    private func allCells(_ pane: NativeTablePreviewView) throws -> [String] {
        var cells: [String] = []
        for row in 0..<pane.tableView.numberOfRows {
            for column in 0..<pane.tableView.numberOfColumns { cells.append(try field(pane, row, column).stringValue) }
        }
        return cells
    }

    private let csv = "name,score,joined\nalice,10,2024-01-05\nbob,20,2024-02-01\ncarol,,2024-03-09\n"

    // MARK: Availability

    @Test func profileFollowsTableForCSVAndTSVAndIsNeverTheInitialMode() throws {
        for (format, syntax, text) in [(FormatID.csv, TextSyntax.commaSeparated, "a,b\n1,2\n"), (.tsv, .tabSeparated, "a\tb\n1\t2\n")] {
            let modes = SafePreviewModes(presentation(text, format: format, syntax: syntax), locale: english)
            #expect(modes.available == [.source, .table, .profile])
            #expect(modes.initialMode(for: format) == .table)
            #expect(modes.available.first == .source)
            #expect(modes.profile != nil)
        }
        #expect(NativePreviewMode.profile.title == .previewModeProfile)
        #expect(PreviewStrings.text(.previewModeProfile) == "Profile")
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        #expect(try titles(view) == [PreviewStrings.text(.previewModeSource), PreviewStrings.text(.previewModeTable),
                                     PreviewStrings.text(.previewModeProfile)])
        #expect(try modeControl(view).selectedSegment == 1)
        #expect(try !pane(view).isHidden)
    }

    @Test func sourceOnlyAndFallbackPresentationsHaveNoProfileMode() throws {
        let plain = SafePreviewModes(presentation("a,b\n1,2\n", format: .plainText, syntax: .plain), locale: english)
        #expect(plain.available == [.source])
        #expect(plain.profile == nil)
        let json = SafePreviewModes(presentation("{\"a\":1}", format: .json, syntax: .json), locale: english)
        #expect(!json.available.contains(.profile))
        let malformed = SafePreviewModes(presentation("a,b\n\"never closed\n"), locale: english)
        #expect(malformed.available == [.source])
        #expect(malformed.profile == nil)
        #expect(malformed.displayedTable(for: .profile) == nil)
        #expect(malformed.hasStructureFallback)
    }

    @Test func malformedSafeTextFallsBackToSafeSourceInTheViewAsItDoesForTheTable() throws {
        let view = makeView()
        let text = "name,note\nalice,\"never closed\n"
        view.display(.ready(presentation(text)), locale: english)
        #expect(try titles(view).isEmpty, "Source only: the mode control is hidden")
        #expect(try pane(view).isHidden)
        #expect(!view.dataProfileIsComputed)
        let source = view.scrollView.documentView as? NSTextView
        #expect(source?.string == text)
    }

    // MARK: Laziness

    @Test func theProfileIsComputedOnlyWhenSelectedAndThenKept() throws {
        let modes = SafePreviewModes(presentation(csv), locale: english)
        let lazy = try #require(modes.profile)
        #expect(!lazy.isComputed)
        #expect(modes.displayedTable(for: .table) != nil)
        #expect(modes.displayedTable(for: .source) == nil)
        #expect(!lazy.isComputed, "Showing the table or the source never builds the profile")
        let first = modes.displayedTable(for: .profile)
        #expect(lazy.isComputed)
        let second = modes.displayedTable(for: .profile)
        #expect(first == second)
        #expect(lazy.value.table == first)
        #expect(lazy.value.profile.columns.count == 3)

        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        #expect(!view.dataProfileIsComputed)
        try select(.previewModeSource, in: view)
        #expect(!view.dataProfileIsComputed)
        try select(.previewModeProfile, in: view)
        #expect(view.dataProfileIsComputed)
        try select(.previewModeTable, in: view)
        #expect(view.dataProfileIsComputed, "Leaving Profile keeps its result for the same presentation")
    }

    // MARK: Display

    @Test func profileShowsOneRowPerSourceColumnWithLocalizedHeaders() throws {
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        #expect(!pane.isHidden)
        #expect(pane.tableView.tableColumns.map(\.title) == (SafeDataProfile.Field.allCases.map { PreviewStrings.text($0.title) }))
        #expect(pane.tableView.numberOfRows == 3)
        #expect(pane.tableView.numberOfColumns == 10)
        #expect(try field(pane, 0, 0).stringValue == "name")
        #expect(try field(pane, 1, 1).stringValue == "Integer")
        #expect(try field(pane, 1, SafeDataProfile.Field.mean.rawValue).stringValue == "15")
        #expect(try field(pane, 1, SafeDataProfile.Field.missing.rawValue).stringValue == "1 (33.3%)")
        #expect(try field(pane, 2, SafeDataProfile.Field.minimum.rawValue).stringValue == "2024-01-05")
        #expect(pane.tableView.accessibilityLabel() == PreviewStrings.format(
            .previewTableAccessibilityLabel, arguments: [Int64(3), Int64(10)], locale: english))
        // Switching back shows the data table again.
        try select(.previewModeTable, in: view)
        #expect(pane.tableView.numberOfRows == 3)
        #expect(pane.tableView.tableColumns.map(\.title) == ["name", "score", "joined"])
    }

    @Test func tableLevelNotesAppearInTheStatusLineOnlyInProfileMode() throws {
        let view = makeView()
        view.display(.ready(presentation("a,b,a\n1\n2,3,4\n")), locale: english)
        let ordinary = try statusText(view)
        #expect(!ordinary.contains("Rows with a different number"))
        try select(.previewModeProfile, in: view)
        let profiled = try statusText(view)
        #expect(profiled.contains("Rows with a different number of fields than the header: 1"))
        #expect(profiled.contains("Columns that share a name with another column: 2"))
        try select(.previewModeTable, in: view)
        #expect(try statusText(view) == ordinary)
    }

    @Test func aSampledTallTableSaysHowManyRowsWereProfiled() throws {
        let view = makeView()
        let text = "n\n" + (0..<10_050).map(String.init).joined(separator: "\n") + "\n"
        view.display(.ready(presentation(text)), locale: english)
        try select(.previewModeProfile, in: view)
        // The sampling note is not shown (owner, 2026-10-15); the limits strip names the rows the profile uses.
        #expect(try !statusText(view).contains("Rows profiled"))
        let pane = try pane(view)
        #expect(pane.tableView.numberOfRows == 1)
        #expect(try field(pane, 0, SafeDataProfile.Field.maximum.rawValue).stringValue == "9999")
    }

    @Test func aShortenedSourceTableKeepsItsTypedLimitInTheProfile() throws {
        let truncated = SafeTable(columns: ["a"], rows: [["1"]], truncation: [.rows])
        let source = presentation("a\n1\n")
        var modes = SafePreviewModes(source, locale: english)
        modes.table = truncated
        let profile = LazyDataProfile(source: truncated, locale: english)
        modes.profile = profile
        let pane = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        pane.display(profile.value.table, typography: .init(),
                     palette: .init(theme: .system, isDark: false, increasedContrast: false), syntaxStyle: .init(), locale: english)
        let notice = PreviewStrings.count(.previewProfileShownRows, 1, locale: english)
        #expect(ModePresentationNotices.notices(for: source, modes: modes, mode: .profile, locale: english)
            == [.init(kind: .limit, text: notice)])
        #expect(!descendants(of: NSTextField.self, in: pane).contains { $0.stringValue == notice })
        #expect(pane.tableView.numberOfRows == 1)
    }

    // MARK: Appearance, locale and replacement

    @Test func restylingKeepsTheProfileColumnsRowsSelectionAndCache() throws {
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        let columns = pane.tableView.tableColumns
        pane.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        view.display(.ready(presentation(csv)), typography: .init(fontSize: 18), theme: .dark, syntaxStyle: .init(usesColor: false),
                     locale: english)
        #expect(pane.tableView.tableColumns.elementsEqual(columns, by: ===), "Restyling must not rebuild the profile columns")
        #expect(pane.tableView.selectedRowIndexes == IndexSet(integer: 1))
        #expect(pane.tableView.numberOfRows == 3)
        #expect(view.dataProfileIsComputed)
        let attributes = try field(pane, 0, 0).attributedStringValue.attributes(at: 0, effectiveRange: nil)
        #expect((attributes[.font] as? NSFont)?.pointSize == 18)
        #expect(try field(pane, 1, SafeDataProfile.Field.mean.rawValue).stringValue == "15")
    }

    @Test func aLocaleChangeRebuildsTheProfileInTheNewLocale() throws {
        let view = makeView()
        let text = "price\n1000\n1469\n"
        view.display(.ready(presentation(text)), locale: english)
        try select(.previewModeProfile, in: view)
        let meanColumn = SafeDataProfile.Field.mean.rawValue
        #expect(try field(pane(view), 0, meanColumn).stringValue == "1,234.5")
        view.display(.ready(presentation(text)), locale: german)
        #expect(try field(pane(view), 0, meanColumn).stringValue == "1.234,5")
        #expect(try modeControl(view).selectedSegment == 2, "Profile stays selected across a locale change")
        view.display(.ready(presentation(text)), locale: english)
        #expect(try field(pane(view), 0, meanColumn).stringValue == "1,234.5")
    }

    @Test func aReplacementPresentationDropsTheOldProfile() throws {
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        try select(.previewModeProfile, in: view)
        #expect(view.dataProfileIsComputed)
        try select(.previewModeTable, in: view)
        view.display(.ready(presentation("x,y\n1,2\n")), locale: english)
        #expect(!view.dataProfileIsComputed, "The new presentation has not been profiled yet")
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        #expect(pane.tableView.numberOfRows == 2)
        #expect(try field(pane, 0, 0).stringValue == "x")
        #expect(try allCells(pane).contains("alice") == false)
        // The same mode stays selected when a same-format replacement arrives.
        view.display(.ready(presentation(csv)), locale: english)
        #expect(try modeControl(view).selectedSegment == 2)
        #expect(pane.tableView.numberOfRows == 3)
        #expect(try field(pane, 2, 0).stringValue == "joined")
        view.display(.unavailable(.malformedDocument))
        #expect(!view.dataProfileIsComputed)
        #expect(pane.tableView.numberOfRows == 0 && pane.isHidden)
        view.display(.ready(presentation(csv)), locale: english, resetsContentState: true)
        #expect(!view.dataProfileIsComputed)
    }

    @Test func aReplacementWithoutATableLeavesNoProfileBehind() throws {
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        try select(.previewModeProfile, in: view)
        view.display(.ready(presentation("just text", format: .plainText, syntax: .plain)), locale: english)
        #expect(!view.dataProfileIsComputed)
        #expect(try pane(view).isHidden)
        #expect(try titles(view).isEmpty)
    }

    // MARK: Privacy

    @Test func concealedColumnsShowNoValueAnywhereInTheProfileView() throws {
        let text = "name,password,note\nalice,••••,fine\nbob,••••,••••\ncarol,,ok\n"
        let view = makeView()
        view.display(.ready(presentation(text, redactions: 3)), locale: english)
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        let cells = try allCells(pane)
        #expect(!cells.contains { $0.contains("••••") })
        #expect(!cells.contains { $0.contains("fine") || $0.contains("ok") })
        #expect(try field(pane, 1, 1).stringValue == "Concealed")
        #expect(try field(pane, 2, 1).stringValue == "Concealed")
        #expect(try field(pane, 1, SafeDataProfile.Field.missing.rawValue).stringValue == "1 (33.3%)")
        // The concealed-column note is not shown (owner, 2026-10-15).
        #expect(try !statusText(view).contains("Columns with concealed values"))
        // Copying the profile cannot reveal them either.
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pane.tableView.pasteboard = pasteboard
        pane.tableView.selectAll(nil)
        pane.tableView.copy(nil)
        let copied = try #require(pasteboard.string(forType: .string))
        #expect(!copied.contains("••••") && !copied.contains("fine") && !copied.contains("ok"))
    }

    // MARK: Copy and accessibility

    @Test func copyingProfileRowsUsesTheTableFormatOfTabSeparatedSafeText() throws {
        let view = makeView()
        view.display(.ready(presentation(csv)), locale: english)
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pane.tableView.pasteboard = pasteboard
        pane.tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        pane.tableView.copy(nil)
        let table = SafeDataProfile.make(from: try parse(csv)).displayTable(locale: english)
        let expected = [0, 1].map { table.rows[$0].joined(separator: "\t") }.joined(separator: "\n")
        #expect(pasteboard.string(forType: .string) == expected)
        // The sparkline travels as its characters; its description is for assistive technology only.
        #expect(expected.contains { sparkBars.contains($0) })
    }

    @Test func theSparklineCellIsReadAloudFromItsDescriptionNotItsBlockCharacters() throws {
        let view = makeView()
        view.display(.ready(presentation("n\n0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n")), locale: english)
        try select(.previewModeProfile, in: view)
        let pane = try pane(view)
        let distribution = try field(pane, 0, SafeDataProfile.Field.distribution.rawValue)
        #expect(distribution.stringValue == "█▅▅▅█▅▅█")
        let spoken = try #require(distribution.accessibilityValue() as? String)
        #expect(spoken == "Distribution from 0 to 10 in 8 ranges, with counts 2, 1, 1, 1, 2, 1, 1, and 2")
        #expect(!spoken.contains { sparkBars.contains($0) })
        #expect(distribution.accessibilityLabel() == PreviewStrings.text(.profileHeaderDistribution))
        // Neighbouring cells are read as their own text.
        let mean = try field(pane, 0, SafeDataProfile.Field.mean.rawValue)
        #expect(mean.accessibilityValue() as? String == mean.stringValue)
    }
}
