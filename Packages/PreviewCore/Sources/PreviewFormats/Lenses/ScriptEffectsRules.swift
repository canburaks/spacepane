import Foundation

/// The per-command rules: what one command, with its wrappers resolved, does when run. A tool is
/// recognized by its name at command position, so a word in an `echo` message or a variable such as
/// `SUDO_USER` is never mistaken for one.
extension ScriptEffectsAnalyzer {
    func evaluate(_ invocation: ScriptInvocation, of command: ScriptCommand, dialect: ScriptDialect, depth: Int, line: Int,
                  effects: inout ScriptListEffects) throws {
        if invocation.viaSudo { effects.add(.elevates) }
        if invocation.sudoReadsPassword { effects.add(.asksForPassword) }
        // A substitution in command position runs its output.
        evaluateExecuted(invocation.commandWord, dialect: dialect, effects: &effects)
        guard let tool = ScriptTool.named(invocation.name) else { return }
        let arguments = invocation.arguments
        switch tool {
        case .curl:
            if ScriptArguments.curl(arguments).uploadsFile { effects.add(.uploadsFiles) }
        case .netcat:
            let readsFile = command.redirects.contains { $0.kind == .input && $0.target.text != "/dev/null" }
            if readsFile, !Self.isListening(invocation) { effects.add(.uploadsFiles) }
        case .eval:
            for word in arguments { evaluateExecuted(word, dialect: dialect, effects: &effects) }
        case .source:
            if let first = arguments.first { evaluateExecuted(first, dialect: dialect, effects: &effects) }
        case .interpreter(let kind):
            try evaluateInterpreter(kind, invocation, command, dialect: dialect, depth: depth, line: line, effects: &effects)
        default:
            evaluateSystemTool(tool, arguments, effects: &effects)
        }
    }

    /// Tools whose arguments alone decide the effect.
    private func evaluateSystemTool(_ tool: ScriptTool, _ arguments: [ScriptWord], effects: inout ScriptListEffects) {
        let texts = arguments.map { $0.text.lowercased() }
        switch tool {
        case .xattr:
            // `-c` clears every attribute; `-d` deletes the one named.
            let letters = arguments.compactMap { ScriptArguments.shortLetters($0.text) }
            let clears = letters.contains { $0.contains("c") }
            let deletes = letters.contains { $0.contains("d") }
            if clears || (deletes && texts.contains { $0.contains("com.apple.quarantine") }) { effects.add(.removesQuarantine) }
        case .defaults:
            evaluateDefaults(texts, effects: &effects)
        case .spctl:
            if texts.contains(where: { $0 == "--master-disable" || $0 == "--global-disable" || $0 == "--disable" }) {
                effects.add(.disablesProtection)
            }
        case .csrutil:
            if texts.contains("disable") { effects.add(.disablesProtection) }
        case .socketfilterfw:
            if let flag = texts.firstIndex(of: "--setglobalstate"), flag + 1 < texts.count, ["off", "0"].contains(texts[flag + 1]) {
                effects.add(.disablesProtection)
            }
        case .netsh:
            if turnsFirewallOff(texts) { effects.add(.disablesProtection) }
        case .dscl:
            if texts.contains("-authonly") { effects.add(.asksForPassword) }
        case .security:
            switch texts.first(where: { !$0.hasPrefix("-") }) {
            case "find-generic-password", "find-internet-password", "dump-keychain", "export": effects.add(.readsSecrets)
            case "unlock-keychain": if texts.contains("-p") { effects.add(.asksForPassword) }
            default: break
            }
        case .launchctl:
            if let subcommand = texts.first(where: { !$0.hasPrefix("-") }), ["load", "bootstrap", "enable", "submit"].contains(subcommand) {
                effects.add(.persistence)
            }
        case .crontab:
            // Listing (-l), removing (-r) and editing by hand (-e) install nothing.
            let letters = arguments.compactMap { ScriptArguments.shortLetters($0.text) }
            if !letters.contains(where: { $0.contains("l") || $0.contains("r") || $0.contains("e") }) { effects.add(.persistence) }
        case .tee:
            let appends = arguments.contains { ScriptArguments.shortLetters($0.text)?.contains("a") == true }
            let files = arguments.filter { !$0.text.hasPrefix("-") }
            if (appends && files.contains { ScriptPersistence.isShellStartupFile($0.text) }) || files.contains(where: { ScriptPersistence.isLaunchFolder($0.text) }) {
                effects.add(.persistence)
            }
        case .copy:
            if arguments.contains(where: { ScriptPersistence.isLaunchFolder($0.text) || ScriptPersistence.isWindowsStartupFolder($0.text) }) {
                effects.add(.persistence)
            }
        case .plistBuddy:
            let edits = texts.contains { text in ["add ", "set ", "merge ", "import ", "copy "].contains { text.hasPrefix($0) } }
            if edits, arguments.contains(where: { ScriptPersistence.isLaunchFolder($0.text) }) { effects.add(.persistence) }
        case .setMpPreference, .addMpPreference, .getCredential, .readHost, .startProcess, .webRequest, .registryProperty, .registerTask:
            evaluatePowerShellTool(tool, texts, effects: &effects)
        case .runas:
            effects.add(.elevates)
        case .schtasks:
            if texts.contains(where: { $0 == "/create" || $0 == "-create" }) { effects.add(.persistence) }
        case .reg:
            if texts.first == "add", texts.contains(where: { $0.replacingOccurrences(of: "/", with: "\\").contains("currentversion\\run") }) {
                effects.add(.persistence)
            }
        default:
            break
        }
    }

