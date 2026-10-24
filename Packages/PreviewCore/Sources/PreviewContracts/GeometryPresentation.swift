import Foundation

/// Numeric-only geometry crosses the importer boundary. Document labels, paths,
/// annotations, materials and external-resource references are deliberately absent.
public enum GeometryLimits {
    public static let maximumInputBytes = 16 * 1_024 * 1_024
    public static let maximumSerializedBytes = 32 * 1_024 * 1_024
    public static let maximumVertices = 1_500_000
    public static let maximumIndices = 1_500_000
    public static let maximumFaces = 100_000
    public static let maximumCoordinateMagnitude: Double = 1e12
    public static let requestBudget = PreviewBudget(maxInputBytes: maximumInputBytes,
        maxOutputUTF8Bytes: maximumSerializedBytes, maxMilliseconds: 20_000)
}

public struct GeometryBounds: Equatable, Sendable {
    /// Importers normalize physical coordinates to millimetres. Bounds are approximate.
    public let minimum: SIMD3<Double>
    public let maximum: SIMD3<Double>
    public init(minimum: SIMD3<Double>, maximum: SIMD3<Double>) {
        self.minimum = minimum; self.maximum = maximum
    }
}

/// A unit of length a model file can declare. Only known units are typed, so no file-supplied text is shown.
public enum GeometryLengthUnit: String, Equatable, Sendable, CaseIterable {
    case micrometre, millimetre, centimetre, metre, inch, foot
    /// Millimetres per unit, for converting declared extents before display.
    public var millimetres: Double {
        switch self {
        case .micrometre: 0.001
        case .millimetre: 1
        case .centimetre: 10
        case .metre: 1_000
        case .inch: 25.4
        case .foot: 304.8
        }
    }
}

/// Where a mesh's unit of length comes from. Extents are stored in millimetres; this says whether the file
/// declared that unit, whether the importer assumed it, or whether the format carries none (decision 027, Q-11).
public enum GeometryUnitProvenance: Equatable, Sendable {
    /// The file declares its unit.
    case declared(GeometryLengthUnit)
    /// The format carries no unit and millimetres were assumed.
    case assumedMillimetres
    /// Nothing is known about the unit; the presentation says so instead of showing a number as millimetres.
    case undeclared
}

/// Approximate values derived from the displayed tessellation, not certified engineering data.
/// The importer's numeric wire format is unchanged: these are computed from the decoded mesh.
public struct GeometryMeasurements: Equatable, Sendable {
    /// Sum of tessellated triangle areas in square millimetres.
    public let surfaceAreaSquareMillimetres: Double
    /// Enclosed volume in cubic millimetres. `nil` unless the surface mesh is closed and consistently oriented.
    public let volumeCubicMillimetres: Double?
    /// Connected components of the welded surface mesh. At least one.
    public let bodyCount: Int
    /// Whether the millimetre values rest on a declared unit, an assumption or nothing.
    public let unitProvenance: GeometryUnitProvenance
    /// Open (boundary) edges: welded edges that exactly one triangle uses, so the surface has a gap there.
    /// Zero for a watertight surface (Mesh Print Check, decision 029). A count of the displayed tessellation.
    public let openEdgeCount: Int
    /// Edges that more than two triangles share, which no solid's surface can have (decision 029). They make a
    /// slicer's idea of inside and outside ambiguous; bodies that touch along a face or an edge produce them too.
    public let nonManifoldEdgeCount: Int

    /// Fails for non-finite or negative values so a malformed measurement can never be displayed.
    public init?(surfaceAreaSquareMillimetres: Double, volumeCubicMillimetres: Double?, bodyCount: Int,
                 unitProvenance: GeometryUnitProvenance = .undeclared,
                 openEdgeCount: Int = 0, nonManifoldEdgeCount: Int = 0) {
        guard surfaceAreaSquareMillimetres.isFinite, surfaceAreaSquareMillimetres >= 0, bodyCount >= 1,
              volumeCubicMillimetres.map({ $0.isFinite && $0 >= 0 }) ?? true,
              openEdgeCount >= 0, nonManifoldEdgeCount >= 0 else { return nil }
        self.surfaceAreaSquareMillimetres = surfaceAreaSquareMillimetres
        self.volumeCubicMillimetres = volumeCubicMillimetres
        self.bodyCount = bodyCount
        self.unitProvenance = unitProvenance
        self.openEdgeCount = openEdgeCount
        self.nonManifoldEdgeCount = nonManifoldEdgeCount
    }

    /// The same values with another unit provenance. They were validated when this value was made, so the
    /// result cannot fail; an importer that learns the unit after measuring uses this instead of measuring again.
    public func declaring(unitProvenance: GeometryUnitProvenance) -> GeometryMeasurements {
        GeometryMeasurements(validated: self, unitProvenance: unitProvenance)
    }

    private init(validated source: GeometryMeasurements, unitProvenance: GeometryUnitProvenance) {
        surfaceAreaSquareMillimetres = source.surfaceAreaSquareMillimetres
        volumeCubicMillimetres = source.volumeCubicMillimetres
        bodyCount = source.bodyCount
        self.unitProvenance = unitProvenance
        openEdgeCount = source.openEdgeCount
        nonManifoldEdgeCount = source.nonManifoldEdgeCount
    }
}

