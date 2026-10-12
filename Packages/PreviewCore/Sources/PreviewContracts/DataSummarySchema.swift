import Foundation

/// Wire names of the JSON envelope that the data adapters write and the native Table and Plot
/// views read back from the already-concealed text. Both sides import them from here so a
/// renamed key cannot silently disconnect a view.
///
/// The summary document is ordinary JSON, so Source and Summary work unchanged. Two optional
/// top-level members add presentations:
///
/// - `table`: `{ "columns"|"columnNames": [...], "rows": [[cell...]...], "truncated": bool }`.
///   `columns` holds technical identifiers that a view translates when it knows them;
///   `columnNames` holds document data (field or column names) that is always shown verbatim.
///   A cell is a string, `null`, an array of strings (joined; used where only part of a value is
///   concealed) or the object `{ "bytes": n }` for binary content, which is never shown.
/// - `rowSample`: the same shape as `table` (always `columnNames`), a second, optional table of values.
/// - `plot`: `{ "paths": [[coding...]...], "points": [coding...], "simplified": bool }`; each path is a
///   list of coded chunks, see `DataPlotCoding`. `simplified` is true when positions were thinned.
public enum DataSummaryKeys {
    public static let table = "table"
    /// A second table with the same shape, holding the first rows of a columnar file (Parquet).
    public static let rowSample = "rowSample"
    public static let columns = "columns"
    public static let columnNames = "columnNames"
    public static let rows = "rows"
    public static let truncated = "truncated"
    public static let binaryByteCount = "bytes"
    public static let plot = "plot"
    public static let paths = "paths"
    public static let points = "points"
    public static let simplified = "simplified"
}

/// Compact text coding of plotted coordinates: `longitude,latitude` pairs separated by one
/// space, each with five decimals (about one metre). A whole chunk is one JSON string so a large
/// track costs one node, not thousands, in the outline the views build.
public enum DataPlotCoding {
    public typealias Position = (longitude: Double, latitude: Double)
    /// Pairs per chunk keep every string far below the shared line limit.
    public static let maximumPositionsPerChunk = 400
    /// Positions drawn for one document; adapters decimate to stay within it.
    public static let maximumPositions = 4_000

    public static func encode(_ positions: some Sequence<Position>) -> String {
        positions.map { String(format: "%.5f,%.5f", $0.longitude, $0.latitude) }.joined(separator: " ")
    }

    /// Returns nil for any malformed or concealed chunk, so a view skips it entirely.
    public static func decode(_ text: String, limit: Int = maximumPositionsPerChunk) -> [Position]? {
        var result: [Position] = []
        for pair in text.split(separator: " ", omittingEmptySubsequences: true) {
            guard result.count < limit else { return nil }
            let parts = pair.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2, let longitude = Double(parts[0]), let latitude = Double(parts[1]),
                  longitude.isFinite, latitude.isFinite,
                  (-180.0...180.0).contains(longitude), (-90.0...90.0).contains(latitude) else { return nil }
            result.append((longitude, latitude))
        }
        return result.isEmpty ? nil : result
    }
}
