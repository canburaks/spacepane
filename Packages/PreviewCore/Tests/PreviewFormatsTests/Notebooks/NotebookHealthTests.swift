import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parse(_ text: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try JupyterNotebookAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count),
                                       context: RequestContext(budget: budget))
}

private func notebook(_ cells: [[String: Any]], metadata: [String: Any] = [:]) throws -> String {
    let object: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": metadata, "cells": cells]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

/// A code cell with an execution count, or with `null` when `count` is `nil`.
private func code(_ count: Int?, source: Any = "x = 1", outputs: [[String: Any]] = []) -> [String: Any] {
    ["cell_type": "code", "metadata": [String: Any](), "execution_count": count.map { $0 as Any } ?? NSNull(),
     "source": source, "outputs": outputs]
}

/// A code cell whose `execution_count` key is absent.
private func codeWithoutCount(source: Any = "x = 1") -> [String: Any] {
    ["cell_type": "code", "metadata": [String: Any](), "source": source, "outputs": [Any]()]
}

private func markdown(_ source: Any = "# Notes") -> [String: Any] {
    ["cell_type": "markdown", "metadata": [String: Any](), "source": source]
}

private func raw(_ source: Any = "raw text") -> [String: Any] {
    ["cell_type": "raw", "metadata": [String: Any](), "source": source]
}

private var errorOutput: [String: Any] { ["output_type": "error", "ename": "ValueError", "evalue": "bad", "traceback": ["Traceback"]] }
private var streamOutput: [String: Any] { ["output_type": "stream", "name": "stdout", "text": ["ok\n"]] }

private func findings(_ cells: [[String: Any]]) throws -> [PreviewFinding] { try parse(try notebook(cells)).findings }

private func kinds(_ findings: [PreviewFinding]) -> [PreviewFindingKind] { findings.map(\.kind) }

/// Raw notebook JSON, for execution-count spellings `JSONSerialization` cannot produce.
private func rawNotebook(_ cells: [String]) -> String {
    #"{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[\#(cells.joined(separator: ",\n"))]}"#
}

private func rawCode(count lexeme: String?, source: String = "x = 1") -> String {
    let field = lexeme.map { #""execution_count":\#($0),"# } ?? ""
    return #"{"cell_type":"code",\#(field)"metadata":{},"source":"\#(source)","outputs":[]}"#
}

@Suite("Notebook health findings")
struct NotebookHealthTests {
    // MARK: Healthy notebooks

    @Test func inOrderFullyExecutedNotebookHasNoFindings() throws {
        // Mirrors the Theme page's built-in notebook sample: markdown first, then two executed cells.
        let result = try findings([
            markdown("# Example notebook"),
            code(1, source: ["values = [1, 2, 3]\n", "print(sum(values))\n"], outputs: [streamOutput]),
            code(2, source: ["total = sum(values) / len(values)\n", "total\n"],
                 outputs: [["output_type": "execute_result", "execution_count": 2, "metadata": [String: Any](),
                            "data": ["text/plain": ["2.0"]]]])
        ])
        #expect(result.isEmpty)
    }

    @Test func emptyAndMarkdownOnlyNotebooksHaveNoFindings() throws {
        #expect(try findings([]).isEmpty)
        #expect(try findings([markdown(), raw()]).isEmpty)
    }

    // MARK: Out of order

    @Test func descentReportsTheSequenceFromTheCellBeforeIt() throws {
        let result = try findings([code(1), code(3), code(2), code(4)])
        #expect(result == [
            PreviewFinding(kind: .notebookOutOfOrder, count: 1, detail: .executionSequence([3, 2, 4])),
            PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
        ])
        #expect(result[0].severity == .caution)
        #expect(result[1].severity == .info)
        #expect(result.allSatisfy { $0.lines.isEmpty })
    }

    @Test func outOfOrderWithGapsReportsBothAndTheDocumentedSequence() throws {
        // 1,2,5,2,9: one descent (5 to 2); sorted distinct 1,2,5,9 leaves two skipped runs.
        let result = try findings([code(1), code(2), code(5), code(2), code(9)])
        #expect(kinds(result) == [.notebookOutOfOrder, .notebookExecutionGaps, .notebookMayNotReproduce])
        #expect(result[0] == PreviewFinding(kind: .notebookOutOfOrder, count: 1, detail: .executionSequence([5, 2, 9])))
        #expect(result[1] == PreviewFinding(kind: .notebookExecutionGaps, count: 2))
    }

    @Test func duplicateCountsAreDescentsToo() throws {
        let result = try findings([code(1), code(2), code(2), code(3)])
        #expect(result == [
            PreviewFinding(kind: .notebookOutOfOrder, count: 1, detail: .executionSequence([2, 2, 3])),
            PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
        ])
    }

    @Test func everyDescentIsCountedAndTheSequenceStartsAtTheFirst() throws {
        let counts = [1, 2, 3, 4, 5, 6, 7, 8, 2, 1]
        let result = try findings(counts.map { code($0) })
        let outOfOrder = try #require(result.first { $0.kind == .notebookOutOfOrder })
        #expect(outOfOrder.count == 2)   // 8 to 2, then 2 to 1
        #expect(outOfOrder.detail == .executionSequence([8, 2, 1]))
    }

    @Test func theSequenceIsLimitedToSixValues() throws {
        let result = try findings([10, 9, 8, 7, 6, 5, 4, 3].map { code($0) })
        let outOfOrder = try #require(result.first { $0.kind == .notebookOutOfOrder })
        #expect(outOfOrder.count == 7)
        #expect(outOfOrder.detail == .executionSequence([10, 9, 8, 7, 6, 5]))
    }

    @Test func unexecutedAndNonCodeCellsBetweenExecutedOnesDoNotBreakTheOrder() throws {
        // The walk is over executed code cells only, so 1 then 2 stays in order across other cells.
        let result = try findings([code(1), markdown(), codeWithoutCount(source: "pending"), raw(), code(2)])
        #expect(kinds(result) == [.notebookUnexecutedCells, .notebookMayNotReproduce])
    }

    // MARK: Gaps

    @Test(arguments: [
        ([1, 2, 5], 1),
        ([3, 4], 1),
        ([2, 5, 9], 3),
        ([1, 2, 3], 0),
        ([1], 0),
        ([0, 1, 2], 0),
        ([0, 2], 1),
        ([5], 1),
        ([1, 4, 9, 20], 3)
    ])
    func gapsCountMissingRunsStartingFromOne(counts: [Int], expected: Int) throws {
        // Sorted so the count is not also an out-of-order case: only gaps are under test here.
        let result = try findings(counts.sorted().map { code($0) })
        let gaps = result.first { $0.kind == .notebookExecutionGaps }
        #expect((gaps?.count ?? 0) == expected)
        #expect(result.contains { $0.kind == .notebookMayNotReproduce } == (expected > 0))
    }

    @Test func gapsAloneAreCautionWithoutAnOrderFinding() throws {
        let result = try findings([code(2), code(3), code(7)])
        #expect(result == [
            PreviewFinding(kind: .notebookExecutionGaps, count: 2),
            PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
        ])
        #expect(result[0].severity == .caution)
    }

    // MARK: Cells that never ran

    @Test func unexecutedCellsUseOneBasedPositionsThatCountEveryCell() throws {
        let result = try findings([
            markdown(),                                  // 1
            code(1),                                     // 2
            code(nil, source: "df.head()"),              // 3
            markdown(),                                  // 4
            code(2),                                     // 5
            raw("not code, never counted"),              // 6
            codeWithoutCount(source: ["a = 1\n", "a"]),  // 7
            code(nil, source: "   \n\t"),                // 8: blank, ignored
            codeWithoutCount(source: [])                 // 9: empty, ignored
        ])
        #expect(result == [
            PreviewFinding(kind: .notebookUnexecutedCells, count: 2, detail: .cells([3, 7])),
            PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
        ])
        #expect(result[0].severity == .caution)
        #expect(result.allSatisfy { $0.lines.isEmpty })
    }

    @Test func nothingExecutedReportsOneFindingWithoutReproducibilityHint() throws {
        let result = try findings([markdown(), code(nil, source: "a = 1"), codeWithoutCount(source: "b = 2")])
        #expect(result == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
        #expect(result[0].severity == .info)
    }

    @Test func blankCodeCellsAreIgnoredWhetherOrNotAnythingRan() throws {
        let blanks: [Any] = ["", "  \n \t ", "\u{00A0}\u{3000}\n", [], ["", "  ", "\n"]]
        for source in blanks {
            #expect(try findings([code(nil, source: source), codeWithoutCount(source: source)]).isEmpty)
            #expect(try findings([code(1), code(nil, source: source), codeWithoutCount(source: source)]).isEmpty)
        }
    }

    @Test func aSingleNonBlankLineInASourceArrayIsEnough() throws {
        #expect(try findings([code(nil, source: ["\n", "  ", "x"])]) == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
    }

    // MARK: Error outputs

    @Test func savedErrorsAreReportedByCellPositionOnAnyCell() throws {
        let result = try findings([
            markdown(),                                                  // 1
            code(1, outputs: [streamOutput, errorOutput, errorOutput]),  // 2: two errors, one cell
            code(2, outputs: [streamOutput]),                            // 3: no error
            code(3, outputs: [errorOutput]),                             // 4
            ["cell_type": "markdown", "metadata": [String: Any](), "source": "m", "outputs": [errorOutput]]  // 5: not code
        ])
        #expect(result == [PreviewFinding(kind: .notebookErrorOutputs, count: 3, detail: .cells([2, 4, 5]))])
        #expect(result[0].severity == .caution)
    }

    @Test func errorOutputsAloneNeitherImplyNorSuppressReproducibilityFindings() throws {
        #expect(kinds(try findings([code(1, outputs: [errorOutput])])) == [.notebookErrorOutputs])
        let mixed = try findings([code(2, outputs: [errorOutput]), code(1)])
        #expect(kinds(mixed) == [.notebookOutOfOrder, .notebookErrorOutputs, .notebookMayNotReproduce])
        // An unexecuted cell with a saved error output still reports both facts.
        #expect(kinds(try findings([code(nil, source: "a", outputs: [errorOutput])])) == [.notebookNotExecuted, .notebookErrorOutputs])
    }

    // MARK: Execution count spellings

    @Test(arguments: [
        "null", "-1", "-0", "1.5", "1.0", "0.0", "1e2", "1E+2", "2147483648", "99999999999999999999",
        #""3""#, "true", "false", "[1]", "{}"
    ])
    func unusableExecutionCountsMeanNotExecutedAndNeverFailTheNotebook(lexeme: String) throws {
        let alone = try parse(rawNotebook([rawCode(count: lexeme)]))
        #expect(alone.findings == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
        // Next to an executed cell, the same cell is one that never ran.
        let beside = try parse(rawNotebook([rawCode(count: "1"), rawCode(count: lexeme)]))
        #expect(beside.findings == [
            PreviewFinding(kind: .notebookUnexecutedCells, count: 1, detail: .cells([2])),
            PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
        ])
    }

    @Test(arguments: [("0", 0), ("1", 1), ("7", 7), ("2147483647", 2_147_483_647)])
    func nonNegativeIntegersThatFitInInt32AreExecutionCounts(lexeme: String, value: Int) throws {
        let result = try parse(rawNotebook([rawCode(count: lexeme)])).findings
        // One executed cell; the only possible finding is a gap when it does not start at 0 or 1.
        #expect(result.contains { $0.kind == .notebookNotExecuted } == false)
        #expect(result.contains { $0.kind == .notebookExecutionGaps } == (value > 1))
    }

    @Test func missingAndDuplicatedExecutionCountFieldsAreNotExecutedAndDoNotFail() throws {
        let missing = try parse(rawNotebook([rawCode(count: nil)]))
        #expect(missing.findings == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
        // `NotebookShape` never reads execution_count, so a repeated name used to be accepted.
        let repeated = #"{"cell_type":"code","execution_count":1,"execution_count":2,"source":"x","outputs":[]}"#
        let result = try parse(rawNotebook([repeated]))
        #expect(result.findings == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
        #expect(result.text == rawNotebook([repeated]))
    }

    @Test func executionCountsOnMarkdownAndRawCellsAreIgnored() throws {
        let cells: [[String: Any]] = [
            code(3),
            ["cell_type": "markdown", "metadata": [String: Any](), "source": "m", "execution_count": 1],
            ["cell_type": "raw", "metadata": [String: Any](), "source": "r", "execution_count": 2, "outputs": [Any]()],
            raw("no count, not code"),
            markdown("no count, not code")
        ]
        #expect(try findings(cells) == [PreviewFinding(kind: .notebookExecutionGaps, count: 1),
                                        PreviewFinding(kind: .notebookMayNotReproduce, count: 1)])
    }

    // MARK: Result integrity

    @Test func findingsNeverChangeTheTextOrTheSensitiveRanges() throws {
        let secret = "synthetic-health-secret"
        let source = try notebook([
            code(3, source: ["password = \"\(secret)\"\n", "print(1)\n"], outputs: [errorOutput]),
            code(1),
            code(nil, source: "pending")
        ])
        let result = try parse(source)
        #expect(result.text.utf8.elementsEqual(source.utf8))
        #expect(result.syntax == .json)
        #expect(result.usesStructuredPrivacy)
        let bytes = Array(result.text.utf8)
        let spans = result.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
        #expect(spans.count == 1 && spans[0].contains(secret) && spans[0].hasPrefix("\"password"))
        // Counts 3 then 1: one descent, and sorted 1,3 skips a number.
        #expect(kinds(result.findings) == [.notebookOutOfOrder, .notebookExecutionGaps, .notebookUnexecutedCells,
                                           .notebookErrorOutputs, .notebookMayNotReproduce])
    }

    @Test func findingsHoldOnlyStructuralIntegers() throws {
        let marker = "synthetic-private-marker"
        let source = try notebook([
            code(5, source: "print('\(marker)-source')", outputs: [
                ["output_type": "error", "ename": "\(marker)-ename", "evalue": "\(marker)-evalue", "traceback": ["\(marker)-trace"]],
                ["output_type": "stream", "name": "stdout", "text": ["\(marker)-stream"]]
            ]),
            code(2, source: "x"),
            code(nil, source: "\(marker)-unrun")
        ], metadata: ["kernelspec": ["name": "\(marker)-kernel", "display_name": "\(marker)-display"],
                      "language_info": ["name": "\(marker)-language"]])
        let result = try parse(source).findings
        #expect(!result.isEmpty)
        #expect(!String(describing: result).contains(marker))
        for finding in result {
            #expect(finding.lines.isEmpty)
            switch finding.detail {
            case .none, .executionSequence, .cells: break
            default: Issue.record("Unexpected detail type for \(finding.kind)")
            }
        }
    }

    @Test func existingFailuresAreUnchangedByHealthChecks() throws {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(rawNotebook([#"{"cell_type":"code","execution_count":1}"#])) }
        #expect(throws: PreviewFailure.unsupportedFormat) { try parse(#"{"nbformat":3,"cells":[]}"#) }
    }

    // MARK: Bounds and cancellation

    @Test func manyCellsStayWithinTheStandardBudgetsAndBoundTheDetail() throws {
        // Six JSON nodes per cell keep 2,500 cells inside the standard 20,000-node budget.
        let total = 2_500
        let healthy = rawNotebook((1...total).map { rawCode(count: String($0)) })
        #expect(try parse(healthy).findings.isEmpty)

        let neverRan = rawNotebook([rawCode(count: "1")] + (2...total).map { _ in rawCode(count: "null") })
        let result = try parse(neverRan).findings
        let unexecuted = try #require(result.first { $0.kind == .notebookUnexecutedCells })
        #expect(unexecuted.count == total - 1)
        #expect(unexecuted.detail == .cells(Array(2...(PreviewFinding.maximumDetailValues + 1))))

        let reversed = rawNotebook((1...total).reversed().map { rawCode(count: String($0)) })
        let outOfOrder = try #require(try parse(reversed).findings.first { $0.kind == .notebookOutOfOrder })
        #expect(outOfOrder.count == total - 1)
        #expect(outOfOrder.detail == .executionSequence(Array((1...6).map { total - $0 + 1 })))
    }

    @Test func thousandsOfCellsBeyondTheNodeBudgetStillFailExplicitly() throws {
        let source = rawNotebook((1...5_000).map { rawCode(count: String($0)) })
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(source) }
    }

    @Test func cancellationStopsParsingBeforeFindingsAreProduced() async throws {
        let source = rawNotebook((1...2_000).map { rawCode(count: String($0)) })
        let task = Task { () throws -> ParsedTextDocument in
            while !Task.isCancelled { await Task.yield() }
            return try parse(source)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func deadlineStillAppliesToLargeNotebooks() async throws {
        let source = rawNotebook((1...2_000).map { rawCode(count: String($0)) })
        let context = RequestContext(budget: PreviewBudget(maxMilliseconds: 1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try JupyterNotebookAdapter().parse(DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        }
    }
}
