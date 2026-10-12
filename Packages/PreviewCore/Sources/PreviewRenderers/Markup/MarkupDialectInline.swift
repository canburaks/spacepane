import Foundation

/// Inline readers for AsciiDoc, reStructuredText, Org and Fountain. Each tokenizes a reflowed
/// paragraph into the shared token model, which `MarkupInline.resolve` pairs. Links, images and
/// references become inert text (a label, with the target in parentheses where it adds
/// information); nothing is fetched or opened, and formulas are approximated like everywhere else.
enum MarkupDialectInline {
    enum Dialect { case asciidoc, restructuredText, org, fountain }

    private static let maximumSpanScan = 2_000
    private static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    static func rules(for dialect: Dialect) -> [Character: MarkupDelimiterRule] {
        switch dialect {
        case .asciidoc:
            return ["*": .init(styles: [1: .bold, 2: .bold]), "_": .init(styles: [1: .italic, 2: .italic])]
        case .restructuredText:
            return ["*": .init(styles: [1: .italic, 2: .bold])]
        case .org:
            return ["*": .init(styles: [1: .bold]), "/": .init(styles: [1: .italic]), "_": .init(styles: [1: .italic]),
                    "+": .init(styles: [1: .strikethrough])]
        case .fountain:
            return ["*": .init(styles: [1: .italic, 2: .bold]), "_": .init(styles: [1: .italic])]
        }
    }

    static func render(_ source: String, dialect: Dialect, footnotes: inout MarkupFootnotes) -> MarkupInlineResult {
        MarkupInline.resolve(tokens(source, dialect: dialect, footnotes: &footnotes), rules: rules(for: dialect))
    }

    // MARK: Tokenizer

