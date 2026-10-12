import Foundation
import PreviewContracts

/// Classifies where a file sits from its path alone: whether the folder is one a sync service
/// mirrors to other devices or servers. A pure test of whole path components. It never touches the
/// file system, resolves links or reads resource values, because the sandboxed extension cannot
/// trust any of those and `homeDirectoryForCurrentUser` would name the extension's container.
///
/// Known limitation: locations are recognized only by these conventional paths. iCloud "Desktop &
/// Documents" sync (the ordinary Desktop and Documents folders), other File Provider locations
/// outside `~/Library/CloudStorage`, and sync folders moved elsewhere are not detected, and a
/// symbolic link into a synced folder is not followed.
public enum SyncFolderLocation {
    /// The provider that syncs the folder holding `url`, or `nil` when the path is not a known sync
    /// location, is not a file URL, or is relative. The folder name under `CloudStorage` can contain an
    /// account address, so only the provider is returned and the name is never kept.
    public static func provider(for url: URL) -> PreviewSyncProvider? {
        guard url.isFileURL, url.host.map({ $0.isEmpty || $0 == "localhost" }) ?? true,
              var components = absoluteComponents(of: url) else { return nil }
        // The same volume is reachable through its data-volume firmlink path.
        if components.starts(with: ["System", "Volumes", "Data"]) { components.removeFirst(3) }
        // A file inside a home folder: Users/<user>/<...>. Any user, since the extension cannot name its own.
        guard components.count >= 4, components[0] == "Users" else { return nil }
        let home = components.dropFirst(2)
        let first = home[home.startIndex]
        if first == "Dropbox" { return .dropbox }
        guard first == "Library" else { return nil }
        let library = home.dropFirst()
        guard let area = library.first else { return nil }
        switch area {
        case "Mobile Documents":
            return library.count >= 2 ? .iCloudDrive : nil
        case "CloudStorage":
            // CloudStorage/<folder>/<file>: the folder names the provider, then at least one component below it.
            guard library.count >= 3 else { return nil }
            return provider(forCloudStorageFolder: library[library.startIndex + 1])
        default:
            return nil
        }
    }

    /// Provider folders are `Dropbox`, `Dropbox-<account>`, `GoogleDrive-<account>`, `OneDrive-<tenant>`,
    /// `Box-Box` and similar. A lookalike such as `Boxes` is another provider, not Box.
    private static func provider(forCloudStorageFolder name: String) -> PreviewSyncProvider {
        let known: [(prefix: String, provider: PreviewSyncProvider)] = [
            ("Dropbox", .dropbox), ("GoogleDrive", .googleDrive), ("OneDrive", .oneDrive), ("Box", .box)
        ]
        for (prefix, provider) in known where name == prefix || name.hasPrefix(prefix + "-") { return provider }
        return .other
    }

    /// Path components of an absolute path with `.`, `..` and empty components resolved lexically.
    /// `standardizedFileURL` is avoided on purpose: it consults the file system for `/private` and links.
    private static func absoluteComponents(of url: URL) -> [String]? {
        let raw = url.pathComponents
        guard raw.first == "/" else { return nil }
        var components: [String] = []
        for component in raw.dropFirst() {
            switch component {
            case "", ".", "/": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(component)
            }
        }
        return components
    }
}
