import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// The "if printed solid in PLA" estimate: shown only when the volume is known and the unit is declared or assumed
/// millimetres, computed from the volume at 1.24 g/cm³ and 1.75 mm filament (decision 029).
@Suite("Mesh Print Check estimate")
struct MeshPrintCheckEstimateTests {
    private func measurements(volume: Double?, _ provenance: GeometryUnitProvenance) throws -> GeometryMeasurements {
        try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: volume, bodyCount: 1,
                                          unitProvenance: provenance))
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) <= expected * tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    @Test func theConstantsAreTheStatedMaterialAndFilament() {
        #expect(GeometryPrintEstimate.plaDensityGramsPerCubicCentimetre == 1.24)
        #expect(GeometryPrintEstimate.filamentDiameterMillimetres == 1.75)
        // pi * 0.875^2 square millimetres.
        expectClose(GeometryPrintEstimate.filamentCrossSectionSquareMillimetres, 2.405_281_874_8, tolerance: 1e-9)
    }

    @Test func aLitreOfSolidPLAWeighsItsDensityTimesAThousandAndIsAFilamentLengthOfItsVolumeOverTheCrossSection() throws {
        // 1,000 cm³ = 10^6 mm³: 1,240 g, and 10^6 / 2.40528 mm = 415.75 m of filament.
        let estimate = try #require(GeometryPrintEstimate(try measurements(volume: 1_000_000, .declared(.millimetre))))
        expectClose(estimate.massGrams, 1_240)
        expectClose(estimate.filamentLengthMetres, 415.753_3, tolerance: 1e-5)
    }

    @Test func anAssumedMillimetreUnitIsEnough() throws {
        // A 10 mm cube: 1 cm³ is 1.24 g.
        let estimate = try #require(GeometryPrintEstimate(try measurements(volume: 1_000, .assumedMillimetres)))
        expectClose(estimate.massGrams, 1.24)
        expectClose(estimate.filamentLengthMetres, 0.415_753_3, tolerance: 1e-5)
    }

    @Test func noEstimateWithoutAKnownVolumeOrAKnownUnit() throws {
        #expect(GeometryPrintEstimate(try measurements(volume: nil, .declared(.millimetre))) == nil)
        #expect(GeometryPrintEstimate(try measurements(volume: 1_000, .undeclared)) == nil)
        #expect(GeometryPrintEstimate(try measurements(volume: 0, .declared(.millimetre))) == nil)
    }

    // MARK: Through the readers

    private let cube = MeshFixtures.cube(size: 10)

    private func measured(_ adapter: any GeometryFormatAdapter, _ data: Data) throws -> GeometryMeasurements {
        let mesh = try adapter.parse(FileBytes(data: data), context: MeshFixtures.context)
        return try #require(mesh.measurements)
    }

    @Test func aThreeMFInCentimetresEstimatesInTheDeclaredUnitsPhysicalSize() throws {
        // 10 cm cube = 1,000 cm³ = 1,240 g.
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: "centimeter")
        let estimate = try #require(GeometryPrintEstimate(try measured(ThreeMFAdapter(), data)))
        expectClose(estimate.massGrams, 1_240, tolerance: 1e-5)
        expectClose(estimate.filamentLengthMetres, 415.753_3, tolerance: 1e-5)
    }

    @Test func aThreeMFInInchesIsConvertedToMillimetresBeforeTheEstimate() throws {
        // A 10 inch cube is 1,000 in³ = 16,387.064 cm³.
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: "inch")
        let estimate = try #require(GeometryPrintEstimate(try measured(ThreeMFAdapter(), data)))
        expectClose(estimate.massGrams, 16_387.064 * 1.24, tolerance: 1e-5)
    }

    @Test func stlObjAndPlyGetNoEstimateBecauseTheyDeclareNoUnit() throws {
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
        let all = [try measured(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, cube.triangles)),
                   try measured(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: quads)),
                   try measured(PLYAdapter(), MeshFixtures.plyASCII(cube.vertices, faces: quads))]
        for measurements in all {
            #expect(measurements.volumeCubicMillimetres != nil)
            #expect(GeometryPrintEstimate(measurements) == nil)
        }
    }

    @Test func anOpenModelGetsNoEstimateEvenWithADeclaredUnit() throws {
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: Array(cube.triangles.dropFirst(2)), unit: "millimeter")
        #expect(GeometryPrintEstimate(try measured(ThreeMFAdapter(), data)) == nil)
    }
}
