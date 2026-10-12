import Foundation
import Testing
import PreviewContracts
@testable import PreviewCore

private let q150AdditionalControls = Array(UInt32(0xFFF9)...0xFFFB)
    + Array(UInt32(0x1D173)...0x1D17A) + Array(UInt32(0x13430)...0x1343F)
private let q150MongolianSelectors: [UInt32] = [0x180B, 0x180C, 0x180D, 0x180F]

private struct Q150ClassifierReader: PreviewFileReading {
    let text: String
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: Data(text.utf8)) }
}

private struct Q150ClassifierAdapter: FormatAdapter {
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: input.text)
    }
}

@Suite("Q150 additional hidden Unicode ranges")
struct Q150HiddenClassifierTests {
    @Test(arguments: q150AdditionalControls)
    func formattingControlsHaveExactRangesWithoutAnotherHiddenScalar(_ value: UInt32) {
        let scalar = Unicode.Scalar(value)!, text = "🧭a\(scalar)b"
        #expect(HiddenCharacters.spans(in: text) == [
            HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 3..<(3 + scalar.utf16.count), scalarCount: 1)
        ])
    }

    @Test(arguments: q150MongolianSelectors)
    func mongolianSelectorsAreHiddenOutsideTheirLetterContext(_ value: UInt32) {
        let scalar = Unicode.Scalar(value)!
        #expect(HiddenCharacters.spans(in: "a\(scalar)b") == [
            HiddenCharacterSpan(kind: .variationSelector, utf16Range: 1..<2, scalarCount: 1)
        ])
        // QA has standardized forms for all four selectors; their characters remain exact.
        #expect(HiddenCharacters.spans(in: "\u{182C}\(scalar)\u{1820}").isEmpty)
        for prefix in ["", " ", "\u{180A}", "\u{1810}", "\u{1885}", "\u{182C}\n"] {
            let text = prefix + String(scalar)
            #expect(HiddenCharacters.spans(in: text) == [
                HiddenCharacterSpan(kind: .variationSelector,
                                    utf16Range: prefix.utf16.count..<text.utf16.count, scalarCount: 1)
            ])
        }
    }

    @Test func stackedSelectorsRemainHiddenEvenAfterAMongolianLetter() {
        #expect(HiddenCharacters.spans(in: "\u{182C}\u{180B}\u{180F}\u{FE01}\u{E0100}x") == [
            HiddenCharacterSpan(kind: .variationSelector, utf16Range: 1..<6, scalarCount: 4)
        ])
    }

    @Test func brailleBlankRequiresAContiguousRunOfAtLeastTwo() {
        #expect(HiddenCharacters.spans(in: "a\u{2800}b").isEmpty)
        #expect(HiddenCharacters.spans(in: "⠁\u{2800}⠃").isEmpty)
        #expect(HiddenCharacters.spans(in: "😀a\u{2800}\u{2800}b\u{2800}x") == [
            HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 3..<5, scalarCount: 2)
        ])
        #expect(HiddenCharacters.spans(in: "\u{2800}\n\u{2800}").isEmpty)
    }

    @Test func nearbyVisibleScalarsAreNotClassifiedByBroadBlockMembership() {
        for value: UInt32 in [0xFFF8, 0xFFFC, 0x1D172, 0x1D17B, 0x1342F, 0x13440, 0x2801, 0x180A, 0x1810] {
            #expect(HiddenCharacters.spans(in: "a\(Unicode.Scalar(value)!)b").isEmpty)
        }
    }

    @Test func validScriptEmojiFlagAndDirectionContextsRemainUnmarked() {
        let text = "\u{182C}\u{180F} ❤\u{FE0F} 👩\u{200D}💻 क्\u{200D}ष می\u{200C}خواهم 葛\u{E0100}\n"
            + "שלום\u{200F} مرحبا\u{061C} \u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        #expect(HiddenCharacters.spans(in: text).isEmpty)
    }

    @Test func theActualPipelineFindingsCountOnlyConcealedDisplayedCharacters() async throws {
        let text = "password=synthetic\u{FFF9}credential\nVisible\u{1D173}\u{13430}\u{FFF9}\n"
            + "Latin\u{180B}\nBlank\u{2800}\u{2800}\n\u{182C}\u{180F}\n"
        let pipeline = PreviewPipeline(registrations: [AdapterRegistration(formatID: .plainText) { Q150ClassifierAdapter() }],
                                       reader: Q150ClassifierReader(text: text))
        let result = await pipeline.preview(url: URL(fileURLWithPath: "/fixtures/synthetic.txt"))
        guard case .ready(let presentation) = result else { Issue.record("No source preview"); return }
        #expect(presentation.text == "password=••••\nVisible\u{1D173}\u{13430}\u{FFF9}\n"
            + "Latin\u{180B}\nBlank\u{2800}\u{2800}\n\u{182C}\u{180F}\n")
        let zeroWidth = try #require(presentation.findings.first { $0.kind == .hiddenZeroWidth })
        #expect(zeroWidth.count == 5 && zeroWidth.lines == [2, 4] && zeroWidth.detail == .none)
        let variation = try #require(presentation.findings.first { $0.kind == .hiddenVariationSelectors })
        #expect(variation.count == 1 && variation.lines == [3] && variation.detail == .none)
    }

    @Test func aLargeNewControlRunRetainsCheckpointCancellation() {
        struct Stop: Error {}
        let text = String(repeating: "\u{13430}", count: 20_000)
        var calls = 0
        #expect(throws: Stop.self) {
            _ = try HiddenCharacters.spans(in: text) {
                calls += 1
                if calls == 3 { throw Stop() }
            }
        }
        #expect(calls == 3)
    }
}
