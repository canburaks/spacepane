import Foundation
import Testing
import PreviewContracts
import PreviewFormats

@Suite("PLY adapter")
struct PLYAdapterTests {
    private let cube = MeshFixtures.cube(size: 6)
    private let cubeQuads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]

    private func parse(_ data: Data, budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try PLYAdapter().parse(FileBytes(data: data), context: RequestContext(budget: budget))
    }

    private func parse(_ text: String) throws -> PreviewMesh { try parse(Data(text.utf8)) }

    @Test func allThreeEncodingsDescribeTheSameMesh() throws {
        let ascii = try parse(MeshFixtures.plyASCII(cube.vertices, faces: cubeQuads))
        let little = try parse(MeshFixtures.plyBinary(cube.vertices, faces: cubeQuads))
        let big = try parse(MeshFixtures.plyBinary(cube.vertices, faces: cubeQuads, bigEndian: true))
        MeshFixtures.expectWellFormed(ascii)
        for other in [little, big] {
            #expect(other.positions == ascii.positions)
            #expect(other.indices == ascii.indices)
            #expect(other.bounds == ascii.bounds)
        }
        #expect(ascii.faceCount == 6)
        #expect(MeshFixtures.triangleCount(ascii) == 12)
        #expect(MeshFixtures.extent(ascii) == SIMD3<Double>(6, 6, 6))
    }

    @Test func vertexCoordinatesMayUseAnyScalarTypeAndOtherPropertiesAreSkipped() throws {
        // Ordering and extra properties before, between and after the coordinates.
        var data = Data("""
        ply
        format binary_little_endian 1.0
        comment synthetic
        obj_info anything at all
        element vertex 3
        property uchar red
        property double x
        property short y
        property list uchar float texcoord
        property uint z
        property float nx
        element face 1
        property uchar flags
        property list uchar short vertex_index
        property list uchar float extra
        end_header

        """.utf8)
        for (x, y, z) in [(0.5, 0, 0), (4.5, 0, 0), (0.5, 3, 7)] as [(Double, Int16, UInt32)] {
            data.append(200)
            data += MeshFixtures.little32(UInt32(truncatingIfNeeded: x.bitPattern)) + MeshFixtures.little32(UInt32(truncatingIfNeeded: x.bitPattern >> 32))
            data += MeshFixtures.little16(UInt16(bitPattern: y))
            data.append(2); data += MeshFixtures.little32(Float(1).bitPattern) + MeshFixtures.little32(Float(2).bitPattern)
            data += MeshFixtures.little32(z)
            data += MeshFixtures.little32(Float.nan.bitPattern)   // unused normal: never interpreted
        }
        data.append(9)
        data.append(3); data += MeshFixtures.little16(0) + MeshFixtures.little16(1) + MeshFixtures.little16(2)
        data.append(1); data += MeshFixtures.little32(Float(3).bitPattern)
        let mesh = try parse(data)
        #expect(MeshFixtures.triangleCount(mesh) == 1)
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(4, 3, 7))
    }

    @Test func polygonsAndAlternateListNamesAreSupported() throws {
        let text = "ply\nformat ascii 1.0\nelement vertex 5\nproperty float x\nproperty float y\nproperty float z\n"
            + "element face 2\nproperty list uchar uint vertex_index\nend_header\n"
            + "0 0 0\n4 0 0\n4 4 0\n2 6 0\n0 4 0\n5 0 1 2 3 4\n3 0 2 4\n"
        let mesh = try parse(text)
        #expect(mesh.faceCount == 2)
        #expect(MeshFixtures.triangleCount(mesh) == 4)
    }

    @Test func otherElementsAreSkippedBySizeOrToken() throws {
        let header = """
        ply
        format ascii 1.0
        element empty 4000000000
        element vertex 3
        property float x
        property float y
        property float z
        element edge 2
        property int vertex1
        property int vertex2
        element material 1
        property list uchar char name
        element face 1
        property list uchar int vertex_indices
        end_header

        """
        let text = header + "0 0 0\n1 0 0\n0 1 0\n0 1\n1 2\n3 97 98 99\n3 0 1 2\n"
        let mesh = try parse(text)
        #expect(MeshFixtures.triangleCount(mesh) == 1)
    }

    @Test func crlfHeadersAreAccepted() throws {
        let text = "ply\r\nformat ascii 1.0\r\nelement vertex 3\r\nproperty float x\r\nproperty float y\r\nproperty float z\r\n"
            + "element face 1\r\nproperty list uchar int vertex_indices\r\nend_header\r\n0 0 0\r\n1 0 0\r\n0 1 0\r\n3 0 1 2\r\n"
        #expect(MeshFixtures.triangleCount(try parse(text)) == 1)
    }

    @Test func malformedHeadersAreRejected() throws {
        let body = "element vertex 1\nproperty float x\nproperty float y\nproperty float z\nelement face 0\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n"
        #expect(throws: PreviewFailure.malformedDocument) { try parse("plx\nformat ascii 1.0\n" + body) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("ply\n" + body) }                       // no format line
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse("ply\nformat binary_middle_endian 1.0\n" + body) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("ply\nformat ascii 1.0\nproperty float x\n" + body) }
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse("ply\nformat ascii 1.0\nelement vertex 1\nproperty quad x\nend_header\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("ply\nformat ascii 1.0\nelement vertex x\nend_header\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("ply\nformat ascii 1.0\nbogus\nend_header\n") }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse("ply\nformat ascii 1.0\n" + String(repeating: "comment x\n", count: 10_000)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("ply\nformat ascii 1.0\nelement vertex 1\n") }   // no end_header
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data()) }
        // A vertex element without all three coordinates cannot place any vertex.
        #expect(throws: PreviewFailure.malformedDocument) {
            try parse("ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nelement face 0\nend_header\n0 0\n")
        }
        // Duplicate elements are ambiguous.
        #expect(throws: PreviewFailure.malformedDocument) {
            try parse("ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nelement vertex 1\nend_header\n")
        }
    }

    @Test func truncatedAndInconsistentDataIsRejected() throws {
        let binary = MeshFixtures.plyBinary(cube.vertices, faces: cubeQuads)
        for cut in [1, 5, 40, binary.count / 2] {
            #expect(throws: PreviewFailure.malformedDocument, "cut \(cut)") { try parse(binary.dropLast(cut)) }
        }
        let ascii = String(decoding: MeshFixtures.plyASCII(cube.vertices, faces: cubeQuads), as: UTF8.self)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(String(ascii.dropLast(20))) }
        // Counts that promise far more rows than the file can hold are refused before allocation.
        #expect(throws: PreviewFailure.malformedDocument) {
            try parse("ply\nformat binary_little_endian 1.0\nelement vertex 1000000\nproperty float x\nproperty float y\nproperty float z\nelement face 0\nend_header\n")
        }
        // Beyond the contract's own ceilings the model is too complex (Q-11); a smaller caller budget stays an output size.
        #expect(throws: PreviewFailure.geometryTooComplex) {
            try parse("ply\nformat ascii 1.0\nelement vertex \(GeometryLimits.maximumVertices + 1)\nproperty float x\nproperty float y\nproperty float z\nend_header\n")
        }
        #expect(throws: PreviewFailure.geometryTooComplex) {
            try parse("ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face \(MeshLimits.maximumTriangles + 1)\nproperty list uchar int vertex_indices\nend_header\n")
        }
    }

    @Test func rejectsIndexErrorsShortPolygonsAndNonFiniteValues() throws {
        let head = "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n"
        let verts = "0 0 0\n1 0 0\n0 1 0\n"
        #expect(MeshFixtures.triangleCount(try parse(head + verts + "3 0 1 2\n")) == 1)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(head + verts + "3 0 1 3\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(head + verts + "3 0 1 -1\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(head + verts + "2 0 1\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(head + verts + "3 0 1.5 2\n") }
        for spelling in ["nan", "inf", "1e999", "0x1"] {
            #expect(throws: PreviewFailure.malformedDocument, "\(spelling)") { try parse(head + "0 0 0\n1 0 0\n\(spelling) 1 0\n3 0 1 2\n") }
        }
        // Binary non-finite coordinates.
        for bad in [Float.nan, .infinity, -.infinity] {
            var data = Data(MeshFixtures.plyHeader("binary_little_endian", vertices: 3, faces: 1).utf8)
            for value in [bad, 0, 0, 1, 0, 0, 0, 1, 0] as [Float] { data += MeshFixtures.little32(value.bitPattern) }
            data.append(3); data += MeshFixtures.little32(0) + MeshFixtures.little32(1) + MeshFixtures.little32(2)
            #expect(throws: PreviewFailure.malformedDocument, "\(bad)") { try parse(data) }
        }
        // A face list whose count type is a float is not a list of indices.
        let floatCount = "ply\nformat binary_little_endian 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list float int vertex_indices\nend_header\n"
        var data = Data(floatCount.utf8)
        for value in [0, 0, 0, 1, 0, 0, 0, 1, 0] as [Float] { data += MeshFixtures.little32(value.bitPattern) }
        data += MeshFixtures.little32(Float(3).bitPattern) + MeshFixtures.little32(0) + MeshFixtures.little32(1) + MeshFixtures.little32(2)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(data) }
    }

    @Test func pointCloudsHaveNoSurface() throws {
        let text = "ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nend_header\n0 0 0\n1 1 1\n"
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse(text) }
        let noIndexProperty = "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int normals\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n"
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse(noIndexProperty) }
    }

    @Test func enforcesByteAndTriangleBudgets() throws {
        let data = MeshFixtures.plyBinary(cube.vertices, faces: cubeQuads)
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: PreviewBudget(maxInputBytes: data.count - 1)) }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143))
        }
    }

    @Test func degenerateFacesAreDroppedAndSourceBytesAreUnchanged() throws {
        var faces = cubeQuads
        faces.append([0, 0, 1])
        let data = MeshFixtures.plyBinary(cube.vertices, faces: faces)
        let copy = data
        let mesh = try parse(data)
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(data == copy)
    }
}
