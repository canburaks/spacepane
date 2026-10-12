import Foundation
import PreviewContracts

/// Bounded lexical decoration, rather than a language compiler. Exact characters and Unicode
/// UTF-16 ranges are retained. Grammar-specific semantic promises are intentionally absent.
enum SourceSyntaxTokens {
    /// `language` is an optional semantic hint; nil keeps the generic lexical rules.
    static func tokens(in source: String, syntax: TextSyntax, language: SourceLanguageID? = nil,
                       maximumUTF16Units: Int = 262_144, maximumTokens: Int = 20_000) -> [JSONSyntaxToken] {
        if syntax == .plain { return [] }
        if syntax == .json { return JSONSyntaxTokens.tokens(in: source, maximumUTF16Units: maximumUTF16Units, maximumTokens: maximumTokens) }
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumTokens > 0 else { return [] }
        // Language-aware, line-oriented and caption decoration lives in the code family's files. These
        // paths color the first `maximumUTF16Units` units and at most `maximumTokens` tokens rather than
        // none, so a large log or source file is still decorated from its start.
        if let tokens = CodeSyntaxTokens.tokens(in: source, syntax: syntax, language: language,
                                                maximumUTF16Units: maximumUTF16Units, maximumTokens: maximumTokens) {
            return tokens
        }
        // Markup sources (LaTeX, BibTeX, AsciiDoc, reStructuredText, Org, Fountain) use the markup family's lexers.
        if let tokens = MarkupSourceTokens.tokens(in: source, syntax: syntax, maximumUTF16Units: maximumUTF16Units,
                                                  maximumTokens: maximumTokens) {
            return tokens
        }
        let units = Array(source.utf16.prefix(maximumUTF16Units + 1))
        guard units.count <= maximumUTF16Units else { return [] }
        if syntax == .diff { return diff(units, maximumTokens: maximumTokens) }
        var result: [JSONSyntaxToken] = []
        var index = 0
        while index < units.count {
            let start = index
            var role: PreviewSyntaxRole?
            let unit = units[index]
            if unit == 34 || unit == 39 || (syntax == .sourceCode && unit == 96) {
                let quote = unit
                index += 1
                while index < units.count {
                    let next = units[index]; index += 1
                    if next == 92, index < units.count { index += 1 }
                    else if next == quote { break }
                }
                var following = index
                while following < units.count, [9, 32].contains(units[following]) { following += 1 }
                role = following < units.count && [58, 61].contains(units[following]) ? .key : .string
            } else if unit == 47, index + 1 < units.count, units[index + 1] == 42 {
                index += 2
                while index + 1 < units.count, !(units[index] == 42 && units[index + 1] == 47) { index += 1 }
                index = min(units.count, index + 2)
                role = .comment
            } else if lineComment(units, at: index, syntax: syntax) {
                while index < units.count, units[index] != 10, units[index] != 13 { index += 1 }
                role = .comment
            } else if syntax == .xml || syntax == .propertyList {
                if unit == 60 {
                    index += 1
                    while index < units.count, units[index] != 62 { index += 1 }
                    if index < units.count { index += 1 }
                    role = .tag
                } else { index += 1 }
            } else if digit(unit) || (unit == 45 && index + 1 < units.count && digit(units[index + 1])) {
                index += 1
                while index < units.count, digit(units[index]) || [46, 95, 101, 69, 120, 88].contains(units[index]) { index += 1 }
                role = .number
            } else if identifierStart(unit) {
                index += 1
                while index < units.count, identifierStart(units[index]) || digit(units[index]) { index += 1 }
                let word = String(decoding: units[start..<index], as: UTF16.self)
                var following = index
                while following < units.count, [9, 32].contains(units[following]) { following += 1 }
                if following < units.count, [58, 61].contains(units[following]), [.yaml, .toml, .environment].contains(syntax) { role = .key }
                else if literals.contains(word.lowercased()) { role = .literal }
                else if keywords.contains(word.lowercased()) { role = .keyword }
            } else if syntax == .markdown, unit == 35, start == 0 || units[start - 1] == 10 || units[start - 1] == 13 {
                while index < units.count, units[index] != 10, units[index] != 13 { index += 1 }
                role = .heading
            } else {
                index += 1
                if syntax == .sourceCode, [43, 45, 42, 47, 61, 60, 62, 33, 38, 124].contains(unit) { role = .operator }
            }
            if let role {
                guard result.count < maximumTokens else { return [] }
                result.append(.init(range: NSRange(location: start, length: index - start), role: role))
            }
        }
        return result
    }
    private static func diff(_ units: [UInt16], maximumTokens: Int) -> [JSONSyntaxToken] {
        var result: [JSONSyntaxToken] = []
        var start = 0
        while start < units.count {
            var end = start
            while end < units.count, units[end] != 10, units[end] != 13 { end += 1 }
            let role: PreviewSyntaxRole?
            switch units[start] {
            case 43: role = .addition
            case 45: role = .deletion
            case 64: role = .heading
            default: role = nil
            }
            if let role {
                guard result.count < maximumTokens else { return [] }
                result.append(.init(range: .init(location: start, length: end - start), role: role))
            }
            start = end < units.count ? end + 1 : end
        }
        return result
    }
    private static func lineComment(_ units: [UInt16], at index: Int, syntax: TextSyntax) -> Bool {
        if units[index] == 35, [.sourceCode, .yaml, .toml, .environment].contains(syntax) { return true }
        if index + 1 < units.count {
            if units[index] == 47, units[index + 1] == 47 { return true }
            if syntax == .sourceCode, units[index] == 45, units[index + 1] == 45 { return true }
        }
        return false
    }
    private static func digit(_ unit: UInt16) -> Bool { (48...57).contains(unit) }
    private static func identifierStart(_ unit: UInt16) -> Bool { (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 || unit == 36 }
    private static let literals: Set<String> = ["true", "false", "null", "nil", "none", "yes", "no"]
    // A deliberately shared lexical keyword set for the tested initial source families.
    private static let keywords: Set<String> = [
        "let", "var", "func", "function", "class", "struct", "enum", "protocol", "extension", "import", "export",
        "public", "private", "internal", "static", "const", "async", "await", "actor", "throws", "throw", "try",
        "if", "else", "switch", "case", "default", "guard", "return", "break", "continue", "for", "while", "do",
        "in", "of", "as", "is", "new", "delete", "typeof", "def", "lambda", "with", "except", "finally", "raise",
        "from", "pass", "yield", "and", "or", "not", "fn", "impl", "trait", "use", "mut", "match", "pub", "mod",
        "package", "type", "interface", "map", "range", "go", "defer", "select", "chan", "int", "void", "char",
        "double", "float", "bool", "unsigned", "sizeof", "typedef", "include", "namespace", "template", "virtual",
        "fi", "then", "done", "esac", "echo", "local", "read", "select", "insert", "update", "delete", "create",
        "table", "where", "join", "order", "group", "by", "values", "into", "limit", "having", "distinct", "union",
        "end", "module", "require", "include", "extends", "implements", "final", "override", "val", "fun"
    ]
}
