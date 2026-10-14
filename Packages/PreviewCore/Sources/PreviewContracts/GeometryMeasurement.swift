import Foundation
import simd

/// Measures the decoded tessellation: surface area, enclosed volume and connected bodies.
///
/// The result describes the displayed surface mesh, not the exact B-rep, so it is an approximation and
/// carries the same chord-error as the picture (typically a fraction of a percent on curved parts).
/// Everything is derived from the numeric mesh; no source bytes, kernel objects or document text are involved.
///
/// Scale: the importer centres the mesh and scales it so the longest extent of `bounds` becomes two
/// (`p_normalized = (p_mm - centre) * 2 / longestExtent`). Hence `p_mm = p_normalized * longestExtent / 2 + centre`.
/// Area and volume are computed in normalized space and multiplied by `scale²` and `scale³`, where
/// `scale = longestExtent / 2`. The centre drops out because a closed surface's volume is translation invariant.
///
/// `package` access: the CAD importer and the STL, OBJ, PLY and 3MF readers live in different targets of this
/// package and share this one implementation, and nothing outside the package needs it.
package enum GeometryMeasurer {
    /// Welding cell in normalized units (2^-17, about 7.6e-6 of the half-extent). The importer tessellates
    /// faces separately but shares edge nodes, so seam vertices normally agree to the last float bit; the
    /// cell only absorbs rounding noise and is far below the tessellation's own minimum feature size.
    private static let weldCellsPerUnit: Float = 131_072
    private static let weldBias: Int64 = 1 << 20
    private static let coordinateBits: UInt64 = 21
    /// Weld IDs must fit 21 bits to pack two of them with a direction bit into one edge key.
    private static let maximumVertices = 1 << 21
    private static let checkpointInterval = 4_096

    /// Returns `nil` only when the numeric result cannot be represented; cancellation and the request
    /// deadline propagate as thrown errors. Work is linear apart from two in-place sorts.
    package static func measure(_ mesh: PreviewMesh, context: RequestContext) throws -> GeometryMeasurements? {
        try context.checkpoint()
        let positions = mesh.positions, indices = mesh.indices
        let extents = mesh.bounds.maximum - mesh.bounds.minimum
        let scale = max(extents.x, extents.y, extents.z) / 2
        guard scale > 0, scale.isFinite, positions.count <= maximumVertices else { return nil }

        let weld = try weldedIdentifiers(of: positions, context: context)
        var components = DisjointSets(count: weld.count)

        // One pass over triangles: area, signed volume, connectivity and directed-edge records.
        let triangleCount = indices.count / 3
        var area = 0.0, signedVolume = 0.0
        var edges = [UInt64]()
        edges.reserveCapacity(triangleCount * 3)
        for triangle in 0..<triangleCount {
            if triangle.isMultiple(of: checkpointInterval) { try context.checkpoint() }
            let base = triangle * 3
            let corners = (Int(indices[base]), Int(indices[base + 1]), Int(indices[base + 2]))
            let p0 = SIMD3<Double>(positions[corners.0])
            let p1 = SIMD3<Double>(positions[corners.1])
            let p2 = SIMD3<Double>(positions[corners.2])
            area += 0.5 * length(cross(p1 - p0, p2 - p0))
            signedVolume += dot(p0, cross(p1, p2)) / 6
            let a = weld[corners.0], b = weld[corners.1], c = weld[corners.2]
            components.union(a, b)
            components.union(b, c)
            // A triangle collapsed by welding covers no surface; its edges would only cancel each other.
            if a == b || b == c || a == c { continue }
            edges.append(edgeKey(a, b)); edges.append(edgeKey(b, c)); edges.append(edgeKey(c, a))
        }
        try context.checkpoint()
        let isClosed = try hasBalancedEdges(&edges, context: context)
        let bodies = try bodyCount(indices: indices, weld: weld, components: &components, context: context)
        let volume = isClosed ? abs(signedVolume) * scale * scale * scale : nil
        return GeometryMeasurements(surfaceAreaSquareMillimetres: area * scale * scale,
                                    volumeCubicMillimetres: volume, bodyCount: bodies)
    }

    /// Assigns one identifier per distinct quantized position. Sorting packed `(key, vertex)` records keeps
    /// peak memory near 24 bytes per vertex and avoids a large hash table.
    private static func weldedIdentifiers(of positions: [SIMD3<Float>], context: RequestContext) throws -> [UInt32] {
        struct Record { var key: UInt64; var vertex: UInt32 }
        var records = [Record]()
        records.reserveCapacity(positions.count)
        for (index, position) in positions.enumerated() {
            if index.isMultiple(of: checkpointInterval) { try context.checkpoint() }
            records.append(Record(key: weldKey(position), vertex: UInt32(index)))
        }
        try context.checkpoint()
        // The standard sort is not cooperatively interruptible; it is bounded by the vertex cap.
        records.sort { $0.key < $1.key }
        var identifiers = [UInt32](repeating: 0, count: positions.count)
        var next: UInt32 = 0
        var previous: UInt64?
        for (offset, record) in records.enumerated() {
            if offset.isMultiple(of: checkpointInterval) { try context.checkpoint() }
            if previous != record.key {
                if previous != nil { next += 1 }
                previous = record.key
            }
            identifiers[Int(record.vertex)] = next
        }
        return identifiers
    }

    private static func weldKey(_ position: SIMD3<Float>) -> UInt64 {
        func cell(_ value: Float) -> UInt64 {
            // PreviewMesh bounds positions to 1.01, so this stays far inside the 21-bit field.
            let quantized = Int64((value * weldCellsPerUnit).rounded()) + weldBias
            return UInt64(clamping: min(max(quantized, 0), (1 << Int64(coordinateBits)) - 1))
        }
        return cell(position.x) << (2 * coordinateBits) | cell(position.y) << coordinateBits | cell(position.z)
    }

    /// Undirected edge in the high bits and traversal direction in bit 0, so a sort groups both directions.
    private static func edgeKey(_ from: UInt32, _ to: UInt32) -> UInt64 {
        from < to ? UInt64(from) << 22 | UInt64(to) << 1 : UInt64(to) << 22 | UInt64(from) << 1 | 1
    }

    /// A closed, consistently oriented surface traverses every edge as often forward as backward. This is
    /// the exact "every edge used twice in opposite directions" rule for manifold edges and also accepts
    /// bodies that touch along an edge. Open boundaries and flipped faces leave an imbalance.
    private static func hasBalancedEdges(_ edges: inout [UInt64], context: RequestContext) throws -> Bool {
        guard !edges.isEmpty else { return false }
        edges.sort()
        var balance = 0
        var group = edges[0] >> 1
        for (offset, key) in edges.enumerated() {
            if offset.isMultiple(of: checkpointInterval) { try context.checkpoint() }
            if key >> 1 != group {
                if balance != 0 { return false }
                group = key >> 1; balance = 0
            }
            balance += key & 1 == 0 ? 1 : -1
        }
        return balance == 0
    }

    private static func bodyCount(indices: [UInt32], weld: [UInt32], components: inout DisjointSets,
                                  context: RequestContext) throws -> Int {
        var seen = [Bool](repeating: false, count: weld.count)
        var count = 0
        for triangle in 0..<(indices.count / 3) {
            if triangle.isMultiple(of: checkpointInterval) { try context.checkpoint() }
            let root = Int(components.find(weld[Int(indices[triangle * 3])]))
            if !seen[root] { seen[root] = true; count += 1 }
        }
        return max(count, 1)
    }
}

/// Union-find over welded vertices with path halving and union by index; amortized near-constant time.
private struct DisjointSets {
    private var parent: [UInt32]
    /// Welded identifiers are dense and never exceed the vertex count.
    init(count: Int) { parent = (0..<count).map { UInt32($0) } }

    mutating func find(_ element: UInt32) -> UInt32 {
        var node = element
        while parent[Int(node)] != node {
            parent[Int(node)] = parent[Int(parent[Int(node)])]
            node = parent[Int(node)]
        }
        return node
    }

    mutating func union(_ first: UInt32, _ second: UInt32) {
        let a = find(first), b = find(second)
        guard a != b else { return }
        if a < b { parent[Int(b)] = a } else { parent[Int(a)] = b }
    }
}
