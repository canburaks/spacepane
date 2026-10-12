import Foundation
import Testing
@testable import PreviewCADFormats
import PreviewContracts

/// The unit a CAD model's extents rest on (decision 027, Q-11): the importer's header word, and the IGES header.
@Suite("CAD declared unit")
struct GeometryCADUnitTests {
    /// The importer's wire format with a chosen fourth header word.
    private func wire(units: UInt32) -> Data {
        var data = Data("PRVCAD01".utf8)
        func u32(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func f64(_ n: Double) { var v = n.bitPattern.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        [3, 3, 1, units].forEach { u32($0) }
        [0, 0, 0, 10, 10, 0].forEach { f64(Double($0)) }
        for p: [Float] in [[-1, -1, 0], [1, -1, 0], [0, 1, 0]] { (p + [0, 0, 1]).forEach { u32($0.bitPattern) } }
        [0, 1, 2].forEach { u32(UInt32($0)) }
        return data
    }

    private func decode(units: UInt32) throws -> PreviewMesh {
        try CADMeshDecoder.decode(wire(units: units), context: RequestContext(budget: GeometryLimits.requestBudget))
    }

    @Test func theWordTheImporterWroteBeforeTheFieldExistedMeansNoDeclaredUnit() throws {
        #expect(try decode(units: 1).unitProvenance == .assumedMillimetres)
    }

    @Test(arguments: [(UInt32(0x101), GeometryLengthUnit.micrometre), (UInt32(0x201), .millimetre), (UInt32(0x301), .centimetre),
                      (UInt32(0x401), .metre), (UInt32(0x501), .inch), (UInt32(0x601), .foot)])
    func theSecondByteNamesTheUnitTheFileDeclared(units: UInt32, expected: GeometryLengthUnit) throws {
        #expect(try decode(units: units).unitProvenance == .declared(expected), "0x\(String(units, radix: 16))")
    }

    @Test func anyOtherWordIsMalformedSoANewWriterCannotBeMisreadAsAnOldOne() {
        // Normalization other than millimetres, an unknown unit code, and bits in the reserved upper half.
        let rejected: [UInt32] = [0, 2, 0x202, 0x701, 0xFF01, 0x1_0001, 0x8000_0001]
        for units in rejected {
            #expect(throws: PreviewFailure.malformedDocument, "0x\(String(units, radix: 16))") { try decode(units: units) }
        }
    }

    @Test func theDecoderTableIsTheDocumentedOneAndNotTheDeclarationOrderOfTheEnum() {
        let table: [(UInt32, GeometryUnitProvenance?)] = [
            (0, .assumedMillimetres), (1, .declared(.micrometre)), (2, .declared(.millimetre)), (3, .declared(.centimetre)),
            (4, .declared(.metre)), (5, .declared(.inch)), (6, .declared(.foot)), (7, nil), (255, nil)]
        for (code, expected) in table {
            #expect(CADMeshDecoder.declaredUnitProvenance(code: code) == expected, "code \(code)")
        }
    }

    @Test func igesHeaderUnitsMapOntoTheContractAndOthersAreLeftToTheImportersConversion() {
        let named: [(String, GeometryLengthUnit)] = [("UM", .micrometre), ("MM", .millimetre), ("CM", .centimetre),
                                                     ("M", .metre), ("IN", .inch), ("FT", .foot)]
        for (code, unit) in named { #expect(CADUnitProvenance.igesUnit(code) == unit, "\(code)") }
        for code in ["MI", "KM", "MIL", "UIN", "INCH", "mm", "", "furlong"] {
            #expect(CADUnitProvenance.igesUnit(code) == nil, "\(code)")
        }
        #expect(CADUnitProvenance.igesUnit(nil) == nil)
    }

    @Test func aReportedUnitWinsAndOnlyAnIgesHeaderMayUpgradeAnAssumption() {
        let inches = CADHeaderFacts(schema: .iges(.version5_3), sourceUnit: "IN")
        // The importer said nothing: an IGES header's own unit names it; STEP has no header unit.
        #expect(CADUnitProvenance.resolve(reported: .assumedMillimetres, kind: .iges, headerFacts: inches) == .declared(.inch))
        #expect(CADUnitProvenance.resolve(reported: .assumedMillimetres, kind: .step, headerFacts: inches) == .assumedMillimetres)
        // The importer said: its word stands, whatever the header says.
        #expect(CADUnitProvenance.resolve(reported: .declared(.metre), kind: .iges, headerFacts: inches) == .declared(.metre))
        // No header, an unmapped unit and a missing unit change nothing.
        #expect(CADUnitProvenance.resolve(reported: .assumedMillimetres, kind: .iges, headerFacts: nil) == .assumedMillimetres)
        let miles = CADHeaderFacts(schema: .iges(.version5_3), sourceUnit: "MI")
        #expect(CADUnitProvenance.resolve(reported: .assumedMillimetres, kind: .iges, headerFacts: miles) == .assumedMillimetres)
        let none = CADHeaderFacts(schema: .iges(.version5_3))
        #expect(CADUnitProvenance.resolve(reported: .assumedMillimetres, kind: .iges, headerFacts: none) == .assumedMillimetres)
    }
}
