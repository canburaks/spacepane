import Foundation

/// SwiftPM's native and Xcode build systems generate different bundle accessors.
/// Prefer the standard signed app/extension Resources directory when staged manually.
enum RendererResources {
    static let bundleName = "PreviewCore_PreviewRenderers"
    static let bundle = resolve(in: .main) { Bundle.module }

    static func resolve(in host: Bundle, fallback: () -> Bundle) -> Bundle {
        if let resources = host.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent(bundleName).appendingPathExtension("bundle")) {
            return bundle
        }
        return fallback()
    }
}
