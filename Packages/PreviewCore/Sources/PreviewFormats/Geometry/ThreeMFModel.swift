import Foundation
import PreviewContracts

/// A 3MF affine transform: twelve numbers `m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32` in the
/// specification's row-vector convention, `p' = [x y z 1] * M`. The last row is the translation.
struct ThreeMFTransform: Equatable {
    var row0: SIMD3<Double>
    var row1: SIMD3<Double>
    var row2: SIMD3<Double>
    var translation: SIMD3<Double>

    static let identity = ThreeMFTransform(row0: SIMD3(1, 0, 0), row1: SIMD3(0, 1, 0), row2: SIMD3(0, 0, 1), translation: .zero)

    init(row0: SIMD3<Double>, row1: SIMD3<Double>, row2: SIMD3<Double>, translation: SIMD3<Double>) {
        self.row0 = row0; self.row1 = row1; self.row2 = row2; self.translation = translation
    }

    /// Parses exactly twelve finite numbers separated by whitespace.
    init?(parsing text: String) {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        guard parts.count == 12 else { return nil }
        var values = [Double]()
        values.reserveCapacity(12)
        for part in parts {
            guard let value = ThreeMFNumber.double(String(part)), abs(value) <= 1e30 else { return nil }
            values.append(value)
        }
        self.init(row0: SIMD3(values[0], values[1], values[2]), row1: SIMD3(values[3], values[4], values[5]),
                  row2: SIMD3(values[6], values[7], values[8]), translation: SIMD3(values[9], values[10], values[11]))
    }

    func apply(_ point: SIMD3<Double>) -> SIMD3<Double> {
        point.x * row0 + point.y * row1 + point.z * row2 + translation
    }

    private func applyLinear(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        vector.x * row0 + vector.y * row1 + vector.z * row2
    }

    /// The transform that applies `self` first and `outer` second.
    func then(_ outer: ThreeMFTransform) -> ThreeMFTransform {
        ThreeMFTransform(row0: outer.applyLinear(row0), row1: outer.applyLinear(row1),
                         row2: outer.applyLinear(row2), translation: outer.apply(translation))
    }
}

