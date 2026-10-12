import Foundation

/// Plain text from TeX-flavored text such as BibTeX field values and LaTeX paragraphs: braces
/// that only protect capitalization disappear, accent commands compose into single characters,
/// dashes and quotes become typographic characters, common text commands keep their argument and
/// inline math is approximated. Nothing is evaluated; unknown commands lose their name and keep
/// their argument. Input and nesting are bounded and every step consumes input.
enum MarkupLaTeXText {
    static let maximumCharacters = 16_384
    private static let maximumNesting = 12

    /// Combining marks for accent commands such as `\'e` and `\c{c}`.
    private static let accents: [Character: Character] = [
        "'": "\u{0301}", "`": "\u{0300}", "^": "\u{0302}", "\"": "\u{0308}", "~": "\u{0303}", "=": "\u{0304}",
        ".": "\u{0307}", "u": "\u{0306}", "v": "\u{030C}", "H": "\u{030B}", "c": "\u{0327}", "k": "\u{0328}",
        "r": "\u{030A}", "b": "\u{0331}", "d": "\u{0323}"
    ]

    private static let letters: [String: String] = [
        "ss": "ß", "o": "ø", "O": "Ø", "aa": "å", "AA": "Å", "ae": "æ", "AE": "Æ", "oe": "œ", "OE": "Œ",
        "l": "ł", "L": "Ł", "i": "ı", "j": "ȷ", "textendash": "–", "textemdash": "—", "ldots": "…", "dots": "…",
        "textellipsis": "…", "LaTeX": "LaTeX", "TeX": "TeX", "BibTeX": "BibTeX", "textbackslash": "\\",
        "textquoteleft": "‘", "textquoteright": "’", "textquotedblleft": "“", "textquotedblright": "”",
        "textasciitilde": "~", "textunderscore": "_", "copyright": "©", "pounds": "£", "S": "§", "P": "¶",
        "dag": "†", "ddag": "‡", "textregistered": "®", "texttrademark": "™", "degree": "°", "textdegree": "°"
    ]

    /// Commands whose braced argument is the text itself.
    private static let transparent: Set<String> = [
        "emph", "textit", "textbf", "textrm", "textsf", "texttt", "textsc", "textsl", "textup", "textnormal",
        "mbox", "hbox", "url", "path", "text", "mathrm", "mathit", "mathbf", "underline", "uppercase",
        "lowercase", "MakeUppercase", "MakeLowercase", "textsuperscript", "textsubscript", "bibinfo", "enquote"
    ]

    /// The character a letter-named command stands for (`ss`, `ldots`, `LaTeX`), or nil.
    static func symbol(named name: String) -> String? { letters[name] }

    /// The combining mark for an accent command (`'`, `"`, `c`, `v`), or nil.
    static func accent(named name: Character) -> Character? { accents[name] }

    /// Applies a combining mark to the first character of `base`.
    static func compose(_ mark: Character, onto base: String) -> String {
        var base = base
        if base == "ı" { base = "i" } else if base == "ȷ" { base = "j" }
        guard let first = base.first else { return String(mark) }
        return (String(first) + String(mark)).precomposedStringWithCanonicalMapping + base.dropFirst()
    }

    static func plain(_ source: String) -> String {
        guard source.count <= maximumCharacters else { return collapse(String(source.prefix(maximumCharacters))) }
        var converter = Converter(characters: Array(source))
        return collapse(converter.run(depth: 0))
    }

    /// Whitespace runs become single spaces; ends are trimmed.
    static func collapse(_ text: String) -> String {
        var result = ""
        var pending = false
        for character in text {
            if character.isWhitespace && character != "\u{00A0}" { pending = true; continue }
            if pending, !result.isEmpty { result.append(" ") }
            pending = false
            result.append(character)
        }
        return result
    }

    private struct Converter {
        let characters: [Character]
        var index = 0

        init(characters: [Character]) { self.characters = characters }

        private var isAtEnd: Bool { index >= characters.count }

