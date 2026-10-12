import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 bounded code body lexical tokens")
struct CodeBlockSyntaxTokensTests {
    @Test func languageProfilesDecorateIndependentBodiesAtExactUTF16OffsetsWithoutTouchingProse() {
        let swift = "let value = \"😀\" // comment\n\n"
        let python = "def greet():\n    return \"مرحبا\""
        let text = "😀 e\u{301} before\n" + swift + "prose let fake = 7\n" + python
        let source = text as NSString
        let blocks = [MarkupCodeBlock(range: source.range(of: swift), language: .swift),
                      .init(range: source.range(of: python), language: .python)]
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks)
        for (word, role) in [("let", PreviewSyntaxRole.keyword), ("\"😀\"", .string), ("// comment", .comment),
                             ("def", .keyword), ("return", .keyword), ("\"مرحبا\"", .string)] {
            #expect(tokens.contains(.init(range: source.range(of: word), role: role)))
        }
        #expect(tokens.allSatisfy { token in blocks.contains { NSIntersectionRange($0.range, token.range) == token.range } })
        #expect(tokens.count >= 6 && source.substring(with: blocks[0].range).utf16.elementsEqual(swift.utf16))
    }

    @Test func unknownAliasesNonASCIIAndUnboundedRawLabelsCannotSelectALanguageProfile() {
        let text = "let value = 1", range = NSRange(location: 0, length: text.utf16.count)
        for language in [nil, SourceLanguageID(rawValue: "js"), .init(rawValue: "\u{212A}otlin"),
                         .init(rawValue: "swift\u{E0061}"), .init(rawValue: String(repeating: "x", count: 100))] {
            var calls = 0
            let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: [.init(range: range, language: language)]) { _, _, _ in
                calls += 1; return []
            }
            #expect(tokens.isEmpty && calls == 0)
        }
    }

    @Test func inspectedTokenFreeBodiesConsumeOneSharedUnitAllowance() {
        let text = "      |let later = 1"
        let blocks = [MarkupCodeBlock(range: NSRange(location: 0, length: 6), language: .swift),
                      .init(range: NSRange(location: 7, length: 13), language: .swift)]
        var inspected: [String] = []
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumUTF16Units: 6) { body, _, _ in
            inspected.append(body); return []
        }
        #expect(inspected == ["      "] && tokens.isEmpty)
        #expect(CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumUTF16Units: 0).isEmpty)
        #expect(CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumUTF16Units: Int.max).isEmpty)
    }

    @Test func tokenAllowanceIsCumulativeAcrossFencesRatherThanRestartedPerBody() {
        let text = "let|var|func"
        let blocks = [MarkupCodeBlock(range: NSRange(location: 0, length: 3), language: .swift),
                      .init(range: NSRange(location: 4, length: 3), language: .swift),
                      .init(range: NSRange(location: 8, length: 4), language: .swift)]
        var allowances: [Int] = []
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumTokens: 2) { body, language, maximum in
            allowances.append(maximum)
            return SourceSyntaxTokens.tokens(in: body, syntax: .sourceCode, language: language, maximumTokens: maximum)
        }
        #expect(allowances == [2, 1])
        #expect(tokens == [.init(range: NSRange(location: 0, length: 3), role: .keyword),
                           .init(range: NSRange(location: 4, length: 3), role: .keyword)])
        #expect(CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumTokens: 0).isEmpty)
    }

    @Test func unitTruncationNeverSuppliesAnUnpairedSurrogateOrRebasesBeyondTheBoundedPrefix() {
        let body = "\"😀\" let value = 1", text = "before|" + body + "|var later"
        let start = (text as NSString).range(of: body).location
        let blocks = [MarkupCodeBlock(range: NSRange(location: start, length: body.utf16.count), language: .swift),
                      .init(range: (text as NSString).range(of: "var later"), language: .swift)]
        var inspected: [String] = []
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks, maximumUTF16Units: 2) { prefix, _, _ in
            inspected.append(prefix)
            return [.init(range: NSRange(location: 0, length: prefix.utf16.count), role: .string)]
        }
        #expect(inspected == ["\""])
        #expect(tokens == [.init(range: NSRange(location: start, length: 1), role: .string)])
        #expect(!inspected.contains { $0.contains("\u{FFFD}") })
    }

    @Test func malformedBodyAndTokenRangesCannotSplitScalarsOverflowOrOverlap() {
        let text = "😀let", length = text.utf16.count
        let blocks = [MarkupCodeBlock(range: NSRange(location: NSNotFound, length: Int.max), language: .swift),
                      .init(range: NSRange(location: 1, length: 4), language: .swift),
                      .init(range: NSRange(location: 0, length: length), language: .swift),
                      .init(range: NSRange(location: 2, length: 3), language: .swift)]
        var calls = 0
        let tokens = CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks) { _, _, _ in
            calls += 1
            return [.init(range: NSRange(location: NSNotFound, length: Int.max), role: .string),
                    .init(range: NSRange(location: 0, length: 1), role: .string),
                    .init(range: NSRange(location: 1, length: 1), role: .string),
                    .init(range: NSRange(location: 2, length: 3), role: .keyword),
                    .init(range: NSRange(location: 3, length: 1), role: .literal),
                    .init(range: NSRange(location: length, length: 1), role: .number)]
        }
        #expect(calls == 1 && tokens == [.init(range: NSRange(location: 2, length: 3), role: .keyword)])
    }
}
