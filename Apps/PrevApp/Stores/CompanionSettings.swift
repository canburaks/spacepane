import Foundation
import Observation
import PreviewContracts
import PreviewPreferences
import PreviewRenderers

@MainActor @Observable
final class CompanionSettings {
    enum StorageMode: Equatable { case shared, privateOnly, unavailable }
    enum SaveState: Equatable { case idle, saving, saved, failed }

    private(set) var snapshot = PreviewPreferencesSnapshot.disabledContentFallback
    private(set) var isLoading = true
    private(set) var recoveredSettings = false
    private(set) var saveState = SaveState.idle
    /// The newest undoable action, shown as an inline row until the next change. Never persisted.
    private(set) var undoNotice: UndoNotice?
    @ObservationIgnored private(set) var appearanceRevision = 0
    let storageMode: StorageMode
    @ObservationIgnored private let store: PreferenceStore?
    @ObservationIgnored private var observers: [UUID: (PreviewPreferencesSnapshot) -> Void] = [:]
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var persistedRevision = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loadHasStarted = false
    /// The window's undo manager, attached by the shell. Checks that do not exercise Undo never attach one.
    @ObservationIgnored private weak var undoManager: UndoManager?
    /// Receives the sentence VoiceOver should speak after an undoable action, an undo or a redo.
    @ObservationIgnored private var announcer: ((String) -> Void)?
    /// Set by Try Again, so the next save that succeeds says so; a refused save already speaks for itself.
    @ObservationIgnored private var announcesNextSave = false
    /// Callers of `flushPendingSave` waiting for the save in flight.
    @ObservationIgnored private var drainWaiters: [SaveDrainWaiter] = []

    convenience init(configuration: HostedConfiguration) {
        if let url = PreferencesLocation.appGroupSnapshotURL(identifier: configuration.appGroupIdentifier) {
            self.init(store: PreferenceStore(url: url), storageMode: .shared)
        } else if let url = try? PreferencesLocation.companionSnapshotURL() {
            self.init(store: PreferenceStore(url: url), storageMode: .privateOnly)
        } else {
            self.init(store: nil, storageMode: .unavailable)
        }
    }

    /// Allows model checks to use isolated temporary storage instead of user preferences.
    init(store: PreferenceStore?, storageMode: StorageMode) {
        self.store = store
        self.storageMode = storageMode
    }

    func load() async {
        guard !loadHasStarted else { return }
        loadHasStarted = true
        let loadRevision = revision
        if let store {
            let loaded = await store.load()
            // An edit made while disk access was pending must never be replaced by old settings.
            if revision == loadRevision {
                if snapshot.appearance != loaded.snapshot.appearance { appearanceRevision += 1 }
                snapshot = loaded.snapshot
                switch loaded.state {
                case .corrupt, .unreadable, .unsupportedVersion: recoveredSettings = true
                case .defaults, .loaded, .migrated: recoveredSettings = false
                }
                // Undo never reaches back across the moment stored choices replace the ones in memory.
                discardUndo()
                notifyObservers()
            }
        }
        isLoading = false
    }

