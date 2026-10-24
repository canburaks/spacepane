import Foundation
import PreviewContracts

/// A bounded table derived only from privacy-filtered text. Cells keep their exact safe spelling:
/// no number/date conversion, trimming, formula evaluation or links. Rows may be ragged; a missing
/// cell reads as empty, so the model stores no padding.
struct SafeTable: Equatable, Sendable {
    /// Which parts of the safe text were left out to keep the view bounded.
    struct Truncation: OptionSet, Sendable {
        let rawValue: UInt8
        static let rows = Truncation(rawValue: 1)
        static let columns = Truncation(rawValue: 2)
        static let cells = Truncation(rawValue: 4)
        /// A folder or archive listing that stopped at a limit, so its rows and totals are incomplete.
        static let partialListing = Truncation(rawValue: 8)
    }

    /// How a column sorts. Display text always keeps its exact spelling; a typed column additionally
    /// carries one sort key per row in `sortKeys`.
    enum ColumnKind: Equatable, Sendable { case text, number, date }

    /// Where the rows come from. The origin decides what the Source mode can still show of the rows the
    /// table limits left out, and with it which truncation notice is true (`sourceHoldsOmittedContent`).
    enum Origin: Equatable, Sendable {
        /// Parsed from the file's own concealed text (CSV, TSV, a String Catalog): Source shows that text.
        case delimitedText
        /// Read back from an adapter's JSON summary (Parquet, Avro, Arrow, NumPy, NPZ, HAR and the SQLite
        /// schema grid): Source holds the same bounded rows, so it can never show more of them.
        case dataSummary
        /// The entries of a folder or archive summary.
        case listing
        /// Per-column facts computed from another table, one row per source column.
        case profile
    }

    /// How the table view lays the columns out. Typed, so a user file whose headers happen to read "Method" and
    /// "Deprecated" never gets the endpoint layout, and the choice never depends on the interface language.
    enum Layout: Equatable, Sendable {
        case standard
        /// The OpenAPI endpoint list: method, path, summary, deprecated.
        case endpoints
    }

    /// Displayed column titles from the first record; blank or missing titles are already localized.
    let columns: [String]
    /// Body records after the header, each holding at most `columns.count` cells.
    let rows: [[String]]
    let truncation: Truncation
    /// Column sort kinds; a column beyond the end of the array sorts as text.
    let columnKinds: [ColumnKind]
    /// Typed sort keys by column index: one optional key per body row (`nil` for a blank cell, which
    /// always sorts last). Only columns of kind `.number` or `.date` have an entry.
    let sortKeys: [Int: [Double?]]
    /// The header record's field count before the column cap, when known. `columns` widens to the widest
    /// record, so the profile needs this to tell a short or long record from the header's own width.
    var headerFieldCount: Int?
    /// Spoken alternatives for cells whose visible text is not meant to be read aloud, such as the
    /// block characters of a sparkline. A cell without an entry is read as its text.
    var cellDescriptions: [CellPosition: String] = [:]
    /// Where the rows come from; tables parsed from a file's own text are the default.
    var origin: Origin = .delimitedText
    var layout: Layout = .standard
    /// The presentation holds only the leading part of the file (`TextPresentation.truncatedSourceBytes`), so
    /// the rows are the first ones read and Source stops at the same cut. Only text-derived tables
    /// (`.delimitedText` and `.profile`) can be partial reads.
    var isPartialRead = false

    struct CellPosition: Hashable, Sendable {
        let row: Int
        let column: Int
    }

    init(columns: [String], rows: [[String]], truncation: Truncation, headerFieldCount: Int? = nil,
         cellDescriptions: [CellPosition: String] = [:], columnKinds: [ColumnKind] = [], sortKeys: [Int: [Double?]] = [:],
         origin: Origin = .delimitedText, isPartialRead: Bool = false) {
        self.columns = columns
        self.rows = rows
        self.truncation = truncation
        self.headerFieldCount = headerFieldCount
        self.cellDescriptions = cellDescriptions
        self.columnKinds = columnKinds
        self.sortKeys = sortKeys
        self.origin = origin
        self.isPartialRead = isPartialRead
    }

    /// Whether Source still holds what the table limits left out. That holds only for rows parsed from the
    /// file's own text when the whole text was read: a summary's Source carries the same bounded rows, and
    /// the Source of a partial read stops at the same cut, so neither may send the reader there for more.
    var sourceHoldsOmittedContent: Bool {
        switch origin {
        case .delimitedText, .profile: !isPartialRead
        case .dataSummary, .listing: false
        }
    }

    func kind(ofColumn column: Int) -> ColumnKind {
        columnKinds.indices.contains(column) ? columnKinds[column] : .text
    }