        /// Converts until the end of input or, inside a group, its closing brace.
        mutating func run(depth: Int) -> String {
            var output = ""
            while !isAtEnd {
                let character = characters[index]
                switch character {
                case "}":
                    if depth > 0 { return output }
                    index += 1
                case "{":
                    index += 1
                    output += depth < MarkupLaTeXText.maximumNesting ? groupContents(depth: depth + 1) : ""
                case "\\":
                    output += command(depth: depth)
                case "$":
                    output += inlineMath()
                case "~":
                    index += 1
                    output.append("\u{00A0}")
                case "-":
                    var run = 0
                    while !isAtEnd, characters[index] == "-" { run += 1; index += 1 }
                    output += run >= 3 ? "—" : run == 2 ? "–" : String(repeating: "-", count: run)
                case "`":
                    index += 1
                    if !isAtEnd, characters[index] == "`" { index += 1; output.append("“") } else { output.append("‘") }
                case "'":
                    index += 1
                    if !isAtEnd, characters[index] == "'" { index += 1; output.append("”") } else { output.append("’") }
                default:
                    index += 1
                    output.append(character)
                }
            }
            return output
        }

        private mutating func groupContents(depth: Int) -> String {
            let inner = run(depth: depth)
            if !isAtEnd, characters[index] == "}" { index += 1 }
            return inner
        }

        private mutating func inlineMath() -> String {
            index += 1
            var tex = ""
            while !isAtEnd, characters[index] != "$" {
                if characters[index] == "\\", index + 1 < characters.count { tex.append(characters[index]); index += 1 }
                tex.append(characters[index])
                index += 1
            }
            if !isAtEnd { index += 1 }
            return MarkupMath.approximate(tex)
        }

        private mutating func skipSpaces() {
            while !isAtEnd, characters[index] == " " || characters[index] == "\t" || characters[index] == "\n" { index += 1 }
        }

        /// One argument: a braced group converted recursively, or a single character.
        private mutating func argument(depth: Int) -> String {
            skipSpaces()
            guard !isAtEnd else { return "" }
            if characters[index] == "{" {
                index += 1
                return depth < MarkupLaTeXText.maximumNesting ? groupContents(depth: depth + 1) : ""
            }
            if characters[index] == "\\" { return command(depth: depth) }
            let character = characters[index]
            index += 1
            return String(character)
        }

        private mutating func command(depth: Int) -> String {
            index += 1 // backslash
            guard !isAtEnd else { return "" }
            let first = characters[index]
            if first.isASCII, first.isLetter {
                var name = ""
                while !isAtEnd, characters[index].isASCII, characters[index].isLetter { name.append(characters[index]); index += 1 }
                // Control words swallow the spaces after them; `\ss{}` style empty groups are empty arguments.
                skipSpaces()
                if name.count == 1, let accent = MarkupLaTeXText.accents[name[name.startIndex]] {
                    return compose(accent, depth: depth)
                }
                if let replacement = MarkupLaTeXText.letters[name] {
                    if !isAtEnd, characters[index] == "{", index + 1 < characters.count, characters[index + 1] == "}" { index += 2 }
                    return replacement
                }
                if MarkupLaTeXText.transparent.contains(name) { return argument(depth: depth) }
                if name == "href" {
                    _ = argument(depth: depth)
                    return argument(depth: depth)
                }
                // Unknown command: its name disappears, a braced argument stays.
                return ""
            }
            index += 1
            switch first {
            case "&", "%", "$", "#", "_", "{", "}": return String(first)
            case " ", "\\", ",", ";", ":", "!": return first == "!" ? "" : " "
            case "-", "/": return ""
            default:
                if let accent = MarkupLaTeXText.accents[first] { return compose(accent, depth: depth) }
                return String(first)
            }
        }

        /// Applies a combining accent to the next letter or braced letter.
        private mutating func compose(_ accent: Character, depth: Int) -> String {
            var base = argument(depth: depth)
            // A dotless i or j under an accent takes the dotted letter's accent form.
            if base == "ı" { base = "i" } else if base == "ȷ" { base = "j" }
            guard let first = base.first else { return String(accent) }
            return (String(first) + String(accent)).precomposedStringWithCanonicalMapping + base.dropFirst()
        }
    }
}
