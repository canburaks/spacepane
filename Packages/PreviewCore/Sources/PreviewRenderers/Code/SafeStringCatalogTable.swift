import Foundation
import PreviewContracts

/// Derives a keys-by-languages table from an Xcode String Catalog (`.xcstrings`) whose JSON text has
/// already been concealed. The catalog format is plain JSON, so the view reads the same safe outline the
/// JSON outline mode uses and never touches source bytes: one row per string key, a `Key` column, then one
/// column per language with the source language first and the others sorted. A cell shows the translated
/// `stringUnit` value as written; entries that vary by plural or device (`variations`, `substitutions`) show
/// an ellipsis, because choosing one form would misstate the others, and a missing translation is empty.
///
/// Anything that does not have the catalog's shape (`sourceLanguage` and a `strings` object) yields `nil`
/// and the JSON modes stay as they are. Display limits match the delimited table: 20,000 rows, 64 columns,
/// 4,096 UTF-16 units per cell and 500,000 cells, with the table's own truncation notice.
enum SafeStringCatalogTable {
    static let maximumRows = 20_000
    static let maximumColumns = 64
    static let maximumCellUTF16Units = 4_096
    static let maximumCells = 500_000
    /// Not localized: a technical ellipsis for plural and device variations.
    private static let variationsCell = "\u{2026}"

    static func table(_ safeText: String, locale: Locale) -> SafeTable? {
        // Cheap precheck: ordinary JSON documents skip the outline parse entirely.
        guard safeText.contains("\"sourceLanguage\""), safeText.contains("\"strings\""),
              let root = SafeStructuredText.json(safeText)?.first,
              let source = root.children.first(where: { $0.name == "sourceLanguage" }),
              let strings = root.children.first(where: { $0.name == "strings" }), strings.value == "{…}" else { return nil }
        var truncation: SafeTable.Truncation = []
        var discovered = Set<String>()
        for entry in strings.children {
            for language in localizations(of: entry)?.children ?? [] { discovered.insert(language.name) }
        }
        var languages = discovered.sorted()
        if let index = languages.firstIndex(of: source.value) {
            languages.remove(at: index)
            languages.insert(source.value, at: 0)
        }
        // One column is the key; the rest are languages.
        if languages.count > maximumColumns - 1 {
            languages = Array(languages.prefix(maximumColumns - 1))
            truncation.insert(.columns)
        }
        var rows: [[String]] = []
        var cells = 0
        for entry in strings.children {
            guard rows.count < maximumRows, cells + languages.count + 1 <= maximumCells else {
                truncation.insert(.rows)
                break
            }
            let row = [clipped(entry.name, &truncation)] + languages.map { clipped(value(of: entry, language: $0), &truncation) }
            rows.append(row)
            cells += row.count
        }
        let columns = [PreviewStrings.text(.previewOutlineKey)] + languages
        return SafeTable(columns: columns, rows: rows, truncation: truncation)
    }

    private static func localizations(of entry: SafeOutlineNode) -> SafeOutlineNode? {
        entry.children.first { $0.name == "localizations" }
    }

    private static func value(of entry: SafeOutlineNode, language: String) -> String {
        guard let localization = localizations(of: entry)?.children.first(where: { $0.name == language }) else { return "" }
        if let unit = localization.children.first(where: { $0.name == "stringUnit" }) {
            return unit.children.first { $0.name == "value" }?.value ?? ""
        }
        if localization.children.contains(where: { $0.name == "variations" || $0.name == "substitutions" }) { return variationsCell }
        return ""
    }

    /// Cuts at a character boundary so no surrogate pair or composed sequence is split.
    private static func clipped(_ text: String, _ truncation: inout SafeTable.Truncation) -> String {
        guard text.utf8.count > maximumCellUTF16Units, text.utf16.count > maximumCellUTF16Units else { return text }
        truncation.insert(.cells)
        let source = text as NSString
        let sequence = source.rangeOfComposedCharacterSequence(at: maximumCellUTF16Units - 1)
        let end = NSMaxRange(sequence) > maximumCellUTF16Units ? sequence.location : maximumCellUTF16Units
        return source.substring(to: end)
    }
}
