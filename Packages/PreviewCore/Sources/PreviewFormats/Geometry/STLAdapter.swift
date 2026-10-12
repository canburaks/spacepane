import Foundation
import PreviewContracts

/// Binary and ASCII STL. A file is binary when its size equals `84 + 50 * triangleCount` for the
/// count in its header, whatever its 80-byte header says: many binary exporters start the header
/// with "solid". Otherwise a leading `solid` keyword selects the ASCII grammar. Facet normals are
/// ignored; shading normals come from the vertices. STL carries no units, so coordinates are taken
/// as millimetres, the convention of 3D printing, and the mesh says its unit is `.undeclared`: the
/// presentation shows plain numbers and "unit not declared" rather than a unit nothing in the file states.
public struct STLAdapter: GeometryFormatAdapter {
    public init() {}

    private static let headerBytes = 80
    private static let triangleBytes = 50

    public func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        let allowance = MeshAllowance(context)
        guard input.data.count <= allowance.inputBytes else { throw PreviewFailure.inputTooLarge }
        let mesh = try input.data.withUnsafeBytes { raw -> TriangleMesh in
            if let declared = Self.binaryTriangleCount(raw) {
                return try Self.readBinary(raw, triangles: declared, allowance: allowance, context: context)
            }
            let bytes = raw.bindMemory(to: UInt8.self)
            if Self.startsWithSolid(bytes) {
                return try Self.readASCII(bytes, allowance: allowance, context: context)
            }
            throw PreviewFailure.malformedDocument
        }
        return try MeshBuilder.makePreviewMesh(mesh, context: context)
    }

    /// The header's triangle count when it agrees exactly with the file size.
    private static func binaryTriangleCount(_ raw: UnsafeRawBufferPointer) -> Int? {
        guard raw.count >= headerBytes + 4 else { return nil }
        let declared = UInt64(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: headerBytes, as: UInt32.self)))
        guard UInt64(headerBytes + 4) + declared * UInt64(triangleBytes) == UInt64(raw.count) else { return nil }
        return Int(declared)
    }

    private static func startsWithSolid(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var scanner = ASCIIScanner(bytes)
        // A UTF-8 byte order mark may precede the keyword.
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            scanner = ASCIIScanner(bytes, position: 3)
        }
        guard let first = scanner.token() else { return false }
        return scanner.matches(first, "solid")
    }

    private static func readBinary(_ raw: UnsafeRawBufferPointer, triangles: Int, allowance: MeshAllowance,
                                   context: RequestContext) throws -> TriangleMesh {
        guard triangles <= allowance.triangles else { throw allowance.triangleOverflow }
        var welder = VertexWelder(expectedVertices: triangles)
        var indices = [UInt32]()
        indices.reserveCapacity(triangles * 3)
        for triangle in 0..<triangles {
            if triangle & 0xFFF == 0 { try context.checkpoint() }
            // Each record: 12-byte normal (ignored), three vertices, 2 attribute bytes (ignored).
            let record = headerBytes + 4 + triangle * triangleBytes + 12
            for corner in 0..<3 {
                let offset = record + corner * 12
                let x = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                let y = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)))
                let z = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self)))
                guard x.isFinite, y.isFinite, z.isFinite else { throw PreviewFailure.malformedDocument }
                indices.append(try welder.index(for: SIMD3<Double>(Double(x), Double(y), Double(z))))
            }
        }
        return TriangleMesh(positions: welder.positions, indices: indices, faceCount: triangles, unitProvenance: .undeclared)
    }

    private static func readASCII(_ bytes: UnsafeBufferPointer<UInt8>, allowance: MeshAllowance,
                                  context: RequestContext) throws -> TriangleMesh {
        var scanner = ASCIIScanner(bytes, position: bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0)
        var welder = VertexWelder(expectedVertices: min(bytes.count / 64, GeometryLimits.maximumVertices))
        var indices = [UInt32]()
        var facets = 0

        func expect(_ keyword: StaticString) throws {
            guard let token = scanner.token(), scanner.matches(token, keyword) else { throw PreviewFailure.malformedDocument }
        }
        func number() throws -> Double {
            guard let token = scanner.token(), let value = scanner.double(token) else { throw PreviewFailure.malformedDocument }
            return value
        }

        guard let first = scanner.token(), scanner.matches(first, "solid") else { throw PreviewFailure.malformedDocument }
        scanner.skipToNextLine()
        while let token = scanner.token() {
            if facets & 0x3FF == 0 { try context.checkpoint() }
            if scanner.matches(token, "facet") {
                guard facets < allowance.triangles else { throw allowance.triangleOverflow }
                // The facet normal is skipped without interpretation: exporters write it as nan or zero.
                try expect("normal")
                for _ in 0..<3 { guard scanner.token() != nil else { throw PreviewFailure.malformedDocument } }
                try expect("outer")
                try expect("loop")
                for _ in 0..<3 {
                    try expect("vertex")
                    let x = try number(), y = try number(), z = try number()
                    indices.append(try welder.index(for: SIMD3<Double>(x, y, z)))
                }
                try expect("endloop")
                try expect("endfacet")
                facets += 1
            } else if scanner.matches(token, "endsolid") || scanner.matches(token, "solid") {
                // A file can hold several solids; names run to the end of the line.
                scanner.skipToNextLine()
            } else {
                throw PreviewFailure.malformedDocument
            }
        }
        return TriangleMesh(positions: welder.positions, indices: indices, faceCount: facets, unitProvenance: .undeclared)
    }
}
