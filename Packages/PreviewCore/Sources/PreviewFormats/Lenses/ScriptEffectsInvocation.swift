import Foundation

/// A command with its wrappers peeled off: `sudo -E env FOO=1 bash -s` is the command `bash` with
/// arguments `-s`, run through `sudo`. Names are lowercased base names without `.exe`.
struct ScriptInvocation {
    let name: String
    let words: [ScriptWord]
    let argumentStart: Int
    var viaSudo = false
    /// `sudo -S` / `--stdin`: the password is read from standard input.
    var sudoReadsPassword = false

    var commandWord: ScriptWord { words[argumentStart - 1] }
    var arguments: [ScriptWord] { argumentStart < words.count ? Array(words[argumentStart...]) : [] }

    static func baseName(of text: String) -> String {
        var name = Substring(text)
        if let slash = name.lastIndex(where: { $0 == "/" || $0 == "\\" }) { name = name[name.index(after: slash)...] }
        var lowered = name.lowercased()
        if lowered.hasSuffix(".exe") { lowered.removeLast(4) }
        return lowered
    }

    static func resolve(_ command: ScriptCommand, dialect: ScriptDialect) -> ScriptInvocation? {
        switch dialect {
        case .shell, .fish: resolveShell(command)
        case .batch: resolveBatch(command)
        case .powerShell: resolvePowerShell(command)
        case .appleScript: nil
        }
    }

    // MARK: Shell

    /// Words that start a command in the shell grammar without being the command.
    private static let shellKeywords: Set<String> = [
        "if", "then", "elif", "else", "do", "while", "until", "!", "{", "time", "coproc", "and", "or", "not", "begin"
    ]

    static func isShellKeyword(_ text: String) -> Bool { shellKeywords.contains(text) }

    private static func resolveShell(_ command: ScriptCommand) -> ScriptInvocation? {
        let words = command.words
        var index = 0
        var viaSudo = false
        var readsPassword = false
        while index < words.count {
            let word = words[index]
            if word.isAssignment || shellKeywords.contains(word.text) {
                index += 1
                continue
            }
            // `function sudo { ...; }` defines a function; it runs nothing.
            if word.text == "function" { return nil }
            let name = baseName(of: word.text)
            switch name {
            case "sudo":
                viaSudo = true
                index = skipSudoOptions(words, from: index + 1, readsPassword: &readsPassword)
                // `sudo -v` and `sudo -k` name no command but still ask for elevation.
                if index >= words.count {
                    return ScriptInvocation(name: name, words: words, argumentStart: words.count, viaSudo: true, sudoReadsPassword: readsPassword)
                }
            case "env":
                index = skip(words, from: index + 1, valueOptions: ["u", "S", "C", "P"], allowsAssignments: true)
            case "command", "builtin":
                let next = skip(words, from: index + 1, valueOptions: [], allowsAssignments: false)
                // `command -v name` only looks the name up.
                if words[(index + 1)..<next].contains(where: { $0.text.hasPrefix("-") && ($0.text.contains("v") || $0.text.contains("V")) }) {
                    return nil
                }
                index = next
            case "exec", "nohup", "setsid", "caffeinate":
                index = skip(words, from: index + 1, valueOptions: ["a", "t", "w"], allowsAssignments: false)
            case "nice":
                index = skip(words, from: index + 1, valueOptions: ["n"], allowsAssignments: false)
            case "timeout":
                index = skip(words, from: index + 1, valueOptions: ["s", "k"], allowsAssignments: false) + 1
            default:
                return ScriptInvocation(name: name, words: words, argumentStart: index + 1, viaSudo: viaSudo, sudoReadsPassword: readsPassword)
            }
        }
        return nil
    }