    func isEnabled(_ id: FormatID) -> Bool { snapshot.isEnabled(id) }
    func setEnabled(_ enabled: Bool, for id: FormatID) {
        change { $0.setEnabled(enabled, for: id) }
    }
    /// One publication preserves the global default and unrelated individual choices.
    func setEnabled(_ enabled: Bool, for ids: [FormatID]) {
        // Collection toggles write each binding; repeated writes must stay no-ops
        // even when persistence failed synchronously because storage is unavailable.
        guard ids.contains(where: { snapshot.isEnabled($0) != enabled }) else { return }
        change { snapshot in
            for id in ids { snapshot.setEnabled(enabled, for: id) }
        }
    }
    /// A group checkbox: the same single publication, and an undoable one. `group` names the group's heading
    /// for the Undo row; the ids are every member, hidden by search or not.
    func setEnabled(_ enabled: Bool, for ids: [FormatID], group: PreviewStrings.Key) {
        guard ids.contains(where: { snapshot.isEnabled($0) != enabled }) else { return }
        perform(.setGroup(enabled: enabled, group: group, ids: ids)) { snapshot in
            for id in ids { snapshot.setEnabled(enabled, for: id) }
        }
    }
    func setAllEnabled(_ enabled: Bool) {
        perform(enabled ? .enableAll : .disableAll) { $0.setAllEnabled(enabled) }
    }
    func resetFileTypeChoices() { perform(.resetFileTypeChoices) { $0.resetFileTypeChoices() } }
    func setTheme(_ theme: PreviewTheme) { change { $0.theme = theme } }
    func setTypography(_ typography: PreviewTypography) { change { $0.typography = typography } }
    func setSyntaxStyle(_ style: PreviewSyntaxStyle) { change { $0.syntaxStyle = style } }
    /// A scheme that does not suit its appearance is ignored, so a light preview never selects a dark scheme.
    func setLightScheme(_ scheme: PreviewColorSchemeID) {
        guard scheme.isAvailable(for: .light) else { return }
        change { $0.syntaxStyle.lightScheme = scheme }
    }
    func setDarkScheme(_ scheme: PreviewColorSchemeID) {
        guard scheme.isAvailable(for: .dark) else { return }
        change { $0.syntaxStyle.darkScheme = scheme }
    }
    func setReloadsOnFileChange(_ enabled: Bool) { change { $0.reloadsOnFileChange = enabled } }
    func setShowsContentThumbnails(_ enabled: Bool) { change { $0.showsContentThumbnails = enabled } }
    /// The depth is limited to the supported range instead of being rejected, so a stepper at its end is harmless.
    func setFolderDepth(_ depth: Int) {
        let range = PreviewRequestOptions.folderDepthRange
        change { $0.folderDepth = min(max(depth, range.lowerBound), range.upperBound) }
    }
    func setShowsHiddenFolderItems(_ enabled: Bool) { change { $0.showsHiddenFolderItems = enabled } }
    func applyAppearance(_ appearance: PreviewAppearance) { change { $0.appearance = appearance } }
    func saveAppearanceProfile(name: String) {
        let profile = PreviewAppearanceProfile(name: name, appearance: snapshot.appearance)
        guard profile.isValid, snapshot.appearanceProfiles.count < PreviewAppearanceProfile.maximumCount,
              !snapshot.appearanceProfiles.contains(where: { $0.name == name }) else { return }
        change { $0.appearanceProfiles.append(profile) }
    }
    func applyAppearanceProfile(id: UUID) {
        guard let profile = snapshot.appearanceProfiles.first(where: { $0.id == id }) else { return }
        perform(.applyProfile(name: profile.name)) { $0.appearance = profile.appearance }
    }
    func deleteAppearanceProfile(id: UUID) {
        guard let profile = snapshot.appearanceProfiles.first(where: { $0.id == id }) else { return }
        perform(.deleteProfile(name: profile.name)) { $0.appearanceProfiles.removeAll(where: { $0.id == id }) }
    }
    func resetAppearance() { perform(.resetAppearance) { $0.resetAppearance() } }

    func observe(_ observer: @escaping (PreviewPreferencesSnapshot) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID) { observers[token] = nil }

    private func change(_ mutation: (inout PreviewPreferencesSnapshot) -> Void) {
        var updated = snapshot
        mutation(&updated)
        // An explicit reset also repairs corrupt storage or retries a failed write,
        // even when its safe value already matches the visible defaults.
        guard updated.hasValidChoices,
              updated != snapshot || recoveredSettings || saveState == .failed else { return }
        if updated.appearance != snapshot.appearance { appearanceRevision += 1 }
        snapshot = updated
        revision += 1
        recoveredSettings = false
        // Any other change ends the inline Undo row; an undoable action sets its own row afterwards.
        undoNotice = nil
        // Policy observers clear disabled content synchronously, before persistence.
        // Appearance observers keep the existing immutable safe presentation.
        notifyObservers()
        beginSaving()
    }

    private func notifyObservers() {
        for observer in observers.values { observer(snapshot) }
    }

    /// Records a failed save and says so, once for each attempt that ends in failure. With no store at all the state
    /// never leaves failed, so that case is said once and not again for every change.
    private func markSaveFailed(announcing key: PreviewStrings.Key) {
        let wasFailed = saveState == .failed
        saveState = .failed
        if !wasFailed { announcer?(PreviewStrings.text(key)) }
    }

    private func beginSaving() {
        guard let store else { markSaveFailed(announcing: .storageUnavailable); return }
        guard saveTask == nil else { return }
        saveState = .saving
        // A single writer drains to the newest revision; stale tasks cannot overwrite a newer save.
        saveTask = Task { [weak self] in
            guard let self else { return }
            while persistedRevision != revision {
                let savingRevision = revision
                let savingSnapshot = snapshot
                do {
                    try await store.save(savingSnapshot)
                    persistedRevision = savingRevision
                } catch {
                    markSaveFailed(announcing: .settingsSaveFailed)
                    announcesNextSave = false
                    saveTask = nil
                    finishDrainWaiters()
                    return
                }
            }
            saveState = .saved
            saveTask = nil
            if announcesNextSave {
                announcesNextSave = false
                announcer?(PreviewStrings.text(.settingsSaved))
            }
            finishDrainWaiters()
        }
    }

