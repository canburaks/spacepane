import Foundation
import PreviewContracts

/// Reads batch (`.bat`, `.cmd`) source into command lists, one per logical line. `rem` and `::` lines are
/// dropped, a caret at the end of a line continues it, `&`, `&&`, `||` and `|` separate commands, and
/// double quotes group words. Nothing is expanded: `%VAR%` stays text.
struct BatchLexer {
    private static let checkpointInterval = 256

    private let bytes: UnsafeBufferPointer<UInt8>
    private let end: Int
    private let context: RequestContext
    private(set) var position = 0
    private(set) var line: Int
    private var checkpointCountdown = BatchLexer.checkpointInterval

    init(bytes: UnsafeBufferPointer<UInt8>, line: Int = 1, context: RequestContext) {
        self.bytes = bytes
        self.end = bytes.count
        self.line = line
        self.context = context
    }

    mutating func nextList() throws -> ScriptCommandList? {
        while position < end {
            let startLine = line
            let text = try readLogicalLine()
            if let list = Self.commands(in: text, line: startLine) { return list }
        }
        return nil
    }

    /// The text of one logical line: physical lines joined at a trailing caret.
    private mutating func readLogicalLine() throws -> [UInt8] {
        var text: [UInt8] = []
        while position < end {
            let lineStart = position
            while position < end, ScriptBytes.breakLength(in: bytes, at: position) == 0 { position += 1 }
            let lineEnd = position
            if position < end { try consumeBreak() }
            var contentEnd = lineEnd
            while contentEnd > lineStart, bytes[contentEnd - 1] == 0x20 || bytes[contentEnd - 1] == 0x09 { contentEnd -= 1 }
            let continues = contentEnd > lineStart && bytes[contentEnd - 1] == 0x5E && text.count < ScriptWordBuilder.limit
            text.append(contentsOf: bytes[lineStart..<(continues ? contentEnd - 1 : lineEnd)])
            if !continues { break }
        }
        return text
    }

    private static func commands(in text: [UInt8], line: Int) -> ScriptCommandList? {
        var list = ScriptCommandList(line: line)
        var command = ScriptCommand()
        var builder = ScriptWordBuilder()
        var inWord = false
        var inQuote = false
        var redirect: ScriptRedirectKind?
        var index = 0

        func finishWord() {
            guard inWord else { return }
            let word = builder.word()
            if let kind = redirect {
                command.redirects.append(ScriptRedirect(kind: kind, target: word))
                redirect = nil
            } else {
                command.words.append(word)
            }
            builder = ScriptWordBuilder()
            inWord = false
        }
        func finishCommand(_ next: ScriptOperator) {
            finishWord()
            guard !command.words.isEmpty || !command.redirects.isEmpty else { return }
            command.next = next
            list.commands.append(command)
            command = ScriptCommand()
        }

        while index < text.count {
            let byte = text[index]
            if inQuote {
                if byte == 0x22 { inQuote = false } else { builder.literal(byte, unquoted: false) }
                index += 1
                continue
            }
            switch byte {
            case 0x22:
                inQuote = true
                inWord = true
                builder.markQuoted()
            case 0x20, 0x09:
                finishWord()
            case 0x5E: // ^ escapes the next character
                index += 1
                if index < text.count {
                    builder.literal(text[index], unquoted: false)
                    inWord = true
                }
            case 0x28 where !inWord: // ( starts a block
                finishCommand(.sequence)
            case 0x29 where Self.endsWord(text, after: index): // ) ends a block; `%ProgramFiles(x86)%` does not
                finishCommand(.sequence)
            case 0x26: // & &&
                let isAnd = index + 1 < text.count && text[index + 1] == 0x26
                finishCommand(isAnd ? .and : .sequence)
                if isAnd { index += 1 }
            case 0x7C: // | ||
                let isOr = index + 1 < text.count && text[index + 1] == 0x7C
                finishCommand(isOr ? .or : .pipe)
                if isOr { index += 1 }
            case 0x3E, 0x3C: // > >> <
                // A number before the operator names a handle, as in `2>nul`.
                if inWord, builder.text.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
                    builder = ScriptWordBuilder()
                    inWord = false
                } else {
                    finishWord()
                }
                var kind = byte == 0x3C ? ScriptRedirectKind.input : .output
                if byte == 0x3E, index + 1 < text.count, text[index + 1] == 0x3E {
                    kind = .append
                    index += 1
                } else if byte == 0x3E, index + 1 < text.count, text[index + 1] == 0x26 {
                    kind = .other
                    index += 1
                }
                redirect = kind
            default:
                builder.literal(byte, unquoted: true)
                inWord = true
            }
            index += 1
        }
        finishCommand(.sequence)
        guard let first = list.commands.first?.words.first else { return list.commands.isEmpty ? nil : list }
        let name = first.text.lowercased()
        // Comments and labels: `rem ...`, `@rem ...`, `:: ...` and `:label`.
        if name == "rem" || name == "@rem" || name.hasPrefix("::") || name.hasPrefix(":") || name.hasPrefix("rem.") { return nil }
        return list
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

    /// Whether a `)` closes a block: it ends the line, the word or the command. `%ProgramFiles(x86)%` is a name.
    private static func endsWord(_ text: [UInt8], after index: Int) -> Bool {
        guard index + 1 < text.count else { return true }
        return [0x20, 0x09, 0x26, 0x7C, 0x29].contains(text[index + 1])
    }
}
