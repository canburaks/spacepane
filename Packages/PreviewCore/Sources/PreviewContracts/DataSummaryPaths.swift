import Foundation

/// The members each data format's summary document may contain, by parent path.
///
/// One declaration serves both sides of the summary contract. The renderers translate exactly the
/// names listed here (and no others, so document data that happens to share a word is never
/// translated), and tests prove that what an adapter writes stays inside it. A path lists the
/// parent keys from the document root, with `[]` for any array element.
///
/// Paths that are absent hold document data or technical identifiers: Parquet column paths, Avro
/// field names, GeoJSON property names, geometry type names and the values of table cells.
public enum DataSummaryPaths {
    private static let table = ["columns", "columnNames", "rows", "truncated"]
    private static let metadata = ["key", "value"]
    private static let plot = ["paths", "points", "simplified"]
    private static let bounds = ["west", "south", "east", "north"]
    private static let ranges = ["totalDistanceMeters", "elevationMinMeters", "elevationMaxMeters",
                                 "timeStart", "timeEnd", "durationSeconds"]

    private static func tabular(_ root: [String], _ others: [[String]: [String]] = [:]) -> [[String]: [String]] {
        var paths: [[String]: [String]] = [[]: root + ["table"], ["table"]: table,
                                           ["table", "rows", "[]", "[]"]: [DataSummaryKeys.binaryByteCount]]
        for (path, names) in others { paths[path] = names }
        return paths
    }

    private static func geographic(_ root: [String]) -> [[String]: [String]] {
        [[]: root + ["bounds", "plot"], ["bounds"]: bounds, ["plot"]: plot]
    }

    private static let schemas: [FormatID: [[String]: [String]]] = [
        .parquet: tabular(["dataFormat", "formatVersion", "createdBy", "rowCount", "rowGroupCount", "columnCount",
                           "rowGroups", "metadata", "partial", "rowSample"], [
            ["rowSample"]: table,
            ["rowSample", "rows", "[]", "[]"]: [DataSummaryKeys.binaryByteCount],
            ["rowGroups", "[]"]: ["rows", "uncompressedBytes", "compressedBytes", "columnChunks"],
            ["rowGroups", "[]", "columnChunks", "[]"]: ["path", "type", "codec", "encodings", "compressedBytes",
                                                        "uncompressedBytes", "valueCount", "nullCount"],
            ["metadata", "[]"]: metadata]),
        .avro: tabular(["dataFormat", "codec", "recordCount", "blockCount", "partial", "schema", "metadata"],
                       [["metadata", "[]"]: metadata]),
        .arrow: tabular(["dataFormat", "formatVersion", "columnCount", "rowCount", "recordBatchCount",
                         "dictionaryCount", "partial", "metadata"], [["metadata", "[]"]: metadata]),
        .numpy: tabular(["dataFormat", "formatVersion", "dtype", "shape", "elementCount", "fortranOrder", "fields"],
                        [["fields", "[]"]: ["name", "dtype"]]),
        .numpyArchive: tabular(["dataFormat", "arrayCount", "arrays", "partial", "shownArray"],
                               [["arrays", "[]"]: ["name", "dtype", "shape"]]),
        .har: tabular(["dataFormat", "formatVersion", "creator", "browser", "pageCount", "entryCount", "partial"]),
        .geoJSON: geographic(["dataFormat", "featureCount", "featuresWithoutGeometry", "geometryTypes",
                              "propertyKeys", "partial", "coordinateCount", "invalidPositions"]),
        .gpx: geographic(["dataFormat", "formatVersion", "creator", "waypointCount", "routeCount", "trackCount",
                          "trackSegmentCount", "coordinateCount", "invalidPositions", "names"] + ranges),
        .kml: geographic(["dataFormat", "placemarkCount", "folderCount", "geometryTypes", "coordinateCount",
                          "invalidPositions", "names"] + ranges)
    ]

    /// Names the summary of `format` may use for the children of `path`, or nil when that path holds
    /// document data or technical identifiers.
    public static func fields(for format: FormatID, path: [String]) -> Set<String>? {
        if format == .avro, let node = avroNodeFields(path) { return node }
        return schemas[format]?[path].map(Set.init)
    }

    /// Formats whose summary schema is declared here.
    public static var formats: Set<FormatID> { Set(schemas.keys) }

    /// Avro schema nodes nest without a fixed depth: `schema`, `items` and `values` hold a node,
    /// and each element of `fields` and `branches` is one.
    private static func avroNodeFields(_ path: [String]) -> Set<String>? {
        guard let last = path.last else { return nil }
        let isNode: Bool
        if last == "[]" {
            isNode = path.dropLast().last.map { $0 == "fields" || $0 == "branches" } ?? false
        } else {
            isNode = ["schema", "items", "values"].contains(last)
        }
        return isNode ? ["name", "kind", "typeName", "logicalType", "partial", "fields", "items", "values",
                         "branches", "symbols", "size"] : nil
    }

    /// Every distinct name any format may use; renderers must label all of them.
    public static var allNames: Set<String> {
        var names = Set(schemas.values.flatMap { $0.values.flatMap { $0 } })
        names.formUnion(["name", "kind", "typeName", "logicalType", "partial", "fields", "items", "values",
                         "branches", "symbols", "size"])
        return names
    }
}
