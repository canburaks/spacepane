import Foundation
import PreviewContracts

/// Wire names to localized labels for the data summaries and their table headers. A name is only
/// translated at the paths a set lists (see `SummaryLabelSet`); document data such as Avro field
/// names, Parquet column names, GeoJSON property names and metadata keys is never in these tables.
enum DataSchemaLabels {
    static let keys: [String: PreviewStrings.Key] = [
        "dataFormat": .dataFormat, "formatVersion": .dataFormatVersion, "createdBy": .dataCreatedBy,
        "rowCount": .dataRowCount, "columnCount": .dataColumnCount, "rowGroupCount": .dataRowGroupCount,
        "rowGroups": .dataRowGroups, "columnChunks": .dataColumnChunks,
        "uncompressedBytes": .dataUncompressedBytes, "compressedBytes": .dataCompressedBytes,
        "valueCount": .dataValueCount, "nullCount": .dataNullCount, "codec": .dataCodec,
        "encodings": .dataEncodings, "metadata": .dataMetadata, "key": .dataKey,
        "recordCount": .dataRecordCount, "blockCount": .dataBlockCount, "fields": .dataFields,
        "items": .dataItemType, "values": .dataValueType, "branches": .dataBranches, "symbols": .dataSymbols,
        "size": .dataSizeBytes, "logicalType": .dataLogicalType, "typeName": .dataTypeName,
        "recordBatchCount": .dataRecordBatchCount, "dictionaryCount": .dataDictionaryCount,
        "dtype": .dataDtype, "shape": .dataShape, "elementCount": .dataElementCount,
        "fortranOrder": .dataFortranOrder, "arrayCount": .dataArrayCount, "arrays": .dataArrays,
        "shownArray": .dataShownArray, "creator": .dataCreator, "browser": .dataBrowser,
        "pageCount": .dataPageCount, "entryCount": .dataEntryCount, "featureCount": .dataFeatureCount,
        "featuresWithoutGeometry": .dataFeaturesWithoutGeometry, "geometryTypes": .dataGeometryTypes,
        "propertyKeys": .dataPropertyKeys, "coordinateCount": .dataCoordinateCount,
        "invalidPositions": .dataInvalidPositions, "bounds": .dataBounds, "west": .dataWest,
        "south": .dataSouth, "east": .dataEast, "north": .dataNorth, "waypointCount": .dataWaypointCount,
        "routeCount": .dataRouteCount, "trackCount": .dataTrackCount, "trackSegmentCount": .dataTrackSegmentCount,
        "totalDistanceMeters": .dataTotalDistance, "elevationMinMeters": .dataElevationMin,
        "elevationMaxMeters": .dataElevationMax, "timeStart": .dataTimeStart, "timeEnd": .dataTimeEnd,
        "durationSeconds": .dataDuration, "placemarkCount": .dataPlacemarkCount, "folderCount": .dataFolderCount,
        "names": .dataNames, "plot": .previewModePlot, "paths": .dataPaths, "points": .dataPoints,
        "simplified": .dataSimplified, "partial": .dataPartial,
        // Names shared with the existing generated summaries.
        "name": .summaryName, "kind": .summaryType, "type": .summaryType, "path": .summaryPath,
        "value": .summaryValue, "table": .summaryTable, "columns": .summaryColumns,
        "columnNames": .summaryColumns, "rows": .summaryRows, "truncated": .summaryTruncated,
        "schema": .summarySchema, "bytes": .summaryBytes, "rowSample": .summaryRows,
        // Table column identifiers (see `DataTable` with `.identifiers`).
        "repetition": .dataRepetition, "physicalType": .dataPhysicalType, "convertedType": .dataConvertedType,
        "nullable": .dataNullable, "method": .dataMethod, "url": .dataURL, "status": .dataStatus,
        "mimeType": .dataMIMEType, "time": .dataTime, "column": .dataColumn, "declaredType": .dataDeclaredType,
        "notNull": .dataNotNull, "defaultValue": .dataDefaultValue, "primaryKey": .dataPrimaryKey,
        "foreignKey": .dataForeignKey, "indexes": .dataIndexes
    ]

    /// Table columns whose cells are `true`/`false` and shown as Yes/No.
    static let booleanColumns: Set<String> = ["nullable", "notNull"]

    static let countFields: Set<String> = [
        "rowCount", "columnCount", "rowGroupCount", "uncompressedBytes", "compressedBytes", "valueCount",
        "nullCount", "recordCount", "blockCount", "size", "recordBatchCount", "dictionaryCount", "elementCount",
        "arrayCount", "pageCount", "entryCount", "featureCount", "featuresWithoutGeometry", "coordinateCount",
        "invalidPositions", "waypointCount", "routeCount", "trackCount", "trackSegmentCount",
        "totalDistanceMeters", "elevationMinMeters", "elevationMaxMeters", "durationSeconds", "placemarkCount",
        "folderCount", "rows"
    ]
    static let booleanFields: Set<String> = ["partial", "truncated", "fortranOrder", "simplified"]

    static func set(for format: FormatID) -> SummaryLabelSet {
        SummaryLabelSet(formats: [format], fields: { DataSummaryPaths.fields(for: format, path: $0) }, keys: keys,
                        booleanFields: booleanFields, countFields: countFields)
    }
}

/// One set per format: the path rules are declared once in `DataSummaryPaths`, which the adapters'
/// tests also check, so the names an adapter writes and the names translated here cannot drift.
extension SummaryLabelSet {
    static let dataParquet = DataSchemaLabels.set(for: .parquet)
    static let dataAvro = DataSchemaLabels.set(for: .avro)
    static let dataArrow = DataSchemaLabels.set(for: .arrow)
    static let dataNumPy = DataSchemaLabels.set(for: .numpy)
    static let dataNumPyArchive = DataSchemaLabels.set(for: .numpyArchive)
    static let dataHAR = DataSchemaLabels.set(for: .har)
    static let dataGeoJSON = DataSchemaLabels.set(for: .geoJSON)
    static let dataGPX = DataSchemaLabels.set(for: .gpx)
    static let dataKML = DataSchemaLabels.set(for: .kml)
}
