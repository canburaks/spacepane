import Foundation
import Testing
import PreviewContracts

@Suite("Geometry safety boundary")
struct GeometryContractTests {
    private let positions: [SIMD3<Float>] = [.init(-1, -1, 0), .init(1, -1, 0), .init(0, 1, 0)]
    private let normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: 3)
    private let bounds = GeometryBounds(minimum: .init(0, 0, 0), maximum: .init(10, 10, 0))

    @Test func rejectsInvalidIndicesNonfiniteCoordinatesAndEmptyGeometry() throws {
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 3], bounds: bounds, faceCount: 1)
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: [.init(.nan, 0, 0), positions[1], positions[2]], normals: normals,
                            indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: [], normals: [], indices: [], bounds: bounds, faceCount: 0)
        }
    }

    @Test func rejectsInconsistentNormalsBoundsAndTriangleShape() throws {
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: [.zero, .zero, .zero], indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1], bounds: bounds, faceCount: 1)
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2],
                            bounds: .init(minimum: .init(2, 0, 0), maximum: .init(1, 1, 1)), faceCount: 1)
        }
    }

    @Test func measurementsRejectNonFiniteNegativeAndEmptyValues() {
        #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 252, volumeCubicMillimetres: 216, bodyCount: 1) != nil)
        #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 0, volumeCubicMillimetres: nil, bodyCount: 2) != nil)
        for area in [Double.nan, .infinity, -1] {
            #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: area, volumeCubicMillimetres: nil, bodyCount: 1) == nil)
        }
        for volume in [Double.nan, .infinity, -0.5] {
            #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: volume, bodyCount: 1) == nil)
        }
        #expect(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: 1, bodyCount: 0) == nil)
    }

    @Test func attachingFactsKeepsValidatedGeometryAndIdentityOfTheArrays() throws {
        let mesh = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        #expect(mesh.measurements == nil)
        let measurements = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 50, volumeCubicMillimetres: nil, bodyCount: 1))
        let enriched = mesh.attaching(measurements: measurements)
        #expect(enriched.positions == mesh.positions && enriched.normals == mesh.normals && enriched.indices == mesh.indices)
        #expect(enriched.bounds == mesh.bounds && enriched.faceCount == mesh.faceCount)
        #expect(enriched.outputByteCount == mesh.outputByteCount)
        #expect(enriched.measurements == measurements)
        #expect(enriched != mesh) // The facts are part of the value.
        #expect(enriched.attaching(measurements: nil) == mesh)
        // The convenience initializer carries the same facts and still validates the geometry.
        let direct = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1,
                                     measurements: measurements)
        #expect(direct == enriched)
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 9], bounds: bounds, faceCount: 1,
                            measurements: measurements)
        }
    }

    @Test func preservesValidatedGeometryAndUsesStablePresentationIdentity() throws {
        let mesh = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        let value = GeometryPresentation(formatID: FormatID(rawValue: "test.geometry"), mesh: mesh, byteCount: 128)
        #expect(value == value)
        #expect(value != GeometryPresentation(formatID: value.formatID, mesh: mesh, byteCount: 128))
        #expect(value.mesh.positions == positions)
        #expect(value.mesh.bounds == bounds)
    }
}
