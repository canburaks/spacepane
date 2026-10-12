import Foundation

enum MarkupLines {
    /// Splits on every Unicode line terminator (line feed through carriage return, NEL, line and
    /// paragraph separators), treating CRLF as one terminator. A trailing terminator yields a final
    /// empty line, as `components(separatedBy: .newlines)` does.
    static func split(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A where previousWasCarriageReturn:
                previousWasCarriageReturn = false
                continue
            case 0x0A...0x0D, 0x85, 0x2028, 0x2029:
                lines.append(String(current))
                current = String.UnicodeScalarView()
                previousWasCarriageReturn = scalar.value == 0x0D
            default:
                current.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        lines.append(String(current))
        return lines
    }
}

/// One line of a front-matter block: `key: value`, or a free line when the block has no key there.
struct FrontMatterEntry: Equatable, Sendable {
    let key: String?
    let value: String
}

/// Reads the top-level keys of a YAML or TOML front-matter block for a compact display.
///
/// This is a display convenience, not a YAML or TOML parser: nothing is evaluated, anchors and
/// tags stay text, and nested structures are flattened into one line of comma-separated items.
enum FrontMatterEntries {
    static let maximumEntries = 200

    static func entries(from body: [String], isTOML: Bool) -> [FrontMatterEntry] {
        isTOML ? toml(body) : yaml(body)
    }

    // MARK: YAML

    private static func yaml(_ body: [String]) -> [FrontMatterEntry] {
        var entries: [FrontMatterEntry] = []
        var index = 0
        while index < body.count, entries.count < maximumEntries {
            let line = body[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { index += 1; continue }
            let isIndented = line.first == " " || line.first == "\t"
            guard !isIndented, let (key, rest) = splitYAMLKey(line) else {
                entries.append(.init(key: nil, value: trimmed))
                index += 1
                continue
            }
            var value = rest.trimmingCharacters(in: .whitespaces)
            var next = index + 1
            let isBlockScalar = value.hasPrefix("|") || value.hasPrefix(">")
            if value.isEmpty || isBlockScalar {
                var parts: [String] = []
                while next < body.count {
                    let continuation = body[next]
                    let item = continuation.trimmingCharacters(in: .whitespaces)
                    let continues = continuation.first == " " || continuation.first == "\t" || item.hasPrefix("- ") || item == "-"
                    if item.isEmpty { next += 1; continue }
                    guard continues else { break }
                    parts.append(item.hasPrefix("- ") ? String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces) : item)
                    next += 1
                }
                value = parts.map(unquoted).joined(separator: isBlockScalar ? " " : ", ")
            } else {
                value = flowList(value)
            }
            entries.append(.init(key: unquoted(key), value: value))
            index = next
        }
        return entries
    }

    private static func splitYAMLKey(_ line: String) -> (key: String, rest: String)? {
        var quote: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let after = line.index(after: index)
                if after == line.endIndex || line[after] == " " || line[after] == "\t" {
                    let key = String(line[..<index]).trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, !key.hasPrefix("- "), !key.hasPrefix("[") else { return nil }
                    return (key, String(line[after...]))
                }
            }
            index = line.index(after: index)
        }
        return nil
    }

    // MARK: TOML

    private static func toml(_ body: [String]) -> [FrontMatterEntry] {
        var entries: [FrontMatterEntry] = []
        var index = 0
        while index < body.count, entries.count < maximumEntries {
            let line = body[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            index += 1
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") { entries.append(.init(key: nil, value: trimmed)); continue }
            guard let equals = firstUnquotedEquals(trimmed) else { entries.append(.init(key: nil, value: trimmed)); continue }
            let key = unquoted(String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces))
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            // Multi-line arrays and strings continue until their closing delimiter.
            if value.hasPrefix("["), !value.hasSuffix("]") {
                while index < body.count, !value.hasSuffix("]") {
                    value += " " + body[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
            } else if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
                let delimiter = String(value.prefix(3))
                var content = String(value.dropFirst(3))
                while !content.hasSuffix(delimiter), index < body.count {
                    content += " " + body[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
                value = content.hasSuffix(delimiter) ? String(content.dropLast(3)) : content
            }
            entries.append(.init(key: key, value: flowList(value)))
        }
        return entries
    }

    private static func firstUnquotedEquals(_ line: String) -> String.Index? {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote { if character == open { quote = nil } }
            else if character == "\"" || character == "'" { quote = character }
            else if character == "=" { return index }
        }
        return nil
    }

    // MARK: Values

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == "\"" || first == "'", trimmed.last == first else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

    /// `[a, "b"]` becomes `a, b`; any other value only loses matching surrounding quotes.
    private static func flowList(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return unquoted(trimmed) }
        let items = trimmed.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: true)
        return items.map { unquoted(String($0)) }.joined(separator: ", ")
    }
}
