import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Every key an adapter writes must be declared in `DataSummaryPaths`, which the renderers use as the
/// only list of names to translate. This keeps adapters and labels in step without either module
/// importing the other.
@Suite("Data summary schema")
struct DataSummarySchemaTests {
    private func undeclared(_ value: Any, path: [String], format: FormatID) -> [String] {
        var failures: [String] = []
        if let object = value as? [String: Any] {
            // Geometry type names are GeoJSON/KML identifiers, written as keys on purpose.
            if path == ["geometryTypes"] { return [] }
            let allowed = DataSummaryPaths.fields(for: format, path: path)
            for (key, child) in object {
                if allowed?.contains(key) != true { failures.append("\(path.joined(separator: "/"))/\(key)") }
                failures += undeclared(child, path: path + [key], format: format)
            }
        } else if let array = value as? [Any] {
            for child in array { failures += undeclared(child, path: path + ["[]"], format: format) }
        }
        return failures
    }

    private func check(_ format: FormatID, _ document: ParsedTextDocument) throws {
        let object = try DataTest.object(document)
        let failures = undeclared(object, path: [], format: format)
        #expect(failures.isEmpty, "\(format.rawValue): \(failures)")
    }

    @Test func fixtureOutputStaysInsideTheDeclaredSchemas() throws {
        try check(.parquet, try DataTest.parse(ParquetAdapter(), DataFixtures.parquet))
        try check(.parquet, try DataTest.parse(ParquetAdapter(), DataFixtures.parquetRows))
        try check(.avro, try DataTest.parse(AvroAdapter(), DataFixtures.avro))
        try check(.arrow, try DataTest.parse(ArrowAdapter(), DataFixtures.arrowFile))
        try check(.arrow, try DataTest.parse(ArrowAdapter(), DataFixtures.arrowManyBatches))
        try check(.numpy, try DataTest.parse(NumPyAdapter(), DataFixtures.numpy))
        try check(.numpyArchive, try DataTest.parse(NumPyArchiveAdapter(), DataFixtures.numpyArchive))
        try check(.har, try DataTest.parse(HARAdapter(), DataFixtures.har))
        try check(.geoJSON, try DataTest.parse(GeoJSONAdapter(), DataFixtures.geoJSON))
        try check(.gpx, try DataTest.parse(GPXAdapter(), DataFixtures.gpx))
        try check(.kml, try DataTest.parse(KMLAdapter(), DataFixtures.kml))
    }

    @Test func richerShapesStayInsideTheDeclaredSchemas() throws {
        // A nested Avro schema with every complex kind and a binary cell.
        let schema = """
        {"type":"record","name":"R","namespace":"n","fields":[
          {"name":"e","type":{"type":"enum","name":"E","symbols":["A","B"]}},
          {"name":"f","type":{"type":"fixed","name":"F","size":4}},
          {"name":"m","type":{"type":"map","values":{"type":"array","items":["null","long"]}}},
          {"name":"u","type":["null",{"type":"record","name":"Inner","fields":[{"name":"x","type":{"type":"long","logicalType":"timestamp-millis"}}]}]},
          {"name":"again","type":["null","R"]},{"name":"raw","type":"bytes"}]}
        """
        let payload = AvroWriter.long(1) + [1, 2, 3, 4] + AvroWriter.long(0) + AvroWriter.long(0) + AvroWriter.long(0)
            + AvroWriter.long(2) + [7, 7]
        let avro = AvroWriter.container(schema: schema, blocks: [(count: 1, payload: payload)])
        let document = try DataTest.parse(AvroAdapter(), avro)
        try check(.avro, document)
        let object = try DataTest.object(document)
        #expect(try DataTest.rows(object).first?.last == "bytes:2")

        let routes = #"<gpx version="1.1"><rte><name>R</name><rtept lat="1" lon="1"/><rtept lat="2" lon="2"/></rte></gpx>"#
        try check(.gpx, try DataTest.parse(GPXAdapter(), Data(routes.utf8)))
        let collection = #"{"type":"GeometryCollection","geometries":[{"type":"Point","coordinates":[1,2]},{"type":"LineString","coordinates":[[0,0],[1,1]]}]}"#
        try check(.geoJSON, try DataTest.parse(GeoJSONAdapter(), Data(collection.utf8)))
    }

    @Test func declaredNamesAreCompleteAndTechnicalPathsStayUntranslated() {
        #expect(DataSummaryPaths.formats == FormatID.dataSummaryFormats)
        #expect(DataSummaryPaths.allNames.contains("table") && DataSummaryPaths.allNames.contains("plot"))
        #expect(DataSummaryPaths.fields(for: .parquet, path: ["table"]) == ["columns", "columnNames", "rows", "truncated"])
        #expect(DataSummaryPaths.fields(for: .har, path: []) != nil)
        #expect(DataSummaryPaths.fields(for: .geoJSON, path: ["plot"]) == ["paths", "points", "simplified"])
        #expect(DataSummaryPaths.fields(for: .geoJSON, path: ["geometryTypes"]) == nil)
        #expect(DataSummaryPaths.fields(for: .avro, path: ["schema", "fields", "[]", "branches", "[]"])?.contains("kind") == true)
        #expect(DataSummaryPaths.fields(for: .avro, path: ["schema", "symbols"]) == nil)
        #expect(DataSummaryPaths.fields(for: .sqlite, path: []) == nil)
    }
}
