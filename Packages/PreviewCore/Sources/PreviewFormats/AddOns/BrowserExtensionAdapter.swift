import Foundation
import PreviewContracts

/// Summarizes a browser extension package: a Firefox add-on (`.xpi`, a ZIP archive) or a Chrome-family
/// extension (`.crx`, a CRX2 or CRX3 header followed by a ZIP archive). Both keep a `manifest.json` at the
/// archive's root.
///
/// The card states what the manifest asks for: the permissions, the sites it can reach, where its updates
/// come from. It says nothing about whether the package is signed or who signed it, because the CRX header
/// is never parsed, and it cannot see an extension that behaves until a later update. Nothing is run.
/// Findings carry counts, not the permission names or addresses, which the card shows as the file's content.
public struct BrowserExtensionAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let manifestPath = "manifest.json"

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let layout = try CRXContainer.layout(of: source, context: context)
        let archiveSource: any PreviewByteSource = layout.map { OffsetByteSource(base: source, offset: $0.archiveOffset) } ?? source
        let package = try AddOnArchive(source: archiveSource, context: context)
        let root = try package.manifest(at: Self.manifestPath)

        // A `.crx` that turns out to be a plain archive is still a Chrome package.
        let family: BrowserExtensionManifest.Family = layout != nil || context.nameHint?.suffix == "crx" ? .chromium : .firefox
        let manifest = BrowserExtensionManifest(root, family: family)

        var fields = SummaryFields()
        fields.text("browser", Self.browser(family, layout: layout))
        fields.text("name", manifest.name)
        fields.text("version", manifest.version)
        fields.number("manifestVersion", manifest.manifestVersion)
        fields.text("description", manifest.description)
        fields.text("addonID", manifest.addonID)
        AddOnSummary.shortList(&fields, "permissions", manifest.permissions)
        AddOnSummary.shortList(&fields, "optionalPermissions", manifest.optionalPermissions)
        AddOnSummary.shortList(&fields, "hostPermissions", manifest.hostPermissions)
        AddOnSummary.shortList(&fields, "contentScriptMatches", manifest.contentScriptMatches)
        AddOnSummary.shortList(&fields, "background", manifest.background)
        // Update addresses carry keys in their paths and queries; the card shows where they point.
        fields.text("updateURL", manifest.updateURL.flatMap(AddOnURL.origin))
        package.addListing(to: &fields)

        var findings: [PreviewFinding] = []
        if manifest.allSitesPatterns > 0 { findings.append(PreviewFinding(kind: .extensionAllSites, count: manifest.allSitesPatterns)) }
        if manifest.sensitivePermissionCount > 0 {
            findings.append(PreviewFinding(kind: .extensionSensitivePermissions, count: manifest.sensitivePermissionCount))
        }
        if manifest.hasSelfHostedUpdates(family) { findings.append(PreviewFinding(kind: .extensionSelfHostedUpdates, count: 1)) }
        if manifest.relaxedScriptPolicy { findings.append(PreviewFinding(kind: .extensionRelaxedScriptPolicy, count: 1)) }
        let native = try package.nativeMembers().count
        if native > 0 { findings.append(PreviewFinding(kind: .artifactNativeCode, count: native)) }

        var hidden = AddOnHiddenTally()
        try AddOnManifestText.forEachString(in: root, context: context) { try hidden.add($0, context: context) }
        try package.addScriptText(preferred: manifest.scriptPaths, to: &hidden)
        return try PackageSummary.document(fields.value, context: context, findings: findings + hidden.findings)
    }

    private static func browser(_ family: BrowserExtensionManifest.Family, layout: CRXContainer.Layout?) -> String {
        switch (family, layout?.version) {
        case (_, 3?): "Chrome (CRX3)"
        case (_, 2?): "Chrome (CRX2)"
        case (.chromium, _): "Chrome (ZIP)"
        case (.firefox, _): "Firefox (XPI)"
        }
    }
}
