import Darwin
import Foundation
import UniformTypeIdentifiers
import PreviewContracts

/// Another installed app whose Quick Look extension declares types that this app's catalog also covers.
struct QuickLookProviderApp: Equatable, Sendable, Identifiable {
    struct Kinds: OptionSet, Sendable {
        let rawValue: Int
        static let preview = Kinds(rawValue: 1)
        static let thumbnail = Kinds(rawValue: 2)
    }

    /// The bundle's path, which is unique among the scanned folders.
    let id: String
    /// A technical name read from the bundle; it is shown as written, never translated.
    let name: String
    let bundleIdentifier: String?
    let kinds: Kinds
    /// Catalog formats whose declared types overlap the extension's, in catalog order.
    let overlappingFormats: [FormatID]
}

struct QuickLookProviderReport: Equatable, Sendable {
    var providers: [QuickLookProviderApp] = []
    /// Application bundles that were inspected, including those with no Quick Look extension.
    var scannedApplications = 0
    /// Bundles whose files could not be read or did not hold a usable property list.
    var skippedApplications = 0
    /// Folder labels that exist but could not be listed, for example because the sandbox denies them.
    var unreadableLocations: [String] = []
    var reachedApplicationLimit = false
}

/// Reads installed application bundles for Quick Look extensions, without executing or modifying anything.
///
/// Scope: the immediate `.app` children of each root, never deeper and never through a symbolic link, and
/// only each app's `Contents/PlugIns/*.appex/Contents/Info.plist`. Every read is bounded and a property
/// list larger than the cap is skipped. The scan is an actor so blocking file access runs off the main
/// actor, and it honors cancellation between bundles. It reports declared types only: it cannot tell
/// which provider macOS selects for a file.
actor QuickLookProviderScanner {
    struct Root: Sendable, Equatable {
        let url: URL
        /// How the folder is named in results; a technical path, never translated.
        let label: String
    }

    struct Limits: Sendable {
        var maximumApplications = 2_000
        var maximumEntriesPerDirectory = 20_000
        var maximumExtensionsPerApplication = 32
        var maximumPropertyListBytes = 262_144
        var maximumDeclaredTypesPerExtension = 512
        var maximumIdentifierUTF8Bytes = 256
    }

    static let previewExtensionPoint = "com.apple.quicklook.preview"
    static let thumbnailExtensionPoint = "com.apple.quicklook.thumbnail"

    private let roots: [Root]
    private let catalog: FormatCatalog
    private let excludedBundleIdentifiers: Set<String>
    private let limits: Limits

    init(roots: [Root] = QuickLookProviderScanner.standardRoots(), catalog: FormatCatalog = .standard,
         excludedBundleIdentifiers: Set<String> = [], limits: Limits = Limits()) {
        self.roots = roots
        self.catalog = catalog
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.limits = limits
    }

    /// `/Applications`, `/System/Applications` and, when it exists, the user's own `Applications` folder.
    /// The home folder comes from the account database because a sandboxed process's home is its container.
    static func standardRoots() -> [Root] {
        var roots = [Root(url: URL(filePath: "/Applications", directoryHint: .isDirectory), label: "/Applications"),
                     Root(url: URL(filePath: "/System/Applications", directoryHint: .isDirectory), label: "/System/Applications")]
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            let home = String(cString: directory)
            roots.append(Root(url: URL(filePath: home, directoryHint: .isDirectory)
                .appending(path: "Applications", directoryHint: .isDirectory), label: "~/Applications"))
        }
        return roots
    }

    func scan() throws -> QuickLookProviderReport {
        var report = QuickLookProviderReport()
        var candidates: [(root: Root, name: String)] = []
        for root in roots {
            try Task.checkCancellation()
            switch Self.applicationNames(in: root.url, entryLimit: limits.maximumEntriesPerDirectory) {
            case .missing: continue
            case .unreadable: report.unreadableLocations.append(root.label)
            case .names(let names):
                for name in names {
                    guard candidates.count < limits.maximumApplications else {
                        report.reachedApplicationLimit = true
                        break
                    }
                    candidates.append((root, name))
                }
            }
        }
        var types = TypeResolver()
        var providers: [QuickLookProviderApp] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let bundle = candidate.root.url.appending(path: candidate.name, directoryHint: .isDirectory)
            switch inspect(bundle: bundle, name: candidate.name, types: &types) {
            case .skipped: report.skippedApplications += 1
            case .inspected(let provider):
                report.scannedApplications += 1
                if let provider { providers.append(provider) }
            }
        }
        report.providers = providers.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return report
    }

    // MARK: Bundle inspection

    private enum Inspection { case skipped, inspected(QuickLookProviderApp?) }

    private func inspect(bundle: URL, name: String, types: inout TypeResolver) -> Inspection {
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let plugIns = contents.appending(path: "PlugIns", directoryHint: .isDirectory)
        // Each level must be a real directory: a link at any level is never followed.
        guard Self.isRealDirectory(contents.path(percentEncoded: false)) else { return .skipped }
        guard Self.isRealDirectory(plugIns.path(percentEncoded: false)) else {
            return .inspected(nil) // No PlugIns folder: an ordinary app with no extension.
        }
        let extensionNames: [String]
        switch Self.entries(in: plugIns, suffix: ".appex", entryLimit: limits.maximumEntriesPerDirectory,
                            nameLimit: limits.maximumExtensionsPerApplication) {
        case .missing: return .inspected(nil)
        case .unreadable: return .skipped
        case .names(let names): extensionNames = names
        }
        let info = Self.propertyList(at: contents.appending(path: "Info.plist"), limit: limits.maximumPropertyListBytes)
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        // Own app and its extensions are never reported as another provider.
        if let bundleIdentifier, excludedBundleIdentifiers.contains(bundleIdentifier) { return .inspected(nil) }
        var kinds: QuickLookProviderApp.Kinds = []
        var overlapping = Set<FormatID>()
        for extensionName in extensionNames {
            let appex = plugIns.appending(path: extensionName, directoryHint: .isDirectory)
            let appexContents = appex.appending(path: "Contents", directoryHint: .isDirectory)
            guard Self.isRealDirectory(appexContents.path(percentEncoded: false)),
                  let plist = Self.propertyList(at: appexContents.appending(path: "Info.plist"),
                                                limit: limits.maximumPropertyListBytes),
                  let extensionInfo = plist["NSExtension"] as? [String: Any],
                  let point = extensionInfo["NSExtensionPointIdentifier"] as? String else { continue }
            let kind: QuickLookProviderApp.Kinds
            switch point {
            case Self.previewExtensionPoint: kind = .preview
            case Self.thumbnailExtensionPoint: kind = .thumbnail
            default: continue
            }
            let attributes = extensionInfo["NSExtensionAttributes"] as? [String: Any]
            let declared = (attributes?["QLSupportedContentTypes"] as? [Any] ?? [])
                .prefix(limits.maximumDeclaredTypesPerExtension)
                .compactMap { $0 as? String }
                .filter { !$0.isEmpty && $0.utf8.count <= limits.maximumIdentifierUTF8Bytes }
            let matches = overlappingFormats(declared: declared, types: &types)
            guard !matches.isEmpty else { continue }
            kinds.insert(kind)
            overlapping.formUnion(matches)
        }
        guard !kinds.isEmpty else { return .inspected(nil) }
        let displayName = (info?["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info?["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(name.dropLast(".app".count))
        return .inspected(QuickLookProviderApp(
            id: bundle.path(percentEncoded: false), name: displayName, bundleIdentifier: bundleIdentifier, kinds: kinds,
            overlappingFormats: catalog.descriptors.map(\.id).filter(overlapping.contains)))
    }

    // MARK: Overlap

    /// An exact identifier match always overlaps. Otherwise a type overlaps when one conforms to the other, except
    /// that the abstract roots `public.data`, `public.item` and `public.content` only ever match exactly:
    /// treating them as ancestors would make every extension that declares one of them overlap every format.
    private func overlappingFormats(declared: [String], types: inout TypeResolver) -> Set<FormatID> {
        var result = Set<FormatID>()
        for descriptor in catalog.descriptors {
            descriptorLoop: for ours in descriptor.contentTypes {
                for identifier in declared {
                    if Self.overlaps(ours: ours, theirs: identifier, types: &types) {
                        result.insert(descriptor.id)
                        break descriptorLoop
                    }
                }
            }
        }
        return result
    }

    private static func overlaps(ours: UTType, theirs identifier: String, types: inout TypeResolver) -> Bool {
        if ours.identifier.caseInsensitiveCompare(identifier) == .orderedSame { return true }
        guard !types.isRoot(identifier), !types.isRoot(ours.identifier), let theirs = types.type(identifier) else { return false }
        return ours.conforms(to: theirs) || theirs.conforms(to: ours)
    }

    /// Caches system type lookups for one scan. Unknown identifiers resolve to nil and match only exactly.
    private struct TypeResolver {
        private var cache: [String: UTType?] = [:]
        private static let roots: Set<String> = [UTType.data.identifier, UTType.item.identifier, UTType.content.identifier]
        func isRoot(_ identifier: String) -> Bool { Self.roots.contains(identifier.lowercased()) }
        mutating func type(_ identifier: String) -> UTType? {
            if let cached = cache[identifier] { return cached }
            let resolved = UTType(identifier)
            cache[identifier] = .some(resolved)
            return resolved
        }
    }

    // MARK: Bounded file access

    private enum DirectoryListing { case missing, unreadable, names([String]) }

    private static func applicationNames(in directory: URL, entryLimit: Int) -> DirectoryListing {
        entries(in: directory, suffix: ".app", entryLimit: entryLimit, nameLimit: .max)
    }

    /// Names of the direct children that end in `suffix`, sorted, counted without following links. At most
    /// `entryLimit` directory entries are read. Only real directories qualify, so a symbolic link is ignored.
    private static func entries(in directory: URL, suffix: String, entryLimit: Int, nameLimit: Int) -> DirectoryListing {
        let path = unslashed(directory.path(percentEncoded: false))
        guard let handle = opendir(path) else {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
        }
        defer { closedir(handle) }
        var names: [String] = []
        var examined = 0
        while examined < entryLimit, let entry = readdir(handle) {
            examined += 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard name.lowercased().hasSuffix(suffix), isRealDirectory(path + "/" + name) else { continue }
            names.append(name)
        }
        names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return .names(Array(names.prefix(nameLimit)))
    }

    /// A trailing slash makes the system resolve a final symbolic link, so it is removed before the check;
    /// without that, a link to a directory would pass as a real directory.
    private static func isRealDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(unslashed(path), &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func unslashed(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return String(trimmed)
    }

    /// A bounded read of one regular file's property list. A symbolic link, a special file, an oversized file
    /// or malformed content yields nil. The file is only ever opened for reading.
    private static func propertyList(at url: URL, limit: Int) -> [String: Any]? {
        guard let data = readRegularFile(at: url.path(percentEncoded: false), limit: limit),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func readRegularFile(at path: String, limit: Int) -> Data? {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let remaining = limit - data.count
            let count = read(descriptor, &buffer, min(buffer.count, remaining + 1))
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard count <= remaining else { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
