import Foundation
import PreviewContracts

/// Path lookup over the entries of a validated ZIP central directory. Package files refer to their parts by
/// relative, percent-encoded URLs; this resolves them to archive paths without touching anything outside the
/// archive. References with a scheme (`http:`, `data:`), traversal above the archive root, and empty
/// references resolve to `nil`.
struct ArchiveMemberIndex {
    private let exact: [String: ZIPEntry]
    private let folded: [String: ZIPEntry]

    init(_ archive: ZIPArchive) {
        var exact: [String: ZIPEntry] = [:]
        var folded: [String: ZIPEntry] = [:]
        for entry in archive.entries where entry.kind == "file" {
            exact[entry.path] = exact[entry.path] ?? entry
            folded[entry.path.lowercased()] = folded[entry.path.lowercased()] ?? entry
        }
        self.exact = exact
        self.folded = folded
    }

    /// The member at `path`, matching case exactly first and then case-insensitively: package writers differ
    /// in the capitalization they record for the same part.
    func entry(at path: String) -> ZIPEntry? { exact[path] ?? folded[path.lowercased()] }

    /// Resolves `reference` against the directory of `base` (an archive path of a file inside the package).
    static func resolve(_ reference: String, relativeTo base: String) -> String? {
        var trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = trimmed.firstIndex(of: "#") { trimmed = String(trimmed[..<hash]) }
        if let query = trimmed.firstIndex(of: "?") { trimmed = String(trimmed[..<query]) }
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2_048, let decoded = trimmed.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        // A scheme such as `https:` or `data:` names something outside the archive.
        if let colon = decoded.firstIndex(of: ":"), !decoded[..<colon].contains("/") { return nil }
        var segments: [String] = decoded.hasPrefix("/") ? [] : directory(of: base)
        for part in decoded.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                guard !segments.isEmpty else { return nil }
                segments.removeLast()
            default: segments.append(String(part))
            }
        }
        return segments.isEmpty ? nil : segments.joined(separator: "/")
    }

    /// Directory segments of an archive path (all but the last component).
    static func directory(of path: String) -> [String] {
        Array(path.split(separator: "/", omittingEmptySubsequences: true).dropLast().map(String.init))
    }
}
