import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Browser extension findings")
struct BrowserExtensionFindingTests {
    typealias Member = AddOnFixtures.Member
    private static let zeroWidth = "\u{200B}"

    private func chrome(_ edit: (inout [String: Any]) -> Void, files: [Member] = BrowserExtensionAdapterTests.defaultFiles) throws -> [PreviewFindingKind: Int] {
        let data = AddOnFixtures.crx3(archive: BrowserExtensionAdapterTests.zip(BrowserExtensionAdapterTests.chrome(edit), files: files))
        return AddOnFixtures.counts(try BrowserExtensionAdapterTests.summary(data).1)
    }

    private func firefox(_ edit: (inout [String: Any]) -> Void, files: [Member] = BrowserExtensionAdapterTests.defaultFiles) throws -> [PreviewFindingKind: Int] {
        let data = BrowserExtensionAdapterTests.zip(BrowserExtensionAdapterTests.firefox(edit), files: files)
        return AddOnFixtures.counts(try BrowserExtensionAdapterTests.summary(data).1)
    }

    // MARK: All sites

    @Test(arguments: ["<all_urls>", "*://*/*", "http://*/*", "https://*/*", "ws://*/*"])
    func everySitePatternIsReported(pattern: String) throws {
        #expect(try chrome { $0["host_permissions"] = [pattern] } == [.extensionAllSites: 1])
        #expect(try chrome { $0["content_scripts"] = [["matches": [pattern], "js": ["content.js"]]] } == [.extensionAllSites: 1])
        #expect(try firefox { $0["permissions"] = ["storage", pattern] } == [.extensionAllSites: 1])
    }

    @Test(arguments: ["https://*.example.test/*", "https://example.test/*", "file:///*", "*://*.com/*", "chrome://favicon/*", "https://notes.example.test/*", "*"])
    func narrowerPatternsAreSilent(pattern: String) throws {
        #expect(try chrome { $0["host_permissions"] = [pattern]; $0["content_scripts"] = [["matches": [pattern]]] }.isEmpty)
    }

    @Test func eachDistinctSitePatternCountsOnce() throws {
        let found = try chrome {
            $0["permissions"] = ["storage"]
            $0["host_permissions"] = ["<all_urls>", "*://*/*", "https://*/*"]
            $0["content_scripts"] = [["matches": ["<all_urls>", "https://*/*"]], ["matches": ["*://*/*"]]]
        }
        #expect(found == [.extensionAllSites: 3])
    }

    @Test func optionalHostsAreAskedForLaterAndAreSilent() throws {
        #expect(try chrome { $0["optional_host_permissions"] = ["<all_urls>"]; $0["optional_permissions"] = ["<all_urls>"] }.isEmpty)
    }

    // MARK: Sensitive permissions

    @Test func sensitivePermissionsAreCountedOnceEach() throws {
        let found = try chrome {
            $0["permissions"] = ["cookies", "webRequest", "storage", "tabs", "cookies"]
            $0["optional_permissions"] = ["history", "cookies", "alarms"]
        }
        #expect(found == [.extensionSensitivePermissions: 3])
    }

    @Test(arguments: ["cookies", "webRequest", "webRequestBlocking", "history", "nativeMessaging", "debugger", "proxy", "management", "downloads",
                      "clipboardRead", "privacy", "browsingData", "contentSettings", "tabCapture", "desktopCapture", "pageCapture",
                      "declarativeNetRequestWithHostAccess"])
    func eachListedPermissionIsReported(permission: String) throws {
        #expect(try chrome { $0["permissions"] = [permission] } == [.extensionSensitivePermissions: 1])
    }

    @Test func ordinaryPermissionsAreSilent() throws {
        let ordinary = ["storage", "tabs", "activeTab", "alarms", "notifications", "contextMenus", "clipboardWrite", "declarativeNetRequest", "scripting",
                        "https://cookies.example.test/*"]
        #expect(try chrome { $0["permissions"] = ordinary }.isEmpty)
    }

    // MARK: Updates

    @Test func aChromeUpdateAddressOutsideTheStoresIsReported() throws {
        #expect(try chrome { $0["update_url"] = "https://updates.example.test/crx?key=abc" } == [.extensionSelfHostedUpdates: 1])
        #expect(try chrome { $0["update_url"] = "http://203.0.113.9/updates.xml" } == [.extensionSelfHostedUpdates: 1])
    }

