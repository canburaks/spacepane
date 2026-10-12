import PreviewContracts

/// Cheap lexical tones for one already concealed line. This is decoration, not a language
/// compiler: it never sees unredacted text, never parses across lines except an open block comment,
/// and falls back to a single ink for syntaxes without rules.
struct ThumbnailLexer {
    struct State: Equatable {
        var inBlockComment = false
    }

    private struct Rules {
        var lineComments: [[Unicode.Scalar]] = []
        var blockComments = false
        var strings = false
        var backticks = false
        var numbers = false
        var literals = false
        var keywords = false
        /// A bare identifier followed by `:` or `=` reads as a key.
        var keys = false
        /// A quoted string followed by `:` or `=` reads as a key.
        var quotedKeys = false
        var tags = false
        /// A line that starts with `[` is a section heading.
        var sections = false
    }

    private let syntax: TextSyntax
    private let rules: Rules?

    init(syntax: TextSyntax) {
        self.syntax = syntax
        rules = Self.rules(for: syntax)
    }

    private static func markers(_ values: String...) -> [[Unicode.Scalar]] { values.map { Array($0.unicodeScalars) } }

    private static func rules(for syntax: TextSyntax) -> Rules? {
        switch syntax {
        case .sourceCode:
            return Rules(lineComments: markers("//", "#", "--"), blockComments: true, strings: true, backticks: true,
                         numbers: true, literals: true, keywords: true)
        case .json:
            return Rules(strings: true, numbers: true, literals: true, quotedKeys: true)
        case .jsonWithComments:
            return Rules(lineComments: markers("//"), blockComments: true, strings: true, numbers: true,
                         literals: true, quotedKeys: true)
        case .yaml:
            return Rules(lineComments: markers("#"), strings: true, numbers: true, literals: true, keys: true, quotedKeys: true)
        case .toml:
            return Rules(lineComments: markers("#"), strings: true, numbers: true, literals: true, keys: true,
                         quotedKeys: true, sections: true)
        case .environment:
            return Rules(lineComments: markers("#"), strings: true, numbers: true, keys: true)
        case .ini:
            return Rules(lineComments: markers(";", "#"), strings: true, numbers: true, keys: true, sections: true)
        case .strings:
            return Rules(lineComments: markers("//"), blockComments: true, strings: true, quotedKeys: true)
        case .xml, .propertyList:
            return Rules(tags: true)
        case .latex, .bibtex:
            return Rules(lineComments: markers("%"))
        default:
            return nil
        }
    }

    private static let literalWords: Set<String> = ["true", "false", "null", "nil", "none", "yes", "no"]
    private static let keywordWords: Set<String> = [
        "let", "var", "func", "function", "class", "struct", "enum", "protocol", "extension", "import", "export",
        "public", "private", "internal", "static", "const", "async", "await", "actor", "throws", "throw", "try",
        "if", "else", "switch", "case", "default", "guard", "return", "break", "continue", "for", "while", "do",
        "in", "as", "is", "new", "def", "lambda", "with", "except", "finally", "raise", "from", "pass", "yield",
        "and", "or", "not", "fn", "impl", "trait", "use", "mut", "match", "pub", "mod", "package", "type",
        "interface", "defer", "int", "void", "char", "double", "float", "bool", "typedef", "include", "namespace",
        "template", "fi", "then", "done", "esac", "echo", "local", "select", "insert", "update", "delete", "create",
        "table", "where", "join", "end", "module", "require", "extends", "implements", "final", "override", "val", "fun"
    ]

    func runs(in line: [Unicode.Scalar], state: inout State) -> [ThumbnailRun] {
        guard !line.isEmpty else { return [] }
        let tones = tones(in: line, state: &state)
        var runs: [ThumbnailRun] = []
        var start = 0
        for index in 1...line.count where index == line.count || tones[index] != tones[start] {
            runs.append(ThumbnailRun(ThumbnailCells.string(line[start..<index]), tone: tones[start]))
            start = index
        }
        return runs
    }

