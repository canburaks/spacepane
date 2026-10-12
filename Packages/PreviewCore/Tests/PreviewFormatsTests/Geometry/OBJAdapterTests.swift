import Foundation
import Testing
import PreviewContracts
import PreviewFormats

@Suite("OBJ adapter")
struct OBJAdapterTests {
    private let cube = MeshFixtures.cube(size: 8)
    private let cubeQuads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]

    private func parse(_ text: String, budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try parse(Data(text.utf8), budget: budget)
    }

    private func parse(_ data: Data, budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try OBJAdapter().parse(FileBytes(data: data), context: RequestContext(budget: budget))
    }

    @Test func quadsAreFanTriangulatedAndFacesCounted() throws {
        let mesh = try parse(MeshFixtures.obj(cube.vertices, faces: cubeQuads))
        MeshFixtures.expectWellFormed(mesh)
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(mesh.faceCount == 6)
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(8, 8, 8))
        // Quads on a cube are flat: each corner keeps one normal per face.
        #expect(mesh.positions.count == 24)
    }

    @Test func everyFaceReferenceFormIsAccepted() throws {
        let text = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        v 0 0 1
        vt 0 0
        vn 0 0 1
        f 1 2 3
        f 1/1 2/1 4/1
        f 1//1 3//1 4//1
        f 2/1/1 3/1/1 4/1/1
        """
        let mesh = try parse(text)
        #expect(MeshFixtures.triangleCount(mesh) == 4)
        #expect(mesh.faceCount == 4)
    }

    @Test func negativeIndicesCountBackFromTheLastVertexDefinedSoFar() throws {
        let relative = """
        v 0 0 0
        v 4 0 0
        v 4 4 0
        v 0 4 0
        f -4 -3 -2 -1
        v 0 0 9
        f -1 -4 -3
        """
        let absolute = """
        v 0 0 0
        v 4 0 0
        v 4 4 0
        v 0 4 0
        f 1 2 3 4
        v 0 0 9
        f 5 2 3
        """
        let a = try parse(relative), b = try parse(absolute)
        #expect(a.positions == b.positions)
        #expect(a.indices == b.indices)
        #expect(MeshFixtures.triangleCount(a) == 3)
    }

    @Test func lineContinuationsJoinFacesAndCommentsAndCRLFAreIgnored() throws {
        // A comment that ends in a backslash continues onto the next line, which it swallows.
        let text = "# comment with a continuation \\\r\nv 99 99 99\r\nv 0 0 0\r\nv 5 0 0\r\nv \\\r\n 5 5 \\\n 0\r\nv 0 5 0\r\n"
            + "f 1 2 \\\r\n   3 \\\r\n 4\r\ng group\r\ns off\r\nl 1 2\r\np 1\r\nvt 0.5 0.5\r\nvn 0 0 1\r\n"
        let mesh = try parse(text)
        #expect(MeshFixtures.triangleCount(mesh) == 2)
        #expect(mesh.faceCount == 1)
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(5, 5, 0))
    }

    @Test func vertexColorsAndHomogeneousWeightsAreIgnored() throws {
        let mesh = try parse("v 0 0 0 1 0 0\nv 3 0 0 1.0\nv 0 3 0 0 1 0 1\nf 1 2 3\n")
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(3, 3, 0))
    }

    @Test func materialAndTextureReferencesAreNeverFollowed() throws {
        // The fixture names a library and a texture that do not exist; reading either would fail.
        let text = "mtllib /does/not/exist.mtl\nusemtl missing\nv 0 0 0\nv 1 0 0\nv 0 1 0\nmap_Kd texture.png\nf 1 2 3\n"
        #expect(MeshFixtures.triangleCount(try parse(text)) == 1)
    }

    @Test func rejectsBadReferencesAndCoordinates() throws {
        let header = "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 2 4\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 0 1 2\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f -4 1 2\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 2 x\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 2 /3\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 2\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 2 99999999999999999999\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("v 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n") }
        for spelling in ["nan", "inf", "-inf", "1e999", "1,5"] {
            #expect(throws: PreviewFailure.malformedDocument, "\(spelling)") { try parse("v \(spelling) 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n") }
        }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("v 4e12 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data([0, 1, 2, 255, 254, 10, 0])) }
    }

    @Test func geometryWithoutFacesIsNotDisplayable() throws {
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse("v 0 0 0\nv 1 0 0\nl 1 2\np 1\n") }
        #expect(throws: PreviewFailure.malformedDocument) { try parse("# nothing here\ng group\n") }
    }

    @Test func degenerateFacesAreDroppedAndAllDegenerateFilesAreRejected() throws {
        let header = "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 2\nv 3 0 0\n"
        // Face 2 repeats a corner and face 4 is collinear: neither has area.
        let mesh = try parse(header + "f 1 2 3\nf 1 1 2\nf 1 2 4\nf 1 2 5\n")
        #expect(MeshFixtures.triangleCount(mesh) == 2)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(header + "f 1 1 2\nf 1 2 5\n") }
    }

    @Test func enforcesByteVertexAndTriangleBudgets() throws {
        let data = MeshFixtures.obj(cube.vertices, faces: cubeQuads)
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: PreviewBudget(maxInputBytes: data.count - 1)) }
        // Twelve triangles need 144 index bytes at least.
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143))
        }
        // One polygon with more corners than any budget could triangulate is refused while it is read.
        var polygon = "v 0 0 0\nv 1 0 0\nv 1 1 0\nf"
        for _ in 0..<((MeshLimits.maximumTriangles + 10) / 3) { polygon += " 1 2 3" }
        polygon += "\n"
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(polygon) }
    }

    @Test func theTriangleCeilingIsExactAndAHighDegreeVertexStaysLinear() throws {
        // Half a million copies of one triangle: every vertex has half a million incident faces, which
        // takes the bounded high-degree path rather than comparing every pair.
        func file(triangles: Int) -> String { "v 0 0 0\nv 1 0 0\nv 0 1 0\n" + String(repeating: "f 1 2 3\n", count: triangles) }
        let mesh = try parse(file(triangles: MeshLimits.maximumTriangles))
        #expect(MeshFixtures.triangleCount(mesh) == MeshLimits.maximumTriangles)
        #expect(mesh.positions.count == 3)
        #expect(mesh.faceCount == GeometryLimits.maximumFaces)
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(file(triangles: MeshLimits.maximumTriangles + 1)) }
    }

    @Test func sourceBytesAreNeverModified() throws {
        let data = MeshFixtures.obj(cube.vertices, faces: cubeQuads)
        let copy = data
        _ = try parse(data)
        #expect(data == copy)
    }
}
