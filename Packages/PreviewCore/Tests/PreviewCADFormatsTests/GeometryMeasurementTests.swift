import Foundation
import Testing
@testable import PreviewCADFormats
import PreviewContracts

/// Synthetic meshes built in code. Positions are given in millimetres and normalized exactly as the importer
/// does (centred, longest extent two), so the scale and offset recovery is exercised end to end.
@Suite("CAD geometry measurements") struct GeometryMeasurementTests {
    typealias Point = SIMD3<Double>
    struct Soup { var points: [Point] = []; var triangles: [[Int]] = [] }

    /// Eight corners indexed by bit pattern (x = 1, y = 2, z = 4) and twelve outward-facing triangles.
    static let cubeTriangles: [[Int]] = [
        [0, 4, 6], [0, 6, 2], [1, 3, 7], [1, 7, 5], [0, 1, 5], [0, 5, 4],
        [2, 6, 7], [2, 7, 3], [0, 2, 3], [0, 3, 1], [4, 5, 7], [4, 7, 6]
    ]
    static func corners(minimum: Point, size: Point) -> [Point] {
        (0..<8).map { bits in
            Point(minimum.x + (bits & 1 != 0 ? size.x : 0), minimum.y + (bits & 2 != 0 ? size.y : 0),
                  minimum.z + (bits & 4 != 0 ? size.z : 0))
        }
    }
    /// A cube with eight shared vertices.
    static func sharedCube(minimum: Point, size: Point) -> Soup {
        Soup(points: corners(minimum: minimum, size: size), triangles: cubeTriangles)
    }
    /// A cube whose every face owns its vertices, as the importer's per-face tessellation produces.
    static func duplicatedCube(minimum: Point, size: Point) -> Soup {
        let corner = corners(minimum: minimum, size: size)
        var soup = Soup()
        for triangle in cubeTriangles {
            var indices: [Int] = []
            for vertex in triangle { indices.append(soup.points.count); soup.points.append(corner[vertex]) }
            soup.triangles.append(indices)
        }
        return soup
    }
    static func merged(_ parts: Soup...) -> Soup {
        var soup = Soup()
        for part in parts {
            let offset = soup.points.count
            soup.points += part.points
            soup.triangles += part.triangles.map { $0.map { $0 + offset } }
        }
        return soup
    }

