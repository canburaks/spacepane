import Foundation
import PreviewContracts

/// Reads only concealed presentation text. Source counts come from parser facts; a probe can
/// establish column kinds and headers but never substitutes its sample size for those counts.
enum ThumbnailGridBuilder {
    enum PlainGridProbe: Sendable {
        case notGrid
        case grid(ThumbnailGrid)
        case withheld
    }
    private static let maximumSummaryBytes = 2_097_152
    private static let probeBytes = 65_536
    private static let formats: Set<FormatID> = [.csv, .tsv, .sqlite, .parquet, .arrow, .avro, .numpy, .numpyArchive, .json]

    private struct Sample {
        var headers: [String] = []
        var kinds: [ThumbnailGrid.ColumnKind] = []
        var rowCount = 0
        var columnCount = 0
        var isPartial = false
        var tableCount: Int?
        var tablesAreLowerBound = false
    }

    /// A detected plain-text grid gets only a bounded tally, marked with + if the probe stops.
    /// This replaces the old auto-table path so it cannot keep drawing ordinary cell values.
    static func tabSeparatedGrid(fromPlainText text: String, metrics: ThumbnailMetrics,
                                 locale: Locale = .current) -> ThumbnailGrid? {
        if case .grid(let grid) = tabSeparatedProbe(fromPlainText: text, metrics: metrics, locale: locale) { return grid }
        return nil
    }

    /// Detection and sampling happen once. A recognized grid refused by a sample bound remains
    /// withheld; callers must not reinterpret its ordinary cell values as a plain-text excerpt.
    static func tabSeparatedProbe(fromPlainText text: String, metrics: ThumbnailMetrics,
                                  locale: Locale = .current) -> PlainGridProbe {
        guard text.utf8.prefix(4_096).contains(9) else { return .notGrid }
        let lines = ThumbnailLines.raw(in: text, limit: 12, maxScalars: 512).filter { !ThumbnailLines.isBlank($0) }
        guard lines.count >= 3, lines.allSatisfy({ $0.first != "\t" }) else { return .notGrid }
        let counts = lines.map { $0.filter { $0 == "\t" }.count + 1 }
        let columns = counts[0]
        guard columns >= 2, counts.filter({ $0 == columns }).count * 5 >= counts.count * 4 else { return .notGrid }
        guard let sample = delimitedSample(text, dialect: .tab, hasHeader: false) else { return .withheld }
        // Consistent tabs establish a shape, never that the first record contains names. Count and
        // classify it with the other records, and keep every ordinary value out of the header band.
        guard let grid = ThumbnailGrid(headers: [], columnKinds: sample.kinds, rowCount: sample.rowCount,
                             columnCount: sample.columnCount, rowsAreLowerBound: sample.isPartial,
                             sampleRowCount: sample.rowCount, columnsAreLowerBound: sample.isPartial, locale: locale) else { return .withheld }
        return .grid(grid)
    }

    static func grid(for presentation: TextPresentation, metrics: ThumbnailMetrics,
                     locale: Locale = .current) -> ThumbnailGrid? {
        guard formats.contains(presentation.formatID) else { return nil }
        guard let fact = presentation.facts.facts.first(where: {
            if case .grid = $0 { return true }; return false
        }), case .grid(let rows, let columns, let lowerBound) = fact, rows >= 0, columns > 0 else { return nil }
        let sample: Sample
        switch presentation.formatID {
        case .csv, .tsv:
            guard let delimited = delimitedSample(presentation.text, dialect: presentation.formatID == .csv ? .comma : .tab) else { return nil }
            sample = delimited
        case .sqlite:
            guard let root = object(presentation.text), let database = databaseSample(root) else { return nil }
            sample = database
        case .json:
            guard let records = jsonRecordsSample(presentation.text, columnCount: columns) else { return nil }
            sample = records
        default:
            guard let root = object(presentation.text) else { return nil }
            sample = dataSample(root, format: presentation.formatID)
        }
        let visibleColumns = min(columns, ThumbnailGrid.maximumColumns)
        let kinds = sample.kinds.isEmpty ? Array(repeating: ThumbnailGrid.ColumnKind.unknown, count: visibleColumns) : sample.kinds
        // Headers are useful only when a grid is large enough to read. Smaller grids keep their band
        // and count line, and never replace clipped headers with app-authored schema text.
        let readableHeaders = min(metrics.canvas.width, metrics.canvas.height) * metrics.pixelScale >= 256
        return ThumbnailGrid(headers: readableHeaders ? sample.headers : [], columnKinds: kinds,
                             rowCount: rows, columnCount: columns, rowsAreLowerBound: lowerBound,
                             sampleRowCount: sample.rowCount, tableCount: sample.tableCount,
                             tablesAreLowerBound: sample.tablesAreLowerBound, locale: locale)
    }