    static func tokens(_ source: String, dialect: Dialect, footnotes: inout MarkupFootnotes) -> [MarkupInlineToken] {
        let characters = Array(source)
        let delimiters = Set(rules(for: dialect).keys)
        var tokens: [MarkupInlineToken] = []
        var pending = ""
        func flush() { if !pending.isEmpty { tokens.append(.text(pending)); pending = "" } }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let match = special(characters, at: index, dialect: dialect, footnotes: &footnotes) {
                flush()
                tokens.append(contentsOf: match.tokens)
                index = match.end
                continue
            }
            if character == "\\", dialect != .fountain, index + 1 < characters.count, asciiPunctuation.contains(characters[index + 1]) {
                pending.append(characters[index + 1]); index += 2; continue
            }
            if delimiters.contains(character) {
                var runEnd = index
                while runEnd < characters.count, characters[runEnd] == character { runEnd += 1 }
                let count = runEnd - index
                let previous = index > 0 ? characters[index - 1] : nil
                let next = runEnd < characters.count ? characters[runEnd] : nil
                let (canOpen, canClose) = flanking(character, count: count, previous: previous, next: next, dialect: dialect)
                if canOpen || canClose {
                    flush()
                    tokens.append(.delimiter(character, count: count, canOpen: canOpen, canClose: canClose))
                } else {
                    pending.append(String(repeating: character, count: count))
                }
                index = runEnd
                continue
            }
            pending.append(character)
            index += 1
        }
        flush()
        return tokens
    }

    // MARK: Flanking

    private static func flanking(_ character: Character, count: Int, previous: Character?, next: Character?,
                                 dialect: Dialect) -> (Bool, Bool) {
        let previousSpace = MarkupInline.isWhitespace(previous)
        let nextSpace = MarkupInline.isWhitespace(next)
        switch dialect {
        case .org:
            // Org: emphasis starts after whitespace or an opening mark and ends before whitespace or punctuation.
            let opening = previous == nil || previousSpace || "-({'\"".contains(previous!)
            let closing = next == nil || nextSpace || "-.,;:!?')}[\"\\".contains(next!)
            return (opening && !nextSpace, closing && !previousSpace)
        case .restructuredText:
            // reStructuredText: start-strings follow whitespace or punctuation; end-strings precede them.
            let opening = previous == nil || previousSpace || MarkupInline.isPunctuation(previous)
            let closing = next == nil || nextSpace || MarkupInline.isPunctuation(next)
            return (opening && !nextSpace, closing && !previousSpace)
        case .asciidoc:
            // Constrained single marks stay out of words; doubled marks may sit inside them.
            if count >= 2 { return (!nextSpace, !previousSpace) }
            let opening = previous == nil || previousSpace || MarkupInline.isPunctuation(previous)
            let closing = next == nil || nextSpace || MarkupInline.isPunctuation(next)
            return (opening && !nextSpace, closing && !previousSpace)
        case .fountain:
            let underscore = character == "_"
            let leftFlanking = !nextSpace
            let rightFlanking = !previousSpace
            if underscore { return (leftFlanking && (previousSpace || previous == nil), rightFlanking && (nextSpace || next == nil || MarkupInline.isPunctuation(next))) }
            return (leftFlanking, rightFlanking)
        }
    }

    // MARK: Specials

    private struct Match {
        let tokens: [MarkupInlineToken]
        let end: Int
    }

    private static func special(_ characters: [Character], at index: Int, dialect: Dialect,
                                footnotes: inout MarkupFootnotes) -> Match? {
        switch dialect {
        case .asciidoc: return asciidoc(characters, at: index, footnotes: &footnotes)
        case .restructuredText: return restructuredText(characters, at: index)
        case .org: return org(characters, at: index, footnotes: &footnotes)
        case .fountain: return fountain(characters, at: index)
        }
    }

    private static func hasPrefix(_ characters: [Character], at index: Int, _ prefix: String) -> Bool {
        let units = Array(prefix)
        guard index + units.count <= characters.count else { return false }
        for offset in 0..<units.count where characters[index + offset] != units[offset] { return false }
        return true
    }

    /// The text between the current position (after `open`) and the next `close`, within the scan bound.
    private static func span(_ characters: [Character], from start: Int, closing close: String) -> (content: String, end: Int)? {
        let end = Array(close)
        var index = start
        let limit = min(characters.count, start + maximumSpanScan)
        while index + end.count <= limit {
            if characters[index] == end[0], hasPrefix(characters, at: index, close) {
                return (String(characters[start..<index]), index + end.count)
            }
            index += 1
        }
        return nil
    }

    private static func isBoundary(_ character: Character?) -> Bool {
        character == nil || MarkupInline.isWhitespace(character) || MarkupInline.isPunctuation(character)
    }

    private static let imageSuffixes: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tif", "tiff", "heic", "avif"]

    /// Whether a link target names an image file: its path ends in an image suffix, ignoring a `::` search option,
    /// a query and a fragment. Only the leading characters are read.
    private static func isImageFile(_ target: String) -> Bool {
        var path = target.prefix(maximumSpanScan)
        if let option = path.range(of: "::") { path = path[..<option.lowerBound] }
        if let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<end] }
        guard let dot = path.lastIndex(of: ".") else { return false }
        return imageSuffixes.contains(path[path.index(after: dot)...].lowercased())
    }

    private static func math(_ tex: String) -> MarkupInlineToken { .styled(MarkupMath.approximate(tex), .math) }

    // MARK: AsciiDoc

    private static func asciidoc(_ characters: [Character], at index: Int, footnotes: inout MarkupFootnotes) -> Match? {
        let character = characters[index]
        let previous = index > 0 ? characters[index - 1] : nil
        if character == "`" {
            // Monospace, with the `+literal+` passthrough form.
            guard isBoundary(previous), let found = span(characters, from: index + 1, closing: "`"), !found.content.isEmpty else { return nil }
            var content = found.content
            if content.count > 2, content.hasPrefix("+"), content.hasSuffix("+") { content = String(content.dropFirst().dropLast()) }
            return Match(tokens: [.styled(content, .code)], end: found.end)
        }
        if character == "<", hasPrefix(characters, at: index, "<<"), let found = span(characters, from: index + 2, closing: ">>") {
            let parts = found.content.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return Match(tokens: [.text(parts.count == 2 ? parts[1] : (parts.first ?? ""))], end: found.end)
        }
        if let name = macroName(characters, at: index, names: ["stem", "latexmath", "asciimath"]),
           let found = span(characters, from: index + name.count + 2, closing: "]") {
            return Match(tokens: [math(found.content)], end: found.end)
        }
        if hasPrefix(characters, at: index, "footnote:["), let found = span(characters, from: index + 10, closing: "]"),
           let number = footnotes.add(text: found.content) {
            return Match(tokens: [.styled(MarkupFootnotes.superscript(number), .footnoteMark)], end: found.end)
        }
        for name in ["image:", "link:", "xref:", "mailto:"] where hasPrefix(characters, at: index, name) && isBoundary(previous) {
            let targetStart = index + name.count
            guard let bracket = nextBracket(characters, from: targetStart), let found = span(characters, from: bracket + 1, closing: "]") else { continue }
            let target = String(characters[targetStart..<bracket])
            let label = found.content.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            switch name {
            case "image:":
                // The description (or the target) is shown; the image itself is never loaded, only counted.
                var pieces: [MarkupInlineToken] = [.text(label.isEmpty ? target : label)]
                if let kind = OmittedResourceKind.image(destination: target) { pieces.append(.omitted(OmittedResources(kind))) }
                return Match(tokens: pieces, end: found.end)
            case "xref:": return Match(tokens: [.text(label.isEmpty ? target : label)], end: found.end)
            default: return Match(tokens: [.text(label.isEmpty ? target : label + " (" + target + ")")], end: found.end)
            }
        }
        if (hasPrefix(characters, at: index, "https://") || hasPrefix(characters, at: index, "http://")) && isBoundary(previous) {
            var end = index
            while end < characters.count, !characters[end].isWhitespace, characters[end] != "[" { end += 1 }
            if end < characters.count, characters[end] == "[", let found = span(characters, from: end + 1, closing: "]") {
                let target = String(characters[index..<end])
                let label = found.content.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
                return Match(tokens: [.text(label.isEmpty ? target : label + " (" + target + ")")], end: found.end)
            }
        }
        return nil
    }

    private static func macroName(_ characters: [Character], at index: Int, names: [String]) -> String? {
        for name in names where hasPrefix(characters, at: index, name + ":[") { return name }
        return nil
    }

    private static func nextBracket(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        let limit = min(characters.count, start + maximumSpanScan)
        while index < limit {
            if characters[index] == "[" { return index }
            if characters[index].isWhitespace { return nil }
            index += 1
        }
        return nil
    }

    // MARK: reStructuredText

    private static func restructuredText(_ characters: [Character], at index: Int) -> Match? {
        let character = characters[index]
        let previous = index > 0 ? characters[index - 1] : nil
        if character == "`", hasPrefix(characters, at: index, "``"), isBoundary(previous) {
            guard let found = span(characters, from: index + 2, closing: "``"), !found.content.isEmpty else { return nil }
            return Match(tokens: [.styled(found.content, .code)], end: found.end)
        }
        if character == ":", isBoundary(previous) {
            // `:role:`text``
            var end = index + 1
            while end < characters.count, characters[end].isLetter || characters[end] == "-" || characters[end] == "+" || characters[end] == ":" { end += 1 }
            if end < characters.count, characters[end] == "`", end > index + 1, characters[end - 1] == ":" {
                let role = String(characters[(index + 1)..<(end - 1)])
                if let found = span(characters, from: end + 1, closing: "`"), !found.content.isEmpty {
                    var content = found.content
                    // `:ref:`label <target>`` shows the label.
                    if let open = content.lastIndex(of: "<"), content.hasSuffix(">"), open != content.startIndex {
                        content = String(content[..<open]).trimmingCharacters(in: .whitespaces)
                    }
                    switch role {
                    case "math": return Match(tokens: [math(found.content)], end: found.end)
                    case "kbd", "code", "literal", "file", "samp", "command", "program", "guilabel", "menuselection", "mimetype", "option":
                        return Match(tokens: [.styled(content, .code)], end: found.end)
                    default: return Match(tokens: [.text(content)], end: found.end)
                    }
                }
            }
            return nil
        }
        if character == "`", isBoundary(previous) {
            guard let found = span(characters, from: index + 1, closing: "`"), !found.content.isEmpty else { return nil }
            var end = found.end
            let isReference = end < characters.count && characters[end] == "_"
            if isReference { end += 1; if end < characters.count, characters[end] == "_" { end += 1 } }
            var content = found.content
            if isReference, let open = content.lastIndex(of: "<"), content.hasSuffix(">") {
                let label = String(content[..<open]).trimmingCharacters(in: .whitespaces)
                let target = String(content[content.index(after: open)..<content.index(before: content.endIndex)])
                content = label.isEmpty ? target : label + " (" + target + ")"
            }
            return Match(tokens: [isReference ? .text(content) : .styled(content, .italic)], end: end)
        }
        return nil
    }

    // MARK: Org

    private static func org(_ characters: [Character], at index: Int, footnotes: inout MarkupFootnotes) -> Match? {
        let character = characters[index]
        let previous = index > 0 ? characters[index - 1] : nil
        let orgOpening = previous == nil || MarkupInline.isWhitespace(previous) || "-({'\"".contains(previous!)
        if (character == "=" || character == "~"), orgOpening,
           let found = span(characters, from: index + 1, closing: String(character)), !found.content.isEmpty,
           !found.content.hasPrefix(" "), !found.content.hasSuffix(" ") {
            let following = found.end < characters.count ? characters[found.end] : nil
            if following == nil || MarkupInline.isWhitespace(following) || "-.,;:!?')}[\"".contains(following!) {
                return Match(tokens: [.styled(found.content, .code)], end: found.end)
            }
        }
        if character == "[", hasPrefix(characters, at: index, "[["), let close = span(characters, from: index + 2, closing: "]]") {
            // [[target]] or [[target][description]]
            let parts = close.content.components(separatedBy: "][")
            if parts.count >= 2 { return Match(tokens: [.text(parts[1] + " (" + parts[0] + ")")], end: close.end) }
            // A link to an image file with no description is an inline image in Org. It is shown as its target
            // and never loaded, only counted.
            var pieces: [MarkupInlineToken] = [.text(close.content)]
            if isImageFile(close.content), let kind = OmittedResourceKind.image(destination: close.content) {
                pieces.append(.omitted(OmittedResources(kind)))
            }
            return Match(tokens: pieces, end: close.end)
        }
        if hasPrefix(characters, at: index, "[fn:"), let close = span(characters, from: index + 4, closing: "]") {
            let parts = close.content.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let number = footnotes.add(text: parts[1]) {
                return Match(tokens: [.styled(MarkupFootnotes.superscript(number), .footnoteMark)], end: close.end)
            }
            if let label = parts.first, let number = footnotes.reference(label: label) {
                return Match(tokens: [.styled(MarkupFootnotes.superscript(number), .footnoteMark)], end: close.end)
            }
            return nil
        }
        if hasPrefix(characters, at: index, "\\("), let close = span(characters, from: index + 2, closing: "\\)") {
            return Match(tokens: [math(close.content)], end: close.end)
        }
        if character == "$" {
            if hasPrefix(characters, at: index, "$$"), let close = span(characters, from: index + 2, closing: "$$"), !close.content.isEmpty {
                return Match(tokens: [math(close.content)], end: close.end)
            }
            guard index + 1 < characters.count, !characters[index + 1].isWhitespace, characters[index + 1] != "$",
                  let close = span(characters, from: index + 1, closing: "$"), !close.content.isEmpty,
                  !close.content.hasSuffix(" ") else { return nil }
            let following = close.end < characters.count ? characters[close.end] : nil
            if following?.isNumber == true { return nil }
            return Match(tokens: [math(close.content)], end: close.end)
        }
        return nil
    }

    // MARK: Fountain

    private static func fountain(_ characters: [Character], at index: Int) -> Match? {
        // Notes `[[...]]` are author remarks, shown dimmed.
        if hasPrefix(characters, at: index, "[["), let close = span(characters, from: index + 2, closing: "]]") {
            return Match(tokens: [.styled("[" + close.content + "]", .dimmed)], end: close.end)
        }
        return nil
    }
}