    func cell(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    func description(row: Int, column: Int) -> String? {
        cellDescriptions.isEmpty ? nil : cellDescriptions[CellPosition(row: row, column: column)]
    }

    // Invalidation compares exact code units: Swift String equality folds canonically equivalent
    // spellings, which would keep stale cells when a replacement differs only that way. Identical
    // storage short-circuits so restyling an unchanged table stays cheap.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.truncation == rhs.truncation, lhs.headerFieldCount == rhs.headerFieldCount,
              lhs.origin == rhs.origin, lhs.layout == rhs.layout, lhs.isPartialRead == rhs.isPartialRead,
              lhs.columnKinds == rhs.columnKinds, lhs.sortKeys == rhs.sortKeys,
              exactlyEqual(lhs.columns, rhs.columns), lhs.rows.count == rhs.rows.count,
              lhs.cellDescriptions.count == rhs.cellDescriptions.count,
              lhs.cellDescriptions.allSatisfy({ key, value in rhs.cellDescriptions[key]?.utf8.elementsEqual(value.utf8) == true })
        else { return false }
        return sameStorage(lhs.rows, rhs.rows) || zip(lhs.rows, rhs.rows).allSatisfy { exactlyEqual($0, $1) }
    }

    private static func exactlyEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && (sameStorage(lhs, rhs)
            || zip(lhs, rhs).allSatisfy { $0.utf8.elementsEqual($1.utf8) })
    }

    private static func sameStorage<Element>(_ lhs: [Element], _ rhs: [Element]) -> Bool {
        lhs.count == rhs.count && lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
        }
    }
}

/// Parses concealed CSV/TSV text with the same `DelimitedRecords` grammar the adapter validated, under
/// explicit display limits. Anything it cannot read reliably returns `nil`, which selects the safe
/// source view instead; there is never a path back to unconcealed source.
enum SafeDelimitedTable {
    /// Body rows shown. Matches the default shared line budget, so ordinary requests are never cut.
    static let maximumRows = 20_000
    /// Columns shown. A view-based table realizes every column of each visible row, so the cap
    /// bounds the live view count; further columns are reported by the notice and stay in Source.
    static let maximumColumns = 64
    /// UTF-16 code units per cell; longer text is cut at a character boundary.
    static let maximumCellUTF16Units = 4_096
    /// Total cells kept, bounding memory for wide tables that are also tall.
    static let maximumCells = 500_000
    /// Safe text above this size (twice the default output budget) is not parsed for a table.
    static let maximumSourceUTF8Bytes = 4_194_304
    private static let maximumFieldsPerRecord = 65_536

    /// `isPartialRead` is true when `safeText` is only the leading part of the file
    /// (`TextPresentation.truncatedSourceBytes != nil`); the table's notices then never point to Source.
    static func table(_ safeText: String, syntax: TextSyntax, locale: Locale, isPartialRead: Bool = false) -> SafeTable? {
        let dialect: DelimitedRecords.Dialect
        switch syntax {
        case .commaSeparated: dialect = .comma
        case .tabSeparated: dialect = .tab
        default: return nil
        }
        guard safeText.utf8.count <= maximumSourceUTF8Bytes else { return nil }
        let bytes = Array(safeText.utf8)
        let limits = DelimitedRecords.Limits(maxRecords: Int.max, maxFieldsPerRecord: maximumFieldsPerRecord,
                                             maxFieldBytes: maximumSourceUTF8Bytes)
        var header: [String] = []
        var headerFieldCount: Int?
        var rows: [[String]] = []
        var widest = 0
        var cellCount = 0
        var truncation: SafeTable.Truncation = []
        do {
            _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: limits, checkpoint: {}) { record, fields in
                widest = max(widest, fields.count)
                if fields.count > maximumColumns { truncation.insert(.columns) }
                var cells: [String] = []
                cells.reserveCapacity(min(fields.count, maximumColumns))
                for field in fields.prefix(maximumColumns) {
                    cells.append(clipped(DelimitedRecords.text(of: field, in: bytes), truncation: &truncation))
                }
                if record == 0 {
                    header = cells
                    headerFieldCount = fields.count
                    return .proceed
                }
                guard rows.count < maximumRows, cellCount + cells.count <= maximumCells else {
                    truncation.insert(.rows)
                    return .stop
                }
                rows.append(cells)
                cellCount += cells.count
                return .proceed
            }
        } catch {
            return nil
        }
        let columnCount = min(widest, maximumColumns)
        let columns = (0..<columnCount).map { index in
            let title = index < header.count ? header[index] : ""
            return title.allSatisfy(\.isWhitespace)
                ? PreviewStrings.format(.previewTableColumn, arguments: [Int64(index + 1)], locale: locale)
                : title
        }
        let typed = SafeTableColumnTypes.infer(rows: rows, columnCount: columnCount)
        return SafeTable(columns: columns, rows: rows, truncation: truncation, headerFieldCount: headerFieldCount,
                         columnKinds: typed.kinds, sortKeys: typed.keys, origin: .delimitedText, isPartialRead: isPartialRead)
    }

    private static func clipped(_ text: String, truncation: inout SafeTable.Truncation) -> String {
        // UTF-16 length never exceeds UTF-8 length, so a short UTF-8 count rules truncation out
        // without an O(n) UTF-16 count.
        guard text.utf8.count > maximumCellUTF16Units, text.utf16.count > maximumCellUTF16Units else { return text }
        truncation.insert(.cells)
        let source = text as NSString
        // Never split a surrogate pair or a composed character sequence.
        let sequence = source.rangeOfComposedCharacterSequence(at: maximumCellUTF16Units - 1)
        let end = NSMaxRange(sequence) > maximumCellUTF16Units ? sequence.location : maximumCellUTF16Units
        return source.substring(to: end)
    }
}
