import Foundation
import PreviewContracts

/// Presentation-only subsets: indented YAML mappings/sequences, TOML tables/assignments,
/// and single-line env assignments. Dates/numbers remain source lexemes. Advanced forms
/// return nil so the caller retains concealed source rather than guessing a structure.
///
/// A YAML sequence may be indented like the key it belongs to (`key:` then `- item`); it stays under that
/// key. A sequence item that cannot be attributed to one parent (after a key that already holds mapping
/// entries, or beside keys) returns nil instead of being moved to another level.
enum SafeConfigurationOutline {
    private final class Node {
        let id: Int
        let name: String
        let value: String
        /// A `- item` entry of a sequence; every other node is a mapping key, a table or an assignment.
        let isItem: Bool
        /// A key whose sequence items are written at the key's own indentation.
        var holdsCompactItems = false
        var children: [Node] = []
        init(id: Int, name: String, value: String, isItem: Bool = false) {
            self.id = id; self.name = name; self.value = value; self.isItem = isItem
        }
        func frozen(duplicate: Bool = false) -> SafeOutlineNode {
            var counts: [String: Int] = [:]
            for child in children { counts[child.name, default: 0] += 1 }
            return .init(id: id, name: name, value: value, children: children.map {
                $0.frozen(duplicate: counts[$0.name, default: 0] > 1)
            }, isDuplicateKey: duplicate)
        }
    }
    static func nodes(_ source: String, syntax: TextSyntax) -> [SafeOutlineNode]? {
        guard source.utf16.prefix(262_145).count <= 262_144 else { return nil }
        let lines = source.components(separatedBy: .newlines)
        guard lines.count <= 20_000 else { return nil }
        switch syntax {
        case .yaml: return yaml(lines)
        case .toml: return assignments(lines, tables: true)
        case .environment: return assignments(lines, tables: false)
        default: return nil
        }
    }
    private static func yaml(_ lines: [String]) -> [SafeOutlineNode]? {
        var roots: [Node] = []
        var stack: [(indent: Int, node: Node)] = []
        var id = 0
        var seenContent = false
        var previousIndent = 0
        var previousAllowsChildren = true
        for raw in lines {
            guard !raw.hasPrefix("\t") else { return nil }
            let indent = raw.prefix(while: { $0 == " " }).count
            let text = stripComment(String(raw.dropFirst(indent))).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if text == "---" { guard !seenContent else { return nil }; continue }
            if text == "..." { continue }
            if text.hasPrefix("%") || text.hasPrefix("<<:") { return nil }
            guard id < 20_000 else { return nil }
            if seenContent, indent > previousIndent, !previousAllowsChildren { return nil }
            let isItem = text == "-" || text.hasPrefix("- ")
            // Entries at this indentation or deeper end here, except that a sequence item keeps the key written
            // at its own indentation open: `key:` followed by `- item` is that key's compact sequence.
            while let top = stack.last {
                let continuesKey = isItem && top.indent == indent && !top.node.isItem
                guard top.indent > indent || (top.indent == indent && !continuesKey) else { break }
                stack.removeLast()
            }
            guard stack.count < 64 else { return nil }
            if isItem, let top = stack.last, top.indent == indent {
                // Only a key with no entries yet, or one that already holds same-indent items, takes the item;
                // beside mapping entries the line has no unambiguous owner.
                guard top.node.children.isEmpty || top.node.holdsCompactItems else { return nil }
                top.node.holdsCompactItems = true
            }
            let siblings = stack.last?.node.children ?? roots
            // A collection holds either keys or items; mixing them is not YAML, so there is nothing to outline.
            if let first = siblings.first, first.isItem != isItem { return nil }
            let name: String
            let scalar: String
            if isItem {
                name = "[\(siblings.count)]"
                scalar = text == "-" ? "" : String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                // Mapping-in-sequence syntax needs an additional ownership/indentation rule.
                // Keep source for that form instead of presenting a misleading scalar.
                if delimiter(":", in: scalar) != nil { return nil }
            } else {
                guard let split = delimiter(":", in: text) else { return nil }
                let after = text.index(after: split)
                guard after == text.endIndex || text[after].isWhitespace else { return nil }
                name = key(String(text[..<split]))
                scalar = String(text[after...]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
            }
            guard supportedScalar(scalar) else { return nil }
            let node = Node(id: id, name: name, value: scalar, isItem: isItem)
            id += 1
            if let parent = stack.last { parent.node.children.append(node) } else { roots.append(node) }
            if scalar.isEmpty { stack.append((indent, node)) }
            previousIndent = indent; previousAllowsChildren = scalar.isEmpty; seenContent = true
        }
        return freeze(roots)
    }
    private static func assignments(_ lines: [String], tables: Bool) -> [SafeOutlineNode]? {
        var roots: [Node] = []
        var table: Node?
        var id = 0
        for raw in lines {
            var text = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard id < 20_000 else { return nil }
            if tables, text.hasPrefix("[") {
                guard text.hasSuffix("]"), !text.hasPrefix("[["), !text.contains("\""), !text.contains("'") else { return nil }
                let path = String(text.dropFirst().dropLast()).split(separator: ".").map(String.init)
                guard !path.isEmpty, path.count <= 64,
                      path.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }) else { return nil }
                var current: Node?
                for part in path {
                    let siblings = current?.children ?? roots
                    if let existing = siblings.first(where: { $0.name == part && $0.value.isEmpty }) { current = existing }
                    else {
                        guard id < 20_000 else { return nil }
                        let node = Node(id: id, name: part, value: ""); id += 1
                        if let parent = current { parent.children.append(node) } else { roots.append(node) }
                        current = node
                    }
                }
                table = current
                continue
            }
            if !tables, text.hasPrefix("export ") { text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let split = delimiter("=", in: text) else { return nil }
            let name = key(String(text[..<split]))
            let value = String(text[text.index(after: split)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, supportedScalar(value) else { return nil }
            if !tables, name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil { return nil }
            let node = Node(id: id, name: name, value: value); id += 1
            if let table { table.children.append(node) } else { roots.append(node) }
        }
        return freeze(roots)
    }
    private static func freeze(_ roots: [Node]) -> [SafeOutlineNode] {
        var counts: [String: Int] = [:]
        for node in roots { counts[node.name, default: 0] += 1 }
        return roots.map { $0.frozen(duplicate: counts[$0.name, default: 0] > 1) }
    }
    private static func key(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), let value = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) { return value }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 { return String(text.dropFirst().dropLast()) }
        return text
    }
    private static func supportedScalar(_ value: String) -> Bool {
        if value.hasPrefix("&") || value.hasPrefix("*") || value.hasPrefix("!") || value.hasPrefix("{") || value == "|" || value == ">" || value.hasPrefix("\"\"\"") || value.hasPrefix("'''") { return false }
        if value.hasPrefix("\"") { return value.hasSuffix("\"") && value.count >= 2 }
        if value.hasPrefix("'") { return value.hasSuffix("'") && value.count >= 2 }
        return true
    }
    private static func delimiter(_ delimiter: Character, in text: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let current = quote { if character == current { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character; continue }
            if character == delimiter { return index }
        }
        return nil
    }
    private static func stripComment(_ text: String) -> String {
        guard let index = delimiter("#", in: text) else { return text }
        return String(text[..<index])
    }
}
