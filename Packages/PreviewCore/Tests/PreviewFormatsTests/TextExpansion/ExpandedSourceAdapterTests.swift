import Foundation
import Testing
import PreviewContracts
import PreviewFormats

@Suite("Expanded safe text adapters")
struct ExpandedSourceAdapterTests {
    @Test func codeRetainsUnicodeSourceAndSuppliesSyntax() throws {
        let text = "// 😀 Unicode\nlet password = \"synthetic-only\"\nlet number = 42"
        let result = try SourceCodeAdapter().parse(.init(text: text, encoding: .utf8, byteCount: text.utf8.count), context: .init(budget: .standard))
        #expect(result.text == text)
        #expect(result.syntax.rawValue == "sourceCode")
    }

    @Test func markdownRetainsRawSourceForSafeSourceMode() throws {
        let text = "# Heading\n\n**strong** and [inert](https://example.invalid)"
        let result = try MarkdownSourceAdapter().parse(.init(text: text, encoding: .utf8, byteCount: text.utf8.count), context: .init(budget: .standard))
        #expect(result.text == text)
        #expect(result.syntax.rawValue == "markdown")
    }

    @Test func directAdaptersRespectInputAndLineBudgets() {
        let input = DecodedText(text: String(repeating: "a", count: 65), encoding: .utf8, byteCount: 65)
        #expect(throws: PreviewFailure.inputTooLarge) { try SourceCodeAdapter().parse(input, context: .init(budget: .init(maxInputBytes: 64))) }
        #expect(throws: PreviewFailure.lineTooLong) { try MarkdownSourceAdapter().parse(input, context: .init(budget: .init(maxLineUTF8Bytes: 64))) }
        let lines = DecodedText(text: "one\r\ntwo\rthree", encoding: .utf8, byteCount: 14)
        #expect(throws: PreviewFailure.tooManyLines) { try SourceCodeAdapter().parse(lines, context: .init(budget: .init(maxTextLines: 2))) }
    }
}
