import Foundation
import Testing
import PreviewContracts
import PreviewCore

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

private struct FindingAdapter: FormatAdapter {
    let findings: [PreviewFinding]
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: input.text, findings: findings)
    }
}

private struct FindingPrivacy: PreviewPrivacyFiltering {
    let findings: [PreviewFinding]
    func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText {
        SafeText(text: document.text, redactionCount: 0, syntax: document.syntax, findings: findings)
    }
}

@Suite("Typed findings contract")
struct FindingsContractTests {
    @Test func initializerKeepsCountsPositiveAndLinesOrderedUniqueAndBounded() {
        let finding = PreviewFinding(kind: .hiddenZeroWidth, count: 0, lines: [9, 3, 3, -1, 0] + Array(100...200))
        #expect(finding.count == 1)
        #expect(finding.lines.prefix(2) == [3, 9])
        #expect(finding.lines.count == PreviewFinding.maximumLines)
        #expect(finding.lines == finding.lines.sorted())
        #expect(finding.severity == PreviewFindingKind.hiddenZeroWidth.defaultSeverity)
        #expect(PreviewFinding(kind: .hiddenZeroWidth, severity: .warning, count: 2).severity == .warning)
    }

    @Test func detailsAreBoundedBeforeTheyReachPresentation() {
        let cells = PreviewFinding(kind: .notebookErrorOutputs, count: 3, detail: .cells([5, 2, 2, 0] + Array(10...100)))
        guard case .cells(let values) = cells.detail else { Issue.record("cells detail"); return }
        #expect(values.prefix(2) == [2, 5])
        #expect(values.count == PreviewFinding.maximumDetailValues)
        let sequence = PreviewFinding(kind: .notebookOutOfOrder, count: 1, detail: .executionSequence(Array(1...100)))
        guard case .executionSequence(let steps) = sequence.detail else { Issue.record("sequence detail"); return }
        #expect(steps.count == PreviewFinding.maximumDetailValues)
        let text = PreviewFinding(kind: .hiddenUnicodeTags, count: 1, detail: .decodedText(String(repeating: "x", count: 5_000)))
        guard case .decodedText(let decoded) = text.detail else { Issue.record("decoded detail"); return }
        #expect(decoded.count == PreviewFinding.maximumDecodedCharacters)
        #expect(PreviewFinding(kind: .archiveLargeExpansion, count: 1, detail: .expandedBytes(-5)).detail == .expandedBytes(0))
    }

    @Test func decodedTextComparesExactCodeUnits() {
        let composed = PreviewFinding(kind: .hiddenUnicodeTags, count: 1, detail: .decodedText("caf\u{E9}"))
        let decomposed = PreviewFinding(kind: .hiddenUnicodeTags, count: 1, detail: .decodedText("cafe\u{301}"))
        #expect("caf\u{E9}" == "cafe\u{301}")
        #expect(composed != decomposed)
    }

    @Test func normalizationMergesKindsAndOrdersBySeverityThenDeclaration() {
        let findings = PreviewFindings.normalized([
            PreviewFinding(kind: .secretAPIKey, count: 1, lines: [4]),
            PreviewFinding(kind: .hiddenZeroWidth, count: 2, lines: [8]),
            PreviewFinding(kind: .archiveUnsafePath, count: 1),
            PreviewFinding(kind: .hiddenZeroWidth, severity: .warning, count: 3, lines: [2, 8]),
            PreviewFinding(kind: .secretAPIKey, count: 2, lines: [1])
        ])
        #expect(findings.map(\.kind) == [.archiveUnsafePath, .hiddenZeroWidth, .secretAPIKey])
        #expect(findings[1].count == 5)
        #expect(findings[1].lines == [2, 8])
        #expect(findings[1].severity == .warning)
        #expect(findings[2].count == 3)
        #expect(findings[2].lines == [1, 4])
    }

    @Test func normalizationKeepsTheMostSeriousFindingsWithinTheBound() {
        let all = PreviewFindingKind.allCases.map { PreviewFinding(kind: $0, count: 1) }
        let findings = PreviewFindings.normalized(all.reversed())
        #expect(findings.count == min(all.count, PreviewFindings.maximumCount))
        #expect(findings.map(\.severity) == findings.map(\.severity).sorted(by: >))
        #expect(findings.filter { $0.severity == .warning }.count == all.filter { $0.severity == .warning }.count)
        #expect(PreviewFindings.normalized([PreviewFinding(kind: .secretAPIKey, count: .max),
                                           PreviewFinding(kind: .secretAPIKey, count: .max)]).first?.count == .max)
    }

    @Test func findingLinesUseTheGutterDefinitionOfALogicalLine() {
        // CRLF is one break; CR, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR each break; a
        // supplementary-plane scalar is two UTF-16 units.
        let text = "a\r\nb\rc\u{85}d\u{2028}e\u{2029}😀f\n"
        let offsets = [0, 3, 5, 7, 9, 11, 13, 14, 15]
        #expect(LogicalLines.lineNumbers(forUTF16Offsets: offsets, in: text) == [1, 2, 3, 4, 5, 6, 6, 6, 7])
        #expect(LogicalLines.starts(in: "").starts.isEmpty)
        #expect(LogicalLines.lineNumbers(forUTF16Offsets: [0, 99], in: "x") == [1])
    }

    @Test func pipelineCarriesAdapterAndPrivacyFindingsIntoThePresentation() async {
        let pipeline = PreviewPipeline(
            registrations: [AdapterRegistration(formatID: .plainText) {
                FindingAdapter(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [1])])
            }],
            reader: BytesReader(data: Data("first\nsecond\n".utf8)),
            privacy: FindingPrivacy(findings: [PreviewFinding(kind: .secretAPIKey, count: 1, lines: [2]),
                                               PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [2])]))
        let outcome = await pipeline.preview(url: URL(fileURLWithPath: "/unused/notes.txt"))
        guard case .ready(let presentation) = outcome else { Issue.record("expected ready: \(outcome)"); return }
        #expect(presentation.findings.map(\.kind) == [.hiddenZeroWidth, .secretAPIKey])
        #expect(presentation.findings.first?.count == 2)
        #expect(presentation.findings.first?.lines == [1, 2])
    }

    @Test func disabledTypesProduceNoFindingsBecauseNoAdapterRuns() async {
        let pipeline = PreviewPipeline(
            registrations: [AdapterRegistration(formatID: .plainText) {
                FindingAdapter(findings: [PreviewFinding(kind: .hiddenZeroWidth, count: 1)])
            }],
            reader: BytesReader(data: Data("text".utf8)))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .plainText)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/notes.txt"), preferences: preferences)
                == .disabledByUser(.plainText))
    }
}
