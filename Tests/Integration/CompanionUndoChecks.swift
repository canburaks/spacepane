import Foundation
import PreviewContracts
import PreviewPreferences
import PreviewRenderers

private struct UndoCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Records what the companion would have said to VoiceOver.
@MainActor private final class AnnouncementRecorder {
    private(set) var texts: [String] = []
    func record(_ text: String) { texts.append(text) }
}

/// Holds a theme read open until the check releases it, to model an import that is still reading its file.
private actor HeldThemeReader {
    private var continuation: CheckedContinuation<PreviewAppearance, any Error>?
    private var hasRequest = false

    func read(_ url: URL) async throws -> PreviewAppearance {
        try await withCheckedThrowingContinuation { pending in
            continuation = pending
            hasRequest = true
        }
    }

    func isWaiting() -> Bool { hasRequest }

    func release(with appearance: PreviewAppearance) {
        continuation?.resume(returning: appearance)
        continuation = nil
    }
}

/// Undo for the eight actions that overwrite saved choices: each is undone and redone from a real undo manager
/// (the headless one a window would provide), restoring only the slice it replaced, in isolated temporary
/// storage. Nothing here reads user preferences, launches a window or speaks to VoiceOver.
@MainActor
enum CompanionUndoChecks {
    static func run(in root: URL) async throws {
        try await everyActionUndoesAndRedoesExactly(root)
        try await anUnrelatedEditSurvivesAnUndo(root)
        try await aGroupToggleRestoresOnlyItsOwnChoices(root)
        try await aDeletedProfileReturnsToItsPlaceAndLaterProfilesSurvive(root)
        try await anImportUndoesAndASupersededImportIsReported(root)
        try await theSavedFileFollowsUndoAndRedo(root)
        try await undoAfterAFailedSaveRepairsStorage(root)
        try await undoNeverCrossesARecoveryOrAReplacedManager(root)
        try await theInlineRowFollowsTheLastActionUntilTheNextChange(root)
        try await announcementsAreMadeOncePerResult(root)
        try await nothingIsRegisteredWithoutAManagerOrAChange(root)
        try actionNamesAndMessagesExistInEveryLanguage()
        print("Passed 12 companion undo checks (isolated storage and a headless undo manager; no window or VoiceOver).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw UndoCheckFailure(description: message) }
    }

    private static func eventually(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw UndoCheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Settings over their own file, loaded, with an undo manager that does not group by run loop event.
    private static func makeSettings(_ root: URL, _ name: String)
        async -> (settings: CompanionSettings, manager: UndoManager, store: PreferenceStore) {
        let store = PreferenceStore(url: root.appendingPathComponent("undo-\(name).json"))
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        return (settings, manager, store)
    }

    /// Takes one action, then undoes, redoes and undoes it again, checking the snapshot each time.
    private static func roundTrip(_ label: String, _ settings: CompanionSettings, _ manager: UndoManager,
                                  name: String, action: () -> Void) throws {
        let before = settings.snapshot
        action()
        let after = settings.snapshot
        try check(after != before, "\(label) must change something, or this check proves nothing")
        try check(manager.canUndo && manager.undoActionName == name,
                  "\(label) must register one undo named \(name), not \(manager.undoActionName)")
        manager.undo()
        try check(settings.snapshot == before, "\(label) must undo exactly")
        try check(manager.canRedo && manager.redoActionName == name,
                  "\(label) must offer a redo with the same name, not \(manager.redoActionName)")
        manager.redo()
        try check(settings.snapshot == after, "\(label) must redo exactly")
        manager.undo()
        try check(settings.snapshot == before, "\(label) must undo again after a redo")
        manager.removeAllActions()
    }

    // MARK: The eight actions

    private static func everyActionUndoesAndRedoesExactly(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "every-action")
        // Every shipped type is on by default, so Enable All has something to change only after one is switched off.
        settings.setEnabled(false, for: .json)
        manager.removeAllActions()
        try roundTrip("Enable All", settings, manager, name: PreviewStrings.text(.enableAll)) {
            settings.setAllEnabled(true)
        }
        try roundTrip("Disable All", settings, manager, name: PreviewStrings.text(.disableAll)) {
            settings.setAllEnabled(false)
        }
        settings.setEnabled(false, for: .json)
        try roundTrip("Reset File Type Choices", settings, manager, name: PreviewStrings.text(.resetChoices)) {
            settings.resetFileTypeChoices()
        }
        let structured = FormatCatalog.standard.descriptors.filter { $0.group == .structured }.map(\.id)
        try roundTrip("A group checkbox", settings, manager, name: PreviewStrings.text(.undoActionGroup)) {
            settings.setEnabled(false, for: structured, group: .fileTypeGroupStructured)
        }
        settings.setTheme(.dark)
        try roundTrip("Reset Appearance", settings, manager, name: PreviewStrings.text(.resetAppearance)) {
            settings.resetAppearance()
        }
        settings.setTheme(.dark)
        settings.saveAppearanceProfile(name: "Dark Fixture")
        guard let profile = settings.snapshot.appearanceProfiles.first else {
            throw UndoCheckFailure(description: "The fixture profile was not saved")
        }
        settings.setTheme(.light)
        try roundTrip("Apply profile", settings, manager, name: PreviewStrings.text(.undoActionApplyProfile)) {
            settings.applyAppearanceProfile(id: profile.id)
        }
        try roundTrip("Delete profile", settings, manager, name: PreviewStrings.text(.undoActionDeleteProfile)) {
            settings.deleteAppearanceProfile(id: profile.id)
        }
        try await eventually("Undo and redo did not finish saving") { settings.saveState == .saved }
    }

    // MARK: Only the replaced slice

    private static func anUnrelatedEditSurvivesAnUndo(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "unrelated")
        // An appearance edit between Disable All and its Undo survives: Disable All never owned it.
        settings.setEnabled(false, for: .yaml)
        settings.setAllEnabled(false)
        settings.setTheme(.dark)
        manager.undo()
        try check(settings.snapshot.theme == .dark, "An appearance edit made after Disable All must survive its Undo")
        try check(settings.snapshot.defaultEnabled && !settings.isEnabled(.yaml) && settings.isEnabled(.json),
                  "Undoing Disable All must bring back the default and the per-type choice that Disable All cleared")
        manager.removeAllActions()
        // And the other way round: a file-type choice made after Reset Appearance survives its Undo.
        settings.setTheme(.highContrast)
        settings.resetAppearance()
        settings.setEnabled(false, for: .yaml)
        manager.undo()
        try check(settings.snapshot.theme == .highContrast && !settings.isEnabled(.yaml),
                  "A file-type choice made after Reset Appearance must survive its Undo, and the theme must return")
        try await eventually("The edits did not finish saving") { settings.saveState == .saved }
    }

