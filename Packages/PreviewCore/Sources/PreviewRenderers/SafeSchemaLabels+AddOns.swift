import Foundation
import PreviewContracts

/// Summary schema written by the MCP bundle, editor extension and browser extension adapters (decision
/// 030). Only the app-owned field names listed here are translated. Names, identifiers, paths,
/// permissions, patterns, addresses, commands and every other value of the package stay exactly as stored.
extension SummaryLabelSet {
    static let addOns = SummaryLabelSet(
        formats: [.mcpBundle, .editorExtension, .browserExtension],
        fields: { parent in
            switch parent {
            case []:
                return ["name", "displayName", "version", "description", "author", "license", "manifestVersion",
                        "serverType", "entryPoint", "command", "arguments", "environment", "platforms", "runtimes",
                        "tools", "prompts", "settings",
                        "publisher", "engine", "entry", "webEntry", "activationEvents", "categories", "commands",
                        "extensionPack", "extensionDependencies", "untrustedWorkspaces",
                        "browser", "addonID", "permissions", "optionalPermissions", "hostPermissions",
                        "contentScriptMatches", "background", "updateURL",
                        "archiveFormat", "listedEntries", "partial", "entries"]
            case ["settings", "[]"]: return ["name", "type", "sensitive", "required"]
            case ["entries", "[]"]: return ["path", "type", "bytes", "modified"]
            default: return nil
            }
        },
        keys: [
            "name": .summaryName, "path": .summaryPath, "type": .summaryType, "bytes": .summaryBytes,
            "partial": .summaryPartial, "entries": .summaryEntries, "listedEntries": .summaryListedEntries,
            "archiveFormat": .packageContainerFormat, "modified": .packageModified,
            "displayName": .packageDisplayName, "version": .packageVersion, "platforms": .packagePlatforms,
            "permissions": .packagePermissions,
            "description": .addOnDescription, "author": .addOnAuthor, "license": .addOnLicense,
            "manifestVersion": .addOnManifestVersion, "serverType": .addOnServerType, "entryPoint": .addOnEntryPoint,
            "command": .addOnCommand, "arguments": .addOnArguments, "environment": .addOnEnvironment,
            "runtimes": .addOnRuntimes, "tools": .addOnTools, "prompts": .addOnPrompts, "settings": .addOnSettings,
            "sensitive": .addOnSensitive, "required": .addOnRequired,
            "publisher": .addOnPublisher, "engine": .addOnEngine, "entry": .addOnEntry, "webEntry": .addOnWebEntry,
            "activationEvents": .addOnActivationEvents, "categories": .addOnCategories, "commands": .addOnCommands,
            "extensionPack": .addOnExtensionPack, "extensionDependencies": .addOnExtensionDependencies,
            "untrustedWorkspaces": .addOnUntrustedWorkspaces,
            "browser": .addOnBrowser, "addonID": .addOnAddonID, "optionalPermissions": .addOnOptionalPermissions,
            "hostPermissions": .addOnHostPermissions, "contentScriptMatches": .addOnContentScriptMatches,
            "background": .addOnBackground, "updateURL": .addOnUpdateURL
        ],
        verbatimFields: ["name", "displayName", "version", "description", "author", "license", "manifestVersion",
                         "serverType", "entryPoint", "command", "publisher", "engine", "entry", "webEntry",
                         "browser", "addonID", "updateURL", "path"],
        booleanFields: ["partial", "sensitive", "required", "untrustedWorkspaces"],
        countFields: ["listedEntries", "bytes", "commands"],
        valueLabels: ["type": entryKinds])
}
