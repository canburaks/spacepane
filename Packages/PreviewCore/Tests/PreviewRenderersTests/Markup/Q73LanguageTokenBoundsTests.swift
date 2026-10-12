import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 code highlighting stays inside token bounds")
struct Q73LanguageTokenBoundsTests {
    /// Every language comments, quotes and numbers somehow; one body with all the common forms and an emoji, so a
    /// profile that splits a surrogate pair or runs past its body is caught whatever its syntax.
    private let universal = "value = 1 // c1\n\"s😀\" 12 /* c2 */ # c3\n-- c4\n<!-- c5 -->\n'q' ; 0x1F + 3.5e2"

    nonisolated static let commentCases: [(SourceLanguageID, String)] = [
        (.swift, "// note"), (.rust, "// note"), (.go, "// note"), (.java, "// note"), (.kotlin, "// note"),
        (.csharp, "// note"), (.c, "// note"), (.cpp, "// note"), (.javascript, "// note"), (.typescript, "// note"),
        (.python, "# note"), (.ruby, "# note"), (.php, "# note"), (.julia, "# note"), (.r, "# note"),
        (.perl, "# note"), (.awk, "# note"), (.lua, "-- note"), (.haskell, "-- note")
    ]

    private func block(_ text: String, _ language: SourceLanguageID?) -> MarkupCodeBlock {
        MarkupCodeBlock(range: NSRange(location: 0, length: text.utf16.count), language: language)
    }

    @Test func everyCanonicalLanguageHasALexicalProfile() {
        for language in SourceLanguageID.all {
            #expect(SourceLanguageProfiles.profile(for: language) != nil, "\(language.rawValue)")
        }
    }

    @Test func tokensOfEveryLanguageStayInsideTheirBodyInOrderWithoutOverlapOrASplitScalar() {
        let prose = "prose before 😀\n", after = "\nprose after"
        let text = prose + universal + after
        let source = text as NSString
        let body = NSRange(location: prose.utf16.count, length: universal.utf16.count)
        for language in SourceLanguageID.all {
            let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: [.init(range: body, language: language)])
            var previousEnd = body.location
            for token in tokens {
                let end = NSMaxRange(token.range)
                #expect(token.range.length > 0 && token.range.location >= previousEnd && end <= NSMaxRange(body),
                        "\(language.rawValue) \(token.range)")
                // Both ends fall on scalar boundaries: no low surrogate starts or ends a token.
                if token.range.location < source.length {
                    #expect(!(0xDC00...0xDFFF).contains(source.character(at: token.range.location)))
                }
                if end < source.length { #expect(!(0xDC00...0xDFFF).contains(source.character(at: end))) }
                previousEnd = end
            }
            #expect(tokens.count <= CodeBlockSyntaxTokens.tokenBudget)
        }
    }

    @Test(arguments: commentCases)
    func eachLanguageHintFindsItsOwnCommentFormExactlyAndNoOtherHintDoes(language: SourceLanguageID, comment: String) {
        let text = "value = 1 " + comment
        let expected = (text as NSString).range(of: comment)
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: [block(text, language)])
        #expect(tokens.contains(.init(range: expected, role: .comment)), "\(language.rawValue)")
        // Without a hint nothing is highlighted: an unlabeled or unknown fence is plain text.
        #expect(CodeBlockSyntaxTokens.tokens(in: text, blocks: [block(text, nil)]).isEmpty)
        #expect(CodeBlockSyntaxTokens.tokens(in: text, blocks: [block(text, .init(rawValue: "js"))]).isEmpty)
    }

    @Test func totalCodeScannedNeverExceedsTheUnitBudgetNoMatterHowManyBodiesThereAre() {
        let body = String(repeating: "a", count: 199) + "\n"
        var text = "", blocks: [MarkupCodeBlock] = []
        for _ in 0..<2_000 {
            blocks.append(.init(range: NSRange(location: text.utf16.count, length: 200), language: .swift))
            text += body
        }
        #expect(text.utf16.count > CodeBlockSyntaxTokens.unitBudget)
        var scanned = 0, calls = 0
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks) { prefix, _, _ in
            scanned += prefix.utf16.count; calls += 1
            return []
        }
        #expect(scanned == CodeBlockSyntaxTokens.unitBudget && tokens.isEmpty)
        #expect(calls <= CodeBlockSyntaxTokens.unitBudget / 200 + 1)
    }

    @Test func totalTokensNeverExceedTheTokenBudgetNoMatterHowManyBodiesProduceThem() {
        let body = "0123456789"
        var text = "", blocks: [MarkupCodeBlock] = []
        for _ in 0..<10_000 {
            blocks.append(.init(range: NSRange(location: text.utf16.count, length: 10), language: .swift))
            text += body
        }
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks) { _, _, maximum in
            // Five one-unit tokens per body, as many as the allowance still permits.
            (0..<min(5, maximum)).map { JSONSyntaxToken(range: NSRange(location: $0 * 2, length: 1), role: .keyword) }
        }
        #expect(tokens.count == CodeBlockSyntaxTokens.tokenBudget)
        #expect(tokens.allSatisfy { $0.range.length == 1 && $0.range.location + 1 <= text.utf16.count })
    }

    @Test func aRealLexerOverAThousandBodiesKeepsEveryTokenInsideItsBodyAndWithinBothBudgets() {
        let body = "func f() { let x = \"s\" // c\n return 12 }\n"
        var text = "", blocks: [MarkupCodeBlock] = []
        for _ in 0..<3_000 {
            blocks.append(.init(range: NSRange(location: text.utf16.count, length: body.utf16.count), language: .swift))
            text += body + "\n"
        }
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks)
        #expect(!tokens.isEmpty && tokens.count <= CodeBlockSyntaxTokens.tokenBudget)
        // The bodies repeat at a fixed stride (the body and one blank line), so a token's body is its quotient.
        let stride = body.utf16.count + 1
        for token in tokens {
            let start = token.range.location / stride * stride
            #expect(token.range.location >= start && NSMaxRange(token.range) <= start + body.utf16.count)
        }
    }

    @Test func theBudgetsAreTheNamedConstantsAndTheDefaultsUseThem() {
        #expect(CodeBlockSyntaxTokens.unitBudget == 262_144 && CodeBlockSyntaxTokens.tokenBudget == 20_000)
        let text = "let a = 1"
        var allowances: [Int] = []
        _ = CodeBlockSyntaxTokens.tokens(in: text, blocks: [block(text, .swift)]) { _, _, maximum in
            allowances.append(maximum); return []
        }
        #expect(allowances == [CodeBlockSyntaxTokens.tokenBudget])
    }
}
