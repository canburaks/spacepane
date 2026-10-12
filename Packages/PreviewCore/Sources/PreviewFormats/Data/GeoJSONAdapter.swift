import Foundation
import PreviewContracts

/// GeoJSON (RFC 7946): feature and geometry counts, property names, extent and a drawable outline.
///
/// The document is walked with the cursor reader, so a collection with hundreds of thousands of
/// vertices is never materialized and the shared node budget does not apply to the input. Property
/// values are skipped without being decoded: only the names of the properties are listed. Positions
/// outside longitude ±180 / latitude ±90 are counted and ignored. At most `GeoPlot.retainedLimit`
/// vertices are kept for the Plot view, thinned further when written.
public struct GeoJSONAdapter: BinaryFormatAdapter {
    public init() {}

    private static let geometryTypes = ["Point", "MultiPoint", "LineString", "MultiLineString",
                                        "Polygon", "MultiPolygon", "GeometryCollection"]
    private static let maximumPropertyKeys = 100

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let scanner = Scanner(context: context)
        var reader = DataJSONReader(bytes: [UInt8](input.data), context: context)
        var root: Parsed?
        try reader.document { reader in
            guard try reader.peekKind() == .object else { throw PreviewFailure.malformedDocument }
            root = try scanner.object(&reader, depth: 1)
        }
        guard let root, root.isGeoJSON else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return try scanner.document(root: root, context: context)
    }

    // MARK: Scanning

    /// What one object turned out to be.
    private struct Parsed {
        var type: String?
        var sawFeatures = false
        var sawGeometry = false

        var isGeoJSON: Bool {
            guard let type else { return false }
            return type == "FeatureCollection" || type == "Feature" || GeoJSONAdapter.geometryTypes.contains(type)
        }
    }

    /// The nesting of a `coordinates` member: positions grouped into chains (arrays of positions).
    private struct Coordinates {
        var chains: [[GeoPosition]] = []
        var point: GeoPosition?
    }

    /// Mutable state of one scan. A class, so the recursive walk and its closures share it without
    /// threading `inout` through every level; it never outlives the request.
    private final class Scanner {
        let context: RequestContext
        var bounds = GeoBounds()
        var plot = GeoPlot()
        var types = GeoTypeCounts(order: GeoJSONAdapter.geometryTypes)
        var featureCount = 0
        var featuresWithoutGeometry = 0
        var propertyKeys: [String] = []
        var propertyKeySet: Set<String> = []
        var propertyKeysCut = false
        private var steps = 0

        init(context: RequestContext) { self.context = context }

        func object(_ reader: inout DataJSONReader, depth: Int) throws -> Parsed {
            var parsed = Parsed()
            var coordinates: Coordinates?
            var hasGeometryMember = false
            var geometryIsNull = false
            try reader.forEachMember(depth: depth) { key, reader in
                try tick()
                switch key {
                case "type":
                    if try reader.peekKind() == .string { parsed.type = try reader.string(maximumBytes: 64).text }
                case "features":
                    guard try reader.peekKind() == .array else { return }
                    parsed.sawFeatures = true
                    try reader.forEachElement(depth: depth + 1) { _, reader in
                        guard try reader.peekKind() == .object else { return }
                        _ = try self.object(&reader, depth: depth + 2)
                    }
                case "geometry":
                    hasGeometryMember = true
                    switch try reader.peekKind() {
                    case .object: parsed.sawGeometry = true; _ = try self.object(&reader, depth: depth + 1)
                    case .null: geometryIsNull = true; try reader.null()
                    default: return
                    }
                case "geometries":
                    guard try reader.peekKind() == .array else { return }
                    try reader.forEachElement(depth: depth + 1) { _, reader in
                        guard try reader.peekKind() == .object else { return }
                        _ = try self.object(&reader, depth: depth + 2)
                    }
                case "coordinates":
                    guard try reader.peekKind() == .array else { return }
                    var collected = Coordinates()
                    let result = try self.coordinates(&reader, depth: depth + 1, into: &collected)
                    if result.height == 0 { collected.point = result.position }
                    coordinates = collected
                case "properties":
                    guard try reader.peekKind() == .object else { return }
                    try reader.forEachMember(depth: depth + 1) { name, _ in self.noteProperty(name) }
                default: return
                }
            }
            switch parsed.type {
            case "Feature":
                featureCount += 1
                if !hasGeometryMember || geometryIsNull { featuresWithoutGeometry += 1 }
            case let name? where GeoJSONAdapter.geometryTypes.contains(name):
                types.add(name)
                if let coordinates { finish(name, coordinates) }
            default: break
            }
            return parsed
        }

        // MARK: Coordinates

        /// Reads a nested `coordinates` array. Height 0 is a position, 1 an array of positions, and
        /// so on; arrays of positions are recorded as chains. A malformed or mixed array records nothing.
        private func coordinates(_ reader: inout DataJSONReader, depth: Int, into collected: inout Coordinates)
            throws -> (height: Int, position: GeoPosition?) {
            var numbers: [Double] = []
            var childHeight: Int?
            var chain: [GeoPosition] = []
            var mixed = false
            try reader.forEachElement(depth: depth) { _, reader in
                try tick()
                switch try reader.peekKind() {
                case .number:
                    if numbers.count < 3 { numbers.append(try reader.double()) } else { _ = try reader.numberSpan() }
                case .array:
                    let child = try self.coordinates(&reader, depth: depth + 1, into: &collected)
                    if let childHeight, childHeight != child.height { mixed = true }
                    childHeight = child.height
                    if child.height == 0, let position = child.position { chain.append(position) }
                default:
                    mixed = true
                }
            }
            if !numbers.isEmpty {
                guard childHeight == nil, numbers.count >= 2 else { return (0, nil) }
                let valid = bounds.add(longitude: numbers[0], latitude: numbers[1])
                return (0, valid ? (numbers[0], numbers[1]) : nil)
            }
            guard let childHeight, !mixed else { return (1, nil) }
            if childHeight == 0 {
                if !chain.isEmpty { collected.chains.append(chain) }
                return (1, nil)
            }
            return (childHeight + 1, nil)
        }

        private func finish(_ type: String, _ coordinates: Coordinates) {
            switch type {
            case "Point":
                if let point = coordinates.point { plot.addPoint(point) }
            case "MultiPoint":
                for chain in coordinates.chains { for point in chain { plot.addPoint(point) } }
            case "LineString", "MultiLineString", "Polygon", "MultiPolygon":
                for chain in coordinates.chains { plot.addPath(chain) }
            default: break
            }
        }

        private func noteProperty(_ name: String) {
            guard !propertyKeySet.contains(name) else { return }
            if propertyKeys.count >= GeoJSONAdapter.maximumPropertyKeys { propertyKeysCut = true; return }
            propertyKeySet.insert(name)
            propertyKeys.append(name)
        }

        private func tick() throws {
            steps += 1
            if steps.isMultiple(of: 1_024) { try context.checkpoint() }
        }

        // MARK: Presentation

        func document(root: Parsed, context: RequestContext) throws -> ParsedTextDocument {
            var members: [(String, SummaryValue)] = [("dataFormat", .string("GeoJSON"))]
            if root.type == "FeatureCollection" || root.type == "Feature" {
                members.append(("featureCount", .integer(featureCount)))
                if featuresWithoutGeometry > 0 { members.append(("featuresWithoutGeometry", .integer(featuresWithoutGeometry))) }
            }
            if !types.isEmpty { members.append(("geometryTypes", types.summary)) }
            if !propertyKeys.isEmpty {
                members.append(("propertyKeys", .array(propertyKeys.map { .string(DataTable.clip($0, to: 100).0) })))
                if propertyKeysCut { members.append(("partial", .boolean(true))) }
            }
            members.append(("coordinateCount", .integer(bounds.positionCount)))
            if bounds.invalidCount > 0 { members.append(("invalidPositions", .integer(bounds.invalidCount))) }
            if let summary = bounds.summary { members.append(("bounds", summary)) }
            if let summary = plot.summary { members.append((DataSummaryKeys.plot, summary)) }
            return try DataDocument.make(members, context: context)
        }
    }
}
