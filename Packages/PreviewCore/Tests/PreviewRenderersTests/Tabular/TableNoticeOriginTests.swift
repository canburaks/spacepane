import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Limits count the cached row batch and keep column/cell caps separate (decision 027, Q-51).
/// Adapter summaries and partial reads never borrow a total from an unrelated grid or missing bytes.
@Suite("Table notice by origin", .serialized)
@MainActor
struct TableNoticeOriginTests {
    private let english = Locale(identifier: "en_US")

    private let avro = """
    {"dataFormat": "Avro", "table": {"columnNames": ["name", "type"],
      "rows": [["row 1", "x"], ["row 2", "y"]], "truncated": true}}
    """

    private let parquet = """
    {"dataFormat": "Parquet", "rowCount": 3,
     "table": {"columns": ["name", "repetition"], "rows": [["id", "REQUIRED"]], "truncated": false},
     "rowSample": {"columnNames": ["id", "city"], "rows": [["1", "Oslo"], ["2", "Rome"]], "truncated": true}}
    """

    private let sqlite = """
    {"databaseFormat": "SQLite", "schema": [], "pages": [], "tableCount": 0,
     "table": {"columns": ["table", "column"], "rows": [["t", "a"]], "truncated": true}}
    """

    /// A header and one record of 70 columns: six more than the table shows.
    private var wideCSV: String {
        let header = (1...70).map { "c\($0)" }.joined(separator: ",")
        let record = (1...70).map { String($0) }.joined(separator: ",")
        return header + "\n" + record + "\n"
    }

    // MARK: Wording

    @Test func theRowAndCapSentencesAreTheReviewedEnglishAndNeitherClaimsCompleteSource() {
        let rows = PreviewStrings.count(.previewTableShownRows, 2, locale: english, languagePreferences: ["en"])
        let caps = PreviewStrings.text(.previewTableLimitCaps, languagePreferences: ["en"])
        #expect(rows == "Showing the first 2 rows.")
        #expect(PreviewStrings.count(.previewTableShownRows, 1, locale: english, languagePreferences: ["en"]) == "Showing the first 1 row.")
        #expect(caps == "Columns or long cells beyond the table limits are not shown.")
        for sentence in [rows, caps] {
            #expect(!sentence.localizedCaseInsensitiveContains("complete"))
            #expect(!sentence.contains("Source"))
        }
    }

    @Test func bothSentencesAreTranslatedInEveryOtherLanguage() {
        let languages = ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for key in [PreviewStrings.Key.previewTableShownRows, .previewTableLimitCaps] {
            func value(_ language: String) -> String {
                key == .previewTableShownRows
                    ? PreviewStrings.count(key, 2, locale: english, languagePreferences: [language])
                    : PreviewStrings.text(key, languagePreferences: [language])
            }
            let source = value("en")
            for language in languages {
                let localized = value(language)
                #expect(!localized.isEmpty && localized != key.rawValue, Comment(rawValue: "\(key.rawValue) \(language)"))
                #expect(localized != source, Comment(rawValue: "\(key.rawValue) \(language)"))
            }
        }
    }

    // MARK: Which sentence a table shows

    @Test func sourceHoldsOmittedContentOnlyForTextThatWasReadWhole() {
        let cases: [(SafeTable.Origin, Bool, Bool)] = [
            (.delimitedText, false, true), (.delimitedText, true, false),
            (.profile, false, true), (.profile, true, false),
            (.dataSummary, false, false), (.dataSummary, true, false),
            (.listing, false, false), (.listing, true, false)
        ]
        for (origin, partial, expected) in cases {
            let table = SafeTable(columns: ["a"], rows: [["x"]], truncation: .rows, origin: origin, isPartialRead: partial)
            #expect(table.sourceHoldsOmittedContent == expected, Comment(rawValue: "\(origin) partial: \(partial)"))
        }
        // Tables built without an origin are the ones parsed from a file's own text.
        let plain = SafeTable(columns: ["a"], rows: [["x"]], truncation: .rows)
        #expect(plain.origin == .delimitedText && !plain.isPartialRead && plain.sourceHoldsOmittedContent)
    }

