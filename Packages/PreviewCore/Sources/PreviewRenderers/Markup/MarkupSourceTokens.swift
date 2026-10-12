import Foundation
import PreviewContracts

/// Lexical highlighting for the Source view of the markup formats. Like `SourceSyntaxTokens`, it
/// is bounded lexical decoration over already-concealed text, not a parser: it never changes
/// the text, never colors unredacted source and keeps exact UTF-16 ranges. A host that tokenizes
/// Source asks this lexer first for these syntaxes and falls back to the generic one on nil.
enum MarkupSourceTokens {
    /// Returns tokens for a markup syntax, or nil when `syntax` is not one of them.
    static func tokens(in source: String, syntax: TextSyntax, maximumUTF16Units: Int = 262_144,
                       maximumTokens: Int = 20_000) -> [JSONSyntaxToken]? {
        switch syntax {
        case .latex, .bibtex, .asciidoc, .restructuredText, .orgMode, .fountain: break
        default: return nil
        }
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumTokens > 0 else { return [] }
        let units = Array(source.utf16.prefix(maximumUTF16Units + 1))
        guard units.count <= maximumUTF16Units else { return [] }
        var tokens: [JSONSyntaxToken] = []
        var overflowed = false
        func add(_ start: Int, _ end: Int, _ role: PreviewSyntaxRole) {
            guard end > start else { return }
            if tokens.count >= maximumTokens { overflowed = true; return }
            tokens.append(.init(range: NSRange(location: start, length: end - start), role: role))
        }
        switch syntax {
        case .latex: latex(units, add)
        case .bibtex: bibtex(units, add)
        default: lines(units, syntax: syntax, add)
        }
        return overflowed ? [] : tokens
    }

    private static func isLetter(_ unit: UInt16) -> Bool { (65...90).contains(unit) || (97...122).contains(unit) }
    private static func isDigit(_ unit: UInt16) -> Bool { (48...57).contains(unit) }

    // MARK: LaTeX

