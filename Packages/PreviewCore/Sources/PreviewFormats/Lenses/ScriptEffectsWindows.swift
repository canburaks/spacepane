import Foundation

/// Rules for PowerShell and for the `powershell` command wherever it appears. A PowerShell statement
/// is judged as a whole, parentheses and nested expressions included: `iex (irm $url)` and
/// `irm $url | iex` are the same fact.
extension ScriptEffectsAnalyzer {
    func evaluateWindows(_ list: ScriptCommandList, _ invocations: [ScriptInvocation?], dialect: ScriptDialect, depth: Int, line: Int,
                         inSubstitution: Bool, effects: inout ScriptListEffects) throws {
        // A sub-expression is part of the statement that holds it, which is judged as a whole.
        guard dialect == .powerShell, !inSubstitution else { return }
        var statement = PowerShellStatement()
        statement.collect(list, depth: 0)
        let words = statement.words
        let runs = statement.names.contains("iex") || statement.names.contains("invoke-expression")
            || words.contains { $0.contains("scriptblock]::create") }
        let fetches = !statement.names.isDisjoint(with: Self.powerShellFetchers) || words.contains { $0.contains(".downloadstring") }
        let startsDownload = !statement.names.isDisjoint(with: ["start-process", "saps", "invoke-item"])
            && (words.contains(where: { $0.contains(".downloadfile") }) || (fetches && words.contains("-outfile")))
        // A run of a file this list saved (`iwr ... -OutFile x; Start-Process x`) is already counted once by the saved-file
        // rule, which is why the statement is not counted again.
        if (runs && fetches) || startsDownload, effects.count(of: .downloadAndRun) == 0 {
            effects.add(.downloadAndRun)
        }
        if runs, words.contains(where: { $0.contains("::frombase64string") }) { effects.add(.decodeAndRun) }
        if words.contains(where: { $0.contains(".uploadfile") }) { effects.add(.uploadsFiles) }
        if words.contains(where: { $0.contains(".promptforcredential") }) { effects.add(.asksForPassword) }
        // A request with a body taken from a file.
        let posts = words.firstIndex(where: { $0 == "-method" }).map { $0 + 1 < words.count && ["post", "put", "patch"].contains(words[$0 + 1]) } ?? false
        let readsFile = statement.names.contains("get-content") || words.contains { $0.contains("readallbytes") || $0.contains("readalltext") }
        if posts, readsFile, !statement.names.isDisjoint(with: Self.powerShellRequesters) { effects.add(.uploadsFiles) }
    }

    static let powerShellFetchers: Set<String> = ["iwr", "irm", "invoke-webrequest", "invoke-restmethod", "curl", "wget"]
    static let powerShellRequesters: Set<String> = ["iwr", "irm", "invoke-webrequest", "invoke-restmethod"]

    /// `powershell -EncodedCommand ...` and `powershell -Command "..."`: the encoded text is reported and never
    /// decoded; the command text is read as PowerShell.
    func evaluatePowerShellInvocation(_ arguments: [ScriptWord], depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        let valueOptions = ["windowstyle", "executionpolicy", "file", "version", "inputformat", "outputformat", "workingdirectory", "ep"]
        var index = 0
        while index < arguments.count {
            let raw = arguments[index].text.lowercased()
            index += 1
            guard raw.count > 1, raw.hasPrefix("-") || raw.hasPrefix("/") else {
                // The first word that is not an option starts the command, which is the default parameter.
                let code = arguments[(index - 1)...].map(\.text)
                try analyzePowerShellText(code.joined(separator: " "), depth: depth + 1, line: line, effects: &effects)
                return
            }
            var name = String(raw.dropFirst())
            var inline: String?
            if let colon = name.firstIndex(of: ":") {
                inline = String(name[name.index(after: colon)...])
                name = String(name[..<colon])
            }
            if name == "ec" || "encodedcommand".hasPrefix(name) {
                effects.add(.decodeAndRun)
                return
            }
            if "command".hasPrefix(name) {
                let code = (inline.map { [$0] } ?? []) + arguments[index...].map(\.text)
                try analyzePowerShellText(code.joined(separator: " "), depth: depth + 1, line: line, effects: &effects)
                return
            }
            if inline == nil, valueOptions.contains(where: { $0.hasPrefix(name) }) { index += 1 }
        }
    }

    /// Reads `text` as PowerShell of its own, for the code given to `powershell -Command`.
    func analyzePowerShellText(_ text: String, depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        guard depth <= Self.maximumNesting, !text.isEmpty else { return }
        let nested = Array(text.utf8)
        try nested.withUnsafeBufferPointer { buffer in
            var lexer = PowerShellLexer(bytes: buffer, context: context)
            while let list = try lexer.nextList() {
                try evaluate(list, dialect: .powerShell, depth: depth, line: line, effects: &effects)
            }
        }
    }

    /// PowerShell cmdlets whose arguments alone decide the effect.
    func evaluatePowerShellTool(_ tool: ScriptTool, _ texts: [String], effects: inout ScriptListEffects) {
        switch tool {
        case .setMpPreference:
            // `-DisableRealtimeMonitoring $true`; a `$false` value turns the protection on.
            for (index, text) in texts.enumerated() where text.hasPrefix("-disable") {
                let inline = text.firstIndex(of: ":").map { String(text[text.index(after: $0)...]) }
                let value = inline ?? (index + 1 < texts.count ? texts[index + 1] : "")
                if !["$false", "0", "false", "$null"].contains(value) {
                    effects.add(.disablesProtection)
                    break
                }
            }
        case .addMpPreference:
            if texts.contains(where: { $0.hasPrefix("-exclusion") }) { effects.add(.disablesProtection) }
        case .getCredential:
            effects.add(.asksForPassword)
        case .readHost:
            if texts.contains("-assecurestring") { effects.add(.asksForPassword) }
        case .startProcess:
            if let verb = texts.firstIndex(where: { $0 == "-verb" || $0.hasPrefix("-verb:") }) {
                let value = texts[verb].firstIndex(of: ":").map { String(texts[verb][texts[verb].index(after: $0)...]) }
                    ?? (verb + 1 < texts.count ? texts[verb + 1] : "")
                if value == "runas" { effects.add(.elevates) }
            }
        case .webRequest:
            if texts.contains("-infile") { effects.add(.uploadsFiles) }
        case .registryProperty:
            if texts.contains(where: { $0.replacingOccurrences(of: "/", with: "\\").contains("currentversion\\run") }) {
                effects.add(.persistence)
            }
        case .registerTask:
            effects.add(.persistence)
        default:
            break
        }
    }
}

/// The command names and lowercased words of one PowerShell statement and everything nested in it.
struct PowerShellStatement {
    private static let wordLimit = 4_096
    private(set) var names: Set<String> = []
    private(set) var words: [String] = []

    mutating func collect(_ list: ScriptCommandList, depth: Int) {
        for command in list.commands {
            if let invocation = ScriptInvocation.resolve(command, dialect: .powerShell) { names.insert(invocation.name) }
            for word in command.words + command.redirects.map(\.target) {
                if words.count < Self.wordLimit { words.append(word.text.lowercased()) }
                guard depth < ShellLexer.maximumDepth else { continue }
                for substitution in word.substitutions { collect(substitution.list, depth: depth + 1) }
            }
        }
    }
}