    @Test func aDataSummaryTableNeverSendsTheReaderToSource() throws {
        let table = try #require(SafeDataPresentation.derive(presentation(.avro, avro, syntax: .json), locale: english)?.table)
        #expect(table.origin == .dataSummary && table.truncation == .rows && !table.sourceHoldsOmittedContent)
        expectNotice(of: table, is: .previewTableShownRows, "Avro rows")
    }

    @Test func theSampleRowsOfAColumnarFileAreADataSummaryToo() throws {
        let modes = SafePreviewModes(presentation(.parquet, parquet, syntax: .json), locale: english)
        let schema = try #require(modes.table)
        let rows = try #require(modes.sampleRows)
        #expect(schema.origin == .dataSummary && schema.truncation.isEmpty)
        #expect(rows.origin == .dataSummary && rows.truncation == .rows)
        // A complete schema grid has nothing to explain.
        #expect(notice(of: schema).isEmpty)
        expectNotice(of: rows, is: .previewTableShownRows, "Parquet row sample")
    }

    @Test func theSQLiteSchemaGridCountsOnlyTheRowsInItsOwnBatch() throws {
        let modes = SafePreviewModes(presentation(.sqlite, sqlite, syntax: .json), locale: english)
        let grid = try #require(modes.table)
        #expect(grid.origin == .dataSummary && grid.truncation == .rows)
        expectNotice(of: grid, is: .previewTableShownRows, "SQLite schema grid")
    }

