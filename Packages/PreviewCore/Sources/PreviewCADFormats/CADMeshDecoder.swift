import Foundation
import PreviewContracts

/// Private wire format: fixed little-endian numeric fields, never document-authored strings.
enum CADMeshDecoder {
    private static let signature = Array("PRVCAD01".utf8)

    /// The header's fourth word. Byte 0 says how the bounds were normalized: 1 is millimetres, the only value.
    /// Byte 1 names the length unit the source file declared and is 0 when the importer does not report one, which
    /// is what the importer wrote before the field existed. The upper half is reserved and must be zero, so a
    /// writer that grows the word cannot be misread as an older one. Codes follow the importer's table, not the
    /// declaration order of `GeometryLengthUnit`.
    static func declaredUnitProvenance(code: UInt32) -> GeometryUnitProvenance? {
        switch code {
        case 0: .assumedMillimetres
        case 1: .declared(.micrometre)
        case 2: .declared(.millimetre)
        case 3: .declared(.centimetre)
        case 4: .declared(.metre)
        case 5: .declared(.inch)
        case 6: .declared(.foot)
        default: nil
        }
    }
    static func decode(_ data: Data, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        guard data.count <= min(context.budget.maxOutputUTF8Bytes, GeometryLimits.maximumSerializedBytes) else {
            throw PreviewFailure.outputTooLarge
        }
        guard data.count >= 72, data.prefix(8).elementsEqual(signature) else { throw PreviewFailure.malformedDocument }
        return try data.withUnsafeBytes { bytes in
            var offset = 8
            func integer() -> UInt32 {
                defer { offset += 4 }
                return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            func scalar() -> Double {
                defer { offset += 8 }
                return Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
            }
            let vertices = Int(integer()), indicesCount = Int(integer()), faces = Int(integer()), units = integer()
            guard units & 0xFF == 1, units >> 16 == 0, let provenance = Self.declaredUnitProvenance(code: (units >> 8) & 0xFF),
                  vertices > 0, indicesCount > 0, indicesCount.isMultiple(of: 3), faces > 0 else {
                throw PreviewFailure.malformedDocument
            }
            guard vertices <= GeometryLimits.maximumVertices, indicesCount <= GeometryLimits.maximumIndices,
                  faces <= GeometryLimits.maximumFaces else { throw PreviewFailure.outputTooLarge }
            // Counts are bounded before multiplication or allocation; trailing data is forbidden.
            guard data.count == 72 + vertices * 24 + indicesCount * 4 else { throw PreviewFailure.malformedDocument }
            let bounds = GeometryBounds(minimum: SIMD3(scalar(), scalar(), scalar()), maximum: SIMD3(scalar(), scalar(), scalar()))
            var positions = [SIMD3<Float>](), normals = [SIMD3<Float>](), indices = [UInt32]()
            positions.reserveCapacity(vertices); normals.reserveCapacity(vertices); indices.reserveCapacity(indicesCount)
            for index in 0..<vertices {
                if index.isMultiple(of: 1024) { try context.checkpoint() }
                positions.append(SIMD3(Float(bitPattern: integer()), Float(bitPattern: integer()), Float(bitPattern: integer())))
                normals.append(SIMD3(Float(bitPattern: integer()), Float(bitPattern: integer()), Float(bitPattern: integer())))
            }
            for index in 0..<indicesCount {
                if index.isMultiple(of: 4096) { try context.checkpoint() }
                indices.append(integer())
            }
            return try PreviewMesh(positions: positions, normals: normals, indices: indices, bounds: bounds, faceCount: faces,
                                   unitProvenance: provenance)
        }
    }
}
