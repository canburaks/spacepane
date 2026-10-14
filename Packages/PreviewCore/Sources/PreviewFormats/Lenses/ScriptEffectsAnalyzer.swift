import Foundation
import PreviewContracts

/// Occurrences found in one command list, before they are tallied against its first line.
struct ScriptListEffects {
    private var counts = [Int](repeating: 0, count: ScriptEffect.allCases.count)

    mutating func add(_ effect: ScriptEffect, count: Int = 1) { counts[effect.rawValue] += count }
    func count(of effect: ScriptEffect) -> Int { counts[effect.rawValue] }
}

/// A file a command saved by downloading or decoding, and the line that did it.
struct ScriptSavedFile {
    var key: String
    var line: Int
}

/// Files saved by downloading or decoding, and files made executable. A batch script keeps them across
/// lines; any other script keeps them for one command list.
struct ScriptSavedFiles {
    var downloads: [ScriptSavedFile] = []
    var decodes: [ScriptSavedFile] = []
    var executable: Set<String> = []
    static let limit = 8
}

/// Applies the effect rules to the command lists of one script. One instance serves one lens call; it
/// holds the tally and the text it reads, and it never runs, expands or decodes anything it finds.
/// Single-threaded and local to one scan, like the hidden-content scanner's line locator.
final class ScriptEffectsAnalyzer {
    /// Nested code (`sh -c '...'`, substitutions, here-documents) is read to this depth.
    static let maximumNesting = 4

    let context: RequestContext
    let bytes: UnsafeBufferPointer<UInt8>
    private(set) var tally = ScriptEffectsTally()
    /// Files an earlier line of a batch script saved, to be recognized when a later line runs them.
    var pendingBatchFiles = ScriptSavedFiles()

