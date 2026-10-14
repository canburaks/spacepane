import Foundation
import PreviewContracts

/// Summarizes a Visual Studio Code extension package (`.vsix`): a ZIP archive whose `extension/package.json`
/// names the publisher, the entry files, the events that start the extension and the extensions it
/// pulls in.
///
/// The card states what the manifest declares. It cannot see code that changes after publication or a
/// dependency that turns hostile later, and it never runs anything: the manifest is the one member read
/// whole, and script members are read only as capped prefixes to look for invisible characters, which
/// supply-chain attacks on this ecosystem have used to hide code. Findings carry counts, not text.
public struct EditorExtensionAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let root = "extension/"
    static let manifestPath = root + "package.json"
    /// Activation events that start the extension without anything the person did.
    static let automaticEvents = ["*", "onStartupFinished"]

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let package = try AddOnArchive(source: source, context: context)
        let manifest = try package.manifest(at: Self.manifestPath)

        let activationEvents = manifest.texts("activationEvents")
        let pack = manifest.texts("extensionPack")
        let dependencies = manifest.texts("extensionDependencies")
        let entry = manifest.text("main")
        let webEntry = manifest.text("browser")

        var fields = SummaryFields()
        fields.text("publisher", manifest.text("publisher"))
        fields.text("name", manifest.text("name"))
        fields.text("displayName", manifest.text("displayName"))
        fields.text("version", manifest.member("version")?.value.scalarText)
        fields.text("description", manifest.text("description"))
        fields.text("engine", manifest.at("engines")?.text("vscode"))
        fields.text("entry", entry)
        fields.text("webEntry", webEntry)
        AddOnSummary.shortList(&fields, "activationEvents", activationEvents)
        AddOnSummary.shortList(&fields, "categories", manifest.texts("categories"))
        let commands = manifest.at("contributes")?.member("commands")?.value.elements?.count ?? 0
        if commands > 0 { fields.number("commands", commands) }
        AddOnSummary.shortList(&fields, "extensionPack", pack)
        AddOnSummary.shortList(&fields, "extensionDependencies", dependencies)
        if let supported = manifest.at("capabilities", "untrustedWorkspaces")?.member("supported")?.value {
            if let flag = supported.bool { fields.flag("untrustedWorkspaces", flag) } else { fields.text("untrustedWorkspaces", supported.string) }
        }
        package.addListing(to: &fields)

        var findings: [PreviewFinding] = []
        if activationEvents.contains(where: { event in Self.automaticEvents.contains { event.equalsExactly($0) } }) {
            findings.append(PreviewFinding(kind: .extensionStartsAutomatically, count: 1))
        }
        let installed = Set(pack + dependencies).count
        if installed > 0 { findings.append(PreviewFinding(kind: .extensionInstallsOthers, count: installed)) }
        let native = try package.nativeMembers().count
        if native > 0 { findings.append(PreviewFinding(kind: .artifactNativeCode, count: native)) }

        var hidden = AddOnHiddenTally()
        try AddOnManifestText.forEachString(in: manifest, context: context) { try hidden.add($0, context: context) }
        let declared = [entry, webEntry].compactMap { $0 }.compactMap { AddOnPath.resolve($0, under: Self.root) }
        try package.addScriptText(preferred: declared, to: &hidden)
        findings += hidden.findings
        return try PackageSummary.document(fields.value, context: context, findings: findings)
    }
}