enum ThreeMFNumber {
    static func double(_ string: String) -> Double? {
        if let value = parse(string) { return value }
        // XML attribute values may carry surrounding whitespace.
        return parse(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func integer(_ string: String) -> Int? {
        var copy = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy.withUTF8 { ASCIIScanner.parseInteger($0, 0..<$0.count) }
    }

    private static func parse(_ string: String) -> Double? {
        var copy = string
        return copy.withUTF8 { ASCIIScanner.parseDouble($0, 0..<$0.count) }
    }
}

/// The 3MF `unit` attribute. Coordinates are converted to millimetres, which the shared geometry
/// contract uses for every importer.
enum ThreeMFUnit: String {
    case micron, millimeter, centimeter, inch, foot, meter

    var millimetres: Double {
        switch self {
        case .micron: 0.001
        case .millimeter: 1
        case .centimeter: 10
        case .inch: 25.4
        case .foot: 304.8
        case .meter: 1_000
        }
    }

    /// The contract's name for the same unit, so the presentation can show the unit the file declared.
    var lengthUnit: GeometryLengthUnit {
        switch self {
        case .micron: .micrometre
        case .millimeter: .millimetre
        case .centimeter: .centimetre
        case .inch: .inch
        case .foot: .foot
        case .meter: .metre
        }
    }
}

/// Reads one model part: its resources (meshes and component lists) and build items. Geometry stays
/// in this part's own tables; the assembler instantiates objects with their transforms afterwards.
/// All ceilings are checked as each element arrives, so nothing is allocated for an oversized file.
final class ThreeMFModelParser: BoundedXMLDelegate {
    struct Component {
        let objectID: Int
        let path: String?
        let transform: ThreeMFTransform
    }
    struct ObjectRecord {
        var type: String
        /// Range of `vertices` and of triangle numbers in `triangles` that belong to this object.
        var vertexRange = 0..<0
        var triangleRange = 0..<0
        var components: [Component] = []
    }
    struct Item {
        let objectID: Int
        let path: String?
        let transform: ThreeMFTransform
    }

    static let coreNamespace = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    static let productionNamespace = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"

    private(set) var unit: String?
    private(set) var sawModel = false
    private(set) var objects: [Int: ObjectRecord] = [:]
    private(set) var objectOrder: [Int] = []
    private(set) var items: [Item] = []
    private(set) var vertices: [SIMD3<Double>] = []
    /// Three object-local vertex indices per triangle.
    private(set) var triangles: [UInt32] = []

    private enum Scope { case model, resources, object, mesh, vertices, triangles, components, build, other }
    private var scopes: [Scope] = []
    private var currentID: Int?
    private var meshStart = (vertices: 0, triangles: 0)
    private let remainingVertices: Int
    private let remainingTriangles: Int
    /// What exceeding `triangleAllowance` means: the geometry ceiling or the caller's lower output budget.
    private let triangleOverflow: PreviewFailure

    init(context: RequestContext, nodeAllowance: Int, vertexAllowance: Int, triangleAllowance: Int,
         triangleOverflow: PreviewFailure = .outputTooLarge) {
        remainingVertices = vertexAllowance
        remainingTriangles = triangleAllowance
        self.triangleOverflow = triangleOverflow
        super.init(context: context, nodeAllowance: nodeAllowance)
    }

    var triangleCount: Int { triangles.count / 3 }

    override func startElement(_ name: String, namespace: String, attributes: [String: String]) throws {
        let parent = scopes.last
        // Elements of extensions (colours, slicer data) and everything inside them is inert.
        guard parent != .other, namespace.isEmpty || namespace == Self.coreNamespace else {
            scopes.append(.other)
            return
        }
        switch (parent, name) {
        case (nil, "model"):
            sawModel = true
            unit = attributes["unit"]
            scopes.append(.model)
        case (.model, "resources"):
            scopes.append(.resources)
        case (.model, "build"):
            scopes.append(.build)
        case (.resources, "object"):
            guard let identifier = attributes["id"].flatMap(ThreeMFNumber.integer), identifier > 0,
                  objects[identifier] == nil else { throw PreviewFailure.malformedDocument }
            objects[identifier] = ObjectRecord(type: attributes["type"] ?? "model")
            objectOrder.append(identifier)
            currentID = identifier
            scopes.append(.object)
        case (.object, "mesh"):
            guard let currentID, objects[currentID]?.triangleRange.isEmpty == true,
                  objects[currentID]?.vertexRange.isEmpty == true else { throw PreviewFailure.malformedDocument }
            meshStart = (vertices.count, triangleCount)
            scopes.append(.mesh)
        case (.mesh, "vertices"):
            scopes.append(.vertices)
        case (.mesh, "triangles"):
            scopes.append(.triangles)
        case (.vertices, "vertex"):
            guard vertices.count < remainingVertices else { throw PreviewFailure.geometryTooComplex }
            guard let x = attributes["x"].flatMap(ThreeMFNumber.double), let y = attributes["y"].flatMap(ThreeMFNumber.double),
                  let z = attributes["z"].flatMap(ThreeMFNumber.double) else { throw PreviewFailure.malformedDocument }
            vertices.append(SIMD3(x, y, z))
            scopes.append(.other)
        case (.triangles, "triangle"):
            guard triangleCount < remainingTriangles else { throw triangleOverflow }
            guard let first = attributes["v1"].flatMap(ThreeMFNumber.integer), let second = attributes["v2"].flatMap(ThreeMFNumber.integer),
                  let third = attributes["v3"].flatMap(ThreeMFNumber.integer),
                  first >= 0, second >= 0, third >= 0,
                  first < GeometryLimits.maximumVertices, second < GeometryLimits.maximumVertices,
                  third < GeometryLimits.maximumVertices else { throw PreviewFailure.malformedDocument }
            triangles.append(UInt32(first)); triangles.append(UInt32(second)); triangles.append(UInt32(third))
            scopes.append(.other)
        case (.object, "components"):
            scopes.append(.components)
        case (.components, "component"):
            guard let currentID, let identifier = attributes["objectid"].flatMap(ThreeMFNumber.integer), identifier > 0 else {
                throw PreviewFailure.malformedDocument
            }
            objects[currentID]?.components.append(Component(objectID: identifier,
                path: attribute("path", namespace: Self.productionNamespace, in: attributes),
                transform: try transform(attributes)))
            scopes.append(.other)
        case (.build, "item"):
            guard let identifier = attributes["objectid"].flatMap(ThreeMFNumber.integer), identifier > 0 else {
                throw PreviewFailure.malformedDocument
            }
            items.append(Item(objectID: identifier, path: attribute("path", namespace: Self.productionNamespace, in: attributes),
                              transform: try transform(attributes)))
            scopes.append(.other)
        default:
            scopes.append(.other)
        }
    }

    override func endElement(_ name: String, namespace: String) throws {
        guard let scope = scopes.popLast() else { throw PreviewFailure.malformedDocument }
        switch scope {
        case .mesh:
            guard let currentID else { throw PreviewFailure.malformedDocument }
            let vertexRange = meshStart.vertices..<vertices.count
            let triangleRange = meshStart.triangles..<triangleCount
            // Every index must name a vertex of this object's own mesh.
            let limit = UInt32(vertexRange.count)
            for slot in (triangleRange.lowerBound * 3)..<(triangleRange.upperBound * 3) {
                if slot & 0xFFFF == 0 { try context.checkpoint() }
                guard triangles[slot] < limit else { throw PreviewFailure.malformedDocument }
            }
            objects[currentID]?.vertexRange = vertexRange
            objects[currentID]?.triangleRange = triangleRange
        case .object:
            currentID = nil
        default:
            break
        }
    }

    private func transform(_ attributes: [String: String]) throws -> ThreeMFTransform {
        guard let text = attributes["transform"] else { return .identity }
        guard let parsed = ThreeMFTransform(parsing: text) else { throw PreviewFailure.malformedDocument }
        return parsed
    }
}

/// Finds the model part named by `_rels/.rels` (relationship type ending `/3dmodel`).
final class ThreeMFRelationshipsParser: BoundedXMLDelegate {
    private(set) var modelTarget: String?

    override func startElement(_ name: String, namespace: String, attributes: [String: String]) throws {
        guard name == "Relationship", modelTarget == nil, let type = attributes["Type"], type.hasSuffix("/3dmodel"),
              let target = attributes["Target"] else { return }
        modelTarget = target
    }
}
