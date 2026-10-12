import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewPreferences

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor private final class WeakTransferReference {
    weak var value: AppearanceThemeTransfer?
    init(_ value: AppearanceThemeTransfer?) { self.value = value }
}

/// Suspends even after task cancellation to characterize a noncooperative native read.
private actor SuspendedThemeReader {
    private var requests: [String: CheckedContinuation<PreviewAppearance, any Error>] = [:]

    func read(_ url: URL) async throws -> PreviewAppearance {
        try await withCheckedThrowingContinuation { requests[url.lastPathComponent] = $0 }
    }

    func hasRequest(_ name: String) -> Bool { requests[name] != nil }

    func complete(_ name: String, with appearance: PreviewAppearance) {
        requests.removeValue(forKey: name)?.resume(returning: appearance)
    }
}

/// Actual companion models, isolated temporary storage and inert synthetic fixtures.
/// These checks do not launch Finder, file sheets, VoiceOver or the companion UI.
@main @MainActor
struct AppearanceInteractionChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await profilesPersistAndPreservePolicy(root)
        try await themeTransferPreservesPolicyAndSource(root)
        try await importSurvivesSaveFailureAndRetry(root)
        try await cancelledAndReplacedImportsCannotApply(root)
        try await pickerCancellationPreservesPreview(root)
        print("Passed 5 appearance interaction groups (isolated models; no Finder/UI validation).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    private static func eventually(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    nonisolated private static func appearance() -> PreviewAppearance {
        PreviewAppearance(typography: PreviewTypography(fontSize: 26, wrapsLines: false,
            fontFamily: "Missing Fixture Family", weight: .semibold, italic: true,
            lineSpacing: 8, characterSpacing: 2, ligatures: false, tabWidth: 8,
            showsLineNumbers: true), theme: .highContrast,
            syntaxStyle: PreviewSyntaxStyle(usesColor: false, boldRoles: [.key, .type], italicRoles: [.comment]))
    }

    private static func profilesPersistAndPreservePolicy(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("profiles.json"))
        let initial = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true])
        try await store.save(initial)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        settings.applyAppearance(appearance())
        settings.saveAppearanceProfile(name: "Fixture 🌍")
        guard let profile = settings.snapshot.appearanceProfiles.first else {
            throw CheckFailure(description: "Profile was not created")
        }
        let beforeRejected = settings.snapshot
        settings.saveAppearanceProfile(name: profile.name)
        settings.saveAppearanceProfile(name: " Leading")
        try check(settings.snapshot == beforeRejected, "Duplicate and invalid names must be rejected in the model")
        settings.resetAppearance()
        settings.applyAppearanceProfile(id: profile.id)
        try check(settings.snapshot.appearance == appearance(), "Profile apply must restore every field")
        for number in 1..<PreviewAppearanceProfile.maximumCount {
            settings.saveAppearanceProfile(name: "Fixture \(number)")
        }
        let atLimit = settings.snapshot
        settings.saveAppearanceProfile(name: "Over Limit")
        try check(settings.snapshot == atLimit, "A full profile list must remain bounded")
        settings.deleteAppearanceProfile(id: profile.id)
        settings.deleteAppearanceProfile(id: profile.id)
        try check(settings.snapshot.appearance == appearance(), "Deleting a profile must retain its active appearance")
        try check(settings.snapshot.defaultEnabled == initial.defaultEnabled
                  && settings.snapshot.formatOverrides == initial.formatOverrides, "Profiles must retain file policy")
        try await eventually("Profile changes did not persist") { settings.saveState == .saved }
        let relaunched = CompanionSettings(store: store, storageMode: .privateOnly)
        await relaunched.load()
        try check(relaunched.snapshot == settings.snapshot && !relaunched.recoveredSettings,
                  "A new model instance must restore names, IDs, deletions and appearance")
    }

    private static func themeTransferPreservesPolicyAndSource(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("transfer-preferences.json"))
        let profile = PreviewAppearanceProfile(name: "Retained", appearance: PreviewAppearance())
        let initial = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
                                                appearanceProfiles: [profile])
        try await store.save(initial)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let transfer = AppearanceThemeTransfer()
        let source = root.appendingPathComponent("inert-theme.json")
        guard let exported = transfer.prepareExport(appearance()) else {
            throw CheckFailure(description: "Export did not produce an inert document")
        }
        try exported.write(to: source)
        transfer.exportCompleted(.failure(CocoaError(.userCancelled)))
        try check(transfer.message == nil && settings.snapshot == initial,
                  "Cancelling an export must preserve settings without reporting failure")
        transfer.importCompleted(.failure(CocoaError(.userCancelled)), settings: settings)
        transfer.importCompleted(.failure(CancellationError()), settings: settings)
        transfer.importCompleted(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)), settings: settings)
        try check(transfer.message == nil && settings.snapshot == initial && !transfer.isReading,
                  "Cancelling an import picker must not start a read or change settings")
        transfer.importCompleted(.success(source), settings: settings)
        try await eventually("Theme import did not finish") { !transfer.isReading }
        try check(transfer.message == .imported && settings.snapshot.appearance == appearance(),
                  "Import must apply every validated appearance value")
        try check(settings.snapshot.defaultEnabled == initial.defaultEnabled
                  && settings.snapshot.formatOverrides == initial.formatOverrides
                  && settings.snapshot.appearanceProfiles == [profile], "Theme imports must retain policy and profiles")
        let readBack = try Data(contentsOf: source)
        try check(readBack == exported, "Theme reads must not modify their source")
        try await eventually("Imported appearance did not save") { settings.saveState == .saved }
        let relaunched = CompanionSettings(store: store, storageMode: .privateOnly)
        await relaunched.load()
        try check(relaunched.snapshot == settings.snapshot, "Imported appearance must survive model recreation")
        let beforeInvalid = settings.snapshot
        let malformed = root.appendingPathComponent("malformed-theme.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: malformed)
        transfer.importCompleted(.success(malformed), settings: settings)
        try await eventually("Malformed import did not finish") { !transfer.isReading }
        try check(transfer.message == .importError(.unsupportedVersion) && settings.snapshot == beforeInvalid,
                  "Rejected imports must leave settings untouched and map to a typed failure")
        transfer.exportCompleted(.success(source))
        try check(transfer.message == .exported && settings.snapshot == beforeInvalid,
                  "An export completion must not alter appearance or file policy")
    }

    private static func importSurvivesSaveFailureAndRetry(_ root: URL) async throws {
        let parent = root.appendingPathComponent("blocked-theme-save")
        let store = PreferenceStore(url: parent.appendingPathComponent("preferences.json"))
        try await store.save(.disabledContentFallback)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        try FileManager.default.removeItem(at: parent)
        try Data("not a directory".utf8).write(to: parent)
        let transfer = AppearanceThemeTransfer(read: { _ in appearance() })
        transfer.importCompleted(.success(root.appendingPathComponent("virtual.json")), settings: settings)
        try await eventually("Failed import save was not reported") { settings.saveState == .failed }
        try check(transfer.message == .imported && settings.snapshot.appearance == appearance()
                  && !settings.snapshot.defaultEnabled, "Persistence failure must preserve visible imported settings and disabled policy")
        try FileManager.default.removeItem(at: parent)
        settings.applyAppearance(settings.snapshot.appearance)
        try await eventually("Imported settings did not retry after storage repair") { settings.saveState == .saved }
        let relaunched = CompanionSettings(store: store, storageMode: .privateOnly)
        await relaunched.load()
        try check(relaunched.snapshot == settings.snapshot && !relaunched.snapshot.defaultEnabled,
                  "Successful retry must persist the complete imported appearance without enabling content")
    }

    private static func cancelledAndReplacedImportsCannotApply(_ root: URL) async throws {
        let settings = CompanionSettings(store: nil, storageMode: .unavailable)
        await settings.load()
        let initial = settings.snapshot
        let reader = SuspendedThemeReader()
        let transfer = AppearanceThemeTransfer(read: { try await reader.read($0) })
        transfer.importCompleted(.success(root.appendingPathComponent("old.json")), settings: settings)
        while !(await reader.hasRequest("old.json")) { await Task.yield() }
        transfer.cancelImport()
        try check(!transfer.isReading && settings.snapshot == initial, "Cancelling an active import must keep settings")
        transfer.importCompleted(.success(root.appendingPathComponent("new.json")), settings: settings)
        while !(await reader.hasRequest("new.json")) { await Task.yield() }
        await reader.complete("new.json", with: appearance())
        try await eventually("Replacement import did not finish") { !transfer.isReading }
        let replacement = settings.snapshot
        await reader.complete("old.json", with: PreviewAppearance(theme: .light))
        try await Task.sleep(for: .milliseconds(30))
        try check(settings.snapshot == replacement && transfer.message == .imported,
                  "A noncooperative stale read must not replace the latest import or its status")

        transfer.importCompleted(.success(root.appendingPathComponent("manual-edit.json")), settings: settings)
        while !(await reader.hasRequest("manual-edit.json")) { await Task.yield() }
        settings.setTheme(.dark)
        let manualEdit = settings.snapshot
        await reader.complete("manual-edit.json", with: PreviewAppearance(theme: .light))
        try await eventually("Superseded import did not finish") { !transfer.isReading }
        try check(settings.snapshot == manualEdit && transfer.message == nil,
                  "A theme read must not replace a newer user appearance choice")

        transfer.importCompleted(.success(root.appendingPathComponent("policy-edit.json")), settings: settings)
        while !(await reader.hasRequest("policy-edit.json")) { await Task.yield() }
        settings.setEnabled(true, for: .yaml)
        await reader.complete("policy-edit.json", with: appearance())
        try await eventually("Import with a policy change did not finish") { !transfer.isReading }
        let policyEdit = settings.snapshot
        try check(policyEdit.appearance == appearance() && policyEdit.isEnabled(.yaml) && !policyEdit.defaultEnabled,
                  "An unrelated file-policy edit must survive a successful import")

        let beforeABA = settings.appearanceRevision
        transfer.importCompleted(.success(root.appendingPathComponent("aba-edit.json")), settings: settings)
        while !(await reader.hasRequest("aba-edit.json")) { await Task.yield() }
        settings.setTheme(.light)
        settings.applyAppearance(policyEdit.appearance)
        try check(settings.snapshot == policyEdit && settings.appearanceRevision == beforeABA + 2,
                  "Returning to identical appearance values must still record both edits")
        await reader.complete("aba-edit.json", with: PreviewAppearance(theme: .dark))
        try await eventually("ABA-superseded import did not finish") { !transfer.isReading }
        try check(settings.snapshot == policyEdit && transfer.message == nil,
                  "A→B→A appearance edits must retain the newer user choice instead of applying a stale import")

        var owner: AppearanceThemeTransfer? = AppearanceThemeTransfer(read: { try await reader.read($0) })
        let releasedOwner = WeakTransferReference(owner)
        owner?.importCompleted(.success(root.appendingPathComponent("released.json")), settings: settings)
        while !(await reader.hasRequest("released.json")) { await Task.yield() }
        owner = nil
        try check(releasedOwner.value == nil, "A suspended import must not retain its view model owner")
        await reader.complete("released.json", with: PreviewAppearance(theme: .dark))
        try await Task.sleep(for: .milliseconds(30))
        try check(settings.snapshot == policyEdit, "A read released with its view owner must not apply")
    }

    private static func pickerCancellationPreservesPreview(_ root: URL) async throws {
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations))
        defer { session.cancel() }
        let source = root.appendingPathComponent("picker-source.json")
        try Data(#"{"password":"synthetic-picker-secret","value":42}"#.utf8).write(to: source)
        session.open(source, preferences: .defaults)
        let pendingGeneration = session.generation
        session.fileImporterFailed(error: CocoaError(.userCancelled))
        try check(session.isLoading && session.sourceURL == source && session.generation == pendingGeneration,
                  "Cancelling a picker must retain the in-flight request and source")
        try await eventually("Retained preview did not finish") { !session.isLoading }
        let safeOutcome = session.outcome
        session.fileImporterFailed(error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        session.fileImporterFailed(error: CancellationError())
        try check(session.outcome == safeOutcome && session.sourceURL == source
                  && session.generation == pendingGeneration && !session.pickerFailed,
                  "Cancelling a picker must retain safe content, source and selection generation")
        session.fileImporterFailed(error: CocoaError(.fileReadNoPermission))
        try check(session.pickerFailed && session.sourceURL == nil && session.outcome == nil
                  && session.generation != pendingGeneration, "Actual picker failures must still clear the preview")
    }
}
