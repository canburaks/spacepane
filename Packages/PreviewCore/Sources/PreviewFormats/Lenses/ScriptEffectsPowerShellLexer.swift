import Foundation
import PreviewContracts

/// Reads PowerShell source into command lists. Strings are single words (a double-quoted string keeps its
/// `$( )` sub-expressions as substitutions), `#` and `<# #>` comments are dropped, a backtick continues
/// a line, and a line break inside parentheses or after `|` does not end the statement. Parentheses and
/// braces separate commands, so `iex (irm $url)` reads as two commands in one statement.
struct PowerShellLexer {
    static let maximumDepth = 6
    private static let maximumStatementLines = 50
    private static let checkpointInterval = 256

    private let bytes: UnsafeBufferPointer<UInt8>
    private let end: Int
    private let context: RequestContext
    private(set) var position = 0
    private(set) var line: Int
    private var checkpointCountdown = PowerShellLexer.checkpointInterval
    private var aborted = false

    init(bytes: UnsafeBufferPointer<UInt8>, line: Int = 1, context: RequestContext) {
        self.bytes = bytes
        self.end = bytes.count
        self.line = line
        self.context = context
    }

    mutating func nextList() throws -> ScriptCommandList? {
        while position < end {
            var list = ScriptCommandList(line: line)
            try parseStatement(&list, depth: 0, closer: nil)
            aborted = false
            if !list.commands.isEmpty { return list }
        }
        return nil
    }

    private mutating func parseStatement(_ list: inout ScriptCommandList, depth: Int, closer: UInt8?) throws {
        var command = ScriptCommand()
        var groups = 0
        let firstLine = line
        while position < end, !aborted {
            let byte = bytes[position]
            switch byte {
            case 0x20, 0x09, 0x0B, 0x0C:
                position += 1
            case ScriptBytes.cutMarker:
                position += 1
                aborted = true
            case 0x0A, 0x0D, 0xC2, 0xE2:
                guard ScriptBytes.breakLength(in: bytes, at: position) > 0 else {
                    try appendWord(to: &command, in: &list, depth: depth)
                    continue
                }
                let continues = command.words.isEmpty && (list.commands.last.map { $0.next != .sequence } ?? false)
                try consumeBreak()
                if depth == 0 {
                    // An open parenthesis keeps the statement going, for a bounded number of lines.
                    if groups > 0, line - firstLine < Self.maximumStatementLines { continue }
                    if !continues {
                        Self.commit(&command, to: &list, as: .sequence)
                        return
                    }
                } else {
                    Self.commit(&command, to: &list, as: .sequence)
                }
            case 0x23: // #
                skipLineComment()
            case 0x3C where peek(1) == 0x23: // <# ... #>
                try skipBlockComment()
            case 0x60 where ScriptBytes.breakLength(in: bytes, at: position + 1) > 0: // a backtick continues the line
                position += 1
                try consumeBreak()
            case 0x3B: // ;
                position += 1
                Self.commit(&command, to: &list, as: .sequence)
            case 0x7C: // | ||
                let isOr = peek(1) == 0x7C
                position += isOr ? 2 : 1
                Self.commit(&command, to: &list, as: isOr ? .or : .pipe)
            case 0x26 where peek(1) == 0x26: // &&
                position += 2
                Self.commit(&command, to: &list, as: .and)
            case 0x28: // (
                position += 1
                groups += 1
                Self.commit(&command, to: &list, as: .sequence)
            case 0x29: // )
                position += 1
                Self.commit(&command, to: &list, as: .sequence)
                if groups > 0 { groups -= 1 } else if closer == 0x29 { return }
            case 0x7B, 0x7D: // { }
                position += 1
                Self.commit(&command, to: &list, as: .sequence)
            case 0x3E: // >
                try parseRedirect(into: &command, depth: depth)
            default:
                try appendWord(to: &command, in: &list, depth: depth)
            }
        }
        Self.commit(&command, to: &list, as: .sequence)
    }

    private static func commit(_ command: inout ScriptCommand, to list: inout ScriptCommandList, as next: ScriptOperator) {
        guard !command.words.isEmpty || !command.redirects.isEmpty else { return }
        command.next = next
        list.commands.append(command)
        command = ScriptCommand()
    }

    private mutating func appendWord(to command: inout ScriptCommand, in list: inout ScriptCommandList, depth: Int) throws {
        if list.commands.isEmpty, command.words.isEmpty, command.redirects.isEmpty { list.line = line }
        let start = position
        guard let word = try parseWord(depth: depth) else {
            if position == start { position += 1 }
            return
        }
        // In `2>&1` the number names a stream.
        if !word.text.isEmpty, position < end, bytes[position] == 0x3E, word.text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { return }
        command.words.append(word)
    }

    private mutating func parseRedirect(into command: inout ScriptCommand, depth: Int) throws {
        let isAppend = peek(1) == 0x3E
        position += isAppend ? 2 : 1
        if position < end, bytes[position] == 0x26 { position += 1 }
        while position < end, bytes[position] == 0x20 || bytes[position] == 0x09 { position += 1 }
        guard position < end, let target = try parseWord(depth: depth) else { return }
        command.redirects.append(ScriptRedirect(kind: isAppend ? .append : .output, target: target))
    }

    // MARK: Words

