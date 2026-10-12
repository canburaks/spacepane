import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats

@main @MainActor
struct PreviewMonitorRearmChecks {
    private struct Failure: Error { let message: String }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-rearm-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic.txt"), bytes = Data("ordinary synthetic text".utf8)
        try bytes.write(to: file)
        var failures: [String] = []
        do { try await failedStartRequiresNewRequest(file) } catch { failures.append("failed-start: \(error)") }
        do { try await unavailableContentNeverStarts(file) } catch { failures.append("unavailable: \(error)") }
        if !failures.isEmpty { throw Failure(message: failures.joined(separator: "; ")) }
        let after = try Data(contentsOf: file)
        try check(after == bytes, "Source changed during lifecycle checks")
        print("Passed 2 deterministic companion monitor-rearm checks (owned files; no provider/Finder proof).")
    }
    private static func toggleVisibilityAndAppearance(_ session: PreviewSession) {
        session.previewVisibilityChanged(false); session.previewVisibilityChanged(true)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.reloadsOnFileChange = false; session.settingsChanged(preferences)
        preferences.reloadsOnFileChange = true; session.settingsChanged(preferences)
        preferences.typography.fontSize = 18; session.settingsChanged(preferences)
    }
    private static func failedStartRequiresNewRequest(_ file: URL) async throws {
        var attempts = 0
        var successfulReloader: PreviewLiveReloader?
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations),
            startWatching: { reloader, url in
                attempts += 1
                if attempts == 1 { return false }
                successfulReloader = reloader
                return reloader.start(watching: url)
            })
        defer { session.close() }
        session.open(file, preferences: .defaults)
        await session.currentRequest?.value
        try check(attempts == 1 && !session.isLoading, "Initial attempt did not finish")
        let generation = session.generation
        toggleVisibilityAndAppearance(session)
        try check(attempts == 1, "Visibility or appearance implicitly retried a refused monitor start")
        try check(session.generation == generation && session.sourceURL == file, "Appearance replaced the request or URL")
        session.open(file, preferences: .defaults)
        await session.currentRequest?.value
        try check(attempts == 2 && successfulReloader?.isWatching == true, "Explicit new request did not regain eligibility")
        session.close()
        try check(successfulReloader?.isWatching == false, "Closing retained the monitor")
    }
    private static func unavailableContentNeverStarts(_ file: URL) async throws {
        var attempts = 0
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations,
            reader: RefusedReader()), startWatching: { _, _ in attempts += 1; return false })
        defer { session.close() }
        session.open(file, preferences: .defaults)
        await session.currentRequest?.value
        try check(session.outcome == .unavailable(.unavailableContent), "Refusal was not displayed")
        toggleVisibilityAndAppearance(session)
        try check(attempts == 0, "An unavailable source started a monitor")
    }
    private struct RefusedReader: PreviewFileReading {
        func read(url: URL, context: RequestContext) throws -> FileBytes { throw PreviewFailure.unavailableContent }
    }
}
