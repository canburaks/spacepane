import Foundation

/// Reads the command-line options of the few programs whose options decide a finding. Only the
/// options that matter are interpreted; every other word is skipped without guessing what it means.
enum ScriptArguments {
    struct Transfer {
        /// The file a download is saved to; `nil` for standard output, `/dev/null` and remote-name saves.
        var outputFile: String?
        /// A request body or form field is read from a file, or a file is uploaded.
        var uploadsFile = false
    }

    // MARK: curl and wget

    /// Short curl options that take a value. In a cluster such as `-fsSLo file` the first one ends it.
    private static let curlValueLetters: Set<Character> = [
        "o", "H", "d", "X", "u", "A", "e", "F", "T", "w", "m", "x", "b", "c", "C", "D", "E", "K", "r", "Y", "y", "z", "U", "P", "Q", "t"
    ]
    private static let wgetValueLetters: Set<Character> = [
        "O", "o", "a", "i", "P", "e", "T", "t", "w", "U", "l", "Q", "B", "I", "X", "D", "R", "A"
    ]

    static func curl(_ arguments: [ScriptWord]) -> Transfer {
        var transfer = Transfer()
        let texts = arguments.map(\.text)
        var index = 0
        while index < texts.count {
            let text = texts[index]
            index += 1
            if text.hasPrefix("--") {
                let (name, inline) = splitLongOption(text)
                let value = inline ?? (index < texts.count ? texts[index] : nil)
                switch name {
                case "--output", "--form", "--data", "--data-binary", "--data-ascii", "--json", "--upload-file":
                    if inline == nil { index += 1 }
                    apply(curlOption: name, value: value, to: &transfer)
                default:
                    break
                }
            } else if text.hasPrefix("-"), text.count > 1 {
                let letters = Array(text.dropFirst())
                guard let position = letters.firstIndex(where: { curlValueLetters.contains($0) }) else { continue }
                let rest = String(letters[(position + 1)...])
                let value = rest.isEmpty ? (index < texts.count ? texts[index] : nil) : rest
                if rest.isEmpty { index += 1 }
                apply(curlOption: "-" + String(letters[position]), value: value, to: &transfer)
            }
        }
        return transfer
    }

    private static func apply(curlOption name: String, value: String?, to transfer: inout Transfer) {
        guard let value, !value.isEmpty else { return }
        switch name {
        case "-o", "--output":
            if value != "-", value != "/dev/null" { transfer.outputFile = value }
        case "-F", "--form":
            // `name=@path` uploads the file; `name=text` and `name=<path` are fields.
            if let equals = value.firstIndex(of: "="), value[value.index(after: equals)...].hasPrefix("@") { transfer.uploadsFile = true }
        case "-d", "--data", "--data-binary", "--data-ascii", "--json":
            if value.hasPrefix("@"), value != "@-", value.count > 1 { transfer.uploadsFile = true }
        case "-T", "--upload-file":
            if value != "-" { transfer.uploadsFile = true }
        default:
            break
        }
    }

    static func wget(_ arguments: [ScriptWord]) -> Transfer {
        var transfer = Transfer()
        let texts = arguments.map(\.text)
        var index = 0
        while index < texts.count {
            let text = texts[index]
            index += 1
            var output: String?
            if text.hasPrefix("--") {
                let (name, inline) = splitLongOption(text)
                guard name == "--output-document" else { continue }
                output = inline ?? (index < texts.count ? texts[index] : nil)
                if inline == nil { index += 1 }
            } else if text.hasPrefix("-"), text.count > 1 {
                let letters = Array(text.dropFirst())
                guard let position = letters.firstIndex(where: { wgetValueLetters.contains($0) }) else { continue }
                let rest = String(letters[(position + 1)...])
                let value = rest.isEmpty ? (index < texts.count ? texts[index] : nil) : rest
                if rest.isEmpty { index += 1 }
                if letters[position] == "O" { output = value }
            }
            if let output, !output.isEmpty, output != "-", output != "/dev/null" { transfer.outputFile = output }
        }
        return transfer
    }

    private static func splitLongOption(_ text: String) -> (name: String, inline: String?) {
        guard let equals = text.firstIndex(of: "=") else { return (text.lowercased(), nil) }
        return (text[..<equals].lowercased(), String(text[text.index(after: equals)...]))
    }

    // MARK: Small predicates

    /// The letters of a short option cluster (`-rd` gives `rd`); `nil` for words that are not one.
    static func shortLetters(_ text: String) -> Substring? {
        text.count > 1 && text.hasPrefix("-") && !text.hasPrefix("--") ? text.dropFirst() : nil
    }

