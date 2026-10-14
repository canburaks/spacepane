import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

@Suite("Python wheel summaries")
struct PythonWheelAdapterTests {
    private typealias Fixtures = InstallFixtures

    private func summary(_ members: [(path: String, data: Data)], deflate: Bool = true,
                         context: RequestContext = Fixtures.context) throws -> ([String: Any], ParsedTextDocument) {
        let document = try PythonWheelAdapter().parse(FileBytes(data: Fixtures.zip(members, deflate: deflate)), context: context)
        return (PackageTestSupport.object(document), document)
    }

    private func strings(_ value: Any?) -> [String] { value as? [String] ?? [] }

    // MARK: Summary fields

    @Test(arguments: [false, true])
    func summarizesAnOrdinaryWheel(deflate: Bool) throws {
        let (summary, document) = try summary(Fixtures.wheelMembers(), deflate: deflate)
        #expect(summary["name"] as? String == "example")
        #expect(summary["version"] as? String == "1.0")
        #expect(summary["summary"] as? String == "A tiny example")
        #expect(summary["requiresPython"] as? String == ">=3.8")
        #expect(strings(summary["dependencies"]) == ["requests (>=2.0)"])
        #expect(summary["license"] as? String == "MIT")
        #expect(summary["wheelVersion"] as? String == "1.0")
        #expect(summary["generator"] as? String == "bdist_wheel (0.43.0)")
        #expect(summary["pureLibrary"] as? Bool == true)
        #expect(strings(summary["tags"]) == ["py3-none-any"])
        #expect(strings(summary["commands"]) == ["example"])
        #expect(summary["startupFiles"] == nil && summary["installedScripts"] == nil && summary["nativeModules"] == nil)
        #expect(summary["archiveFormat"] as? String == "ZIP")
        #expect(summary["listedEntries"] as? Int == 5)
        #expect(summary["partial"] as? Bool == false)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }.first == "example/__init__.py")
        #expect(document.origin == .summary)
        #expect(document.findings.isEmpty)
    }

