import Foundation

/// One person in an `author` or `editor` field, split by the BibTeX name rules
/// (`First von Last`, `von Last, First` and `von Last, Jr, First`). Parts are plain text.
struct BibliographyName: Equatable, Sendable {
    let first: String
    let von: String
    let last: String
    let jr: String
    /// The `others` marker that stands for "et al.".
    let isOthers: Bool

    init(first: String = "", von: String = "", last: String = "", jr: String = "", isOthers: Bool = false) {
        self.first = first
        self.von = von
        self.last = last
        self.jr = jr
        self.isOthers = isOthers
    }

    /// The family name with its particle: "van der Berg".
    var surname: String { [von, last].filter { !$0.isEmpty }.joined(separator: " ") }

    /// Given names reduced to initials: "Ada Byron" becomes "A. B." and "Jean-Paul" becomes "J.-P.".
    var initials: String {
        first.split(separator: " ").map { word in
            word.split(separator: "-", omittingEmptySubsequences: true).map { part -> String in
                guard let letter = part.first(where: { $0.isLetter }) else { return String(part) }
                return String(letter).uppercased() + "."
            }.joined(separator: "-")
        }.joined(separator: " ")
    }
}

/// A bibliography entry as written: raw field values after `@string` macro expansion and `#`
/// concatenation, with braces and TeX commands intact. Accessors return plain text.
struct BibliographyEntry: Equatable, Sendable {
    let type: String
    let key: String
    let fields: [String: String]

