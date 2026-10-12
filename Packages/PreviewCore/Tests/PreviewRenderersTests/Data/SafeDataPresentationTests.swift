import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The renderer side of the data summaries: the Table and Plot derivations, the mode choices and the
/// label sets. The JSON below is the envelope the adapters write, as the privacy filter leaves it.
@Suite("Safe data presentation")
@MainActor
struct SafeDataPresentationTests {
    private func presentation(_ formatID: FormatID, _ json: String, syntax: TextSyntax = .json) -> TextPresentation {
        TextPresentation(formatID: formatID, text: json, lineCount: json.split(separator: "\n").count,
                         byteCount: json.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax)
    }

    private let parquet = """
    {
      "dataFormat": "Parquet",
      "rowCount": 3,
      "table": {
        "columns": ["name", "repetition", "physicalType", "convertedType", "logicalType"],
        "rows": [["id", "REQUIRED", "INT64", "", ""], ["address.city", "OPTIONAL", "BYTE_ARRAY", "UTF8", ""]],
        "truncated": false
      }
    }
    """

    private let avro = """
    {
      "dataFormat": "Avro",
      "table": {
        "columnNames": ["name", "type", "password", "blob", "nick"],
        "rows": [["row 1", "x", "••••", {"bytes": 1234}, null], ["row 2", "y", "••••", {"bytes": 2}, "n"]],
        "truncated": true
      }
    }
    """

    // MARK: Table

