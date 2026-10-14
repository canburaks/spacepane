import Foundation
import PreviewContracts

/// The one top-level folder an install-time inspector reads (decision 030): `package/` in an npm tarball,
/// `name-1.0/` in a Python source distribution. Only names the listing already holds are used; nothing
/// is read. An archive whose members sit in more than one place, or loose at the top, has no layout and
/// the inspectors say nothing about it.
struct InstallableLayout {
    /// The folder's name, as listed.
    let folder: String
    /// Names of the regular files directly inside the folder.
    private let files: [String]

    /// Whether the folder holds a regular file with exactly this name. Code-unit equality: String equality
    /// would equate canonically equivalent spellings that a package manager does not.
    func has(_ name: String) -> Bool { files.contains { $0.equalsExactly(name) } }

    /// The normalized archive path of a file directly inside the folder.
    func path(of name: String) -> String { folder + "/" + name }

    /// Path components without empty and `.` parts, or `nil` for a path that is absolute or climbs out
    /// with `..`: an archive like that is not read as a package.
    static func components(of path: String) -> [String]? {
        guard !path.hasPrefix("/") else { return nil }
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) where part != "." {
            guard part != ".." else { return nil }
            parts.append(String(part))
        }
        return parts
    }

    static func find(in entries: [ContainerEntry], context: RequestContext) throws -> InstallableLayout? {
        var folder: String?
        var files: [String] = []
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            guard let parts = components(of: entry.path) else { return nil }
            // A bare `./` entry names the archive root itself.
            guard let first = parts.first else { continue }
            if let folder, !folder.equalsExactly(first) { return nil }
            folder = first
            if parts.count == 1 {
                // Only the folder itself may stand at the top level.
                guard entry.kind == ContainerEntryKind.directory.rawValue else { return nil }
            } else if parts.count == 2, entry.kind == ContainerEntryKind.file.rawValue {
                files.append(parts[1])
            }
        }
        return folder.map { InstallableLayout(folder: $0, files: files) }
    }
}
