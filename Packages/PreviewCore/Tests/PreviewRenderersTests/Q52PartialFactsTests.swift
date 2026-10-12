import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q52 partial text facts retain their lower bounds")
struct Q52PartialFactsTests {
    private let english = Locale(identifier: "en_US")

    @Test func recordAndCuePrefixesCannotClaimWholeFileCounts() {
        let inputs: [(FormatID, TextSyntax, String, String)] = [
            (.jsonLines, .json, "{\"a\":1}\n{\"a\":2}\n", "Records: 2"),
            (.subRip, .subRip, "1\n00:00:00,000 --> 00:00:01,000\nSafe\n\n2\n00:00:02,000 --> 00:00:03,000\nCaption\n", "Cues: 2")
        ]
        for (format, syntax, text, expected) in inputs {
            for partial in [false, true] {
                let p = TextPresentation(formatID: format, text: text, lineCount: 2,
                    byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax,
                    sourceRecordCount: 2, truncatedSourceBytes: partial ? 10_000 : nil)
                let modes = SafePreviewModes(p, locale: english)
                let facts = PresentationFactsProvider.facts(for: p, modes: modes)
                #expect(lines(facts).first == expected + (partial ? "+" : ""))
            }
        }
    }

    @Test func cachedOutlinePrefixIsNotAnExactWholeFileNodeCount() {
        let text = "[section]\nname=safe\n"
        let p = TextPresentation(formatID: .plainText, text: text, lineCount: 2, byteCount: text.utf8.count,
            encoding: .utf8, redactionCount: 0, truncatedSourceBytes: 1000)
        var modes = SafePreviewModes(p, locale: english)
        modes.outline = [.init(id: 0, name: "safe", value: "", children: [.init(id: 1, name: "safe", value: "")])]
        #expect(lines(PresentationFactsProvider.facts(for: p, modes: modes)).first == "Nodes: 2+")
    }

    @Test func geometryHeaderUsesOnlyTypedSourceSize() throws {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: .init(minimum: .zero, maximum: SIMD3<Double>(1, 1, 0)), faceCount: 1)
        let p = GeometryPresentation(formatID: .step, mesh: mesh, byteCount: 999,
            facts: PresentationFacts([.shownSize(shown: 4, total: 500)]))
        let facts = PresentationFactsProvider.facts(for: p)
        #expect(facts.facts.contains(.shownSize(shown: 4, total: 500)))
        #expect(!facts.facts.contains(.size(999)))
    }

    private func lines(_ facts: PresentationFacts) -> [String] {
        PresentationFactsFormatter.lines(for: facts, compact: false, locale: english, languagePreferences: ["en"])
    }
}
