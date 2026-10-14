import Foundation
import PreviewContracts

/// Splits AppleScript source into statements of words, strings and symbols. Comments (`--`, `#` and
/// nested `(* *)`) are dropped, a `¬` continues the statement on the next line, and a string is one token
/// whatever it holds, so a phrase inside a string is never mistaken for code.
struct AppleScriptScanner {
    enum Token: Equatable {
        case word(String)
        case string(String)
        case symbol(UInt8)
    }

    struct Statement {
        var line: Int
        var tokens: [Token]
    }

    private static let checkpointInterval = 256
    private static let stringLimit = 64 * 1024

    private let bytes: UnsafeBufferPointer<UInt8>
    private let end: Int
    private let context: RequestContext
    private(set) var position = 0
    private(set) var line: Int
    private var checkpointCountdown = AppleScriptScanner.checkpointInterval

    init(bytes: UnsafeBufferPointer<UInt8>, line: Int = 1, context: RequestContext) {
        self.bytes = bytes
        self.end = bytes.count
        self.line = line
        self.context = context
    }

    mutating func nextStatement() throws -> Statement? {
        var tokens: [Token] = []
        var statementLine = line
        var continued = false
        while position < end {
            let byte = bytes[position]
            switch byte {
            case 0x20, 0x09, 0x0B, 0x0C, ScriptBytes.cutMarker:
                position += 1
            case 0x0A, 0x0D, 0xC2, 0xE2:
                if byte == 0xC2, position + 1 < end, bytes[position + 1] == 0xAC {
                    position += 2 // ¬
                    continued = true
                } else if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                    try consumeBreak()
                    if continued { continued = false; continue }
                    if !tokens.isEmpty { return Statement(line: statementLine, tokens: tokens) }
                    statementLine = line
                } else {
                    position += 1
                }
            case 0x2D where peek(1) == 0x2D, 0x23: // -- and # comments
                skipLineComment()
            case 0x28 where peek(1) == 0x2A: // (* ... *)
                try skipBlockComment()
            case 0x22:
                if tokens.isEmpty { statementLine = line }
                tokens.append(.string(try readString()))
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F:
                if tokens.isEmpty { statementLine = line }
                tokens.append(.word(readWord()))
            default:
                if tokens.isEmpty { statementLine = line }
                tokens.append(.symbol(byte))
                position += 1
            }
        }
        return tokens.isEmpty ? nil : Statement(line: statementLine, tokens: tokens)
    }

    private mutating func readWord() -> String {
        let start = position
        while position < end {
            let byte = bytes[position]
            guard (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F else { break }
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self).lowercased()
    }

    /// A string literal with its backslash escapes resolved just far enough to keep the quote and the
    /// backslash; `\n` and its kind stay as the character after the backslash.
    private mutating func readString() throws -> String {
        position += 1
        var text: [UInt8] = []
        while position < end {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { break }
            if byte == 0x22 {
                position += 1
                break
            }
            if byte == 0x5C, position + 1 < end, bytes[position + 1] != ScriptBytes.cutMarker {
                if ScriptBytes.breakLength(in: bytes, at: position + 1) == 0 {
                    if text.count < Self.stringLimit { text.append(bytes[position + 1]) }
                    position += 2
                    continue
                }
            }
            let length = ScriptBytes.breakLength(in: bytes, at: position)
            if length > 0 {
                if text.count < Self.stringLimit { text.append(0x0A) }
                try consumeBreak()
            } else {
                if text.count < Self.stringLimit { text.append(byte) }
                position += 1
            }
        }
        return String(decoding: text, as: UTF8.self)
    }

    private mutating func skipLineComment() {
        while position < end, ScriptBytes.breakLength(in: bytes, at: position) == 0, bytes[position] != ScriptBytes.cutMarker {
            position += 1
        }
    }

    private mutating func skipBlockComment() throws {
        var nesting = 0
        while position < end {
            if bytes[position] == ScriptBytes.cutMarker { return }
            if bytes[position] == 0x28, peek(1) == 0x2A {
                nesting += 1
                position += 2
            } else if bytes[position] == 0x2A, peek(1) == 0x29 {
                nesting -= 1
                position += 2
                if nesting == 0 { return }
            } else if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                try consumeBreak()
            } else {
                position += 1
            }
        }
    }

    private func peek(_ offset: Int) -> UInt8? {
        position + offset < end ? bytes[position + offset] : nil
    }

    private mutating func consumeBreak() throws {
        position += ScriptBytes.breakLength(in: bytes, at: position)
        line += 1
        checkpointCountdown -= 1
        if checkpointCountdown == 0 {
            checkpointCountdown = Self.checkpointInterval
            try context.checkpoint()
        }
    }
}

