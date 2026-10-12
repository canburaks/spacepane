import Foundation
import PreviewContracts

/// GPX 1.0/1.1 GPS exchange files: waypoint, route and track counts, extent, track length,
/// elevation range, time span and a drawable outline.
///
/// Parsing is event-driven through `GeoXML` (no entity resolution, no tree). Track distance is the
/// haversine sum along consecutive valid points of each segment, never across segments. Extension
/// elements, descriptions, comments, links and sensor data are ignored. Point names are listed
/// (the first 20 names in document order); nothing else free-form is shown.
public struct GPXAdapter: BinaryFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let scanner = Scanner(context: context)
        try GeoXML.run(input.data, delegate: scanner, context: context)
        guard scanner.sawRoot else { throw PreviewFailure.malformedDocument }
        return try scanner.document(context: context)
    }

    private final class Scanner: GeoXMLDelegate {
        var sawRoot = false
        var version: String?
        var creator: String?
        var bounds = GeoBounds()
        var plot = GeoPlot()
        var ranges = GeoRanges()
        var waypoints = 0, routes = 0, tracks = 0, segments = 0
        var distance = 0.0
        var names: [String] = []
        private var pointKind: String?
        private var latitude: Double?
        private var longitude: Double?
        private var segment: [GeoPosition] = []
        private var route: [GeoPosition] = []
        private var lastTrackPosition: GeoPosition?

        private static let pointNames: Set<String> = ["wpt", "rtept", "trkpt"]
        private static let namedParents: Set<String> = ["metadata", "trk", "rte", "wpt"]
        private static let maximumNames = 20

        override func elementStarted(_ name: String, qualifiedName: String, attributes: [String: String]) {
            if stack.count == 1 {
                // The document element must be `gpx`; anything else is not a GPX file.
                guard name == "gpx" else { fail(PreviewFailure.malformedDocument); return }
                sawRoot = true
                version = attributes["version"]
                creator = attributes["creator"]
                return
            }
            switch name {
            case "wpt", "rtept", "trkpt":
                pointKind = name
                latitude = attributes["lat"].flatMap { Double($0) }
                longitude = attributes["lon"].flatMap { Double($0) }
                if name == "wpt" { waypoints += 1 }
            case "rte": routes += 1; route = []
            case "trk": tracks += 1
            case "trkseg": segments += 1; segment = []; lastTrackPosition = nil
            case "ele", "time":
                if let parent = ancestor(1), Self.pointNames.contains(parent) { captureText(limit: 64) }
            case "name":
                if let parent = ancestor(1), Self.namedParents.contains(parent), names.count < Self.maximumNames {
                    captureText(limit: 200)
                }
            default: break
            }
        }

        override func elementEnded(_ name: String, qualifiedName: String, text: String?) {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "ele":
                if let trimmed, let meters = Double(trimmed) { ranges.addElevation(meters) }
            case "time":
                if let trimmed, !trimmed.isEmpty, let parent = ancestor(1), Self.pointNames.contains(parent) {
                    ranges.addTime(trimmed)
                }
            case "name":
                if let trimmed, !trimmed.isEmpty, names.count < Self.maximumNames { names.append(trimmed) }
            case "wpt", "rtept", "trkpt":
                finishPoint(name)
            case "trkseg":
                plot.addPath(segment)
                segment = []
            case "rte":
                plot.addPath(route)
                route = []
            default: break
            }
        }

        private func finishPoint(_ name: String) {
            defer { pointKind = nil; latitude = nil; longitude = nil }
            guard let latitude, let longitude else {
                // A point without usable coordinates is counted as invalid, not guessed.
                _ = bounds.add(longitude: .nan, latitude: .nan)
                return
            }
            guard bounds.add(longitude: longitude, latitude: latitude) else { return }
            let position: GeoPosition = (longitude, latitude)
            switch name {
            case "wpt": plot.addPoint(position)
            case "rtept": route.append(position)
            default:
                if let previous = lastTrackPosition { distance += GeoDistance.haversine(previous, position) }
                lastTrackPosition = position
                segment.append(position)
            }
        }

        func document(context: RequestContext) throws -> ParsedTextDocument {
            var members: [(String, SummaryValue)] = [("dataFormat", .string("GPX"))]
            if let version = DataDocument.string(version, clippedTo: 16) { members.append(("formatVersion", version)) }
            if let creator = DataDocument.string(creator) { members.append(("creator", creator)) }
            members.append(("waypointCount", .integer(waypoints)))
            members.append(("routeCount", .integer(routes)))
            members.append(("trackCount", .integer(tracks)))
            members.append(("trackSegmentCount", .integer(segments)))
            members.append(("coordinateCount", .integer(bounds.positionCount)))
            if bounds.invalidCount > 0 { members.append(("invalidPositions", .integer(bounds.invalidCount))) }
            members += ranges.members(distanceMeters: distance)
            if let summary = bounds.summary { members.append(("bounds", summary)) }
            if !names.isEmpty { members.append(("names", .array(names.map { .string(DataTable.clip($0, to: 100).0) }))) }
            if let summary = plot.summary { members.append((DataSummaryKeys.plot, summary)) }
            return try DataDocument.make(members, context: context)
        }
    }
}