    /// Whether a `chmod` mode sets an execute bit: `+x`, `u+x`, `a+rx`, `755`, `0700`.
    static func setsExecuteBit(_ mode: String) -> Bool {
        if mode.allSatisfy(\.isNumber) {
            let digits = mode.compactMap(\.wholeNumberValue)
            return digits.count >= 3 && digits[digits.count - 3] & 1 == 1
        }
        return mode.split(separator: ",").contains { clause in
            guard let sign = clause.firstIndex(where: { $0 == "+" || $0 == "=" }) else { return false }
            return clause[clause.index(after: sign)...].contains("x")
        }
    }

    /// A path in a form two commands of one script can be compared in: no leading `./`; for Windows, lowercase
    /// with forward slashes.
    static func fileKey(_ text: String, windows: Bool) -> String {
        var path = windows ? text.lowercased().replacingOccurrences(of: "\\", with: "/") : text
        while path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// Whether two keys name the same file. On Windows a bare file name also matches the same name in a folder.
    static func sameFile(_ first: String, _ second: String, windows: Bool) -> Bool {
        if first == second { return true }
        guard windows, !first.contains("/") || !second.contains("/") else { return false }
        return first.split(separator: "/").last == second.split(separator: "/").last
    }
}

// MARK: - Secret locations

/// Paths that hold credentials a script has little reason to read: browser credential stores, keychains,
/// private keys, cloud credentials and crypto-wallet folders. Matching is on the text of one word, so a
/// path built from variables is missed, which is acceptable.
enum ScriptSecretPaths {
    enum Strength { case strong, weak }

    private static let chromiumFolders = ["google/chrome", "bravesoftware", "microsoft edge", "microsoft/edge", "chromium", "vivaldi"]
    private static let walletFolders: Set<String> = ["exodus", "electrum", ".electrum", "coinomi", "atomic wallet"]
    private static let metaMaskID = "nkbihfbeogaeaoehlefnkodbefgpgknn"

    /// `.strong` paths are credential stores whatever the command; `.weak` ones (a user's own SSH key, the
    /// AWS credentials file) are ordinary arguments in setup scripts and count only for a real command.
    static func strength(of text: String) -> Strength? {
        guard text.utf8.count >= 7, text.utf8.contains(where: { $0 == 0x2F || $0 == 0x5C || $0 == 0x2E || $0 == 0x20 }) else { return nil }
        let path = text.lowercased().replacingOccurrences(of: "\\", with: "/")
        if path.contains(metaMaskID) || path.hasSuffix(".binarycookies") || path.contains("library/keychains") { return .strong }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = components.last else { return nil }
        if ["logins.json", "key4.db", "key3.db", "tcc.db"].contains(last) { return .strong }
        if components.contains(where: { $0 == "login data" || $0.hasPrefix("login data-") || $0.hasPrefix("login data for") }) { return .strong }
        let inChromium = chromiumFolders.contains { path.contains($0) }
        if last == "cookies", inChromium || path.contains("/default/") || path.contains("/network/") || path.contains("/profile ") { return .strong }
        if last == "local state", inChromium || path.contains("user data") { return .strong }
        if path.contains("atomic/local storage") { return .strong }
        if components.count > 1, components.contains(where: { walletFolders.contains($0) || $0.hasPrefix("exodus.") || $0.hasPrefix("electrum-") }) {
            return .strong
        }
        if path.contains(".ssh/id_"), !path.hasSuffix(".pub") { return .weak }
        if path.contains(".aws/credentials") { return .weak }
        return nil
    }
}

// MARK: - Persistence locations

enum ScriptPersistence {
    private static let startupFiles: Set<String> = [
        ".zshrc", ".zprofile", ".zshenv", ".zlogin", ".bash_profile", ".bash_login", ".bashrc", ".profile"
    ]

    private static func components(of text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// A launchd folder. `App.app/Contents/Library/LaunchAgents` holds an app's own helper jobs, which are
    /// packaging until the app registers them, so it does not count.
    static func isLaunchFolder(_ text: String) -> Bool {
        guard text.utf8.count >= 12 else { return false }
        let parts = components(of: text)
        guard let index = parts.firstIndex(where: { $0 == "launchagents" || $0 == "launchdaemons" }) else { return false }
        return !(index >= 2 && parts[index - 1] == "library" && parts[index - 2] == "contents")
    }

    static func isShellStartupFile(_ text: String) -> Bool {
        guard let last = components(of: text).last else { return false }
        return startupFiles.contains(last)
    }

    static func isWindowsStartupFolder(_ text: String) -> Bool {
        let path = text.lowercased().replacingOccurrences(of: "\\", with: "/")
        return path.contains("start menu/programs/startup") || path.contains("shell:startup")
    }
}