    private func tones(in line: [Unicode.Scalar], state: inout State) -> [ThumbnailTone] {
        var tones = [ThumbnailTone](repeating: .text, count: line.count)
        func fill(_ range: Range<Int>, _ tone: ThumbnailTone) { for index in range { tones[index] = tone } }
        let count = line.count
        let first = line.firstIndex(where: { $0.value != 32 }) ?? count
        switch syntax {
        case .diff:
            if first < count {
                switch line[first] {
                case "+": fill(0..<count, .addition)
                case "-": fill(0..<count, .deletion)
                case "@": fill(0..<count, .heading)
                default: break
                }
            }
            return tones
        case .subRip, .webVTT, .subStationAlpha, .timedText, .subViewer, .microDVD:
            let text = ThumbnailCells.string(line)
            if text.contains("-->") || (!text.isEmpty && text.allSatisfy(\.isNumber)) || text.hasPrefix("WEBVTT") {
                fill(0..<count, .muted)
            }
            return tones
        case .markdown:
            if first < count, line[first] == "#" { fill(0..<count, .heading) }
            return tones
        default:
            break
        }
        guard let rules else { return tones }
        if rules.sections, first < count, line[first] == "[" {
            fill(0..<count, .heading)
            return tones
        }
        var index = 0
        if state.inBlockComment {
            let end = Self.endOfBlockComment(line, from: 0)
            fill(0..<end.index, .comment)
            state.inBlockComment = !end.closed
            index = end.index
        }
        while index < count {
            let scalar = line[index]
            if rules.lineComments.contains(where: { Self.matches(line, at: index, $0) }) {
                fill(index..<count, .comment)
                break
            }
            if rules.blockComments, scalar == "/", index + 1 < count, line[index + 1] == "*" {
                let end = Self.endOfBlockComment(line, from: index + 2)
                fill(index..<end.index, .comment)
                state.inBlockComment = !end.closed
                index = end.index
                continue
            }
            if rules.strings, scalar == "\"" || scalar == "'" || (rules.backticks && scalar == "`") {
                var end = index + 1
                while end < count {
                    if line[end] == "\\" { end += 2; continue }
                    if line[end] == scalar { end += 1; break }
                    end += 1
                }
                end = min(end, count)
                var follower = end
                while follower < count, line[follower] == " " { follower += 1 }
                let isKey = rules.quotedKeys && follower < count && (line[follower] == ":" || line[follower] == "=")
                fill(index..<end, isKey ? .key : .string)
                index = end
                continue
            }
            if rules.tags, scalar == "<" {
                var end = index + 1
                while end < count, line[end] != ">" { end += 1 }
                end = min(end + 1, count)
                fill(index..<end, .tag)
                index = end
                continue
            }
            if rules.numbers, Self.isDigit(scalar) || (scalar == "-" && index + 1 < count && Self.isDigit(line[index + 1])) {
                var end = index + 1
                while end < count, Self.isDigit(line[end]) || line[end] == "." || line[end] == "_" { end += 1 }
                fill(index..<end, .number)
                index = end
                continue
            }
            if Self.isIdentifierStart(scalar) {
                var end = index + 1
                while end < count, Self.isIdentifierPart(line[end], allowsDotAndDash: rules.keys) { end += 1 }
                var follower = end
                while follower < count, line[follower] == " " { follower += 1 }
                let word = ThumbnailCells.string(line[index..<end]).lowercased()
                if rules.keys, follower < count, line[follower] == ":" || line[follower] == "=" {
                    fill(index..<end, .key)
                } else if rules.literals, Self.literalWords.contains(word) {
                    fill(index..<end, .literal)
                } else if rules.keywords, Self.keywordWords.contains(word) {
                    fill(index..<end, .keyword)
                }
                index = end
                continue
            }
            index += 1
        }
        return tones
    }

    private static func matches(_ line: [Unicode.Scalar], at index: Int, _ marker: [Unicode.Scalar]) -> Bool {
        guard !marker.isEmpty, index + marker.count <= line.count else { return false }
        for offset in marker.indices where line[index + offset] != marker[offset] { return false }
        return true
    }

    /// The index just past the `*/` that closes a comment, or the line's end when it stays open.
    private static func endOfBlockComment(_ line: [Unicode.Scalar], from start: Int) -> (index: Int, closed: Bool) {
        var index = start
        while index + 1 < line.count {
            if line[index] == "*", line[index + 1] == "/" { return (index + 2, true) }
            index += 1
        }
        return (line.count, false)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 48 && scalar.value <= 57 }
    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122) || scalar == "_" || scalar == "$"
    }
    private static func isIdentifierPart(_ scalar: Unicode.Scalar, allowsDotAndDash: Bool) -> Bool {
        isIdentifierStart(scalar) || isDigit(scalar) || (allowsDotAndDash && (scalar == "." || scalar == "-"))
    }
}
