import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct EmptyInputReader: PreviewFileReading {
    var data = Data()
    var totalByteCount = 0
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        try context.checkpoint()
        return FileBytes(data: data, totalByteCount: totalByteCount)
    }
}

private final class EmptyBinaryAdapter: BinaryFormatAdapter, Sendable {
    let calls = Mutex(0)
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        calls.withLock { $0 += 1 }
        throw PreviewFailure.malformedDocument
    }
}

@Suite("Empty structured source policy")
struct EmptyStructuredInputTests {
    @Test func binaryFamiliesRequireExplicitEmptyOptIn() async {
        let adapter = EmptyBinaryAdapter()
        let url = URL(fileURLWithPath: "/unused/empty.txt")
        let strict = PreviewPipeline(registrations: [.init(formatID: .plainText, binaryAdapter: { adapter })], reader: EmptyInputReader())
        #expect(await strict.preview(url: url) == .unavailable(.malformedDocument))
        #expect(adapter.calls.withLock { $0 } == 1)
        let empty = PreviewPipeline(registrations: [
            .init(formatID: .plainText, emptyInputPolicy: .emptyPreview, binaryAdapter: { adapter })
        ], reader: EmptyInputReader())
        guard case .ready(let presentation) = await empty.preview(url: url) else { Issue.record("Expected explicit empty state"); return }
        #expect(presentation.text.isEmpty)
        #expect(adapter.calls.withLock { $0 } == 1, "The empty policy must run before parsing")
    }

    @Test(arguments: ["json", "jsonl", "yaml", "toml", "xml", "plist", "stringsdict", "jsonc", "json5", "ipynb", "csv", "tsv"])
    func zeroByteSourcesShowTheEmptyStateInsteadOfMalformed(suffix: String) async {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: EmptyInputReader())
        let result = await pipeline.previewResult(url: URL(fileURLWithPath: "/unused/empty.\(suffix)"))
        guard case .ready(let presentation) = result.outcome else { Issue.record("Empty .\(suffix): \(result.outcome)"); return }
        #expect(presentation.text.isEmpty && presentation.byteCount == 0)
        #expect(presentation.images.isEmpty && presentation.findings.isEmpty)
        #expect(result.effectiveBudget != nil)
    }

    @Test func nonemptyMalformedSourceStillFails() async {
        let reader = EmptyInputReader(data: Data("{".utf8), totalByteCount: 1)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: reader)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/malformed.json")) == .unavailable(.malformedDocument))
    }

    @Test func missingBytesAreNotClaimedToBeAnEmptyFile() async {
        let reader = EmptyInputReader(totalByteCount: 12)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: reader)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/unavailable.json")) == .unavailable(.malformedDocument))
    }

    @Test func aDisabledEmptySourceStillHonorsPolicy() async {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: EmptyInputReader())
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .json)
        let result = await pipeline.previewResult(url: URL(fileURLWithPath: "/unused/empty.json"), preferences: preferences)
        #expect(result.outcome == .disabledByUser(.json))
        #expect(result.effectiveBudget == nil)
    }
}
