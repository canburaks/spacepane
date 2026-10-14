import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Editor extension summaries")
struct EditorExtensionAdapterTests {
    typealias Member = AddOnFixtures.Member
    private static let zeroWidth = "\u{200B}"

    /// An ordinary extension that starts on a command and brings no native code.
    static func manifest(_ edit: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var manifest: [String: Any] = [
            "name": "notes-helper", "publisher": "example", "displayName": "Notes Helper", "version": "0.4.1",
            "description": "Helps with notes.", "engines": ["vscode": "^1.85.0"], "main": "./out/extension",
            "activationEvents": ["onCommand:notes.open", "onLanguage:markdown"], "categories": ["Other", "Notebooks"],
            "contributes": ["commands": [["command": "notes.open", "title": "Open Notes"], ["command": "notes.new", "title": "New Note"]]],
            "capabilities": ["untrustedWorkspaces": ["supported": "limited"]]
        ]
        edit(&manifest)
        return manifest
    }

    static func vsix(_ manifest: [String: Any] = Self.manifest(), files: [Member] = [Member("extension/out/extension.js", text: "exports.activate = function () {};\n", deflated: true)]) -> Data {
        AddOnFixtures.zip([Member("[Content_Types].xml", text: "<Types/>"), Member("extension.vsixmanifest", text: "<PackageManifest/>"),
                           Member("extension/package.json", AddOnFixtures.json(manifest))] + files)
    }