extension ScriptEffectsAnalyzer {
    /// A whole AppleScript (a file or a here-document), tallied statement by statement against its own lines.
    func analyzeAppleScript(_ body: UnsafeBufferPointer<UInt8>, startLine: Int, depth: Int) throws {
        guard depth <= Self.maximumNesting else { return }
        var scanner = AppleScriptScanner(bytes: body, line: startLine, context: context)
        while let statement = try scanner.nextStatement() {
            var effects = ScriptListEffects()
            try evaluate(statement, depth: depth, line: statement.line, effects: &effects)
            flush(effects, line: statement.line)
        }
    }

    /// AppleScript handed over as text (`osascript -e`), whose findings belong to the line of the command.
    func evaluateAppleScript(_ text: String, depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        guard depth <= Self.maximumNesting, !text.isEmpty else { return }
        let nested = Array(text.utf8)
        try nested.withUnsafeBufferPointer { buffer in
            var scanner = AppleScriptScanner(bytes: buffer, context: context)
            while let statement = try scanner.nextStatement() {
                try evaluate(statement, depth: depth, line: line, effects: &effects)
            }
        }
    }

    private func evaluate(_ statement: AppleScriptScanner.Statement, depth: Int, line: Int, effects: inout ScriptListEffects) throws {
        let tokens = statement.tokens
        if Self.contains(["with", "administrator", "privileges"], in: tokens) { effects.add(.elevates) }
        if Self.contains(["with", "hidden", "answer"], in: tokens) { effects.add(.asksForPassword) }
        if let login = Self.index(of: ["login", "item"], in: tokens), tokens[max(0, login - 2)..<login].contains(.word("make")) {
            effects.add(.persistence)
        }
        // The string given to `do shell script` (or Terminal's `do script`) is shell code.
        if let shell = Self.index(of: ["do", "shell", "script"], in: tokens) {
            try analyzeText(Self.shellText(in: tokens, after: shell + 3), dialect: .shell, depth: depth + 1, line: line, effects: &effects)
        } else if let script = Self.index(of: ["do", "script"], in: tokens) {
            try analyzeText(Self.shellText(in: tokens, after: script + 2), dialect: .shell, depth: depth + 1, line: line, effects: &effects)
        }
    }

    /// The shell text an expression builds: its string literals joined, with `$x` where a value is spliced in.
    private static func shellText(in tokens: [AppleScriptScanner.Token], after start: Int) -> String {
        let stoppers: Set<String> = ["with", "without", "user", "password", "altering", "administrator"]
        var text = ""
        var spliced = false
        for token in tokens[min(start, tokens.count)...] {
            switch token {
            case .string(let literal):
                text += literal
                spliced = false
            case .word(let word):
                if stoppers.contains(word) { return text }
                if !spliced { text += "$x" }
                spliced = true
            case .symbol:
                break
            }
        }
        return text
    }

    private static func contains(_ words: [String], in tokens: [AppleScriptScanner.Token]) -> Bool {
        index(of: words, in: tokens) != nil
    }

    private static func index(of words: [String], in tokens: [AppleScriptScanner.Token]) -> Int? {
        guard tokens.count >= words.count else { return nil }
        for start in 0...(tokens.count - words.count)
        where words.indices.allSatisfy({ tokens[start + $0] == .word(words[$0]) }) {
            return start
        }
        return nil
    }
}
