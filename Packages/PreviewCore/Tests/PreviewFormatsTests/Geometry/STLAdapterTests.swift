import Foundation
import Testing
import PreviewContracts
import PreviewFormats

@Suite("STL adapter")
struct STLAdapterTests {
    private let cube = MeshFixtures.cube(size: 20)

    private func parse(_ data: Data, budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try STLAdapter().parse(FileBytes(data: data), context: RequestContext(budget: budget))
    }

    @Test func binaryAndASCIIProduceTheSameMesh() throws {
        let binary = try parse(MeshFixtures.stlBinary(cube.vertices, cube.triangles))
        let ascii = try parse(MeshFixtures.stlASCII(cube.vertices, cube.triangles))
        MeshFixtures.expectWellFormed(binary)
        #expect(binary.positions == ascii.positions)
        #expect(binary.indices == ascii.indices)
        #expect(binary.bounds == ascii.bounds)
        #expect(binary.faceCount == 12)
        #expect(MeshFixtures.triangleCount(binary) == 12)
        // Physical bounds are the model's own coordinates; positions are centered and normalized.
        #expect(binary.bounds.minimum == SIMD3<Double>(-10, -10, -10))
        #expect(binary.bounds.maximum == SIMD3<Double>(10, 10, 10))
    }

    @Test func binaryFileWhoseHeaderStartsWithSolidIsStillBinary() throws {
        let data = MeshFixtures.stlBinary(cube.vertices, cube.triangles, header: "solid exported by a binary writer")
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "solid")
        let mesh = try parse(data)
        #expect(MeshFixtures.triangleCount(mesh) == 12)
    }

    @Test func weldsSharedVerticesAndKeepsCubeEdgesSharp() throws {
        let mesh = try parse(MeshFixtures.stlBinary(cube.vertices, cube.triangles))
        // Eight corners, each shared by three faces at right angles: one output vertex per face normal.
        #expect(mesh.positions.count == 24)
        for normal in mesh.normals {
            let components = [abs(normal.x), abs(normal.y), abs(normal.z)].sorted()
            #expect(abs(components[2] - 1) < 1e-5 && components[0] < 1e-5)
        }
    }

    @Test func smoothSurfacesShareVertexNormals() throws {
        let torus = MeshFixtures.torus(segments: 24, sides: 12)
        let mesh = try parse(MeshFixtures.stlBinary(torus.vertices, MeshFixtures.triangles(torus.quads)))
        #expect(mesh.positions.count == torus.vertices.count)
        #expect(MeshFixtures.triangleCount(mesh) == torus.quads.count * 2)
        MeshFixtures.expectWellFormed(mesh)
    }

    @Test func asciiAcceptsUppercaseKeywordsSeveralSolidsAndOddWhitespace() throws {
        var text = "\u{FEFF}SOLID first\r\n"
        for triangle in cube.triangles.prefix(6) {
            text += "FACET NORMAL nan nan nan\r\n OUTER LOOP\r\n"
            for index in triangle { text += "\tVERTEX \(cube.vertices[index].x)   \(cube.vertices[index].y)\t\(cube.vertices[index].z)\r\n" }
            text += " ENDLOOP\r\nENDFACET\r\n"
        }
        text += "ENDSOLID first\r\nsolid second\r\n"
        for triangle in cube.triangles.suffix(6) {
            text += "facet normal 0 0 0\nouter loop\n"
            for index in triangle { text += "vertex \(cube.vertices[index].x) \(cube.vertices[index].y) \(cube.vertices[index].z)\n" }
            text += "endloop\nendfacet\n"
        }
        text += "endsolid second\n"
        let mesh = try parse(Data(text.utf8))
        #expect(MeshFixtures.triangleCount(mesh) == 12)
    }

    @Test func asciiParsesScientificNotationAndSigns() throws {
        let text = """
        solid s
        facet normal 0 0 1
        outer loop
        vertex 0 0 0
        vertex 1.5E+1 -0.0 0
        vertex +0.000000000001e13 2.5e1 1e-3
        endloop
        endfacet
        endsolid s
        """
        let mesh = try parse(Data(text.utf8))
        #expect(mesh.bounds.maximum.x == 15)
        #expect(mesh.bounds.maximum.y == 25)
        #expect(abs(mesh.bounds.maximum.z - 0.001) < 1e-12)
    }

    @Test func triangleCountAndSizeMustAgree() throws {
        let valid = MeshFixtures.stlBinary(cube.vertices, cube.triangles)
        // Truncated: the header promises more triangles than the file holds.
        #expect(throws: PreviewFailure.malformedDocument) { try parse(valid.dropLast(7)) }
        // Trailing bytes after the last triangle are not a binary STL either.
        #expect(throws: PreviewFailure.malformedDocument) { try parse(valid + Data([0])) }
        // A count that disagrees with the size, for a file that is not ASCII.
        var wrongCount = valid
        wrongCount.replaceSubrange(80..<84, with: MeshFixtures.little32(13))
        #expect(throws: PreviewFailure.malformedDocument) { try parse(wrongCount) }
        // A header-only file has no triangles.
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.stlBinary([], [])) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data(repeating: 0, count: 83)) }
    }

    @Test func rejectsMalformedASCII() throws {
        let truncated = "solid s\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\n"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data(truncated.utf8)) }
        let wrongKeyword = "solid s\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nbogus\n"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data(wrongKeyword.utf8)) }
        let missingCoordinate = "solid s\nfacet normal 0 0 1\nouter loop\nvertex 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data(missingCoordinate.utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data("solid empty\nendsolid empty\n".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data("not an stl at all\n".utf8)) }
    }

    @Test func rejectsNonFiniteAndOutOfRangeCoordinates() throws {
        for spelling in ["nan", "inf", "-inf", "Infinity", "1e999", "0x10", "1.5f", "--1", "1e", "."] {
            let text = "solid s\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex \(spelling) 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid s\n"
            #expect(throws: PreviewFailure.malformedDocument, "\(spelling)") { try parse(Data(text.utf8)) }
        }
        // Binary NaN, infinity and a coordinate beyond the contract's 1e12 magnitude.
        for bad in [Float.nan, Float.infinity, -Float.infinity, 3e12] {
            var triangle = cube.vertices
            triangle[0] = SIMD3<Double>(Double(bad), 0, 0)
            let data = MeshFixtures.stlBinary(triangle, [[0, 1, 2]])
            #expect(throws: PreviewFailure.malformedDocument, "\(bad)") { try parse(data) }
        }
    }

    @Test func dropsDegenerateTrianglesAndRejectsAFileOfOnlyDegenerateOnes() throws {
        var vertices = cube.vertices
        vertices.append(SIMD3<Double>(5, 5, 5))      // 8
        vertices.append(SIMD3<Double>(0, -10, -10))  // 9: on the edge between corners 0 and 1
        // A repeated corner, a collinear zero-area sliver and a collapsed triangle join the real faces.
        let triangles = cube.triangles + [[0, 0, 1], [0, 1, 9], [8, 8, 8]]
        let mesh = try parse(MeshFixtures.stlBinary(vertices, triangles))
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(throws: PreviewFailure.malformedDocument) {
            try parse(MeshFixtures.stlBinary(vertices, [[0, 0, 1], [8, 8, 8], [0, 1, 9]]))
        }
    }

    @Test func flatModelsKeepTheirPlane() throws {
        // All z are equal: one axis has no extent, which is still a displayable surface.
        let mesh = try parse(MeshFixtures.stlBinary([SIMD3(0, 0, 3), SIMD3(4, 0, 3), SIMD3(0, 2, 3)], [[0, 1, 2]]))
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(4, 2, 0))
        MeshFixtures.expectWellFormed(mesh)
    }

    @Test func enforcesByteAndTriangleBudgets() throws {
        let data = MeshFixtures.stlBinary(cube.vertices, cube.triangles)
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: PreviewBudget(maxInputBytes: data.count - 1)) }
        #expect(throws: PreviewFailure.inputTooLarge) {
            try STLAdapter().parse(FileBytes(data: Data(count: GeometryLimits.maximumInputBytes + 1)), context: MeshFixtures.context)
        }
        // Twelve triangles need at least 144 index bytes: a smaller output budget refuses before any work.
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143))
        }
        // The same limit applies to ASCII input.
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(MeshFixtures.stlASCII(cube.vertices, cube.triangles), budget: PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143))
        }
    }

    @Test func headerClaimingMoreTrianglesThanTheContractAllowsIsRefusedBeforeAllocation() throws {
        // 600,000 triangles would need a 30 MB file; the declared count must not drive any allocation.
        var data = Data(repeating: 0x20, count: 80)
        data += MeshFixtures.little32(600_000)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(data) }
    }

    @Test func sourceBytesAreNeverModified() throws {
        let data = MeshFixtures.stlBinary(cube.vertices, cube.triangles)
        let copy = data
        _ = try parse(data)
        #expect(data == copy)
    }
}
