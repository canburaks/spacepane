import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Shared helpers for the package-family adapter tests.
enum PackageTestSupport {
    /// Built per use: a `RequestContext` dates its deadline from construction, so a shared static one
    /// would expire partway through a long parallel test run.
    static var context: RequestContext { RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)) }
    /// Fixed clock so expiry flags never depend on the day the tests run.
    static let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15

    /// The adapter's summary text as a JSON object.
    static func object(_ document: ParsedTextDocument, sourceLocation: SourceLocation = #_sourceLocation) -> [String: Any] {
        guard let value = (try? JSONSerialization.jsonObject(with: Data(document.text.utf8))) as? [String: Any] else {
            Issue.record("Summary is not a JSON object", sourceLocation: sourceLocation)
            return [:]
        }
        return value
    }

    /// What remains visible after the adapter's declared sensitive ranges are replaced, mirroring the
    /// shared privacy filter's range replacement. End-to-end concealment is covered by the pipeline tests.
    static func concealedText(_ document: ParsedTextDocument) -> String {
        var bytes = Array(document.text.utf8)
        for range in document.sensitiveRanges.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
            bytes.replaceSubrange(range.utf8Range, with: Array("••••".utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("package-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func entries(_ summary: [String: Any]) -> [[String: Any]] { summary["entries"] as? [[String: Any]] ?? [] }

    /// Runs `body` in a task that is already cancelled and reports whether it threw `CancellationError`.
    static func parseIsCancelled(_ body: @escaping @Sendable () throws -> Void) async -> Bool {
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { try body(); return false } catch is CancellationError { return true } catch { return false }
        }
        return await task.value
    }

    /// A source that serves bytes.
    static func source(_ data: Data) -> DataByteSource { DataByteSource(data) }
}