    private func finishDrainWaiters() {
        let waiting = drainWaiters
        drainWaiters = []
        for waiter in waiting { waiter.finish() }
    }

    /// Writes the choices again after a failed save. Nothing a person chose changes, so this is not an action to
    /// undo and leaves the Undo row as it is; it only starts the single writer again. With no storage there is
    /// nothing to retry.
    func retrySave() {
        guard saveState == .failed, store != nil else { return }
        announcesNextSave = true
        revision += 1
        beginSaving()
    }

    /// The recovery action: replaces the fail-closed settings read after an unusable file with the standard
    /// defaults and saves them. It registers no Undo, because there is no saved choice to bring back.
    func restoreDefaults() {
        guard recoveredSettings else { return }
        change { $0 = PreviewPreferencesSnapshot.defaults }
        announcer?(PreviewStrings.text(.defaultsRestored))
    }

    /// Waits for the save in flight, and for one more try if the last one failed, but never longer than `limit`.
    /// It answers whether every change is on disk. A hook that runs when the app stops being active uses it so the
    /// last choice is not lost; `sleep` is injected so a check never waits on the clock.
    func flushPendingSave(limit: Duration = .seconds(1),
                          sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async -> Bool {
        if saveTask == nil, persistedRevision != revision, store != nil { beginSaving() }
        guard saveTask != nil else { return persistedRevision == revision }
        let waiter = SaveDrainWaiter()
        drainWaiters.append(waiter)
        let timer = Task { [weak waiter] in
            try? await sleep(limit)
            waiter?.finish()
        }
        await waiter.wait()
        timer.cancel()
        drainWaiters.removeAll { $0 === waiter }
        return persistedRevision == revision
    }
}

/// One caller of `flushPendingSave`, resumed when the save finishes or its limit passes, whichever is first.
@MainActor private final class SaveDrainWaiter {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: Undo

extension CompanionSettings {
    /// The eight actions that overwrite saved choices in one step. Each can be undone and redone from the Edit
    /// menu and from the inline row on the page where it was taken.
    enum UndoAction: Equatable, Sendable {
        case enableAll
        case disableAll
        case resetFileTypeChoices
        /// A group checkbox. `group` is the group's name key and `ids` every member of the group.
        case setGroup(enabled: Bool, group: PreviewStrings.Key, ids: [FormatID])
        case resetAppearance
        case applyProfile(name: String)
        case importTheme
        case deleteProfile(name: String)

        /// The page an action is taken on, so a page shows only the row of its own actions.
        enum Area: Equatable, Sendable { case fileTypes, appearance }

        var area: Area {
            switch self {
            case .enableAll, .disableAll, .resetFileTypeChoices, .setGroup: return .fileTypes
            case .resetAppearance, .applyProfile, .importTheme, .deleteProfile: return .appearance
            }
        }

        /// The name the Edit menu shows after Undo and Redo.
        var menuNameKey: PreviewStrings.Key {
            switch self {
            case .enableAll: return .enableAll
            case .disableAll: return .disableAll
            case .resetFileTypeChoices: return .resetChoices
            case .setGroup: return .undoActionGroup
            case .resetAppearance: return .resetAppearance
            case .applyProfile: return .undoActionApplyProfile
            case .importTheme: return .undoActionImportTheme
            case .deleteProfile: return .undoActionDeleteProfile
            }
        }

        func menuName(languagePreferences: [String]? = nil) -> String {
            PreviewStrings.text(menuNameKey, languagePreferences: languagePreferences)
        }

