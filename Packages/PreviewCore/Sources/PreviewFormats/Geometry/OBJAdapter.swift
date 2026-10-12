import Foundation
import PreviewContracts

/// Wavefront OBJ geometry: `v` positions and `f` faces in every reference form (`v`, `v/vt`, `v//vn`,
/// `v/vt/vn`), including negative (relative) indices. Polygons are fan-triangulated from their first
/// vertex, which is exact for convex faces. Texture coordinates, normals, groups, objects, smoothing
/// groups, free-form geometry, lines and points are skipped; `mtllib` and `usemtl` are never
/// followed, so a material library or texture is never opened. OBJ has no units, so coordinates are
/// taken as millimetres and the mesh says its unit is `.undeclared` (see `STLAdapter`).
public struct OBJAdapter: GeometryFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        let allowance = MeshAllowance(context)
        guard input.data.count <= allowance.inputBytes else { throw PreviewFailure.inputTooLarge }
        let mesh = try input.data.withUnsafeBytes { raw in
            try Self.read(raw.bindMemory(to: UInt8.self), allowance: allowance, context: context)
        }
        return try MeshBuilder.makePreviewMesh(mesh, context: context)
    }

    private static let vertexKeyword: UInt8 = 0x76 // v
    private static let faceKeyword: UInt8 = 0x66 // f
    private static let slash: UInt8 = 0x2F

    private static func read(_ bytes: UnsafeBufferPointer<UInt8>, allowance: MeshAllowance,
                             context: RequestContext) throws -> TriangleMesh {
        var scanner = ASCIIScanner(bytes)
        var positions = [SIMD3<Double>]()
        var indices = [UInt32]()
        var polygon = [Int]()
        var faceCount = 0
        var highestReference = -1
        var lines = 0
        while !scanner.isAtEnd {
            lines += 1
            if lines & 0x3FFF == 0 { try context.checkpoint() }
            guard let keyword = scanner.tokenOnLine() else { scanner.skipToNextLine(); continue }
            if keyword.count == 1, bytes[keyword.lowerBound] == vertexKeyword {
                guard positions.count < allowance.vertices else { throw allowance.vertexOverflow }
                var position = SIMD3<Double>()
                for axis in 0..<3 {
                    // A fourth weight or vertex colours may follow; they are ignored with the rest of the line.
                    guard let token = scanner.tokenOnLine(), let value = scanner.double(token) else {
                        throw PreviewFailure.malformedDocument
                    }
                    position[axis] = value
                }
                positions.append(position)
            } else if keyword.count == 1, bytes[keyword.lowerBound] == faceKeyword {
                polygon.removeAll(keepingCapacity: true)
                while let token = scanner.tokenOnLine() {
                    // The vertex reference is the integer before the first slash.
                    var end = token.lowerBound
                    while end < token.upperBound, bytes[end] != slash { end += 1 }
                    guard let reference = scanner.integer(token.lowerBound..<end), reference != 0 else {
                        throw PreviewFailure.malformedDocument
                    }
                    // Negative references count back from the last vertex defined so far.
                    let resolved = reference > 0 ? reference - 1 : positions.count + reference
                    guard resolved >= 0, resolved < GeometryLimits.maximumVertices else { throw PreviewFailure.malformedDocument }
                    polygon.append(resolved)
                    highestReference = max(highestReference, resolved)
                    guard polygon.count <= allowance.triangles + 2 else { throw allowance.triangleOverflow }
                }
                guard polygon.count >= 3 else { throw PreviewFailure.malformedDocument }
                guard indices.count / 3 + polygon.count - 2 <= allowance.triangles else { throw allowance.triangleOverflow }
                faceCount += 1
                for k in 1..<(polygon.count - 1) {
                    indices.append(UInt32(polygon[0]))
                    indices.append(UInt32(polygon[k]))
                    indices.append(UInt32(polygon[k + 1]))
                }
            }
            scanner.skipToNextLine()
        }
        guard !positions.isEmpty else { throw PreviewFailure.malformedDocument }
        // Forward references to vertices defined later in the file are accepted; unknown ones are not.
        guard highestReference < positions.count else { throw PreviewFailure.malformedDocument }
        // Valid geometry with no faces (points, lines, curves) has nothing this viewer draws.
        guard faceCount > 0 else { throw PreviewFailure.unsupportedFormat }
        return TriangleMesh(positions: positions, indices: indices, faceCount: faceCount, unitProvenance: .undeclared)
    }
}
