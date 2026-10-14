import Foundation
import PreviewContracts

/// Reads POSIX-shell and fish source into command lists without running or expanding anything.
///
/// The lexer knows just enough shell to tell a command from text: quoting, escapes, comments, operators,
/// redirections, here-documents, line continuations and the three substitution forms (`$( )`, backticks
/// and `<( )`). Everything else stays a plain word. It is linear in the text, never recurses past
/// `maximumDepth`, and treats the cut marker (`ScriptBytes.cutMarker`) as the end of whatever was open,
/// so one long line cannot swallow the rest of the file.
struct ShellLexer {
    /// Substitutions nested deeper than this are skipped instead of read.
    static let maximumDepth = 6
    private static let checkpointInterval = 256

    private let bytes: UnsafeBufferPointer<UInt8>
    private let end: Int
    private let isFish: Bool
    private let allowsHeredocs: Bool
    private let context: RequestContext
    private(set) var position = 0
    private(set) var line: Int
    private var checkpointCountdown = ShellLexer.checkpointInterval
    private var aborted = false
    private var pending: [PendingHeredoc] = []
    /// Inside `[[ ... ]]`, where parentheses and bars belong to a pattern.
    private var inTest = false
    /// Open `case` statements, and whether the next words are a clause's patterns, which name nothing to run.
    private var caseDepth = 0
    private var inCasePatterns = false
    private var patternWords = 0

    private struct PendingHeredoc {
        var delimiter: [UInt8]
        var stripsTabs: Bool
    }

    init(bytes: UnsafeBufferPointer<UInt8>, line: Int = 1, isFish: Bool, allowsHeredocs: Bool, context: RequestContext) {
        self.bytes = bytes
        self.end = bytes.count
        self.line = line
        self.isFish = isFish
        self.allowsHeredocs = allowsHeredocs
        self.context = context
    }

    /// The next top-level list, or `nil` at the end of the text.
    mutating func nextList() throws -> ScriptCommandList? {
        while position < end {
            var list = ScriptCommandList(line: line)
            try parseList(&list, depth: 0, closer: nil)
            aborted = false
            if !list.commands.isEmpty { return list }
        }
        return nil
    }

    /// Everything in the text as one list, line breaks acting as `;`. Used for text inside a substitution.
    mutating func wholeList(depth: Int) throws -> ScriptCommandList {
        var list = ScriptCommandList(line: line)
        try parseList(&list, depth: max(depth, 1), closer: nil)
        return list
    }

    // MARK: Lists

