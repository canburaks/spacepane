import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// The "if printed solid in PLA" estimate: shown only when the volume is known, computed from the volume at 1.24 g/cm³
/// and 1.75 mm filament, and worded as conditional on millimetres when the model's unit is undeclared (decision 029).
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

    @Test func noEstimateWithoutAKnownPositiveVolume() throws {
        for provenance in [GeometryUnitProvenance.declared(.millimetre), .assumedMillimetres, .undeclared] {
            #expect(GeometryPrintEstimate(try measurements(volume: nil, provenance)) == nil, "\(provenance)")
            #expect(GeometryPrintEstimate(try measurements(volume: 0, provenance)) == nil, "\(provenance)")
        }
    }

    @Test func anUndeclaredUnitGivesTheSameNumbersAsAConditionalEstimate() throws {
        // 10^6 mm³ again: the figures are those of millimetres, flagged as depending on that assumption.
        let conditional = try #require(GeometryPrintEstimate(try measurements(volume: 1_000_000, .undeclared)))
        expectClose(conditional.massGrams, 1_240)
        expectClose(conditional.filamentLengthMetres, 415.753_3, tolerance: 1e-5)
        #expect(conditional.isConditionalOnMillimetres)
        for provenance in [GeometryUnitProvenance.declared(.millimetre), .declared(.inch), .assumedMillimetres] {
            let plain = try #require(GeometryPrintEstimate(try measurements(volume: 1_000_000, provenance)))
            #expect(!plain.isConditionalOnMillimetres, "\(provenance)")
            expectClose(plain.massGrams, conditional.massGrams)
        }
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

    @Test func stlObjAndPlyGetAConditionalEstimateBecauseTheyDeclareNoUnit() throws {
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
        let all = [try measured(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, cube.triangles)),
                   try measured(OBJAdapter(), MeshFixtures.obj(cube.vertices, faces: quads)),
                   try measured(PLYAdapter(), MeshFixtures.plyASCII(cube.vertices, faces: quads))]
        for measurements in all {
            // A 10 mm cube if the numbers are millimetres: 1 cm³ is 1.24 g.
            let estimate = try #require(GeometryPrintEstimate(measurements))
            #expect(estimate.isConditionalOnMillimetres)
            expectClose(estimate.massGrams, 1.24, tolerance: 1e-5)
        }
    }

    @Test func aThreeMFEstimateIsNeverConditional() throws {
        for unit in ["centimeter", "millimeter", nil] {
            let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: cube.triangles, unit: unit)
            let estimate = try #require(GeometryPrintEstimate(try measured(ThreeMFAdapter(), data)))
            #expect(!estimate.isConditionalOnMillimetres, "\(unit ?? "no unit")")
        }
    }

    @Test func anOpenModelGetsNoEstimateWhateverItsUnit() throws {
        let triangles = Array(cube.triangles.dropFirst(2))
        let data = MeshFixtures.threeMF(vertices: cube.vertices, triangles: triangles, unit: "millimeter")
        #expect(GeometryPrintEstimate(try measured(ThreeMFAdapter(), data)) == nil)
        #expect(GeometryPrintEstimate(try measured(STLAdapter(), MeshFixtures.stlBinary(cube.vertices, triangles))) == nil)
    }
}
