import Foundation
import Testing
@testable import PreviewCADFormats
import PreviewContracts

@Suite("CAD header facts") struct CADHeaderReaderTests {
    // Verbatim headers of the synthetic Native/CADWorker/Tests/Fixtures/box.* files.
    static let boxStepHeader = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('Open CASCADE Model'),'2;1');
        FILE_NAME('synthetic','2000-01-01T00:00:00',('synthetic'),('synthetic'),
          'Open CASCADE STEP processor 7.9','Open CASCADE 7.9','Unknown');
        FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));
        ENDSEC;
        DATA;
        #1 = APPLICATION_PROTOCOL_DEFINITION('international standard',
        """
    static let boxIGES = [
        String(repeating: " ", count: 72) + "S0000001",
        ",,31HOpen CASCADE IGES processor 7.9,14Hsynthetic.iges,".padding(toLength: 72, withPad: " ", startingAt: 0) + "G0000001",
        "16HOpen CASCADE 7.9,31HOpen CASCADE IGES processor 7.9,32,308,15,308,15,".padding(toLength: 72, withPad: " ", startingAt: 0) + "G0000002",
        ",1.,2,2HMM,1,0.01,15H20000101.000000,1E-07,30.,9Hsynthetic,9Hsynthetic, ".padding(toLength: 72, withPad: " ", startingAt: 0) + "G0000003",
        "11,0,15H20000101.000000,;".padding(toLength: 72, withPad: " ", startingAt: 0) + "G0000004",
        "     402       1       0       0       0       0       0       000000000D0000001"
    ].joined(separator: "\n") + "\n"

    static func facts(_ kind: CADFileKind, _ text: String) -> CADHeaderFacts? {
        CADHeaderReader.facts(kind: kind, data: Data(text.utf8))
    }
    /// A STEP header with only the entities under test.
    static func step(name: String = "FILE_NAME('p','2020',('Jane Doe'),('Acme Corp'),'Translator 1.0','CAD System 2.0','')",
                     schema: String = "FILE_SCHEMA(('AUTOMOTIVE_DESIGN'))") -> String {
        "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\n\(name);\n\(schema);\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n"
    }

    // MARK: Real fixture text

    @Test func stepFixtureHeaderGivesAP214AndTheOriginatingSystem() {
        let facts = Self.facts(.step, Self.boxStepHeader)
        #expect(facts?.schema == .stepAP214)
        #expect(facts?.originatingSystem == "Open CASCADE 7.9") // The sixth argument, not the preprocessor.
        #expect(facts?.schema?.displayName == "AP214")
    }

    @Test func igesFixtureHeaderGivesRevisionSystemAndUnit() {
        let facts = Self.facts(.iges, Self.boxIGES)
        #expect(facts?.schema == .iges(.version5_3))
        #expect(facts?.schema?.displayName == "IGES 5.3")
        #expect(facts?.originatingSystem == "Open CASCADE 7.9") // Native system ID (parameter 5).
        #expect(facts?.sourceUnit == "MM")
    }

    @Test func theSyntheticFixtureFilesOnDiskAgree() throws {
        for (name, kind) in [("box.step", CADFileKind.step), ("box.iges", .iges)] {
            let data = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("Native/CADWorker/Tests/Fixtures/" + name))
            let facts = try #require(CADHeaderReader.facts(kind: kind, data: data))
            #expect(facts.originatingSystem == "Open CASCADE 7.9")
            #expect(facts.schema == (kind == .step ? .stepAP214 : .iges(.version5_3)))
        }
    }
    /// This file lives five directories below the repository root.
    static var repositoryRoot: URL {
        (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
    }

    // MARK: STEP schemas and systems

    @Test(arguments: [
        ("CONFIG_CONTROL_DESIGN", CADSchema.stepAP203),
        ("config_control_design", .stepAP203),
        ("AP203_CONFIGURATION_CONTROLLED_3D_DESIGN_OF_MECHANICAL_PARTS_AND_ASSEMBLIES_MIM_LF { 1 0 10303 403 3 1 4 }", .stepAP203Edition2),
        ("AUTOMOTIVE_DESIGN", .stepAP214),
        ("AUTOMOTIVE_DESIGN_CC2 { 1 2 840 10303 214 -1 1 5 4 }", .stepAP214),
        ("AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF { 1 0 10303 442 1 1 4 }", .stepAP242),
        ("AP242_MANAGED_MODEL_BASED_3D_ENGINEERING { 1 0 10303 442 3 1 4 }", .stepAP242)
    ]) func knownSchemasMapToTheirApplicationProtocol(identifier: String, expected: CADSchema) {
        #expect(Self.facts(.step, Self.step(schema: "FILE_SCHEMA(('\(identifier)'))"))?.schema == expected)
    }

    @Test func unknownSchemasAreOmittedButTheSystemIsStillRead() {
        let facts = Self.facts(.step, Self.step(schema: "FILE_SCHEMA(('INTEGRATED_CNC_SCHEMA'))"))
        #expect(facts?.schema == nil)
        #expect(facts?.originatingSystem == "CAD System 2.0")
        #expect(Self.facts(.step, Self.step(name: "FILE_NAME('p','t',(''),(''),'','','')",
            schema: "FILE_SCHEMA(('SOMETHING_ELSE'))")) == nil)
    }

    @Test func aRecognizedSchemaIsFoundAmongSeveralDeclared() {
        let facts = Self.facts(.step, Self.step(schema: "FILE_SCHEMA(('UNKNOWN_ONE','CONFIG_CONTROL_DESIGN'))"))
        #expect(facts?.schema == .stepAP203)
    }

    @Test func theOriginatingSystemFallsBackToThePreprocessorOnlyWhenBlank() {
        func system(_ fifth: String, _ sixth: String) -> String? {
            Self.facts(.step, Self.step(name: "FILE_NAME('p','t',('a'),('o'),'\(fifth)','\(sixth)','')"))?.originatingSystem
        }
        #expect(system("Translator 1.0", "CAD System 2.0") == "CAD System 2.0")
        #expect(system("Translator 1.0", "") == "Translator 1.0")
        #expect(system("Translator 1.0", "Unknown") == "Translator 1.0")
        #expect(system("", "") == nil)
        // An unsafe sixth argument is omitted outright rather than replaced by another field.
        #expect(system("Translator 1.0", "Bad@Name") == nil)
    }

    @Test func lexicalVariantsAreAccepted() {
        let text = """
            /* leading comment with FILE_NAME('x','y',('z'),('w'),'a','b','c'); inside */
            ISO-10303-21;
            header ;
            /* FILE_SCHEMA(('CONFIG_CONTROL_DESIGN')); */
            file_name
              ( 'p' , 't' , ( 'a' ) , ( 'o' ) , 'Pre' , 'Maker''s CAD 3' , '' ) ;
            FILE_SCHEMA ( ( 'AUTOMOTIVE_DESIGN' ) ) ;
            ENDSEC;
            """
        let facts = Self.facts(.step, text)
        #expect(facts?.schema == .stepAP214) // The commented-out schema is ignored.
        #expect(facts?.originatingSystem == nil) // The apostrophe is outside the safe alphabet.
        let plain = Self.facts(.step, text.replacingOccurrences(of: "Maker''s CAD 3", with: "Maker CAD 3"))
        #expect(plain?.originatingSystem == "Maker CAD 3")
    }

    // MARK: Privacy

    @Test func authorOrganizationFileNameAndTimestampsAreNeverRead() {
        let secrets = ["Jane Q. Doe", "Acme Aerospace Ltd", "secret-project-final.step", "2031-02-03T04:05:06", "jane@example.com"]
        let name = "FILE_NAME('\(secrets[2])','\(secrets[3])',('\(secrets[0])','\(secrets[4])'),('\(secrets[1])'),'Translator 1.0','CAD System 2.0','\(secrets[0])')"
        let facts = Self.facts(.step, Self.step(name: name))
        let rendered = String(describing: facts)
        for secret in secrets { #expect(!rendered.contains(secret)) }
        #expect(facts?.originatingSystem == "CAD System 2.0")
        // IGES: product ID (3), file name (4), date (18), author (21) and organization (22) are skipped unread.
        // "synthetic" and "SecretNam" have equal length, so the Hollerith counts stay valid.
        let iges = Self.boxIGES.replacingOccurrences(of: "synthetic", with: "SecretNam")
        let igesFacts = Self.facts(.iges, iges)
        #expect(!String(describing: igesFacts).contains("SecretNam"))
        #expect(igesFacts?.originatingSystem == "Open CASCADE 7.9")
    }

    @Test(arguments: [
        "Bad@Name", "C:\\Users\\jane\\cad", "Jane's CAD", "Caf\u{00E9} CAD", "CAD<script>", "Name;Other", "\\X2\\00E9\\X0\\ CAD",
        String(repeating: "A", count: 65)
    ]) func unsafeOriginatingSystemsAreOmitted(value: String) {
        let facts = Self.facts(.step, Self.step(name: "FILE_NAME('p','t',('a'),('o'),'x','\(value.replacingOccurrences(of: "'", with: "''"))','')"))
        #expect(facts?.originatingSystem == nil)
    }

    @Test func safeAlphabetAndLengthBoundaryAreAccepted() {
        let boundary = String(repeating: "A", count: 64)
        #expect(Self.facts(.step, Self.step(name: "FILE_NAME('p','t',('a'),('o'),'x','\(boundary)','')"))?.originatingSystem == boundary)
        let punctuated = "SolidWorks 2020 (SP5.0)/x64+beta.1-2"
        #expect(CADHeaderFacts(originatingSystem: punctuated).originatingSystem == punctuated)
        #expect(CADHeaderFacts(originatingSystem: "snake_case").originatingSystem == "snake_case")
        #expect(CADHeaderFacts(originatingSystem: "star*name").originatingSystem == nil)
        #expect(CADHeaderFacts(originatingSystem: "   ").originatingSystem == nil)
        #expect(CADHeaderFacts(originatingSystem: "  Padded 1.0 ").originatingSystem == "Padded 1.0")
    }

    // MARK: Malformed, truncated and hostile headers

    @Test func emptyGarbageAndMissingSectionsYieldNothing() {
        #expect(CADHeaderReader.facts(kind: .step, data: Data()) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: Data()) == nil)
        #expect(Self.facts(.step, "not a STEP file at all") == nil)
        #expect(Self.facts(.step, "ISO-10303-21;\nDATA;\n#1=X();\nENDSEC;\n") == nil)
        #expect(Self.facts(.iges, "not an IGES file at all") == nil)
        let noise = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 7) })
        #expect(CADHeaderReader.facts(kind: .step, data: noise) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: noise) == nil)
    }

    @Test func truncationAtEveryOffsetNeverCrashesAndNeverInventsFacts() {
        let source = Data(Self.boxStepHeader.utf8)
        let iges = Data(Self.boxIGES.utf8)
        for cut in 0...source.count {
            if let facts = CADHeaderReader.facts(kind: .step, data: source.prefix(cut)) {
                #expect(facts.originatingSystem == nil || facts.originatingSystem == "Open CASCADE 7.9")
                #expect(facts.schema == nil || facts.schema == .stepAP214)
            }
        }
        for cut in 0...iges.count {
            if let facts = CADHeaderReader.facts(kind: .iges, data: iges.prefix(cut)) {
                #expect(facts.originatingSystem == nil || facts.originatingSystem == "Open CASCADE 7.9")
                #expect(facts.schema == nil || facts.schema == .iges(.version5_3))
            }
        }
    }

    @Test func unterminatedStringsAndCommentsAreIgnored() {
        #expect(Self.facts(.step, "ISO-10303-21;\nHEADER;\nFILE_NAME('p','t',('a'),('o'),'x','Unterminated") == nil)
        #expect(Self.facts(.step, "ISO-10303-21;\nHEADER;\n/* never closed\nFILE_SCHEMA(('CONFIG_CONTROL_DESIGN'));") == nil)
    }

    @Test func deeplyNestedArgumentsAreRejectedWithoutRecursion() {
        let nested = String(repeating: "(", count: 50_000) + String(repeating: ")", count: 50_000)
        #expect(Self.facts(.step, "ISO-10303-21;\nHEADER;\nFILE_NAME\(nested);\nFILE_SCHEMA(('CONFIG_CONTROL_DESIGN'));\nENDSEC;") == nil)
    }

    @Test func factsBeyondTheSixtyFourKiBScanWindowAreNotRead() {
        let filler = "/* " + String(repeating: "x", count: CADHeaderReader.scanLimit) + " */\n"
        let late = "ISO-10303-21;\nHEADER;\n" + filler + "FILE_SCHEMA(('CONFIG_CONTROL_DESIGN'));\nENDSEC;\n"
        #expect(Self.facts(.step, late) == nil)
        let early = "ISO-10303-21;\nHEADER;\nFILE_SCHEMA(('CONFIG_CONTROL_DESIGN'));\n" + filler + "ENDSEC;\n"
        #expect(Self.facts(.step, early)?.schema == .stepAP203)
        // Many megabytes after the header cost nothing: only the first 64 KiB is ever copied.
        let huge = Data(Self.boxStepHeader.utf8) + Data(repeating: 0x41, count: 12 * 1_024 * 1_024)
        let started = ContinuousClock.now
        #expect(CADHeaderReader.facts(kind: .step, data: huge)?.schema == .stepAP214)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func aHeaderWithThousandsOfEntitiesStaysBounded() {
        let entities = String(repeating: "OTHER_ENTITY(('a','b'),(1,2,3));\n", count: 5_000)
        let text = "ISO-10303-21;\nHEADER;\n" + entities + "FILE_SCHEMA(('CONFIG_CONTROL_DESIGN'));\nENDSEC;\n"
        #expect(Self.facts(.step, text) == nil) // The entity cap is reached first.
    }

    // MARK: IGES variants

    /// Builds a fixed-record IGES file from the Global-section text, one 72-column record per chunk.
    static func iges(global: String, lineBreak: String = "\n", startLine: Bool = true, trailing: Bool = true) -> Data {
        func record(_ text: String, _ section: String, _ number: Int) -> String {
            text.padding(toLength: 72, withPad: " ", startingAt: 0) + section + String(format: "%07d", number)
        }
        var lines: [String] = startLine ? [record("synthetic start", "S", 1)] : []
        let characters = Array(global)
        var number = 1
        for start in stride(from: 0, to: characters.count, by: 72) {
            lines.append(record(String(characters[start..<min(start + 72, characters.count)]), "G", number)); number += 1
        }
        if trailing { lines.append(record("     402       1", "D", 1)) }
        return Data((lines.joined(separator: lineBreak) + lineBreak).utf8)
    }
    static let defaultGlobal = ",,5HPROD1,8Hfile.igs,16HExampleCAD V12.1,10HPreproc 2.,32,38,6,308,15,,1.,6,2HM ,1,0.01,13H20250101.0000,1E-07,30.,6HAuthor,3HOrg,9,0,;"

    @Test func standardRecordsWithDefaultDelimiters() {
        let facts = CADHeaderReader.facts(kind: .iges, data: Self.iges(global: Self.defaultGlobal))
        #expect(facts?.originatingSystem == "ExampleCAD V12.1")
        #expect(facts?.schema == .iges(.version5_1))
        #expect(facts?.sourceUnit == "M")
    }

    @Test func explicitDefaultDelimitersAndCustomDelimitersAreHonored() {
        let explicit = "1H,,1H;," + String(Self.defaultGlobal.dropFirst(2))
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: explicit))?.originatingSystem == "ExampleCAD V12.1")
        for separator in [",", "/"] { // The declared delimiter or the default comma may follow the definition.
            let custom = Self.defaultGlobal.dropFirst(2).replacingOccurrences(of: ",", with: "/")
                .replacingOccurrences(of: ";", with: "!")
            let global = "1H/\(separator)1H!/" + custom
            let facts = CADHeaderReader.facts(kind: .iges, data: Self.iges(global: global))
            #expect(facts?.originatingSystem == "ExampleCAD V12.1", "separator \(separator)")
            #expect(facts?.schema == .iges(.version5_1))
        }
    }

    @Test func delimiterCharactersInsideHollerithStringsAreData() {
        let global = ",,5HPROD1,8Hfile.igs,16HVendor, Inc; CAD,10HPreproc 2.,32,38,6,308,15,,1.,2,2HMM,1,0.01,13H20250101.0000,1E-07,30.,6HAuthor,3HOrg,11,0,;"
        let facts = CADHeaderReader.facts(kind: .iges, data: Self.iges(global: global))
        #expect(facts?.originatingSystem == nil) // "Vendor, Inc; CAD" holds unsafe punctuation, so it is omitted.
        #expect(facts?.schema == .iges(.version5_3)) // Parsing stayed aligned past the embedded delimiters.
        #expect(facts?.sourceUnit == "MM")
    }

    @Test func nativeSystemFallsBackToThePreprocessorOnlyWhenBlank() {
        let blank = ",,5HPROD1,8Hfile.igs,0H,10HPreproc 2.,32,38,6,308,15,,1.,2,2HMM,1,0.01,13H20250101.0000,1E-07,30.,6HAuthor,3HOrg,11,0,;"
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: blank))?.originatingSystem == "Preproc 2.")
    }

    @Test func newlineStylesAndBareEightyByteRecordsAreAccepted() {
        for lineBreak in ["\n", "\r\n", "\r", ""] {
            let facts = CADHeaderReader.facts(kind: .iges, data: Self.iges(global: Self.defaultGlobal, lineBreak: lineBreak))
            #expect(facts?.originatingSystem == "ExampleCAD V12.1", "line break \(lineBreak.debugDescription)")
        }
    }

    @Test func unitFlagsRevisionFlagsAndNamedUnits() {
        func facts(unitFlag: String, unitName: String, revision: String) -> CADHeaderFacts? {
            let text = ",,5HPROD1,8Hfile.igs,5HSys 1,0H,32,38,6,308,15,,1.,\(unitFlag),\(unitName),1,0.01,13H20250101.0000,1E-07,30.,6HAuthor,3HOrg,\(revision),0,;"
            return CADHeaderReader.facts(kind: .iges, data: Self.iges(global: text))
        }
        #expect(facts(unitFlag: "1", unitName: "4HINCH", revision: "11")?.sourceUnit == "IN")
        #expect(facts(unitFlag: "3", unitName: "6HFURLNG", revision: "11")?.sourceUnit == "FURLNG")
        #expect(facts(unitFlag: "3", unitName: "7Hbad@unt", revision: "11")?.sourceUnit == nil)
        #expect(facts(unitFlag: "99", unitName: "", revision: "11")?.sourceUnit == nil)
        let revisions: [(String, IGESRevision?)] = [("3", .version2_0), ("4", .version3_0), ("6", .version4_0), ("8", .version5_0),
                                                    ("9", .version5_1), ("10", .version5_2), ("11", .version5_3), ("5", nil), ("99", nil)]
        for (flag, expected) in revisions {
            #expect(facts(unitFlag: "2", unitName: "2HMM", revision: flag)?.schema == expected.map(CADSchema.iges), "flag \(flag)")
        }
    }

    @Test func byteOrderMarksAndStrayLeadingRecordsAreTolerated() {
        let bom = Data([0xEF, 0xBB, 0xBF])
        #expect(CADHeaderReader.facts(kind: .step, data: bom + Data(Self.boxStepHeader.utf8))?.schema == .stepAP214)
        // A BOM shifts the first fixed-width record, so it no longer shows a section letter; later records do.
        let igesWithBOM = CADHeaderReader.facts(kind: .iges, data: bom + Self.iges(global: Self.defaultGlobal))
        #expect(igesWithBOM?.originatingSystem == "ExampleCAD V12.1")
        let junk = Data("this line is not a record\n".utf8) + Self.iges(global: Self.defaultGlobal)
        #expect(CADHeaderReader.facts(kind: .iges, data: junk)?.schema == .iges(.version5_1))
    }

    @Test func malformedIGESGlobalSectionsAreIgnored() {
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: "")) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: ",,999999HToo long")) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: ",,5HPROD1,99HShort")) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: "garbage without delimiters")) == nil)
        #expect(CADHeaderReader.facts(kind: .iges, data: Self.iges(global: Self.defaultGlobal, startLine: false))?.originatingSystem == "ExampleCAD V12.1")
        // A Delimiter-only section and a missing Global section both leave nothing to report.
        #expect(CADHeaderReader.facts(kind: .iges, data: Data((String(repeating: " ", count: 72) + "S0000001\n").utf8)) == nil)
        // Non-ASCII bytes inside the system name decline to decode.
        var bytes = Self.iges(global: Self.defaultGlobal)
        if let range = bytes.firstRange(of: Data("ExampleCAD".utf8)) { bytes[range.lowerBound] = 0xE9 }
        #expect(CADHeaderReader.facts(kind: .iges, data: bytes)?.originatingSystem == nil)
    }

    @Test func aGlobalSectionThatNeverEndsIsBoundedAndIgnored() {
        let endless = ",," + String(repeating: "4HAAAA,", count: 4_000)
        let data = Self.iges(global: endless)
        let started = ContinuousClock.now
        #expect(CADHeaderReader.facts(kind: .iges, data: data)?.originatingSystem == "AAAA") // Reads 23 parameters, then stops.
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
