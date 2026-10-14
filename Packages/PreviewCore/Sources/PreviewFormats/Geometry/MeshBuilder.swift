import Foundation
import PreviewContracts
import simd

/// Triangles that share vertices, in millimetres, before normalization and shading normals.
struct TriangleMesh {
    var positions: [SIMD3<Double>] = []
    /// Three source-vertex indices per triangle. Readers validate them; the builder validates again.
    var indices: [UInt32] = []
    /// Source polygons: an OBJ quad is one face and two triangles.
    var faceCount = 0
    /// Where the unit of the positions comes from. Positions are millimetres either way; a reader says here whether
    /// the file declared the unit, so a format without one is never presented as millimetres (decision 027, Q-11).
    var unitProvenance = GeometryUnitProvenance.undeclared
}

/// Merges bit-identical positions while a triangle soup (STL) is read, so the shared vertices that
/// smooth shading needs exist before the builder runs. Negative zero merges with zero.
struct VertexWelder {
    private struct Key: Hashable {
        let x: UInt64, y: UInt64, z: UInt64
    }
    private var table: [Key: UInt32] = [:]
    private(set) var positions: [SIMD3<Double>] = []

    init(expectedVertices: Int) {
        table.reserveCapacity(min(expectedVertices, GeometryLimits.maximumVertices))
        positions.reserveCapacity(min(expectedVertices, GeometryLimits.maximumVertices))
    }

    mutating func index(for position: SIMD3<Double>) throws -> UInt32 {
        let key = Key(x: position.x == 0 ? 0 : position.x.bitPattern,
                      y: position.y == 0 ? 0 : position.y.bitPattern,
                      z: position.z == 0 ? 0 : position.z.bitPattern)
        if let existing = table[key] { return existing }
        guard positions.count < GeometryLimits.maximumVertices else { throw PreviewFailure.geometryTooComplex }
        let index = UInt32(positions.count)
        table[key] = index
        positions.append(position)
        return index
    }
}

/// Turns validated indexed triangles into the contract's mesh: drops degenerate triangles, centers
/// and scales the positions to an extent of two, and computes shading normals. A corner shares its
/// vertex's smooth normal only with neighbouring faces within the crease angle, so flat models keep
/// their edges and curved ones shade smoothly. Output is bounded by the request's allowance. The finished mesh
/// carries its measurements, the same ones the CAD importer attaches.
enum MeshBuilder {
    /// Cosine of the 45 degree crease angle.
    static let creaseCosine: Float = 0.707_106_8
    /// Up to this many incident faces, each corner is compared with every neighbour. Beyond it the
    /// corner is compared with the vertex's average normal, keeping the work linear.
    static let exactSmoothingDegree = 32

