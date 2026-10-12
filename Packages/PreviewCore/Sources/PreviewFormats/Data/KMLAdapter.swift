import Foundation
import PreviewContracts

/// KML 2.x (OGC): placemark and folder counts, geometry counts, extent, line length, elevation
/// range, time span and a drawable outline.
///
/// Parsing is event-driven through `GeoXML`. Only geometry, coordinate, name and time elements
/// are read. Descriptions, styles, balloons, icons, `NetworkLink` and every referenced resource
/// are ignored: nothing is fetched. Line length is the haversine sum over `LineString` and
/// `gx:Track` paths. Altitudes and times from coordinates, `when`, `begin` and `end` feed the
/// ranges. A KMZ package is a ZIP archive: its `doc.kml` (or its first root-level `.kml`) is read
/// through the shared bounded ZIP reader, CRC-checked and parsed in memory; images, icons and every
/// other member are ignored and nothing is extracted to disk.
public struct KMLAdapter: BinaryFormatAdapter {
    public init() {}

    private static let geometryNames = ["Point", "LineString", "LinearRing", "Polygon", "MultiGeometry", "Track"]
    /// `PK\u{3}\u{4}`: a ZIP local file header, so a KMZ package rather than a KML document.
    private static let zipSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        if input.data.starts(with: Self.zipSignature) {
            return try Self.parse(data: try Self.document(inPackage: input.data, context: context), context: context)
        }
        return try Self.parse(data: input.data, context: context)
    }

    /// The package's KML document: `doc.kml` when present, otherwise the first `.kml` at the archive root.
    static func document(inPackage data: Data, context: RequestContext) throws -> Data {
        let source = DataByteSource(data)
        // Encrypted members are listed so the failure names them (`encryptedContent`), not the archive.
        let archive = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list)
        let roots = archive.entries.filter {
            $0.kind == "file" && !$0.path.contains("/") && $0.path.lowercased().hasSuffix(".kml")
        }
        guard let entry = roots.first(where: { $0.path.lowercased() == "doc.kml" }) ?? roots.first else {
            throw PreviewFailure.malformedDocument
        }
        return try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: context.budget.maxInputBytes, context: context)
    }

    /// Parses one KML document held in memory.
    static func parse(data: Data, context: RequestContext) throws -> ParsedTextDocument {
        let scanner = Scanner(context: context)
        try GeoXML.run(data, delegate: scanner, context: context)
        guard scanner.sawRoot else { throw PreviewFailure.malformedDocument }
        return try scanner.document(context: context)
    }

    private final class Scanner: GeoXMLDelegate {
        var sawRoot = false
        var bounds = GeoBounds()
        var plot = GeoPlot()
        var ranges = GeoRanges()
        var types = GeoTypeCounts(order: KMLAdapter.geometryNames)
        var placemarks = 0, folders = 0
        var distance = 0.0
        var names: [String] = []
        private var track: [GeoPosition] = []
        private let coordinateLimit: Int

        private static let maximumNames = 20
        private static let namedParents: Set<String> = ["Document", "Folder", "Placemark"]
        private static let timeElements: Set<String> = ["when", "begin", "end"]

        override init(context: RequestContext) {
            coordinateLimit = context.budget.maxInputBytes
            super.init(context: context)
        }

        override func elementStarted(_ name: String, qualifiedName: String, attributes: [String: String]) {
            if stack.count == 1 {
                // `kml` is the document element; a bare `Document` or `Placemark` is also accepted.
                guard ["kml", "Document", "Placemark", "Folder"].contains(name) else {
                    fail(PreviewFailure.malformedDocument)
                    return
                }
                sawRoot = true
            }
            switch name {
            case "Placemark": placemarks += 1
            case "Folder": folders += 1
            case "Point", "LineString", "Polygon", "MultiGeometry": types.add(name)
            case "LinearRing":
                // Rings of a polygon are part of that polygon, not geometries of their own.
                if !stack.contains("Polygon") { types.add(name) }
            case "Track":
                if qualifiedName.hasSuffix(":Track") || qualifiedName == "Track" { types.add("Track"); track = [] }
            case "coordinates": captureText(limit: coordinateLimit)
            case "coord":
                if ancestor(1) == "Track" { captureText(limit: 128) }
            case "name":
                if let parent = ancestor(1), Self.namedParents.contains(parent), names.count < Self.maximumNames {
                    captureText(limit: 200)
                }
            default:
                if Self.timeElements.contains(name) { captureText(limit: 64) }
            }
        }

        override func elementEnded(_ name: String, qualifiedName: String, text: String?) {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "coordinates":
                guard let trimmed, let parent = ancestor(1) else { return }
                finishCoordinates(trimmed, parent: parent)
            case "coord":
                guard let trimmed, ancestor(1) == "Track" else { return }
                // `gx:coord` separates longitude, latitude and altitude with spaces.
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).compactMap { Double($0) }
                if parts.count >= 2, bounds.add(longitude: parts[0], latitude: parts[1]) {
                    track.append((parts[0], parts[1]))
                    if parts.count >= 3 { ranges.addElevation(parts[2]) }
                }
            case "Track":
                guard qualifiedName.hasSuffix(":Track") || qualifiedName == "Track" else { return }
                addPath(track)
                track = []
            case "name":
                if let trimmed, !trimmed.isEmpty, names.count < Self.maximumNames { names.append(trimmed) }
            default:
                if Self.timeElements.contains(name), let trimmed, !trimmed.isEmpty { ranges.addTime(trimmed) }
            }
        }

        /// Parses `lon,lat[,alt]` tuples separated by whitespace.
        private func finishCoordinates(_ text: String, parent: String) {
            var path: [GeoPosition] = []
            var count = 0
            for tuple in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
                count += 1
                if count.isMultiple(of: 1_024) {
                    do { try context.checkpoint() } catch { fail(error); return }
                }
                let parts = tuple.split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) }
                guard parts.count >= 2 else { _ = bounds.add(longitude: .nan, latitude: .nan); continue }
                guard bounds.add(longitude: parts[0], latitude: parts[1]) else { continue }
                if parts.count >= 3 { ranges.addElevation(parts[2]) }
                let position: GeoPosition = (parts[0], parts[1])
                if parent == "Point" { plot.addPoint(position) } else { path.append(position) }
            }
            if parent == "LineString" || parent == "LinearRing" { addPath(path, isLine: parent == "LineString") }
        }

        private func addPath(_ path: [GeoPosition], isLine: Bool = true) {
            plot.addPath(path)
            // Only open lines and tracks contribute to length; polygon rings are boundaries.
            guard isLine, path.count >= 2 else { return }
            for index in 1..<path.count { distance += GeoDistance.haversine(path[index - 1], path[index]) }
        }

        func document(context: RequestContext) throws -> ParsedTextDocument {
            var members: [(String, SummaryValue)] = [("dataFormat", .string("KML"))]
            members.append(("placemarkCount", .integer(placemarks)))
            members.append(("folderCount", .integer(folders)))
            if !types.isEmpty { members.append(("geometryTypes", types.summary)) }
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
