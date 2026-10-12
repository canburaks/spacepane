import Foundation

/// One lexical piece of an inline run. Dialect tokenizers (Markdown, AsciiDoc, reStructuredText,
/// Org) split a line into these pieces; `MarkupInline.resolve` then pairs emphasis delimiters the
/// same way for every dialect.
enum MarkupInlineToken: Equatable, Sendable {
    case text(String)
    /// A span with a fixed style that is never matched against delimiters, such as code or math.
    case styled(String, MarkdownDecoration.Style)
    /// A run of one delimiter character with its flanking facts, decided by the dialect.
    case delimiter(Character, count: Int, canOpen: Bool, canClose: Bool)
    /// References the tokenizer left as inert text, such as an image destination. It adds no text, only a count
    /// for the offline notice.
    case omitted(OmittedResources)
}

/// The emphasis styles a delimiter character can open, by matched run length.
struct MarkupDelimiterRule: Sendable {
    let styles: [Int: MarkdownDecoration.Style]
    var maximumLength: Int { styles.keys.max() ?? 0 }
}

enum MarkupInline {
    /// Total pairing steps for one line; beyond it the remaining delimiters stay literal. Pairing
    /// is linear in practice (each closer inspects only the stack of its own character), so this
    /// only bounds adversarial lines.
    static let maximumPairingSteps = 400_000

    /// Pairs delimiter runs with one stack per delimiter character (the strategy of CommonMark's
    /// delimiter algorithm, without its rule of three) and emits the text with its decorations.
    /// Unmatched delimiters stay literal; matched ones are consumed from the inner side of their runs.
    static func resolve(_ tokens: [MarkupInlineToken], rules: [Character: MarkupDelimiterRule]) -> MarkupInlineResult {
        var remaining = [Int](repeating: 0, count: tokens.count)
        var pairs: [(opener: Int, closer: Int, style: MarkdownDecoration.Style)] = []
        for (index, token) in tokens.enumerated() {
            if case .delimiter(_, let count, _, _) = token { remaining[index] = count }
        }
        var stacks: [Character: [Int]] = [:]
        var steps = 0
        for (index, token) in tokens.enumerated() {
            guard case .delimiter(let character, _, let canOpen, let canClose) = token,
                  let rule = rules[character], steps < maximumPairingSteps else { continue }
            if canClose, var stack = stacks.removeValue(forKey: character) {
                var position = stack.count - 1
                while position >= 0, remaining[index] > 0, steps < maximumPairingSteps {
                    steps += 1
                    let opener = stack[position]
                    let openerLeft = remaining[opener]
                    var length = min(openerLeft, remaining[index], rule.maximumLength)
                    while length > 0, rule.styles[length] == nil { length -= 1 }
                    guard openerLeft > 0, length > 0, let style = rule.styles[length] else { position -= 1; continue }
                    pairs.append((opener, index, style))
                    remaining[opener] = openerLeft - length
                    remaining[index] -= length
                    // Openers between this pair and its closer never matched; they stay literal.
                    if position + 1 < stack.count { stack.removeSubrange((position + 1)...) }
                    if remaining[opener] == 0 { stack.remove(at: position) }
                    position = stack.count - 1
                }
                stacks[character] = stack
            }
            if canOpen, remaining[index] > 0 { stacks[character, default: []].append(index) }
        }
        var text = ""
        var offset = 0
        var starts: [Int] = []
        var ends: [Int] = []
        var decorations: [MarkdownDecoration] = []
        var omitted = OmittedResources()
        for (index, token) in tokens.enumerated() {
            starts.append(offset)
            let piece: String
            switch token {
            case .omitted(let resources):
                omitted.add(resources)
                piece = ""
            case .text(let value): piece = value
            case .styled(let value, let style):
                if !value.isEmpty { decorations.append(.init(range: NSRange(location: offset, length: value.utf16.count), style: style)) }
                piece = value
            case .delimiter(let character, _, _, _):
                piece = String(repeating: character, count: remaining[index])
            }
            text.append(piece)
            offset += piece.utf16.count
            ends.append(offset)
        }
        for pair in pairs {
            let range = NSRange(location: ends[pair.opener], length: starts[pair.closer] - ends[pair.opener])
            if range.length > 0 { decorations.append(.init(range: range, style: pair.style)) }
        }
        return MarkupInlineResult(text: text, decorations: decorations, omitted: omitted)
    }

    // MARK: Flanking helpers shared by dialect tokenizers

    static func isWhitespace(_ character: Character?) -> Bool { character?.isWhitespace ?? true }

    static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }

    /// Punctuation or symbol, using Unicode categories rather than an ASCII list.
    static func isPunctuation(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isPunctuation || character.isSymbol
    }
}