    static func makePreviewMesh(_ source: TriangleMesh, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        let allowance = MeshAllowance(context)
        let vertexCount = source.positions.count
        guard vertexCount > 0, !source.indices.isEmpty, source.indices.count.isMultiple(of: 3) else {
            throw PreviewFailure.malformedDocument
        }
        guard vertexCount <= allowance.vertices else { throw allowance.vertexOverflow }
        guard source.indices.count / 3 <= allowance.triangles else { throw allowance.triangleOverflow }
        let limit = GeometryLimits.maximumCoordinateMagnitude
        for (offset, position) in source.positions.enumerated() {
            if offset & 0xFFFF == 0 { try context.checkpoint() }
            // NaN and infinities fail every comparison.
            guard abs(position.x) <= limit, abs(position.y) <= limit, abs(position.z) <= limit else {
                throw PreviewFailure.malformedDocument
            }
        }

        // Keep non-degenerate triangles and measure what they cover.
        var kept = [UInt32]()
        kept.reserveCapacity(source.indices.count)
        var minimum = SIMD3<Double>(repeating: .infinity)
        var maximum = SIMD3<Double>(repeating: -.infinity)
        let triangleCount = source.indices.count / 3
        for triangle in 0..<triangleCount {
            if triangle & 0x3FFF == 0 { try context.checkpoint() }
            let first = source.indices[3 * triangle], second = source.indices[3 * triangle + 1]
            let third = source.indices[3 * triangle + 2]
            guard Int(first) < vertexCount, Int(second) < vertexCount, Int(third) < vertexCount else {
                throw PreviewFailure.malformedDocument
            }
            let a = source.positions[Int(first)], b = source.positions[Int(second)], c = source.positions[Int(third)]
            let normal = cross(b - a, c - a)
            let lengthSquared = dot(normal, normal)
            guard lengthSquared > 0, lengthSquared.isFinite else { continue }
            kept.append(first); kept.append(second); kept.append(third)
            minimum = pointwiseMin(minimum, pointwiseMin(a, pointwiseMin(b, c)))
            maximum = pointwiseMax(maximum, pointwiseMax(a, pointwiseMax(b, c)))
        }
        let keptCount = kept.count / 3
        guard keptCount > 0 else { throw PreviewFailure.malformedDocument }
        let extents = maximum - minimum
        let longest = max(extents.x, extents.y, extents.z)
        guard longest > 0, longest.isFinite else { throw PreviewFailure.malformedDocument }
        let center = (minimum + maximum) / 2
        let scale = 2 / longest

        // Face normals in normalized space: the cross product's length is twice the face area.
        var faceCross = [SIMD3<Float>]()
        var faceUnit = [SIMD3<Float>]()
        faceCross.reserveCapacity(keptCount)
        faceUnit.reserveCapacity(keptCount)
        for k in 0..<keptCount {
            if k & 0x3FFF == 0 { try context.checkpoint() }
            let a = (source.positions[Int(kept[3 * k])] - center) * scale
            let b = (source.positions[Int(kept[3 * k + 1])] - center) * scale
            let c = (source.positions[Int(kept[3 * k + 2])] - center) * scale
            let normal = cross(b - a, c - a)
            let length = (dot(normal, normal)).squareRoot()
            faceCross.append(SIMD3<Float>(normal))
            faceUnit.append(length > 0 ? SIMD3<Float>(normal / length) : SIMD3<Float>(0, 0, 1))
        }

        // Compressed incidence lists: the faces around each vertex.
        var offsets = [UInt32](repeating: 0, count: vertexCount + 1)
        for corner in kept { offsets[Int(corner) + 1] += 1 }
        for v in 0..<vertexCount { offsets[v + 1] += offsets[v] }
        var cursor = offsets
        var incident = [UInt32](repeating: 0, count: kept.count)
        for k in 0..<keptCount {
            for corner in 0..<3 {
                let v = Int(kept[3 * k + corner])
                incident[Int(cursor[v])] = UInt32(k)
                cursor[v] += 1
            }
        }

        var outPositions = [SIMD3<Float>]()
        var outNormals = [SIMD3<Float>]()
        var outIndices = [UInt32](repeating: 0, count: kept.count)
        let indexBytes = kept.count * 4
        let maximumOutputVertices = min(allowance.vertices, max(0, allowance.outputBytes - 72 - indexBytes) / 24)
        guard maximumOutputVertices > 0 else { throw allowance.outputOverflow }
        var seen: [(normal: SIMD3<Float>, index: UInt32)] = []
        for v in 0..<vertexCount {
            let start = Int(offsets[v]), end = Int(offsets[v + 1])
            guard end > start else { continue }
            if v & 0x3FFF == 0 { try context.checkpoint() }
            let local = ((source.positions[v] - center) * scale)
            let position = SIMD3<Float>(pointwiseMin(pointwiseMax(local, SIMD3<Double>(repeating: -1)), SIMD3<Double>(repeating: 1)))
            let degree = end - start
            let exact = degree <= exactSmoothingDegree
            var average: SIMD3<Float>?
            if !exact {
                var sum = SIMD3<Float>.zero
                for slot in start..<end { sum += faceCross[Int(incident[slot])] }
                average = normalized(sum)
            }
            seen.removeAll(keepingCapacity: true)
            for slot in start..<end {
                let k = Int(incident[slot])
                let unit = faceUnit[k]
                let normal: SIMD3<Float>
                if exact {
                    var sum = SIMD3<Float>.zero
                    for other in start..<end {
                        let neighbour = Int(incident[other])
                        if dot(unit, faceUnit[neighbour]) >= creaseCosine { sum += faceCross[neighbour] }
                    }
                    normal = normalized(sum) ?? unit
                } else if let average, dot(unit, average) >= creaseCosine {
                    normal = average
                } else {
                    normal = unit
                }
                let outIndex: UInt32
                // Sharing is only searched where the work is bounded: every corner of a low-degree
                // vertex, and the one smooth normal of a high-degree vertex.
                if (exact || normal == average), let existing = seen.first(where: { $0.normal == normal }) {
                    outIndex = existing.index
                } else {
                    outIndex = UInt32(outPositions.count)
                    outPositions.append(position)
                    outNormals.append(normal)
                    if exact || normal == average { seen.append((normal, outIndex)) }
                }
                let base = 3 * k
                let corner = kept[base] == UInt32(v) ? 0 : (kept[base + 1] == UInt32(v) ? 1 : 2)
                outIndices[base + corner] = outIndex
            }
            guard outPositions.count <= maximumOutputVertices else { throw allowance.outputOverflow }
        }
        guard 72 + outPositions.count * 24 + indexBytes <= allowance.outputBytes else { throw allowance.outputOverflow }
        // The face count stops at the contract's cap; the mesh says so, because a saturated number must not read as exact.
        let sourceFaces = max(1, min(source.faceCount, keptCount))
        let mesh = try PreviewMesh(positions: outPositions, normals: outNormals, indices: outIndices,
                                   bounds: GeometryBounds(minimum: minimum, maximum: maximum),
                                   faceCount: min(sourceFaces, GeometryLimits.maximumFaces),
                                   unitProvenance: source.unitProvenance,
                                   faceCountIsCapped: sourceFaces > GeometryLimits.maximumFaces)
        return try measured(mesh, context: context)
    }

    /// Attaches the shared measurements (Mesh Print Check, decision 029) in the unit provenance the reader recorded:
    /// a 3MF's declared unit, `.assumedMillimetres` for a 3MF without one, `.undeclared` for STL, OBJ and PLY. The
    /// measurer reads the mesh just built, checks the request's checkpoint in its loops and uses the request's
    /// deadline, so cancellation propagates like any other stage. It returns nothing only for a mesh whose scale or
    /// weld cannot be represented, and the preview is then shown without the facts.
    private static func measured(_ mesh: PreviewMesh, context: RequestContext) throws -> PreviewMesh {
        guard let measurements = try GeometryMeasurer.measure(mesh, context: context) else { return mesh }
        return mesh.attaching(measurements: measurements.declaring(unitProvenance: mesh.unitProvenance), headerFacts: nil)
    }

    private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = dot(vector, vector).squareRoot()
        return length > 1e-20 && length.isFinite ? vector / length : nil
    }
}
