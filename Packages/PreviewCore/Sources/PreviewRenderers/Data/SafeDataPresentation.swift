import Foundation
import PreviewContracts

/// Coordinates to draw, derived only from concealed text. A concealed or malformed chunk is
/// dropped as a whole, so the plot can omit a path but never invent one.
struct SafePlot: Equatable, Sendable {
    struct Position: Equatable, Sendable {
        let longitude: Double
        let latitude: Double
    }

    let paths: [[Position]]
    let points: [Position]
    /// The adapter thinned long paths before writing them.
    let simplified: Bool

    var positions: [Position] { paths.flatMap { $0 } + points }

    /// Longitude and latitude ranges, or nil when nothing can be drawn.
    var extent: (west: Double, south: Double, east: Double, north: Double)? {
        let all = positions
        guard let first = all.first else { return nil }
        var result = (west: first.longitude, south: first.latitude, east: first.longitude, north: first.latitude)
        for position in all {
            result.west = min(result.west, position.longitude)
            result.east = max(result.east, position.longitude)
            result.south = min(result.south, position.latitude)
            result.north = max(result.north, position.latitude)
        }
        return result
    }
}

/// Derives the Table and Plot presentations of the data formats from their concealed JSON summary.
///
/// The adapters write one JSON document (see `DataSummaryKeys`); this reads back its `table` and
/// `plot` members from the privacy-filtered text. Nothing here reads files, so a concealed value is
/// concealed in the table, and a column whose name looks secret is already `••••` in every row.
enum SafeDataPresentation {
    static let maximumRows = 1_000
    static let maximumColumns = SafeDelimitedTable.maximumColumns
    static let maximumPaths = 500
    static let maximumPositions = 8_000

    struct Result {
        var table: SafeTable?
        /// The first rows of a columnar file, a second table beside the schema (Parquet).
        var sampleRows: SafeTable?
        var plot: SafePlot?
    }

    /// Formats whose summary document may carry a table or a plot. SQLite's schema grid uses the
    /// same envelope.
    static func handles(_ formatID: FormatID) -> Bool {
        FormatID.dataSummaryFormats.contains(formatID) || formatID == .sqlite
    }

    static func derive(_ presentation: TextPresentation, locale: Locale) -> Result? {
        guard handles(presentation.formatID), presentation.syntax == .json,
              let root = SafeStructuredText.json(presentation.text)?.first else { return nil }
        return Result(table: table(in: root, locale: locale),
                      sampleRows: table(in: root, key: DataSummaryKeys.rowSample, locale: locale), plot: plot(in: root))
    }

    /// The mode shown first: the data itself where there is one, otherwise the generic choice.
    static func initialMode(for formatID: FormatID, table: SafeTable?, sampleRows: SafeTable?, plot: SafePlot?) -> NativePreviewMode? {
        guard FormatID.dataSummaryFormats.contains(formatID) else { return nil }
        if sampleRows != nil { return .rows }
        switch formatID {
        case .geoJSON, .gpx, .kml: return plot != nil ? .plot : nil
        default: return table != nil ? .table : nil
        }
    }

    // MARK: Table

    static func table(in root: SafeOutlineNode, key: String = DataSummaryKeys.table, locale: Locale) -> SafeTable? {
        guard let node = root.dataChild(key), let rowsNode = node.dataChild(DataSummaryKeys.rows) else { return nil }
        let identifiers = node.dataChild(DataSummaryKeys.columns)
        // Identifiers are translated when known; document names never are.
        guard let header = identifiers ?? node.dataChild(DataSummaryKeys.columnNames) else { return nil }
        let ids = header.children.prefix(maximumColumns).map(\.value)
        let titles = ids.enumerated().map { index, id -> String in
            if identifiers != nil, let key = DataSchemaLabels.keys[id] { return PreviewStrings.text(key) }
            return id.allSatisfy(\.isWhitespace)
                ? PreviewStrings.format(.previewTableColumn, arguments: [Int64(index + 1)], locale: locale) : id
        }
        var rows: [[String]] = []
        for row in rowsNode.children.prefix(maximumRows) {
            rows.append(row.children.prefix(ids.count).enumerated().map { index, cell in
                text(of: cell, column: identifiers != nil ? ids[index] : nil, locale: locale)
            })
        }
        let truncated = node.dataChild(DataSummaryKeys.truncated)?.value == "true" || rowsNode.children.count > rows.count
        // The summary JSON in Source holds exactly these bounded rows, so its notice must not point there.
        return SafeTable(columns: titles, rows: rows, truncation: truncated ? .rows : [], origin: .dataSummary)
    }

    private static func text(of cell: SafeOutlineNode, column: String?, locale: Locale) -> String {
        if cell.value == "[…]" { return cell.children.map(\.value).joined() }
        if cell.value == "{…}" {
            // Binary content is shown only as its length.
            guard let count = cell.dataChild(DataSummaryKeys.binaryByteCount), let bytes = Int64(count.value) else { return "" }
            return PreviewStrings.format(.dataBinaryValue, arguments: [bytes.formatted(.number.locale(locale))], locale: locale)
        }
        if let column, DataSchemaLabels.booleanColumns.contains(column) {
            if cell.value == "true" { return PreviewStrings.text(.summaryBooleanTrue) }
            if cell.value == "false" { return PreviewStrings.text(.summaryBooleanFalse) }
        }
        return cell.value
    }

    // MARK: Plot

    static func plot(in root: SafeOutlineNode) -> SafePlot? {
        guard let node = root.dataChild(DataSummaryKeys.plot) else { return nil }
        var budget = maximumPositions
        var paths: [[SafePlot.Position]] = []
        for path in node.dataChild(DataSummaryKeys.paths)?.children.prefix(maximumPaths) ?? [] {
            var positions: [SafePlot.Position] = []
            for chunk in path.children.prefix(maximumPositions / DataPlotCoding.maximumPositionsPerChunk + 1) {
                guard let decoded = DataPlotCoding.decode(chunk.value) else { continue }
                positions += decoded.map { SafePlot.Position(longitude: $0.longitude, latitude: $0.latitude) }
            }
            guard positions.count >= 2, positions.count <= budget else { continue }
            budget -= positions.count
            paths.append(positions)
        }
        var points: [SafePlot.Position] = []
        for chunk in node.dataChild(DataSummaryKeys.points)?.children ?? [] {
            guard let decoded = DataPlotCoding.decode(chunk.value), decoded.count <= budget else { continue }
            budget -= decoded.count
            points += decoded.map { SafePlot.Position(longitude: $0.longitude, latitude: $0.latitude) }
        }
        guard !paths.isEmpty || !points.isEmpty else { return nil }
        return SafePlot(paths: paths, points: points, simplified: node.dataChild(DataSummaryKeys.simplified)?.value == "true")
    }
}

fileprivate extension SafeOutlineNode {
    /// The first member with this name. Safe nodes come only from privacy-filtered text.
    func dataChild(_ name: String) -> SafeOutlineNode? { children.first { $0.name == name } }
}