public struct PreviewMesh: Equatable, Sendable {
    /// Positions are centered and normalized to an extent of two for stable GPU precision.
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
    public let bounds: GeometryBounds
    public let faceCount: Int
    /// Optional facts attached by an adapter after import; they never influence rendering or validation.
    public let measurements: GeometryMeasurements?
    /// Where the unit of `bounds` comes from. Every importer states it; a mesh built without saying so is
    /// `.undeclared`, so no number is shown as millimetres on the strength of a default (decision 027, Q-11).
    public let unitProvenance: GeometryUnitProvenance
    /// Whether `faceCount` stopped at `GeometryLimits.maximumFaces` although the model has more faces, so the
    /// presentation can say "at least" instead of showing a saturated number as exact.
    public let faceCountIsCapped: Bool
    /// Canonical numeric payload cost, independent of platform SIMD padding.
    public var outputByteCount: Int { 72 + positions.count * 24 + indices.count * 4 }

    /// A mesh beyond the contract's vertex, index, face or serialized-size ceilings fails with
    /// `PreviewFailure.geometryTooComplex`, so the message can name the geometry limit instead of a file size.
    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32],
                bounds: GeometryBounds, faceCount: Int,
                measurements: GeometryMeasurements? = nil,
                unitProvenance: GeometryUnitProvenance = .undeclared, faceCountIsCapped: Bool = false) throws {
        guard !positions.isEmpty, normals.count == positions.count,
              !indices.isEmpty, indices.count.isMultiple(of: 3), faceCount > 0 else {
            throw PreviewFailure.malformedDocument
        }
        guard positions.count <= GeometryLimits.maximumVertices,
              indices.count <= GeometryLimits.maximumIndices, faceCount <= GeometryLimits.maximumFaces,
              positions.count * 24 + indices.count * 4 + 72 <= GeometryLimits.maximumSerializedBytes else {
            throw PreviewFailure.geometryTooComplex
        }
        // A count is capped only where the cap is reached.
        guard !faceCountIsCapped || faceCount == GeometryLimits.maximumFaces else { throw PreviewFailure.malformedDocument }
        for axis in 0..<3 {
            guard bounds.minimum[axis].isFinite, bounds.maximum[axis].isFinite,
                  abs(bounds.minimum[axis]) <= GeometryLimits.maximumCoordinateMagnitude,
                  abs(bounds.maximum[axis]) <= GeometryLimits.maximumCoordinateMagnitude,
                  bounds.minimum[axis] <= bounds.maximum[axis] else { throw PreviewFailure.malformedDocument }
        }
        guard bounds.minimum != bounds.maximum else { throw PreviewFailure.malformedDocument }
        for index in positions.indices {
            let position = positions[index], normal = normals[index]
            for axis in 0..<3 {
                guard position[axis].isFinite, abs(position[axis]) <= 1.01,
                      normal[axis].isFinite else { throw PreviewFailure.malformedDocument }
            }
            let lengthSquared = normal.x * normal.x + normal.y * normal.y + normal.z * normal.z
            guard (0.25...2.25).contains(lengthSquared) else { throw PreviewFailure.malformedDocument }
        }
        guard indices.allSatisfy({ $0 < positions.count }) else { throw PreviewFailure.malformedDocument }
        self.positions = positions; self.normals = normals; self.indices = indices
        self.bounds = bounds; self.faceCount = faceCount
        self.measurements = measurements
        self.unitProvenance = unitProvenance; self.faceCountIsCapped = faceCountIsCapped
    }

    /// Returns the same validated geometry with facts attached. Arrays are shared, not revalidated or copied.
    /// `unitProvenance` replaces the mesh's own only when given, for an importer that learns the unit after decoding.
    public func attaching(measurements: GeometryMeasurements?,
                          unitProvenance: GeometryUnitProvenance? = nil) -> PreviewMesh {
        PreviewMesh(validated: self, measurements: measurements,
                    unitProvenance: unitProvenance ?? self.unitProvenance)
    }

    private init(validated source: PreviewMesh, measurements: GeometryMeasurements?,
                 unitProvenance: GeometryUnitProvenance) {
        positions = source.positions; normals = source.normals; indices = source.indices
        bounds = source.bounds; faceCount = source.faceCount
        self.measurements = measurements
        self.unitProvenance = unitProvenance; faceCountIsCapped = source.faceCountIsCapped
    }
}

public struct GeometryPresentation: Equatable, Sendable {
    public let id: UUID
    public let formatID: FormatID
    public let mesh: PreviewMesh
    public let byteCount: Int
    public let facts: PresentationFacts
    public init(formatID: FormatID, mesh: PreviewMesh, byteCount: Int, facts: PresentationFacts = .none) {
        id = UUID(); self.formatID = formatID; self.mesh = mesh; self.byteCount = byteCount
        self.facts = facts
    }
    // Immutable request identity avoids walking mesh arrays on every view update.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

public protocol GeometryFormatAdapter: Sendable {
    func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh
}