    init(bytes: UnsafeBufferPointer<UInt8>, context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    func analyzeAll(_ dialect: ScriptDialect) throws {
        switch dialect {
        case .shell, .fish:
            var lexer = ShellLexer(bytes: bytes, isFish: dialect == .fish, allowsHeredocs: true, context: context)
            while let list = try lexer.nextList() { try analyze(list, dialect: dialect) }
        case .powerShell:
            var lexer = PowerShellLexer(bytes: bytes, context: context)
            while let list = try lexer.nextList() { try analyze(list, dialect: .powerShell) }
        case .batch, .appleScript:
            break
        }
    }

    /// Evaluates one top-level list and tallies what it found against the line it starts on.
    func analyze(_ list: ScriptCommandList, dialect: ScriptDialect) throws {
        var effects = ScriptListEffects()
        try evaluate(list, dialect: dialect, depth: 0, line: list.line, effects: &effects)
        flush(effects, line: list.line)
    }

    /// An occurrence that belongs to a line other than the one being evaluated.
    func record(_ effect: ScriptEffect, line: Int) {
        tally.add(effect, line: line)
    }

    func flush(_ effects: ScriptListEffects, line: Int) {
        for effect in ScriptEffect.allCases {
            // Reading secrets is one occurrence per line, however many paths the line names.
            let count = effects.count(of: effect)
            tally.add(effect, count: effect == .readsSecrets ? min(count, 1) : count, line: line)
        }
    }

    // MARK: Lists

    func evaluate(_ list: ScriptCommandList, dialect: ScriptDialect, depth: Int, line: Int, inSubstitution: Bool = false,
                  effects: inout ScriptListEffects) throws {
        guard depth <= Self.maximumNesting else { return }
        let commands = list.commands
        let invocations = commands.map { ScriptInvocation.resolve($0, dialect: dialect) }
        evaluatePipelines(commands, invocations, effects: &effects)
        var files = dialect == .batch ? pendingBatchFiles : ScriptSavedFiles()
        for index in commands.indices {
            let command = commands[index]
            let invocation = invocations[index]
            evaluateRedirects(of: command, effects: &effects)
            evaluateSecrets(of: command, invocation: invocation, effects: &effects)
            if let invocation {
                try evaluate(invocation, of: command, dialect: dialect, depth: depth, line: line, effects: &effects)
                trackFiles(command, invocation, dialect: dialect, line: line, files: &files)
            }
            for word in command.words where !word.substitutions.isEmpty {
                try evaluate(substitutionsOf: word, dialect: dialect, depth: depth, line: line, effects: &effects)
            }
            for redirect in command.redirects where !redirect.target.substitutions.isEmpty {
                try evaluate(substitutionsOf: redirect.target, dialect: dialect, depth: depth, line: line, effects: &effects)
            }
        }
        if dialect == .batch { pendingBatchFiles = files }
        try evaluateWindows(list, invocations, dialect: dialect, depth: depth, line: line, inSubstitution: inSubstitution, effects: &effects)
    }

    private func evaluate(substitutionsOf word: ScriptWord, dialect: ScriptDialect, depth: Int, line: Int,
                          effects: inout ScriptListEffects) throws {
        for substitution in word.substitutions {
            try evaluate(substitution.list, dialect: dialect, depth: depth + 1, line: line, inSubstitution: true, effects: &effects)
        }
    }

    /// Reads `text` as a script of its own: the argument of `sh -c`, or a string handed to a shell.
    func analyzeText(_ text: String, dialect: ScriptDialect, depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        guard depth <= Self.maximumNesting, !text.isEmpty else { return }
        let nestedBytes = Array(text.utf8)
        try nestedBytes.withUnsafeBufferPointer { buffer in
            var lexer = ShellLexer(bytes: buffer, isFish: dialect == .fish, allowsHeredocs: false, context: context)
            while let list = try lexer.nextList() {
                try evaluate(list, dialect: dialect, depth: depth, line: line, effects: &effects)
            }
        }
    }

    /// Reads the body of a here-document fed to an interpreter, tallying against the body's own lines.
    func analyzeBody(_ range: Range<Int>, startLine: Int, as interpreter: ScriptInterpreter, depth: Int) throws {
        guard depth < Self.maximumNesting, !range.isEmpty else { return }
        let body = UnsafeBufferPointer(rebasing: bytes[range])
        switch interpreter {
        case .shell:
            var lexer = ShellLexer(bytes: body, line: startLine, isFish: false, allowsHeredocs: false, context: context)
            while let list = try lexer.nextList() {
                var effects = ScriptListEffects()
                try evaluate(list, dialect: .shell, depth: depth + 1, line: list.line, effects: &effects)
                flush(effects, line: list.line)
            }
        case .osascript:
            try analyzeAppleScript(body, startLine: startLine, depth: depth + 1)
        default:
            break
        }
    }

    // MARK: Pipelines

    private func evaluatePipelines(_ commands: [ScriptCommand], _ invocations: [ScriptInvocation?],
                                   effects: inout ScriptListEffects) {
        var first = 0
        while first < commands.count {
            var last = first
            while last + 1 < commands.count, commands[last].next == .pipe { last += 1 }
            if last > first { evaluatePipeline(Array(invocations[first...last]), effects: &effects) }
            first = last + 1
        }
    }

    /// A download or a decoder feeding an interpreter that takes its program from standard input.
    private func evaluatePipeline(_ stages: [ScriptInvocation?], effects: inout ScriptListEffects) {
        var downloaded = false, decoded = false
        var reportedDownload = false, reportedDecode = false
        var previous: ScriptInvocation?
        for case let stage? in stages {
            if Self.isStandardInputExecutor(stage) {
                if downloaded, !reportedDownload { effects.add(.downloadAndRun); reportedDownload = true }
                if decoded, !reportedDecode { effects.add(.decodeAndRun); reportedDecode = true }
            }
            downloaded = downloaded || Self.isDownloader(stage)
            decoded = decoded || Self.isDecoder(stage)
            if case .netcat? = ScriptTool.named(stage.name), previous?.name == "cat",
               let previous, previous.arguments.contains(where: { !$0.text.hasPrefix("-") }), !Self.isListening(stage) {
                effects.add(.uploadsFiles)
            }
            previous = stage
        }
    }

    // MARK: Classifiers

    static func isDownloader(_ invocation: ScriptInvocation) -> Bool {
        switch ScriptTool.named(invocation.name) {
        case .curl?, .wget?, .fetch?: true
        default: false
        }
    }

    /// `base64 -d`, `openssl ... -d -base64`, `xxd -r`: programs whose job is turning text back into bytes.
    static func isDecoder(_ invocation: ScriptInvocation) -> Bool {
        let arguments = invocation.arguments
        switch ScriptTool.named(invocation.name) {
        case .base64?:
            return arguments.contains { word in
                if let letters = ScriptArguments.shortLetters(word.text) { return letters.contains("d") || letters.contains("D") }
                return word.text == "--decode"
            }
        case .openssl?:
            let texts = arguments.map { $0.text.lowercased() }
            return texts.contains("-d") && (texts.contains("-base64") || texts.contains("-a") || texts.contains("base64"))
        case .xxd?:
            return arguments.contains { ScriptArguments.shortLetters($0.text)?.contains("r") == true || $0.text == "-revert" }
        default:
            return false
        }
    }

    /// An interpreter that, as invoked, runs the program it reads from standard input.
    static func isStandardInputExecutor(_ invocation: ScriptInvocation) -> Bool {
        switch ScriptTool.named(invocation.name) {
        case .interpreter(let kind)?:
            return kind != .powerShell && kind.program(arguments: invocation.arguments) == .standardInput
        case .source?:
            let texts = invocation.arguments.map(\.text)
            return texts.isEmpty || texts == ["-"] || texts == ["/dev/stdin"]
        default:
            return false
        }
    }

    static func isListening(_ invocation: ScriptInvocation) -> Bool {
        invocation.arguments.contains { ScriptArguments.shortLetters($0.text)?.contains("l") == true || $0.text == "--listen" }
    }

    /// The substitution that makes up the whole word runs a download or a decoder whose output the
    /// enclosing command then executes.
    func evaluateExecuted(_ word: ScriptWord, dialect: ScriptDialect, effects: inout ScriptListEffects) {
        guard word.isWholeSubstitution, let substitution = word.substitutions.first else { return }
        let inner = substitution.list.commands.compactMap { ScriptInvocation.resolve($0, dialect: dialect) }
        if inner.contains(where: Self.isDownloader) { effects.add(.downloadAndRun) }
        if inner.contains(where: Self.isDecoder) { effects.add(.decodeAndRun) }
    }
}
