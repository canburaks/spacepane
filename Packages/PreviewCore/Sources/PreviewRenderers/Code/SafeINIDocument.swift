import Foundation

/// Derives a sections-then-settings outline from INI-family text that concealment has already run on.
/// It reads the same lenient shape the adapter accepts: `[section]` headers, `key = value` or
/// `key: value` assignments, `key value` directives, `;`, `#` and `!` comments, and indented or
/// backslash continuation lines (joined with a single space). Values keep their source spelling.
///
/// It returns `nil`, which shows the structure-unavailable notice with the safe source, when a line
/// cannot be a setting (a stray brace, a nested bracket, an empty name) or a limit is exceeded, so a
/// `.conf` file in some other grammar (nginx blocks, tmux commands) is never presented as sections.
enum SafeINIDocument {
    static let maximumUTF16Units = 262_144
    static let maximumNodes = 20_000

    private final class Node {
        let id: Int
        let name: String
        var value: String
        var children: [Node] = []
        init(id: Int, name: String, value: String) { self.id = id; self.name = name; self.value = value }
        func frozen(isDuplicate: Bool) -> SafeOutlineNode {
            var counts: [String: Int] = [:]
            for child in children { counts[child.name, default: 0] += 1 }
            return SafeOutlineNode(id: id, name: name, value: value,
                                   children: children.map { $0.frozen(isDuplicate: counts[$0.name, default: 0] > 1) },
                                   isDuplicateKey: isDuplicate)
        }
    }

    static func nodes(_ source: String) -> [SafeOutlineNode]? {
        guard source.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units else { return nil }
        var roots: [Node] = []
        var section: Node?
        var last: Node?
        var continues = false
        var nextID = 0
        for raw in source.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { last = nil; continues = false; continue }
            if let first = trimmed.first, first == ";" || first == "#" || first == "!" { last = nil; continues = false; continue }
            // A continuation extends the previous setting's value.
            if let previous = last, continues || raw.first == " " || raw.first == "\t" {
                var value = previous.value
                if value.hasSuffix("\\") { value.removeLast() }
                value = value.trimmingCharacters(in: .whitespaces)
                previous.value = value.isEmpty ? trimmed : value + " " + trimmed
                continues = trimmed.hasSuffix("\\")
                continue
            }
            guard nextID < maximumNodes else { return nil }
            if trimmed.hasPrefix("[") {
                guard trimmed.hasSuffix("]"), trimmed.count > 2 else { return nil }
                let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !name.contains("[") else { return nil }
                let node = Node(id: nextID, name: name, value: "")
                nextID += 1
                roots.append(node)
                section = node
                last = nil
                continues = false
                continue
            }
            guard let (name, value) = setting(trimmed) else { return nil }
            let node = Node(id: nextID, name: name, value: value)
            nextID += 1
            if let section { section.children.append(node) } else { roots.append(node) }
            last = node
            continues = value.hasSuffix("\\")
        }
        var counts: [String: Int] = [:]
        for node in roots { counts[node.name, default: 0] += 1 }
        return roots.map { $0.frozen(isDuplicate: counts[$0.name, default: 0] > 1) }
    }

    /// Splits one setting line. The first `=` or `:` separates name and value, except that a URL-like name
    /// (`//registry.example/:_authToken=…`) is split at its `=`; a line with neither is `name value`.
    private static func setting(_ line: String) -> (name: String, value: String)? {
        guard let first = line.first, !"{}()<>".contains(first) else { return nil }
        var split = line.firstIndex(where: { $0 == "=" || $0 == ":" })
        if let colon = split, line[colon] == ":", line[..<colon].contains("/"),
           let equals = line.firstIndex(of: "=") { split = equals }
        let name: String
        let value: String
        if let split {
            name = String(line[..<split]).trimmingCharacters(in: .whitespaces)
            value = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces)
        } else if let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            name = String(line[..<space])
            value = String(line[space...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = line
            value = ""
        }
        guard !name.isEmpty, value != "{", value != "}" else { return nil }
        return (name, value)
    }
}
