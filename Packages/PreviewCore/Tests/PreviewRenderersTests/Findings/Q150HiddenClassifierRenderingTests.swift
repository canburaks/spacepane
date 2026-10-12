import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let q150MarkerControls = Array(UInt32(0xFFF9)...0xFFFB)
    + Array(UInt32(0x1D173)...0x1D17A) + Array(UInt32(0x13430)...0x1343F)

@Suite("Q150 additional hidden Unicode marker mapping")
struct Q150HiddenClassifierRenderingTests {
    @Test(arguments: q150MarkerControls)
    func eachNewControlMapsToItsOwnVisibleMarker(_ value: UInt32) throws {
        let text = "🧭a\(Unicode.Scalar(value)!)b\n"
        let presentation = TextPresentation(formatID: .plainText, text: text, lineCount: 2,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0,
            findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])])
        let result = try #require(SafeInvisibleText.make(for: presentation))
        let marker = "⟨U+\(String(value, radix: 16, uppercase: true))⟩"
        #expect(result.text == "🧭a\(marker)b\n")
        #expect(result.markerRanges == [NSRange(location: 3, length: marker.utf16.count)])
        #expect(LogicalLines.starts(in: result.text).starts.count == 2)
        #expect(presentation.text.utf8.elementsEqual(text.utf8))
    }

    @Test func mongolianSelectorsAndBrailleRunsFollowTheClassifierContext() throws {
        let text = "\u{182C}\u{180F} a\u{180B} ⠁\u{2800}⠃ x\u{2800}\u{2800}y"
        let result = try #require(SafeInvisibleText.derive(from: text))
        #expect(result.text == "\u{182C}\u{180F} a⟨U+180B⟩ ⠁\u{2800}⠃ x⟨U+2800⟩⟨U+2800⟩y")
        #expect(result.markerRanges.count == 3)
        #expect(result.markerRanges.map { (result.text as NSString).substring(with: $0) }
            == ["⟨U+180B⟩", "⟨U+2800⟩", "⟨U+2800⟩"])
    }

    @Test func additionalRangesObeyExistingMarkerBudgets() {
        #expect(SafeInvisibleText.derive(from: "\u{13430}\u{13431}", maximumHiddenScalars: 1) == nil)
        #expect(SafeInvisibleText.derive(from: "\u{FFF9}", maximumUTF8Bytes: 4) == nil)
    }
}
