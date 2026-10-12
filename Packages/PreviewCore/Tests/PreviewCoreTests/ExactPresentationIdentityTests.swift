import Testing
import PreviewContracts

@Suite("Exact safe presentation identity")
struct ExactPresentationIdentityTests {
    private func presentation(_ text: String) -> TextPresentation {
        .init(formatID: .json, text: text, lineCount: 1, byteCount: 128,
              encoding: .utf8, redactionCount: 0, syntax: .json)
    }

    @Test func canonicallyEquivalentSourceStillInvalidatesDisplayAndDerivedModels() {
        let composed = presentation("{\"word\":\"caf\u{00e9}\"}")
        let decomposed = presentation("{\"word\":\"cafe\u{0301}\"}")
        #expect(composed.text == decomposed.text)
        #expect(!composed.text.utf16.elementsEqual(decomposed.text.utf16))
        #expect(composed != decomposed)
        #expect(PreviewOutcome.ready(composed) != .ready(decomposed))
        #expect(PreviewResult(outcome: .ready(composed)) != PreviewResult(outcome: .ready(decomposed)))
    }

    @Test func identicalSourceAndMetadataRemainEqual() {
        let first = presentation("{\"word\":\"cafe\u{0301}\"}")
        let copy = presentation(String(decoding: Array(first.text.utf8), as: UTF8.self))
        #expect(first == copy)
        #expect(PreviewResult(outcome: .ready(first), effectiveBudget: .standard)
                == PreviewResult(outcome: .ready(copy), effectiveBudget: .standard))
    }
}
