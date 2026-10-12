import Foundation

/// SwiftPM's native command-line accessor does not search Contents/Resources.
/// Prefer this module's actual embedded bundle when the host is an app/extension;
/// keep SwiftPM's generated lookup for tests and ordinary package consumers.
enum ContractResources {
    static let bundleName = "PreviewCore_PreviewContracts"
    static let bundle = resolve(in: .main) { Bundle.module }

    static func resolve(in host: Bundle, fallback: () -> Bundle) -> Bundle {
        if let url = host.resourceURL?.appendingPathComponent(bundleName).appendingPathExtension("bundle"),
           let embedded = Bundle(url: url) {
            return embedded
        }
        return fallback()
    }
}
