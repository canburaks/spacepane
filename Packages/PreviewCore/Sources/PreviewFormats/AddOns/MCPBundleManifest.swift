import Foundation
import PreviewContracts

/// What an MCP bundle's `manifest.json` declares (the MCPB manifest, formerly DXT): the server it
/// starts, the configuration it asks for, and the tools and prompts it offers. Members of another type
/// than the specification gives read as absent. Environment variables are kept by name only.
struct MCPBundleManifest {
    /// A user configuration entry. Its value and default are never kept.
    struct Setting {
        let name: String
        let type: String?
        let sensitive: Bool
        let required: Bool
    }

    /// A tool or prompt: its name, and every text that tells the assistant about it.
    struct Offering {
        let name: String?
        let texts: [String]
    }

    let manifestVersion: String?
    let name: String?
    let displayName: String?
    let version: String?
    let description: String?
    let authorName: String?
    let license: String?
    let serverType: String?
    let entryPoint: String?
    let command: String?
    let arguments: [String]
    let environmentNames: [String]
    let platforms: [String]
    let runtimes: [(name: String, version: String)]
    let tools: [Offering]
    let prompts: [Offering]
    let settings: [Setting]
    /// The server starts a program: it has a type, or a command in the base or a platform override.
    let runsProgram: Bool
    /// Arguments, environment values and folder defaults that are exactly a whole personal folder.
    let wholeFolderUses: Int
    /// Archive paths worth scanning first: the entry point and `${__dirname}` arguments.
    let scriptPaths: [String]

    init(_ root: LensJSONNode) {
        manifestVersion = root.member("manifest_version")?.value.scalarText ?? root.member("dxt_version")?.value.scalarText
        name = root.text("name")
        displayName = root.text("display_name")
        version = root.member("version")?.value.scalarText
        description = root.text("description")
        let author = root.member("author")?.value
        authorName = author?.string ?? author?.text("name")
        license = root.text("license")

        let server = root.at("server")
        serverType = server?.text("type")
        entryPoint = server?.text("entry_point")
        let base = server?.at("mcp_config")
        var configs: [LensJSONNode] = base.map { [$0] } ?? []
        configs += (base?.at("platform_overrides")?.members ?? []).map(\.value)
        command = base?.text("command")
        arguments = base?.texts("args") ?? []
        runsProgram = serverType != nil || configs.contains { $0.text("command") != nil }

        var names: [String] = []
        var seen = Set<String>()
        var wholeFolders = 0
        for config in configs {
            for variable in config.at("env")?.members ?? [] {
                if seen.insert(variable.key).inserted { names.append(variable.key) }
                if let value = variable.value.string, MCPBundleTextRules.isWholeFolder(value) { wholeFolders += 1 }
            }
            wholeFolders += config.texts("args").filter(MCPBundleTextRules.isWholeFolder).count
        }
        environmentNames = names

        var settings: [Setting] = []
        for entry in root.at("user_config")?.members ?? [] where entry.value.members != nil {
            let node = entry.value
            let type = node.text("type")
            settings.append(Setting(name: entry.key, type: type, sensitive: node.flag("sensitive") == true,
                                    required: node.flag("required") == true))
            // A folder setting whose default is a whole personal folder starts the server there.
            if type == "directory", let defaults = node.member("default")?.value {
                let values = defaults.string.map { [$0] } ?? defaults.textElements
                wholeFolders += values.filter(MCPBundleTextRules.isWholeFolder).count
            }
        }
        self.settings = settings
        wholeFolderUses = wholeFolders

        let compatibility = root.at("compatibility")
        platforms = compatibility?.texts("platforms") ?? []
        runtimes = (compatibility?.at("runtimes")?.members ?? []).compactMap { member in
            member.value.scalarText.map { (member.key, $0) }
        }
        tools = Self.offerings(root.member("tools")?.value, textKeys: ["description"])
        prompts = Self.offerings(root.member("prompts")?.value, textKeys: ["description", "text"])

        let dirname = "${__dirname}"
        var paths = [entryPoint].compactMap { $0 }
        paths += arguments.filter { $0.hasPrefix(dirname) }.map { String($0.dropFirst(dirname.count)) }
        scriptPaths = paths.compactMap { AddOnPath.resolve($0) }
    }

    private static func offerings(_ node: LensJSONNode?, textKeys: [String]) -> [Offering] {
        (node?.elements ?? []).filter { $0.members != nil }.map { item in
            Offering(name: item.text("name"), texts: textKeys.compactMap { item.text($0) })
        }
    }
}
