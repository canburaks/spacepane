import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// Where a mesh's unit comes from, and what a model beyond the geometry ceilings fails with (decision 027, Q-11).
@Suite("Mesh unit provenance and geometry limits")
struct GeometryUnitProvenanceTests {
    private let cube = MeshFixtures.cube()

    private func parse(_ adapter: any GeometryFormatAdapter, _ data: Data,
                       budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try adapter.parse(FileBytes(data: data), context: RequestContext(budget: budget))
    }

    // MARK: Provenance

    @Test func stlObjAndPlyCarryNoUnitSoThePresentationNeverShowsOneAsMillimetres() throws {
        let meshes = [
            try parse(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, cube.triangles)),
            try parse(STLAdapter(), MeshFixtures.stlASCII(cube.vertices, cube.triangles)),
            try parse(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: cube.triangles)),
            try parse(PLYAdapter(), MeshFixtures.plyASCII(cube.vertices, faces: cube.triangles)),
            try parse(PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: cube.triangles))]
        for mesh in meshes { #expect(mesh.unitProvenance == .undeclared) }
        // The extents are still millimetres by the importers' convention; only the claim about them is withheld.
        #expect(MeshFixtures.extent(meshes[0]) == SIMD3<Double>(2, 2, 2))
    }

    @Test(arguments: [("micron", GeometryLengthUnit.micrometre), ("millimeter", .millimetre), ("centimeter", .centimetre),
                      ("meter", .metre), ("inch", .inch), ("foot", .foot)])
    func aThreeMFDeclaresTheUnitItNames(name: String, expected: GeometryLengthUnit) throws {
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: name)
        let mesh = try parse(ThreeMFAdapter(), data)
        #expect(mesh.unitProvenance == .declared(expected), "\(name)")
        // The stored extents are millimetres whatever the declared unit.
        let edge = 2 * expected.millimetres
        #expect(abs(MeshFixtures.extent(mesh).x - edge) < 1e-9 * max(1, edge), "\(name)")
    }

    @Test func aThreeMFWithoutTheUnitAttributeAssumesTheSpecificationsMillimetres() throws {
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: nil)
        #expect(try parse(ThreeMFAdapter(), data).unitProvenance == .assumedMillimetres)
    }

    // MARK: Face counts

    @Test func aFaceCountAtTheCapIsExactAndOneMoreIsReportedAsCapped() throws {
        // One triangle's bytes repeated: the same triangle many times welds to three vertices, so the file is cheap to build.
        let corner = [MeshFixtures.Vertex(0, 0, 0), MeshFixtures.Vertex(1, 0, 0), MeshFixtures.Vertex(0, 1, 0)]
        let single = MeshFixtures.stlBinary(corner, [[0, 1, 2]])
        let record = Data(single.suffix(50))
        func binarySTL(triangles: Int) -> Data {
            var data = Data(single.prefix(80)) + MeshFixtures.little32(UInt32(triangles))
            data.reserveCapacity(84 + 50 * triangles)
            for _ in 0..<triangles { data.append(record) }
            return data
        }
        let atCap = try parse(STLAdapter(), binarySTL(triangles: GeometryLimits.maximumFaces))
        #expect(atCap.faceCount == GeometryLimits.maximumFaces && !atCap.faceCountIsCapped)
        let beyond = try parse(STLAdapter(), binarySTL(triangles: GeometryLimits.maximumFaces + 1))
        #expect(beyond.faceCount == GeometryLimits.maximumFaces && beyond.faceCountIsCapped)
        // The triangle count is exact either way.
        #expect(MeshFixtures.triangleCount(atCap) == GeometryLimits.maximumFaces)
        #expect(MeshFixtures.triangleCount(beyond) == GeometryLimits.maximumFaces + 1)
    }

    @Test func aSmallModelsFaceCountIsNeverCapped() throws {
        let mesh = try parse(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: cube.triangles))
        #expect(!mesh.faceCountIsCapped && mesh.faceCount == 12)
    }

    // MARK: Ceilings

    @Test func aModelBeyondTheGeometryCeilingsFailsAsTooComplex() throws {
        let vertices = "ply\nformat ascii 1.0\nelement vertex \(GeometryLimits.maximumVertices + 1)\n"
            + "property float x\nproperty float y\nproperty float z\nend_header\n"
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(PLYAdapter(), Data(vertices.utf8)) }
        let faces = "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n"
            + "element face \(MeshLimits.maximumTriangles + 1)\nproperty list uchar int vertex_indices\nend_header\n"
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(PLYAdapter(), Data(faces.utf8)) }
        let objTriangles = "v 0 0 0\nv 1 0 0\nv 0 1 0\n" + String(repeating: "f 1 2 3\n", count: MeshLimits.maximumTriangles + 1)
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(OBJAdapter(), Data(objTriangles.utf8)) }
    }

    @Test func aLowerOutputBudgetKeepsItsOwnOutputSizeFailure() throws {
        // Twelve triangles need at least 144 index bytes: a smaller output budget refuses before any work, and that is
        // a budget, not a statement about the model.
        let small = PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143)
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, cube.triangles), budget: small)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(STLAdapter(), MeshFixtures.stlASCII(cube.vertices, cube.triangles), budget: small)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: cube.triangles), budget: small)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: cube.triangles), budget: small)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(ThreeMFAdapter(), MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles), budget: small)
        }
    }
}
