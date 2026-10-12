import Foundation

/// The descriptive fields shared by macOS application bundles and iOS archives, read from the bundle's
/// `Info.plist`. Only identity, version and capability counts are surfaced; localized resource
/// references, URL scheme names and usage-description prose are not.
enum BundleInfoSummary {
    private static let usageDescriptionSuffix = "UsageDescription"
    private static let deviceFamilyNames: [Int: String] = [
        1: "iPhone", 2: "iPad", 3: "Apple TV", 4: "Apple Watch", 6: "Mac", 7: "Apple Vision"
    ]

    static func fields(_ info: [String: Any]) -> SummaryFields {
        var fields = SummaryFields()
        fields.text("name", PlistAccess.string(info, "CFBundleName"))
        fields.text("displayName", PlistAccess.string(info, "CFBundleDisplayName"))
        fields.text("bundleIdentifier", PlistAccess.string(info, "CFBundleIdentifier"))
        fields.text("version", PlistAccess.string(info, "CFBundleShortVersionString"))
        fields.text("build", PlistAccess.string(info, "CFBundleVersion"))
        fields.text("minimumOSVersion", PlistAccess.string(info, "LSMinimumSystemVersion")
                    ?? PlistAccess.string(info, "MinimumOSVersion"))
        fields.text("category", PlistAccess.string(info, "LSApplicationCategoryType"))
        fields.text("executable", PlistAccess.string(info, "CFBundleExecutable"))
        fields.list("platforms", PlistAccess.strings(info, "CFBundleSupportedPlatforms"))
        let families = (PlistAccess.array(info, "UIDeviceFamily")).compactMap { ($0 as? NSNumber).flatMap { deviceFamilyNames[$0.intValue] } }
        fields.list("deviceFamilies", families)
        let documentTypes = PlistAccess.array(info, "CFBundleDocumentTypes").count
        if documentTypes > 0 { fields.number("documentTypes", documentTypes) }
        let schemes = PlistAccess.dictionaries(info, "CFBundleURLTypes").reduce(0) { $0 + PlistAccess.strings($1, "CFBundleURLSchemes").count }
        if schemes > 0 { fields.number("urlSchemes", schemes) }
        fields.list("usageDescriptions", info.keys.filter { $0.hasSuffix(usageDescriptionSuffix) }.sorted())
        return fields
    }

    /// Base names listed for an iOS icon (`CFBundleIconFiles`, primary icon sets, and the asset-catalog
    /// icon name, whose rendered files Xcode names with that prefix).
    static func iconBaseNames(_ info: [String: Any]) -> [String] {
        var names = PlistAccess.strings(info, "CFBundleIconFiles")
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard let icons = info[key] as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else { continue }
            names += PlistAccess.strings(primary, "CFBundleIconFiles")
            if let name = PlistAccess.string(primary, "CFBundleIconName") { names.append(name) }
        }
        if let name = PlistAccess.string(info, "CFBundleIconName") { names.append(name) }
        var seen = Set<String>()
        return names.map { ($0 as NSString).deletingPathExtension }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
