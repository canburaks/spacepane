import Foundation
import PreviewContracts

/// Reads one fact from a `pyproject.toml`: whether its `[build-system]` table declares `backend-path`,
/// which makes the installer import the build backend from inside the package itself. The text is never
/// parsed as full TOML and nothing in it is evaluated; the scan follows table headers line by line, sets
/// comments, multi-line strings and multi-line arrays aside, and reads only keys at the start of a line.
enum PyprojectBuildSystem {
    static func declaresBackendPath(_ data: Data, context: RequestContext) throws -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        var table: Table = .root
        var multilineDelimiter: String?
        var openBrackets = 0
        for (number, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            if number.isMultiple(of: 1_024) { try context.checkpoint() }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let delimiter = multilineDelimiter {
                if line.contains(delimiter) { multilineDelimiter = nil }
                continue
            }
            if openBrackets > 0 {
                openBrackets = max(0, openBrackets + bracketBalance(line))
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                table = header(line)
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = unquoted(line[..<equals].trimmingCharacters(in: .whitespaces))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if table == .buildSystem, key.equalsExactly("backend-path") { return true }
            if table == .root {
                if key.equalsExactly("build-system.backend-path") { return true }
                // The whole table written inline on one line.
                if key.equalsExactly("build-system"), value.hasPrefix("{"), value.contains("backend-path") { return true }
            }
            multilineDelimiter = ["\"\"\"", "'''"].first { value.components(separatedBy: $0).count % 2 == 0 }
            if multilineDelimiter == nil { openBrackets = max(0, bracketBalance(value)) }
        }
        return false
    }

    private enum Table { case root, buildSystem, other }

    /// `[build-system]` names the table; `[[build-system]]` is an array of tables and some other table.
    private static func header(_ line: String) -> Table {
        guard !line.hasPrefix("[["), let close = line.firstIndex(of: "]") else { return .other }
        let name = unquoted(line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces))
        return name.equalsExactly("build-system") ? .buildSystem : .other
    }

    private static func unquoted(_ key: String) -> String {
        guard key.count >= 2, let first = key.first, first == "\"" || first == "'", key.last == first else { return key }
        return String(key.dropFirst().dropLast())
    }

    /// Opening minus closing square brackets outside quoted text and comments.
    private static func bracketBalance(_ text: String) -> Int {
        var balance = 0
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if escaped { escaped = false } else if character == "\\" && open == "\"" { escaped = true } else if character == open { quote = nil }
                continue
            }
            switch character {
            case "\"", "'": quote = character
            case "#": return balance
            case "[": balance += 1
            case "]": balance -= 1
            default: break
            }
        }
        return balance
    }
}
