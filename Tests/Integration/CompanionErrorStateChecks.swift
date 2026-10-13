import Foundation
import Synchronization
import PreviewContracts
import PreviewPreferences
import PreviewRenderers

private struct ErrorStateCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Suspends an injected save deadline without sleeping or blocking a thread. Opening after the save drains
/// releases even a timer whose cancellation arrived before it entered this latch.
private final class ErrorStateCheckLatch: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.waiters.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }

    func open() {
        let released = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let waiting = state.waiters
            state.waiters = []
            return waiting
        }
        for waiter in released { waiter.resume() }
    }
}

/// Actual storage failures and recovery in a private temporary directory passed by CompanionModelChecks.
/// No convenience initializer, App Group location, standard defaults, UI, clipboard or Finder is used.
@MainActor
enum CompanionErrorStateChecks {
    static func run(in root: URL) async throws {
        let isolated = root.appendingPathComponent("companion-error-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolated) }
        try editingPagesOfferOnlyApplicableActions()
        try problemActionsHaveLocalizedLabels()
        try await unavailableStorageNeverPretendsToSave()
        try await recoveryRestoresDefaultsOnlyOnRequest(isolated)
        try await retryRetainsChoicesAndUndo(isolated)
        try await flushingPersistsTheNewestChoices(isolated)
        print("Passed 6 companion error-state checks (isolated storage; injected save waits; no UI validation).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ErrorStateCheckFailure(description: message) }
    }

    /// The production drain resumes on a completed or failed save. Its clock is parked, then always released,
    /// so these persistence checks do not race a deadline or poll wall time. The driver supplies a process limit.
    private static func drain(_ settings: CompanionSettings) async -> Bool {
        let deadline = ErrorStateCheckLatch()
        defer { deadline.open() }
        return await settings.flushPendingSave(sleep: { _ in await deadline.wait() })
    }

    private static func editingPagesOfferOnlyApplicableActions() throws {
        try check(SettingsStatus.action(for: .settingsRecovery) == .restoreDefaults
                  && SettingsStatus.action(for: .settingsSaveFailed) == .tryAgain,
                  "Recovery and failed saves must offer their own corrective action")
        for key in [PreviewStrings.Key.storageUnavailable, .setupNotConfigured, .statusLoading, .settingsSaved] {
            try check(SettingsStatus.action(for: key) == nil, "Storage facts and healthy states must not invent a fix")
        }
        let storages: [CompanionSettings.StorageMode] = [.shared, .privateOnly, .unavailable]
        let saves: [CompanionSettings.SaveState] = [.idle, .saving, .saved, .failed]
        for storage in storages {
            for save in saves {
                for recovered in [false, true] {
                    let status = SettingsStatus(storage: storage, save: save, recovered: recovered, isLoading: false)
                    let expected: PreviewStrings.Key?
                    if recovered { expected = .settingsRecovery }
                    else if storage == .unavailable { expected = .storageUnavailable }
                    else if save == .failed { expected = .settingsSaveFailed }
                    else { expected = nil }
                    try check(status.editingProblem == expected,
                              "Editing pages must show one verified problem, recovery first, without the General-only storage note")
                    let loading = SettingsStatus(storage: storage, save: save, recovered: recovered, isLoading: true)
                    try check(loading.editingProblem == nil && loading.problemKeys.isEmpty,
                              "Loading must not show a recovery action before storage has been read")
                }
            }
        }
    }

    private static func problemActionsHaveLocalizedLabels() throws {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        for language in languages {
            for key in [SettingsStatus.Action.tryAgain.titleKey,
                        SettingsStatus.Action.restoreDefaults.titleKey, .defaultsRestored] {
                let text = PreviewStrings.text(key, languagePreferences: [language])
                try check(!text.isEmpty && text != unavailable && text != key.rawValue && !text.contains("%"),
                          "\(language): settings recovery must have usable action and result words")
            }
        }
    }

    private static func unavailableStorageNeverPretendsToSave() async throws {
        let settings = CompanionSettings(store: nil, storageMode: .unavailable)
        await settings.load()
        var announcements: [String] = []
        settings.setAnnouncer { announcements.append($0) }
        settings.setTheme(.dark)
        settings.setEnabled(true, for: .json)
        let beforeRetry = settings.snapshot
        settings.retrySave()
        let flushed = await drain(settings)
        try check(!flushed && settings.saveState == .failed && settings.snapshot == beforeRetry,
                  "Missing storage must retain in-memory choices and report that they are not persisted")
        try check(settings.status.problemKeys == [.storageUnavailable]
                  && settings.status.editingProblem == .storageUnavailable,
                  "Missing storage must not duplicate its problem as a failed save")
        try check(announcements.count == 1 && !announcements[0].isEmpty,
                  "Missing storage must be announced once, rather than after every edit or retry")
    }

    private static func recoveryRestoresDefaultsOnlyOnRequest(_ root: URL) async throws {
        let url = root.appendingPathComponent("corrupt.json")
        let corrupt = Data("not a settings document".utf8)
        try corrupt.write(to: url)
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        try check(settings.recoveredSettings && settings.snapshot == .disabledContentFallback
                  && settings.status.editingProblem == .settingsRecovery,
                  "An unusable document must load fail-closed and explain the recovery action")
        let bytesAfterLoad = try Data(contentsOf: url)
        try check(bytesAfterLoad == corrupt, "Loading a corrupt document must not repair or overwrite it")
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        var announcements: [String] = []
        settings.setAnnouncer { announcements.append($0) }
        settings.restoreDefaults()
        let flushed = await drain(settings)
        let loaded = await store.load()
        try check(flushed && loaded.state == .loaded && loaded.snapshot == .defaults
                  && settings.snapshot == .defaults && !settings.recoveredSettings,
                  "Explicit recovery must write current-schema defaults and clear the recovery problem")
        try check(settings.snapshot.formatOverrides.isEmpty
                  && settings.isEnabled(.json) && !manager.canUndo && settings.undoNotice == nil,
                  "Recovery must restore the catalog defaults and must not register invented prior choices for Undo")
        try check(announcements.count == 1 && !announcements[0].isEmpty,
                  "Explicit recovery must announce its result once")
        let savedBytes = try Data(contentsOf: url)
        settings.restoreDefaults()
        try check(settings.saveState == .saved && announcements.count == 1,
                  "Restore Defaults must be inert after recovery is resolved")
        let bytesAfterNoOp = try Data(contentsOf: url)
        try check(bytesAfterNoOp == savedBytes, "An inapplicable recovery action must not rewrite storage")
    }

    private static func retryRetainsChoicesAndUndo(_ root: URL) async throws {
        let parent = root.appendingPathComponent("blocked-parent")
        let url = parent.appendingPathComponent("settings.json")
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .shared)
        await settings.load()
        try Data("not a directory".utf8).write(to: parent)
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        var publications = 0
        let observation = settings.observe { _ in publications += 1 }
        defer { settings.removeObserver(observation) }
        var announcements: [String] = []
        settings.setAnnouncer { announcements.append($0) }
        settings.setAllEnabled(false)
        let expected = settings.snapshot
        let notice = settings.undoNotice
        let appearanceRevision = settings.appearanceRevision
        let failedDrain = await drain(settings)
        try check(!failedDrain && settings.saveState == .failed && settings.status.editingProblem == .settingsSaveFailed,
                  "A refused write must resolve the drain as failed and expose Try Again")
        try check(notice?.action == .disableAll && manager.canUndo && publications == 1,
                  "A failed save must retain the user's undoable action and its one publication")
        let failureAnnouncements = announcements.count
        settings.retrySave()
        let refusedAgain = await drain(settings)
        try check(!refusedAgain && announcements.count == failureAnnouncements + 1,
                  "A second refused attempt must announce one new failure")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        settings.retrySave()
        let succeeded = await drain(settings)
        let loaded = await store.load()
        try check(succeeded && settings.saveState == .saved && loaded.state == .loaded && loaded.snapshot == expected,
                  "Try Again must persist the unchanged choices after the storage problem is repaired")
        try check(settings.undoNotice == notice && manager.canUndo && publications == 1
                  && settings.appearanceRevision == appearanceRevision,
                  "A save retry must preserve Undo, publish no policy change and restyle no content")
        try check(settings.status.editingProblem == nil && announcements.count == failureAnnouncements + 2,
                  "A successful retry must clear the problem and announce its one result")
        settings.retrySave()
        try check(settings.saveState == .saved && announcements.count == failureAnnouncements + 2,
                  "Try Again must be inert without a failed save")
    }

    private static func flushingPersistsTheNewestChoices(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("drain.json"))
        let settings = CompanionSettings(store: store, storageMode: .shared)
        await settings.load()
        let unchanged = await drain(settings)
        try check(unchanged, "An unchanged loaded snapshot must have nothing pending")
        settings.setTheme(.dark)
        settings.setEnabled(false, for: .json)
        settings.setShowsContentThumbnails(false)
        settings.setTheme(.light)
        let expected = settings.snapshot
        let first = Task { await drain(settings) }
        let second = Task { await drain(settings) }
        let firstResult = await first.value
        let secondResult = await second.value
        let loaded = await store.load()
        try check(firstResult && secondResult && settings.saveState == .saved
                  && loaded.state == .loaded && loaded.snapshot == expected,
                  "Concurrent drains must complete with the newest complete snapshot, not an older revision")
        try check(loaded.snapshot.theme == .light && !loaded.snapshot.isEnabled(.json)
                  && !loaded.snapshot.showsContentThumbnails,
                  "The last appearance choice and independent policy choices must all survive the drain")
    }
}