        /// What happened, as one sentence for the inline row and for VoiceOver. A name that the sentence
        /// quotes (a group or a profile) is shown as written.
        func message(locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
            switch self {
            case .enableAll:
                return PreviewStrings.text(.undoMessageEnableAll, languagePreferences: languagePreferences)
            case .disableAll:
                return PreviewStrings.text(.undoMessageDisableAll, languagePreferences: languagePreferences)
            case .resetFileTypeChoices:
                return PreviewStrings.text(.undoMessageResetChoices, languagePreferences: languagePreferences)
            case .setGroup(let enabled, let group, _):
                let name = PreviewStrings.text(group, languagePreferences: languagePreferences)
                if enabled {
                    return PreviewStrings.format(.undoMessageGroupOn, arguments: [name], locale: locale,
                                                 languagePreferences: languagePreferences)
                }
                return PreviewStrings.format(.undoMessageGroupOff, arguments: [name], locale: locale,
                                             languagePreferences: languagePreferences)
            case .resetAppearance:
                return PreviewStrings.text(.undoMessageResetAppearance, languagePreferences: languagePreferences)
            case .applyProfile(let name):
                return PreviewStrings.format(.undoMessageApplyProfile, arguments: [name], locale: locale,
                                             languagePreferences: languagePreferences)
            case .importTheme:
                return PreviewStrings.text(.undoMessageImportTheme, languagePreferences: languagePreferences)
            case .deleteProfile(let name):
                return PreviewStrings.format(.undoMessageDeleteProfile, arguments: [name], locale: locale,
                                             languagePreferences: languagePreferences)
            }
        }
    }

    /// The inline row: the last undoable action and whether it is applied or undone. A new value replaces
    /// the row each time, so `id` tells two identical actions apart.
    struct UndoNotice: Equatable, Sendable {
        enum Phase: Equatable, Sendable { case applied, undone }

        let id: UUID
        let action: UndoAction
        let phase: Phase

        func text(locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
            switch phase {
            case .applied:
                return action.message(locale: locale, languagePreferences: languagePreferences)
            case .undone:
                return PreviewStrings.format(.undoMessageUndone,
                                             arguments: [action.menuName(languagePreferences: languagePreferences)],
                                             locale: locale, languagePreferences: languagePreferences)
            }
        }
    }

    /// One type's own choice: true or false, or nil when the type follows the default.
    struct TypeOverride: Equatable, Sendable {
        let id: FormatID
        let value: Bool?
    }

    /// The part of the snapshot an action replaced. Restoring a slice writes only these fields, so an unrelated
    /// edit made in between survives an Undo.
    enum UndoSlice: Equatable, Sendable {
        /// The global default and every individual choice: Enable All, Disable All and Reset.
        case fileTypes(defaultEnabled: Bool, overrides: [FormatID: Bool])
        /// The individual choices of some types only: a group checkbox.
        case typeOverrides([TypeOverride])
        /// Typography, theme and syntax style together: Reset Appearance, Apply profile and Import theme.
        case appearance(PreviewAppearance)
        /// A saved profile at its position, which is what a deleted profile needs to come back.
        case profilePresent(PreviewAppearanceProfile, index: Int)
        /// No profile with this identifier, which is how a restored profile is taken away again.
        case profileAbsent(UUID)
    }

    /// The row for `area`, or nil when the last action belongs to another page or there is none.
    func undoNotice(in area: UndoAction.Area) -> UndoNotice? {
        guard let notice = undoNotice, notice.action.area == area else { return nil }
        return notice
    }

    /// Attaches the window's undo manager. A different manager forgets what was registered with the old one.
    func attachUndoManager(_ manager: UndoManager?) {
        guard manager !== undoManager else { return }
        discardUndo()
        undoManager = manager
    }

    /// The shell passes VoiceOver's announcement here; a check passes a recorder.
    func setAnnouncer(_ handler: @escaping (String) -> Void) {
        announcer = handler
    }

    /// The inline row's button: the same step as Edit > Undo.
    func undoLastAction() {
        if let manager = undoManager, manager.canUndo { manager.undo() }
    }

    /// The inline row's button after an undo: the same step as Edit > Redo.
    func redoLastAction() {
        if let manager = undoManager, manager.canRedo { manager.redo() }
    }

    /// Applies `mutation` through the single change funnel and, when an undo manager is attached and the
    /// action really replaced something, registers the inverse of the slice it replaced. Nothing is
    /// registered while settings load or after a recovery: the first explicit choice then repairs storage
    /// and there is no saved choice to bring back. Without an undo manager this is exactly `change`.
    func perform(_ action: UndoAction, _ mutation: (inout PreviewPreferencesSnapshot) -> Void) {
        let before = snapshot
        let registers = !isLoading && !recoveredSettings
        change(mutation)
        guard registers, snapshot != before, let manager = undoManager,
              let slice = Self.replacedSlice(for: action, before: before, after: snapshot) else { return }
        // An explicit group makes each action one undo step whatever the run loop does around it.
        manager.beginUndoGrouping()
        registerUndo(slice, action: action, manager: manager)
        manager.endUndoGrouping()
        let notice = UndoNotice(id: UUID(), action: action, phase: .applied)
        undoNotice = notice
        announcer?(notice.text())
    }

