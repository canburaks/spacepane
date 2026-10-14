import Foundation

/// What a browser extension's `manifest.json` declares, for Chrome-family and Firefox packages alike.
/// The two families share most keys; where they differ (the update address, the places a host pattern
/// may appear) the declared facts are read in the family's own way. Members of another type than the
/// documentation gives read as absent.
struct BrowserExtensionManifest {
    enum Family { case chromium, firefox }

    /// Permissions that reach beyond the page the person is on, as named in the extension manifest
    /// documentation of both families. The set is a list of facts, not a judgement of any one extension.
    static let sensitivePermissions: Set<String> = [
        "cookies", "webRequest", "webRequestBlocking", "history", "nativeMessaging", "debugger", "proxy", "management",
        "downloads", "clipboardRead", "privacy", "browsingData", "contentSettings", "tabCapture", "desktopCapture",
        "pageCapture", "declarativeNetRequestWithHostAccess"
    ]

    /// Hosts that serve the stores' own updates. Anything else is an update address the publisher runs.
    static let storeUpdateHosts: Set<String> = ["clients2.google.com", "update.googleapis.com", "edge.microsoft.com"]

    let name: String?
    let version: String?
    let description: String?
    let manifestVersion: Int?
    let addonID: String?
    /// Named permissions (`tabs`, `storage`), without host patterns.
    let permissions: [String]
    /// Optional permissions and optional host patterns, as written.
    let optionalPermissions: [String]
    /// Host patterns from `host_permissions` and, in manifest version 2, from `permissions`.
    let hostPermissions: [String]
    let contentScriptMatches: [String]
    /// Background service worker, scripts or page.
    let background: [String]
    /// The update address of the family: `update_url` for Chrome, the gecko setting for Firefox.
    let updateURL: String?
    let relaxedScriptPolicy: Bool
    /// Archive paths worth scanning first: the background code, then the content scripts.
    let scriptPaths: [String]

    init(_ root: LensJSONNode, family: Family) {
        name = root.text("name")
        version = root.member("version")?.value.scalarText
        description = root.text("description")
        manifestVersion = root.integer("manifest_version")
        let gecko = root.at("browser_specific_settings", "gecko") ?? root.at("applications", "gecko")
        addonID = gecko?.text("id")

        var named: [String] = []
        var hosts: [String] = []
        for permission in root.texts("permissions") {
            if Self.isHostPattern(permission) { hosts.append(permission) } else { named.append(permission) }
        }
        hosts += root.texts("host_permissions")
        permissions = named
        hostPermissions = hosts
        optionalPermissions = root.texts("optional_permissions") + root.texts("optional_host_permissions")

        let scripts = (root.member("content_scripts")?.value.elements ?? []).filter { $0.members != nil }
        contentScriptMatches = scripts.flatMap { $0.texts("matches") }

        var background: [String] = []
        let node = root.at("background")
        background += node?.text("service_worker").map { [$0] } ?? []
        background += node?.texts("scripts") ?? []
        background += node?.text("page").map { [$0] } ?? []
        self.background = background
        scriptPaths = (background + scripts.flatMap { $0.texts("js") }).compactMap { AddOnPath.resolve($0) }

        updateURL = family == .firefox ? gecko?.text("update_url") : root.text("update_url")
        relaxedScriptPolicy = Self.allowsUnsafeEval(root.member("content_security_policy")?.value)
    }

    // MARK: Derived facts

    /// Patterns that reach every site, from the permissions, host permissions and content scripts the
    /// extension requests when it is installed (optional ones are asked for later).
    var allSitesPatterns: Int { Set((hostPermissions + contentScriptMatches).filter(Self.isAllSites)).count }

    /// Distinct sensitive permission names, requested or optional.
    var sensitivePermissionCount: Int {
        Set((permissions + optionalPermissions).filter(Self.sensitivePermissions.contains)).count
    }

    /// Whether the extension's updates come from the publisher instead of the store. A Chrome address on
    /// a store host, or one with no usable host, says nothing; any Firefox update address is the
    /// publisher's, because the store supplies its own.
    func hasSelfHostedUpdates(_ family: Family) -> Bool {
        guard let updateURL else { return false }
        switch family {
        case .firefox: return true
        case .chromium:
            guard let host = AddOnURL.components(of: updateURL)?.host else { return false }
            return !Self.storeUpdateHosts.contains(host)
        }
    }

    // MARK: Patterns and policies

    static func isHostPattern(_ text: String) -> Bool { text == "<all_urls>" || text.contains("://") }

    /// `<all_urls>`, or a web pattern whose host is exactly `*` (`*://*/*`, `https://*/*`).
    static func isAllSites(_ pattern: String) -> Bool {
        if pattern == "<all_urls>" { return true }
        guard let separator = pattern.range(of: "://") else { return false }
        let scheme = pattern[..<separator.lowerBound].lowercased()
        let host = pattern[separator.upperBound...].prefix { $0 != "/" }
        return host == "*" && ["*", "http", "https", "ws", "wss", "ftp"].contains(scheme)
    }

    /// Whether a content security policy lets script evaluate strings. A string policy is one
    /// (Manifest version 2, Firefox); an object holds one per page kind (version 3). The `sandbox`
    /// policy is left out: it applies to pages with no access to the extension's rights, where the
    /// documentation sends extensions that need `eval` on purpose.
    static func allowsUnsafeEval(_ policy: LensJSONNode?) -> Bool {
        var policies: [String] = []
        if let text = policy?.string { policies.append(text) }
        else { policies += (policy?.members ?? []).filter { !$0.key.equalsExactly("sandbox") }.compactMap { $0.value.string } }
        return policies.contains { policy in
            policy.lowercased().split(whereSeparator: { $0 == ";" || $0.isWhitespace }).contains("'unsafe-eval'")
        }
    }
}