    @Test(arguments: ["https://clients2.google.com/service/update2/crx", "https://update.googleapis.com/service/update2/crx",
                      "https://edge.microsoft.com/extensionwebstorebase/v1/crx", "not a url", ""])
    func storeAndUnusableUpdateAddressesAreSilent(address: String) throws {
        #expect(try chrome { $0["update_url"] = address }.isEmpty)
    }

    @Test func aFirefoxUpdateAddressIsReportedOnlyInTheGeckoSetting() throws {
        let gecko: (inout [String: Any]) -> Void = { $0["browser_specific_settings"] = ["gecko": ["id": "x@example.test", "update_url": "https://updates.example.test/u.json"]] }
        #expect(try firefox(gecko) == [.extensionSelfHostedUpdates: 1])
        #expect(try firefox { $0["applications"] = ["gecko": ["id": "x@example.test", "update_url": "https://updates.example.test/u.json"]]; $0["browser_specific_settings"] = nil }
                == [.extensionSelfHostedUpdates: 1])
        #expect(try firefox { $0["update_url"] = "https://updates.example.test/u.json" }.isEmpty)
        #expect(try chrome { $0["browser_specific_settings"] = ["gecko": ["update_url": "https://updates.example.test/u.json"]] }.isEmpty)
    }

    // MARK: Script policy

    @Test func aPolicyThatAllowsEvalIsReported() throws {
        #expect(try firefox { $0["content_security_policy"] = "script-src 'self' 'unsafe-eval'; object-src 'self'" } == [.extensionRelaxedScriptPolicy: 1])
        #expect(try firefox { $0["content_security_policy"] = "SCRIPT-SRC 'UNSAFE-EVAL'" } == [.extensionRelaxedScriptPolicy: 1])
        #expect(try chrome { $0["content_security_policy"] = ["extension_pages": "script-src 'self' 'unsafe-eval'"] } == [.extensionRelaxedScriptPolicy: 1])
    }

    @Test func otherPoliciesAreSilent() throws {
        #expect(try chrome { $0["content_security_policy"] = ["extension_pages": "script-src 'self' 'wasm-unsafe-eval'"] }.isEmpty)
        #expect(try chrome { $0["content_security_policy"] = ["sandbox": "sandbox allow-scripts; script-src 'self' 'unsafe-eval'"] }.isEmpty)
        #expect(try firefox { $0["content_security_policy"] = "script-src 'self'; object-src 'self'" }.isEmpty)
        #expect(try firefox { $0["content_security_policy"] = "default-src 'self'; img-src data: 'unsafe-inline-not-eval'" }.isEmpty)
        #expect(try firefox { $0["description"] = "mentions 'unsafe-eval' in prose" }.isEmpty)
    }

    // MARK: Native code and invisible characters

    @Test func nativeMembersAreCounted() throws {
        let files = BrowserExtensionAdapterTests.defaultFiles + [Member("host/helper.exe", Data("e".utf8)), Member("host/tool", AddOnFixtures.machO, deflated: true)]
        #expect(try chrome({ _ in }, files: files) == [.artifactNativeCode: 2])
    }

    @Test func invisibleCharactersInBackgroundAndContentScriptsAreCounted() throws {
        let files = [Member("background.js", text: "let a = 1;\(Self.zeroWidth)\n", deflated: true), Member("content.js", text: "// \u{202E}\n")]
        #expect(try chrome({ _ in }, files: files) == [.hiddenZeroWidth: 1, .hiddenBidirectionalControls: 1])
    }

    @Test func invisibleCharactersInManifestTextAreCounted() throws {
        #expect(try firefox { $0["name"] = "Tab\(Self.zeroWidth)Notes" } == [.hiddenZeroWidth: 1])
    }

    @Test func anOrdinaryExtensionHasNoFindings() throws {
        let busy = try chrome {
            $0["permissions"] = ["storage", "tabs", "alarms", "contextMenus"]
            $0["host_permissions"] = ["https://*.example.test/*"]
            $0["content_security_policy"] = ["extension_pages": "script-src 'self'; object-src 'self'", "sandbox": "sandbox allow-scripts"]
        }
        #expect(busy.isEmpty)
    }
}