    /// The slice `action` replaced, from the states before and after it; nil when nothing it owns changed.
    static func replacedSlice(for action: UndoAction, before: PreviewPreferencesSnapshot,
                              after: PreviewPreferencesSnapshot) -> UndoSlice? {
        switch action {
        case .enableAll, .disableAll, .resetFileTypeChoices:
            let previous = fileTypeSlice(of: before)
            return previous == fileTypeSlice(of: after) ? nil : previous
        case .setGroup(_, _, let ids):
            let previous = UndoSlice.typeOverrides(ids.map { TypeOverride(id: $0, value: before.formatOverrides[$0]) })
            let current = UndoSlice.typeOverrides(ids.map { TypeOverride(id: $0, value: after.formatOverrides[$0]) })
            return previous == current ? nil : previous
        case .resetAppearance, .applyProfile, .importTheme:
            return before.appearance == after.appearance ? nil : .appearance(before.appearance)
        case .deleteProfile:
            let removed = before.appearanceProfiles.firstIndex { profile in
                !after.appearanceProfiles.contains { $0.id == profile.id }
            }
            guard let index = removed else { return nil }
            return .profilePresent(before.appearanceProfiles[index], index: index)
        }
    }

    private static func fileTypeSlice(of snapshot: PreviewPreferencesSnapshot) -> UndoSlice {
        .fileTypes(defaultEnabled: snapshot.defaultEnabled, overrides: snapshot.formatOverrides)
    }

    /// The same kind of slice as `slice`, taken from `snapshot`: what an undo of that slice must restore.
    static func currentSlice(matching slice: UndoSlice, in snapshot: PreviewPreferencesSnapshot) -> UndoSlice {
        switch slice {
        case .fileTypes:
            return fileTypeSlice(of: snapshot)
        case .typeOverrides(let choices):
            return .typeOverrides(choices.map { TypeOverride(id: $0.id, value: snapshot.formatOverrides[$0.id]) })
        case .appearance:
            return .appearance(snapshot.appearance)
        case .profilePresent(let profile, _):
            return .profileAbsent(profile.id)
        case .profileAbsent(let id):
            guard let index = snapshot.appearanceProfiles.firstIndex(where: { $0.id == id }) else {
                return .profileAbsent(id)
            }
            return .profilePresent(snapshot.appearanceProfiles[index], index: index)
        }
    }

    private func registerUndo(_ slice: UndoSlice, action: UndoAction, manager: UndoManager) {
        // The handler runs on the thread that calls undo or redo, which is the main thread for this window.
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restore(slice, action: action) }
        }
        manager.setActionName(action.menuName())
    }

    /// The undo manager's handler: writes the slice back, registers the inverse so the step can be redone
    /// (or undone again) and updates the row.
    private func restore(_ slice: UndoSlice, action: UndoAction) {
        let before = snapshot
        let inverse = Self.currentSlice(matching: slice, in: before)
        write(slice)
        guard snapshot != before, let manager = undoManager else {
            undoNotice = nil
            return
        }
        registerUndo(inverse, action: action, manager: manager)
        let notice = UndoNotice(id: UUID(), action: action, phase: manager.isUndoing ? .undone : .applied)
        undoNotice = notice
        announcer?(notice.text())
    }

    private func write(_ slice: UndoSlice) {
        change { snapshot in
            switch slice {
            case .fileTypes(let defaultEnabled, let overrides):
                snapshot.defaultEnabled = defaultEnabled
                snapshot.formatOverrides = overrides
            case .typeOverrides(let choices):
                for choice in choices { snapshot.formatOverrides[choice.id] = choice.value }
            case .appearance(let appearance):
                snapshot.appearance = appearance
            case .profilePresent(let profile, let index):
                if !snapshot.appearanceProfiles.contains(where: { $0.id == profile.id }) {
                    let position = min(max(index, 0), snapshot.appearanceProfiles.count)
                    snapshot.appearanceProfiles.insert(profile, at: position)
                }
            case .profileAbsent(let id):
                snapshot.appearanceProfiles.removeAll(where: { $0.id == id })
            }
        }
    }

    private func discardUndo() {
        undoNotice = nil
        undoManager?.removeAllActions(withTarget: self)
    }
}
