import Foundation

/// Interpreters and the files a script saves and runs: what `sh -c`, `eval`, `osascript`, a here-document
/// or a downloaded file makes run. Together with the pipeline rules these are the download-and-run and
/// decode-and-run findings.
extension ScriptEffectsAnalyzer {
    func evaluateInterpreter(_ kind: ScriptInterpreter, _ invocation: ScriptInvocation, _ command: ScriptCommand,
                                     dialect: ScriptDialect, depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        let arguments = invocation.arguments
        switch kind {
        case .osascript:
            try evaluateOsascript(arguments, command, depth: depth, line: line, effects: &effects)
        case .powerShell:
            try evaluatePowerShellInvocation(arguments, depth: depth, line: line, effects: &effects)
        case .shell, .python, .perl, .ruby, .node:
            switch kind.program(arguments: arguments) {
            case .code(let index):
                let word = arguments[index]
                if word.isWholeSubstitution {
                    evaluateExecuted(word, dialect: dialect, effects: &effects)
                } else if kind == .shell {
                    try analyzeText(word.text, dialect: .shell, depth: depth + 1, line: line, effects: &effects)
                } else if ScriptDecoding.decodesAndRuns(kind, code: word.text) {
                    effects.add(.decodeAndRun)
                }
            case .file(let index?):
                evaluateExecuted(arguments[index], dialect: dialect, effects: &effects)
            case .file(nil):
                break
            case .standardInput:
                try evaluateStandardInput(kind, command, depth: depth, line: line, effects: &effects)
            }
        }
    }

    /// A here-document or here-string handed to an interpreter is its program.
    private func evaluateStandardInput(_ kind: ScriptInterpreter, _ command: ScriptCommand, depth: Int, line: Int,
                                       effects: inout ScriptListEffects) throws {
        for redirect in command.redirects {
            switch redirect.kind {
            case .hereDocument:
                if let body = redirect.body { try analyzeBody(body, startLine: redirect.bodyLine, as: kind, depth: depth) }
            case .input where redirect.target.isWholeSubstitution:
                evaluateExecuted(redirect.target, dialect: .shell, effects: &effects)
            case .hereString:
                if redirect.target.isWholeSubstitution {
                    evaluateExecuted(redirect.target, dialect: .shell, effects: &effects)
                } else if kind == .shell {
                    try analyzeText(redirect.target.text, dialect: .shell, depth: depth + 1, line: line, effects: &effects)
                } else if kind == .osascript {
                    try evaluateAppleScript(redirect.target.text, depth: depth + 1, line: line, effects: &effects)
                }
            default:
                break
            }
        }
    }