    @Test func keysFollowTheDocumentedOrderAndListingComesLast() throws {
        let members = Fixtures.wheelMembers(extra: [Fixtures.wheelFile("import os\n", at: "ex.pth")])
        let document = try PythonWheelAdapter().parse(FileBytes(data: Fixtures.zip(members)), context: Fixtures.context)
        let order = ["\"name\"", "\"version\"", "\"summary\"", "\"requiresPython\"", "\"dependencies\"", "\"license\"",
                     "\"wheelVersion\"", "\"generator\"", "\"pureLibrary\"", "\"tags\"", "\"commands\"", "\"startupFiles\"",
                     "\"archiveFormat\"", "\"listedEntries\"", "\"partial\"", "\"entries\""]
        let positions = order.map { document.text.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
    }

    @Test func aWheelWithAnExtensionModuleIsNotPure() throws {
        let wheel = "Wheel-Version: 1.0\nRoot-Is-Purelib: false\nTag: cp312-cp312-macosx_11_0_arm64\nTag: cp312-cp312-macosx_10_9_x86_64\n"
        let (summary, _) = try summary(Fixtures.wheelMembers(wheel: wheel))
        #expect(summary["pureLibrary"] as? Bool == false)
        #expect(strings(summary["tags"]).count == 2)
        let unknown = try self.summary(Fixtures.wheelMembers(wheel: "Wheel-Version: 1.0\nRoot-Is-Purelib: maybe\n")).0
        #expect(unknown["pureLibrary"] == nil)
    }

    @Test func theLicenseFallsBackToTheOldFieldAndLongTextIsClipped() throws {
        let old = Fixtures.defaultMetadata.replacingOccurrences(of: "License-Expression: MIT", with: "License: BSD-3-Clause")
        #expect(try summary(Fixtures.wheelMembers(metadata: old)).0["license"] as? String == "BSD-3-Clause")
        let text = Fixtures.defaultMetadata.replacingOccurrences(of: "License-Expression: MIT", with: "License: " + String(repeating: "word ", count: 400))
        let clipped = try #require(try summary(Fixtures.wheelMembers(metadata: text)).0["license"] as? String)
        #expect(clipped.utf8.count <= PythonWheelAdapter.maximumLicenseBytes)
    }

    @Test func nameAndVersionFallBackToTheFolderName() throws {
        let (summary, _) = try summary(Fixtures.wheelMembers(metadata: "Metadata-Version: 2.1\n", folder: "my_pkg-2.3.1+local"))
        #expect(summary["name"] as? String == "my_pkg")
        #expect(summary["version"] as? String == "2.3.1+local")
    }

    @Test func missingWheelAndEntryPointFilesJustShowLess() throws {
        let (summary, _) = try summary(Fixtures.wheelMembers(wheel: nil, entryPoints: nil))
        #expect(summary["name"] as? String == "example")
        for key in ["wheelVersion", "generator", "pureLibrary", "tags", "commands"] { #expect(summary[key] == nil, "\(key)") }
    }

    @Test func requirementsAndFoldedValuesStayVerbatim() throws {
        let metadata = "Name: example\nVersion: 1.0\nSummary: first\n second\nRequires-Dist: a (>=1) ; python_version < \"3.9\"\nRequires-Dist: b[extra]\n\nbody"
        let (summary, _) = try summary(Fixtures.wheelMembers(metadata: metadata))
        #expect(summary["summary"] as? String == "first second")
        #expect(strings(summary["dependencies"]) == ["a (>=1) ; python_version < \"3.9\"", "b[extra]"])
    }

    @Test func aHugeDescriptionIsNeverReadBeyondTheCap() throws {
        let metadata = Fixtures.defaultMetadata + String(repeating: "A very long description line.\n", count: 150_000)
        #expect(metadata.utf8.count > PythonWheelAdapter.maximumMetadataBytes)
        let source = RecordingByteSource(Fixtures.zip(Fixtures.wheelMembers(metadata: metadata), deflate: false))
        let document = try PythonWheelAdapter().parse(source, context: Fixtures.context)
        #expect(PackageTestSupport.object(document)["name"] as? String == "example")
        let archive = try ZIPArchiveReader.read(source, context: Fixtures.context)
        let entry = try #require(archive.entry(at: "example-1.0.dist-info/METADATA"))
        // The ZIP reader itself reads the last 64 KiB of the file to find the end record.
        let end = entry.payloadOffset + entry.compressedSize - 70_000
        #expect(end > entry.payloadOffset + PythonWheelAdapter.maximumMetadataBytes + 1_000_000)
        #expect(!source.touches((entry.payloadOffset + PythonWheelAdapter.maximumMetadataBytes)..<end))
    }

    // MARK: Startup files

    @Test func importLinesOfInstalledPthFilesAreCounted() throws {
        let members = Fixtures.wheelMembers(extra: [
            Fixtures.wheelFile("# comment\nimport os; os.environ\n\nsrc\nimport sys\n  import indented\n", at: "boot.pth"),
            Fixtures.wheelFile("import a\n", at: "example-1.0.data/purelib/more.pth"),
            Fixtures.wheelFile("import b\nimport\tc\n", at: "example-1.0.data/platlib/native.pth")
        ])
        let (summary, document) = try summary(members)
        #expect(document.findings == [PreviewFinding(kind: .installStartupCode, count: 5)])
        #expect(document.findings.first?.severity == .warning && document.findings.first?.lines.isEmpty == true)
        #expect(strings(summary["startupFiles"]) == ["boot.pth", "example-1.0.data/purelib/more.pth", "example-1.0.data/platlib/native.pth"])
        // The lines themselves are never shown.
        #expect(!document.text.contains("os.environ"))
    }

    @Test func pathOnlyPthFilesAreListedButSilent() throws {
        let members = Fixtures.wheelMembers(extra: [Fixtures.wheelFile("# libs\n./vendor\n/usr/lib/extra\nimportant\n", at: "paths.pth")])
        let (summary, document) = try summary(members)
        #expect(document.findings.isEmpty)
        #expect(strings(summary["startupFiles"]) == ["paths.pth"])
    }

    @Test func onlyPathFilesThatInstallationPlacesInSitePackagesCount() throws {
        let code = "import os\n"
        let members = Fixtures.wheelMembers(extra: [
            Fixtures.wheelFile(code, at: "example/nested.pth"),
            Fixtures.wheelFile(code, at: "example-1.0.data/data/etc/x.pth"),
            Fixtures.wheelFile(code, at: "example-1.0.data/scripts/x.pth"),
            Fixtures.wheelFile(code, at: "example-1.0.data/purelib/sub/x.pth"),
            Fixtures.wheelFile(code, at: "other-9.9.data/purelib/x.pth"),
            Fixtures.wheelFile(code, at: ".hidden.pth"),
            Fixtures.wheelFile(code, at: "UPPER.PTH"),
            Fixtures.wheelFile(code, at: "notes.pth.txt"),
            Fixtures.wheelFile(code, at: "example-1.0.dist-info/inside.pth")
        ])
        let (summary, document) = try summary(members)
        #expect(document.findings.isEmpty)
        #expect(summary["startupFiles"] == nil)
    }

    @Test func aPthFileOverItsCapIsReadUpToTheCap() throws {
        let padding = String(repeating: "# padding\n", count: 7_000)
        let early = Fixtures.wheelMembers(extra: [Fixtures.wheelFile("import os\n" + padding, at: "early.pth")])
        #expect(try summary(early).1.findings.first?.count == 1)
        let late = Fixtures.wheelMembers(extra: [Fixtures.wheelFile(padding + "import os\n", at: "late.pth")])
        #expect(padding.utf8.count > PythonWheelAdapter.maximumPathFileBytes)
        #expect(try summary(late).1.findings.isEmpty)
    }

    @Test func installedScriptsAreListedByRelativePath() throws {
        let members = Fixtures.wheelMembers(extra: [
            Fixtures.wheelFile("#!/bin/sh\n", at: "example-1.0.data/scripts/tool"),
            Fixtures.wheelFile("x", at: "example-1.0.data/scripts/sub/helper.py"),
            Fixtures.wheelFile("x", at: "example-1.0.data/data/share/readme")
        ])
        #expect(strings(try summary(members).0["installedScripts"]) == ["tool", "sub/helper.py"])
    }
}
