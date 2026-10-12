import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private let notebookSecret = "synthetic-host-matrix-secret"
private let notebookPipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

private final class NotebookReadCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct CountingNotebookReader: PreviewFileReading {
    let data: Data
    let reads: NotebookReadCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
}

private struct NotebookFixture {
    let directory: URL
    let url: URL
    init(_ data: Data) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("analysis.ipynb")
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func notebookData(cells: [[String: Any]], nbformat: Any = 4, metadata: [String: Any] = [:]) throws -> Data {
    let object: [String: Any] = ["nbformat": nbformat, "nbformat_minor": 5, "metadata": metadata, "cells": cells]
    return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

private func secretNotebook() throws -> Data {
    let ansiAssignment = "\u{1B}[0;32m----> 1\u{1B}[0m password\u{1B}[0m \u{1B}[0;34m=\u{1B}[0m \u{1B}[0;34m'\(notebookSecret)'\u{1B}[0m"
    return try notebookData(cells: [
        ["cell_type": "markdown", "metadata": [String: Any](), "source": ["# Report\n", "Synthetic notebook."]],
        ["cell_type": "code", "metadata": [String: Any](), "execution_count": 1,
         "source": ["password = \"\(notebookSecret)\"\n", "print(42)\n"],
         "outputs": [
            ["output_type": "stream", "name": "stdout", "text": ["token: \(notebookSecret)\n", "42\n"]],
            ["output_type": "error", "ename": "ValueError", "evalue": "bad value",
             "traceback": ["Traceback (most recent call last)", ansiAssignment, "ValueError: bad value"]]
         ]]
    ], metadata: ["token": notebookSecret, "language_info": ["name": "python"]])
}

@Test func notebookPipelineConcealsSecretsInsideStringsAndNeverMutatesTheSource() async throws {
    let original = try secretNotebook()
    let fixture = try NotebookFixture(original)
    defer { fixture.remove() }
    let before = try fixture.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    guard case .ready(let result) = await notebookPipeline.preview(url: fixture.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    #expect(result.formatID == .jupyterNotebook)
    #expect(result.syntax == .json)
    #expect(result.encoding == .utf8)
    #expect(result.byteCount == original.count)
    #expect(!result.text.contains(notebookSecret))
    #expect(result.text.contains("print(42)"))
    #expect(result.text.contains("Traceback (most recent call last)"))
    #expect(result.redactionCount >= 4)
    #expect(try Data(contentsOf: fixture.url) == original)
    #expect(try fixture.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before)
    // Whole-token concealment keeps the safe text valid JSON once the inert token is read as a scalar.
    let parsed = try JSONSerialization.jsonObject(with: Data(result.text.replacingOccurrences(of: "••••", with: "null").utf8))
    let root = try #require(parsed as? [String: Any])
    #expect(root["nbformat"] as? Int == 4)
    #expect((root["cells"] as? [Any])?.count == 2)
}

@Test func notebookWithoutSecretsPassesThroughUnchanged() async throws {
    let original = try notebookData(cells: [["cell_type": "code", "metadata": [String: Any](), "execution_count": NSNull(),
                                             "source": ["print('password manager')\n"], "outputs": [Any]()]])
    let fixture = try NotebookFixture(original)
    defer { fixture.remove() }
    guard case .ready(let result) = await notebookPipeline.preview(url: fixture.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    #expect(result.text == String(decoding: original, as: UTF8.self))
    #expect(result.redactionCount == 0)
}

@Test func disabledNotebookTypeIsNotReadParsedOrFallenBackToText() async throws {
    var preferences = PreviewPreferencesSnapshot.defaults
    preferences.setEnabled(false, for: .jupyterNotebook)
    let reads = NotebookReadCounter()
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                   reader: CountingNotebookReader(data: try secretNotebook(), reads: reads))
    let url = URL(fileURLWithPath: "/unused/analysis.ipynb")
    #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.jupyterNotebook))
    #expect(await pipeline.inspect(url: url, preferences: preferences) == .disabledByUser(.jupyterNotebook))
    #expect(reads.value == 0)
    // Enabled by default, and then it reads exactly once.
    #expect(await pipeline.inspect(url: url) == .enabled(.jupyterNotebook))
    _ = await pipeline.preview(url: url)
    #expect(reads.value == 1)
}

@Test func unsupportedAndMalformedNotebooksAreExplicitFailures() async throws {
    let legacy = try NotebookFixture(Data(#"{"nbformat":3,"nbformat_minor":0,"worksheets":[{"cells":[]}]}"#.utf8))
    defer { legacy.remove() }
    #expect(await notebookPipeline.preview(url: legacy.url) == .unavailable(.unsupportedFormat))
    let malformed = try NotebookFixture(Data(#"{"nbformat":4,"cells":[{"cell_type":"code"}]}"#.utf8))
    defer { malformed.remove() }
    #expect(await notebookPipeline.preview(url: malformed.url) == .unavailable(.malformedDocument))
    let truncated = try NotebookFixture(Data(#"{"nbformat":4,"cells":["#.utf8))
    defer { truncated.remove() }
    #expect(await notebookPipeline.preview(url: truncated.url) == .unavailable(.malformedDocument))
}

@Test func notebookImagesAreOmittedAndExplicitInputBudgetsStillApply() async throws {
    // Unsupported image bytes become inert source placeholders, without claiming Pages availability.
    let image = try NotebookFixture(try notebookData(cells: [["cell_type": "code", "metadata": [String: Any](), "source": "",
        "outputs": [["output_type": "display_data", "metadata": [String: Any](), "data": ["image/png": String(repeating: "A", count: 40_000)]]]]]))
    defer { image.remove() }
    guard case .ready(let result) = await notebookPipeline.preview(url: image.url) else {
        Issue.record("Expected image source omission"); return
    }
    #expect(result.origin == .converted)
    #expect(result.images.isEmpty)
    #expect(!result.text.contains(String(repeating: "A", count: 40_000)))
    // A caller's explicit standard budget still overrides the notebook's larger default.
    let huge = try NotebookFixture(Data(repeating: 32, count: PreviewBudget.standard.maxInputBytes + 1))
    defer { huge.remove() }
    #expect(await notebookPipeline.preview(url: huge.url, budget: .standard) == .unavailable(.inputTooLarge))
}

@Test func notebookParsingHonorsCancellationThroughThePipeline() async throws {
    let cells = (0..<400).map { index -> [String: Any] in
        ["cell_type": "code", "metadata": [String: Any](), "source": ["value = \(index)\n"], "outputs": [Any]()]
    }
    let fixture = try NotebookFixture(try notebookData(cells: cells))
    defer { fixture.remove() }
    let task = Task { await notebookPipeline.preview(url: fixture.url) }
    task.cancel()
    let outcome = await task.value
    #expect(outcome == .cancelled)
}

// MARK: Notebook health findings

private func healthCell(_ count: Int?, source: String, outputs: [[String: Any]] = []) -> [String: Any] {
    ["cell_type": "code", "metadata": [String: Any](), "execution_count": count.map { $0 as Any } ?? NSNull(),
     "source": [source], "outputs": outputs]
}

@Test func notebookHealthFindingsReachThePresentationAndLeaveConcealmentAndSourceUntouched() async throws {
    let error: [String: Any] = ["output_type": "error", "ename": "ValueError", "evalue": "bad", "traceback": ["Traceback"]]
    let original = try notebookData(cells: [
        ["cell_type": "markdown", "metadata": [String: Any](), "source": ["# Report\n"]],
        healthCell(3, source: "password = \"\(notebookSecret)\"\n", outputs: [error]),
        healthCell(1, source: "print(1)\n"),
        healthCell(nil, source: "pending()\n")
    ])
    let fixture = try NotebookFixture(original)
    defer { fixture.remove() }
    let before = try fixture.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    guard case .ready(let result) = await notebookPipeline.preview(url: fixture.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    // Cautions first in declaration order, then the informational hint. The concealed password
    // also yields the secret inventory's own finding, which is checked separately.
    let notebookKinds = Set(PreviewFindingKind.allCases.filter { $0.rawValue.hasPrefix("notebook.") })
    let health = result.findings.filter { notebookKinds.contains($0.kind) }
    #expect(health == [
        PreviewFinding(kind: .notebookOutOfOrder, count: 1, detail: .executionSequence([3, 1])),
        PreviewFinding(kind: .notebookExecutionGaps, count: 1),
        PreviewFinding(kind: .notebookUnexecutedCells, count: 1, detail: .cells([4])),
        PreviewFinding(kind: .notebookErrorOutputs, count: 1, detail: .cells([2])),
        PreviewFinding(kind: .notebookMayNotReproduce, count: 1)
    ])
    #expect(health.allSatisfy { $0.lines.isEmpty })
    #expect(result.findings.filter { !notebookKinds.contains($0.kind) }.map(\.kind) == [.secretSensitiveField])
    // The existing concealment is unchanged, and the findings never carry the secret.
    #expect(!result.text.contains(notebookSecret))
    #expect(!String(describing: result.findings).contains(notebookSecret))
    #expect(result.redactionCount == 1)
    #expect(result.text.contains("pending()"))
    #expect(try Data(contentsOf: fixture.url) == original)
    #expect(try fixture.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before)
}

@Test func healthyNotebookHasNoFindingsAndNeverRunNotebookHasOne() async throws {
    let healthy = try NotebookFixture(try notebookData(cells: [healthCell(1, source: "a = 1\n"), healthCell(2, source: "a\n")]))
    defer { healthy.remove() }
    guard case .ready(let clean) = await notebookPipeline.preview(url: healthy.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    #expect(clean.findings.isEmpty)

    let neverRun = try NotebookFixture(try notebookData(cells: [healthCell(nil, source: "a = 1\n")]))
    defer { neverRun.remove() }
    guard case .ready(let fresh) = await notebookPipeline.preview(url: neverRun.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    #expect(fresh.findings == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
}

@Test func unusableExecutionCountsDoNotFailTheNotebookPreview() async throws {
    let source = #"{"nbformat":4,"cells":[{"cell_type":"code","execution_count":-3,"source":"x","outputs":[]},"#
        + #"{"cell_type":"code","execution_count":1.5,"source":"y","outputs":[]},"#
        + #"{"cell_type":"code","execution_count":99999999999,"source":"z","outputs":[]}]}"#
    let fixture = try NotebookFixture(Data(source.utf8))
    defer { fixture.remove() }
    guard case .ready(let result) = await notebookPipeline.preview(url: fixture.url) else {
        Issue.record("Expected a ready notebook preview")
        return
    }
    #expect(result.text == source)
    #expect(result.findings == [PreviewFinding(kind: .notebookNotExecuted, count: 1)])
}
