import Foundation
import Testing
import PreviewCADFormats

/// The STEP and IGES header facts moved from PreviewContracts to the CAD module on 2026-10-24 (decision 031); these
/// checks moved with them from GeometryContractTests.
struct CADHeaderFactsTests {
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
}
