import Foundation
import Testing
import PreviewContracts

@Suite("Geometry provenance on the mesh contract")
struct GeometryProvenanceContractTests {
    private let positions: [SIMD3<Float>] = [.init(-1, -1, 0), .init(1, -1, 0), .init(0, 1, 0)]
    private let normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: 3)
    private let bounds = GeometryBounds(minimum: .init(0, 0, 0), maximum: .init(10, 10, 0))

    private func mesh(unit: GeometryUnitProvenance = .undeclared, faceCount: Int = 1, capped: Bool = false) throws -> PreviewMesh {
        try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: faceCount,
                        unitProvenance: unit, faceCountIsCapped: capped)
    }

    @Test func aMeshThatSaysNothingDeclaresNoUnitAndHasAnExactFaceCount() throws {
        let plain = try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds, faceCount: 1)
        #expect(plain.unitProvenance == .undeclared && !plain.faceCountIsCapped)
    }

    @Test func provenanceAndTheCappedFlagAreCarriedAndAreAPartOfTheValue() throws {
        let declared = try mesh(unit: .declared(.inch))
        #expect(declared.unitProvenance == .declared(.inch))
        #expect(declared != (try mesh(unit: .undeclared)))
        let capped = try mesh(faceCount: GeometryLimits.maximumFaces, capped: true)
        #expect(capped.faceCountIsCapped && capped.faceCount == GeometryLimits.maximumFaces)
        #expect(capped != (try mesh(faceCount: GeometryLimits.maximumFaces, capped: false)))
    }

    @Test func attachingFactsKeepsTheProvenanceAndTheCappedFlagUnlessTheCallerReplacesTheProvenance() throws {
        let source = try mesh(unit: .assumedMillimetres, faceCount: GeometryLimits.maximumFaces, capped: true)
        let measurements = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 50, volumeCubicMillimetres: nil, bodyCount: 1))
        let kept = source.attaching(measurements: measurements, headerFacts: nil)
        #expect(kept.unitProvenance == .assumedMillimetres && kept.faceCountIsCapped)
        #expect(kept.attaching(measurements: nil, headerFacts: nil) == source)
        let replaced = source.attaching(measurements: measurements, headerFacts: nil, unitProvenance: .declared(.foot))
        #expect(replaced.unitProvenance == .declared(.foot) && replaced.faceCountIsCapped)
        #expect(replaced.positions == source.positions && replaced.indices == source.indices)
    }

    @Test func measurementsCanBeRedeclaredWithoutValidatingThemAgain() throws {
        let measurements = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 252, volumeCubicMillimetres: 216, bodyCount: 2))
        #expect(measurements.unitProvenance == .undeclared)
        let declared = measurements.declaring(unitProvenance: .declared(.centimetre))
        #expect(declared.unitProvenance == .declared(.centimetre))
        #expect(declared.surfaceAreaSquareMillimetres == 252 && declared.volumeCubicMillimetres == 216 && declared.bodyCount == 2)
        #expect(declared.declaring(unitProvenance: .undeclared) == measurements)
    }

    @Test func aCappedCountIsOnlyValidAtTheCap() {
        #expect(throws: PreviewFailure.malformedDocument) { try mesh(faceCount: 10, capped: true) }
        #expect(throws: PreviewFailure.malformedDocument) { try mesh(faceCount: GeometryLimits.maximumFaces - 1, capped: true) }
    }

    @Test func aMeshBeyondTheContractsCeilingsFailsAsTooComplexNotAsTooLarge() throws {
        #expect(throws: PreviewFailure.geometryTooComplex) {
            try PreviewMesh(positions: positions, normals: normals, indices: [0, 1, 2], bounds: bounds,
                            faceCount: GeometryLimits.maximumFaces + 1)
        }
        let tooManyIndices = [UInt32](repeating: 0, count: GeometryLimits.maximumIndices + 3)
        #expect(throws: PreviewFailure.geometryTooComplex) {
            try PreviewMesh(positions: positions, normals: normals, indices: tooManyIndices, bounds: bounds, faceCount: 1)
        }
        // The edge case at the ceiling itself is accepted.
        #expect(try mesh(faceCount: GeometryLimits.maximumFaces).faceCount == GeometryLimits.maximumFaces)
    }
}