    /// The first non-empty field among `names`, as plain text.
    func field(_ names: String...) -> String? {
        for name in names {
            guard let raw = fields[name] else { continue }
            let value = MarkupLaTeXText.plain(raw)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// People in `author` or `editor`, in order. An `and others` tail is kept as a marker name.
    func people(_ name: String) -> [BibliographyName] {
        guard let raw = fields[name] else { return [] }
        return BibliographyNames.parse(raw)
    }
}

/// The parsed content of a `.bib` file. Entries keep file order; `@comment`, `@preamble` and text
/// between entries are ignored, and nothing is fetched or evaluated.
struct SafeBibliography: Equatable, Sendable {
    static let maximumEntries = 5_000
    static let maximumFieldsPerEntry = 64
    static let maximumValueUnits = 8_192
    static let maximumSourceUnits = 262_144

    let entries: [BibliographyEntry]

    /// Parses concealed BibTeX text. Returns nil when the text is too large or holds no entry.
    static func parse(_ text: String) -> SafeBibliography? {
        guard text.utf16.prefix(maximumSourceUnits + 1).count <= maximumSourceUnits else { return nil }
        var parser = Parser(characters: Array(text))
        parser.run()
        return parser.entries.isEmpty ? nil : SafeBibliography(entries: parser.entries)
    }

    private static let months = [
        "jan": "January", "feb": "February", "mar": "March", "apr": "April", "may": "May", "jun": "June",
        "jul": "July", "aug": "August", "sep": "September", "oct": "October", "nov": "November", "dec": "December"
    ]

    private struct Parser {
        let characters: [Character]
        var index = 0
        var macros: [String: String] = SafeBibliography.months
        var entries: [BibliographyEntry] = []

        init(characters: [Character]) { self.characters = characters }

        private var isAtEnd: Bool { index >= characters.count }

        mutating func run() {
            while !isAtEnd, entries.count < SafeBibliography.maximumEntries {
                guard let at = characters[index...].firstIndex(of: "@") else { return }
                index = at + 1
                parseItem()
            }
        }

        private mutating func skipWhitespace() {
            while !isAtEnd, characters[index].isWhitespace { index += 1 }
        }

        private static func isIdentifier(_ character: Character) -> Bool {
            !(character.isWhitespace || ",=#{}()\"".contains(character))
        }

        private mutating func parseItem() {
            skipWhitespace()
            var type = ""
            while !isAtEnd, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "-" {
                type.append(characters[index]); index += 1
            }
            skipWhitespace()
            guard !type.isEmpty, !isAtEnd, characters[index] == "{" || characters[index] == "(" else { return }
            let opener = characters[index]
            let closer: Character = opener == "{" ? "}" : ")"
            index += 1
            switch type.lowercased() {
            case "comment", "preamble":
                skipGroup(opener: opener, closer: closer)
            case "string":
                skipWhitespace()
                let name = identifier().lowercased()
                skipWhitespace()
                if !isAtEnd, characters[index] == "=" {
                    index += 1
                    let value = parseValue(closer: closer)
                    if !name.isEmpty { macros[name] = value }
                }
                skipToClose(closer: closer)
            default:
                parseEntry(type: type.lowercased(), closer: closer)
            }
        }

        private mutating func identifier() -> String {
            var name = ""
            while !isAtEnd, Self.isIdentifier(characters[index]) { name.append(characters[index]); index += 1 }
            return name
        }

        /// Skips to just after the bracket that closes a group whose opener was already consumed.
        private mutating func skipGroup(opener: Character, closer: Character) {
            var depth = 1
            while !isAtEnd, depth > 0 {
                let character = characters[index]
                index += 1
                if character == opener { depth += 1 } else if character == closer { depth -= 1 }
            }
        }

        /// Error recovery: continues to the closer of the current entry at brace depth zero.
        private mutating func skipToClose(closer: Character) {
            var depth = 0
            while !isAtEnd {
                let character = characters[index]
                if character == "{" { depth += 1 }
                else if character == "}" {
                    if depth == 0 && closer == "}" { index += 1; return }
                    depth = max(depth - 1, 0)
                } else if character == closer, depth == 0 { index += 1; return }
                else if character == "@", depth == 0, atLineStart() { return }
                index += 1
            }
        }

        private func atLineStart() -> Bool {
            var position = index - 1
            while position >= 0, characters[position] == " " || characters[position] == "\t" { position -= 1 }
            return position < 0 || characters[position] == "\n" || characters[position] == "\r"
        }

        private mutating func parseEntry(type: String, closer: Character) {
            skipWhitespace()
            var key = ""
            while !isAtEnd, characters[index] != ",", characters[index] != closer, characters[index] != "}" {
                key.append(characters[index]); index += 1
            }
            key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            var fields: [String: String] = [:]
            while !isAtEnd {
                while !isAtEnd, characters[index].isWhitespace || characters[index] == "," { index += 1 }
                if isAtEnd { break }
                if characters[index] == closer || characters[index] == "}" { index += 1; break }
                if characters[index] == "@", atLineStart() { break }
                let name = identifier().lowercased()
                skipWhitespace()
                guard !name.isEmpty, !isAtEnd, characters[index] == "=" else {
                    // Not a field: skip to the next comma at depth zero, or stop at the entry's end.
                    skipField(closer: closer)
                    continue
                }
                index += 1
                let value = parseValue(closer: closer)
                if fields.count < SafeBibliography.maximumFieldsPerEntry, fields[name] == nil { fields[name] = value }
            }
            entries.append(BibliographyEntry(type: type, key: key, fields: fields))
        }

        private mutating func skipField(closer: Character) {
            var depth = 0
            while !isAtEnd {
                let character = characters[index]
                if character == "{" { depth += 1 }
                else if character == "}" { if depth == 0 { return }; depth -= 1 }
                else if character == ",", depth == 0 { index += 1; return }
                else if character == closer, depth == 0 { return }
                index += 1
            }
        }

        /// A value: one or more `{braced}`, `"quoted"`, numeric or macro parts joined with `#`.
        private mutating func parseValue(closer: Character) -> String {
            var value = ""
            func append(_ part: String) {
                guard value.utf16.count < SafeBibliography.maximumValueUnits else { return }
                value += part
            }
            while true {
                skipWhitespace()
                guard !isAtEnd else { break }
                let character = characters[index]
                if character == "{" {
                    index += 1
                    append(readBraced())
                } else if character == "\"" {
                    index += 1
                    append(readQuoted())
                } else if character.isNumber {
                    var digits = ""
                    while !isAtEnd, characters[index].isNumber { digits.append(characters[index]); index += 1 }
                    append(digits)
                } else if Self.isIdentifier(character) {
                    let name = identifier()
                    append(macros[name.lowercased()] ?? name)
                } else { break }
                skipWhitespace()
                if !isAtEnd, characters[index] == "#" { index += 1 } else { break }
            }
            return value
        }

        /// The contents of a braced value; nested braces stay in the text.
        private mutating func readBraced() -> String {
            var depth = 1
            var text = ""
            while !isAtEnd {
                let character = characters[index]
                index += 1
                if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 { return text }
                }
                if text.utf16.count < SafeBibliography.maximumValueUnits { text.append(character) }
            }
            return text
        }

        /// The contents of a quoted value, which ends at a quote outside nested braces.
        private mutating func readQuoted() -> String {
            var depth = 0
            var text = ""
            while !isAtEnd {
                let character = characters[index]
                index += 1
                if character == "{" { depth += 1 }
                else if character == "}" { depth = max(depth - 1, 0) }
                else if character == "\"", depth == 0 { return text }
                if text.utf16.count < SafeBibliography.maximumValueUnits { text.append(character) }
            }
            return text
        }
    }
}

enum BibliographyNames {
    static let maximumNames = 200

