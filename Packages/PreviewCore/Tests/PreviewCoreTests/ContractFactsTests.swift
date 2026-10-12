import Foundation
import Testing
import PreviewContracts

@Suite("Contract facts and failure cases")
struct ContractFactsTests {
    @Test func factsKeepPriorityOrderAndDensityCounts() {
        let facts = PresentationFacts([.lines(3), .size(10), .encoding(.utf8), .nodes(4), .records(2, .cues)])
        #expect(facts.shown(compact: true) == [.lines(3), .size(10)])
        #expect(facts.shown(compact: false).count == PresentationFacts.regularCount)
        #expect(PresentationFacts.none.isEmpty)
        #expect(!facts.isEmpty)
    }

    @Test func measurementsDefaultToAnUndeclaredUnit() throws {
        let measurements = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: nil, bodyCount: 1))
        #expect(measurements.unitProvenance == .undeclared)
        let declared = try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: 1, volumeCubicMillimetres: 2,
                                                         bodyCount: 1, unitProvenance: .declared(.inch)))
        #expect(declared.unitProvenance == .declared(.inch))
        #expect(GeometryLengthUnit.inch.millimetres == 25.4)
        #expect(GeometryLengthUnit.metre.millimetres == 1_000)
    }

    @Test func theNewFailureCasesAreDistinct() {
        #expect(PreviewFailure.unsupportedVariant != .unsupportedFormat)
        #expect(PreviewFailure.geometryTooComplex != .tooManyNodes)
    }
}