    @Test func columnIdentifiersAreTranslatedButDocumentNamesNever() throws {
        let labelled = try #require(SafeDataPresentation.derive(presentation(.parquet, parquet), locale: .current)?.table)
        #expect(labelled.columns == [PreviewStrings.text(.summaryName), PreviewStrings.text(.dataRepetition),
                                     PreviewStrings.text(.dataPhysicalType), PreviewStrings.text(.dataConvertedType),
                                     PreviewStrings.text(.dataLogicalType)])
        #expect(labelled.rows == [["id", "REQUIRED", "INT64", "", ""], ["address.city", "OPTIONAL", "BYTE_ARRAY", "UTF8", ""]])
        #expect(labelled.truncation.isEmpty)
        // Avro field names that equal wire words (name, type) are the document's own and stay as written.
        let named = try #require(SafeDataPresentation.derive(presentation(.avro, avro), locale: .current)?.table)
        #expect(named.columns == ["name", "type", "password", "blob", "nick"])
        #expect(named.truncation == .rows)
        #expect(named.rows[0][2] == "••••" && named.rows[1][2] == "••••")
    }

    @Test func cellsJoinSegmentsFormatBinaryAndBooleansForTheLocale() throws {
        let german = Locale(identifier: "de_DE")
        let table = try #require(SafeDataPresentation.derive(presentation(.avro, avro), locale: german)?.table)
        #expect(table.rows[0][3] == PreviewStrings.format(.dataBinaryValue, arguments: ["1.234"], locale: german))
        #expect(table.rows[1][3] == PreviewStrings.format(.dataBinaryValue, arguments: ["2"], locale: german))
        #expect(table.rows[0][4] == "null" && table.rows[1][4] == "n")

        let segments = """
        {"dataFormat": "HAR", "table": {"columns": ["method", "url", "status"],
          "rows": [["GET", ["https://h/p?", "k", "=", "••••", "&z"], "200"]], "truncated": false}}
        """
        let har = try #require(SafeDataPresentation.derive(presentation(.har, segments), locale: .current)?.table)
        #expect(har.rows == [["GET", "https://h/p?k=••••&z", "200"]])

        let grid = """
        {"table": {"columns": ["table", "column", "notNull", "primaryKey"],
          "rows": [["t", "a", "true", "1"], ["t", "b", "false", ""], ["t", "c", "maybe", ""]], "truncated": false}}
        """
        let sqlite = try #require(SafeDataPresentation.derive(presentation(.sqlite, grid), locale: .current)?.table)
        #expect(sqlite.rows.map { $0[2] } == [PreviewStrings.text(.summaryBooleanTrue), PreviewStrings.text(.summaryBooleanFalse), "maybe"])
        #expect(sqlite.columns[0] == PreviewStrings.text(.summaryTable) && sqlite.columns[1] == PreviewStrings.text(.dataColumn))
    }

    @Test func unknownIdentifiersEmptyHeadersAndWideTablesAreHandled() throws {
        let numpy = """
        {"dataFormat": "NumPy", "table": {"columns": ["#", "0", "value", ""], "rows": [["0", "1", "2", "3"]], "truncated": true}}
        """
        let table = try #require(SafeDataPresentation.derive(presentation(.numpy, numpy), locale: .current)?.table)
        #expect(table.columns == ["#", "0", PreviewStrings.text(.summaryValue), PreviewStrings.format(.previewTableColumn, arguments: [Int64(4)], locale: .current)])
        let wideColumns = (0..<90).map { "\"c\($0)\"" }.joined(separator: ",")
        let wideRow = (0..<90).map { "\"\($0)\"" }.joined(separator: ",")
        let wide = #"{"dataFormat": "Avro", "table": {"columnNames": [\#(wideColumns)], "rows": [[\#(wideRow)]], "truncated": false}}"#
        let cut = try #require(SafeDataPresentation.derive(presentation(.avro, wide), locale: .current)?.table)
        #expect(cut.columns.count == SafeDelimitedTable.maximumColumns && cut.rows[0].count == SafeDelimitedTable.maximumColumns)
    }

    @Test func formatsWithoutTheEnvelopeAndNonJSONTextGetNoTable() {
        #expect(SafeDataPresentation.derive(presentation(.json, parquet), locale: .current) == nil)
        #expect(SafeDataPresentation.derive(presentation(.parquet, parquet, syntax: .plain), locale: .current) == nil)
        #expect(SafeDataPresentation.derive(presentation(.parquet, "{ not json"), locale: .current) == nil)
        let none = SafeDataPresentation.derive(presentation(.har, #"{"dataFormat": "HAR"}"#), locale: .current)
        #expect(none?.table == nil && none?.plot == nil)
    }

    // MARK: Plot

    private func plotJSON(paths: String = #"[["1.00000,2.00000 3.00000,4.00000"]]"#, points: String = #"["5.00000,6.00000"]"#,
                          simplified: Bool = false) -> String {
        #"{"dataFormat": "GPX", "plot": {"paths": \#(paths), "points": \#(points), "simplified": \#(simplified)}}"#
    }

    @Test func plotChunksDecodeAndConcealedOrMalformedChunksAreDropped() throws {
        let plot = try #require(SafeDataPresentation.derive(presentation(.gpx, plotJSON()), locale: .current)?.plot)
        #expect(plot.paths == [[.init(longitude: 1, latitude: 2), .init(longitude: 3, latitude: 4)]])
        #expect(plot.points == [.init(longitude: 5, latitude: 6)])
        #expect(!plot.simplified)
        let extent = try #require(plot.extent)
        #expect(extent.west == 1 && extent.east == 5 && extent.south == 2 && extent.north == 6)

        // A chunk the privacy filter replaced, one that is malformed and an out-of-range one vanish whole.
        let damaged = plotJSON(paths: #"[["••••"], ["1.00000,2.00000 3.00000,4.00000", "bad"], ["0,0 200,0"], ["9.00000,9.00000"]]"#,
                               points: #"["••••", "181,0", "7.00000,8.00000"]"#, simplified: true)
        let remaining = try #require(SafeDataPresentation.derive(presentation(.gpx, damaged), locale: .current)?.plot)
        #expect(remaining.paths == [[.init(longitude: 1, latitude: 2), .init(longitude: 3, latitude: 4)]])
        #expect(remaining.points == [.init(longitude: 7, latitude: 8)])
        #expect(remaining.simplified)
        // Nothing drawable means no plot.
        #expect(SafeDataPresentation.derive(presentation(.gpx, plotJSON(paths: "[]", points: "[]")), locale: .current)?.plot == nil)
    }

    @Test func plotSizeIsBoundedWhateverTheTextClaims() throws {
        // 30 paths of 400 positions fit the outline limit but exceed the drawing budget of 8,000 positions.
        let chunk = (0..<400).map { "\($0 % 100).00000,10.00000" }.joined(separator: " ")
        let heavy = plotJSON(paths: "[" + Array(repeating: "[\"\(chunk)\"]", count: 30).joined(separator: ",") + "]", points: "[]")
        let plot = try #require(SafeDataPresentation.derive(presentation(.gpx, heavy), locale: .current)?.plot)
        #expect(plot.positions.count <= SafeDataPresentation.maximumPositions)
        #expect(plot.paths.count == SafeDataPresentation.maximumPositions / 400)
        // Many tiny paths are capped by count.
        let many = plotJSON(paths: "[" + Array(repeating: "[\"1.00000,1.00000 2.00000,2.00000\"]", count: 700).joined(separator: ",") + "]", points: "[]")
        let capped = try #require(SafeDataPresentation.derive(presentation(.gpx, many), locale: .current)?.plot)
        #expect(capped.paths.count == SafeDataPresentation.maximumPaths)
    }

    // MARK: Modes

    @Test func tableFormatsOpenAsATableAndGeographicFormatsAsAPlot() throws {
        let tabular = SafePreviewModes(presentation(.parquet, parquet), locale: .current)
        #expect(tabular.available == [.source, .summary, .table])
        #expect(tabular.initialMode(for: .parquet) == .table)
        #expect(tabular.plot == nil)

        let geographic = SafePreviewModes(presentation(.gpx, plotJSON()), locale: .current)
        #expect(geographic.available == [.source, .summary, .plot])
        #expect(geographic.initialMode(for: .gpx) == .plot)
        #expect(NativePreviewMode.plot.title == .previewModePlot)

        // Without anything to draw or tabulate the generic summary choice applies.
        let plain = SafePreviewModes(presentation(.har, #"{"dataFormat": "HAR", "entryCount": 0}"#), locale: .current)
        #expect(plain.available == [.source, .summary] && plain.initialMode(for: .har) == .summary)
        #expect(plain.hasStructureFallback == false)
    }

    @Test func aRowSampleIsASecondTableAndOpensFirst() throws {
        let json = """
        {"dataFormat": "Parquet", "rowCount": 2,
         "table": {"columns": ["name", "repetition", "physicalType", "convertedType", "logicalType"],
                   "rows": [["id", "REQUIRED", "INT64", "", ""]], "truncated": false},
         "rowSample": {"columnNames": ["id", "name", "api_token"],
                       "rows": [["10", "alpha", "••••"], ["20", null, "••••"]], "truncated": true}}
        """
        let modes = SafePreviewModes(presentation(.parquet, json), locale: .current)
        #expect(modes.available == [.source, .summary, .table, .rows])
        #expect(modes.initialMode(for: .parquet) == .rows)
        #expect(NativePreviewMode.rows.title == .summaryRows)
        let rows = try #require(modes.sampleRows)
        #expect(rows.columns == ["id", "name", "api_token"] && rows.truncation == .rows)
        #expect(rows.rows == [["10", "alpha", "••••"], ["20", "null", "••••"]])
        // The schema table is untouched beside it.
        #expect(modes.table?.columns.first == PreviewStrings.text(.summaryName))

        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        view.display(.ready(presentation(.parquet, json)))
        let rowsView = try #require(descendants(of: NativeRowsPreviewView.self, in: view).first)
        #expect(!rowsView.isHidden && rowsView.table.tableView.numberOfRows == 2)
        #expect(rowsView.table.tableView.tableColumns.map(\.title) == ["id", "name", "api_token"])
        let control = view.modeControl
        #expect((0..<control.segmentCount).map { control.label(forSegment: $0) }.last == PreviewStrings.text(.summaryRows))
        view.display(.unavailable(.malformedDocument))
        #expect(rowsView.isHidden && rowsView.table.tableView.numberOfRows == 0)
        #expect(SafeModeViewRegistry.makeView(for: .rows) is NativeRowsPreviewView)
    }

    @Test func theSQLiteGridIsAnExtraModeAndSummaryStaysFirst() throws {
        let json = """
        {"databaseFormat": "SQLite", "schema": [], "pages": [], "tableCount": 0,
         "table": {"columns": ["table", "column"], "rows": [["t", "a"]], "truncated": false}}
        """
        let modes = SafePreviewModes(presentation(.sqlite, json), locale: .current)
        #expect(modes.available.contains(.table) && modes.available.contains(.summary))
        #expect(modes.initialMode(for: .sqlite) == .summary)
    }

    @Test func nativePreviewViewHostsTheTableAndThePlotWithSourceStillAvailable() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        view.display(.ready(presentation(.parquet, parquet)))
        let table = try #require(descendants(of: NativeTablePreviewView.self, in: view).first)
        let control = view.modeControl
        #expect(!table.isHidden && table.tableView.numberOfRows == 2)
        #expect((0..<control.segmentCount).map { control.label(forSegment: $0) }
                == [PreviewStrings.text(.previewModeSource), PreviewStrings.text(.previewModeSummary), PreviewStrings.text(.previewModeTable)])
        #expect(control.selectedSegment == 2)

        view.display(.ready(presentation(.gpx, plotJSON())))
        let plot = try #require(descendants(of: NativePlotPreviewView.self, in: view).first)
        #expect(!plot.isHidden && table.isHidden)
        let plotControl = view.modeControl
        #expect((0..<plotControl.segmentCount).map { plotControl.label(forSegment: $0) }.last == PreviewStrings.text(.previewModePlot))
        plotControl.selectedSegment = 0
        #expect(plotControl.sendAction(plotControl.action, to: plotControl.target))
        #expect(plot.isHidden)
        view.display(.unavailable(.malformedDocument))
        #expect(plot.isHidden && plot.canvas.accessibilityLabel() == nil)
    }

    // MARK: Labels

    @Test func everyDeclaredSummaryNameHasALabelAndEveryDataFormatUsesTheSets() {
        for name in DataSummaryPaths.allNames {
            #expect(DataSchemaLabels.keys[name] != nil, "\(name)")
        }
        for format in FormatID.dataSummaryFormats {
            #expect(SafeSchemaLabels.formats.contains(format), "\(format.rawValue)")
            #expect(SafeSchemaLabels.labelSet(for: format) != nil)
        }
        for identifier in ["repetition", "physicalType", "convertedType", "nullable", "method", "url", "status", "mimeType",
                           "time", "column", "declaredType", "notNull", "defaultValue", "primaryKey", "foreignKey", "indexes"] {
            #expect(DataSchemaLabels.keys[identifier] != nil, "table header \(identifier)")
        }
    }

    @Test func summariesTranslateTheDeclaredNamesAndNothingTheDocumentOwns() throws {
        let json = """
        {"dataFormat": "Parquet", "rowCount": 1234567, "partial": true,
         "rowGroups": [{"rows": 5, "columnChunks": [{"path": "rowCount", "type": "INT32", "codec": "SNAPPY", "nullCount": 2}]}],
         "metadata": [{"key": "rowCount", "value": "partial"}]}
        """
        let nodes = try #require(SafeStructuredText.json(json))
        let german = Locale(identifier: "de_DE")
        let localized = SafeSchemaLabels.localize(nodes, formatID: .parquet, locale: german)
        func find(_ names: [String], in node: SafeOutlineNode) -> SafeOutlineNode? {
            guard let first = names.first else { return node }
            return node.children.first { $0.name == first }.flatMap { find(Array(names.dropFirst()), in: $0) }
        }
        let root = try #require(localized.first)
        #expect(find([PreviewStrings.text(.dataFormat)], in: root)?.value == "Parquet")
        #expect(find([PreviewStrings.text(.dataRowCount)], in: root)?.value == (1_234_567 as Int64).formatted(.number.locale(german)))
        #expect(find([PreviewStrings.text(.dataPartial)], in: root)?.value == PreviewStrings.text(.summaryBooleanTrue))
        let groups = try #require(find([PreviewStrings.text(.dataRowGroups)], in: root))
        let chunk = try #require(find(["[0]", PreviewStrings.text(.dataColumnChunks), "[0]"], in: groups))
        // The chunk's column path is a document name shown as written; its labelled fields translate.
        #expect(find([PreviewStrings.text(.summaryPath)], in: chunk)?.value == "rowCount")
        #expect(find([PreviewStrings.text(.dataNullCount)], in: chunk)?.value == "2")
        let metadata = try #require(find([PreviewStrings.text(.dataMetadata), "[0]"], in: root))
        #expect(find([PreviewStrings.text(.dataKey)], in: metadata)?.value == "rowCount")
        #expect(find([PreviewStrings.text(.summaryValue)], in: metadata)?.value == "partial")
    }

    @Test func geographicNamesStayAsWrittenWhileTheirContainersAreLabelled() throws {
        let json = """
        {"dataFormat": "GeoJSON", "featureCount": 2, "geometryTypes": {"Point": 1, "bounds": 1},
         "propertyKeys": ["bounds", "plot"], "bounds": {"west": "1.000000", "south": "2.000000", "east": "3.000000", "north": "4.000000"}}
        """
        let nodes = try #require(SafeStructuredText.json(json))
        let root = try #require(SafeSchemaLabels.localize(nodes, formatID: .geoJSON, locale: .current).first)
        let types = try #require(root.children.first { $0.name == PreviewStrings.text(.dataGeometryTypes) })
        #expect(types.children.map(\.name) == ["Point", "bounds"])
        let keys = try #require(root.children.first { $0.name == PreviewStrings.text(.dataPropertyKeys) })
        #expect(keys.children.map(\.value) == ["bounds", "plot"])
        let bounds = try #require(root.children.first { $0.name == PreviewStrings.text(.dataBounds) })
        #expect(bounds.children.map(\.name) == [PreviewStrings.text(.dataWest), PreviewStrings.text(.dataSouth),
                                                 PreviewStrings.text(.dataEast), PreviewStrings.text(.dataNorth)])
    }

    @Test func avroSchemaNodesAreLabelledAtEveryDepth() throws {
        let json = """
        {"dataFormat": "Avro", "schema": {"kind": "record", "typeName": "n.R", "fields": [
          {"name": "kind", "kind": "union", "branches": [{"kind": "null"}, {"kind": "map", "values": {"kind": "long", "logicalType": "timestamp-millis"}}]}]}}
        """
        let nodes = try #require(SafeStructuredText.json(json))
        let root = try #require(SafeSchemaLabels.localize(nodes, formatID: .avro, locale: .current).first)
        func descend(_ names: [String], from node: SafeOutlineNode) -> SafeOutlineNode? {
            names.reduce(Optional(node)) { current, name in current?.children.first { $0.name == name } }
        }
        let schema = try #require(descend([PreviewStrings.text(.summarySchema)], from: root))
        let field = try #require(descend([PreviewStrings.text(.dataFields), "[0]"], from: schema))
        // The field is called "kind" in the document; that value is verbatim, the key is the label.
        #expect(descend([PreviewStrings.text(.summaryName)], from: field)?.value == "kind")
        let map = try #require(descend([PreviewStrings.text(.dataBranches), "[1]"], from: field))
        let values = try #require(descend([PreviewStrings.text(.dataValueType)], from: map))
        #expect(descend([PreviewStrings.text(.dataLogicalType)], from: values)?.value == "timestamp-millis")
    }

    @Test func dataLabelsAreRealTranslationsInScriptsThatShareNoWordsWithEnglish() {
        let keys: [PreviewStrings.Key] = [.dataFormat, .dataRowCount, .dataColumnChunks, .dataCodec, .dataMetadata, .dataKey, .dataBounds,
                                          .dataTotalDistance, .dataTimeStart, .dataPaths, .dataPlotAccessibility, .dataPlotExtent,
                                          .dataPlotSimplified, .dataPlotHelp, .dataBinaryValue, .previewModePlot, .dataPrimaryKey]
        for language in ["tr", "ru", "zh-Hans", "bn", "ja", "hi"] {
            for key in keys {
                #expect(PreviewStrings.text(key, languagePreferences: [language]) != PreviewStrings.text(key, languagePreferences: ["en"]),
                        "\(key.rawValue) in \(language)")
            }
        }
    }
}