    /// `defaults write com.apple.LaunchServices LSQuarantine -bool NO` and a write into a launchd folder.
    private func evaluateDefaults(_ texts: [String], effects: inout ScriptListEffects) {
        guard texts.first == "write" else { return }
        if let key = texts.firstIndex(of: "lsquarantine") {
            var value = key + 1
            if value < texts.count, texts[value].hasPrefix("-") { value += 1 }
            if value < texts.count, ["no", "false", "0"].contains(texts[value]) { effects.add(.removesQuarantine) }
        }
        if texts.count > 1, ScriptPersistence.isLaunchFolder(texts[1]) { effects.add(.persistence) }
    }

    /// `netsh advfirewall set allprofiles state off` and the older `netsh firewall set opmode disable`.
    private func turnsFirewallOff(_ texts: [String]) -> Bool {
        guard texts.contains("set") else { return false }
        if texts.contains("advfirewall"), let state = texts.firstIndex(of: "state"), state + 1 < texts.count, texts[state + 1] == "off" { return true }
        if texts.contains("firewall"), let mode = texts.firstIndex(where: { $0 == "opmode" || $0.hasPrefix("mode=") }) {
            return texts[mode...].contains { $0 == "disable" || $0 == "mode=disable" }
        }
        return false
    }

    // MARK: Redirections and secrets

    /// Output written into a launchd folder or appended to a shell start-up file.
    func evaluateRedirects(of command: ScriptCommand, effects: inout ScriptListEffects) {
        for redirect in command.redirects where redirect.kind == .output || redirect.kind == .append {
            let target = redirect.target.text
            if ScriptPersistence.isLaunchFolder(target) || ScriptPersistence.isWindowsStartupFolder(target)
                || (redirect.kind == .append && ScriptPersistence.isShellStartupFile(target)) {
                effects.add(.persistence)
            }
        }
    }

    /// A word that names a credential store. Messages (`echo`), the programs that use one's own key
    /// legitimately (`ssh`, `git`) and `security` (its subcommands decide) are skipped. A command that only
    /// handles a file's metadata (`chmod`, `ls`) and a bare assignment count only for the strong stores.
    func evaluateSecrets(of command: ScriptCommand, invocation: ScriptInvocation?, effects: inout ScriptListEffects) {
        var strongOnly = invocation == nil
        switch invocation.flatMap({ ScriptTool.named($0.name) }) {
        case .message?, .keyTool?, .security?: return
        case .fileMeta?, .chmod?: strongOnly = true
        default: break
        }
        let inputs = command.redirects.filter { $0.kind == .input }.map(\.target)
        for word in command.words + inputs {
            guard let strength = ScriptSecretPaths.strength(of: word.text) else { continue }
            if strength == .strong || !(strongOnly || word.isAssignment) {
                effects.add(.readsSecrets)
                return
            }
        }
    }
}