    private mutating func parseWord(depth: Int) throws -> ScriptWord? {
        var builder = ScriptWordBuilder()
        let start = position
        wordLoop: while position < end {
            let byte = bytes[position]
            switch byte {
            case 0x20, 0x09, 0x0B, 0x0C, ScriptBytes.cutMarker, 0x3B, 0x7C, 0x28, 0x29, 0x7B, 0x7D, 0x3E:
                break wordLoop
            case 0x26 where peek(1) == 0x26:
                break wordLoop
            case 0x0A, 0x0D, 0xC2, 0xE2:
                if ScriptBytes.breakLength(in: bytes, at: position) > 0 { break wordLoop }
                builder.literal(byte, unquoted: true)
                position += 1
            case 0x60: // the escape character; before a line break it continues the line
                position += 1
                if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                    try consumeBreak()
                } else if position < end, bytes[position] != ScriptBytes.cutMarker {
                    builder.literal(bytes[position], unquoted: false)
                    position += 1
                }
            case 0x27: // '
                position += 1
                builder.markQuoted()
                try copySingleQuoted(into: &builder)
            case 0x22: // "
                position += 1
                builder.markQuoted()
                try parseDoubleQuoted(into: &builder, depth: depth)
            case 0x40 where position == start && (peek(1) == 0x22 || peek(1) == 0x27)
                && ScriptBytes.breakLength(in: bytes, at: position + 2) > 0: // @" or @' ends the line: a here-string
                try copyHereString(into: &builder)
            default:
                builder.literal(byte, unquoted: true)
                position += 1
            }
        }
        return position > start ? builder.word() : nil
    }

    /// `'text'`, where `''` is a quote.
    private mutating func copySingleQuoted(into builder: inout ScriptWordBuilder) throws {
        while position < end {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { return }
            if byte == 0x27 {
                if peek(1) == 0x27 {
                    builder.literal(0x27, unquoted: false)
                    position += 2
                    continue
                }
                position += 1
                return
            }
            try copyQuotedByte(byte, into: &builder)
        }
    }

    /// `"text $(code) text"`, where `""` is a quote and the backtick escapes.
    private mutating func parseDoubleQuoted(into builder: inout ScriptWordBuilder, depth: Int) throws {
        while position < end {
            let byte = bytes[position]
            switch byte {
            case ScriptBytes.cutMarker:
                return
            case 0x22:
                if peek(1) == 0x22 {
                    builder.literal(0x22, unquoted: false)
                    position += 2
                } else {
                    position += 1
                    return
                }
            case 0x60:
                position += 1
                if position < end, bytes[position] != ScriptBytes.cutMarker {
                    if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                        try consumeBreak()
                    } else {
                        builder.literal(bytes[position], unquoted: false)
                        position += 1
                    }
                }
            case 0x24 where peek(1) == 0x28: // $( )
                builder.substitution(try parseSubexpression(depth: depth))
            default:
                try copyQuotedByte(byte, into: &builder)
            }
        }
    }

    private mutating func copyQuotedByte(_ byte: UInt8, into builder: inout ScriptWordBuilder) throws {
        let length = ScriptBytes.breakLength(in: bytes, at: position)
        if length > 0 {
            for offset in 0..<length { builder.literal(bytes[position + offset], unquoted: false) }
            try consumeBreak()
        } else {
            builder.literal(byte, unquoted: false)
            position += 1
        }
    }

    /// A here-string runs from the line after `@"` to a line that starts with `"@`.
    private mutating func copyHereString(into builder: inout ScriptWordBuilder) throws {
        let quote = bytes[position + 1]
        position += 2
        try consumeBreak()
        builder.markQuoted()
        while position < end {
            let atLineStart = position == 0 || ScriptBytes.breakLength(in: bytes, at: position - 1) > 0
                || (position >= 2 && ScriptBytes.breakLength(in: bytes, at: position - 2) > 0)
            if atLineStart, bytes[position] == quote, peek(1) == 0x40 {
                position += 2
                return
            }
            if bytes[position] == ScriptBytes.cutMarker { return }
            try copyQuotedByte(bytes[position], into: &builder)
        }
    }

    private mutating func parseSubexpression(depth: Int) throws -> ScriptSubstitution? {
        guard depth < Self.maximumDepth else {
            try skipParenthesized()
            return nil
        }
        position += 2
        var inner = ScriptCommandList(line: line)
        try parseStatement(&inner, depth: depth + 1, closer: 0x29)
        return ScriptSubstitution(list: inner, isProcess: false)
    }

    private mutating func skipParenthesized() throws {
        position += 2
        var nesting = 1
        while position < end, nesting > 0 {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { return }
            if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                try consumeBreak()
                continue
            }
            if byte == 0x28 { nesting += 1 } else if byte == 0x29 { nesting -= 1 }
            position += 1
        }
    }

    // MARK: Comments and cursor

    private mutating func skipLineComment() {
        while position < end, ScriptBytes.breakLength(in: bytes, at: position) == 0, bytes[position] != ScriptBytes.cutMarker {
            position += 1
        }
    }

    private mutating func skipBlockComment() throws {
        position += 2
        while position < end {
            if bytes[position] == ScriptBytes.cutMarker { return }
            if bytes[position] == 0x23, peek(1) == 0x3E {
                position += 2
                return
            }
            if ScriptBytes.breakLength(in: bytes, at: position) > 0 { try consumeBreak() } else { position += 1 }
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
