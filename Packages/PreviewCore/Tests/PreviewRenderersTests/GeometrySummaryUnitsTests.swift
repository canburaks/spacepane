import Foundation
import PreviewContracts
import Testing
@testable import PreviewRenderers

@Suite("Geometry summary units and counts", .serialized)
@MainActor
struct GeometrySummaryUnitsTests {
    private func mesh(_ provenance: GeometryUnitProvenance, capped: Bool = false, measurements: GeometryMeasurements? = nil) throws -> PreviewMesh {
        try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)),
            faceCount: capped ? GeometryLimits.maximumFaces : 1, measurements: measurements,
            unitProvenance: provenance, faceCountIsCapped: capped)
    }

    private func measurements(_ provenance: GeometryUnitProvenance, area: Double = 2_200, volume: Double? = 6_000,
                              bodies: Int = 1) throws -> GeometryMeasurements {
        try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: area, volumeCubicMillimetres: volume,
                                          bodyCount: bodies, unitProvenance: provenance))
    }

    private func lines(_ mesh: PreviewMesh, language: String = "en") -> [String] {
        NativeGeometryPreviewView.summaryLines(for: mesh, locale: Locale(identifier: language), languagePreferences: [language])
    }

    @Test func aModelThatDeclaresNoUnitShowsPlainNumbersAndSaysSo() throws {
        let result = lines(try mesh(.undeclared))
        #expect(result == ["Faces: 1 · Triangles: 1 · 20 × 20 × 1 (unit not declared)"])
        #expect(!result[0].contains("mm"))
    }

    @Test func aModelInMillimetresShowsTheUnitWhetherDeclaredOrAssumed() throws {
        let expected = ["Faces: 1 · Triangles: 1 · 20 × 20 × 1 mm"]
        #expect(lines(try mesh(.declared(.millimetre))) == expected)
        #expect(lines(try mesh(.assumedMillimetres)) == expected)
        // Foundation has no cubic micrometre, so a model declared in micrometres is shown in millimetres.
        #expect(lines(try mesh(.declared(.micrometre))) == expected)
    }

    @Test func aDeclaredUnitConvertsTheMillimetreExtentsAndNeverShowsMillimetres() throws {
        // The importers store 20 mm x 20 mm x 1 mm.
        let expectations: [(GeometryLengthUnit, String)] = [
            (.centimetre, "Faces: 1 · Triangles: 1 · 2 × 2 × 0.1 "),
            (.metre, "Faces: 1 · Triangles: 1 · 0.02 × 0.02 × 0.001 "),
            (.inch, "Faces: 1 · Triangles: 1 · 0.787 × 0.787 × 0.039 "),
            (.foot, "Faces: 1 · Triangles: 1 · 0.066 × 0.066 × 0.003 ")]
        for (unit, prefix) in expectations {
            let line = lines(try mesh(.declared(unit)))[0]
            #expect(line.hasPrefix(prefix), "\(unit): \(line)")
            // A symbol follows the numbers, and it is not the millimetre of the stored values.
            #expect(line.count > prefix.count && !line.contains("mm") && !line.contains("%"), "\(unit): \(line)")
        }
    }

    @Test func lengthSymbolsComeFromTheLocaleNotFromALiteral() throws {
        let russian = lines(try mesh(.declared(.millimetre)), language: "ru")[0]
        #expect(russian.hasPrefix("Грани: 1 · Треугольники: 1 · 20 × 20 × 1 "), "\(russian)")
        #expect(russian.contains("мм") && !russian.contains("mm"), "\(russian)")
        let german = lines(try mesh(.declared(.millimetre)), language: "de")[0]
        #expect(german.hasPrefix("Flächen: 1 · Dreiecke: 1 · 20 × 20 × 1 ") && german.contains("mm"), "\(german)")
    }

    @Test func aFaceCountThatStoppedAtTheCapReadsAsAtLeast() throws {
        let english = lines(try mesh(.undeclared, capped: true))[0]
        #expect(english.hasPrefix("Faces: 100,000+ · Triangles: 1 · "), "\(english)")
        let german = lines(try mesh(.undeclared, capped: true), language: "de")[0]
        #expect(german.hasPrefix("Flächen: 100.000+ · Dreiecke: 1 · "), "\(german)")
        // An exact count, even one at the cap's neighbourhood, never carries the plus sign.
        #expect(!lines(try mesh(.undeclared))[0].contains("+"))
    }

    @Test func measurementLinesCarryTheUnitsOfTheirOwnProvenance() throws {
        let solid = lines(try mesh(.declared(.millimetre), measurements: try measurements(.declared(.millimetre))))
        #expect(solid.count == 2)
        #expect(solid[1] == "Surface area: 2,200 mm² · Volume: 6,000 mm³ · Bodies: 1")
        let open = lines(try mesh(.assumedMillimetres,
            measurements: try measurements(.assumedMillimetres, area: 180, volume: nil, bodies: 3)))
        #expect(open[1] == "Surface area: 180 mm² · Volume unavailable (surface not closed) · Bodies: 3")
        // No declared unit: plain numbers, because the summary line above already says the unit is not declared.
        let unitless = lines(try mesh(.undeclared, measurements: try measurements(.undeclared)))
        #expect(unitless[1] == "Surface area: 2,200 · Volume: 6,000 · Bodies: 1")
        let openUnitless = lines(try mesh(.undeclared,
            measurements: try measurements(.undeclared, area: 180, volume: nil, bodies: 3)))
        #expect(openUnitless[1] == "Surface area: 180 · Volume unavailable (surface not closed) · Bodies: 3")
    }

    @Test func areasAndVolumesAreConvertedByTheSquareAndTheCubeOfTheUnit() throws {
        // 645.16 mm² is one square inch and 16,387.064 mm³ one cubic inch; 2,200 mm² is 22 cm² and 6,000 mm³ is 6 cm³.
        let inch = lines(try mesh(.declared(.inch),
            measurements: try measurements(.declared(.inch), area: 645.16, volume: 16_387.064)))[1]
        #expect(inch.hasPrefix("Surface area: 1 ") && inch.contains(" · Volume: 1 ") && inch.hasSuffix(" · Bodies: 1"), "\(inch)")
        #expect(!inch.contains("mm"), "\(inch)")
        let centimetre = lines(try mesh(.declared(.centimetre), measurements: try measurements(.declared(.centimetre))))[1]
        #expect(centimetre.hasPrefix("Surface area: 22 ") && centimetre.contains(" · Volume: 6 "), "\(centimetre)")
        #expect(!centimetre.contains("mm"), "\(centimetre)")
    }

    @Test func theMeasurementsOwnProvenanceDecidesItsLine() throws {
        // A mesh in millimetres whose measurements declare nothing prints plain numbers on the measurement line only.
        let result = lines(try mesh(.declared(.millimetre), measurements: try measurements(.undeclared)))
        #expect(result[0].hasSuffix(" mm") && result[1] == "Surface area: 2,200 · Volume: 6,000 · Bodies: 1")
    }

    @Test func aUnitIsKnownOnlyWhenTheModelStatesOne() {
        #expect(GeometrySummaryUnits(.undeclared) == nil)
        #expect(GeometrySummaryUnits(.assumedMillimetres)?.millimetresPerUnit == 1)
        let factors: [(GeometryLengthUnit, Double)] = [(.micrometre, 1), (.millimetre, 1), (.centimetre, 10),
                                                       (.metre, 1_000), (.inch, 25.4), (.foot, 304.8)]
        for (unit, factor) in factors {
            #expect(GeometrySummaryUnits(.declared(unit))?.millimetresPerUnit == factor, "\(unit)")
        }
    }

    @Test(arguments: ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"])
    func everyLanguageCompletesEveryTemplate(language: String) throws {
        for provenance in [GeometryUnitProvenance.undeclared, .assumedMillimetres, .declared(.inch)] {
            for capped in [false, true] {
                for isSolid in [true, false] {
                    let measured = try measurements(provenance, volume: isSolid ? 6_000 : nil, bodies: 2)
                    let result = lines(try mesh(provenance, capped: capped, measurements: measured),
                                       language: language)
                    #expect(result.count == 2, "\(language)")
                    for line in result {
                        #expect(!line.isEmpty && !line.contains("%") && !line.contains("geometry."), "\(language): \(line)")
                    }
                }
            }
        }
    }
}
