import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Add-on summary labels")
struct Sl3AddonsLabelTests {
    private let set = SummaryLabelSet.addOns

    /// The keys the three add-on adapters write at the root of a summary (decision 030).
    private static let emitted: [FormatID: [String]] = [
        .mcpBundle: ["name", "displayName", "version", "description", "author", "license", "manifestVersion", "serverType",
                     "entryPoint", "command", "arguments", "environment", "platforms", "runtimes", "tools", "prompts", "settings",
                     "archiveFormat", "listedEntries", "partial", "entries"],
        .editorExtension: ["publisher", "name", "displayName", "version", "description", "engine", "entry", "webEntry",
                           "activationEvents", "categories", "commands", "extensionPack", "extensionDependencies",
                           "untrustedWorkspaces", "archiveFormat", "listedEntries", "partial", "entries"],
        .browserExtension: ["browser", "name", "version", "manifestVersion", "description", "addonID", "permissions",
                            "optionalPermissions", "hostPermissions", "contentScriptMatches", "background", "updateURL",
                            "archiveFormat", "listedEntries", "partial", "entries"]
    ]

    @Test func oneSetOwnsTheThreeFormats() {
        #expect(set.formats == [.mcpBundle, .editorExtension, .browserExtension])
    }

    @Test func everyKeyTheAdaptersWriteIsATranslatableLabel() throws {
        let owned = try #require(set.fields([]))
        for (format, keys) in Self.emitted {
            for key in keys {
                #expect(owned.contains(key), "\(format.rawValue) writes \(key)")
                #expect(set.keys[key] != nil, "\(key) has no label key")
            }
        }
    }

    @Test func everyOwnedFieldHasALabelKey() throws {
        for path in [[], ["settings", "[]"], ["entries", "[]"]] as [[String]] {
            for field in try #require(set.fields(path)) { #expect(set.keys[field] != nil, "\(path) \(field)") }
        }
    }

    @Test func onlyTheAdaptersOwnPathsAreOwned() {
        #expect(set.fields(["settings", "[]"]) == ["name", "type", "sensitive", "required"])
        #expect(set.fields(["entries", "[]"]) == ["path", "type", "bytes", "modified"])
        #expect(set.fields(["tools"]) == nil && set.fields(["environment"]) == nil && set.fields(["settings"]) == nil)
    }

    @Test func newLabelsUseTheAddOnKeyPrefixAndOldOnesAreReused() {
        let addOnKeys = set.keys.values.filter { $0.rawValue.hasPrefix("preview.addon.") }
        #expect(addOnKeys.count == 32 && Set(addOnKeys).count == 32)
        #expect(set.keys["name"] == .summaryName && set.keys["version"] == .packageVersion && set.keys["permissions"] == .packagePermissions)
    }

    @Test func documentTextAndBooleansKeepTheirMeaning() {
        for field in ["name", "description", "command", "entryPoint", "updateURL", "addonID", "version"] {
            #expect(set.verbatimFields.contains(field), "\(field)")
        }
        #expect(set.booleanFields.isSuperset(of: ["sensitive", "required", "untrustedWorkspaces", "partial"]))
        #expect(set.countFields.contains("commands") && !set.countFields.contains("version"))
        #expect(set.valueLabels["type"]?["directory"] == .summaryKindDirectory)
    }
}