    private static func latex(_ units: [UInt16], _ add: (Int, Int, PreviewSyntaxRole) -> Void) {
        var index = 0
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 37: // % comment
                let start = index
                while index < units.count, units[index] != 10, units[index] != 13 { index += 1 }
                add(start, index, .comment)
            case 92: // \command
                let start = index
                index += 1
                if index < units.count, isLetter(units[index]) {
                    while index < units.count, isLetter(units[index]) { index += 1 }
                    if index < units.count, units[index] == 42 { index += 1 }
                } else if index < units.count { index += 1 }
                add(start, index, .keyword)
            case 36: // $ math $
                let start = index
                index += units[index...].starts(with: [36, 36]) ? 2 : 1
                while index < units.count, units[index] != 36, units[index] != 10 { if units[index] == 92 { index += 1 }; index += 1 }
                index = min(index + 1, units.count)
                add(start, index, .number)
            default: index += 1
            }
        }
    }

    // MARK: BibTeX

    private static func bibtex(_ units: [UInt16], _ add: (Int, Int, PreviewSyntaxRole) -> Void) {
        var index = 0
        var depth = 0
        while index < units.count {
            let unit = units[index]
            if depth == 0, unit == 64 { // @type
                let start = index
                index += 1
                while index < units.count, isLetter(units[index]) { index += 1 }
                add(start, index, .keyword)
                // Skip the opening brace; the key up to the comma is the entry's identifier.
                while index < units.count, units[index] == 32 || units[index] == 9 { index += 1 }
                if index < units.count, units[index] == 123 || units[index] == 40 {
                    depth = 1
                    index += 1
                    let keyStart = index
                    while index < units.count, ![44, 10, 13, 125, 41].contains(units[index]) { index += 1 }
                    add(keyStart, index, .type)
                }
                continue
            }
            if depth > 0 {
                if unit == 123 {
                    // A braced value: highlighted whole, nesting respected.
                    let start = index
                    var nesting = 0
                    repeat {
                        if units[index] == 123 { nesting += 1 } else if units[index] == 125 { nesting -= 1 }
                        index += 1
                    } while index < units.count && nesting > 0
                    add(start, index, .string)
                    continue
                }
                if unit == 125 || unit == 41 { depth = 0; index += 1; continue }
                if unit == 34 {
                    let start = index
                    index += 1
                    while index < units.count, units[index] != 34 { index += 1 }
                    index = min(index + 1, units.count)
                    add(start, index, .string)
                    continue
                }
                if isLetter(unit) {
                    let start = index
                    while index < units.count, isLetter(units[index]) || isDigit(units[index]) || units[index] == 45 || units[index] == 95 { index += 1 }
                    var following = index
                    while following < units.count, units[following] == 32 || units[following] == 9 { following += 1 }
                    if following < units.count, units[following] == 61 { add(start, index, .key) }
                    continue
                }
                if isDigit(unit) {
                    let start = index
                    while index < units.count, isDigit(units[index]) { index += 1 }
                    add(start, index, .number)
                    continue
                }
            }
            if unit == 37, depth == 0 {
                let start = index
                while index < units.count, units[index] != 10, units[index] != 13 { index += 1 }
                add(start, index, .comment)
                continue
            }
            index += 1
        }
    }

    // MARK: Line-based formats

    private static func lines(_ units: [UInt16], syntax: TextSyntax, _ add: (Int, Int, PreviewSyntaxRole) -> Void) {
        // Line spans first, so lookahead (underlines, blank lines) is cheap.
        var spans: [(start: Int, end: Int)] = []
        var start = 0
        while start <= units.count {
            var end = start
            while end < units.count, units[end] != 10, units[end] != 13 { end += 1 }
            spans.append((start, end))
            if end >= units.count { break }
            start = end + (units[end] == 13 && end + 1 < units.count && units[end + 1] == 10 ? 2 : 1)
        }
        func text(_ span: (start: Int, end: Int)) -> String { String(decoding: units[span.start..<span.end], as: UTF16.self) }
        for (position, span) in spans.enumerated() {
            let line = text(span)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let next = position + 1 < spans.count ? text(spans[position + 1]).trimmingCharacters(in: .whitespaces) : ""
            let previousBlank = position == 0 || text(spans[position - 1]).trimmingCharacters(in: .whitespaces).isEmpty
            switch syntax {
            case .asciidoc:
                if trimmed.hasPrefix("//") { add(span.start, span.end, .comment) }
                else if trimmed.hasPrefix("="), let first = trimmed.drop(while: { $0 == "=" }).first, first == " ", trimmed.prefix(while: { $0 == "=" }).count <= 6 {
                    add(span.start, span.end, .heading)
                } else if trimmed.hasPrefix(":"), trimmed.dropFirst().contains(":") { add(span.start, span.end, .key) }
                else if trimmed.hasPrefix("["), trimmed.hasSuffix("]") { add(span.start, span.end, .tag) }
                else if trimmed.count >= 4, let mark = trimmed.first, "-.=*_+/".contains(mark), trimmed.allSatisfy({ $0 == mark }) { add(span.start, span.end, .operator) }
                else if trimmed.hasPrefix("include::") || trimmed.hasPrefix("image::") { add(span.start, span.end, .keyword) }
            case .restructuredText:
                if trimmed.hasPrefix(".. ") || trimmed == ".." {
                    let isDirective = trimmed.contains("::")
                    add(span.start, span.end, isDirective ? .keyword : .comment)
                } else if trimmed.hasPrefix(":"), trimmed.dropFirst().contains(":") { add(span.start, span.end, .key) }
                else if isAdornment(trimmed) { add(span.start, span.end, .operator) }
                else if isAdornment(next), next.count >= trimmed.count, line.first != " " { add(span.start, span.end, .heading) }
            case .orgMode:
                let upper = trimmed.uppercased()
                if line.hasPrefix("*"), line.drop(while: { $0 == "*" }).first == " " { add(span.start, span.end, .heading) }
                else if upper.hasPrefix("#+BEGIN_") || upper.hasPrefix("#+END_") { add(span.start, span.end, .keyword) }
                else if trimmed.hasPrefix("#+") { add(span.start, span.end, .keyword) }
                else if trimmed.hasPrefix("# ") || trimmed == "#" { add(span.start, span.end, .comment) }
                else if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") || trimmed.dropFirst().contains(":") { add(span.start, span.end, .key) }
                else if upper.hasPrefix("SCHEDULED:") || upper.hasPrefix("DEADLINE:") || upper.hasPrefix("CLOSED:") { add(span.start, span.end, .comment) }
                else if trimmed.hasPrefix("|") { add(span.start, span.end, .operator) }
            case .fountain:
                if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") { add(span.start, span.end, .comment) }
                else if trimmed.hasPrefix("#") { add(span.start, span.end, .heading) }
                else if previousBlank, isScene(trimmed) { add(span.start, span.end, .heading) }
                else if previousBlank, trimmed.hasSuffix("TO:"), !trimmed.contains(where: { $0.isLowercase }) { add(span.start, span.end, .keyword) }
                else if previousBlank, !next.isEmpty, isCue(trimmed) { add(span.start, span.end, .key) }
                else if trimmed.hasPrefix("("), trimmed.hasSuffix(")") { add(span.start, span.end, .comment) }
                else if position < 12, let colon = trimmed.firstIndex(of: ":"), line.first?.isLetter == true,
                        trimmed[..<colon].allSatisfy({ $0.isLetter || $0 == " " }) {
                    let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
                    add(span.start + leading, span.start + leading + String(trimmed[..<colon]).utf16.count, .key)
                }
            default: break
            }
        }
    }

    private static func isAdornment(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3, let first = trimmed.first, "=-`:'\"~^_*+#<>".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    private static func isScene(_ trimmed: String) -> Bool {
        let upper = trimmed.uppercased()
        return ["INT.", "EXT.", "EST.", "INT/EXT", "INT./EXT", "I/E"].contains { upper.hasPrefix($0) } || trimmed.hasPrefix(".") && !trimmed.hasPrefix("..")
    }

    private static func isCue(_ trimmed: String) -> Bool {
        var name = trimmed
        if let open = name.firstIndex(of: "(") { name = String(name[..<open]).trimmingCharacters(in: .whitespaces) }
        return !name.isEmpty && name.contains(where: { $0.isLetter }) && !name.contains(where: { $0.isLowercase })
    }
}