    /// Splits an `author`/`editor` value at top-level `and` and parses every name.
    static func parse(_ raw: String) -> [BibliographyName] {
        var names: [BibliographyName] = []
        for piece in splitAnd(raw).prefix(maximumNames) {
            if let name = parseName(piece) { names.append(name) }
        }
        return names
    }

    /// Words split on whitespace outside braces.
    private static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 }
            else if character == "}" { depth = max(depth - 1, 0) }
            if character.isWhitespace, depth == 0 {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func splitAnd(_ text: String) -> [String] {
        var pieces: [String] = []
        var current: [String] = []
        for token in tokens(text) {
            if token.lowercased() == "and" {
                pieces.append(current.joined(separator: " "))
                current = []
            } else { current.append(token) }
        }
        pieces.append(current.joined(separator: " "))
        return pieces.filter { !$0.isEmpty }
    }

    /// Parts separated by commas outside braces.
    private static func commaParts(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 }
            else if character == "}" { depth = max(depth - 1, 0) }
            if character == ",", depth == 0 { parts.append(current); current = "" } else { current.append(character) }
        }
        parts.append(current)
        return parts
    }

    /// BibTeX treats a word as a "von" part when its first letter outside braces is lowercase.
    private static func startsLowercase(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isLowercase
    }

    private static func plain(_ tokens: ArraySlice<String>) -> String {
        MarkupLaTeXText.plain(tokens.joined(separator: " "))
    }

    private static func parseName(_ text: String) -> BibliographyName? {
        let parts = commaParts(text)
        let words = tokens(parts[0])
        guard !words.isEmpty else { return nil }
        if parts.count == 1 {
            if words == ["others"] { return BibliographyName(isOthers: true) }
            guard words.count > 1 else { return BibliographyName(last: MarkupLaTeXText.plain(words[0])) }
            // First von Last: von is the run of lowercase words that is not the final word.
            var vonStart: Int?
            var vonEnd = 0
            for index in 0..<(words.count - 1) where startsLowercase(words[index]) {
                if vonStart == nil { vonStart = index }
                vonEnd = index
            }
            guard let start = vonStart else {
                return BibliographyName(first: plain(words[0..<(words.count - 1)]), last: MarkupLaTeXText.plain(words[words.count - 1]))
            }
            return BibliographyName(first: plain(words[0..<start]), von: plain(words[start...vonEnd]),
                                    last: plain(words[(vonEnd + 1)...]))
        }
        // von Last, [Jr,] First: the particle is the leading lowercase run before the last word.
        var vonEnd = -1
        for index in 0..<max(words.count - 1, 0) {
            if startsLowercase(words[index]), vonEnd == index - 1 { vonEnd = index }
        }
        let von = vonEnd >= 0 ? plain(words[0...vonEnd]) : ""
        let last = plain(words[(vonEnd + 1)...])
        let jr = parts.count >= 3 ? MarkupLaTeXText.plain(parts[1]) : ""
        let first = MarkupLaTeXText.plain(parts[parts.count >= 3 ? 2 : 1])
        return BibliographyName(first: first, von: von, last: last, jr: jr)
    }
}
