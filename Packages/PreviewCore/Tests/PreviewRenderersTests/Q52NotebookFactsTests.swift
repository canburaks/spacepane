import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Existing model/provider/facade seams reproduce missing counts before the render-result integration.
@Suite("Q52 notebook total cells from cached rendering", .serialized)
@MainActor
struct Q52NotebookFactsTests {
    private let english = Locale(identifier: "en_US")

    private func notebook(_ cells: [[String: Any]]) throws -> String {
        let value: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": [:], "cells": cells]
        return String(decoding: try JSONSerialization.data(withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    private func markdown(_ text: String) -> [String: Any] { ["cell_type": "markdown", "source": text] }
    private func code(_ text: String) -> [String: Any] {
        ["cell_type": "code", "source": text, "execution_count": NSNull(), "outputs": []]
    }
    private func presentation(_ text: String, facts: PresentationFacts = .none) -> TextPresentation {
        TextPresentation(formatID: .jupyterNotebook, text: text,
            lineCount: LogicalLines.starts(in: text).starts.count, byteCount: text.utf8.count,
            encoding: .utf8, redactionCount: 0, syntax: .json, origin: .converted, facts: facts)
    }
    private func cellCounts(_ facts: PresentationFacts) -> [Int] {
        facts.facts.compactMap { if case .records(let count, .cells, _) = $0 { count } else { nil } }
    }
    private func facts(_ source: String) -> (SafePreviewModes, PresentationFacts) {
        let value = presentation(source), modes = SafePreviewModes(value, locale: english)
        return (modes, PresentationFactsProvider.facts(for: value, modes: modes))
    }

    @Test func totalIncludesCellsThatRenderNothingAndProviderUsesTheExistingCache() throws {
        let source = try notebook([markdown(""), markdown("Q52Payload"), code("x = 1"), markdown("\n")])
        let (modes, supplied) = facts(source)
        let document = try #require(modes.markdown)
        #expect(cellCounts(supplied) == [4])
        #expect(document.text.contains("Q52Payload") && document.text.contains("x = 1"))
        // The Rendered document is the grouped layout with cell-group rules (Q-76), not the original flat render.
        let value = presentation(source)
        #expect(SafeNotebookDocument.renderResult(for: value, locale: english)?.document == document)
        #expect(SafeNotebookDocument.render(source, locale: english)?.text.contains("Q52Payload") == true)
        // Changing the provider's text to invalid JSON must not make it recount or lose cached model facts.
        let differentText = presentation("This is not notebook JSON")
        #expect(cellCounts(PresentationFactsProvider.facts(for: differentText, modes: modes)) == [4])
        let parserSupplied = presentation(source, facts: PresentationFacts([.records(99, .cells)]))
        #expect(cellCounts(PresentationFactsProvider.facts(for: parserSupplied, modes: modes)) == [99])
    }

    @Test func boundedMarkdownPrefixKeepsTheTotalInsteadOfShownBlocksOrCellPosition() throws {
        let source = try notebook([markdown(""), code("Q52Kept\n" + String(repeating: "a", count: 150_000)),
            code("Q52Omitted\n" + String(repeating: "b", count: 150_000)), markdown("\n")])
        let (modes, supplied) = facts(source)
        let document = try #require(modes.markdown)
        #expect(cellCounts(supplied) == [4]) // One shown block ends at cell position two, but the total is four.
        #expect(document.text.contains("Q52Kept") && !document.text.contains("Q52Omitted"))
        #expect(document.text.utf16.count <= 262_144)
        let shortened = PreviewStrings.format(.notebookTruncated, arguments: [Int64(2), Int64(4)], locale: english)
        #expect(document.text.contains(shortened))
    }

    @Test func decorationBisectionKeepsTheTotalFromTheSameSuccessfulPlan() throws {
        let source = try notebook([markdown("Q52Kept"),
            markdown(String(repeating: "*a* ", count: 21_000)), markdown("Q52Omitted")])
        let (modes, supplied) = facts(source)
        let document = try #require(modes.markdown)
        #expect(cellCounts(supplied) == [3])
        #expect(document.text.contains("Q52Kept") && !document.text.contains("Q52Omitted"))
        #expect(document.decorations.count <= 20_000)
    }

    @Test func validEmptyNotebookIsZeroWhileOnlyEmptyMarkdownCellsRemainUnknown() throws {
        let empty = try notebook([])
        let (modes, supplied) = facts(empty)
        #expect(modes.markdown?.text == PreviewStrings.text(.notebookEmpty))
        #expect(cellCounts(supplied) == [0])
        let noRenderedDocument = try notebook([markdown(""), markdown("\n")])
        let (omitted, unknown) = facts(noRenderedDocument)
        #expect(omitted.markdown == nil && omitted.hasStructureFallback)
        #expect(cellCounts(unknown).isEmpty)
    }

    @Test func invalidAndOversizedOrUnrenderableDocumentsNeverInventCounts() throws {
        let invalid = ["{", #"{"nbformat":3,"cells":[]}"#,
            #"{"nbformat":4,"cells":[{"cell_type":"code","source":1}]}"#,
            try notebook([code(String(repeating: "a", count: 300_000))]),
            try notebook([markdown(String(repeating: "a", count: 2_100_000))]),
            #"{"nbformat":4,"cells":[],"x":"# + String(repeating: "[", count: 70)
                + String(repeating: "]", count: 70) + "}",
            #"{"nbformat":4,"cells":[],"x":["# + Array(repeating: "1", count: 20_001).joined(separator: ",") + "]}"]
        for source in invalid {
            let (modes, supplied) = facts(source)
            #expect(modes.markdown == nil && modes.hasStructureFallback)
            #expect(cellCounts(supplied).isEmpty)
        }
    }

    @Test func nativeHeaderKeepsCachedTotalAcrossModesAndClearsItForAReplacement() throws {
        let source = try notebook([markdown(""), markdown("Q52Payload"), code("x = 1")])
        let host = InteractionHarness(width: 800); defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        host.view.display(.ready(presentation(source)), locale: english, resetsContentState: true)
        let count = PreviewStrings.format(.previewFactsCells, arguments: ["3"], locale: english)
        #expect(host.view.displayedFacts.contains(count))
        #expect(!host.view.factsLabel.stringValue.contains("Q52Payload"))
        for mode in [NativePreviewMode.source, .rendered] {
            let index = try #require(host.view.displayedModes.firstIndex(of: mode))
            #expect(host.view.selectMode(number: index + 1))
            #expect(host.view.displayedFacts.contains(count))
            #expect(host.view.factsLabel.toolTip?.contains(count) == true)
            #expect((host.view.factsLabel.accessibilityValue() as? String)?.contains(count) == true)
        }
        host.view.display(.ready(presentation("{")), locale: english, resetsContentState: true)
        #expect(!host.view.displayedFacts.contains(count))
        #expect(host.view.factsLabel.toolTip?.contains(count) != true)
        #expect((host.view.factsLabel.accessibilityValue() as? String)?.contains(count) != true)
    }
}
