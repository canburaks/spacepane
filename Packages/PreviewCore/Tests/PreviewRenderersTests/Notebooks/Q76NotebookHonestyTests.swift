import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-76 (review DM-26): a notebook's image outputs point at the saved figures in Pages instead of saying
// "Output not shown", and each code or raw cell with its outputs reads as one group with a visible boundary. Both are
// opt-in through `NotebookRenderOptions`; the original layout stays the default.

private let english = Locale(identifier: "en_US")

private func safeJSON(cells: [[String: Any]], metadata: [String: Any] = [:]) throws -> String {
    let object: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": metadata, "cells": cells]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

private func code(_ source: Any, count: Int? = 1, outputs: [[String: Any]] = []) -> [String: Any] {
    var cell: [String: Any] = ["cell_type": "code", "metadata": [String: Any](), "source": source, "outputs": outputs]
    cell["execution_count"] = count ?? NSNull()
    return cell
}

private func markdown(_ source: Any) -> [String: Any] { ["cell_type": "markdown", "metadata": [String: Any](), "source": source] }
private func raw(_ source: Any) -> [String: Any] { ["cell_type": "raw", "metadata": [String: Any](), "source": source] }

/// An output whose image payloads were already replaced by the inert `null` placeholder, as the adapter leaves them.
private func figureOutput(_ types: [String] = ["image/png"], plain: String? = nil, other: [String: Any] = [:]) -> [String: Any] {
    var data: [String: Any] = other
    for type in types { data[type] = NSNull() }
    if let plain { data["text/plain"] = plain }
    return ["output_type": "display_data", "metadata": [String: Any](), "data": data]
}

private func label(_ key: PreviewStrings.Key) -> String { "**" + PreviewStrings.text(key) + "**" }
private func numbered(_ key: PreviewStrings.Key, _ count: Int64) -> String {
    "**" + PreviewStrings.format(key, arguments: [count], locale: english).replacingOccurrences(of: "[", with: "\\[") + "**"
}
private func notShown(_ type: String) -> String { PreviewStrings.format(.notebookOutputNotShown, arguments: [type], locale: english) }
private func figure(_ number: Int) -> String { "Figure \(number), shown in Pages." }

private func markdownSource(_ json: String, _ options: NotebookRenderOptions = .original) throws -> String {
    try #require(SafeNotebookDocument.markdown(json, locale: english, options: options))
}

@Suite("Notebook honesty")
struct Q76NotebookHonestyTests {
    // MARK: Figures

    @Test func imageOutputsPointAtTheirFigureWhenFiguresAndPlaceholdersAgree() throws {
        let json = try safeJSON(cells: [
            code("plot()", count: 1, outputs: [figureOutput(plain: "<Figure size 640x480>")]),
            markdown("Between"),
            code("plot2()", count: 2, outputs: [figureOutput(["image/jpeg"])])
        ])
        let source = try markdownSource(json, .grouped(figureCount: 2))
        let first = [label(.notebookOutput), "```", "<Figure size 640x480>", "```", figure(1)].joined(separator: "\n")
        #expect(source.contains(first))
        #expect(source.contains([label(.notebookOutput), figure(2)].joined(separator: "\n")))
        #expect(!source.contains(notShown("image/png")) && !source.contains(notShown("image/jpeg")))
    }

    @Test func figureNumbersCountEveryPlaceholderInNotebookOrderAndPNGBeforeJPEG() throws {
        // File order puts image/jpeg before image/png (keys are sorted), the adapter extracts PNG first.
        let json = try safeJSON(cells: [
            code("a", outputs: [figureOutput()]),
            code("b", outputs: [figureOutput(["image/jpeg", "image/png"])]),
            code("c", outputs: [figureOutput(["image/jpeg"])])
        ])
        let source = try markdownSource(json, .grouped(figureCount: 4))
        let lines = source.components(separatedBy: "\n").filter { $0.hasPrefix("Figure ") }
        #expect(lines == [figure(1), figure(2), figure(3), figure(4)])
    }

    @Test func whenTheCountsDifferNoOutputClaimsAFigure() throws {
        // Two placeholders. One figure could be either of them; three cannot all be here; none means Pages is empty.
        let json = try safeJSON(cells: [
            code("a", outputs: [figureOutput(["image/png"])]),
            code("b", outputs: [figureOutput(["image/jpeg"])])
        ])
        for count in [0, 1, 3] {
            let source = try markdownSource(json, .grouped(figureCount: count))
            #expect(!source.contains("shown in Pages"), "\(count) figures")
            #expect(source.contains(notShown("image/png")) && source.contains(notShown("image/jpeg")), "\(count) figures")
        }
        // The original layout never numbers anything, whatever the figures.
        let original = try markdownSource(json)
        #expect(!original.contains("shown in Pages") && original.contains(notShown("image/png")))
    }

    @Test func otherRepresentationsAndRealPayloadsStayNotShown() throws {
        let json = try safeJSON(cells: [
            code("a", outputs: [figureOutput(other: ["image/svg+xml": "<svg/>", "text/html": "<b>x</b>"])]),
            code("b", outputs: [["output_type": "display_data", "metadata": [String: Any](),
                                 "data": ["image/png": "iVBORw0KGgo="] as [String: Any]]])
        ])
        // One placeholder (the first output's PNG); the second PNG still holds a string, so it is not a placeholder.
        let source = try markdownSource(json, .grouped(figureCount: 1))
        #expect(source.contains(figure(1)))
        #expect(source.contains(notShown("image/svg+xml")) && source.contains(notShown("text/html")))
        #expect(source.contains(notShown("image/png")))
        #expect(!source.contains("iVBOR"))
    }

    @Test func aRepeatedImageMemberEarnsNoFigureNumber() throws {
        let json = #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"display_data","data":{"image/png":null,"image/png":null}}]}]}"#
        let source = try markdownSource(json, .grouped(figureCount: 1))
        #expect(!source.contains("shown in Pages"))
        #expect(source.components(separatedBy: notShown("image/png")).count - 1 == 2)
    }

    @Test func aFigureLineNeverCarriesAnythingFromTheOutput() throws {
        let json = try safeJSON(cells: [code("a", outputs: [figureOutput(plain: "SECRETISH <b>markup</b>")])])
        let source = try markdownSource(json, .grouped(figureCount: 1))
        let line = try #require(source.components(separatedBy: "\n").first { $0.hasPrefix("Figure ") })
        #expect(line == figure(1))
    }

    @Test func thePresentationEntryPointCountsOnlyValidFigures() throws {
        let json = try safeJSON(cells: [
            code("a", outputs: [figureOutput(["image/png"])]),
            code("b", outputs: [figureOutput(["image/jpeg"])])
        ])
        let valid = PreviewImage(data: Data([1]), pixelWidth: 4, pixelHeight: 4, role: .figure)
        let empty = PreviewImage(data: Data(), pixelWidth: 4, pixelHeight: 4, role: .figure)
        let cover = PreviewImage(data: Data([1]), pixelWidth: 4, pixelHeight: 4, role: .cover)
        let both = presentation(.jupyterNotebook, text: json, syntax: .json, images: [valid, valid, cover])
        let result = try #require(SafeNotebookDocument.renderResult(for: both, locale: english))
        #expect(result.document.text.contains(figure(1)) && result.document.text.contains(figure(2)))
        #expect(result.totalCells == 2)
        #expect(NotebookFigureFacts.validFigureCount(in: both) == 2)
        let oneInvalid = presentation(.jupyterNotebook, text: json, syntax: .json, images: [valid, empty])
        let partial = try #require(SafeNotebookDocument.renderResult(for: oneInvalid, locale: english))
        #expect(!partial.document.text.contains("shown in Pages") && partial.document.text.contains(notShown("image/png")))
        #expect(NotebookFigureFacts.validFigureCount(in: oneInvalid) == 1)
    }

    // MARK: Cell groups

    @Test func theOriginalLayoutIsUnchangedUnlessGroupingIsAskedFor() throws {
        let json = try safeJSON(cells: [markdown("Intro"), code("a = 1", outputs: [figureOutput()]), raw("r")])
        let byDefault = try markdownSource(json)
        let explicit = try markdownSource(json, .original)
        #expect(byDefault == explicit)
        #expect(!byDefault.components(separatedBy: "\n\n").contains("---"))
        let document = try #require(SafeNotebookDocument.render(json, locale: english))
        #expect(document.decorations.allSatisfy { $0.style != .rule })
    }

    @Test func eachCodeOrRawGroupIsSeparatedFromItsNeighboursByABreak() throws {
        let json = try safeJSON(cells: [
            markdown("Intro"), code("a = 1", count: 1), markdown("Prose"), markdown("More prose"), raw("r"), code("b = 2", count: 2)
        ])
        let source = try markdownSource(json, .grouped(figureCount: 0))
        #expect(source.contains("Intro\n\n---\n\n" + numbered(.notebookCodeCellNumbered, 1)))
        #expect(source.contains("```\n\n---\n\nProse"))
        // Two prose cells beside each other need no break.
        #expect(source.contains("Prose\n\nMore prose\n\n---\n\n" + label(.notebookRawCell)))
        #expect(source.contains("```\n\n---\n\n" + numbered(.notebookCodeCellNumbered, 2)))
        let parts = source.components(separatedBy: "\n\n")
        #expect(parts.filter { $0 == "---" }.count == 4)
        #expect(parts.first != "---" && parts.last != "---")
    }

    @Test func aGroupAloneOrBesideTheLanguageLineHasNoBreak() throws {
        let metadata: [String: Any] = ["language_info": ["name": "python"]]
        let alone = try markdownSource(try safeJSON(cells: [code("x", outputs: [figureOutput()])], metadata: metadata), .grouped(figureCount: 1))
        #expect(!alone.contains("---"))
        let languageLine = "> " + PreviewStrings.format(.notebookLanguage, arguments: ["python"], locale: english)
        #expect(alone.hasPrefix(languageLine + "\n\n" + numbered(.notebookCodeCellNumbered, 1)))
        // Prose cells alone never get one either.
        let prose = try markdownSource(try safeJSON(cells: [markdown("a"), markdown("b")]), .grouped(figureCount: 0))
        #expect(prose == "a\n\nb")
    }

    @Test func breaksRenderAsThematicBreaksAndNeverBecomeHeadings() throws {
        let json = try safeJSON(cells: [markdown("Intro"), code("a = 1"), markdown("Prose"), code("b = 2")])
        let result = try #require(SafeNotebookDocument.renderResult(json, locale: english, options: .grouped(figureCount: 0)))
        #expect(result.document.decorations.filter { $0.style == .rule }.count == 3)
        #expect(!result.document.decorations.contains { if case .heading = $0.style { true } else { false } })
        #expect(result.totalCells == 4)
        // The text is the notebook's own words; the break is the rule glyph line the Markdown renderer draws.
        #expect(!result.document.text.contains("---"))
    }

    @Test func breaksCountAgainstTheSameBoundsAsTheCellsTheySeparate() throws {
        // 3,000 cells of 30 lines each: the 20,000-line ceiling binds well before the node limit.
        let cells = (0..<3_000).map { code("print(\($0))\n" + String(repeating: "pass\n", count: 29), count: $0 + 1) }
        let json = try safeJSON(cells: cells)
        let grouped = try #require(SafeNotebookDocument.renderResult(json, locale: english, options: .grouped(figureCount: 0)))
        #expect(grouped.document.text.utf16.count <= 262_144)
        #expect(grouped.document.text.components(separatedBy: .newlines).count <= 20_000)
        #expect(grouped.document.decorations.count <= 20_000)
        let shownGrouped = try markdownSource(json, .grouped(figureCount: 0)).components(separatedBy: "print(").count - 1
        let shownOriginal = try markdownSource(json).components(separatedBy: "print(").count - 1
        #expect(shownGrouped > 100 && shownGrouped < 3_000)
        #expect(shownGrouped <= shownOriginal)
        // The shortened notebook still says so, after its last shown cell and never after a break.
        let source = try markdownSource(json, .grouped(figureCount: 0))
        let notice = PreviewStrings.format(.notebookTruncated, arguments: [Int64(shownGrouped), Int64(3_000)], locale: english)
        #expect(source.hasSuffix(notice))
        #expect(!source.hasSuffix("---"))
    }
}
