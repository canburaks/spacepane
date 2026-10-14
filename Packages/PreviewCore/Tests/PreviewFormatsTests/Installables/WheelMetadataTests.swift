import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Wheel metadata readers")
struct WheelMetadataTests {
    private typealias Fixtures = InstallFixtures

    private func headers(_ text: String, keeping names: Set<String> = ["name", "version", "summary", "requires-dist", "license"]) throws -> WheelHeaders {
        try WheelHeaders(Data(text.utf8), keeping: names, context: Fixtures.context)
    }

    // MARK: Headers

    @Test func readsTheNamedHeadersInOrder() throws {
        let parsed = try headers("""
        Metadata-Version: 2.1
        Name: example-pkg
        Version: 1.2.3
        Summary: A tiny example
        Requires-Dist: requests (>=2.0)
        Requires-Dist: rich ; extra == "cli"
        Classifier: Programming Language :: Python

        Name: not-a-header
        """)
        #expect(parsed.first("name") == "example-pkg")
        #expect(parsed.first("version") == "1.2.3")
        #expect(parsed.first("summary") == "A tiny example")
        #expect(parsed.all("requires-dist") == ["requests (>=2.0)", "rich ; extra == \"cli\""])
        #expect(parsed.first("classifier") == nil)
        #expect(parsed.first("metadata-version") == nil)
    }

    @Test func namesIgnoreCaseAndLineEndingsMayBeCRLF() throws {
        let parsed = try headers("NAME: Example\r\nVERSION: 2\r\nrequires-DIST: a\r\n\r\nbody: x\r\n")
        #expect(parsed.first("name") == "Example")
        #expect(parsed.first("version") == "2")
        #expect(parsed.all("requires-dist") == ["a"])
        #expect(parsed.first("body") == nil)
    }

    @Test func foldedValuesAreJoinedWithOneSpace() throws {
        let parsed = try headers("Summary: first part\n        second part\n\tthird part\nName: x\n  continued\n")
        #expect(parsed.first("summary") == "first part second part third part")
        #expect(parsed.first("name") == "x continued")
    }

    @Test func aContinuationOfAHeaderThatWasNotKeptIsIgnored() throws {
        let parsed = try headers("Author: someone\n  else\nName: x\n")
        #expect(parsed.first("name") == "x")
        #expect(parsed.first("author") == nil)
    }

    @Test func linesWithoutAColonAndEmptyValuesAreSkipped() throws {
        let parsed = try headers("garbage line\nName:\nVersion: 3\n: orphan\n")
        #expect(parsed.first("name") == nil)
        #expect(parsed.first("version") == "3")
    }

    @Test func eachHeaderKeepsAtMostSixtyFourValuesOfBoundedLength() throws {
        let many = (0..<200).map { "Requires-Dist: pkg\($0)" }.joined(separator: "\n")
        #expect(try headers(many).all("requires-dist").count == WheelHeaders.maximumValues)
        let long = try headers("Summary: " + String(repeating: "é", count: 10_000) + "\n")
        #expect((long.first("summary") ?? "").utf8.count <= WheelHeaders.maximumValueBytes)
        let folded = try headers("Summary: a\n" + String(repeating: " " + String(repeating: "b", count: 1_000) + "\n", count: 10))
        #expect((folded.first("summary") ?? "").utf8.count < WheelHeaders.maximumValueBytes)
    }

    @Test func aLargeBodyAfterTheHeadersIsNeverScanned() throws {
        let body = String(repeating: "Name: spoof\n", count: 200_000)
        let parsed = try headers("Name: real\n\n" + body)
        #expect(parsed.all("name") == ["real"])
    }

    @Test func invalidUTF8IsDecodedWithReplacementsAndNeverFails() throws {
        var data = Data("Name: ab".utf8)
        data.append(contentsOf: [0xFF, 0xFE])
        data += Data("\nVersion: 1\n".utf8)
        let parsed = try WheelHeaders(data, keeping: ["name", "version"], context: Fixtures.context)
        #expect(parsed.first("name")?.hasPrefix("ab") == true)
        #expect(parsed.first("version") == "1")
        #expect(try WheelHeaders(Data(), keeping: ["name"], context: Fixtures.context).first("name") == nil)
    }

    // MARK: Entry points

    @Test func listsTheNamesOfConsoleAndGuiScripts() throws {
        let text = """
        # generated
        [console_scripts]
        example = example.cli:main
        other-tool=example.other:run [extra]
        ; comment
        [gui_scripts]
        example-gui = example.gui:main
        [distutils.commands]
        build_thing = example.build:Thing
        [Console_Scripts]
        wrong-case = x:y
        [console_scripts]
        example = example.cli:main
        """
        let names = try WheelEntryPoints.commandNames(Data(text.utf8), context: Fixtures.context)
        #expect(names == ["example", "other-tool", "example-gui"])
    }

    @Test func continuationLinesEmptyNamesAndMalformedLinesAreNotCommands() throws {
        let text = "[console_scripts]\nexample = a:b\n    continued = c:d\n= nothing\nno equals sign\n[ gui_scripts ]\ng = h:i\r\n"
        #expect(try WheelEntryPoints.commandNames(Data(text.utf8), context: Fixtures.context) == ["example", "g"])
        #expect(try WheelEntryPoints.commandNames(Data(), context: Fixtures.context).isEmpty)
    }

    @Test func commandNamesAreBounded() throws {
        let text = "[console_scripts]\n" + (0..<1_000).map { "tool\($0) = m:f" }.joined(separator: "\n")
        #expect(try WheelEntryPoints.commandNames(Data(text.utf8), context: Fixtures.context).count == WheelEntryPoints.maximumNames)
    }
}