    private static func delimitedSample(_ text: String, dialect: DelimitedRecords.Dialect, hasHeader: Bool = true) -> Sample? {
        let probe = Array(text.utf8.prefix(probeBytes + 1))
        let bytes = Array(probe.prefix(probeBytes))
        var records: [[String]] = []
        var columnCount = 0
        var partial = probe.count > probeBytes
        let recordLimit = ThumbnailGrid.maximumSampleRows + (hasHeader ? 1 : 0)
        let limits = DelimitedRecords.Limits(maxRecords: recordLimit,
                                             maxFieldsPerRecord: 256, maxFieldBytes: 4_096)
        do {
            let result = try DelimitedRecords.scan(bytes, dialect: dialect, limits: limits, checkpoint: {}) { _, fields in
                columnCount = max(columnCount, fields.count)
                records.append(fields.prefix(ThumbnailGrid.maximumColumns).map { DelimitedRecords.text(of: $0, in: bytes) })
                return records.count >= recordLimit ? .stop : .proceed
            }
            partial = partial || result.stoppedEarly
        } catch {
            // An incomplete bounded probe may keep complete records. The adapter already validated
            // the document before concealment; nothing from an incomplete record is classified.
            partial = true
        }
        guard let first = records.first, !first.isEmpty else { return nil }
        let body = hasHeader ? Array(records.dropFirst()) : records
        let headers = hasHeader ? first : []
        let kindColumns = hasHeader ? first.count : columnCount
        return Sample(headers: headers, kinds: kinds(rows: body.map { $0.map { $0 as Any } }, columns: kindColumns),
                      rowCount: body.count, columnCount: columnCount, isPartial: partial)
    }

    private static func databaseSample(_ root: [String: Any]) -> Sample? {
        guard let pages = root["pages"] as? [[String: Any]] else { return nil }
        for page in pages {
            guard let names = page["columns"] as? [String], !names.isEmpty,
                  let rows = page["rows"] as? [[String: Any]], !rows.isEmpty else { continue }
            let columns = Array(names.prefix(ThumbnailGrid.maximumColumns))
            let sampled = rows.prefix(ThumbnailGrid.maximumSampleRows).map { row in columns.map { name -> Any in
                guard let value = row[name] as? [String: Any] else { return NSNull() }
                if let text = value["value"] as? String { return text }
                // Opaque blob metadata is present, not an empty cell. It never supplies source bytes.
                return value
            } }
            return Sample(headers: columns, kinds: kinds(rows: sampled, columns: columns.count), rowCount: sampled.count,
                          tableCount: nonnegativeInteger(root["tableCount"]),
                          tablesAreLowerBound: root["schemaPartial"] as? Bool ?? false)
        }
        return nil
    }

    private static func dataSample(_ root: [String: Any], format: FormatID) -> Sample {
        // Technical `columns` describe a metadata schema, not the source grid. Only `columnNames`
        // have proven source provenance. NumPy's artificial index column is omitted as well.
        let table = (root[DataSummaryKeys.rowSample] ?? root[DataSummaryKeys.table]) as? [String: Any]
        guard let table else { return Sample() }
        let rows = Array((table[DataSummaryKeys.rows] as? [[Any]] ?? []).prefix(ThumbnailGrid.maximumSampleRows))
        if let names = table[DataSummaryKeys.columnNames] as? [String] {
            let count = min(names.count, ThumbnailGrid.maximumColumns)
            return Sample(headers: Array(names.prefix(count)), kinds: kinds(rows: rows, columns: count), rowCount: rows.count)
        }
        if format == .numpy || format == .numpyArchive {
            let technicalColumns = table[DataSummaryKeys.columns] as? [String] ?? []
            let hasIndex = technicalColumns.first == "#"
            let values = hasIndex ? rows.map { Array($0.dropFirst()) } : rows
            let count = min(max(0, technicalColumns.count - (hasIndex ? 1 : 0)), ThumbnailGrid.maximumColumns)
            return Sample(kinds: kinds(rows: values, columns: count), rowCount: rows.count)
        }
        return Sample() // A schema-only summary carries counts, without invented sample kinds or names.
    }

    private static func jsonRecordsSample(_ text: String, columnCount: Int) -> Sample? {
        guard text.utf8.count <= maximumSummaryBytes,
              let records = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]],
              !records.isEmpty else { return nil }
        let sampled = Array(records.prefix(ThumbnailGrid.maximumSampleRows))
        var names: Set<String> = []
        for row in sampled {
            guard row.count <= 256 else { return nil }
            for name in row.keys {
                names.insert(name)
                guard names.count <= 256 else { return nil }
            }
        }
        // Foundation dictionaries can coalesce canonically equivalent keys. When this complete
        // sample cannot account for the exact parser schema, omit labels and kinds rather than
        // associating a decoded value with the wrong source column. Counts still come from facts.
        if records.count <= ThumbnailGrid.maximumSampleRows && names.count != columnCount {
            return Sample(rowCount: sampled.count)
        }
        let headers = Array(names.sorted().prefix(ThumbnailGrid.maximumColumns))
        let rows = sampled.map { row in headers.map { row[$0] ?? NSNull() } }
        return Sample(headers: headers, kinds: kinds(rows: rows, columns: headers.count), rowCount: rows.count)
    }

    private static func kinds(rows: [[Any]], columns: Int) -> [ThumbnailGrid.ColumnKind] {
        (0..<min(columns, ThumbnailGrid.maximumColumns)).map { index in
            guard !rows.isEmpty else { return .unknown }
            var found = false
            for row in rows.prefix(ThumbnailGrid.maximumSampleRows) where index < row.count {
                let value = row[index]
                if value is NSNull { continue }
                let text: String
                if let string = value as? String { text = string }
                else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { text = number.stringValue }
                else { return .unknown }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                found = true
                guard text.utf8.count <= 200, let number = Double(text), number.isFinite else { return .text }
            }
            return found ? .numeric : .empty
        }
    }

    private static func object(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= maximumSummaryBytes else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue < Double(Int.max), number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return Int(number.doubleValue)
    }
}
