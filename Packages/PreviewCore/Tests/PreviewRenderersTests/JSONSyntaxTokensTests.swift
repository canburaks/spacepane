import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Bounded JSON decoration")
struct JSONSyntaxTokensTests {
    @Test func rolesAndUTF16RangesIncludeNonBMPText() {
        let text = #"{"😀key":"👩🏽‍💻", "n":-12.5e+2, "flags":[true,false,null]}"#
        let tokens = JSONSyntaxTokens.tokens(in: text)
        #expect(tokens.map(\.role) == [.key, .string, .key, .number, .key, .literal, .literal, .literal])
        let source = text as NSString
        #expect(tokens.map { source.substring(with: $0.range) } == [
            #""😀key""#, #""👩🏽‍💻""#, #""n""#, "-12.5e+2", #""flags""#, "true", "false", "null"
        ])
        #expect(tokens[1].range == source.range(of: #""👩🏽‍💻""#))
        #expect(tokens[3].range == source.range(of: "-12.5e+2"))
    }

    @Test func escapedQuotesAndBackslashesStayInsideStrings() {
        let text = #"{"a\"b":"quote \" and slash \\ and \u1234","value":"[true,123]"}"#
        let tokens = JSONSyntaxTokens.tokens(in: text)
        #expect(tokens.map(\.role) == [.key, .string, .key, .string])
        let source = text as NSString
        #expect(source.substring(with: tokens[0].range) == #""a\"b""#)
        #expect(source.substring(with: tokens[1].range) == #""quote \" and slash \\ and \u1234""#)
        #expect(source.substring(with: tokens[3].range) == #""[true,123]""#)
    }

    @Test func malformedCandidatesDoNotBecomePartialNumbersOrLiterals() {
        #expect(JSONSyntaxTokens.tokens(in: "[01, 1., 1e+, truex, -]").isEmpty)
        let text = #"{"good":1,"unterminated":"abc\"#
        let tokens = JSONSyntaxTokens.tokens(in: text)
        #expect(tokens.map(\.role) == [.key, .number, .key])
        #expect(tokens.allSatisfy { NSMaxRange($0.range) <= text.utf16.count })
    }

    @Test func excessiveLengthOrTokenCountFallsBackToPlainDecoration() {
        #expect(!JSONSyntaxTokens.tokens(in: "[1,2]", maximumUTF16Units: 5).isEmpty)
        #expect(JSONSyntaxTokens.tokens(in: "[1,2]", maximumUTF16Units: 4).isEmpty)
        #expect(JSONSyntaxTokens.tokens(in: "[1,2,3]", maximumTokens: 2).isEmpty)
        #expect(JSONSyntaxTokens.tokens(in: "[1,2]", maximumTokens: 2).count == 2)
        #expect(JSONSyntaxTokens.tokens(in: "[1]", maximumUTF16Units: 0).isEmpty)
        #expect(JSONSyntaxTokens.tokens(in: "[1]", maximumTokens: 0).isEmpty)
        let huge = String(repeating: "1", count: 100_000)
        let bounded = JSONSyntaxTokens.scan(in: huge, maximumUTF16Units: 64)
        #expect(bounded.tokens.isEmpty)
        #expect(bounded.visitedUTF16Units == 65)
    }

    @Test func invalidDigitRunHasLinearVisitedWork() {
        for suffix in ["x", "e+", "."] {
            let text = String(repeating: "1", count: 32_000) + suffix
            let result = JSONSyntaxTokens.scan(in: text)
            #expect(result.tokens.isEmpty)
            #expect(result.visitedUTF16Units <= text.utf16.count * 8)
        }
    }
}
