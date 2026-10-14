import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Browser extension summaries")
struct BrowserExtensionAdapterTests {
    typealias Member = AddOnFixtures.Member

    /// An ordinary Manifest version 3 Chrome extension that reaches one site and updates from the store.
    static func chrome(_ edit: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var manifest: [String: Any] = [
            "manifest_version": 3, "name": "Tab Notes", "version": "2.0.1", "description": "Keeps a note for each tab.",
            "permissions": ["storage", "activeTab"], "host_permissions": ["https://notes.example.test/*"],
            "background": ["service_worker": "background.js"],
            "content_scripts": [["matches": ["https://notes.example.test/*"], "js": ["content.js"]]],
            "content_security_policy": ["extension_pages": "script-src 'self'; object-src 'self'"],
            "update_url": "https://clients2.google.com/service/update2/crx"
        ]
        edit(&manifest)
        return manifest
    }

    /// An ordinary Manifest version 2 Firefox add-on with a placeholder name.
    static func firefox(_ edit: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var manifest: [String: Any] = [
            "manifest_version": 2, "name": "__MSG_extName__", "version": "1.0", "description": "__MSG_extDescription__",
            "browser_specific_settings": ["gecko": ["id": "tabnotes@example.test", "strict_min_version": "109.0"]],
            "permissions": ["storage", "https://notes.example.test/*"], "background": ["scripts": ["bg.js"]]
        ]
        edit(&manifest)
        return manifest
    }

    static let defaultFiles = [Member("background.js", text: "chrome.runtime.onInstalled.addListener(() => {});\n", deflated: true),
                               Member("content.js", text: "document.title;\n"), Member("bg.js", text: "browser.runtime;\n")]

    static func zip(_ manifest: [String: Any], files: [Member] = defaultFiles) -> Data {
        AddOnFixtures.zip([Member("manifest.json", AddOnFixtures.json(manifest))] + files)
    }

    static func summary(_ data: Data, suffix: String? = nil) throws -> ([String: Any], ParsedTextDocument) {
        var context = AddOnFixtures.context
        context.nameHint = suffix.map { PreviewNameHint(filename: "sample.\($0)", suffix: $0) }
        let document = try BrowserExtensionAdapter().parse(DataByteSource(data), context: context)
        return (PackageTestSupport.object(document), document)
    }

    // MARK: The card

    @Test func aFirefoxAddOnShowsItsManifestAsWritten() throws {
        let (summary, document) = try Self.summary(Self.zip(Self.firefox()))
        #expect(summary["browser"] as? String == "Firefox (XPI)")
        #expect(summary["name"] as? String == "__MSG_extName__" && summary["description"] as? String == "__MSG_extDescription__")
        #expect(summary["version"] as? String == "1.0" && summary["manifestVersion"] as? Int == 2)
        #expect(summary["addonID"] as? String == "tabnotes@example.test")
        #expect(summary["permissions"] as? [String] == ["storage"])
        #expect(summary["hostPermissions"] as? [String] == ["https://notes.example.test/*"])
        #expect(summary["background"] as? [String] == ["bg.js"])
        #expect(summary["updateURL"] == nil && summary["optionalPermissions"] == nil)
        #expect(summary["archiveFormat"] as? String == "ZIP")
        #expect(document.origin == .summary && document.findings.isEmpty)
    }

    @Test func aChromeExtensionInACRX3FileShowsItsManifest() throws {
        let archive = Self.zip(Self.chrome())
        let (summary, document) = try Self.summary(AddOnFixtures.crx3(archive: archive))
        #expect(summary["browser"] as? String == "Chrome (CRX3)")
        #expect(summary["name"] as? String == "Tab Notes" && summary["manifestVersion"] as? Int == 3)
        #expect(summary["permissions"] as? [String] == ["storage", "activeTab"])
        #expect(summary["hostPermissions"] as? [String] == ["https://notes.example.test/*"])
        #expect(summary["contentScriptMatches"] as? [String] == ["https://notes.example.test/*"])
        #expect(summary["background"] as? [String] == ["background.js"])
        #expect(summary["updateURL"] as? String == "https://clients2.google.com")
        #expect(summary["addonID"] == nil)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }.first == "manifest.json")
        #expect(document.findings.isEmpty)
    }

    @Test func aCRX2FileIsReadTheSameWay() throws {
        let (summary, _) = try Self.summary(AddOnFixtures.crx2(archive: Self.zip(Self.chrome())))
        #expect(summary["browser"] as? String == "Chrome (CRX2)" && summary["name"] as? String == "Tab Notes")
    }

    @Test func theSameArchiveGivesTheSameCardInAnyWrapper() throws {
        let archive = Self.zip(Self.chrome { $0["update_url"] = nil })
        var plain = try Self.summary(archive).0
        var wrapped = try Self.summary(AddOnFixtures.crx3(archive: archive)).0
        #expect(plain["browser"] as? String == "Firefox (XPI)")
        plain["browser"] = nil
        wrapped["browser"] = nil
        #expect(NSDictionary(dictionary: plain).isEqual(to: wrapped))
        // The name hint decides only the label of an archive without a header.
        #expect(try Self.summary(archive, suffix: "crx").0["browser"] as? String == "Chrome (ZIP)")
    }

