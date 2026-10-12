import Foundation
import PreviewContracts

/// Health findings for a validated notebook: whether saved results can be trusted to match the code.
/// They come from the JSON tree the adapter already built and carry only structural integers (execution
/// counts and one-based cell positions), never source, output text, error names, metadata or kernel
/// names. Nothing runs, and no cell content is copied.
///
/// Cell positions count every cell, markdown and raw included, as the rendered notebook view numbers
/// them. `lines` stay empty because notebook source is JSON and concealment can shift displayed lines.
enum NotebookHealth {
    /// Execution numbers shown for the first out-of-order step: the cell before it and what follows.
    static let sequenceLength = 6
    /// Highest execution number accepted; a larger or malformed value counts as "not executed".
    private static let largestExecutionCount = Int(Int32.max)

    /// Call after `NotebookShape.validate`: the shape guarantees the fields read here are typed and
    /// unique, except `execution_count`, which validation never reads and which is handled leniently.
    static func findings(in root: NotebookJSONValue, bytes: [UInt8], context: RequestContext) throws -> [PreviewFinding] {
        guard case .array(let cells)? = try root.member("cells") else { return [] }
        var tally = Tally()
        for (index, cell) in cells.enumerated() {
            try context.checkpoint()
            try tally.record(cell, position: index + 1, bytes: bytes)
        }
        try context.checkpoint()
        return tally.findings
    }

    /// Cell positions in ascending order. Only the first few are kept for the finding's detail, so
    /// a notebook with thousands of flagged cells allocates nothing proportional to them.
    private struct Positions {
        private(set) var count = 0
        private(set) var kept: [Int] = []

        mutating func add(_ position: Int) {
            count += 1
            if kept.count < PreviewFinding.maximumDetailValues { kept.append(position) }
        }
    }

    private struct Tally {
        /// Execution counts of the executed code cells, in cell order.
        var executed: [Int] = []
        /// Code cells with source text and no usable execution count.
        var unexecuted = Positions()
        /// Cells of any type with at least one saved error output.
        var withErrors = Positions()

        mutating func record(_ cell: NotebookJSONValue, position: Int, bytes: [UInt8]) throws {
            if case .string(let type)? = try cell.member("cell_type"), type.value.utf8.elementsEqual("code".utf8) {
                if let count = NotebookHealth.executionCount(of: cell, bytes: bytes) {
                    executed.append(count)
                } else if let source = try cell.member("source"), NotebookHealth.hasText(source) {
                    unexecuted.add(position)
                }
            }
            let outputs = try cell.member("outputs")
            if NotebookHealth.hasErrorOutput(outputs) { withErrors.add(position) }
        }

        var findings: [PreviewFinding] {
            var result: [PreviewFinding] = []
            let (descents, firstDescent) = self.descents
            if let firstDescent {
                // Start at the cell before the first descent so the reader sees what it followed.
                let sequence = executed[(firstDescent - 1)...].prefix(NotebookHealth.sequenceLength)
                result.append(PreviewFinding(kind: .notebookOutOfOrder, count: descents,
                                             detail: .executionSequence(Array(sequence))))
            }
            let gaps = self.gaps
            if gaps > 0 { result.append(PreviewFinding(kind: .notebookExecutionGaps, count: gaps)) }
            // Cells that never ran only matter next to cells that did; alone they mean "not executed".
            let skippedCells = !executed.isEmpty && unexecuted.count > 0
            if skippedCells {
                result.append(PreviewFinding(kind: .notebookUnexecutedCells, count: unexecuted.count,
                                             detail: .cells(unexecuted.kept)))
            } else if executed.isEmpty, unexecuted.count > 0 {
                result.append(PreviewFinding(kind: .notebookNotExecuted, count: 1))
            }
            if withErrors.count > 0 {
                result.append(PreviewFinding(kind: .notebookErrorOutputs, count: withErrors.count,
                                             detail: .cells(withErrors.kept)))
            }
            if descents > 0 || gaps > 0 || skippedCells {
                result.append(PreviewFinding(kind: .notebookMayNotReproduce, count: 1))
            }
            return result
        }

        /// Steps where an executed cell ran no later than the executed cell before it, and the index of
        /// the first such cell. Equal counts qualify: a kernel numbers each run once, so a repeat means
        /// the saved results come from different sessions.
        private var descents: (count: Int, first: Int?) {
            var count = 0
            var first: Int?
            for index in executed.indices.dropFirst() where executed[index] <= executed[index - 1] {
                count += 1
                first = first ?? index
            }
            return (count, first)
        }

        /// Runs of missing numbers between the sorted distinct counts, starting from 1.
        private var gaps: Int {
            let ordered = executed.sorted()
            guard let smallest = ordered.first else { return 0 }
            var gaps = smallest > 1 ? 1 : 0
            for index in ordered.indices.dropFirst() where ordered[index] - ordered[index - 1] > 1 { gaps += 1 }
            return gaps
        }
    }

    /// A non-negative integer that fits in `Int32`, read from the exact spelling. Null, missing, signed,
    /// fractional, exponent, leading-zero, huge and wrong-typed values are "not executed", never a
    /// failure: this is an annotation, so it must not reject a notebook the preview already accepts.
    private static func executionCount(of cell: NotebookJSONValue, bytes: [UInt8]) -> Int? {
        // A repeated name makes the value ambiguous, so it is treated like a missing one.
        guard case .number(let span)? = try? cell.member("execution_count") else { return nil }
        let lexeme = bytes[span]
        guard (1...10).contains(lexeme.count), lexeme.allSatisfy({ (48...57).contains($0) }),
              lexeme.count == 1 || lexeme.first != 48 else { return nil }
        let value = lexeme.reduce(0) { $0 * 10 + Int($1 - 48) }
        return value <= largestExecutionCount ? value : nil
    }

    /// Source with at least one non-whitespace character, in either nbformat multiline form.
    private static func hasText(_ source: NotebookJSONValue) -> Bool {
        switch source {
        case .string(let token): containsText(token)
        case .array(let lines): lines.contains { if case .string(let token) = $0 { containsText(token) } else { false } }
        default: false
        }
    }

    private static func containsText(_ token: NotebookJSONString) -> Bool {
        token.value.unicodeScalars.contains { !$0.properties.isWhitespace }
    }

    private static func hasErrorOutput(_ outputs: NotebookJSONValue?) -> Bool {
        guard case .array(let items)? = outputs else { return false }
        return items.contains { output in
            // `output_type` was validated as a unique string.
            if case .string(let type)? = try? output.member("output_type") { type.value.utf8.elementsEqual("error".utf8) } else { false }
        }
    }
}
