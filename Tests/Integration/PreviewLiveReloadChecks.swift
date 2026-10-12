import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Drives the production `PreviewSession` against temporary files: live reload keeps one request's
/// generation, follows atomic saves and deletions, honors the preference and page visibility, and stops
/// when the session closes. It never reads user preferences or files, and does not start a UI.
@main @MainActor
struct PreviewLiveReloadChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-reload-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await reloadsUnderTheSameGeneration(root)
        try await followsAtomicSavesAndDeletion(root)
        try await honorsThePreferenceAndVisibility(root)
        try await closingStopsReloading(root)
        try await policyChangesStillStartANewRequest(root)
        try await retainsEffectiveLimitsAcrossReloads(root)
        print("Passed 6 live-reload session checks (temporary files; no Finder or UI validation).")
    }

    private static func session() -> PreviewSession {
        PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations))
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    private static func eventually(_ message: String, timeout: Duration = .seconds(8), _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func quiet(_ duration: Duration = .milliseconds(900)) async throws { try await Task.sleep(for: duration) }

    private static func text(_ session: PreviewSession) -> String? {
        if case .ready(let presentation) = session.outcome { return presentation.text }
        return nil
    }

    private static func write(_ value: Int, to url: URL, atomically: Bool = false) throws {
        try Data(#"{"version":\#(value)}"#.utf8).write(to: url, options: atomically ? [.atomic] : [])
    }

    private static func reloadsUnderTheSameGeneration(_ root: URL) async throws {
        let source = root.appendingPathComponent("same-generation.json")
        try write(1, to: source)
        let session = session()
        defer { session.close() }
        session.open(source, preferences: .defaults)
        try await eventually("The first preview did not finish") { !session.isLoading && text(session)?.contains("1") == true }
        let generation = session.generation
        try write(2, to: source)
        try await eventually("An edit did not reload the preview") { text(session)?.contains("2") == true }
        try check(session.generation == generation, "A live reload must keep the request generation so the pane keeps its place")
        try check(!session.isLoading, "A live reload must not flash the loading state")
        try check(session.sourceURL == source, "A live reload keeps the source")
    }

    private static func followsAtomicSavesAndDeletion(_ root: URL) async throws {
        let source = root.appendingPathComponent("atomic.json")
        try write(1, to: source)
        let session = session()
        defer { session.close() }
        session.open(source, preferences: .defaults)
        try await eventually("The first preview did not finish") { text(session)?.contains("1") == true }
        let generation = session.generation
        try write(2, to: source, atomically: true)
        try await eventually("An atomic save did not reload the preview") { text(session)?.contains("2") == true }
        try write(3, to: source)
        try await eventually("The file after an atomic save is no longer watched") { text(session)?.contains("3") == true }
        try FileManager.default.removeItem(at: source)
        try await eventually("A deleted file did not show the unavailable state") {
            session.outcome == .unavailable(.missingFile)
        }
        try check(session.generation == generation, "Showing a deletion keeps the request generation")
    }

    private static func honorsThePreferenceAndVisibility(_ root: URL) async throws {
        let source = root.appendingPathComponent("switches.json")
        try write(1, to: source)
        let session = session()
        defer { session.close() }
        var off = PreviewPreferencesSnapshot.defaults
        off.reloadsOnFileChange = false
        session.open(source, preferences: off)
        try await eventually("The first preview did not finish") { text(session)?.contains("1") == true }
        try write(2, to: source)
        try await quiet()
        try check(text(session)?.contains("1") == true && text(session)?.contains("2") == false,
                  "With reloading off an edit must not reread the file")
        // Turning it on starts watching the already open file.
        session.settingsChanged(.defaults)
        try write(3, to: source)
        try await eventually("Turning reloading on did not watch the file") { text(session)?.contains("3") == true }
        // Turning it off again stops it.
        session.settingsChanged(off)
        try write(4, to: source)
        try await quiet()
        try check(text(session)?.contains("3") == true, "Turning reloading off must stop watching")
        // A hidden page does not reload; showing it again reads the file as it is now.
        session.settingsChanged(.defaults)
        session.previewVisibilityChanged(false)
        try write(5, to: source)
        try await quiet()
        try check(text(session)?.contains("5") == false, "A hidden preview page must not reload")
        session.previewVisibilityChanged(true)
        try await eventually("Showing the page again did not refresh a changed file") { text(session)?.contains("5") == true }
    }

    private static func closingStopsReloading(_ root: URL) async throws {
        let source = root.appendingPathComponent("closed.json")
        try write(1, to: source)
        let session = session()
        session.open(source, preferences: .defaults)
        try await eventually("The first preview did not finish") { text(session)?.contains("1") == true }
        session.close()
        try write(2, to: source)
        try await quiet()
        try check(session.outcome == nil && session.sourceURL == nil, "A closed session must not reload its old file")
        // Cancelling (the window closing) also ends the watch and forgets the result.
        let other = root.appendingPathComponent("cancelled.json")
        try write(1, to: other)
        session.open(other, preferences: .defaults)
        try await eventually("The second preview did not finish") { text(session)?.contains("1") == true }
        session.cancel()
        try write(2, to: other)
        try await quiet()
        try check(session.outcome == nil, "A cancelled session must not reload")
        session.close()
    }

    private static func policyChangesStillStartANewRequest(_ root: URL) async throws {
        let source = root.appendingPathComponent("policy.json")
        try write(1, to: source)
        let session = session()
        defer { session.close() }
        session.open(source, preferences: .defaults)
        try await eventually("The first preview did not finish") { text(session)?.contains("1") == true }
        let generation = session.generation
        var disabled = PreviewPreferencesSnapshot.defaults
        disabled.setEnabled(false, for: .json)
        session.settingsChanged(disabled)
        try check(session.generation != generation, "A file-type policy change must still replace the request")
        try await eventually("Disabling the type did not show the disabled state") { session.outcome == .disabledByUser(.json) }
        // Re-enabling reads the file again and live reload resumes under the new request.
        session.settingsChanged(.defaults)
        try await eventually("Re-enabling did not show the file") { text(session)?.contains("1") == true }
        try write(2, to: source)
        try await eventually("Reloading did not resume after a policy change") { text(session)?.contains("2") == true }
    }

    private static func retainsEffectiveLimitsAcrossReloads(_ root: URL) async throws {
        let source = root.appendingPathComponent("effective-limits.txt")
        let limits = PreviewBudget(maxInputBytes: 32, maxOutputUTF8Bytes: 256, maxMilliseconds: 4_000)
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: [
            .init(formatID: .plainText, defaultBudget: limits, binaryAdapter: { BudgetCheckAdapter() })
        ]))
        defer { session.close() }
        try Data("first".utf8).write(to: source)
        session.open(source, preferences: .defaults)
        try await eventually("The budget check did not open") { text(session) == "first" }
        try check(session.result?.effectiveBudget == limits, "The initial request lost the family's effective limits")
        let generation = session.generation
        try Data(String(repeating: "x", count: 64).utf8).write(to: source)
        try await eventually("The oversized edit did not show its limit state") {
            session.outcome == .unavailable(.inputTooLarge)
        }
        try check(session.result?.effectiveBudget == limits, "The live-reload failure lost the actual limit")
        try check(session.generation == generation, "A limit-state reload replaced the request generation")
        try Data("recovered".utf8).write(to: source)
        try await eventually("The file did not recover after shrinking") { text(session) == "recovered" }
        try check(session.result?.effectiveBudget == limits, "Recovery lost the actual limits")
        var disabled = PreviewPreferencesSnapshot.defaults
        disabled.setEnabled(false, for: .plainText)
        session.settingsChanged(disabled)
        try await eventually("The budget check did not honor disabled policy") {
            session.outcome == .disabledByUser(.plainText)
        }
        try check(session.result?.effectiveBudget == nil, "Disabled content retained stale displayed limits")
        session.cancel()
        try check(session.result == nil, "Cancellation retained the prior result metadata")
    }
}

private struct BudgetCheckAdapter: BinaryFormatAdapter {
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: String(decoding: input.data, as: UTF8.self))
    }
}
