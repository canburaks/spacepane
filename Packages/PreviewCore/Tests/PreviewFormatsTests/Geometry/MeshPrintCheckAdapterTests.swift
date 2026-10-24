import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// STL, OBJ, PLY and 3MF previews carry the shared measurements, with the unit provenance each format has
/// (Mesh Print Check, decision 029). The cube has an edge of 10 units: area 600 and volume 1,000 in those units.
@Suite("Mesh Print Check in the adapters")
struct MeshPrintCheckAdapterTests {
    private let cube = MeshFixtures.cube(size: 10)
    private let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]

    private func parse(_ adapter: any GeometryFormatAdapter, _ data: Data) throws -> PreviewMesh {
        try adapter.parse(FileBytes(data: data), context: MeshFixtures.context)
    }

    private func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-5,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else { Issue.record("value unavailable", sourceLocation: sourceLocation); return }
        #expect(abs(actual - expected) <= expected * tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    /// A closed cube of edge 10: size from the bounds, measurements from the surface.
    private func expectClosedCube(_ mesh: PreviewMesh, _ name: String, provenance: GeometryUnitProvenance,
                                  sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(10, 10, 10), "\(name)", sourceLocation: sourceLocation)
        let measured = try #require(mesh.measurements, "\(name)", sourceLocation: sourceLocation)
        expectClose(measured.surfaceAreaSquareMillimetres, 600, sourceLocation: sourceLocation)
        expectClose(measured.volumeCubicMillimetres, 1_000, sourceLocation: sourceLocation)
        #expect(measured.bodyCount == 1, "\(name)", sourceLocation: sourceLocation)
        #expect(measured.openEdgeCount == 0 && measured.nonManifoldEdgeCount == 0, "\(name)", sourceLocation: sourceLocation)
        #expect(measured.unitProvenance == provenance, "\(name)", sourceLocation: sourceLocation)
    }

    // MARK: Every format

    @Test func stlObjAndPlyMeasureAClosedCubeInAnUndeclaredUnit() throws {
        let meshes: [(String, PreviewMesh)] = [
            ("STL binary", try parse(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, cube.triangles))),
            ("STL ASCII", try parse(STLAdapter(), MeshFixtures.stlASCII(cube.vertices, cube.triangles))),
            ("OBJ", try parse(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: quads))),
            ("PLY ASCII", try parse(PLYAdapter(), MeshFixtures.plyASCII(cube.vertices, faces: quads))),
            ("PLY binary", try parse(PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: quads))),
            ("PLY big endian", try parse(PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: quads, bigEndian: true)))]
        for (name, mesh) in meshes {
            // The reader records no unit for these formats; the measurements say the same as the mesh, never millimetres.
            try expectClosedCube(mesh, name, provenance: .undeclared)
            #expect(mesh.unitProvenance == .undeclared, "\(name)")
        }
    }

    @Test func aThreeMFMeasuresInTheUnitItDeclares() throws {
        for (name, unit) in [("millimeter", GeometryLengthUnit.millimetre), ("inch", .inch)] {
            let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: name)
            let mesh = try parse(ThreeMFAdapter(), data)
            let factor = unit.millimetres
            // The values stay in millimetres whatever the declared unit: only the provenance says what they were.
            for axis in 0..<3 { expectClose(MeshFixtures.extent(mesh)[axis], 10 * factor, tolerance: 1e-9) }
            let measured = try #require(mesh.measurements)
            expectClose(measured.surfaceAreaSquareMillimetres, 600 * factor * factor)
            expectClose(measured.volumeCubicMillimetres, 1_000 * factor * factor * factor)
            #expect(measured.unitProvenance == .declared(unit) && mesh.unitProvenance == .declared(unit), "\(name)")
        }
    }

    @Test func aThreeMFInCentimetresMeasuresTenCentimetresAsOneHundredMillimetres() throws {
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: "centimeter")
        let mesh = try parse(ThreeMFAdapter(), data)
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(100, 100, 100))
        let measured = try #require(mesh.measurements)
        expectClose(measured.surfaceAreaSquareMillimetres, 60_000)
        expectClose(measured.volumeCubicMillimetres, 1_000_000)
        #expect(measured.unitProvenance == .declared(.centimetre))
    }

    @Test func aThreeMFWithoutAUnitAssumesMillimetresInItsMeasurements() throws {
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: nil)
        try expectClosedCube(try parse(ThreeMFAdapter(), data), "3MF", provenance: .assumedMillimetres)
    }

    // MARK: Print facts

    @Test func anOpenBoxInEveryFormatReportsItsOpenEdgesAndNoVolume() throws {
        let faces = Array(quads.dropFirst())   // The first face is missing.
        let triangles = Array(cube.triangles.dropFirst(2))
        let meshes: [(String, PreviewMesh)] = [
            ("STL", try parse(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, triangles))),
            ("OBJ", try parse(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: faces))),
            ("PLY", try parse(PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: faces))),
            ("3MF", try parse(ThreeMFAdapter(), MeshFixtures.threeMF(vertices: cube.vertices, triangles: triangles)))]
        for (name, mesh) in meshes {
            let measured = try #require(mesh.measurements, "\(name)")
            #expect(measured.openEdgeCount == 4, "\(name)")
            #expect(measured.nonManifoldEdgeCount == 0, "\(name)")
            #expect(measured.volumeCubicMillimetres == nil, "\(name)")
            expectClose(measured.surfaceAreaSquareMillimetres, 500)
        }
    }

    @Test func aModelWithoutSharedVerticesStillWeldsIntoOneClosedBody() throws {
        // A triangle soup OBJ: every face owns its corners, as many exporters write them.
        var text = ""
        var faceLines = ""
        for (index, triangle) in cube.triangles.enumerated() {
            for corner in triangle { let v = cube.vertices[corner]; text += "v \(v.x) \(v.y) \(v.z)\n" }
            faceLines += "f \(index * 3 + 1) \(index * 3 + 2) \(index * 3 + 3)\n"
        }
        let mesh = try parse(OBJAdapter(), Data((text + faceLines).utf8))
        try expectClosedCube(mesh, "soup OBJ", provenance: .undeclared)
    }

    // MARK: Cancellation

    @Test func cancellationDuringTheMeasurementOfAnyFormatPropagates() async throws {
        let inputs: [(any GeometryFormatAdapter, Data)] = [
            (STLAdapter(), MeshFixtures.stlASCII(cube.vertices, cube.triangles)),
            (OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: quads)),
            (PLYAdapter(), MeshFixtures.plyBinary(cube.vertices, faces: quads)),
            (ThreeMFAdapter(), MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles))]
        for (adapter, data) in inputs {
            // The final checkpoint of a parse belongs to the measurer, the last stage.
            try await MeshPrintCheckMeasurementTests.expectCancelledAtFinalCheckpoint { context in
                _ = try adapter.parse(FileBytes(data: data), context: context)
            }
        }
    }
}