    private mutating func parseList(_ list: inout ScriptCommandList, depth: Int, closer: UInt8?) throws {
        var command = ScriptCommand()
        var groups = 0
        while position < end, !aborted {
            if inCasePatterns {
                try skipCasePattern()
                continue
            }
            let byte = bytes[position]
            if inTest, byte == 0x28 || byte == 0x29 || byte == 0x7C || byte == 0x26 || byte == 0x3C || byte == 0x3E {
                try appendWord(to: &command, in: &list, depth: depth)
                continue
            }
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
                // A line break after `|`, `&&` or `||` continues the list.
                let continues = command.words.isEmpty && command.redirects.isEmpty
                    && (list.commands.last.map { $0.next != .sequence } ?? false)
                try consumeBreak()
                inTest = false
                if !continues { Self.commit(&command, to: &list, as: .sequence) }
                // The bodies of here-documents opened on this line start on the next one.
                if !pending.isEmpty { try readHeredocBodies(into: &list) }
                if depth == 0, !continues { return }
            case 0x23: // #
                skipComment()
            case 0x3B: // ; ;; ;&
                position += 1
                var endsClause = false
                if position < end, bytes[position] == 0x3B || bytes[position] == 0x26 {
                    position += 1
                    // The end of a clause: the next words are the patterns of another.
                    if caseDepth > 0 { (inCasePatterns, patternWords, endsClause) = (true, 0, true) }
                }
                Self.commit(&command, to: &list, as: .sequence)
                // A clause is a command list of its own, numbered by the line it starts on.
                if endsClause, depth == 0 { return }
            case 0x26: // & &&
                if peek(1) == 0x26 {
                    position += 2
                    Self.commit(&command, to: &list, as: .and)
                } else if peek(1) == 0x3E {
                    try parseRedirect(into: &command, depth: depth)
                } else {
                    position += 1
                    Self.commit(&command, to: &list, as: .sequence)
                }
            case 0x7C: // | || |&
                let operatorLength = peek(1) == 0x7C || peek(1) == 0x26 ? 2 : 1
                let kind: ScriptOperator = peek(1) == 0x7C ? .or : .pipe
                position += operatorLength
                Self.commit(&command, to: &list, as: kind)
            case 0x28: // (
                if isFish {
                    try appendWord(to: &command, in: &list, depth: depth)
                } else if command.words.isEmpty, peek(1) == 0x28 {
                    try skipParenthesized(prefix: 2, nesting: 2)
                } else if position > 0, bytes[position - 1] == 0x3D, !command.words.isEmpty {
                    try parseArrayLiteral(into: &command, depth: depth)
                } else if command.words.count == 1, closesImmediately() {
                    // `name() { ...; }` defines a function; its name is not a command.
                    command = ScriptCommand()
                } else {
                    position += 1
                    groups += 1
                    Self.commit(&command, to: &list, as: .sequence)
                }
            case 0x29: // )
                position += 1
                Self.commit(&command, to: &list, as: .sequence)
                if groups > 0 { groups -= 1 } else if closer == 0x29 { return }
            case 0x3C, 0x3E: // < >
                if peek(1) == 0x28 {
                    try appendWord(to: &command, in: &list, depth: depth)
                } else {
                    try parseRedirect(into: &command, depth: depth)
                }
            case 0x5C: // a backslash before a line break continues the line
                if ScriptBytes.breakLength(in: bytes, at: position + 1) > 0 {
                    position += 1
                    try consumeBreak()
                } else {
                    try appendWord(to: &command, in: &list, depth: depth)
                }
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
        // In `2>file` the number names a descriptor and is not an argument.
        if !word.text.isEmpty, word.substitutions.isEmpty, position < end, bytes[position] == 0x3E || bytes[position] == 0x3C,
           word.text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
            return
        }
        command.words.append(word)
        noteStructure(of: word, in: &command)
    }

    /// `[[` opens a test whose patterns are not commands; `case X in` and `esac` frame clauses whose
    /// patterns are not commands either.
    private mutating func noteStructure(of word: ScriptWord, in command: inout ScriptCommand) {
        guard !isFish else { return }
        let leading = command.words.dropLast()
        if word.text == "[[", leading.allSatisfy({ ScriptInvocation.isShellKeyword($0.text) }) { inTest = true }
        if word.text == "]]" { inTest = false }
        if leading.isEmpty, word.text == "esac" { caseDepth = max(0, caseDepth - 1) }
        if word.text == "in", command.words.count == 3, command.words[0].text == "case" {
            command = ScriptCommand()
            caseDepth += 1
            (inCasePatterns, patternWords) = (true, 0)
        }
    }

