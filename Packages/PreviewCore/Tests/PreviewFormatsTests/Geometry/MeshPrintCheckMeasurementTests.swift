import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats

/// The shared measurer's print-relevant counts (Mesh Print Check, decision 029), on synthetic STL fixtures read through
/// the real adapter, so the meshes are the ones the viewer gets. The cube has edge 10 mm: area 600 mm², volume 1,000 mm³.
@Suite("Mesh Print Check measurements")
struct MeshPrintCheckMeasurementTests {
    typealias Vertex = MeshFixtures.Vertex
    private let cube = MeshFixtures.cube(size: 10)

    private func mesh(_ vertices: [Vertex], _ triangles: [[Int]]) throws -> PreviewMesh {
        try STLAdapter().parse(FileBytes(data: MeshFixtures.stlASCII(vertices, triangles)), context: MeshFixtures.context)
    }

    private func measure(_ vertices: [Vertex], _ triangles: [[Int]]) throws -> GeometryMeasurements {
        try #require(try GeometryMeasurer.measure(try mesh(vertices, triangles), context: MeshFixtures.context))
    }

    private func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-5,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else { Issue.record("value unavailable", sourceLocation: sourceLocation); return }
        #expect(abs(actual - expected) <= expected * tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    @Test func aClosedCubeHasVolumeAndNoOpenOrNonManifoldEdges() throws {
        let measured = try measure(cube.vertices, cube.triangles)
        expectClose(measured.surfaceAreaSquareMillimetres, 600)
        expectClose(measured.volumeCubicMillimetres, 1_000)
        #expect(measured.bodyCount == 1)
        #expect(measured.openEdgeCount == 0)
        #expect(measured.nonManifoldEdgeCount == 0)
    }

    @Test func aBoxMissingOneFaceHasFourOpenEdgesAndNoVolume() throws {
        // The first quad is two triangles; without them the four edges of that face are used by one triangle each.
        let measured = try measure(cube.vertices, Array(cube.triangles.dropFirst(2)))
        expectClose(measured.surfaceAreaSquareMillimetres, 500)
        #expect(measured.volumeCubicMillimetres == nil)
        #expect(measured.openEdgeCount == 4)
        #expect(measured.nonManifoldEdgeCount == 0)
        #expect(measured.bodyCount == 1)
    }

    @Test func threeTrianglesSharingOneEdgeAreOneNonManifoldEdge() throws {
        let vertices = [Vertex(0, 0, 0), Vertex(10, 0, 0), Vertex(0, 10, 0), Vertex(0, 0, 10), Vertex(0, -10, 0)]
        let measured = try measure(vertices, [[0, 1, 2], [0, 1, 3], [0, 1, 4]])
        #expect(measured.nonManifoldEdgeCount == 1)
        // The three outer edges of each triangle are used once.
        #expect(measured.openEdgeCount == 6)
        #expect(measured.volumeCubicMillimetres == nil)
        #expect(measured.bodyCount == 1)
    }

    @Test func aFlippedFaceIsNotOpenEvenThoughTheVolumeIsUnknown() throws {
        // Both triangles of the face run the other way: every edge is still used twice, but not in opposite directions.
        var triangles = cube.triangles
        triangles[0] = [triangles[0][0], triangles[0][2], triangles[0][1]]
        triangles[1] = [triangles[1][0], triangles[1][2], triangles[1][1]]
        let measured = try measure(cube.vertices, triangles)
        #expect(measured.volumeCubicMillimetres == nil)
        #expect(measured.openEdgeCount == 0)
        #expect(measured.nonManifoldEdgeCount == 0)
    }

    @Test func twoCubesSharingAFaceKeepTheirVolumeAndCountTheSharedEdges() throws {
        // Two 4 mm cubes whose faces coincide at z = 4 weld into one surface. Each edge of the shared square is used by
        // four triangles (two per cube), and so is the diagonal both cubes triangulate the same way: five edges.
        let lower = MeshFixtures.cube(size: 4)
        let shifted = lower.vertices.map { Vertex($0.x, $0.y, $0.z + 4) }
        let vertices = lower.vertices + shifted
        let triangles = lower.triangles + lower.triangles.map { $0.map { $0 + lower.vertices.count } }
        let measured = try measure(vertices, triangles)
        expectClose(measured.volumeCubicMillimetres, 128)
        #expect(measured.nonManifoldEdgeCount == 5)
        #expect(measured.openEdgeCount == 0)
        #expect(measured.bodyCount == 1)
    }

    @Test func aTriangleCollapsedByWeldingAddsNoEdges() throws {
        // A vertex a millionth of a millimetre from a cube corner is a different vertex for the reader, so the sliver
        // survives it, but the measurer's weld merges the two and the collapsed triangle must add no edge.
        let vertices = cube.vertices + [Vertex(-5 + 1e-6, -5, -5)]
        let measured = try measure(vertices, cube.triangles + [[0, 8, 3]])
        expectClose(measured.volumeCubicMillimetres, 1_000)
        #expect(measured.openEdgeCount == 0 && measured.nonManifoldEdgeCount == 0)
        #expect(measured.bodyCount == 1)
    }

    @Test func theMovedMeasurerKeepsTheCADMeasurementNumbers() throws {
        // The numbers the CAD measurement suite asserts for a 12 x 6 x 3 mm box (area 252, volume 216), through the
        // package-wide measurer, now also with the new counts at zero.
        let box = MeshFixtures.cube(size: 2).vertices.map { Vertex($0.x * 6, $0.y * 3, $0.z * 1.5) }
        let measured = try measure(box, MeshFixtures.cube(size: 2).triangles)
        expectClose(measured.surfaceAreaSquareMillimetres, 252)
        expectClose(measured.volumeCubicMillimetres, 216)
        #expect(measured.bodyCount == 1 && measured.openEdgeCount == 0 && measured.nonManifoldEdgeCount == 0)
    }

    @Test func theNewCountsRejectNegativeValuesAndDefaultToZero() throws {
        #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: nil, bodyCount: 1,
                                     openEdgeCount: -1) == nil)
        #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: nil, bodyCount: 1,
                                     nonManifoldEdgeCount: -1) == nil)
        let plain = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: nil, bodyCount: 1))
        #expect(plain.openEdgeCount == 0 && plain.nonManifoldEdgeCount == 0)
        let counted = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: nil,
                                                        bodyCount: 1, openEdgeCount: 6, nonManifoldEdgeCount: 2))
        // Declaring the unit afterwards keeps every other value, the counts included.
        let declared = counted.declaring(unitProvenance: .declared(.centimetre))
        #expect(declared.openEdgeCount == 6 && declared.nonManifoldEdgeCount == 2)
        #expect(declared.unitProvenance == .declared(.centimetre))
    }

    // MARK: Cancellation

    @Test func cancellationAtTheFinalCheckpointOfAMeasurementPropagates() async throws {
        let source = try mesh(cube.vertices, cube.triangles)
        try await Self.expectCancelledAtFinalCheckpoint { context in _ = try GeometryMeasurer.measure(source, context: context) }
    }

    /// Runs `work` once, counting its checkpoints, then again in a task that cancels itself at the final one: the
    /// second run must end with `CancellationError` there. Placing the request at a checkpoint avoids racing a timer.
    static func expectCancelledAtFinalCheckpoint(sourceLocation: SourceLocation = #_sourceLocation,
                                                 _ work: @escaping @Sendable (RequestContext) throws -> Void) async throws {
        let counted = Mutex(0)
        var context = MeshFixtures.context
        context.checkpointObserver = { counted.withLock { $0 += 1 } }
        try work(context)
        let finalCheckpoint = counted.withLock { $0 }
        try #require(finalCheckpoint > 1, "The work has no checkpoint to cancel at", sourceLocation: sourceLocation)
        let observed = Mutex(0)
        let cancelled = await Task.detached { () -> Bool in
            var context = MeshFixtures.context
            context.checkpointObserver = {
                let count = observed.withLock { $0 += 1; return $0 }
                if count == finalCheckpoint { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { try work(context); return false } catch is CancellationError { return true } catch { return false }
        }.value
        #expect(cancelled, "The work completed despite cancellation at its final checkpoint", sourceLocation: sourceLocation)
        #expect(observed.withLock { $0 } == finalCheckpoint, sourceLocation: sourceLocation)
    }
}