    @Test func oldManifestsWithCommentsAreTolerated() throws {
        let text = "// Chrome accepted comments in manifests once\n{ \"manifest_version\": 2, /* the name */ \"name\": \"Old\", \"version\": \"1\", }\n"
        let (summary, _) = try Self.summary(AddOnFixtures.zip([Member("manifest.json", text: text)]))
        #expect(summary["name"] as? String == "Old")
    }

    @Test func theUpdateAddressShowsOnlyWhereItPoints() throws {
        let secret = AddOnFixtures.secret
        let data = Self.zip(Self.chrome { $0["update_url"] = "https://user:pw@updates.example.test:8443/crx?key=\(secret)#frag" })
        let (summary, document) = try Self.summary(AddOnFixtures.crx3(archive: data))
        #expect(summary["updateURL"] as? String == "https://updates.example.test:8443")
        #expect(!document.text.contains(secret) && !document.text.contains("pw@"))
    }

    @Test func longPermissionListsAreCut() throws {
        let hosts = (0..<300).map { "https://site\($0).example.test/*" }
        let (summary, _) = try Self.summary(Self.zip(Self.chrome { $0["host_permissions"] = hosts; $0["permissions"] = (0..<300).map { "perm\($0)" } }))
        #expect((summary["hostPermissions"] as? [String])?.count == AddOnLimits.listItems)
        #expect((summary["permissions"] as? [String])?.count == AddOnLimits.listItems)
    }

    @Test func credentialLookingDescriptionsAreConcealed() throws {
        let secret = AddOnFixtures.secret
        let (_, document) = try Self.summary(Self.zip(Self.chrome { $0["description"] = "Uses password: \(secret) always" }))
        #expect(!PackageTestSupport.concealedText(document).contains(secret))
    }

    // MARK: Container and malformed input

    @Test func unsupportedAndBrokenCRXHeadersFailCleanly() throws {
        let archive = Self.zip(Self.chrome())
        var version4 = AddOnFixtures.crx3(archive: archive)
        version4.replaceSubrange(4..<8, with: AddOnFixtures.little(4, 4))
        #expect(throws: PreviewFailure.unsupportedVariant) { try Self.summary(version4) }
        let hugeHeader = Data("Cr24".utf8) + AddOnFixtures.little(3, 4) + AddOnFixtures.little(262_145, 4) + Data(repeating: 0, count: 262_145) + archive
        #expect(throws: PreviewFailure.malformedDocument) { try Self.summary(hugeHeader) }
        let overrun = Data("Cr24".utf8) + AddOnFixtures.little(3, 4) + AddOnFixtures.little(0xFFFF_FFFF, 4) + archive
        #expect(throws: PreviewFailure.malformedDocument) { try Self.summary(overrun) }
        let shortCRX2 = Data("Cr24".utf8) + AddOnFixtures.little(2, 4) + AddOnFixtures.little(40, 4)
        #expect(throws: PreviewFailure.malformedDocument) { try Self.summary(shortCRX2) }
        #expect(throws: PreviewFailure.malformedDocument) { try Self.summary(Data("Cr24".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try Self.summary(Data("Cr24".utf8) + AddOnFixtures.little(3, 4)) }
    }

    @Test func malformedPackagesFailClosed() throws {
        let valid = AddOnFixtures.crx3(archive: Self.zip(Self.chrome()))
        let plain = Self.zip(Self.firefox())
        let noManifest = AddOnFixtures.zip([Member("background.js", text: "x")])
        let nested = AddOnFixtures.zip([Member("ext/manifest.json", AddOnFixtures.json(Self.chrome()))])
        let notObject = AddOnFixtures.zip([Member("manifest.json", text: "\"manifest\"")])
        let oversized = AddOnFixtures.zip([Member("manifest.json", Data("{\"description\": \"".utf8) + Data(repeating: 0x61, count: 1_100_000) + Data("\"}".utf8))])
        let samples: [Data] = [Data(), Data("PK".utf8), valid.dropLast(), Data(valid.prefix(valid.count / 2)), plain.dropLast(), Data(plain.prefix(40)),
                               noManifest, nested, notObject, oversized]
        for data in samples { #expect(throws: PreviewFailure.self) { try Self.summary(data) } }
        #expect(throws: PreviewFailure.inputTooLarge) { try Self.summary(oversized) }
    }

    @Test func cancellationStopsAnActiveParse() async throws {
        let files = (0..<200).map { Member("lib/l\($0).js", text: "let a;\n", deflated: $0.isMultiple(of: 2)) }
        let data = AddOnFixtures.crx3(archive: Self.zip(Self.chrome(), files: Self.defaultFiles + files))
        let document = try await CancellationTest.expectStopsActiveParse(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)) { context in
            try BrowserExtensionAdapter().parse(DataByteSource(data), context: context)
        }
        #expect(PackageTestSupport.object(document)["name"] as? String == "Tab Notes")
    }
}
