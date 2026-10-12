import Foundation
import PreviewContracts

/// A shared bounded allowance decorates exact safe bodies. Only ranges/roles leave this scan.
enum CodeBlockSyntaxTokens {
    typealias Tokenizer = (String, SourceLanguageID, Int) -> [JSONSyntaxToken]

    /// The most code, in UTF-16 units across every body of a document, that is scanned for highlighting. A document the
    /// renderer accepts is at most this long, so ordinary documents are highlighted whole; a body past the budget is
    /// shown plain and costs nothing more.
    static let unitBudget = 262_144
    /// The most tokens a document keeps, however its bodies split them.
    static let tokenBudget = 20_000

    static func tokens(in text: String, blocks: [MarkupCodeBlock],
                       maximumUTF16Units: Int = CodeBlockSyntaxTokens.unitBudget,
                       maximumTokens: Int = CodeBlockSyntaxTokens.tokenBudget,
                       tokenizer: Tokenizer = lexicalTokens) -> [JSONSyntaxToken] {
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumTokens > 0 else { return [] }
        let source = text as NSString
        var unitsRemaining = maximumUTF16Units, tokensRemaining = maximumTokens, lastBodyEnd = 0
        var result: [JSONSyntaxToken] = []
        for block in blocks {
            guard unitsRemaining > 0, tokensRemaining > 0 else { break }
            let range = block.range
            guard range.location >= lastBodyEnd, range.location != NSNotFound, range.location <= source.length,
                  range.length > 0, range.length <= source.length - range.location,
                  scalarBoundary(range.location, in: source), scalarBoundary(range.location + range.length, in: source) else { continue }
            lastBodyEnd = range.location + range.length
            guard let language = block.language, SourceLanguageProfiles.profile(for: language) != nil else { continue }
            let requested = min(range.length, unitsRemaining)
            var count = requested
            if (0xD800...0xDBFF).contains(source.character(at: range.location + count - 1)) { count -= 1 }
            // An inspected boundary unit still consumes budget even when avoiding a split leaves no body.
            unitsRemaining -= requested
            guard count > 0 else { continue }
            let body = source.substring(with: NSRange(location: range.location, length: count))
            let tokens = tokenizer(body, language, tokensRemaining)
            var lastTokenEnd = 0
            for token in tokens.prefix(tokensRemaining) {
                let local = token.range
                guard local.location >= lastTokenEnd, local.location != NSNotFound, local.location <= count,
                      local.length > 0, local.length <= count - local.location,
                      scalarBoundary(range.location + local.location, in: source),
                      scalarBoundary(range.location + local.location + local.length, in: source) else { continue }
                lastTokenEnd = local.location + local.length
                result.append(.init(range: NSRange(location: range.location + local.location, length: local.length), role: token.role))
            }
            tokensRemaining -= min(tokens.count, tokensRemaining)
        }
        return result
    }

    private static func scalarBoundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        return !(0xDC00...0xDFFF).contains(source.character(at: offset))
    }

    private static func lexicalTokens(_ text: String, _ language: SourceLanguageID, _ maximumTokens: Int) -> [JSONSyntaxToken] {
        SourceSyntaxTokens.tokens(in: text, syntax: .sourceCode, language: language,
                                  maximumUTF16Units: text.utf16.count, maximumTokens: maximumTokens)
    }
}
