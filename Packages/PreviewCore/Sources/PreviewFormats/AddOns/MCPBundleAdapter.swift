import Foundation
import PreviewContracts

/// Summarizes an MCP bundle (`.mcpb`, formerly `.dxt`): a ZIP archive with a `manifest.json` at its root
/// that tells an AI app which local server to start, what it asks the person to configure and which tools
/// and prompts it offers.
///
/// The card states what the manifest declares and never runs, evaluates or follows anything in the
/// bundle: the archive is read through the shared bounded reader, the manifest is the one member read
/// whole, and server scripts are read only as capped prefixes to look for invisible characters.
/// Environment variables appear by name; their values and the settings' defaults are never shown.
/// Findings (decision 030) are counts of declared facts and carry no text from the file.
public struct MCPBundleAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let manifestPath = "manifest.json"

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let package = try AddOnArchive(source: source, context: context)
        let root = try package.manifest(at: Self.manifestPath)
        let manifest = MCPBundleManifest(root)
        let findings = try Self.findings(for: manifest, root: root, package: package, context: context)

        var fields = SummaryFields()
        fields.text("name", manifest.name)
        fields.text("displayName", manifest.displayName)
        fields.text("version", manifest.version)
        fields.text("description", manifest.description)
        fields.text("author", manifest.authorName)
        fields.text("license", manifest.license)
        fields.text("manifestVersion", manifest.manifestVersion)
        fields.text("serverType", manifest.serverType)
        fields.text("entryPoint", manifest.entryPoint)
        fields.text("command", manifest.command)
        AddOnSummary.markedList(&fields, "arguments", MCPBundleTextRules.markingCredentials(in: manifest.arguments))
        AddOnSummary.shortList(&fields, "environment", manifest.environmentNames)
        AddOnSummary.shortList(&fields, "platforms", manifest.platforms)
        AddOnSummary.markedList(&fields, "runtimes", manifest.runtimes.map { ("\($0.name) \($0.version)", SecretFieldPolicy.isSensitive($0.name)) })
        AddOnSummary.shortList(&fields, "tools", manifest.tools.compactMap(\.name))
        AddOnSummary.shortList(&fields, "prompts", manifest.prompts.compactMap(\.name))
        Self.addSettings(manifest.settings, to: &fields)
        package.addListing(to: &fields)
        return try PackageSummary.document(fields.value, context: context, findings: findings)
    }

    private static func addSettings(_ settings: [MCPBundleManifest.Setting], to fields: inout SummaryFields) {
        guard !settings.isEmpty else { return }
        fields.add("settings", .array(settings.prefix(AddOnLimits.listItems).map { setting in
            var items: [(String, SummaryValue)] = [("name", .string(PackageSummary.clipped(setting.name)))]
            if let type = setting.type { items.append(("type", .string(PackageSummary.clipped(type)))) }
            items += [("sensitive", .boolean(setting.sensitive)), ("required", .boolean(setting.required))]
            return .object(items)
        }))
    }

    // MARK: Findings

    private static func findings(for manifest: MCPBundleManifest, root: LensJSONNode, package: AddOnArchive,
                                 context: RequestContext) throws -> [PreviewFinding] {
        var findings: [PreviewFinding] = []
        if manifest.runsProgram { findings.append(PreviewFinding(kind: .bundleRunsProgram, count: 1)) }

        // A binary server's entry point is machine code even when its bytes cannot be checked.
        let native = try package.nativeMembers()
        var nativeCount = native.count
        if manifest.serverType?.equalsExactly("binary") == true {
            let entry = manifest.entryPoint.flatMap { AddOnPath.resolve($0) }
            if entry.map({ !native.contains($0) }) ?? true { nativeCount += 1 }
        }
        if nativeCount > 0 { findings.append(PreviewFinding(kind: .artifactNativeCode, count: nativeCount)) }

        let secrets = manifest.settings.filter(\.sensitive).count
        if secrets > 0 { findings.append(PreviewFinding(kind: .bundleAsksForSecrets, count: secrets)) }
        if manifest.wholeFolderUses > 0 { findings.append(PreviewFinding(kind: .bundleBroadFolderAccess, count: manifest.wholeFolderUses)) }

        var targeting = 0
        for offering in manifest.tools + manifest.prompts {
            try context.checkpoint()
            if offering.texts.contains(where: MCPBundleTextRules.targetsAssistant) { targeting += 1 }
        }
        if targeting > 0 { findings.append(PreviewFinding(kind: .bundleToolTextTargetsAssistant, count: targeting)) }

        var hidden = AddOnHiddenTally()
        try AddOnManifestText.forEachString(in: root, context: context) { try hidden.add($0, context: context) }
        try package.addScriptText(preferred: manifest.scriptPaths, to: &hidden)
        return findings + hidden.findings
    }
}
