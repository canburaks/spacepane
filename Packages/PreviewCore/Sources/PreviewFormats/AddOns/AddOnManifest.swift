import Foundation
import PreviewContracts

/// Reading helpers over the tolerant manifest tree (`LensJSONNode`) that the MCP bundle, editor
/// extension and browser extension adapters share. Absent and wrongly typed members read as absent,
/// so a manifest that is missing a key simply shows less. Keys compare by code units.
extension LensJSONNode {
    /// The value reached by following `keys` through nested objects.
    func at(_ keys: String...) -> LensJSONNode? {
        var node: LensJSONNode? = self
        for key in keys { node = node?.member(key)?.value }
        return node
    }

    /// A non-empty string member.
    func text(_ key: String) -> String? {
        guard let value = member(key)?.value.string, !value.isEmpty else { return nil }
        return value
    }

    /// The non-empty string elements of an array member, in order.
    func texts(_ key: String) -> [String] { member(key)?.value.textElements ?? [] }

    /// The non-empty string elements of this node when it is an array.
    var textElements: [String] {
        (elements ?? []).compactMap { $0.string }.filter { !$0.isEmpty }
    }

    /// A string, or a number written the way a person would, for version-like members.
    var scalarText: String? {
        switch value {
        case .string(let text): return text.isEmpty ? nil : text
        case .number(let number):
            guard number.isFinite else { return nil }
            return number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        default: return nil
        }
    }

    /// A boolean member; any other type reads as absent.
    func flag(_ key: String) -> Bool? { member(key)?.value.bool }

    /// An integral number member.
    func integer(_ key: String) -> Int? {
        guard let number = member(key)?.value.number, number.isFinite, number.rounded() == number,
              abs(number) < 1e15 else { return nil }
        return Int(number)
    }
}

enum AddOnManifestText {
    /// Calls `body` with every string and every member name in the tree, so invisible characters are
    /// found wherever the manifest holds text, shown or not. The walk is bounded by the manifest the
    /// parser already accepted.
    static func forEachString(in root: LensJSONNode, context: RequestContext, _ body: (String) throws -> Void) throws {
        var stack = [root]
        var visited = 0
        while let node = stack.popLast() {
            visited += 1
            if visited.isMultiple(of: 256) { try context.checkpoint() }
            switch node.value {
            case .string(let text): try body(text)
            case .array(let elements): stack.append(contentsOf: elements.reversed())
            case .object(let members):
                for member in members.reversed() {
                    try body(member.key)
                    stack.append(member.value)
                }
            default: break
            }
        }
    }
}

enum AddOnURL {
    /// `scheme://host[:port]` of a web address; path, query, fragment and user information are dropped
    /// because update addresses commonly carry keys in them.
    static func origin(of text: String) -> String? {
        guard let parts = components(of: text) else { return nil }
        let authority = parts.host.contains(":") && !parts.host.hasPrefix("[") ? "[\(parts.host)]" : parts.host
        return "\(parts.scheme)://\(authority)" + (parts.port.map { ":\($0)" } ?? "")
    }

    static func components(of text: String) -> (scheme: String, host: String, port: Int?)? {
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        return (scheme, host, parts.port)
    }
}

enum AddOnPath {
    /// A member path relative to `base`, with `.` components dropped and backslashes read as slashes.
    /// `nil` for an empty path or one that climbs out with `..`, which no archive member name can be.
    static func resolve(_ relative: String, under base: String = "") -> String? {
        var parts: [Substring] = []
        for part in relative.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { return nil }
            parts.append(part)
        }
        guard !parts.isEmpty else { return nil }
        return base + parts.joined(separator: "/")
    }

    /// The names a declared entry file may have in the archive: as written, with the `.js` that
    /// Node.js and VS Code add to an extension-less `main`, and as a folder's `index.js`.
    static func candidates(_ path: String) -> [String] {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name.contains(".") ? [path] : [path, path + ".js", path + "/index.js"]
    }
}

enum AddOnSummary {
    /// A list of names or values from the manifest, cut to `AddOnLimits.listItems`.
    static func shortList(_ fields: inout SummaryFields, _ key: String, _ values: [String]) {
        fields.list(key, values, limit: AddOnLimits.listItems)
    }

    /// A list whose items are concealed one by one: an argument that follows `--api-key`, a runtime
    /// whose name looks like a credential. An empty list is omitted.
    static func markedList(_ fields: inout SummaryFields, _ key: String, _ items: [(text: String, sensitive: Bool)]) {
        guard !items.isEmpty else { return }
        fields.add(key, .array(items.prefix(AddOnLimits.listItems).map {
            .string(PackageSummary.clipped($0.text), sensitive: $0.sensitive)
        }))
    }
}
