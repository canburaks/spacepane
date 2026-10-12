import Foundation
import Testing
@testable import PreviewRenderers

private let english = Locale(identifier: "en_US")

/// Serializes plain values to notebook JSON. A value of "@@CONCEALED@@" becomes the bare
/// concealment token, exactly as the shared privacy filter leaves a concealed JSON value.
private func safeJSON(cells: [[String: Any]], metadata: [String: Any] = [:], nbformat: Any = 4,
                      extra: [String: Any] = [:]) throws -> String {
    var object: [String: Any] = ["nbformat": nbformat, "nbformat_minor": 5, "metadata": metadata, "cells": cells]
    object.merge(extra) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"@@CONCEALED@@\"", with: "••••")
}

private func code(_ source: Any, count: Int? = 1, outputs: [[String: Any]] = []) -> [String: Any] {
    var cell: [String: Any] = ["cell_type": "code", "metadata": [String: Any](), "source": source, "outputs": outputs]
    cell["execution_count"] = count ?? NSNull()
    return cell
}

private func markdown(_ source: Any) -> [String: Any] { ["cell_type": "markdown", "metadata": [String: Any](), "source": source] }
private func raw(_ source: Any) -> [String: Any] { ["cell_type": "raw", "metadata": [String: Any](), "source": source] }
private func stream(_ text: Any, name: String = "stdout") -> [String: Any] { ["output_type": "stream", "name": name, "text": text] }
private func rich(_ data: [String: Any], type: String = "display_data", count: Int? = nil) -> [String: Any] {
    var output: [String: Any] = ["output_type": type, "metadata": [String: Any](), "data": data]
    if let count { output["execution_count"] = count }
    return output
}

private func label(_ key: PreviewStrings.Key) -> String { "**" + PreviewStrings.text(key) + "**" }
private func numbered(_ key: PreviewStrings.Key, _ count: Int64) -> String {
    "**" + PreviewStrings.format(key, arguments: [count], locale: english).replacingOccurrences(of: "[", with: "\\[") + "**"
}
private func notShown(_ type: String) -> String { PreviewStrings.format(.notebookOutputNotShown, arguments: [type], locale: english) }

private func rendered(_ cells: [[String: Any]], metadata: [String: Any] = [:]) throws -> SafeMarkdownDocument {
    try #require(SafeNotebookDocument.render(try safeJSON(cells: cells, metadata: metadata), locale: english))
}

@Suite("Safe notebook document")
struct SafeNotebookDocumentTests {
    // MARK: Mapping

    @Test func everyCellAndOutputKindMapsToInertMarkdown() throws {
        let metadata: [String: Any] = ["language_info": ["name": "python"]]
        let json = try safeJSON(cells: [
            markdown(["# Title 😀\n", "Prose with `code`."]),
            code(["x = 1\n", "print(x)"], count: 3, outputs: [
                stream("1\n"),
                stream(["warning\n"], name: "stderr"),
                rich(["text/plain": ["'abc'"], "image/png": "AAAA", "text/html": "<b>x</b>"], type: "execute_result", count: 3),
                rich(["image/svg+xml": "<svg/>"]),
                ["output_type": "error", "ename": "ValueError", "evalue": "bad",
                 "traceback": ["Traceback (most recent call last)", "\u{1B}[0;31mValueError\u{1B}[0m: bad"]]
            ]),
            code("", count: nil),
            raw("a: b")
        ], metadata: metadata)
        let source = try #require(SafeNotebookDocument.markdown(json, locale: english))
        let languageLine = "> " + PreviewStrings.format(.notebookLanguage, arguments: ["python"], locale: english)
        let expected = [
            languageLine,
            "# Title 😀\nProse with `code`.",
            [numbered(.notebookCodeCellNumbered, 3), "```python", "x = 1", "print(x)", "```"].joined(separator: "\n"),
            [label(.notebookOutput), "```", "1", "```"].joined(separator: "\n"),
            [label(.notebookOutputStderr), "```", "warning", "```"].joined(separator: "\n"),
            [numbered(.notebookOutputNumbered, 3), "```", "'abc'", "```", notShown("image/png"), notShown("text/html")].joined(separator: "\n"),
            [label(.notebookOutput), notShown("image/svg+xml")].joined(separator: "\n"),
            [label(.notebookOutputError), "```", "ValueError: bad", "Traceback (most recent call last)", "ValueError: bad", "```"].joined(separator: "\n"),
            label(.notebookCodeCell),
            [label(.notebookRawCell), "```", "a: b", "```"].joined(separator: "\n")
        ]
        // Cell blocks are separated by a blank line; a cell's own outputs by one too.
        let cellOne = expected[2...7].joined(separator: "\n\n")
        #expect(source == ([expected[0], expected[1], cellOne, expected[8], expected[9]]).joined(separator: "\n\n"))

        let document = try #require(SafeNotebookDocument.render(json, locale: english))
        #expect(!document.text.contains("```"))
        #expect(document.text.contains("print(x)"))
        #expect(document.text.contains(PreviewStrings.format(.notebookCodeCellNumbered, arguments: [Int64(3)], locale: english)))
        #expect(document.decorations.contains { $0.style == .heading(1) })
        #expect(document.decorations.contains { $0.style == .code })
        #expect(document.decorations.contains { $0.style == .bold })
        #expect(document.decorations.allSatisfy { NSMaxRange($0.range) <= document.text.utf16.count })
    }

