import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// An independent haversine, so the expected distances do not come from the code under test.
private func greatCircle(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
    let radius = 6_371_008.8
    let (lon1, lat1, lon2, lat2) = (a.0 * .pi / 180, a.1 * .pi / 180, b.0 * .pi / 180, b.1 * .pi / 180)
    let h = pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
    return 2 * radius * asin(sqrt(h))
}

private func plotPaths(_ object: [String: Any]) throws -> [[DataPlotCoding.Position]] {
    let plot = try #require(object["plot"] as? [String: Any])
    let paths = (plot["paths"] as? [[String]]) ?? []
    return try paths.map { chunks in try chunks.flatMap { try #require(DataPlotCoding.decode($0)) } }
}

private func plotPoints(_ object: [String: Any]) throws -> [DataPlotCoding.Position] {
    let plot = try #require(object["plot"] as? [String: Any])
    return try ((plot["points"] as? [String]) ?? []).flatMap { try #require(DataPlotCoding.decode($0)) }
}

@Suite("Geographic support")
struct GeoSupportTests {
    @Test func greatCircleDistanceMatchesTheDefinition() {
        #expect(abs(GeoDistance.haversine((0, 0), (1, 0)) - 111_194.93) < 1)
        #expect(abs(GeoDistance.haversine((12.49, 41.9), (12.5, 41.9)) - greatCircle((12.49, 41.9), (12.5, 41.9))) < 0.001)
        #expect(GeoDistance.haversine((10, 10), (10, 10)) == 0)
        // Antipodal points: half the circumference.
        #expect(abs(GeoDistance.haversine((0, 0), (180, 0)) - Double.pi * 6_371_008.8) < 1)
    }

    @Test func timesParseAgainstFoundationAsAnOracle() throws {
        let formatter = ISO8601DateFormatter()
        for text in ["2026-01-01T08:00:00Z", "1999-12-31T23:59:59Z", "2026-02-28T12:00:00+02:00", "2026-03-01T00:00:00-05:30",
                     "2026-06-15T10:20:30+0100", "2000-02-29T00:00:00Z", "1970-01-01T00:00:00Z", "1969-12-31T23:59:59Z"] {
            let expected = try #require(formatter.date(from: text.replacingOccurrences(of: "+0100", with: "+01:00")))
            #expect(GeoTime.epochSeconds(text) == expected.timeIntervalSince1970, "\(text)")
        }
        #expect(GeoTime.epochSeconds("2026-01-01") == 1_767_225_600)
        #expect(abs((GeoTime.epochSeconds("2026-01-01T00:00:00.250Z") ?? 0) - 1_767_225_600.25) < 1e-6)
        // A time without a zone is read as UTC, as KML permits.
        #expect(GeoTime.epochSeconds("2026-01-01T00:00:00") == 1_767_225_600)
        for invalid in ["", "2026", "2026-13-01", "2026-01-32T00:00:00Z", "2026-01-01T25:00:00Z",
                        "2026-01-01T00:00:00Zjunk", "2026/01/01", "abc", "2026-01-01T00:00:00+9999"] {
            #expect(GeoTime.epochSeconds(invalid) == nil, "\(invalid)")
        }
        #expect(GeoTime.format(1_767_254_400) == "2026-01-01T08:00:00Z")
        #expect(GeoTime.format(0) == "1970-01-01T00:00:00Z")
        #expect(GeoTime.format(-1) == "1969-12-31T23:59:59Z")
    }

    @Test func boundsCountInvalidPositionsInsteadOfClampingThem() {
        var bounds = GeoBounds()
        let results = [bounds.add(longitude: 10, latitude: 20), bounds.add(longitude: -10, latitude: -5),
                       bounds.add(longitude: 181, latitude: 0), bounds.add(longitude: 0, latitude: -90.5),
                       bounds.add(longitude: .nan, latitude: 0)]
        #expect(results == [true, true, false, false, false])
        #expect(bounds.positionCount == 2 && bounds.invalidCount == 3)
        #expect(bounds.west == -10 && bounds.east == 10 && bounds.south == -5 && bounds.north == 20)
    }

    @Test func plotCodingRoundTripsAndRejectsEverythingElse() {
        let coded = DataPlotCoding.encode([(longitude: 12.4964, latitude: 41.9028), (longitude: -0.1, latitude: -33.8)])
        #expect(coded == "12.49640,41.90280 -0.10000,-33.80000")
        #expect(DataPlotCoding.decode(coded)?.count == 2)
        for invalid in ["", "••••", "1,2,3", "1;2", "181,0", "0,91", "nan,0", "1,", ",1", "a,b"] {
            #expect(DataPlotCoding.decode(invalid) == nil, "\(invalid)")
        }
        #expect(DataPlotCoding.decode(Array(repeating: "1,1", count: 401).joined(separator: " ")) == nil)
    }

    @Test func thinningKeepsEndpointsAndTheLimit() {
        let path = (0..<10_000).map { (longitude: Double($0) / 100, latitude: 0.0) }
        let thinned = GeoPlot.thinned(path, keeping: 100)
        #expect(thinned.count == 100 && thinned.first?.longitude == 0 && thinned.last?.longitude == 99.99)
        #expect(GeoPlot.thinned(path, keeping: 20_000).count == 10_000)
        #expect(GeoPlot.thinned(path, keeping: 1).count == 1)
        #expect(GeoPlot.thinned([], keeping: 5).isEmpty)
    }
}

@Suite("GeoJSON adapter")
struct GeoJSONAdapterTests {
    @Test func collectionsCountFeaturesGeometriesKeysExtentAndPlot() throws {
        let document = try DataTest.parse(GeoJSONAdapter(), DataFixtures.geoJSON)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "GeoJSON")
        #expect(object["featureCount"] as? Int == 4 && object["featuresWithoutGeometry"] as? Int == 1)
        let types = try #require(object["geometryTypes"] as? [String: Int])
        #expect(types == ["Point": 1, "LineString": 1, "Polygon": 1])
        #expect(object["propertyKeys"] as? [String] == ["name", "password", "length"])
        #expect(object["coordinateCount"] as? Int == 9 && object["invalidPositions"] == nil)
        let bounds = try #require(object["bounds"] as? [String: String])
        #expect(bounds == ["west": "12.480000", "south": "41.880000", "east": "12.510000", "north": "41.910000"])
        let paths = try plotPaths(object)
        #expect(paths.count == 2 && paths[0].count == 3 && paths[1].count == 5)
        #expect(try plotPoints(object).count == 1)
        #expect((object["plot"] as? [String: Any])?["simplified"] == nil)
        #expect(document.syntax == .json && document.usesStructuredPrivacy)
    }

    @Test func propertyValuesAreNeverReadOnlyTheirNamesAreListed() throws {
        let document = try DataTest.parse(GeoJSONAdapter(), DataFixtures.geoJSON)
        #expect(!document.text.contains(DataFixtures.secret))
        #expect(document.text.contains("\"password\""))
        let nested = #"{"type":"Feature","geometry":null,"properties":{"a":{"b":[1,2,{"token":"synthetic-secret-value"}]}}}"#
        let object = try DataTest.object(try DataTest.parse(GeoJSONAdapter(), Data(nested.utf8)))
        #expect(object["propertyKeys"] as? [String] == ["a"])
        #expect(!(try DataTest.parse(GeoJSONAdapter(), Data(nested.utf8))).text.contains("synthetic"))
    }

    @Test func memberOrderDoesNotMatterAndEveryGeometryTypeIsHandled() throws {
        let geometries = """
        {"type":"GeometryCollection","geometries":[
          {"coordinates":[1,2],"type":"Point"},
          {"type":"MultiPoint","coordinates":[[3,4],[5,6]]},
          {"type":"MultiLineString","coordinates":[[[0,0],[1,1]],[[2,2],[3,3],[4,4]]]},
          {"type":"MultiPolygon","coordinates":[[[[0,0],[2,0],[2,2],[0,0]]],[[[5,5],[6,5],[6,6],[5,5]]]]},
          {"type":"Polygon","coordinates":[[[0,0],[9,0],[9,9],[0,0]],[[1,1],[2,1],[2,2],[1,1]]]}
        ]}
        """
        let object = try DataTest.object(try DataTest.parse(GeoJSONAdapter(), Data(geometries.utf8)))
        let types = try #require(object["geometryTypes"] as? [String: Int])
        #expect(types == ["Point": 1, "MultiPoint": 1, "MultiLineString": 1, "Polygon": 1, "MultiPolygon": 1, "GeometryCollection": 1])
        #expect(object["featureCount"] == nil)
        // MultiPoint members and the Point are drawn as points; lines and rings as paths (2 + 2 + 2).
        #expect(try plotPoints(object).count == 3)
        #expect(try plotPaths(object).count == 6)
    }

    @Test func positionsOutsideGeographicRangeAreCountedAndNeverDrawn() throws {
        let projected = #"{"type":"LineString","coordinates":[[500000,4649776],[500100,4649800]]}"#
        let object = try DataTest.object(try DataTest.parse(GeoJSONAdapter(), Data(projected.utf8)))
        #expect(object["coordinateCount"] as? Int == 0 && object["invalidPositions"] as? Int == 2)
        #expect(object["bounds"] == nil && object["plot"] == nil)
        let mixed = #"{"type":"MultiPoint","coordinates":[[10,10],[200,10],[10,100],[11,11,250.5]]}"#
        let mixedObject = try DataTest.object(try DataTest.parse(GeoJSONAdapter(), Data(mixed.utf8)))
        #expect(mixedObject["coordinateCount"] as? Int == 2 && mixedObject["invalidPositions"] as? Int == 2)
        #expect(try plotPoints(mixedObject).count == 2)
    }

    @Test func longLinesAreThinnedToTheDrawingLimitKeepingEndpoints() throws {
        let vertices = (0..<10_000).map { "[\(Double($0) / 100), \(sin(Double($0) / 500) * 40)]" }.joined(separator: ",")
        let data = Data(#"{"type":"LineString","coordinates":[\#(vertices)]}"#.utf8)
        let object = try DataTest.object(try DataTest.parse(GeoJSONAdapter(), data))
        #expect(object["coordinateCount"] as? Int == 10_000)
        let path = try #require(try plotPaths(object).first)
        #expect(path.count <= DataPlotCoding.maximumPositions && path.count > 1_000)
        #expect(path.first?.longitude == 0 && path.last?.longitude == 99.99)
        #expect((object["plot"] as? [String: Any])?["simplified"] as? Bool == true)
    }

    @Test func largeCollectionsAreWalkedWithoutTheNodeBudget() throws {
        // 20,000 features (about 240,000 JSON nodes): far beyond the 20,000-node output budget, which never applied to input.
        let features = (0..<20_000).map { #"{"type":"Feature","properties":{"i":\#($0)},"geometry":{"type":"Point","coordinates":[\#($0 % 180),\#($0 % 90)]}}"# }
        let data = Data((#"{"type":"FeatureCollection","features":["# + features.joined(separator: ",") + "]}").utf8)
        #expect(data.count < 8_388_608)
        let document = try DataTest.parse(GeoJSONAdapter(), data, budget: PreviewBudget(maxInputBytes: 8_388_608, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        #expect(object["featureCount"] as? Int == 20_000 && object["coordinateCount"] as? Int == 20_000)
        #expect(document.text.utf16.count < 250_000)
        #expect(try plotPoints(object).count <= DataPlotCoding.maximumPositions)
    }

    @Test func invalidDocumentsAreMalformed() throws {
        for text in ["", "[]", "{}", #"{"type":"Banana"}"#, #"{"type":"Point""#, #"{"type":7}"#, "null", #"{"features":[]}"#] {
            #expect(throws: PreviewFailure.malformedDocument, "\(text)") { try DataTest.parse(GeoJSONAdapter(), Data(text.utf8)) }
        }
        let deep = String(repeating: "[", count: 80) + "1" + String(repeating: "]", count: 80)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try DataTest.parse(GeoJSONAdapter(), Data(#"{"type":"Point","coordinates":\#(deep)}"#.utf8))
        }
        #expect(throws: PreviewFailure.inputTooLarge) {
            try DataTest.parse(GeoJSONAdapter(), DataFixtures.geoJSON, budget: PreviewBudget(maxInputBytes: 50, maxMilliseconds: 30_000))
        }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.geoJSON
        for length in stride(from: 0, to: data.count, by: 2) {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(GeoJSONAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 0, to: data.count, by: 3) {
            var changed = data
            changed[index] ^= 0x10
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(GeoJSONAdapter(), changed) }
        }
    }

    @Test func cancellationAndDeadlineAreHonored() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try GeoJSONAdapter().parse(FileBytes(data: DataFixtures.geoJSON), context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try GeoJSONAdapter().parse(FileBytes(data: DataFixtures.geoJSON), context: DataTest.context()); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}

@Suite("GPX adapter")
struct GPXAdapterTests {
    @Test func tracksWaypointsDistanceElevationAndTimeAreSummarized() throws {
        let document = try DataTest.parse(GPXAdapter(), DataFixtures.gpx)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "GPX" && object["formatVersion"] as? String == "1.1")
        #expect(object["creator"] as? String == "Synthetic Tracker")
        #expect(object["waypointCount"] as? Int == 1 && object["routeCount"] as? Int == 0)
        #expect(object["trackCount"] as? Int == 1 && object["trackSegmentCount"] as? Int == 1)
        #expect(object["coordinateCount"] as? Int == 4)
        let expected = greatCircle((12.4900, 41.9000), (12.4950, 41.9010)) + greatCircle((12.4950, 41.9010), (12.5000, 41.9030))
        #expect(abs(Double(object["totalDistanceMeters"] as? Int ?? 0) - expected) <= 1)
        #expect(object["elevationMinMeters"] as? Int == 20 && object["elevationMaxMeters"] as? Int == 25)
        #expect(object["timeStart"] as? String == "2026-01-01T08:00:00Z" && object["timeEnd"] as? String == "2026-01-01T08:10:00Z")
        #expect(object["durationSeconds"] as? Int == 600)
        #expect(object["names"] as? [String] == ["Morning loop", "Start", "Loop"])
        #expect(try plotPaths(object).count == 1 && (try plotPoints(object).count) == 1)
        #expect(!document.text.contains(DataFixtures.secret))
    }

    @Test func distanceIsNeverCountedAcrossSegments() throws {
        let gpx = """
        <gpx version="1.1"><trk><trkseg><trkpt lat="0" lon="0"/><trkpt lat="0" lon="1"/></trkseg>
        <trkseg><trkpt lat="10" lon="10"/><trkpt lat="10" lon="11"/></trkseg></trk>
        <rte><rtept lat="20" lon="20"/><rtept lat="21" lon="20"/></rte></gpx>
        """
        let object = try DataTest.object(try DataTest.parse(GPXAdapter(), Data(gpx.utf8)))
        let expected = greatCircle((0, 0), (1, 0)) + greatCircle((10, 10), (11, 10))
        #expect(abs(Double(object["totalDistanceMeters"] as? Int ?? 0) - expected) <= 1)
        #expect(object["trackSegmentCount"] as? Int == 2 && object["routeCount"] as? Int == 1)
        #expect(try plotPaths(object).count == 3)
    }

    @Test func invalidCoordinatesAreCountedAndNeverPlotted() throws {
        let gpx = #"<gpx version="1.1"><wpt lat="95" lon="0"/><wpt lon="5"/><wpt lat="abc" lon="5"/><wpt lat="10" lon="10"/></gpx>"#
        let object = try DataTest.object(try DataTest.parse(GPXAdapter(), Data(gpx.utf8)))
        #expect(object["waypointCount"] as? Int == 4 && object["coordinateCount"] as? Int == 1)
        #expect(object["invalidPositions"] as? Int == 3)
        #expect(try plotPoints(object).count == 1)
    }

    @Test func entityDeclarationsAndForeignRootsAreRefusedBeforeParsing() throws {
        let declared = #"<?xml version="1.0"?><!DOCTYPE gpx [<!ENTITY a "&b;&b;"><!ENTITY b "xxxxxxxxxx">]><gpx><metadata><name>&a;</name></metadata></gpx>"#
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(GPXAdapter(), Data(declared.utf8)) }
        let external = #"<?xml version="1.0"?><!DOCTYPE gpx [<!ENTITY x SYSTEM "file:///etc/hosts">]><gpx><metadata><name>&x;</name></metadata></gpx>"#
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(GPXAdapter(), Data(external.utf8)) }
        let parameter = #"<!DOCTYPE gpx [<!ENTITY % p SYSTEM "http://127.0.0.1:9/x.dtd"> %p;]><gpx/>"#
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(GPXAdapter(), Data(parameter.utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(GPXAdapter(), Data("<html><body/></html>".utf8)) }
        // A DOCTYPE without entity declarations is harmless and is not loaded.
        let plain = #"<?xml version="1.0"?><!DOCTYPE gpx SYSTEM "http://127.0.0.1:9/gpx.dtd"><gpx version="1.1"/>"#
        #expect(try DataTest.object(try DataTest.parse(GPXAdapter(), Data(plain.utf8)))["dataFormat"] as? String == "GPX")
    }

    @Test func malformedOversizedAndDeepDocumentsAreRefused() throws {
        for text in ["", "not xml", "<gpx>", "<gpx></notgpx>", "<gpx><trk></gpx>"] {
            #expect(throws: PreviewFailure.malformedDocument, "\(text)") { try DataTest.parse(GPXAdapter(), Data(text.utf8)) }
        }
        let deep = "<gpx>" + String(repeating: "<a>", count: 200) + String(repeating: "</a>", count: 200) + "</gpx>"
        #expect(throws: PreviewFailure.structureTooDeep) { try DataTest.parse(GPXAdapter(), Data(deep.utf8)) }
        #expect(throws: PreviewFailure.inputTooLarge) {
            try DataTest.parse(GPXAdapter(), DataFixtures.gpx, budget: PreviewBudget(maxInputBytes: 50, maxMilliseconds: 30_000))
        }
    }

    @Test func aLargeTrackIsSummarizedAndThinned() throws {
        let points = (0..<20_000).map { index in
            #"<trkpt lat="\#(41 + Double(index) / 100_000)" lon="\#(12 + Double(index) / 100_000)"><ele>\#(index % 50)</ele><time>2026-01-01T\#(String(format: "%02d", index / 3_600 % 24)):\#(String(format: "%02d", index / 60 % 60)):\#(String(format: "%02d", index % 60))Z</time></trkpt>"#
        }
        let data = Data(("<gpx version=\"1.1\"><trk><trkseg>" + points.joined() + "</trkseg></trk></gpx>").utf8)
        let document = try DataTest.parse(GPXAdapter(), data, budget: PreviewBudget(maxInputBytes: 8_388_608, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        #expect(object["coordinateCount"] as? Int == 20_000 && object["elevationMaxMeters"] as? Int == 49)
        #expect((object["totalDistanceMeters"] as? Int ?? 0) > 20_000)
        #expect((try plotPaths(object).first?.count ?? 0) <= DataPlotCoding.maximumPositions)
        #expect(document.text.utf16.count < 250_000)
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.gpx
        for length in stride(from: 0, to: data.count, by: 3) {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(GPXAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 0, to: data.count, by: 4) {
            var changed = data
            changed[index] ^= 0x08
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(GPXAdapter(), changed) }
        }
    }

    @Test func cancellationAndDeadlineAreHonored() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try GPXAdapter().parse(FileBytes(data: DataFixtures.gpx), context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try GPXAdapter().parse(FileBytes(data: DataFixtures.gpx), context: DataTest.context()); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}

@Suite("KML adapter")
struct KMLAdapterTests {
    @Test func placemarksGeometryExtentLengthAndNamesAreSummarized() throws {
        let document = try DataTest.parse(KMLAdapter(), DataFixtures.kml)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "KML")
        #expect(object["placemarkCount"] as? Int == 2 && object["folderCount"] as? Int == 1)
        #expect(object["geometryTypes"] as? [String: Int] == ["Point": 1, "LineString": 1])
        #expect(object["coordinateCount"] as? Int == 4)
        let expected = greatCircle((12.49, 41.89), (12.50, 41.90)) + greatCircle((12.50, 41.90), (12.51, 41.91))
        #expect(abs(Double(object["totalDistanceMeters"] as? Int ?? 0) - expected) <= 1)
        #expect(object["elevationMinMeters"] as? Int == 0 && object["elevationMaxMeters"] as? Int == 21)
        #expect(object["names"] as? [String] == ["Synthetic places", "Pin", "Walks", "Walk"])
        let bounds = try #require(object["bounds"] as? [String: String])
        #expect(bounds == ["west": "12.490000", "south": "41.890000", "east": "12.510000", "north": "41.910000"])
        #expect(try plotPaths(object).count == 1 && (try plotPoints(object).count) == 1)
        // Descriptions never enter the document.
        #expect(!document.text.contains(DataFixtures.secret))
    }

    @Test func polygonsTracksMultiGeometryAndTimesAreRead() throws {
        let kml = """
        <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2"><Document>
        <Placemark><MultiGeometry>
          <Point><coordinates>1,1</coordinates></Point>
          <Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 4,0 4,4 0,0</coordinates></LinearRing></outerBoundaryIs></Polygon>
        </MultiGeometry></Placemark>
        <Placemark><LinearRing><coordinates>8,8 9,8 9,9 8,8</coordinates></LinearRing></Placemark>
        <Placemark><TimeSpan><begin>2026-01-01T00:00:00Z</begin><end>2026-01-02T00:00:00Z</end></TimeSpan>
          <gx:Track><when>2026-01-01T06:00:00Z</when><when>2026-01-01T07:00:00Z</when>
          <gx:coord>20 20 5</gx:coord><gx:coord>21 20 9</gx:coord></gx:Track></Placemark>
        <NetworkLink><Link><href>http://127.0.0.1:9/never-fetched.kml</href></Link></NetworkLink>
        </Document></kml>
        """
        let object = try DataTest.object(try DataTest.parse(KMLAdapter(), Data(kml.utf8)))
        #expect(object["geometryTypes"] as? [String: Int] == ["Point": 1, "Polygon": 1, "LinearRing": 1, "MultiGeometry": 1, "Track": 1])
        #expect(object["placemarkCount"] as? Int == 3)
        #expect(object["coordinateCount"] as? Int == 4 + 4 + 2 + 1)
        #expect(object["elevationMinMeters"] as? Int == 5 && object["elevationMaxMeters"] as? Int == 9)
        #expect(object["timeStart"] as? String == "2026-01-01T00:00:00Z" && object["timeEnd"] as? String == "2026-01-02T00:00:00Z")
        // Only the track is a line: rings are boundaries and add no length.
        #expect(abs(Double(object["totalDistanceMeters"] as? Int ?? 0) - greatCircle((20, 20), (21, 20))) <= 1)
        #expect(try plotPaths(object).count == 3 && (try plotPoints(object).count) == 1)
    }

    @Test func rejectsEntitiesForeignRootsAndMalformedCoordinates() throws {
        let entity = #"<!DOCTYPE kml [<!ENTITY x SYSTEM "file:///etc/hosts">]><kml><Document><name>&x;</name></Document></kml>"#
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(KMLAdapter(), Data(entity.utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(KMLAdapter(), Data("<svg/>".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(KMLAdapter(), Data()) }
        let broken = "<kml><Placemark><Point><coordinates>1,1 abc,2 3 200,5 4,4</coordinates></Point></Placemark></kml>"
        let object = try DataTest.object(try DataTest.parse(KMLAdapter(), Data(broken.utf8)))
        #expect(object["coordinateCount"] as? Int == 2 && object["invalidPositions"] as? Int == 3)
    }

    @Test func kmzPackagesAreSummarizedLikeTheirKMLDocument() throws {
        let plain = try DataTest.object(try DataTest.parse(KMLAdapter(), DataFixtures.kml))
        let packaged = try DataTest.object(try DataTest.parse(KMLAdapter(), DataFixtures.kmz))
        #expect(NSDictionary(dictionary: packaged).isEqual(to: plain))
        // Without doc.kml the first root-level KML is used; nested documents and other members are not.
        let kml = Array(DataFixtures.kml)
        let renamed = DataTest.zip([("icon.png", [1, 2, 3], false), ("places.kml", kml, true)])
        #expect(try DataTest.object(try DataTest.parse(KMLAdapter(), renamed))["placemarkCount"] as? Int == 2)
        let both = DataTest.zip([("other.kml", Array("<kml/>".utf8), false), ("doc.kml", kml, true)])
        #expect(try DataTest.object(try DataTest.parse(KMLAdapter(), both))["placemarkCount"] as? Int == 2)
        let nested = DataTest.zip([("folder/doc.kml", kml, true), ("readme.txt", [1], false)])
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(KMLAdapter(), nested) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(KMLAdapter(), DataTest.zip([])) }
    }

    @Test func kmzMembersAreBoundedCheckedAndNeverExtractedBeyondTheBudget() throws {
        // A deflated member that would expand beyond the input budget is refused by its declared size.
        let bloated = Array("<kml>".utf8) + [UInt8](repeating: 0x20, count: 3_000_000) + Array("</kml>".utf8)
        #expect(throws: PreviewFailure.inputTooLarge) { try DataTest.parse(KMLAdapter(), DataTest.zip([("doc.kml", bloated, true)])) }
        // A damaged member fails its CRC instead of being parsed.
        var damaged = DataFixtures.kmz
        let marker = try #require(damaged.range(of: Data([0x50, 0x4B, 0x03, 0x04])))
        damaged[marker.lowerBound + 30 + 7 + 5] ^= 0xFF
        #expect(throws: PreviewFailure.self) { try DataTest.parse(KMLAdapter(), damaged) }
        // An encrypted member fails as encrypted content.
        let encrypted = DataTest.zip([("doc.kml", Array(DataFixtures.kml), false)], flags: 1)
        #expect(throws: PreviewFailure.encryptedContent) { try DataTest.parse(KMLAdapter(), encrypted) }
        // Not an archive after all: a truncated signature is just malformed XML.
        #expect(throws: PreviewFailure.self) { try DataTest.parse(KMLAdapter(), Data([0x50, 0x4B, 0x03, 0x04, 0, 0])) }
    }

    @Test func everyKMZTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.kmz
        for length in stride(from: 0, to: data.count, by: 2) {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(KMLAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 0, to: data.count, by: 3) {
            var changed = data
            changed[index] ^= 0x01
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(KMLAdapter(), changed) }
        }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        let data = DataFixtures.kml
        for length in stride(from: 0, to: data.count, by: 3) {
            DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(KMLAdapter(), data.prefix(length)) }
        }
        for index in stride(from: 0, to: data.count, by: 4) {
            var changed = data
            changed[index] ^= 0x04
            DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(KMLAdapter(), changed) }
        }
    }

    @Test func cancellationAndDeadlineAreHonored() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try KMLAdapter().parse(FileBytes(data: DataFixtures.kml), context: DataTest.context(PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try KMLAdapter().parse(FileBytes(data: DataFixtures.kml), context: DataTest.context()); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}
