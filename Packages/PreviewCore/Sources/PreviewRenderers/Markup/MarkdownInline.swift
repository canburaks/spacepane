import Foundation

/// Inline Markdown for the inert subset: emphasis, strikethrough, code spans, math,
/// footnote references and links/images shown as text. Destinations are plain text and never
/// become link attributes; HTML and entities stay literal. An image is drawn as one localized
/// "Image: description" marker and its destination is only classified for the offline notice.
enum MarkdownInline {
    static let rules: [Character: MarkupDelimiterRule] = [
        "*": .init(styles: [1: .italic, 2: .bold]),
        "_": .init(styles: [1: .italic, 2: .bold]),
        "~": .init(styles: [2: .strikethrough])
    ]
    /// A math span or link target is searched for within this many characters of its opener.
    static let maximumSpanScan = 2_000
    private static let maximumLabelDepth = 2
    private static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    static func render(_ source: String, footnotes: inout MarkupFootnotes) -> MarkupInlineResult {
        MarkupInline.resolve(tokens(source, footnotes: &footnotes, depth: 0), rules: rules)
    }

    static func tokens(_ source: String, footnotes: inout MarkupFootnotes, depth: Int) -> [MarkupInlineToken] {
        let characters = Array(source)
        var tokens: [MarkupInlineToken] = []
        var pending = ""
        func flush() { if !pending.isEmpty { tokens.append(.text(pending)); pending = "" } }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                if index + 1 < characters.count, asciiPunctuation.contains(characters[index + 1]) {
                    pending.append(characters[index + 1]); index += 2
                } else { pending.append(character); index += 1 }
            case "`":
                var runEnd = index
                while runEnd < characters.count, characters[runEnd] == "`" { runEnd += 1 }
                let length = runEnd - index
                if let close = closingBackticks(characters, from: runEnd, length: length) {
                    var content = String(characters[runEnd..<close])
                    if content.hasPrefix(" "), content.hasSuffix(" "), content.contains(where: { $0 != " " }) {
                        content = String(content.dropFirst().dropLast())
                    }
                    flush()
                    tokens.append(.styled(content, .code))
                    index = close + length
                } else {
                    pending.append(String(repeating: "`", count: length)); index = runEnd
                }
            case "$":
                if let span = mathSpan(characters, at: index) {
                    flush()
                    tokens.append(.styled(MarkupMath.approximate(span.tex), .math))
                    index = span.end
                } else { pending.append(character); index += 1 }
            case "*", "_", "~":
                var runEnd = index
                while runEnd < characters.count, characters[runEnd] == character { runEnd += 1 }
                let count = runEnd - index
                if character == "~", count != 2 { pending.append(String(repeating: character, count: count)); index = runEnd; continue }
                let previous = index > 0 ? characters[index - 1] : nil
                let next = runEnd < characters.count ? characters[runEnd] : nil
                let (canOpen, canClose) = flanking(character, previous: previous, next: next)
                flush()
                tokens.append(.delimiter(character, count: count, canOpen: canOpen, canClose: canClose))
                index = runEnd
            case "!", "[":
                if let consumed = bracket(characters, at: index, depth: depth, footnotes: &footnotes, into: &tokens, pending: &pending) {
                    index = consumed
                } else { pending.append(character); index += 1 }
            default:
                pending.append(character); index += 1
            }
        }
        flush()
        return tokens
    }

    // MARK: Pieces

    private static func closingBackticks(_ characters: [Character], from start: Int, length: Int) -> Int? {
        var index = start
        while index < characters.count {
            guard characters[index] == "`" else { index += 1; continue }
            var end = index
            while end < characters.count, characters[end] == "`" { end += 1 }
            if end - index == length { return index }
            index = end
        }
        return nil
    }

    /// `$…$` (the Pandoc rules: no space inside the delimiters, and no digit right after the closer)
    /// or `$$…$$` on one line. Returns the TeX source and the index after the closing delimiter.
    private static func mathSpan(_ characters: [Character], at start: Int) -> (tex: String, end: Int)? {
        if start + 1 < characters.count, characters[start + 1] == "$" {
            var index = start + 2
            let limit = min(characters.count, start + 2 + maximumSpanScan)
            while index + 1 < limit {
                if characters[index] == "\\" { index += 2; continue }
                if characters[index] == "$", characters[index + 1] == "$", index > start + 2 {
                    return (String(characters[(start + 2)..<index]), index + 2)
                }
                index += 1
            }
            return nil
        }
        guard start + 1 < characters.count, !characters[start + 1].isWhitespace else { return nil }
        var index = start + 1
        let limit = min(characters.count, start + 1 + maximumSpanScan)
        while index < limit {
            if characters[index] == "\\" { index += 2; continue }
            if characters[index] == "$" {
                if index > start + 1, !characters[index - 1].isWhitespace {
                    let following = index + 1 < characters.count ? characters[index + 1] : nil
                    if following?.isNumber != true { return (String(characters[(start + 1)..<index]), index + 1) }
                }
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func flanking(_ character: Character, previous: Character?, next: Character?) -> (canOpen: Bool, canClose: Bool) {
        let previousSpace = MarkupInline.isWhitespace(previous)
        let nextSpace = MarkupInline.isWhitespace(next)
        let previousPunctuation = MarkupInline.isPunctuation(previous)
        let nextPunctuation = MarkupInline.isPunctuation(next)
        let leftFlanking = !nextSpace && (!nextPunctuation || previousSpace || previousPunctuation)
        let rightFlanking = !previousSpace && (!previousPunctuation || nextSpace || nextPunctuation)
        if character == "_" {
            return (leftFlanking && (!rightFlanking || previousPunctuation), rightFlanking && (!leftFlanking || nextPunctuation))
        }
        return (leftFlanking, rightFlanking)
    }

    /// Handles `[^note]`, `![alt](target)` and `[label](target)`. Returns the next index, or nil
    /// when the bracket is literal text.
    private static func bracket(_ characters: [Character], at start: Int, depth: Int,
                                footnotes: inout MarkupFootnotes, into tokens: inout [MarkupInlineToken],
                                pending: inout String) -> Int? {
        let isImage = characters[start] == "!"
        let open = isImage ? start + 1 : start
        guard open < characters.count, characters[open] == "[" else { return nil }
        guard let close = matchingBracket(characters, from: open) else { return nil }
        let label = Array(characters[(open + 1)..<close])
        if !isImage, label.first == "^", label.count > 1, !label.contains(where: { $0.isWhitespace }) {
            let name = String(label.dropFirst())
            if let number = footnotes.reference(label: name) {
                if !pending.isEmpty { tokens.append(.text(pending)); pending = "" }
                tokens.append(.styled(MarkupFootnotes.superscript(number), .footnoteMark))
                return close + 1
            }
            return nil
        }
        guard close + 1 < characters.count, characters[close + 1] == "(",
              let end = closingParenthesis(characters, from: close + 2) else { return nil }
        let target = String(characters[(close + 2)..<end])
        if !pending.isEmpty { tokens.append(.text(pending)); pending = "" }
        if isImage {
            tokens.append(contentsOf: imageTokens(label: label, target: target, depth: depth, footnotes: &footnotes))
            return end + 1
        }
        if depth < maximumLabelDepth {
            tokens.append(contentsOf: Self.tokens(String(label), footnotes: &footnotes, depth: depth + 1))
        } else {
            tokens.append(.text(String(label)))
        }
        // Link targets are shown as inert text.
        tokens.append(.text(" (" + target + ")"))
        return end + 1
    }

    /// An image becomes one localized marker carrying its description, dimmed like other references that only
    /// point elsewhere. The destination is never shown, followed or kept: it is classified from its spelling so
    /// the status line can say how many images were not loaded. An image without a description draws no marker
    /// but is still counted.
    private static func imageTokens(label: [Character], target: String, depth: Int,
                                    footnotes: inout MarkupFootnotes) -> [MarkupInlineToken] {
        var result: [MarkupInlineToken] = []
        let description: String
        if depth < maximumLabelDepth {
            // The description is plain text: emphasis and code inside it are resolved and their markers dropped.
            let nested = MarkupInline.resolve(Self.tokens(String(label), footnotes: &footnotes, depth: depth + 1), rules: rules)
            description = nested.text
            if !nested.omitted.isEmpty { result.append(.omitted(nested.omitted)) }
        } else {
            description = String(label)
        }
        let shown = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shown.isEmpty {
            result.insert(.styled(PreviewStrings.format(.documentImageMarker, arguments: [shown]), .dimmed), at: 0)
        }
        if let kind = OmittedResourceKind.image(destination: target) { result.append(.omitted(OmittedResources(kind))) }
        return result
    }

    private static func matchingBracket(_ characters: [Character], from open: Int) -> Int? {
        var nesting = 0
        var index = open
        let limit = min(characters.count, open + maximumSpanScan)
        while index < limit {
            switch characters[index] {
            case "\\": index += 1
            case "[": nesting += 1
            case "]":
                nesting -= 1
                if nesting == 0 { return index }
            default: break
            }
            index += 1
        }
        return nil
    }

    private static func closingParenthesis(_ characters: [Character], from start: Int) -> Int? {
        var nesting = 0
        var index = start
        let limit = min(characters.count, start + maximumSpanScan)
        while index < limit {
            switch characters[index] {
            case "\\": index += 1
            case "(": nesting += 1
            case ")":
                if nesting == 0 { return index }
                nesting -= 1
            default: break
            }
            index += 1
        }
        return nil
    }
}