    @Test func aWholeCSVDescribesItsColumnCapWithoutPromisingMoreSource() throws {
        let table = try #require(SafeDelimitedTable.table(wideCSV, syntax: .commaSeparated, locale: english))
        #expect(table.columns.count == SafeDelimitedTable.maximumColumns && table.truncation == .columns)
        #expect(table.origin == .delimitedText && !table.isPartialRead && table.sourceHoldsOmittedContent)
        expectNotice(of: table, is: .previewTableLimitCaps, "70-column CSV read whole")
        // The same text, parsed for a presentation without a partial read.
        let modes = SafePreviewModes(presentation(.csv, wideCSV, syntax: .commaSeparated), locale: english)
        expectNotice(of: try #require(modes.table), is: .previewTableLimitCaps, "70-column CSV presentation")
        expectNotice(of: try #require(modes.profile).value.table, is: .previewTableLimitCaps, "its profile")
    }

    @Test func aPartiallyReadCSVKeepsItsColumnCapSeparateFromItsByteReadLimit() throws {
        let table = try #require(SafeDelimitedTable.table(wideCSV, syntax: .commaSeparated, locale: english, isPartialRead: true))
        #expect(table.truncation == .columns && table.isPartialRead && !table.sourceHoldsOmittedContent)
        expectNotice(of: table, is: .previewTableLimitCaps, "70-column CSV, first part read")
    }

    @Test func thePresentationsPartialReadReachesItsTableAndItsProfile() throws {
        // The shared pipeline reports `truncatedSourceBytes` when only the leading records of a large CSV were read.
        let partial = presentation(.csv, wideCSV, syntax: .commaSeparated, truncatedSourceBytes: 3_000_000)
        let modes = SafePreviewModes(partial, locale: english)
        let table = try #require(modes.table)
        // SafePreviewModes passes `presentation.truncatedSourceBytes != nil` to `SafeDelimitedTable.table(isPartialRead:)`.
        #expect(table.isPartialRead, "The presentation's partial read must reach the table")
        expectNotice(of: table, is: .previewTableLimitCaps, "partial CSV table")
        let profile = try #require(modes.profile).value.table
        #expect(profile.origin == .profile && profile.isPartialRead)
        expectNotice(of: profile, is: .previewTableLimitCaps, "partial CSV profile")
    }

    @Test func aListingSaysItsOwnPartialNoticeAndNeverPointsToSourceForRows() throws {
        let json = #"{"partial":true,"entries":[{"path":"a","type":"file","bytes":1}]}"#
        let modes = SafePreviewModes(presentation(.zip, json, syntax: .json), locale: english)
        let files = try #require(modes.files)
        #expect(files.origin == .listing && files.truncation == [.partialListing])
        #expect(notice(of: files) == PreviewStrings.text(.listingPartialNotice))
        // A listing that also hit a table limit adds the sentence that does not claim Source has the rest.
        let both = SafeTable(columns: ["a"], rows: [["1"]], truncation: [.partialListing, .rows], origin: .listing)
        #expect(notice(of: both) == PreviewStrings.text(.listingPartialNotice) + "\nShowing the first 1 row.")
    }

    @Test func tablesThatDifferOnlyByOriginOrPartialReadAreNotEqualSoTheViewRefreshes() {
        let base = SafeTable(columns: ["a"], rows: [["x"]], truncation: .rows)
        var summary = base
        summary.origin = .dataSummary
        var partial = base
        partial.isPartialRead = true
        #expect(base != summary && base != partial && summary != partial)
        #expect(base == SafeTable(columns: ["a"], rows: [["x"]], truncation: .rows, origin: .delimitedText, isPartialRead: false))
        // Equal safe cells with changed provenance still replace the table and reset selection.
        let view = makeView()
        view.display(base, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.tableView.selectAll(nil)
        #expect(!view.tableView.selectedRowIndexes.isEmpty)
        #expect(notice(of: base) == "Showing the first 1 row.")
        view.display(partial, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        #expect(view.tableView.selectedRowIndexes.isEmpty)
        #expect(notice(of: partial) == "Showing the first 1 row.")
    }

    @Test func aLiveReloadOfTheSameTableKeepsTheSelectionOfRowsThatRemain() {
        // A genuine reload of the same file: same origin, same partial-read state, same columns, one row added.
        let before = SafeTable(columns: ["a"], rows: [["x"], ["y"]], truncation: [])
        let after = SafeTable(columns: ["a"], rows: [["x"], ["y"], ["z"]], truncation: [])
        let view = makeView()
        view.display(before, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        view.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        view.display(after, typography: .init(), palette: palette(), syntaxStyle: .init(), locale: english)
        #expect(view.tableView.selectedRowIndexes == IndexSet(integer: 1))
    }

    // MARK: Helpers

    private func presentation(_ formatID: FormatID, _ text: String, syntax: TextSyntax,
                              truncatedSourceBytes: Int? = nil) -> TextPresentation {
        TextPresentation(formatID: formatID, text: text, lineCount: text.split(separator: "\n").count, byteCount: text.utf8.count,
                         encoding: .utf8, redactionCount: 0, syntax: syntax, truncatedSourceBytes: truncatedSourceBytes)
    }

    /// Typed notices for this cached batch; no content view owns a notice label.
    private func notice(of table: SafeTable) -> String {
        let presentation = presentation(.csv, "a\n1\n", syntax: .commaSeparated)
        var modes = SafePreviewModes(presentation, locale: english)
        modes.table = table
        return ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: english)
            .map(\.text).joined(separator: "\n")
    }

    /// Counts use the row batch; caps stay separate and no sentence promises complete Source.
    private func expectNotice(of table: SafeTable, is key: PreviewStrings.Key, _ label: String) {
        let shown = notice(of: table)
        let expected = key == .previewTableShownRows
            ? PreviewStrings.count(key, table.rows.count, locale: english) : PreviewStrings.text(key)
        #expect(shown == expected, Comment(rawValue: label))
        #expect(!shown.isEmpty && !shown.localizedCaseInsensitiveContains("complete") && !shown.contains("Source"), Comment(rawValue: label))
    }

    private func makeView() -> NativeTablePreviewView {
        let view = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    private func palette() -> NativeTextPalette {
        .init(theme: .system, isDark: false, increasedContrast: false)
    }
}
