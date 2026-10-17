import Foundation
import Darwin

/// Read-only Foundation resource inspection. This does not execute the app or
/// either extension and cannot establish a Finder host's effective language.
///
/// Two modes share one manifest. With `systemLanguage` absent, `preferences` select a language
/// explicitly. With `systemLanguage` set, the lookup passes no preferences at all, the way the
/// production string API does (`PreviewStrings.text`): the script stages a copy of one host with this
/// executable inside it, so that `Bundle.main` is that host, and launches it with the system language
/// set. The nested bundle's `Bundle.localizedString` must then return the expected language by itself.
/// macOS resolves a nested bundle's language through the main bundle, which a bare executable lacks.
private struct Manifest: Decodable {
    let preferences: [String]
    let systemLanguage: String?
    let expectedLanguage: String
    let formattingLocale: String
    let bundles: [Host]
    let strings: [String: String]

    struct Host: Decodable {
        let role: String
        let path: String
        let metadata: [String: String]
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

@main
struct LocalizedBundleChecks {
    static func main() {
        do { try inspect() }
        catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    private static func inspect() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw CheckFailure(description: "Expected a temporary resource-check manifest")
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        for expected in manifest.bundles {
            let host = try loadBundle(URL(fileURLWithPath: expected.path), label: expected.role)
            if manifest.systemLanguage != nil {
                try require(Bundle.main.bundleURL.standardizedFileURL == host.bundleURL.standardizedFileURL,
                            "The checker is not running as the staged \(expected.role) host: \(Bundle.main.bundleURL.path)")
            }
            guard let hostResources = host.resourceURL else {
                throw CheckFailure(description: "Missing Resources directory: \(expected.role)")
            }
            let embeddedURL = hostResources.appendingPathComponent("PreviewCore_PreviewRenderers.bundle")
            let resources = try loadBundle(embeddedURL, label: "\(expected.role) renderer resources")
            try require(resources.bundleURL.standardizedFileURL == embeddedURL.standardizedFileURL,
                        "Resource lookup escaped the supplied host: \(expected.role)")
            let localizedResources: Bundle
            let localizedHostMetadata: Bundle
            if let systemLanguage = manifest.systemLanguage {
                // No preferences: whatever the bundle itself resolves. The system language of this process
                // must be the injected one, or an English answer would prove nothing.
                try require(Locale.preferredLanguages.first?.hasPrefix(systemLanguage) == true,
                            "The checker did not start with system language \(systemLanguage): \(Locale.preferredLanguages)")
                localizedResources = resources
                localizedHostMetadata = host
            } else {
                localizedResources = try localizedBundle(resources, preferences: manifest.preferences,
                                                         expectedLanguage: manifest.expectedLanguage, role: expected.role)
                localizedHostMetadata = try localizedBundle(host, preferences: manifest.preferences,
                                                            expectedLanguage: manifest.expectedLanguage, role: expected.role)
            }

            for key in manifest.strings.keys.sorted() {
                let actual = localizedResources.localizedString(forKey: key, value: "MISSING_TRANSLATION", table: nil)
                try require(actual == manifest.strings[key],
                            "Missing or stale embedded translation: \(expected.role)/\(manifest.expectedLanguage)/\(key)"
                                + (manifest.systemLanguage.map { " (system language \($0), no explicit preferences)" } ?? "")
                                + "; got \"\(actual.prefix(60))\"")
            }
            for key in expected.metadata.keys.sorted() {
                let actual = localizedHostMetadata.localizedString(forKey: key, value: "MISSING_METADATA", table: "InfoPlist")
                try require(actual == expected.metadata[key],
                            "Missing or stale localized metadata: \(expected.role)/\(manifest.expectedLanguage)/\(key)")
            }

            // UI interpolation must preserve user values, even when the language
            // and formatting region differ or the value contains RTL characters.
            let sourceSpelling = "package.json / .env.* / İı / e\u{301} / 9007199254740993 / مثال"
            let template = localizedResources.localizedString(forKey: "appearance.unavailableFontFamily", value: nil, table: nil)
            let formatted = String(format: template, locale: Locale(identifier: manifest.formattingLocale), arguments: [sourceSpelling])
            try require(formatted.components(separatedBy: sourceSpelling).count == 2,
                        "Interpolation changed argument spelling: \(expected.role)/\(manifest.expectedLanguage)")
            let position = localizedResources.localizedString(forKey: "midi.positionValue", value: nil, table: nil)
            let times = String(format: position, locale: Locale(identifier: manifest.formattingLocale), arguments: ["1:02", "3:04"])
            try require(times.contains("1:02") && times.contains("3:04"),
                        "Runtime formatting dropped a position argument: \(expected.role)/\(manifest.expectedLanguage)")
        }
        print("Foundation bundle resources passed: \(manifest.expectedLanguage), \(manifest.bundles.count) hosts, \(manifest.strings.count) keys")
    }

    private static func loadBundle(_ url: URL, label: String) throws -> Bundle {
        guard FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) else {
            throw CheckFailure(description: "Missing bundle: \(label)")
        }
        return bundle
    }

    private static func localizedBundle(_ bundle: Bundle, preferences: [String],
                                        expectedLanguage: String, role: String) throws -> Bundle {
        let matches = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: preferences)
        guard let language = matches.first,
              language.caseInsensitiveCompare(expectedLanguage) == .orderedSame,
              let path = bundle.path(forResource: language, ofType: "lproj") else {
            throw CheckFailure(description: "Explicit Foundation language selection failed: \(role)/\(expectedLanguage)")
        }
        return try loadBundle(URL(fileURLWithPath: path), label: "\(role)/\(expectedLanguage)")
    }
}