    /// Skips one token of a case clause's patterns: `(a|b)`, `*.sh)`, or the closing `esac`.
    private mutating func skipCasePattern() throws {
        let byte = bytes[position]
        switch byte {
        case 0x20, 0x09, 0x0B, 0x0C, 0x28, 0x7C:
            position += 1
        case 0x29:
            position += 1
            inCasePatterns = false
        case ScriptBytes.cutMarker:
            inCasePatterns = false
        case 0x23:
            skipComment()
        default:
            if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                try consumeBreak()
                return
            }
            let start = position
            if let word = try parseWord(depth: 0), word.text == "esac" {
                inCasePatterns = false
                caseDepth = max(0, caseDepth - 1)
            } else if position == start {
                position += 1
            }
            patternWords += 1
            // A case that never closes must not swallow the rest of the script.
            if patternWords > 64 { inCasePatterns = false }
        }
    }

    /// `name=(a b c)`: the elements are data, not commands. They are folded into the assignment word.
    private mutating func parseArrayLiteral(into command: inout ScriptCommand, depth: Int) throws {
        position += 1
        var assignment = command.words.removeLast()
        var elements = 0
        arrayLoop: while position < end, elements < 4_096 {
            let byte = bytes[position]
            switch byte {
            case ScriptBytes.cutMarker:
                break arrayLoop
            case 0x29:
                position += 1
                break arrayLoop
            case 0x20, 0x09, 0x0B, 0x0C:
                position += 1
            case 0x23:
                skipComment()
            default:
                if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                    try consumeBreak()
                    continue
                }
                let start = position
                if let element = try parseWord(depth: depth) {
                    if assignment.text.utf8.count < ScriptWordBuilder.limit { assignment.text += " " + element.text }
                    assignment.substitutions += element.substitutions
                    assignment.isWholeSubstitution = false
                    elements += 1
                } else if position == start {
                    position += 1
                }
            }
        }
        command.words.append(assignment)
    }

    /// Whether the text after a `(` is `)`, as in a function definition `name() {`; consumes both if so.
    private mutating func closesImmediately() -> Bool {
        var index = position + 1
        while index < end, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        guard index < end, bytes[index] == 0x29 else { return false }
        position = index + 1
        return true
    }

    // MARK: Redirections and here-documents

    private mutating func parseRedirect(into command: inout ScriptCommand, depth: Int) throws {
        var kind = ScriptRedirectKind.output
        var length = 1
        switch bytes[position] {
        case 0x26: // &> and &>>
            if peek(2) == 0x3E { kind = .append; length = 3 } else { length = 2 }
        case 0x3E:
            switch peek(1) {
            case 0x3E: kind = .append; length = 2
            case 0x26: kind = .other; length = 2
            case 0x7C: length = 2
            default: break
            }
        default:
            kind = .input
            switch peek(1) {
            case 0x3C:
                if peek(2) == 0x3C { kind = .hereString; length = 3 }
                else if peek(2) == 0x2D { kind = .hereDocument; length = 3 }
                else { kind = .hereDocument; length = 2 }
            case 0x26, 0x3E: kind = .other; length = 2
            default: break
            }
        }
        let stripsTabs = kind == .hereDocument && length == 3
        position += length
        while position < end, bytes[position] == 0x20 || bytes[position] == 0x09 { position += 1 }
        guard position < end, let target = try parseWord(depth: depth) else { return }
        var redirect = ScriptRedirect(kind: kind, target: target)
        if kind == .hereDocument {
            // A delimiter that starts with a digit is arithmetic (`1 << 2`), not a here-document.
            let delimiter = Array(target.text.utf8)
            if allowsHeredocs, let first = delimiter.first, first < 0x30 || first > 0x39 {
                pending.append(PendingHeredoc(delimiter: delimiter, stripsTabs: stripsTabs))
            } else {
                redirect.kind = .other
            }
        }
        command.redirects.append(redirect)
    }

    /// Reads the bodies of the here-documents opened on the line that just ended and attaches them, in
    /// order, to the redirections that still lack one.
    private mutating func readHeredocBodies(into list: inout ScriptCommandList) throws {
        var bodies: [(Range<Int>, Int)] = []
        for heredoc in pending {
            let bodyStart = position
            let bodyLine = line
            var bodyEnd = end
            readLines: while position < end {
                let lineStart = position
                var lineEnd = position
                while lineEnd < end, ScriptBytes.breakLength(in: bytes, at: lineEnd) == 0 { lineEnd += 1 }
                var content = lineStart
                if heredoc.stripsTabs { while content < lineEnd, bytes[content] == 0x09 { content += 1 } }
                position = lineEnd
                let terminated = lineEnd - content == heredoc.delimiter.count && heredoc.delimiter.elementsEqual(bytes[content..<lineEnd])
                if position < end { try consumeBreak() }
                if terminated { bodyEnd = lineStart; break readLines }
            }
            bodies.append((bodyStart..<max(bodyStart, bodyEnd), bodyLine))
        }
        pending.removeAll(keepingCapacity: true)
        var next = 0
        for commandIndex in list.commands.indices {
            for redirectIndex in list.commands[commandIndex].redirects.indices where next < bodies.count {
                let redirect = list.commands[commandIndex].redirects[redirectIndex]
                guard redirect.kind == .hereDocument, redirect.body == nil else { continue }
                list.commands[commandIndex].redirects[redirectIndex].body = bodies[next].0
                list.commands[commandIndex].redirects[redirectIndex].bodyLine = bodies[next].1
                next += 1
            }
        }
    }

    // MARK: Words

    private mutating func parseWord(depth: Int) throws -> ScriptWord? {
        var builder = ScriptWordBuilder()
        let start = position
        wordLoop: while position < end {
            let byte = bytes[position]
            if inTest, byte == 0x28 || byte == 0x29 || byte == 0x7C || byte == 0x26 || byte == 0x3C || byte == 0x3E {
                builder.literal(byte, unquoted: true)
                position += 1
                continue
            }
            switch byte {
            case 0x20, 0x09, 0x0B, 0x0C, ScriptBytes.cutMarker, 0x3B, 0x26, 0x7C, 0x29:
                break wordLoop
            case 0x28:
                guard isFish else { break wordLoop }
                builder.substitution(try parseSubstitution(prefix: 1, isProcess: false, depth: depth))
            case 0x3C, 0x3E:
                guard position == start, peek(1) == 0x28 else { break wordLoop }
                builder.substitution(try parseSubstitution(prefix: 2, isProcess: true, depth: depth))
            case 0x0A, 0x0D, 0xC2, 0xE2:
                if ScriptBytes.breakLength(in: bytes, at: position) > 0 { break wordLoop }
                builder.literal(byte, unquoted: true)
                position += 1
            case 0x5C: // backslash
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
                try copySingleQuoted(into: &builder, ansi: isFish)
            case 0x22: // "
                position += 1
                builder.markQuoted()
                try parseDoubleQuoted(into: &builder, depth: depth)
            case 0x24: // $
                try parseDollar(into: &builder, depth: depth, quoted: false)
            case 0x60: // `
                builder.substitution(try parseBackticks(depth: depth))
            default:
                builder.literal(byte, unquoted: true)
                position += 1
            }
        }
        return position > start ? builder.word() : nil
    }

    private mutating func parseDoubleQuoted(into builder: inout ScriptWordBuilder, depth: Int) throws {
        while position < end {
            let byte = bytes[position]
            switch byte {
            case 0x22:
                position += 1
                return
            case ScriptBytes.cutMarker:
                return
            case 0x5C:
                let next = peek(1)
                if ScriptBytes.breakLength(in: bytes, at: position + 1) > 0 {
                    position += 1
                    try consumeBreak()
                } else if let next, next == 0x24 || next == 0x60 || next == 0x22 || next == 0x5C {
                    builder.literal(next, unquoted: false)
                    position += 2
                } else {
                    builder.literal(byte, unquoted: false)
                    position += 1
                }
            case 0x24:
                try parseDollar(into: &builder, depth: depth, quoted: true)
            case 0x60:
                builder.substitution(try parseBackticks(depth: depth))
            default:
                let length = ScriptBytes.breakLength(in: bytes, at: position)
                if length > 0 {
                    for offset in 0..<length { builder.literal(bytes[position + offset], unquoted: false) }
                    try consumeBreak()
                } else {
                    builder.literal(byte, unquoted: false)
                    position += 1
                }
            }
        }
    }

    /// Copies single-quoted text; the opening quote is already consumed. In `$'...'`, and in fish, a backslash escapes.
    private mutating func copySingleQuoted(into builder: inout ScriptWordBuilder, ansi: Bool) throws {
        while position < end {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { return }
            if byte == 0x27 {
                position += 1
                return
            }
            if ansi, byte == 0x5C, position + 1 < end {
                builder.literal(byte, unquoted: false)
                builder.literal(bytes[position + 1], unquoted: false)
                position += 2
                continue
            }
            let length = ScriptBytes.breakLength(in: bytes, at: position)
            if length > 0 {
                for offset in 0..<length { builder.literal(bytes[position + offset], unquoted: false) }
                try consumeBreak()
            } else {
                builder.literal(byte, unquoted: false)
                position += 1
            }
        }
    }

    private mutating func parseDollar(into builder: inout ScriptWordBuilder, depth: Int, quoted: Bool) throws {
        switch peek(1) {
        case 0x28:
            if peek(2) == 0x28 {
                try skipParenthesized(prefix: 3, nesting: 2)
                builder.literal(0x30, unquoted: false)
            } else {
                builder.substitution(try parseSubstitution(prefix: 2, isProcess: false, depth: depth))
            }
        case 0x7B:
            try copyBraced(into: &builder)
        case 0x27 where !quoted:
            position += 2
            try copySingleQuoted(into: &builder, ansi: true)
        case 0x22 where !quoted:
            position += 2
            try parseDoubleQuoted(into: &builder, depth: depth)
        default:
            builder.literal(0x24, unquoted: !quoted)
            position += 1
        }
    }

    /// Parameter expansion `${...}` is kept as written, so a path such as `${HOME}/.ssh/id_rsa` still reads as one.
    private mutating func copyBraced(into builder: inout ScriptWordBuilder) throws {
        var nesting = 0
        while position < end {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { return }
            let length = ScriptBytes.breakLength(in: bytes, at: position)
            if length > 0 {
                builder.literal(bytes[position], unquoted: false)
                try consumeBreak()
                continue
            }
            builder.literal(byte, unquoted: false)
            position += 1
            if byte == 0x7B {
                nesting += 1
            } else if byte == 0x7D {
                nesting -= 1
                if nesting == 0 { return }
            }
        }
    }

    // MARK: Substitutions

    /// `$( )`, `<( )`, `>( )` and, in fish, a bare `( )`. The prefix is consumed, then commands are read
    /// to the matching parenthesis.
    private mutating func parseSubstitution(prefix: Int, isProcess: Bool, depth: Int) throws -> ScriptSubstitution? {
        guard depth < Self.maximumDepth else {
            try skipParenthesized(prefix: prefix, nesting: 1)
            return nil
        }
        position += prefix
        var inner = ScriptCommandList(line: line)
        try parseList(&inner, depth: depth + 1, closer: 0x29)
        return ScriptSubstitution(list: inner, isProcess: isProcess)
    }

    /// Backticks. The text between them is unescaped (`\`` `\\` `\$`) and read by a nested lexer.
    private mutating func parseBackticks(depth: Int) throws -> ScriptSubstitution? {
        let startLine = line
        var index = position + 1
        var inner: [UInt8] = []
        var breaks = 0
        while index < end {
            let byte = bytes[index]
            if byte == 0x60 || byte == ScriptBytes.cutMarker { break }
            let length = ScriptBytes.breakLength(in: bytes, at: index)
            if length > 0 {
                inner.append(contentsOf: bytes[index..<(index + length)])
                index += length
                breaks += 1
            } else if byte == 0x5C, index + 1 < end, bytes[index + 1] == 0x60 || bytes[index + 1] == 0x5C || bytes[index + 1] == 0x24 {
                inner.append(bytes[index + 1])
                index += 2
            } else {
                inner.append(byte)
                index += 1
            }
            if inner.count > ScriptWordBuilder.limit { break }
        }
        position = index < end && bytes[index] == 0x60 ? index + 1 : index
        line += breaks
        guard depth < Self.maximumDepth else { return nil }
        let list: ScriptCommandList = try inner.withUnsafeBufferPointer { buffer in
            var nested = ShellLexer(bytes: buffer, line: startLine, isFish: isFish, allowsHeredocs: false, context: context)
            return try nested.wholeList(depth: depth + 1)
        }
        return ScriptSubstitution(list: list, isProcess: false)
    }

    /// Skips to the parenthesis that closes `nesting` open ones, without reading what is inside.
    private mutating func skipParenthesized(prefix: Int, nesting initial: Int) throws {
        position += prefix
        var nesting = initial
        while position < end, nesting > 0 {
            let byte = bytes[position]
            if byte == ScriptBytes.cutMarker { return }
            if byte == 0x5C {
                position += 1
                if ScriptBytes.breakLength(in: bytes, at: position) > 0 { try consumeBreak() } else if position < end { position += 1 }
                continue
            }
            if ScriptBytes.breakLength(in: bytes, at: position) > 0 {
                try consumeBreak()
                continue
            }
            if byte == 0x28 { nesting += 1 } else if byte == 0x29 { nesting -= 1 }
            position += 1
        }
    }

    // MARK: Cursor

    private func peek(_ offset: Int) -> UInt8? {
        position + offset < end ? bytes[position + offset] : nil
    }

    private mutating func skipComment() {
        while position < end, ScriptBytes.breakLength(in: bytes, at: position) == 0, bytes[position] != ScriptBytes.cutMarker {
            position += 1
        }
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
