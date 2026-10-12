import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en")

private let catalog = """
{
  "sourceLanguage" : "en",
  "strings" : {
    "Hello" : {
      "comment" : "greeting",
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Hallo" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hello" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "こんにちは 🙂" } }
      }
    },
    "%lld files" : {
      "localizations" : {
        "en" : { "variations" : { "plural" : { "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld file" } } } } }
      }
    },
    "Untranslated" : { "extractionState" : "manual" },
    "password" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : ••••} } } }
  },
  "version" : "1.0"
}
"""

@Suite("String catalog table")
struct StringCatalogTableTests {
    @Test func keysByLanguagesWithTheSourceLanguageFirst() throws {
        let table = try #require(SafeStringCatalogTable.table(catalog, locale: english))
        #expect(table.columns == ["Key", "en", "de", "ja"])
        #expect(table.rows.map { $0[0] } == ["Hello", "%lld files", "Untranslated", "password"])
        #expect(table.rows[0] == ["Hello", "Hello", "Hallo", "こんにちは 🙂"])
        // Plural and device variations are not collapsed to one form; a missing translation is empty.
        #expect(table.rows[1] == ["%lld files", "…", "", ""])
        #expect(table.rows[2] == ["Untranslated", "", "", ""])
        // A concealed value stays the inert token.
        #expect(table.rows[3][1] == "••••")
        #expect(table.truncation.isEmpty)
    }

    @Test func theTableIsTheFirstViewOfACatalogAndJSONModesRemain() {
        let presentation = TextPresentation(formatID: .json, text: catalog, lineCount: 1, byteCount: 1, encoding: .utf8,
                                            redactionCount: 1, syntax: .json)
        let modes = SafePreviewModes(presentation, locale: english)
        #expect(modes.table != nil && modes.outline != nil && !modes.hasStructureFallback)
        #expect(modes.available == [.source, .outline, .table] && modes.initialMode(for: .json) == .table)
    }

    @Test func ordinaryJSONAndOtherFormatsHaveNoTable() {
        for (format, text) in [(FormatID.json, "{\"a\": 1}"), (.packageJSON, catalog), (.jsonLines, catalog)] {
            let presentation = TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: 1, encoding: .utf8, redactionCount: 0, syntax: .json)
            #expect(SafePreviewModes(presentation, locale: english).table == nil, "\(format.rawValue)")
        }
        #expect(SafeStringCatalogTable.table("{\"sourceLanguage\": \"en\", \"strings\": [1]}", locale: english) == nil)
        #expect(SafeStringCatalogTable.table("{\"strings\": {}}", locale: english) == nil)
        #expect(SafeStringCatalogTable.table("not json \"sourceLanguage\" \"strings\"", locale: english) == nil)
    }

    @Test func columnsRowsAndCellsAreBounded() throws {
        let many = (0..<70).map { "\"l\($0)\": {\"stringUnit\": {\"value\": \"v\"}}" }.joined(separator: ",")
        let wide = "{\"sourceLanguage\": \"l5\", \"strings\": {\"k\": {\"localizations\": {\(many)}}}}"
        let wideTable = try #require(SafeStringCatalogTable.table(wide, locale: english))
        #expect(wideTable.columns.count == 64 && wideTable.columns[1] == "l5" && wideTable.truncation.contains(.columns))
        // The safe outline the table reads is itself bounded to 20,000 nodes, so a larger catalog has no table.
        let rows = (0..<19_990).map { "\"k\($0)\": {}" }.joined(separator: ",")
        let tall = try #require(SafeStringCatalogTable.table("{\"sourceLanguage\": \"en\", \"strings\": {\(rows)}}", locale: english))
        #expect(tall.rows.count == 19_990 && tall.truncation.isEmpty)
        let tooMany = (0..<20_001).map { "\"k\($0)\": {}" }.joined(separator: ",")
        #expect(SafeStringCatalogTable.table("{\"sourceLanguage\": \"en\", \"strings\": {\(tooMany)}}", locale: english) == nil)
        let long = String(repeating: "x", count: 5_000)
        let cell = try #require(SafeStringCatalogTable.table(
            "{\"sourceLanguage\": \"en\", \"strings\": {\"k\": {\"localizations\": {\"en\": {\"stringUnit\": {\"value\": \"\(long)\"}}}}}}", locale: english))
        #expect(cell.rows[0][1].utf16.count == 4_096 && cell.truncation.contains(.cells))
    }
}
