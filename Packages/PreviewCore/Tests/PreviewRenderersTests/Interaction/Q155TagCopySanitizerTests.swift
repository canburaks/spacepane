import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Q155 copy-only Unicode Tag hygiene")
struct Q155TagCopySanitizerTests {
    private let tag = "\u{E0061}\u{E0062}\u{E007F}"
    private let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

    @Test func absenceOfFindingPreservesExactCodeUnits() {
        let text = "e\u{301}\u{200B}" + tag
        let copy = TagCopySanitizer(safeDisplayedText: text, safetyLensFoundTags: false).wholeText()
        #expect(Array(copy.text.utf16) == Array(text.utf16))
        #expect(copy.removedTagScalarCount == 0 && copy.removedUTF16Ranges.isEmpty)
    }

    @Test func removesOnlyUnsafeTagsAndNeverDecodesTheirPayload() {
        let text = "safe e\u{301}\u{200B}\u{202E}\u{FE0F}" + tag + " end"
        let copy = sanitizer(text).wholeText()
        #expect(Array(copy.text.utf16) == Array("safe e\u{301}\u{200B}\u{202E}\u{FE0F} end".utf16))
        #expect(copy.removedTagScalarCount == 3)
        #expect(!copy.text.contains("ab"))
    }

    @Test func preservesValidFlagBesideUnsafePayloadIncludingPartialSuffix() throws {
        let text = "😀" + flag + " " + tag
        let sanitizer = sanitizer(text)
        #expect(Array(sanitizer.wholeText().text.utf16) == Array(("😀" + flag + " ").utf16))
        let suffix = try #require(sanitizer.selection(6..<16))
        #expect(Array(suffix.text.utf16) == Array((text as NSString).substring(with: NSRange(location: 6, length: 10)).utf16))
        #expect(suffix.removedTagScalarCount == 0)
    }

    @Test func partialUnsafeRunCountsSelectedScalarsAndUsesRelativeRanges() throws {
        let text = "😀x" + tag + "y"
        let copy = try #require(sanitizer(text).selection(5..<10))
        #expect(Array(copy.text.utf16) == Array("y".utf16))
        #expect(copy.removedTagScalarCount == 2)
        #expect(copy.removedUTF16Ranges == [0..<4])
        #expect(sanitizer(text).wholeText().removedUTF16Ranges == [3..<9])
    }

    @Test func independentSelectionsKeepDocumentContextAndDoNotMutateIt() throws {
        let text = flag + " " + tag + " end"
        let sanitizer = sanitizer(text)
        #expect(try #require(sanitizer.selection(2..<14)).removedTagScalarCount == 0)
        #expect(try #require(sanitizer.selection(15..<21)).text.isEmpty)
        #expect(try #require(sanitizer.selection(22..<25)).text == "end")
        #expect(Array(text.utf16) == Array((flag + " " + tag + " end").utf16))
    }

    @Test func malformedFlagsLoseOnlyTheirUnsafeTags() {
        let malformed = "\u{1F3F4}\u{E0067}\u{E0062}" + " text"
        let copy = sanitizer(malformed).wholeText()
        #expect(Array(copy.text.utf16) == Array("\u{1F3F4} text".utf16))
        #expect(copy.removedTagScalarCount == 2)
    }

    @Test func rowAndCellContextDoesNotAllowOneCellToCompleteAnotherFlag() {
        let text = "\u{1F3F4}\t" + tag + "\n" + flag
        let copy = sanitizer(text).wholeText()
        #expect(Array(copy.text.utf16) == Array(("\u{1F3F4}\t\n" + flag).utf16))
        #expect(copy.removedTagScalarCount == 3)
    }

    @Test func emptyAndInvalidSelectionsAreExplicit() throws {
        let sanitizer = sanitizer("😀" + tag)
        #expect(try #require(sanitizer.selection(2..<2)).text.isEmpty)
        #expect(sanitizer.selection(-1..<2) == nil)
        #expect(sanitizer.selection(0..<9) == nil)
        #expect(sanitizer.selection(1..<2) == nil)
        #expect(sanitizer.selection(2..<3) == nil)
    }

    @Test func removingTagsIsIdempotentAndHandlesBoundedLargeRuns() {
        let text = "prefix" + String(repeating: "\u{E0061}", count: 8192) + "suffix"
        let first = sanitizer(text).wholeText()
        #expect(Array(first.text.utf16) == Array("prefixsuffix".utf16))
        #expect(first.removedTagScalarCount == 8192)
        #expect(first.removedUTF16Ranges == [6..<16390])
        let second = sanitizer(first.text).wholeText()
        #expect(Array(second.text.utf16) == Array(first.text.utf16) && second.removedTagScalarCount == 0)
    }

    private func sanitizer(_ text: String) -> TagCopySanitizer {
        .init(safeDisplayedText: text, safetyLensFoundTags: true)
    }
}
