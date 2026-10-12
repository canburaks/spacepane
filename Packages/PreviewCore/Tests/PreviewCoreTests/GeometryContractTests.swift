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

    @Test func headerFactsOnlyCarryShortTechnicalSystemNames() {
        #expect(CADHeaderFacts().isEmpty)
        #expect(CADHeaderFacts(originatingSystem: "Open CASCADE 7.9").originatingSystem == "Open CASCADE 7.9")
        #expect(CADHeaderFacts(originatingSystem: "A.B_C (x)/1+2-3").originatingSystem == "A.B_C (x)/1+2-3")
        let unsafe = ["Jane Doe <jane@example.com>", "C:\\Users\\jane", "name;drop", "caf\u{00E9}", "tab\there", "line\nbreak",
                      "emoji \u{1F600}", String(repeating: "x", count: CADHeaderFacts.maximumSystemNameLength + 1), ""]
        for value in unsafe { #expect(CADHeaderFacts(originatingSystem: value).originatingSystem == nil, "\(value.debugDescription)") }
        #expect(CADHeaderFacts(originatingSystem: String(repeating: "x", count: CADHeaderFacts.maximumSystemNameLength))
            .originatingSystem?.count == CADHeaderFacts.maximumSystemNameLength)
        #expect(!CADHeaderFacts(schema: .stepAP242).isEmpty)
        #expect(CADHeaderFacts(sourceUnit: "MM").sourceUnit == "MM")
        #expect(CADHeaderFacts(sourceUnit: "far too long unit name").sourceUnit == nil)
    }

    @Test func schemaDisplayNamesAreTechnicalIdentifiers() {
        #expect([CADSchema.stepAP203, .stepAP203Edition2, .stepAP214, .stepAP242].map(\.displayName) == ["AP203", "AP203e2", "AP214", "AP242"])
        #expect(IGESRevision.allCases.map { CADSchema.iges($0).displayName }
            == ["IGES 1.0", "IGES 2.0", "IGES 3.0", "IGES 4.0", "IGES 5.0", "IGES 5.1", "IGES 5.2", "IGES 5.3"])
        #expect(IGESRevision(rawValue: 11) == .version5_3 && IGESRevision(rawValue: 2) == nil)
    }

    @Test func attachingFactsKeepsValidatedGeometryAndIdentityOfTheArrays() throws {
        let mesh = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        #expect(mesh.measurements == nil && mesh.headerFacts == nil)
        let measurements = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 50, volumeCubicMillimetres: nil, bodyCount: 1))
        let facts = CADHeaderFacts(schema: .stepAP214, originatingSystem: "Example CAD")
        let enriched = mesh.attaching(measurements: measurements, headerFacts: facts)
        #expect(enriched.positions == mesh.positions && enriched.normals == mesh.normals && enriched.indices == mesh.indices)
        #expect(enriched.bounds == mesh.bounds && enriched.faceCount == mesh.faceCount)
        #expect(enriched.outputByteCount == mesh.outputByteCount)
        #expect(enriched.measurements == measurements && enriched.headerFacts == facts)
        #expect(enriched != mesh) // The facts are part of the value.
        #expect(enriched.attaching(measurements: nil, headerFacts: nil) == mesh)
        // The convenience initializer carries the same facts and still validates the geometry.
        let direct = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1,
                                     measurements: measurements, headerFacts: facts)
        #expect(direct == enriched)
        #expect(throws: PreviewFailure.malformedDocument) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 9], bounds: bounds, faceCount: 1,
                            measurements: measurements, headerFacts: facts)
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