    static func summary(_ data: Data) throws -> ([String: Any], ParsedTextDocument) {
        let document = try EditorExtensionAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context)
        return (PackageTestSupport.object(document), document)
    }

    private func counts(_ edit: (inout [String: Any]) -> Void, files: [Member]? = nil) throws -> [PreviewFindingKind: Int] {
        let data = files.map { Self.vsix(Self.manifest(edit), files: $0) } ?? Self.vsix(Self.manifest(edit))
        return AddOnFixtures.counts(try Self.summary(data).1)
    }

    // MARK: The card

    @Test func anOrdinaryExtensionShowsItsManifestAndNoFindings() throws {
        let (summary, document) = try Self.summary(Self.vsix())
        #expect(summary["publisher"] as? String == "example" && summary["name"] as? String == "notes-helper")
        #expect(summary["displayName"] as? String == "Notes Helper" && summary["version"] as? String == "0.4.1")
        #expect(summary["description"] as? String == "Helps with notes.")
        #expect(summary["engine"] as? String == "^1.85.0")
        #expect(summary["entry"] as? String == "./out/extension" && summary["webEntry"] == nil)
        #expect(summary["activationEvents"] as? [String] == ["onCommand:notes.open", "onLanguage:markdown"])
        #expect(summary["categories"] as? [String] == ["Other", "Notebooks"])
        #expect(summary["commands"] as? Int == 2)
        #expect(summary["extensionPack"] == nil && summary["extensionDependencies"] == nil)
        #expect(summary["untrustedWorkspaces"] as? String == "limited")
        #expect(summary["archiveFormat"] as? String == "ZIP")
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }.contains("extension/package.json"))
        #expect(document.origin == .summary && document.findings.isEmpty)
    }

    @Test func webEntriesDependenciesAndBooleanTrustAreShown() throws {
        let data = Self.vsix(Self.manifest {
            $0["browser"] = "./dist/web.js"
            $0["extensionPack"] = ["a.one", "b.two"]
            $0["extensionDependencies"] = ["c.three"]
            $0["capabilities"] = ["untrustedWorkspaces": ["supported": false]]
        })
        let (summary, _) = try Self.summary(data)
        #expect(summary["webEntry"] as? String == "./dist/web.js")
        #expect(summary["extensionPack"] as? [String] == ["a.one", "b.two"])
        #expect(summary["extensionDependencies"] as? [String] == ["c.three"])
        #expect(summary["untrustedWorkspaces"] as? Bool == false)
    }

    @Test func theRandomAccessAndByteRoutesAgree() throws {
        let data = Self.vsix()
        let viaBytes = try EditorExtensionAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context)
        let viaSource = try EditorExtensionAdapter().parse(DataByteSource(data), context: AddOnFixtures.context)
        #expect(viaBytes.text == viaSource.text)
    }

    // MARK: Findings

    @Test(arguments: ["*", "onStartupFinished"])
    func automaticActivationIsReported(event: String) throws {
        #expect(try counts { $0["activationEvents"] = ["onCommand:x", event] } == [.extensionStartsAutomatically: 1])
    }

    @Test(arguments: ["onCommand:notes.open", "onLanguage:python", "workspaceContains:**/*.json", "onView:explorer", "onStartup", "**"])
    func otherActivationEventsAreSilent(event: String) throws {
        #expect(try counts { $0["activationEvents"] = [event] }.isEmpty)
    }

    @Test func installedExtensionsAreCountedOnce() throws {
        #expect(try counts { $0["extensionPack"] = ["a.one", "b.two"]; $0["extensionDependencies"] = ["b.two", "c.three"] }
                == [.extensionInstallsOthers: 3])
        #expect(try counts { $0["extensionPack"] = [] ; $0["extensionDependencies"] = [] }.isEmpty)
    }

    @Test func nativeCodeInThePackageIsCounted() throws {
        let files = [Member("extension/out/extension.js", text: "x"), Member("extension/bin/mac.node", Data("n".utf8)),
                     Member("extension/bin/helper", AddOnFixtures.machO, deflated: true), Member("extension/bin/win.dll", Data("d".utf8))]
        #expect(try counts({ _ in }, files: files) == [.artifactNativeCode: 3])
    }

    @Test func invisibleCharactersInTheMainScriptAreCounted() throws {
        let payload = String(repeating: "\u{FE01}", count: 12) + String(repeating: "\u{E000}", count: 3)
        let script = "const hidden = '\(payload)';\nexports.activate = () => {};\n"
        let files = [Member("extension/out/extension.js", text: script, deflated: true)]
        #expect(try counts({ _ in }, files: files) == [.hiddenVariationSelectors: 12, .hiddenPrivateUse: 3])
    }

    @Test func theDeclaredEntryIsScannedEvenWhenManyOtherScriptsExist() throws {
        var files = (0..<30).map { Member("extension/lib/l\($0).js", text: "let a;\n") }
        files.append(Member("extension/zz/deep/dist/main.js", text: "let b = 1;\(Self.zeroWidth)\n"))
        #expect(try counts({ $0["main"] = "./zz/deep/dist/main.js" }, files: files)[.hiddenZeroWidth] == 1)
    }

    @Test func invisibleCharactersInManifestStringsAreCounted() throws {
        let found = try counts { $0["displayName"] = "Notes\(Self.zeroWidth) Helper"; $0["description"] = "\u{202E}txet" }
        #expect(found == [.hiddenZeroWidth: 1, .hiddenBidirectionalControls: 1])
    }

    @Test func ordinaryInternationalTextIsSilent() throws {
        let found = try counts { $0["displayName"] = "Not Defteri \u{1F4D3}"; $0["description"] = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645} \u{65E5}\u{672C}\u{8A9E} caf\u{E9}" }
        #expect(found.isEmpty)
    }

    // MARK: Privacy and malformed input

    @Test func credentialLookingDescriptionsAreConcealed() throws {
        let secret = AddOnFixtures.secret
        let (_, document) = try Self.summary(Self.vsix(Self.manifest { $0["description"] = "Set token: \(secret) first" }))
        #expect(!PackageTestSupport.concealedText(document).contains(secret))
    }

    @Test func malformedPackagesFailClosed() throws {
        let valid = Self.vsix()
        let wrongPlace = AddOnFixtures.zip([Member("package.json", AddOnFixtures.json(Self.manifest()))])
        let notObject = AddOnFixtures.zip([Member("extension/package.json", text: "[]")])
        let oversized = AddOnFixtures.zip([Member("extension/package.json", Data("{\"description\": \"".utf8) + Data(repeating: 0x61, count: 1_100_000) + Data("\"}".utf8))])
        let samples: [Data] = [Data(), Data("PK\u{3}\u{4}".utf8), valid.dropLast(), Data(valid.prefix(valid.count / 3)), wrongPlace, notObject, oversized]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try EditorExtensionAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context) }
        }
    }

    @Test func cancellationStopsAnActiveParse() async throws {
        let files = (0..<200).map { Member("extension/lib/l\($0).js", text: "let a;\n", deflated: $0.isMultiple(of: 2)) }
        let data = Self.vsix(files: files)
        let document = try await CancellationTest.expectStopsActiveParse(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)) { context in
            try EditorExtensionAdapter().parse(DataByteSource(data), context: context)
        }
        #expect(PackageTestSupport.object(document)["name"] as? String == "notes-helper")
    }
}