    /// Normalizes like `CADImport.cpp`: centre of the bounds, scale 2 / longest extent, Float32 output.
    static func mesh(_ soup: Soup, nudge: (Int, SIMD3<Float>) -> SIMD3<Float> = { $1 }) throws -> PreviewMesh {
        var low = soup.points[0], high = soup.points[0]
        for point in soup.points { low = pointwiseMin(low, point); high = pointwiseMax(high, point) }
        let extent = max(high.x - low.x, high.y - low.y, high.z - low.z)
        let centre = (low + high) / 2, scale = 2 / extent
        let positions = soup.points.enumerated().map { nudge($0, SIMD3<Float>((($1 - centre) * scale))) }
        return try PreviewMesh(positions: positions, normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count),
            indices: soup.triangles.flatMap { $0.map(UInt32.init) }, bounds: GeometryBounds(minimum: low, maximum: high),
            faceCount: max(1, soup.triangles.count / 2))
    }

    static func context() -> RequestContext { RequestContext(budget: GeometryLimits.requestBudget) }
    static func measure(_ soup: Soup, nudge: (Int, SIMD3<Float>) -> SIMD3<Float> = { $1 }) throws -> GeometryMeasurements {
        try #require(try GeometryMeasurer.measure(try mesh(soup, nudge: nudge), context: context()))
    }
    func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-5,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else { Issue.record("value unavailable", sourceLocation: sourceLocation); return }
        #expect(abs(actual - expected) <= expected * tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    // 12 x 6 x 3 mm at an offset: area 2(72 + 36 + 18) = 252 mm², volume 216 mm³.
    static let origin = Point(94, -53, 8.5), size = Point(12, 6, 3)

    @Test func unitCubeAtUnitScale() throws {
        let measured = try Self.measure(Self.sharedCube(minimum: .zero, size: Point(1, 1, 1)))
        expectClose(measured.surfaceAreaSquareMillimetres, 6)
        expectClose(measured.volumeCubicMillimetres, 1)
        #expect(measured.bodyCount == 1)
    }

    @Test func sharedVertexCubeRecoversScaleAndOffset() throws {
        let measured = try Self.measure(Self.sharedCube(minimum: Self.origin, size: Self.size))
        expectClose(measured.surfaceAreaSquareMillimetres, 252)
        expectClose(measured.volumeCubicMillimetres, 216)
        #expect(measured.bodyCount == 1)
    }

    @Test func perFaceDuplicatedVerticesWeldIntoOneClosedBody() throws {
        let measured = try Self.measure(Self.duplicatedCube(minimum: Self.origin, size: Self.size))
        expectClose(measured.surfaceAreaSquareMillimetres, 252)
        expectClose(measured.volumeCubicMillimetres, 216)
        #expect(measured.bodyCount == 1)
    }

    @Test func weldingToleratesFloatRoundingNoiseBetweenFaces() throws {
        // Each duplicate of a corner moves by a unit or two in the last place, as differing transform
        // rounding between faces could produce. Edges must still pair up.
        let measured = try Self.measure(Self.duplicatedCube(minimum: Self.origin, size: Self.size)) { index, position in
            var value = position
            for axis in 0..<3 { value[axis] = (index + axis).isMultiple(of: 2) ? value[axis].nextUp.nextUp : value[axis].nextDown }
            return value
        }
        expectClose(measured.volumeCubicMillimetres, 216, tolerance: 1e-4)
        #expect(measured.bodyCount == 1)
    }

    @Test func openBoxReportsAreaButNoVolume() throws {
        var soup = Self.duplicatedCube(minimum: Self.origin, size: Self.size)
        soup.triangles.removeLast(2) // Drop the +Z face.
        let measured = try Self.measure(soup)
        expectClose(measured.surfaceAreaSquareMillimetres, 252 - 72)
        #expect(measured.volumeCubicMillimetres == nil)
        #expect(measured.bodyCount == 1)
    }

    @Test func disjointCubesCountTwoBodiesAndSumTheirVolumes() throws {
        let first = Self.duplicatedCube(minimum: Self.origin, size: Self.size)
        let second = Self.sharedCube(minimum: Point(150, -53, 8.5), size: Point(4, 4, 4))
        let measured = try Self.measure(Self.merged(first, second))
        #expect(measured.bodyCount == 2)
        expectClose(measured.volumeCubicMillimetres, 216 + 64)
        expectClose(measured.surfaceAreaSquareMillimetres, 252 + 96)
    }

    @Test func invertedWindingGivesAPositiveVolume() throws {
        var soup = Self.sharedCube(minimum: Self.origin, size: Self.size)
        soup.triangles = soup.triangles.map { [$0[0], $0[2], $0[1]] }
        let measured = try Self.measure(soup)
        expectClose(measured.volumeCubicMillimetres, 216)
        expectClose(measured.surfaceAreaSquareMillimetres, 252)
    }

    @Test func oneFlippedFaceIsNotAConsistentlyClosedSurface() throws {
        var soup = Self.sharedCube(minimum: Self.origin, size: Self.size)
        soup.triangles[0] = [soup.triangles[0][0], soup.triangles[0][2], soup.triangles[0][1]]
        let measured = try Self.measure(soup)
        #expect(measured.volumeCubicMillimetres == nil)
    }

    @Test func degenerateTrianglesDoNotChangeAreaVolumeOrClosure() throws {
        var soup = Self.duplicatedCube(minimum: Self.origin, size: Self.size)
        // A repeated index, and a triangle whose three distinct vertices all sit at one corner.
        soup.triangles.append([0, 0, 1])
        let base = soup.points.count
        soup.points += Array(repeating: soup.points[0], count: 3)
        soup.triangles.append([base, base + 1, base + 2])
        let measured = try Self.measure(soup)
        expectClose(measured.surfaceAreaSquareMillimetres, 252)
        expectClose(measured.volumeCubicMillimetres, 216)
        #expect(measured.bodyCount == 1)
    }

    @Test func stackedSolidsSharingAFaceStayClosedAndAreOneWeldedBody() throws {
        // Two 4 mm cubes touching on a coincident face keep both copies of that face: every edge still
        // balances, so the volume is the sum, and the welded surface is one connected component.
        let lower = Self.duplicatedCube(minimum: .zero, size: Point(4, 4, 4))
        let upper = Self.duplicatedCube(minimum: Point(0, 0, 4), size: Point(4, 4, 4))
        let measured = try Self.measure(Self.merged(lower, upper))
        expectClose(measured.volumeCubicMillimetres, 128)
        expectClose(measured.surfaceAreaSquareMillimetres, 192)
        #expect(measured.bodyCount == 1)
    }

    @Test func aMeshWithOnlyDegenerateTrianglesHasNoVolume() throws {
        let soup = Soup(points: [Point(0, 0, 0), Point(1, 0, 0), Point(0, 1, 0)], triangles: [[0, 0, 1], [1, 1, 2]])
        let measured = try Self.measure(soup)
        #expect(measured.surfaceAreaSquareMillimetres == 0)
        #expect(measured.volumeCubicMillimetres == nil)
        #expect(measured.bodyCount >= 1)
    }

    // MARK: Cancellation and the request deadline

    /// 150,000 loose triangles: 450,000 vertices and 450,000 edge records.
    static func largeSoup() throws -> PreviewMesh {
        var soup = Soup()
        for triangle in 0..<150_000 {
            let x = Double(triangle % 400) / 200 - 1, y = Double(triangle / 400) / 190 - 1
            let base = soup.points.count
            soup.points += [Point(x, y, 0), Point(x + 0.002, y, 0.001), Point(x, y + 0.002, -0.001)]
            soup.triangles.append([base, base + 1, base + 2])
        }
        return try mesh(soup)
    }

    @Test func anExpiredDeadlineStopsBeforeAnyWork() throws {
        let mesh = try Self.largeSoup()
        let context = RequestContext(budget: PreviewBudget(maxMilliseconds: 1))
        Thread.sleep(forTimeInterval: 0.05)
        #expect(throws: PreviewFailure.deadlineExceeded) { try GeometryMeasurer.measure(mesh, context: context) }
    }

    @Test func aDeadlineThatExpiresDuringWorkIsHonoredPromptly() throws {
        let mesh = try Self.largeSoup()
        let started = ContinuousClock.now
        let context = RequestContext(budget: PreviewBudget(maxMilliseconds: 5))
        #expect(throws: PreviewFailure.deadlineExceeded) { try GeometryMeasurer.measure(mesh, context: context) }
        // The standard sort cannot be interrupted, so allow it to finish; the whole run must still be bounded.
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    @Test func cancellationPropagatesAsCancellationError() async throws {
        let mesh = try Self.largeSoup()
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try GeometryMeasurer.measure(mesh, context: RequestContext(budget: GeometryLimits.requestBudget))
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("A cancelled measurement completed") }
        catch is CancellationError {} catch { Issue.record("Unexpected failure \(error)") }
    }

    // MARK: Adapter integration

    @Test func theAdapterAttachesMeasurementsAndHeaderFactsAfterAnImportThroughTheRealTransport() throws {
        // A 10 x 20 x 30 mm box with per-face vertices, delivered by a stub helper over the real process transport.
        let box = Self.duplicatedCube(minimum: Point(100, 200, 300), size: Point(10, 20, 30))
        let plain = try Self.mesh(box)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let meshFile = directory.appendingPathComponent("mesh.bin")
        try Self.wireFormat(plain).write(to: meshFile)
        let helper = directory.appendingPathComponent("helper.sh")
        try Data("#!/bin/sh\nexec /bin/cat '\(meshFile.path)'\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let source = Data("""
            ISO-10303-21;
            HEADER;
            FILE_NAME('part','2020-01-01T00:00:00',('A. Person'),('Acme Org'),'Pre 1.0','Example CAD 9.1','Unknown');
            FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF { 1 0 10303 442 1 1 4 }'));
            ENDSEC;
            DATA;
            ENDSEC;
            END-ISO-10303-21;
            """.utf8)
        let adapter = CADFormatAdapter(kind: .step, transport: .worker(helper))
        let mesh = try adapter.parse(FileBytes(data: source), context: Self.context())
        #expect(mesh.positions == plain.positions && mesh.indices == plain.indices && mesh.bounds == plain.bounds)
        expectClose(mesh.measurements?.surfaceAreaSquareMillimetres, 2200)
        expectClose(mesh.measurements?.volumeCubicMillimetres, 6000)
        #expect(mesh.measurements?.bodyCount == 1)
        #expect(mesh.headerFacts == CADHeaderFacts(schema: .stepAP242, originatingSystem: "Example CAD 9.1"))
        #expect(!String(describing: mesh.headerFacts).contains("Person") && !String(describing: mesh.headerFacts).contains("Acme"))
    }

    /// The importer's private numeric protocol, so the decoder path is exercised with the same bytes.
    static func wireFormat(_ mesh: PreviewMesh) -> Data {
        var data = Data("PRVCAD01".utf8)
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func f64(_ value: Double) { var v = value.bitPattern.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        [UInt32(mesh.positions.count), UInt32(mesh.indices.count), UInt32(mesh.faceCount), 1].forEach(u32)
        [mesh.bounds.minimum.x, mesh.bounds.minimum.y, mesh.bounds.minimum.z,
         mesh.bounds.maximum.x, mesh.bounds.maximum.y, mesh.bounds.maximum.z].forEach(f64)
        for (position, normal) in zip(mesh.positions, mesh.normals) {
            [position.x, position.y, position.z, normal.x, normal.y, normal.z].forEach { u32($0.bitPattern) }
        }
        mesh.indices.forEach(u32)
        return data
    }
}
