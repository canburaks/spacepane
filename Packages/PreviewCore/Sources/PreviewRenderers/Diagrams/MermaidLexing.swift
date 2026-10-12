import Foundation

/// Line-level helpers shared by the Mermaid parsers. The grammar here follows the public Mermaid
/// syntax documentation; nothing in a document is executed or fetched.
enum MermaidLexing {
    /// Splits source into lines (LF, CRLF or CR), dropping nothing: blank lines keep numbering simple.
    static func lines(_ source: String) throws -> [String] {
        guard source.utf8.count <= DiagramLimits.maximumSourceUTF8Bytes else { throw DiagramFailure.tooLarge }
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in source.unicodeScalars {
            if scalar == "\n" {
                if previousWasCR { previousWasCR = false; continue }
                lines.append(String(current)); current = .init()
            } else if scalar == "\r" {
                lines.append(String(current)); current = .init()
                previousWasCR = true
            } else {
                previousWasCR = false
                current.append(scalar)
            }
            guard lines.count <= DiagramLimits.maximumLines else { throw DiagramFailure.tooLarge }
        }
        lines.append(String(current))
        return lines
    }

    /// Splits one line into statements at `;`, ignoring semicolons inside quotes and the
    /// terminator of an entity code such as `#59;`.
    static func statements(in line: String) -> [String] {
        guard line.contains(";") else { return [line] }
        let characters = Array(line)
        var statements: [String] = []
        var current = ""
        var inQuotes = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ";", !inQuotes, !endsEntityCode(characters, at: index) {
                statements.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        statements.append(current)
        return statements
    }

    /// True when the semicolon at `index` closes `#name;` or `#123;` immediately before it.
    private static func endsEntityCode(_ characters: [Character], at index: Int) -> Bool {
        var cursor = index - 1
        var length = 0
        while cursor >= 0, characters[cursor].isLetter || characters[cursor].isNumber, length < 10 {
            cursor -= 1
            length += 1
        }
        return length > 0 && cursor >= 0 && characters[cursor] == "#"
    }

    static func isComment(_ trimmed: String) -> Bool { trimmed.hasPrefix("%%") }

    /// Removes `---` front matter (a `title:` or `config:` block) at the top of the file.
    static func skipFrontMatter(_ lines: [String]) throws -> Int {
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        guard index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        var cursor = index + 1
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces) == "---" { return cursor + 1 }
            cursor += 1
        }
        throw DiagramFailure.malformed
    }

    /// Strips matching double quotes around a label.
    static func unquoted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") { return String(trimmed.dropFirst().dropLast()) }
        return trimmed
    }

    static func firstWord(of text: String) -> String {
        String(text.prefix { !$0.isWhitespace && $0 != ":" && $0 != "{" })
    }
}