    private static func aGroupToggleRestoresOnlyItsOwnChoices(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "group")
        let structured = FormatCatalog.standard.descriptors.filter { $0.group == .structured }.map(\.id)
        try check(structured.contains(.yaml) && !structured.contains(.plainText),
                  "Fixture: the structured group holds YAML and not plain text")
        settings.setEnabled(false, for: .yaml)
        let before = settings.snapshot
        settings.setEnabled(false, for: structured, group: .fileTypeGroupStructured)
        try check(structured.allSatisfy { !settings.isEnabled($0) }, "The group checkbox must turn off every member")
        settings.setEnabled(false, for: .plainText)
        manager.undo()
        try check(settings.snapshot.formatOverrides[.yaml] == false && settings.isEnabled(.json)
                  && structured.filter({ $0 != .yaml }).allSatisfy { settings.isEnabled($0) },
                  "Undo must give each member its own earlier choice, including the one that was off")
        try check(!settings.isEnabled(.plainText), "A choice outside the group must survive the Undo")
        try check(settings.snapshot.defaultEnabled == before.defaultEnabled, "A group toggle never owns the default")
        manager.redo()
        try check(structured.allSatisfy { !settings.isEnabled($0) } && !settings.isEnabled(.plainText),
                  "Redo must turn the group off again and leave the other choice alone")
        try await eventually("The group checks did not finish saving") { settings.saveState == .saved }
    }

    private static func aDeletedProfileReturnsToItsPlaceAndLaterProfilesSurvive(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "profiles")
        for name in ["Alpha", "Beta", "Gamma"] { settings.saveAppearanceProfile(name: name) }
        let saved = settings.snapshot.appearanceProfiles
        try check(saved.map(\.name) == ["Alpha", "Beta", "Gamma"], "Fixture: three profiles in the order they were saved")
        settings.deleteAppearanceProfile(id: saved[1].id)
        try check(settings.snapshot.appearanceProfiles.map(\.id) == [saved[0].id, saved[2].id], "Fixture: Beta is deleted")
        settings.saveAppearanceProfile(name: "Delta")
        guard let delta = settings.snapshot.appearanceProfiles.last, delta.name == "Delta" else {
            throw UndoCheckFailure(description: "Fixture: Delta was not appended")
        }
        manager.undo()
        try check(settings.snapshot.appearanceProfiles == [saved[0], saved[1], saved[2], delta],
                  "Undo must return Beta with its identifier and its place, and keep the profile saved since")
        manager.redo()
        try check(settings.snapshot.appearanceProfiles == [saved[0], saved[2], delta],
                  "Redo must delete Beta again and nothing else")
        try await eventually("The profile checks did not finish saving") { settings.saveState == .saved }
    }

    private static func anImportUndoesAndASupersededImportIsReported(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "import")
        let imported = PreviewAppearance(typography: PreviewTypography(fontSize: 21), theme: .dark)
        let transfer = AppearanceThemeTransfer(read: { _ in imported })
        let original = settings.snapshot.appearance
        transfer.importCompleted(.success(root.appendingPathComponent("theme.json")), settings: settings)
        try await eventually("The import did not finish") { !transfer.isReading }
        try check(transfer.message == .imported && settings.snapshot.appearance == imported,
                  "The import must apply the whole appearance")
        try check(manager.undoActionName == PreviewStrings.text(.undoActionImportTheme),
                  "The import must be one undo named for it, not \(manager.undoActionName)")
        manager.undo()
        try check(settings.snapshot.appearance == original, "Undo must restore the appearance the import replaced")
        manager.removeAllActions()

        // An import that was still reading when the appearance changed is not applied, and says so.
        let held = HeldThemeReader()
        let slow = AppearanceThemeTransfer(read: { url in try await held.read(url) })
        slow.importCompleted(.success(root.appendingPathComponent("slow.json")), settings: settings)
        while !(await held.isWaiting()) { await Task.yield() }
        settings.setTheme(.highContrast)
        await held.release(with: imported)
        try await eventually("The superseded import did not finish") { !slow.isReading }
        try check(slow.wasSuperseded && slow.message == nil && settings.snapshot.theme == .highContrast
                  && settings.snapshot.appearance != imported && !manager.canUndo,
                  "A superseded import must change nothing, register nothing and be reported separately")
        slow.clearMessage()
        try check(!slow.wasSuperseded, "Clearing the message must clear the superseded report")
        try await eventually("The import checks did not finish saving") { settings.saveState == .saved }
    }

    // MARK: Storage

    private static func theSavedFileFollowsUndoAndRedo(_ root: URL) async throws {
        let (settings, manager, store) = await makeSettings(root, "persisted")
        settings.setEnabled(false, for: .yaml)
        settings.setAllEnabled(false)
        try await eventually("Disable All did not save") { settings.saveState == .saved }
        manager.undo()
        try await eventually("Undo did not save") { settings.saveState == .saved }
        var loaded = await store.load()
        try check(loaded.state == .loaded && loaded.snapshot == settings.snapshot && !loaded.snapshot.isEnabled(.yaml),
                  "The file written after Undo must equal the snapshot, with the per-type choice back")
        manager.redo()
        try await eventually("Redo did not save") { settings.saveState == .saved }
        loaded = await store.load()
        try check(loaded.snapshot == settings.snapshot && !loaded.snapshot.defaultEnabled,
                  "The file written after Redo must equal the snapshot")
    }

    private static func undoAfterAFailedSaveRepairsStorage(_ root: URL) async throws {
        let parent = root.appendingPathComponent("undo-blocked")
        let store = PreferenceStore(url: parent.appendingPathComponent("preferences.json"))
        try await store.save(.defaults)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        let announcements = AnnouncementRecorder()
        settings.setAnnouncer { announcements.record($0) }
        try FileManager.default.removeItem(at: parent)
        try Data("not a directory".utf8).write(to: parent)
        settings.setAllEnabled(false)
        try await eventually("The unwritable path did not report a failed save") { settings.saveState == .failed }
        let failed = settings.snapshot
        try check(announcements.texts.filter { $0 == PreviewStrings.text(.settingsSaveFailed) }.count == 1,
                  "A failed save must be announced once: \(announcements.texts)")
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        manager.undo()
        try await eventually("Undo did not retry the failed save") { settings.saveState == .saved }
        let loaded = await store.load()
        try check(loaded.state == .loaded && loaded.snapshot == settings.snapshot && settings.snapshot != failed,
                  "Undo must repair storage: the file holds the restored snapshot")
    }

    private static func undoNeverCrossesARecoveryOrAReplacedManager(_ root: URL) async throws {
        // Corrupt storage fails closed; the first explicit choice repairs it and there is nothing to bring back.
        let url = root.appendingPathComponent("undo-corrupt.json")
        try Data("broken".utf8).write(to: url)
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        try check(settings.recoveredSettings, "Fixture: the corrupt file must be a recovery")
        settings.setAllEnabled(true)
        try check(!settings.recoveredSettings && !manager.canUndo && settings.undoNotice == nil,
                  "The repairing choice after a recovery must register no undo and show no row")
        try await eventually("The repair did not save") { settings.saveState == .saved }
        // A different manager forgets what the old one held, so a replaced window cannot undo into a new state.
        settings.setAllEnabled(false)
        try check(manager.canUndo && settings.undoNotice != nil, "Fixture: a normal action registers")
        let replacement = UndoManager()
        replacement.groupsByEvent = false
        settings.attachUndoManager(replacement)
        try check(!manager.canUndo && settings.undoNotice == nil && !replacement.canUndo,
                  "Attaching another manager must discard the old registrations and the row")
        try await eventually("The recovery checks did not finish saving") { settings.saveState == .saved }
    }

    // MARK: The inline row and its announcements

    private static func theInlineRowFollowsTheLastActionUntilTheNextChange(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "row")
        try check(settings.undoNotice == nil, "No row before any action")
        settings.setAllEnabled(false)
        guard let first = settings.undoNotice else { throw UndoCheckFailure(description: "Disable All must show a row") }
        try check(first.action == .disableAll && first.phase == .applied
                  && first.text() == PreviewStrings.text(.undoMessageDisableAll),
                  "The row must say what Disable All did")
        try check(settings.undoNotice(in: .fileTypes) == first && settings.undoNotice(in: .appearance) == nil,
                  "A file-type action belongs on the File Types page only")
        settings.undoLastAction()
        guard let undone = settings.undoNotice else { throw UndoCheckFailure(description: "Undo must keep a row") }
        let undoneText = PreviewStrings.format(.undoMessageUndone, arguments: [PreviewStrings.text(.disableAll)])
        try check(undone.phase == .undone && undone.text() == undoneText && undone.id != first.id && settings.isEnabled(.json),
                  "After Undo the row must say so, offer Redo, and be a new row")
        settings.redoLastAction()
        try check(settings.undoNotice?.phase == .applied && !settings.isEnabled(.json) && manager.canUndo,
                  "Redo from the row must apply the action again")
        settings.setTheme(.dark)
        try check(settings.undoNotice == nil, "The next change must end the row")
        settings.resetAppearance()
        try check(settings.undoNotice(in: .appearance)?.action == .resetAppearance, "Reset Appearance belongs on Theme")
        try await eventually("The row checks did not finish saving") { settings.saveState == .saved }
    }

    private static func announcementsAreMadeOncePerResult(_ root: URL) async throws {
        let (settings, manager, _) = await makeSettings(root, "announce")
        let announcements = AnnouncementRecorder()
        settings.setAnnouncer { announcements.record($0) }
        settings.setAllEnabled(false)
        try check(announcements.texts == [PreviewStrings.text(.undoMessageDisableAll)],
                  "An action must be announced once, in the row's words: \(announcements.texts)")
        manager.undo()
        let undone = PreviewStrings.format(.undoMessageUndone, arguments: [PreviewStrings.text(.disableAll)])
        try check(announcements.texts.count == 2 && announcements.texts.last == undone,
                  "An undo must be announced once: \(announcements.texts)")
        manager.redo()
        try check(announcements.texts.count == 3 && announcements.texts.last == PreviewStrings.text(.undoMessageDisableAll),
                  "A redo must be announced once: \(announcements.texts)")
        // A change that registers nothing says nothing.
        settings.setTheme(.dark)
        try check(announcements.texts.count == 3, "An ordinary edit must not be announced: \(announcements.texts)")
        try await eventually("The announcement checks did not finish saving") { settings.saveState == .saved }
    }

    private static func nothingIsRegisteredWithoutAManagerOrAChange(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("undo-none.json"))
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        settings.setAllEnabled(false)
        try check(settings.undoNotice == nil && !settings.isEnabled(.json),
                  "Without an undo manager an action must still apply and show no row")
        let manager = UndoManager()
        manager.groupsByEvent = false
        settings.attachUndoManager(manager)
        settings.setAllEnabled(false)
        settings.resetAppearance()
        try check(!manager.canUndo && settings.undoNotice == nil,
                  "An action that changes nothing it owns must register nothing")
        settings.undoLastAction()
        settings.redoLastAction()
        try await eventually("The no-op checks did not finish saving") { settings.saveState == .saved }
    }

    // MARK: Words

    private static func actionNamesAndMessagesExistInEveryLanguage() throws {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        let actions: [CompanionSettings.UndoAction] = [
            .enableAll, .disableAll, .resetFileTypeChoices,
            .setGroup(enabled: true, group: .fileTypeGroupText, ids: []),
            .setGroup(enabled: false, group: .fileTypeGroupText, ids: []),
            .resetAppearance, .applyProfile(name: "Fixture Profile"), .importTheme,
            .deleteProfile(name: "Fixture Profile"),
        ]
        for language in languages {
            let locale = Locale(identifier: language)
            for action in actions {
                let name = action.menuName(languagePreferences: [language])
                let message = action.message(locale: locale, languagePreferences: [language])
                try check(!name.isEmpty && name != unavailable && !name.contains("%"),
                          "\(language): the Edit menu name of \(action) must exist")
                try check(!message.isEmpty && message != unavailable && !message.contains("%"),
                          "\(language): the row sentence of \(action) must exist and print its name: \(message)")
                if case .applyProfile(let profile) = action {
                    try check(message.contains(profile), "\(language): the sentence must quote the profile: \(message)")
                }
                if case .setGroup(_, let groupKey, _) = action {
                    let groupName = PreviewStrings.text(groupKey, languagePreferences: [language])
                    try check(message.contains(groupName), "\(language): the sentence must quote the group: \(message)")
                }
            }
            let undone = CompanionSettings.UndoNotice(id: UUID(), action: .disableAll, phase: .undone)
            let sentence = undone.text(locale: locale, languagePreferences: [language])
            try check(sentence != unavailable && !sentence.contains("%")
                      && sentence.contains(CompanionSettings.UndoAction.disableAll.menuName(languagePreferences: [language])),
                      "\(language): the undone sentence must name the action: \(sentence)")
            for key in [PreviewStrings.Key.undo, .redo] {
                let word = PreviewStrings.text(key, languagePreferences: [language])
                try check(!word.isEmpty && word != unavailable, "\(language): the button \(key.rawValue) must exist")
            }
        }
    }
}
