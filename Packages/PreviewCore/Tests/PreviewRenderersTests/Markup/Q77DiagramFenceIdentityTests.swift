import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Q77 explicit diagram fence identity")
struct Q77DiagramFenceIdentityTests {
    private let english = Locale(identifier: "en_US")
    private let first = "flowchart LR\nA[One] --> B[Two]"
    private let second = "flowchart TD\nC[Three] --> D[Four]"
    private func fenced(_ body: String) -> String { "```mermaid\n" + body + "\n```" }

    @Test func adjacentDiagramsRetainIndependentBodiesAndSelectOnlyOne() throws {
        let document = try #require(SafeMarkdownDocument.render(fenced(first) + "\n" + fenced(second)))
        let ranges = MarkdownDiagramFences.fenceRanges(in: document, text: document.text as NSString)
        try #require(document.diagramFences.count == 2 && ranges.count == 2)
        #expect(ranges.map { (document.text as NSString).substring(with: $0) } == [first, second])
        #expect(MarkdownDiagramFences.firstDiagram(in: document, locale: english)
                == SafeDiagram.parse(mermaid: first, environment: DiagramEnvironment(locale: english)))
        #expect(document.codeBlocks.map(\.range) == ranges)
        #expect(document.text == first + "\n" + second)
    }

    @Test func emptyAndUnsupportedFencesKeepTheirPositionsAndExactBlankText() throws {
        let body = "\n" + first + "\n\n"
        let source = "```mermaid\n```\n" + fenced("gantt\n title inert") + "\n" + fenced(body)
        let document = try #require(SafeMarkdownDocument.render(source))
        let ranges = MarkdownDiagramFences.fenceRanges(in: document, text: document.text as NSString)
        try #require(ranges.count == 3)
        #expect(ranges[0].length == 0)
        #expect((document.text as NSString).substring(with: ranges[2]).utf16.elementsEqual(body.utf16))
        #expect(MarkdownDiagramFences.firstDiagram(in: document, locale: english)
                == SafeDiagram.parse(mermaid: body, environment: DiagramEnvironment(locale: english)))
    }

    @Test func emptyFencesConsumeTheBoundedAttemptPrefix() throws {
        let source = String(repeating: "```mermaid\n```\n", count: MarkdownDiagramFences.maximumFences) + fenced(first)
        let document = try #require(SafeMarkdownDocument.render(source))
        #expect(document.diagramFences.count == MarkdownDiagramFences.maximumFences + 1)
        #expect(MarkdownDiagramFences.firstDiagram(in: document, locale: english) == nil)
        let within = try #require(SafeMarkdownDocument.render(String(repeating: "```mermaid\n```\n", count: MarkdownDiagramFences.maximumFences - 1) + fenced(first)))
        #expect(MarkdownDiagramFences.firstDiagram(in: within, locale: english) != nil)
    }

    @Test func emptyFenceMetadataUsesTheExistingCountBudget() {
        var limits = MarkupBuilder.Limits()
        limits.maximumDecorations = 1
        #expect(MarkdownRenderer.render("```mermaid\n```", limits: limits)?.diagramFences.count == 1)
        #expect(MarkdownRenderer.render("```mermaid\n```\n```mermaid\n```", limits: limits) == nil)
    }

    @Test func decorationAdjacencyCannotInventIdentityAndBadRangesCannotTrap() {
        let text = first
        let fabricated = SafeMarkdownDocument(text: text, decorations: [.init(range: NSRange(location: 0, length: text.utf16.count), style: .diagramSource)])
        #expect(MarkdownDiagramFences.firstDiagram(in: fabricated, locale: english) == nil)
        let malformed = SafeMarkdownDocument(text: text, decorations: [], diagramFences: [
            .init(range: NSRange(location: Int.max, length: 2)),
            .init(range: NSRange(location: -1, length: 2)),
            .init(range: NSRange(location: 0, length: Int.max)),
            .init(range: NSRange(location: 0, length: text.utf16.count))
        ])
        #expect(MarkdownDiagramFences.fenceRanges(in: malformed, text: text as NSString) == [NSRange(location: 0, length: text.utf16.count)])
        #expect(MarkdownDiagramFences.firstDiagram(in: malformed, locale: english) != nil)
    }

    @Test func notebookCompositionRetainsFenceIdentityThroughItsExistingRenderer() throws {
        let cells: [[String: Any]] = [
            ["cell_type": "markdown", "source": fenced(first), "metadata": [:]],
            ["cell_type": "markdown", "source": fenced(second), "metadata": [:]]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: ["nbformat": 4, "cells": cells, "metadata": [:]])
        let document = try #require(SafeNotebookDocument.render(String(decoding: bytes, as: UTF8.self), locale: english))
        let ranges = MarkdownDiagramFences.fenceRanges(in: document, text: document.text as NSString)
        try #require(ranges.count == 2)
        #expect(ranges.map { (document.text as NSString).substring(with: $0) } == [first, second])
    }
}