    /// Index after the leading options (and, for `env`, assignments) that start at `start`.
    private static func skip(_ words: [ScriptWord], from start: Int, valueOptions: Set<Character>, allowsAssignments: Bool) -> Int {
        var index = start
        while index < words.count {
            let text = words[index].text
            if allowsAssignments, words[index].isAssignment {
                index += 1
            } else if text == "--" {
                return index + 1
            } else if text.hasPrefix("-"), text.count > 1 {
                let letters = Array(text.dropFirst())
                if !text.hasPrefix("--"), let last = letters.last, valueOptions.contains(last) { index += 1 }
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private static let sudoValueOptions: Set<Character> = ["u", "g", "h", "p", "C", "D", "r", "t", "U", "T"]
    private static let sudoValueLongOptions: Set<String> = [
        "--user", "--group", "--host", "--prompt", "--close-from", "--chdir", "--role", "--type", "--other-user", "--command-timeout"
    ]

    private static func skipSudoOptions(_ words: [ScriptWord], from start: Int, readsPassword: inout Bool) -> Int {
        var index = start
        while index < words.count {
            let text = words[index].text
            if words[index].isAssignment {
                index += 1
            } else if text == "--" {
                return index + 1
            } else if text.hasPrefix("--") {
                if text == "--stdin" { readsPassword = true }
                if sudoValueLongOptions.contains(text) { index += 1 }
                index += 1
            } else if text.hasPrefix("-"), text.count > 1 {
                let letters = Array(text.dropFirst())
                if letters.contains("S") { readsPassword = true }
                // A letter that takes a value ends the cluster: the value is the rest, or the next word.
                if let position = letters.firstIndex(where: { sudoValueOptions.contains($0) }), position == letters.count - 1 { index += 1 }
                index += 1
            } else {
                break
            }
        }
        return index
    }

    // MARK: Batch and PowerShell

    private static func resolveBatch(_ command: ScriptCommand) -> ScriptInvocation? {
        let words = command.words
        var index = 0
        while index < words.count {
            let text = words[index].text.lowercased()
            switch text {
            case "@", "call", "else", "do":
                index += 1
            case "if":
                index = skipBatchCondition(words, from: index + 1)
            case "start":
                index += 1
                // Options come first, then a quoted window title (the first quoted word, as in cmd), then the program.
                while index < words.count, words[index].text.hasPrefix("/") { index += 1 }
                if index < words.count, words[index].isQuoted { index += 1 }
                while index < words.count, words[index].text.hasPrefix("/"), words[index].text.count <= 8 { index += 1 }
            case "cmd", "cmd.exe":
                index += 1
                while index < words.count, words[index].text.hasPrefix("/") {
                    let option = words[index].text.lowercased()
                    index += 1
                    if option == "/c" || option == "/k" { break }
                }
            default:
                // `@echo off`, and the first command of a parenthesized block on one line.
                let name = text.drop(while: { $0 == "@" || $0 == "(" })
                return ScriptInvocation(name: baseName(of: String(name)), words: words, argumentStart: index + 1)
            }
        }
        return nil
    }

    /// `if [/i] [not] exist X`, `defined X`, `errorlevel N`, and `A == B` (or `A equ B`).
    private static func skipBatchCondition(_ words: [ScriptWord], from start: Int) -> Int {
        var index = start
        if index < words.count, words[index].text.lowercased() == "/i" { index += 1 }
        if index < words.count, words[index].text.lowercased() == "not" { index += 1 }
        guard index < words.count else { return index }
        switch words[index].text.lowercased() {
        case "exist", "defined", "errorlevel", "cmdextversion": return index + 2
        default:
            // `"%a%"=="b"` is one word; `%a% == b` is three.
            return words[index].text.contains("==") ? index + 1 : index + 3
        }
    }

    private static func resolvePowerShell(_ command: ScriptCommand) -> ScriptInvocation? {
        let words = command.words
        var index = 0
        // The call operator and dot-sourcing precede a command.
        while index < words.count, words[index].text == "&" || words[index].text == "." { index += 1 }
        guard index < words.count else { return nil }
        // `$value = Get-Credential`: the command follows the assignment.
        let first = words[index].text
        if first.hasPrefix("$") {
            if index + 1 < words.count, ["=", "+=", "-=", "*="].contains(words[index + 1].text) {
                index += 2
            } else if let equals = first.firstIndex(of: "="), first.index(after: equals) < first.endIndex {
                return ScriptInvocation(name: baseName(of: String(first[first.index(after: equals)...])), words: words, argumentStart: index + 1)
            }
        }
        guard index < words.count else { return nil }
        return ScriptInvocation(name: baseName(of: words[index].text), words: words, argumentStart: index + 1)
    }
}

// MARK: - Tools

/// The programs the rules know by name, so a command costs one dictionary lookup.
enum ScriptTool {
    case curl, wget, fetch, base64, openssl, xxd, xattr, defaults, spctl, csrutil, socketfilterfw
    case security, dscl, launchctl, crontab, chmod, tee, netcat, eval, source, message, keyTool, copy, runas
    case schtasks, reg, netsh, certutil, bitsadmin, plistBuddy
    case fileMeta
    case setMpPreference, addMpPreference, getCredential, readHost, startProcess, webRequest, registryProperty, registerTask
    case interpreter(ScriptInterpreter)

    static func named(_ name: String) -> ScriptTool? { table[name] ?? ScriptInterpreter(name: name).map { .interpreter($0) } }

    private static let table: [String: ScriptTool] = [
        "curl": .curl, "wget": .wget, "fetch": .fetch, "base64": .base64, "openssl": .openssl, "xxd": .xxd, "xattr": .xattr,
        "defaults": .defaults, "spctl": .spctl, "csrutil": .csrutil, "socketfilterfw": .socketfilterfw, "security": .security,
        "dscl": .dscl, "launchctl": .launchctl, "crontab": .crontab, "chmod": .chmod, "tee": .tee, "nc": .netcat,
        "ncat": .netcat, "netcat": .netcat, "eval": .eval, "source": .source, ".": .source,
        "echo": .message, "printf": .message, "print": .message, "say": .message, "logger": .message,
        "write-host": .message, "write-output": .message, "write-warning": .message, "write-error": .message,
        "ssh": .keyTool, "ssh-add": .keyTool, "ssh-keygen": .keyTool, "ssh-copy-id": .keyTool, "scp": .keyTool,
        "sftp": .keyTool, "git": .keyTool, "test": .keyTool, "[": .keyTool, "[[": .keyTool,
        "chown": .fileMeta, "chgrp": .fileMeta, "ls": .fileMeta, "stat": .fileMeta, "mkdir": .fileMeta, "rm": .fileMeta,
        "file": .fileMeta, "readlink": .fileMeta, "realpath": .fileMeta,
        "cp": .copy, "mv": .copy, "install": .copy, "ln": .copy, "touch": .copy, "ditto": .copy, "rsync": .copy,
        "copy": .copy, "move": .copy, "xcopy": .copy, "robocopy": .copy, "copy-item": .copy, "move-item": .copy,
        "new-item": .copy, "set-content": .copy, "add-content": .copy, "out-file": .copy,
        "runas": .runas, "schtasks": .schtasks, "reg": .reg, "netsh": .netsh, "certutil": .certutil,
        "bitsadmin": .bitsadmin, "plistbuddy": .plistBuddy,
        "set-mppreference": .setMpPreference, "add-mppreference": .addMpPreference, "get-credential": .getCredential,
        "read-host": .readHost, "start-process": .startProcess, "saps": .startProcess,
        "iwr": .webRequest, "irm": .webRequest, "invoke-webrequest": .webRequest, "invoke-restmethod": .webRequest,
        "set-itemproperty": .registryProperty, "new-itemproperty": .registryProperty, "register-scheduledtask": .registerTask
    ]
}

enum ScriptInterpreter {
    case shell, python, perl, ruby, node, osascript, powerShell

    /// Versioned names (`python3.12`, `perl5`, `ksh93`) share their family.
    init?(name: String) {
        var stem = Substring(name)
        while let last = stem.last, last.isNumber || last == "." { stem = stem.dropLast() }
        switch stem {
        case "sh", "bash", "zsh", "ksh", "dash", "ash", "csh", "tcsh", "fish", "mksh", "rbash": self = .shell
        case "python", "pypy": self = .python
        case "perl": self = .perl
        case "ruby", "jruby": self = .ruby
        case "node", "nodejs": self = .node
        case "osascript": self = .osascript
        case "pwsh", "powershell": self = .powerShell
        default: return nil
        }
    }

    /// How the interpreter's command line names its code. See `ScriptProgram`.
    fileprivate var grammar: ProgramGrammar {
        switch self {
        case .shell: ProgramGrammar(code: ["c"], longCode: ["--command"], value: ["o", "O"], rest: [], standardInput: ["s"],
                                    longValue: ["--rcfile", "--init-file"], plusOptions: true)
        case .python: ProgramGrammar(code: ["c"], module: ["m"], value: ["W", "X", "Q"])
        case .perl: ProgramGrammar(code: ["e", "E"], value: ["I"], rest: ["M", "m", "x", "i", "0", "l", "F"])
        case .ruby: ProgramGrammar(code: ["e"], value: ["r", "I", "C"], rest: ["x", "K", "E"])
        case .node: ProgramGrammar(code: ["e", "p"], longCode: ["--eval", "--print"], value: ["r"], longValue: ["--require", "--import", "--loader"])
        case .osascript: ProgramGrammar(code: ["e"], value: ["l", "s"])
        case .powerShell: ProgramGrammar(code: [])
        }
    }
}

/// Where an interpreter takes its program from.
enum ScriptProgram: Equatable {
    case standardInput
    /// The code is in the argument at this index.
    case code(Int)
    /// A script file named on the command line (at this argument index), or a module (`nil`).
    case file(Int?)
}

fileprivate struct ProgramGrammar {
    var code: Set<Character> = []
    var longCode: Set<String> = []
    var module: Set<Character> = []
    var value: Set<Character> = []
    /// Letters whose value is the rest of the cluster (`-MPOSIX`, `-i.bak`).
    var rest: Set<Character> = []
    var standardInput: Set<Character> = []
    var longValue: Set<String> = []
    var plusOptions = false
}

extension ScriptInterpreter {
    /// Reads an interpreter's options just far enough to say where its program comes from, so
    /// `curl ... | python3 -c '...'` (data on standard input) differs from `curl ... | python3 -`.
    func program(arguments: [ScriptWord]) -> ScriptProgram {
        let grammar = self.grammar
        var index = 0
        var readsStandardInput = false
        while index < arguments.count {
            let text = arguments[index].text
            if text == "-" { return .standardInput }
            if text == "--" { return readsStandardInput || index + 1 >= arguments.count ? .standardInput : .file(index + 1) }
            if text.hasPrefix("--") {
                let name = String(text.prefix(while: { $0 != "=" }))
                if grammar.longCode.contains(name) {
                    if text.contains("=") { return .code(index) }
                    return index + 1 < arguments.count ? .code(index + 1) : .standardInput
                }
                if grammar.longValue.contains(name), !text.contains("=") { index += 1 }
                index += 1
                continue
            }
            if text.count > 1, text.hasPrefix("-") || (grammar.plusOptions && text.hasPrefix("+")) {
                let letters = Array(text.dropFirst())
                for (offset, letter) in letters.enumerated() {
                    let isLast = offset == letters.count - 1
                    if grammar.code.contains(letter) {
                        if !isLast { return .code(index) }
                        return index + 1 < arguments.count ? .code(index + 1) : .standardInput
                    }
                    if grammar.module.contains(letter) { return .file(nil) }
                    if grammar.standardInput.contains(letter) { readsStandardInput = true }
                    if grammar.value.contains(letter) {
                        if isLast { index += 1 }
                        break
                    }
                    if grammar.rest.contains(letter) { break }
                }
                index += 1
                continue
            }
            if !readsStandardInput { return .file(index) }
            index += 1
        }
        return .standardInput
    }
}
