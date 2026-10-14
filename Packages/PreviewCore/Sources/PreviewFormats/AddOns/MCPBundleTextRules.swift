import Foundation
import PreviewContracts

/// Recognizes the two facts about an MCP bundle that are read from words and variables rather than from
/// structure: tool or prompt text that speaks to the assistant about files and apps outside the tool's
/// job, and a path variable that names a whole personal folder. Both are conservative on purpose: an
/// ordinary imperative ("Use this tool when ...") says nothing, and a subfolder is not a whole folder.
enum MCPBundleTextRules {
    private enum Boundary { case none, left, both }

    /// References to credential files and to the settings of other apps, lowercase. A name that is also
    /// ordinary text ("process.env", ".environment") must stand alone where the boundary says so.
    private static let references: [(text: String, boundary: Boundary)] = [
        ("~/.ssh", .none), ("/.ssh/", .none), ("id_rsa", .left), ("id_ed25519", .left), (".aws/credentials", .none),
        (".netrc", .left), (".npmrc", .left), (".pypirc", .left), (".gnupg", .left), (".env", .both),
        ("keychain", .left), ("mcp.json", .left), ("claude_desktop_config.json", .none)
    ]

    /// Requests to keep something from the person using the tool, with apostrophes folded.
    private static let concealments = [
        "do not tell the user", "don't tell the user", "without telling the user",
        "do not mention this to the user", "don't mention this to the user", "hide this from the user"
    ]

    private static let tags = ["<important>", "<system>"]

    /// Whether `text` refers to a credential file or another app's settings, asks to conceal something
    /// from the user, or carries an `<IMPORTANT>` or `<SYSTEM>` tag. English only, ASCII case folded.
    /// Invisible format characters are dropped first, so they cannot split a phrase.
    static func targetsAssistant(_ text: String) -> Bool {
        let folded = normalized(text)
        if tags.contains(where: { folded.contains($0) }) || concealments.contains(where: { folded.contains($0) }) { return true }
        return references.contains { contains(folded, reference: $0.text, boundary: $0.boundary) }
    }

    private static func normalized(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .format { continue }
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace { result += " "; pendingSpace = false }
            switch scalar.value {
            case 0x2018, 0x2019, 0x02BC: result += "'"
            default: result += scalar.properties.lowercaseMapping
            }
        }
        return result
    }

    private static func contains(_ text: String, reference: String, boundary: Boundary) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: reference, range: start..<text.endIndex) {
            let leftIsClear = range.lowerBound == text.startIndex || !isWord(text[text.index(before: range.lowerBound)])
            let rightIsClear = range.upperBound == text.endIndex || !isWord(text[range.upperBound])
            switch boundary {
            case .none: return true
            case .left where leftIsClear: return true
            case .both where leftIsClear && rightIsClear: return true
            default: start = range.upperBound
            }
        }
        return false
    }

    private static func isWord(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" }

    // MARK: Whole personal folders

    private static let folderVariables = ["${HOME}", "${DOCUMENTS}", "${DOWNLOADS}", "${DESKTOP}"]
    private static let separators: Set<String> = ["/", "\\", "${/}", "${pathSeparator}"]

    /// A value that is exactly a user-folder variable, optionally followed by one path separator. A path
    /// below it (`${HOME}/.myapp`) is the app's own place and is not broad.
    static func isWholeFolder(_ value: String) -> Bool {
        folderVariables.contains { variable in
            guard value.hasPrefix(variable) else { return false }
            let rest = value.dropFirst(variable.count)
            return rest.isEmpty || separators.contains(String(rest))
        }
    }
}

// MARK: Command-line arguments

extension MCPBundleTextRules {
    /// Marks the arguments that carry a credential: the value after a flag whose name looks like one
    /// (`--api-key abc`), and the value of `--token=abc` or `NAME=abc` with such a name. The flag itself
    /// stays readable, because it says what the argument is.
    static func markingCredentials(in arguments: [String]) -> [(text: String, sensitive: Bool)] {
        var previousNamesCredential = false
        return arguments.map { argument in
            defer { if !argument.hasPrefix("-") || argument.contains("=") { previousNamesCredential = false } }
            if let equals = argument.firstIndex(of: "="), equals != argument.startIndex {
                let name = argument[..<equals].drop { $0 == "-" }
                return (argument, !name.isEmpty && !name.contains(" ") && SecretFieldPolicy.isSensitive(String(name)))
            }
            if argument.hasPrefix("-") {
                previousNamesCredential = SecretFieldPolicy.isSensitive(String(argument.drop { $0 == "-" }))
                return (argument, false)
            }
            return (argument, previousNamesCredential)
        }
    }
}