    /// `osascript -e '...'` and an AppleScript here-document are AppleScript for the other rules.
    private func evaluateOsascript(_ arguments: [ScriptWord], _ command: ScriptCommand, depth: Int, line: Int,
                                   effects: inout ScriptListEffects) throws {
        var script: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index].text == "-e", index + 1 < arguments.count {
                script.append(arguments[index + 1].text)
                index += 1
            }
            index += 1
        }
        if !script.isEmpty {
            try evaluateAppleScript(script.joined(separator: "\n"), depth: depth + 1, line: line, effects: &effects)
        }
        guard ScriptInterpreter.osascript.program(arguments: arguments) == .standardInput else { return }
        try evaluateStandardInput(.osascript, command, depth: depth, line: line, effects: &effects)
    }

    // MARK: Saved files

    /// Follows files a script downloads or decodes, makes executable and runs. A file saved on one line and run
    /// on a later one is one finding. Shell and PowerShell report it on the line of the run, in the run's command
    /// list; batch scripts report it on the line that saved the file, as they always have.
    func trackFiles(_ command: ScriptCommand, _ invocation: ScriptInvocation, dialect: ScriptDialect, line: Int,
                    effects: inout ScriptListEffects) {
        let windows = dialect == .batch || dialect == .powerShell
        let arguments = invocation.arguments
        // A download is saved where its option or its output redirection says.
        let redirected = command.redirects.last { $0.kind == .output || $0.kind == .append }?.target.text
        if let saved = Self.downloadTarget(of: invocation) ?? (Self.isDownloader(invocation) ? redirected : nil) {
            ScriptSavedFiles.remember(ScriptSavedFile(key: ScriptArguments.fileKey(saved, windows: windows), line: line), in: &savedFiles.downloads)
        }
        if let decoded = Self.decodeTarget(of: invocation) {
            ScriptSavedFiles.remember(ScriptSavedFile(key: ScriptArguments.fileKey(decoded, windows: windows), line: line), in: &savedFiles.decodes)
        } else if Self.isDecoder(invocation) {
            for redirect in command.redirects where redirect.kind == .output || redirect.kind == .append {
                let file = ScriptSavedFile(key: ScriptArguments.fileKey(redirect.target.text, windows: windows), line: line)
                ScriptSavedFiles.remember(file, in: &savedFiles.decodes)
            }
        }
        if case .chmod? = ScriptTool.named(invocation.name) {
            let operands = arguments.filter { !$0.text.hasPrefix("-") }
            if let mode = operands.first, ScriptArguments.setsExecuteBit(mode.text) {
                for target in operands.dropFirst() { savedFiles.markExecutable(ScriptArguments.fileKey(target.text, windows: false)) }
            }
        }
        guard let run = Self.executedFile(invocation, dialect: dialect) else { return }
        let key = ScriptArguments.fileKey(run.path, windows: windows)
        // A directly run file needs the execute bit a `chmod` of this script gave it, unless it is a Windows file.
        // A file that `open` or `Start-Process` launches runs only if its name is of a program kind, or it has the bit.
        let hasExecuteBit = savedFiles.executable.contains(key)
        let runs = run.opened
            ? hasExecuteBit || ScriptArguments.opensAsProgram(run.path, windows: windows)
            : !run.direct || windows || hasExecuteBit
        guard runs else { return }
        if let index = savedFiles.downloads.firstIndex(where: { ScriptArguments.sameFile($0.key, key, windows: windows) }) {
            reportSavedRun(.downloadAndRun, saved: savedFiles.downloads.remove(at: index), dialect: dialect, effects: &effects)
        }
        if let index = savedFiles.decodes.firstIndex(where: { ScriptArguments.sameFile($0.key, key, windows: windows) }) {
            reportSavedRun(.decodeAndRun, saved: savedFiles.decodes.remove(at: index), dialect: dialect, effects: &effects)
        }
    }

    /// One run of a saved file. Batch scripts tally it on the saving line; the other dialects add it to the run's
    /// command list, which is tallied on the line of the run.
    private func reportSavedRun(_ effect: ScriptEffect, saved: ScriptSavedFile, dialect: ScriptDialect,
                                effects: inout ScriptListEffects) {
        if dialect == .batch {
            record(effect, line: saved.line)
        } else {
            effects.add(effect)
        }
    }

    /// The file a downloader saves to, including the Windows downloaders (`certutil -urlcache`, `bitsadmin /transfer`).
    static func downloadTarget(of invocation: ScriptInvocation) -> String? {
        let arguments = invocation.arguments
        switch ScriptTool.named(invocation.name) {
        case .curl?, .fetch?: return ScriptArguments.curl(arguments).outputFile
        case .wget?: return ScriptArguments.wget(arguments).outputFile
        case .webRequest?: return ScriptArguments.outFile(arguments)
        case .certutil?:
            let texts = arguments.map { $0.text.lowercased() }
            guard texts.contains(where: { $0 == "-urlcache" || $0 == "/urlcache" }), texts.contains(where: { $0 == "-f" || $0 == "/f" }) else { return nil }
            let operands = arguments.filter { !$0.text.hasPrefix("-") && !$0.text.hasPrefix("/") }
            return operands.count >= 2 ? operands.last?.text : nil
        case .bitsadmin?:
            let texts = arguments.map { $0.text.lowercased() }
            guard let transfer = texts.firstIndex(of: "/transfer") else { return nil }
            let operands = arguments[(transfer + 1)...].filter { !$0.text.hasPrefix("/") }
            return operands.count >= 3 ? operands.last?.text : nil
        default: return nil
        }
    }

    /// The file `certutil -decode in out` writes.
    static func decodeTarget(of invocation: ScriptInvocation) -> String? {
        guard case .certutil? = ScriptTool.named(invocation.name) else { return nil }
        let arguments = invocation.arguments
        guard arguments.contains(where: { ["-decode", "/decode", "-decodehex", "/decodehex"].contains($0.text.lowercased()) }) else { return nil }
        let operands = arguments.filter { !$0.text.hasPrefix("-") && !$0.text.hasPrefix("/") }
        return operands.count >= 2 ? operands.last?.text : nil
    }

    /// The file a command runs. `direct` means it runs as a program and needs an execute bit; `opened` means
    /// `open` or `Start-Process` launches it, which runs only some kinds of file.
    struct ExecutedFile {
        var path: String
        var direct: Bool
        var opened = false
    }

    /// The file a command runs: directly, as a script of an interpreter or `source`, through `open` or
    /// `installer -pkg`, or through PowerShell's `Start-Process`. `start` runs a file only in PowerShell.
    static func executedFile(_ invocation: ScriptInvocation, dialect: ScriptDialect) -> ExecutedFile? {
        let arguments = invocation.arguments
        switch ScriptTool.named(invocation.name) {
        case .interpreter(let kind)?:
            guard kind != .powerShell, case .file(let index?) = kind.program(arguments: arguments) else { return nil }
            return ExecutedFile(path: arguments[index].text, direct: false)
        case .source?:
            return arguments.first.map { ExecutedFile(path: $0.text, direct: false) }
        case .opener?:
            return ScriptArguments.openedFile(arguments).map { ExecutedFile(path: $0, direct: true, opened: true) }
        case .installer?:
            return ScriptArguments.installedPackage(arguments).map { ExecutedFile(path: $0, direct: false) }
        case .startProcess?:
            guard dialect == .powerShell else { return nil }
            return ScriptArguments.startedFile(arguments).map { ExecutedFile(path: $0, direct: false, opened: true) }
        default:
            return ExecutedFile(path: invocation.commandWord.text, direct: true)
        }
    }
}

// MARK: - Decoding in code strings

enum ScriptDecoding {
    /// An interpreter's own code string that decodes base64 text and evaluates the result. Only the
    /// two words are looked for; nothing is decoded.
    static func decodesAndRuns(_ kind: ScriptInterpreter, code: String) -> Bool {
        let text = code.lowercased()
        switch kind {
        case .python: return (text.contains("exec(") || text.contains("eval(")) && (text.contains("b64decode") || text.contains("decode('base64')") || text.contains("decode(\"base64\")"))
        case .perl: return text.contains("eval") && text.contains("decode_base64")
        case .ruby: return text.contains("eval") && text.contains("decode64")
        case .node: return (text.contains("eval(") || text.contains("function(")) && (text.contains("base64") || text.contains("atob("))
        case .shell, .osascript, .powerShell: return false
        }
    }
}
