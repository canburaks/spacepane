import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Quick win 4 of the 2026-10-14 list (owner answer D-chrome, 2026-10-06): provenance notes leave the status line under
/// the header and appear in the information panel; limits stay in the strip at the bottom.
@Suite("Provenance notes in the information panel", .serialized)
@MainActor
struct TqInteractionProvenanceTests {
    private let english = Locale(identifier: "en")

    private func presentation(_ text: String = "safe", format: FormatID = .plainText, syntax: TextSyntax = .plain,
                              redactions: Int = 0, truncatedSourceBytes: Int? = nil,
                              isReformatted: Bool = false) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                         redactionCount: redactions, syntax: syntax, truncatedSourceBytes: truncatedSourceBytes,
                         isReformatted: isReformatted)
    }

    private func harness() -> InteractionHarness {
        let host = InteractionHarness()
        host.view.chromeScheduler = ManualChromeScheduler()
        return host
    }

    /// Opens the information panel as its badge does and returns the lines it shows.
    private func openedPanelLines(_ host: InteractionHarness) -> [String] {
        host.view.refreshInfoPanel(forOpening: true)
        host.view.infoPanel.setExpanded(true)
        return host.view.infoPanel.lines
    }

    @Test func aReformattedAndTruncatedPreviewShowsTheNoteInThePanelAndTheLimitInTheStrip() {
        let host = harness()
        defer { host.release() }
        let sample = presentation("token = ••••", redactions: 1, truncatedSourceBytes: 4_000_000, isReformatted: true)
        host.view.display(.ready(sample), locale: english)
        let reformatted = PreviewStrings.text(.codeNoticeReformatted)
        let limit = PresentationNotices.notices(for: sample, locale: english).first { $0.kind == .limit }?.text ?? ""
        #expect(!limit.isEmpty)
        // The limit keeps its slot at the bottom, and the note leaves the status line under the header.
        #expect(host.view.limitsLabel.stringValue == limit)
        #expect(!host.view.statusLabel.stringValue.contains(reformatted))
        #expect(!host.view.limitsLabel.stringValue.contains(reformatted))
        let lines = openedPanelLines(host)
        #expect(lines.contains(reformatted))
        #expect(!lines.contains(limit))
        // Every notice is still reachable: the panel holds the note, the strip the limit.
        #expect(host.view.displayedStatus.contains(reformatted) && host.view.displayedStatus.contains(limit))
    }

    @Test func aSignedPackageShowsItsSignatureNoteOnlyInThePanel() {
        let host = harness()
        defer { host.release() }
        host.view.display(.ready(presentation("{}", format: .applicationBundle, syntax: .json)), locale: english)
        let note = PreviewStrings.text(.packageNoticeSignature)
        #expect(!host.view.statusLabel.stringValue.contains(note))
        #expect(!host.view.displayedStatus.isEmpty && host.view.displayedStatus.contains(note))
        #expect(openedPanelLines(host).contains(note))
    }

    @Test func aStructureFallbackStaysInTheStatusLineAndOutOfThePanel() {
        let host = harness()
        defer { host.release() }
        host.view.display(.ready(presentation("{ not json", format: .json, syntax: .json)), locale: english)
        let fallback = PreviewStrings.text(.previewStructureFallback)
        #expect(host.view.statusLabel.stringValue.contains(fallback))
        #expect(!openedPanelLines(host).contains(fallback))
    }

    @Test func switchingToRenderedWhileThePanelIsOpenAddsItsFormulaNoteLiveAndSourceRemovesIt() throws {
        let host = harness()
        defer { host.release() }
        host.view.display(.ready(presentation("# Title\n\nEnergy $$E = mc^2$$", format: .markdown, syntax: .markdown)),
                          locale: english)
        let math = PreviewStrings.text(.markupMathNotice)
        let source = try #require(host.view.displayedModes.firstIndex(of: .source))
        let rendered = try #require(host.view.displayedModes.firstIndex(of: .rendered))
        #expect(host.view.selectMode(number: source + 1))
        #expect(!openedPanelLines(host).contains(math))
        // The panel is open: a mode change refreshes its lines without the reader reopening it.
        #expect(host.view.selectMode(number: rendered + 1))
        #expect(host.view.infoPanel.lines.contains(math))
        #expect(host.view.selectMode(number: source + 1))
        #expect(!host.view.infoPanel.lines.contains(math))
    }

    @Test func theCADPrivacyNoteMovesFromTheHeaderIntoThePanel() throws {
        let host = harness()
        defer { host.release() }
        host.view.display(.geometryReady(try geometry()), locale: english)
        let note = PreviewStrings.text(.cadPrivacyNotice)
        #expect(!host.view.statusLabel.stringValue.contains(note))
        #expect(openedPanelLines(host).contains(note))
    }

    private func geometry() throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: .zero, maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1,
            measurements: nil, headerFacts: nil, unitProvenance: .declared(.millimetre))
        return GeometryPresentation(formatID: .step, mesh: mesh, byteCount: 100)
    }
}
