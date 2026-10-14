import Foundation
import PreviewContracts

/// Where the parts of a wheel's installation sit in its member list (decision 030). The wheel format puts
/// the package's own files at the root, its metadata in one `<name>-<version>.dist-info` folder, and
/// anything that is installed elsewhere in a sibling `<name>-<version>.data` folder: `purelib` and
/// `platlib` go into site-packages, `scripts` into the environment's `bin`. Only names are used here.
struct WheelLayout {
    private static let distInfoSuffix = ".dist-info"

    /// The metadata folder's name, for example `example-1.0.dist-info`.
    let distInfo: String
    /// The `.pth` files that installation puts into site-packages: at the wheel root, or at the root of
    /// the data folder's `purelib` or `platlib`. Python runs the `import` lines of such a file at start.
    let startupFiles: [ZIPEntry]
    /// Files of the data folder's `scripts`, as paths relative to it. They are installed as commands.
    let installedScripts: [String]

    /// `<name>` and `<version>` as the folder names them; used only when METADATA does not say.
    var identity: (name: String, version: String?) {
        let stem = String(distInfo.dropLast(Self.distInfoSuffix.count))
        guard let dash = stem.firstIndex(of: "-") else { return (stem, nil) }
        return (String(stem[..<dash]), String(stem[stem.index(after: dash)...]))
    }

    /// - Throws: `malformedDocument` unless the wheel has exactly one metadata folder.
    init(_ entries: [ZIPEntry], context: RequestContext) throws {
        var folder: String?
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = parts.first.map(String.init), first.hasSuffix(Self.distInfoSuffix),
                  first.count > Self.distInfoSuffix.count, parts.count > 1 || entry.kind == "directory" else { continue }
            if let folder, !folder.equalsExactly(first) { throw PreviewFailure.malformedDocument }
            folder = first
        }
        guard let folder else { throw PreviewFailure.malformedDocument }
        distInfo = folder
        let data = String(folder.dropLast(Self.distInfoSuffix.count)) + ".data"
        var startup: [ZIPEntry] = []
        var scripts: [String] = []
        for (index, entry) in entries.enumerated() where entry.kind == "file" {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.last else { continue }
            if parts.count == 1 || (parts.count == 3 && parts[0].equalsExactly(data)
                                    && (parts[1].equalsExactly("purelib") || parts[1].equalsExactly("platlib"))) {
                // Python's site module skips names that start with a dot, and matches the suffix exactly.
                if name.hasSuffix(".pth"), !name.hasPrefix(".") { startup.append(entry) }
            } else if parts.count >= 3, parts[0].equalsExactly(data), parts[1].equalsExactly("scripts") {
                scripts.append(parts.dropFirst(2).joined(separator: "/"))
            }
        }
        startupFiles = startup
        installedScripts = scripts
    }
}