    @Test func stringAndArraySourcesJoinWithoutSeparator() throws {
        let document = try rendered([markdown("one\ntwo"), markdown(["three\n", "four"]), code("a = 1\nb = 2")])
        #expect(document.text.contains("one two"))
        #expect(document.text.contains("three four"))
        #expect(document.text.contains("a = 1\nb = 2"))
    }

    @Test func nativeEnglishResourcesAreDefinedForEveryNotebookKey() {
        let keys: [PreviewStrings.Key: String] = [
            .notebookLanguage: "Language: %@", .notebookCodeCell: "Code cell", .notebookCodeCellNumbered: "Code cell [%lld]",
            .notebookRawCell: "Raw cell", .notebookOutput: "Output", .notebookOutputNumbered: "Output [%lld]",
            .notebookOutputStderr: "Error stream", .notebookOutputError: "Error",
            .notebookOutputNotShown: "Output not shown: %@", .notebookOutputMoreLines: "More lines not shown: %lld",
            .notebookTruncated: "Preview shortened. Cells shown: %1$lld of %2$lld.", .notebookEmpty: "This notebook has no cells."
        ]
        for (key, value) in keys { #expect(PreviewStrings.text(key, languagePreferences: ["en"]) == value) }
    }

    @Test func languageFallsBackThroughKernelspecAndIsSanitized() throws {
        let fromKernel = try #require(SafeNotebookDocument.markdown(
            try safeJSON(cells: [code("x")], metadata: ["kernelspec": ["language": "julia", "name": "julia-1.10"]]), locale: english))
        #expect(fromKernel.contains("```julia\n"))
        let named = try #require(SafeNotebookDocument.markdown(
            try safeJSON(cells: [code("x")], metadata: ["kernelspec": ["name": "ir"]]), locale: english))
        #expect(named.contains("```ir\n"))
        // Fence-info text keeps a conservative alphabet; injected markup and fences cannot survive.
        let hostile = try #require(SafeNotebookDocument.markdown(
            try safeJSON(cells: [code("x")], metadata: ["language_info": ["name": "c++\n```\n# injected *b* [l](u)"]]), locale: english))
        #expect(hostile.contains("```c++#injectedblu\n"))
        #expect(!hostile.contains("# injected"))
        // A name with no usable characters yields no language line and a plain fence.
        let unusable = try #require(SafeNotebookDocument.markdown(
            try safeJSON(cells: [code("x")], metadata: ["language_info": ["name": "***"]]), locale: english))
        #expect(!unusable.hasPrefix("> "))
        #expect(unusable.contains("\n```\nx\n```"))
    }

    // MARK: Outputs

    @Test func richMIMETypesAreNamedNeverDecodedOrShown() throws {
        let payload = "iVBORw0KGgoAAAANSUhEUgAAA"
        let document = try rendered([code("", outputs: [
            rich(["image/png": payload, "image/jpeg": payload, "image/svg+xml": "<svg onload='alert(1)'/>",
                  "text/html": "<script>alert('x')</script>", "application/javascript": "alert('js')",
                  "application/vnd.jupyter.widget-view+json": ["model_id": "abc"], "text/latex": "$x$", "text/plain": "<Figure size 640x480>"])
        ])])
        for type in ["image/png", "image/jpeg", "image/svg+xml", "text/html", "application/javascript",
                     "application/vnd.jupyter.widget-view+json", "text/latex"] {
            #expect(document.text.contains(notShown(type)))
        }
        #expect(document.text.contains("<Figure size 640x480>"))
        for forbidden in ["iVBOR", "alert", "<script", "<svg", "model_id", "$x$"] { #expect(!document.text.contains(forbidden)) }
    }

    @Test func hostileMIMEAndOutputTypeNamesStayOnOneInertLine() throws {
        // Includes every Unicode line separator SafeMarkdownDocument splits on, not only line feed.
        let hostile = "image/png\n```\n# injected\n**x**\u{2028}```\u{85}# injected\u{2029}~~~"
        let document = try rendered([code("", outputs: [
            rich([hostile: "AAAA"]), ["output_type": "novel\n# heading\u{2028}```", "payload": "x"]
        ]), markdown("# Later")])
        #expect(document.decorations.filter { if case .heading = $0.style { true } else { false } }.count == 1)
        #expect(!document.decorations.contains { $0.style == .code })
        #expect(document.text.components(separatedBy: .newlines).filter { $0.contains("injected") }.count == 1)
        #expect(document.text.components(separatedBy: .newlines).filter { $0.contains("heading") }.count == 1)
    }

    @Test func terminalEscapesAndControlCharactersAreRemoved() throws {
        let tracebackLine = "\u{1B}[0;31m---------------------------\u{1B}[0m\n\u{1B}[0;31mKeyError\u{1B}[0m \u{1B}]8;;https://example.invalid\u{7}link\u{1B}]8;;\u{7}\u{8}\u{0}"
        let document = try rendered([code("", outputs: [
            stream("progress 10%\r 50%\r\n\u{1B}[2K done\u{1B}c\n"),
            ["output_type": "error", "ename": "KeyError", "evalue": "'k'", "traceback": [tracebackLine]]
        ])])
        #expect(!document.text.contains("\u{1B}"))
        #expect(!document.text.contains("[0;31m"))
        #expect(!document.text.contains("\u{0}") && !document.text.contains("\u{8}"))
        #expect(document.text.contains("KeyError link"))
        #expect(document.text.contains("progress 10%\n 50%\n done"))
    }

    @Test func longOutputIsCappedWithALocalizedCount() throws {
        let lines = (0..<1_000).map { "line \($0)\n" }
        let document = try rendered([code("", outputs: [stream(lines)])])
        #expect(document.text.contains("line 299"))
        #expect(!document.text.contains("line 300\n"))
        #expect(document.text.contains(PreviewStrings.format(.notebookOutputMoreLines, arguments: [Int64(700)], locale: english)))
    }

    // MARK: Fences

    @Test func contentContainingFenceMarkersCannotEscapeItsBlock() throws {
        let after = markdown("# After")
        for source in ["before\n```\n# not heading\nafter", "before\n~~~\n# not heading\nafter", "```\n~~~\n   ```swift\n~~~ x\n# not heading"] {
            let document = try rendered([code(source), after])
            let ns = document.text as NSString
            let notHeading = ns.range(of: "# not heading")
            #expect(notHeading.location != NSNotFound)
            #expect(document.decorations.contains { $0.style == .code && NSIntersectionRange($0.range, notHeading).length == notHeading.length })
            #expect(!document.decorations.contains { if case .heading = $0.style { NSIntersectionRange($0.range, notHeading).length > 0 } else { false } })
            let afterRange = ns.range(of: "After")
            #expect(document.decorations.contains { $0.style == .heading(1) && NSIntersectionRange($0.range, afterRange).length == afterRange.length })
            #expect(!document.decorations.contains { $0.style == .code && NSIntersectionRange($0.range, afterRange).length > 0 })
        }
        // Raw cells and outputs use the same strategy.
        let outputs = try rendered([raw("~~~\n```"), code("", outputs: [stream("```\n~~~\n")]), after])
        #expect(outputs.text.contains("\u{2060}```"))
        let afterRange = (outputs.text as NSString).range(of: "After")
        #expect(outputs.decorations.contains { $0.style == .heading(1) && NSIntersectionRange($0.range, afterRange).length == afterRange.length })
    }

    @Test func fenceMarkerSelectionOnlyNeutralizesWhenBothMarkersCollide() throws {
        let backticks = try #require(SafeNotebookDocument.markdown(try safeJSON(cells: [code("```\nx")]), locale: english))
        #expect(backticks.contains("~~~\n```\nx\n~~~"))
        let both = try #require(SafeNotebookDocument.markdown(try safeJSON(cells: [code("```\n~~~\n  ```py\ny")]), locale: english))
        #expect(both.contains("\u{2060}```\n~~~\n\u{2060}  ```py\ny"))
    }

    @Test func unterminatedFenceInAMarkdownCellDoesNotAbsorbLaterCells() throws {
        let document = try rendered([markdown("text\n```swift\nlet x = 1"), code("y = 2"), markdown("# Later")])
        let ns = document.text as NSString
        let later = ns.range(of: "Later")
        #expect(document.decorations.contains { $0.style == .heading(1) && NSIntersectionRange($0.range, later).length == later.length })
        let labelRange = ns.range(of: PreviewStrings.format(.notebookCodeCellNumbered, arguments: [Int64(1)], locale: english))
        #expect(labelRange.location != NSNotFound)
        #expect(!document.decorations.contains { $0.style == .code && NSIntersectionRange($0.range, labelRange).length > 0 })
    }

    @Test func markdownCellsKeepTheirInertSubsetAndLookalikeStringsAreText() throws {
        let document = try rendered([markdown("[…]"), markdown("{…}"), markdown("[link](javascript:inert) ![img](https://example.invalid/i.png)\n<script>x</script>")])
        #expect(document.text.contains("[…]"))
        #expect(document.text.contains("{…}"))
        #expect(document.text.contains("link (javascript:inert)"))
        #expect(!document.text.contains("i.png"))
        #expect(document.text.contains("<script>x</script>"))
    }

    // MARK: Concealment

    @Test func concealedTokensRemainVerbatimAndKeepTheirOwnLines() throws {
        let json = try safeJSON(cells: [
            code(["before\n", "@@CONCEALED@@", "after\n", "@@CONCEALED@@"], outputs: [
                stream(["ok\n", "@@CONCEALED@@", "last"]),
                ["output_type": "error", "ename": "@@CONCEALED@@", "evalue": "e", "traceback": ["@@CONCEALED@@", "tail"]]
            ]),
            markdown("@@CONCEALED@@")
        ], metadata: ["token": "@@CONCEALED@@", "language_info": ["name": "python"]])
        let source = try #require(SafeNotebookDocument.markdown(json, locale: english))
        #expect(source.contains("```python\nbefore\n••••\nafter\n••••\n```"))
        #expect(source.contains("```\nok\n••••\nlast\n```"))
        #expect(source.contains("```\n••••: e\n••••\ntail\n```"))
        #expect(source.hasSuffix("\n\n••••"))
        let document = try #require(SafeNotebookDocument.render(json, locale: english))
        #expect(document.text.contains("before\n••••\nafter"))
    }

    @Test func aConcealedWholeFieldIsTreatedAsConcealedTextNotAsStructure() throws {
        let json = try safeJSON(cells: [["cell_type": "code", "source": "@@CONCEALED@@", "outputs": "@@CONCEALED@@"]])
        // A concealed `outputs` value is not an array, so the view declines instead of guessing.
        #expect(SafeNotebookDocument.render(json, locale: english) == nil)
        let source = try safeJSON(cells: [["cell_type": "code", "source": "@@CONCEALED@@"]])
        #expect(try #require(SafeNotebookDocument.markdown(source, locale: english)).contains("```\n••••\n```"))
    }

    // MARK: Declined input

    @Test(arguments: [
        "", "not json", "[]", "{}", #"{"nbformat":4}"#, #"{"nbformat":4,"cells":[}"#, #"{"nbformat":4,"cells":[]} trailing"#,
        #"{"nbformat":3,"cells":[]}"#, #"{"nbformat":"4","cells":[]}"#, #"{"nbformat":4,"cells":{}}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"markdown"}]}"#, #"{"nbformat":4,"cells":[{"cell_type":"x","source":""}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":5}]}"#, #"{"nbformat":4,"cells":[{"cell_type":"code","source":[1]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"stream","text":false}]}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"error","traceback":"x"}]}]}"#,
        #"{"nbformat":4,"cells":[],"cells":[]}"#, #"{"nbformat":4,"cells":[{"cell_type":"code","cell_type":"raw","source":""}]}"#,
        #"{"nbformat":4,"cells":[{"cell_type":"code","source":"","outputs":[{"output_type":"display_data","data":{"text/plain":"a","text/plain":"b"}}]}]}"#,
        #"{"nbformat":4,"cells":["••••x"]}"#, #"{"nbformat":4,••••:[]}"#, #"{"nbformat":4,"cells":[{"cell_type":"markdown","source":"\ud800"}]}"#,
        "{\"nbformat\":4,\"cells\":[{\"cell_type\":\"markdown\",\"source\":\"raw\ttab\"}]}"
    ])
    func unparsableOrUnsupportedSafeTextReturnsNil(source: String) {
        #expect(SafeNotebookDocument.render(source, locale: english) == nil)
    }

    @Test func emptyNotebooksAndEmptyCells() throws {
        let empty = try #require(SafeNotebookDocument.render(try safeJSON(cells: []), locale: english))
        #expect(empty.text == PreviewStrings.text(.notebookEmpty))
        // Empty code and raw cells still show their label; an all-empty-Markdown notebook has nothing to show.
        let labelled = try rendered([code(""), raw(""), markdown("   \n")])
        #expect(labelled.text.contains(PreviewStrings.text(.notebookCodeCell)))
        #expect(labelled.text.contains(PreviewStrings.text(.notebookRawCell)))
        #expect(SafeNotebookDocument.render(try safeJSON(cells: [markdown(""), markdown("\n")]), locale: english) == nil)
    }

    // MARK: Limits

    @Test func structuralLimitsDeclineTheView() throws {
        let tooLarge = "{\"nbformat\":4,\"cells\":[{\"cell_type\":\"markdown\",\"source\":\"" + String(repeating: "a", count: 2_100_000) + "\"}]}"
        #expect(SafeNotebookDocument.render(tooLarge, locale: english) == nil)
        let nested = "{\"nbformat\":4,\"cells\":[],\"x\":" + String(repeating: "[", count: 70) + String(repeating: "]", count: 70) + "}"
        #expect(SafeNotebookDocument.render(nested, locale: english) == nil)
        let manyNodes = "{\"nbformat\":4,\"cells\":[],\"x\":[" + Array(repeating: "1", count: 20_001).joined(separator: ",") + "]}"
        #expect(SafeNotebookDocument.render(manyNodes, locale: english) == nil)
    }

    @Test func manyCellsStopAtACellBoundaryWithALocalizedNotice() throws {
        // 3,000 cells of 30 lines each: the 20,000-line Markdown ceiling binds long before the node limit.
        let cells = (0..<3_000).map { code("print(\($0))\n" + String(repeating: "pass\n", count: 29), count: $0 + 1) }
        let json = try safeJSON(cells: cells)
        let document = try #require(SafeNotebookDocument.render(json, locale: english))
        let source = try #require(SafeNotebookDocument.markdown(json, locale: english))
        #expect(document.text.utf16.count <= 262_144)
        #expect(document.text.components(separatedBy: .newlines).count <= 20_000)
        #expect(document.decorations.count <= 20_000)
        let shown = source.components(separatedBy: "print(").count - 1
        #expect(shown > 100 && shown < 3_000)
        let notice = PreviewStrings.format(.notebookTruncated, arguments: [Int64(shown), Int64(3_000)], locale: english)
        #expect(source.hasSuffix("\n\n" + notice))
        #expect(document.text.hasSuffix("\n\n" + notice))
        // Every shown cell is complete: fences are balanced and the last shown cell has all its lines.
        #expect((source.components(separatedBy: "```").count - 1).isMultiple(of: 2))
        #expect(source.components(separatedBy: "pass\n").count - 1 == shown * 29)
    }

    @Test func aFirstCellLargerThanTheMarkdownCeilingDeclinesInsteadOfTruncatingMidCell() throws {
        let json = try safeJSON(cells: [code(String(repeating: "a", count: 300_000)), markdown("small")])
        #expect(SafeNotebookDocument.render(json, locale: english) == nil)
    }

    @Test func laterOversizedCellsAreDroppedWholeAndNoticed() throws {
        let cells = [markdown("first"), code(String(repeating: "b", count: 300_000)), markdown("third")]
        let document = try #require(SafeNotebookDocument.render(try safeJSON(cells: cells), locale: english))
        #expect(document.text.contains("first"))
        #expect(!document.text.contains("bbbb"))
        #expect(!document.text.contains("third"))
        #expect(document.text.contains(PreviewStrings.format(.notebookTruncated, arguments: [Int64(1), Int64(3)], locale: english)))
    }

    @Test func decorationCeilingTruncatesByBisectionAtACellBoundary() throws {
        let emphasized = String(repeating: "*a* ", count: 21_000)
        let cells = [markdown("kept"), markdown(emphasized), markdown("dropped")]
        let document = try #require(SafeNotebookDocument.render(try safeJSON(cells: cells), locale: english))
        #expect(document.text.contains("kept"))
        #expect(!document.text.contains("dropped"))
        #expect(document.decorations.count <= 20_000)
        #expect(document.text.contains(PreviewStrings.format(.notebookTruncated, arguments: [Int64(1), Int64(3)], locale: english)))
        #expect(SafeNotebookDocument.render(try safeJSON(cells: [markdown(emphasized)]), locale: english) == nil)
    }

    @Test func exactSafeSpellingsAreNeverRoundedOrReformatted() throws {
        let json = try safeJSON(cells: [markdown("9007199254740993123456789 1.234567890123456789e999 \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"),
                                        code("print('é')", count: 9_007_199_254_740_993)])
        let document = try #require(SafeNotebookDocument.render(json, locale: english))
        #expect(document.text.contains("9007199254740993123456789 1.234567890123456789e999 \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"))
        #expect(document.text.contains("print('é')"))
        #expect(document.text.contains(PreviewStrings.format(.notebookCodeCellNumbered, arguments: [Int64(9_007_199_254_740_993)], locale: english)))
    }

    @Test func executionCountLabelUsesTheRequestedLocale() throws {
        let json = try safeJSON(cells: [code("x", count: 12)])
        let bengali = Locale(identifier: "bn")
        let expected = PreviewStrings.format(.notebookCodeCellNumbered, arguments: [Int64(12)], locale: bengali)
        let document = try #require(SafeNotebookDocument.render(json, locale: bengali))
        #expect(document.text.contains(expected))
        // Invalid or negative counters are ignored rather than displayed.
        let odd = try safeJSON(cells: [code("x", count: -3), code("y", count: nil)])
        let oddDocument = try #require(SafeNotebookDocument.render(odd, locale: english))
        #expect(oddDocument.text.components(separatedBy: PreviewStrings.text(.notebookCodeCell)).count == 3)
    }
}
