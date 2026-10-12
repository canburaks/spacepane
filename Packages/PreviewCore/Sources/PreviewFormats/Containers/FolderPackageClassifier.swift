import Foundation
import UniformTypeIdentifiers

/// Decides from a directory's name alone whether Finder presents it as one opaque item, such as an
/// application or framework bundle. The folder listing shows such a directory as a `package` and
/// never enumerates its contents. Only the name is consulted: asking the filesystem for the package
/// bit would need a path-based lookup that could follow a link swapped in after the descriptor-relative
/// metadata read, which the folder scan avoids on purpose.
struct FolderPackageClassifier {
    /// Well-known package suffixes, matched without consulting the type database so the result does
    /// not depend on which applications are installed on the Mac.
    static let knownSuffixes: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "xcarchive", "photoslibrary", "xcodeproj", "xcworkspace",
        "playground", "rtfd", "kext", "prefpane", "saver", "qlgenerator", "mdimporter", "xpc", "wdgt", "dsym",
        "systemextension", "dext", "driver", "workflow", "action", "component", "vst", "vst3", "xctest",
        "docset", "mlpackage", "scptd", "sparsebundle", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
        "logicx", "band"
    ]
    private static let maximumSuffixBytes = 32
    /// Suffixes resolved through the type database, so each is looked up at most once per request.
    private var resolved: [String: Bool] = [:]

    mutating func isPackage(name: String) -> Bool {
        // A leading dot starts a hidden name, not a suffix: ".app" has no extension.
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let suffix = name[name.index(after: dot)...].lowercased()
        guard !suffix.isEmpty, suffix.utf8.count <= Self.maximumSuffixBytes else { return false }
        if Self.knownSuffixes.contains(suffix) { return true }
        if let known = resolved[suffix] { return known }
        let isPackage = UTType(filenameExtension: suffix).map { $0.conforms(to: .package) || $0.conforms(to: .bundle) } ?? false
        resolved[suffix] = isPackage
        return isPackage
    }
}
