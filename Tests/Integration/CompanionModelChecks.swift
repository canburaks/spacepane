import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewPreferences
import PreviewRenderers

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// This executable compiles the production companion models, without launching a UI
/// or reading the user's settings. It complements package tests and native UI audits.
@main @MainActor
struct CompanionModelChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await appearanceRetainsSafeContent(root)
        try await groupChangesAreAtomic(root)
        try await sameValueResetRepairsCorruption(root)
        try await sameValueResetRetriesFailedSave(root)
        try filenameSummariesPreserveCatalogIdentity()
        try patternSummariesShortenLongLists()
        try searchResultsAreAnnouncedWithTheirCount()
        try aboutAcknowledgementsFollowTheBundledNoticeFolders()
        try enablementSummariesCountEveryMember()
        try groupStatusUsesAllMembersWhileSearching()
        try everyPageIsAlwaysOffered()
        try await closedSessionIgnoresPolicyChanges(root)
        try await everyFormatHasARenderableSample(root)
        try await SettingsModelChecks.run(in: root)
        try await CompanionUndoChecks.run(in: root)
        try await CompanionPresentationChecks.run(in: root)
        try CompanionLayoutChecks.run()
        try await CompanionErrorStateChecks.run(in: root)
        print("Passed 12 companion model checks (isolated storage; no Finder/UI validation).")
    }

    private static func filenameSummariesPreserveCatalogIdentity() throws {
        let catalog = FormatCatalog.standard
        guard let package = catalog.descriptor(for: .packageJSON),
              let environment = catalog.descriptor(for: .environment),
              let folder = catalog.descriptor(for: .folder) else {
            throw CheckFailure(description: "Missing filename-specific fixtures")
        }
        let packageSummary = FormatFilenameSummary(package)
        try check(packageSummary.patterns == ["package.json"], "Exact filenames must be visible without a suffix alias")
        let environmentSummary = FormatFilenameSummary(environment)
        try check(environmentSummary.patterns == [".env", ".env.*"], "Shared suffix/name spelling must appear once, with prefix coverage")
        try check(FormatFilenameSummary(folder).patterns.isEmpty, "Folders must not acquire invented suffix claims")
        for language in ["en", "tr", "de", "zh-Hans", "pt", "es"] {
            let locale = Locale(identifier: language)
            try check(packageSummary.text(locale: locale) == "package.json", "Locale must never translate a catalog filename")
            let text = environmentSummary.text(locale: locale)
            try check(environmentSummary.patterns.allSatisfy(text.contains), "Locale must preserve exact filename patterns")
        }
        try check(environmentSummary.text(locale: Locale(identifier: "en")) == ".env and .env.*",
                  "Filename lists must use locale-aware conjunctions")
        try check(environmentSummary.text(locale: Locale(identifier: "es")) == ".env y .env.*",
                  "Spanish must not inherit English list wording")
        let groups = FileTypeSettingsGroup.matching(in: catalog, search: "package.json")
        try check(groups.flatMap(\.visibleMembers).contains { $0.id == .packageJSON },
                  "An exact filename shown in the UI must remain searchable")
    }

    /// Q-94 / CO-09: a long pattern list shows its first patterns and the count of the rest, while every pattern
    /// stays searchable; a short list is shown whole.
    private static func patternSummariesShortenLongLists() throws {
        let catalog = FormatCatalog.standard
        let english = Locale(identifier: "en")
        let visible = FormatFilenameSummary.visiblePatterns
        guard let long = catalog.descriptors.map(FormatFilenameSummary.init).max(by: { $0.patterns.count < $1.patterns.count }),
              long.patterns.count > visible + 1,
              let environment = catalog.descriptor(for: .environment) else {
            throw CheckFailure(description: "Missing a format with a long pattern list")
        }
        let short = long.shortText(locale: english)
        let hidden = long.patterns.count - visible
        try check(short.hasPrefix(Array(long.patterns.prefix(visible)).formatted(.list(type: .and).locale(english))),
                  "A long list must start with its first patterns")
        try check(short.contains(hidden.formatted(.number.locale(english))) && !short.contains(long.patterns[visible]),
                  "A long list must name the count of the rest, not the rest")
        try check(short.count < long.text(locale: english).count, "A long list must get shorter")
        let summary = FormatFilenameSummary(environment)
        try check(summary.shortText(locale: english) == summary.text(locale: english), "A short list must be shown whole")
        try check(FileTypeSettingsGroup.matching(in: catalog, search: long.patterns[long.patterns.count - 1]).contains { !$0.visibleMembers.isEmpty },
                  "A pattern hidden from the caption must stay searchable")
    }

    /// Q-94 / CO-10: a settled search announces how many types it shows, zero included, with the preview's
    /// filter sentences.
    private static func searchResultsAreAnnouncedWithTheirCount() throws {
        let english = Locale(identifier: "en")
        let groups = FileTypeSettingsGroup.matching(in: .standard, search: "package.json")
        let count = groups.reduce(0) { $0 + $1.visibleMembers.count }
        try check(count > 0, "An exact filename must match")
        try check(FileTypeSettingsGroup.resultAnnouncement(for: groups, locale: english)
                      == PreviewStrings.format(.interactionFilterMatches, arguments: [Int64(count)], locale: english),
                  "A search with results must announce their count")
        let none = FileTypeSettingsGroup.matching(in: .standard, search: "zzqqxx-no-such-type")
        try check(none.isEmpty && FileTypeSettingsGroup.resultAnnouncement(for: none, locale: english)
                      == PreviewStrings.text(.interactionFilterNoMatches),
                  "A search without results must announce that")
    }

    private static func aboutAcknowledgementsFollowTheBundledNoticeFolders() throws {
        let schemes = URL(fileURLWithPath: "/unused/ColorSchemes-Notices")
        // The card offers the color-scheme notice only; no folder name reveals a section another build would show.
        try check(BundledNotices.Folder.allCases == [.colorSchemes], "The About page knows only the color-scheme notices")
        let staged = AboutAcknowledgements(notices: BundledNotices(locations: [.colorSchemes: schemes]))
        try check(staged.colorSchemeNotices == schemes, "A staged build offers the color-scheme notices")
        let bare = AboutAcknowledgements(notices: BundledNotices(locations: [:]))
        try check(bare.colorSchemeNotices == nil, "A run without notice folders offers no row")
    }

    private final class BundleAnchor {}

    private static func enablementSummariesCountEveryMember() throws {
        let descriptors = FormatCatalog.standard.descriptors
        let optIn = descriptors.filter { !$0.defaultEnabled }.map(\.id)
        try check(optIn.isEmpty, "Version 1.0 has no format that is off by default (the STEP and IGES previews are not shipped)")
        try check(descriptors.count == 81 && !descriptors.contains { $0.id.rawValue.hasPrefix("cad.") },
                  "The shipped catalog has 81 formats and no CAD format")

        var snapshot = PreviewPreferencesSnapshot.defaults
        var summary = FileTypeEnablementSummary(descriptors, isEnabled: { snapshot.isEnabled($0) })
        try check(summary.total == descriptors.count && summary.enabled == descriptors.count && summary.state == .all,
                  "The default snapshot must leave every shipped type on")
        snapshot.setEnabled(false, for: .json)
        summary = FileTypeEnablementSummary(descriptors, isEnabled: { snapshot.isEnabled($0) })
        try check(summary.enabled == descriptors.count - 1 && summary.state == .some,
                  "One type switched off must be a mixed state")

        snapshot.setAllEnabled(true)
        summary = FileTypeEnablementSummary(descriptors, isEnabled: { snapshot.isEnabled($0) })
        try check(summary.enabled == summary.total && summary.state == .all, "Enable All must report every type")

        snapshot.setAllEnabled(false)
        summary = FileTypeEnablementSummary(descriptors, isEnabled: { snapshot.isEnabled($0) })
        try check(summary.enabled == 0 && summary.total == descriptors.count && summary.state == .none,
                  "Disable All must report no enabled type")

        snapshot.resetFileTypeChoices()
        let groups = FileTypeSettingsGroup.matching(in: .standard, search: "")
        try check(groups.flatMap(\.members).count == descriptors.count, "Groups must partition the catalog")
        for group in groups {
            let groupSummary = group.enablement(isEnabled: { snapshot.isEnabled($0) })
            let expected = group.members.filter(\.defaultEnabled).count
            try check(groupSummary.total == group.members.count && groupSummary.enabled == expected,
                      "Group counts must follow the default snapshot")
            try check(groupSummary.state == (expected == group.members.count ? .all : expected == 0 ? .none : .some),
                      "Group state must follow its counts")
        }
        try check(FileTypeEnablementSummary([], isEnabled: { _ in true }).state == .none,
                  "An empty list has nothing enabled")
    }

    private static func groupStatusUsesAllMembersWhileSearching() throws {
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setEnabled(false, for: .jsonLines)
        guard let group = FileTypeSettingsGroup.matching(in: .standard, search: ".ndjson").first else {
            throw CheckFailure(description: "NDJSON search must resolve its group")
        }
        try check(group.visibleMembers.map(\.id) == [.jsonLines] && group.members.count > 1,
                  "The search must hide other members of the group")
        let visibleOnly = FileTypeEnablementSummary(group.visibleMembers, isEnabled: { snapshot.isEnabled($0) })
        try check(visibleOnly.state == .none, "Fixture: the only visible member is off")
        let summary = group.enablement(isEnabled: { snapshot.isEnabled($0) })
        try check(summary.total == group.members.count && summary.enabled == group.members.count - 1 && summary.state == .some,
                  "Group status must count hidden members too")
    }

    /// No setting reveals a page or a command (App Review Guidelines 2.5.19 and 5.6): the five pages are always in
    /// the sidebar and the View menu, in this order, with Command-1 to Command-5.
    private static func everyPageIsAlwaysOffered() throws {
        try check(CompanionRoute.allCases == [.general, .fileTypes, .theme, .about, .tryPreview],
                  "The five destinations must keep their order")
        let keys = CompanionRoute.allCases.compactMap { $0.shortcutKey.character.wholeNumberValue }
        try check(keys == Array(1...CompanionRoute.allCases.count), "Command-1 to Command-5 must select the pages in order")
        try keyboardHelpListsEveryPageShortcut()
    }

    /// The Help text states the page shortcuts, so it must reach exactly as far as the View menu does, and it names
    /// Open File's Command-O, which is always in the File menu.
    private static func keyboardHelpListsEveryPageShortcut() throws {
        let help = PreviewStrings.text(.helpKeyboardBody, languagePreferences: ["en"])
        let pages = CompanionRoute.allCases.count
        try check(help.contains("\u{2318}1 to \u{2318}\(pages)"), "The Help must name the shortcuts of all \(pages) pages: \(help)")
        try check(help.contains("\u{2318}O"), "The Help must name Open File's shortcut: \(help)")
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

    /// The Theme page offers one built-in sample per catalog format, read through the production pipeline.
    private static func everyFormatHasARenderableSample(_ root: URL) async throws {
        let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Apps/PrevApp/Resources/AppearanceSamples.json")
        let library = AppearanceSampleLibrary(manifestURL: manifest)
        let descriptors = FormatCatalog.standard.descriptors
        let sampled = try await library.formatIDs()
        try check(sampled == descriptors.map(\.id), "Samples must cover every catalog format once, in catalog order")
        let temporary = root.appendingPathComponent("appearance-samples", isDirectory: true)
        let session = AppearanceSampleSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations),
                                              library: library, temporaryDirectory: temporary)
        try check(session.outcome == nil && !session.isLoading, "A sample must not load before it is requested")
        for descriptor in descriptors {
            session.select(descriptor.id)
            try await eventually("Sample did not finish: \(descriptor.id.rawValue)") { !session.isLoading }
            try check(session.selected == descriptor.id && session.itemName?.isEmpty == false,
                      "The finished sample must be the selected one: \(descriptor.id.rawValue)")
            // An app-authored sample is shown even for a type the person has switched off.
            try check(session.outcome != .disabledByUser(descriptor.id), "Samples must not depend on file-type choices")
            guard descriptor.presentation == .text else { continue } // CAD import needs the native helper.
            guard case .ready(let presentation) = session.outcome else {
                throw CheckFailure(description: "Sample is not renderable: \(descriptor.id.rawValue)")
            }
            try check(presentation.formatID == descriptor.id && !presentation.text.isEmpty,
                      "A sample must be recognized as its own format: \(descriptor.id.rawValue)")
            try check(presentation.redactionCount == 0, "Samples must not contain secret-like values: \(descriptor.id.rawValue)")
        }
        // A quick second choice owns the result; the first request's late answer is dropped.
        let before = session.generation
        session.select(.json)
        session.select(.markdown)
        try await eventually("Replacement sample did not finish") { !session.isLoading }
        guard case .ready(let replacement) = session.outcome else { throw CheckFailure(description: "Replacement sample failed") }
        try check(replacement.formatID == .markdown && session.selected == .markdown && session.generation != before,
                  "Only the latest selection may publish a sample")
        let directories = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        try check(directories.count == 1, "Samples must be written under one private directory")
        session.close()
        try check(session.outcome == nil && !session.isLoading
                    && !FileManager.default.fileExists(atPath: directories[0].path),
                  "Closing must cancel the sample and remove its temporary files")
        let missing = AppearanceSampleSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations),
                                              library: AppearanceSampleLibrary(manifestURL: root.appendingPathComponent("missing.json")),
                                              temporaryDirectory: temporary)
        missing.loadIfNeeded()
        try await eventually("Missing manifest did not resolve") { !missing.isLoading }
        try check(missing.outcome == .unavailable(.unavailableContent), "A missing sample must show an explicit unavailable state")
    }

    /// Closing the session forgets the file; a later file-type change must not reread it.
    private static func closedSessionIgnoresPolicyChanges(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("closed-session-preferences.json"))
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations))
        let observer = settings.observe { session.settingsChanged($0) }
        defer { settings.removeObserver(observer); session.cancel() }
        let source = root.appendingPathComponent("closed-session-source.json")
        try Data(#"{"value":1}"#.utf8).write(to: source)
        session.open(source, preferences: settings.snapshot)
        try await eventually("Preview did not finish before closing") { !session.isLoading }
        try check(session.outcome != nil && session.sourceURL == source, "Fixture: a file must be open before closing")
        session.presentsFileImporter = true
        session.close()
        let closedGeneration = session.generation
        try check(session.sourceURL == nil && session.outcome == nil && !session.isLoading && !session.presentsFileImporter,
                  "Closing must forget the file, its result and a pending picker")
        settings.setEnabled(false, for: .json)
        settings.setEnabled(true, for: .json)
        try check(session.sourceURL == nil && session.outcome == nil && !session.isLoading
                    && session.generation == closedGeneration,
                  "A policy change after closing must not start a request")
    }

    private static func appearanceRetainsSafeContent(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("appearance-preferences.json"))
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let session = PreviewSession(pipeline: PreviewPipeline(registrations: StandardFormatAdapters.registrations))
        let observer = settings.observe { session.settingsChanged($0) }
        defer { settings.removeObserver(observer); session.cancel() }
        let source = root.appendingPathComponent("appearance-source.json")
        try Data(#"{"password":"synthetic-companion-secret","value":42}"#.utf8).write(to: source)
        // The file is deleted below to prove appearance edits never reread it; a live reload would
        // legitimately show the deletion, so this check opens the file with reloading off.
        var openPreferences = settings.snapshot
        openPreferences.reloadsOnFileChange = false
        session.open(source, preferences: openPreferences)
        try await eventually("Initial preview did not finish") { !session.isLoading }
        guard case .ready(let presentation) = session.outcome else {
            throw CheckFailure(description: "Expected a ready source preview")
        }
        try check(presentation.redactionCount > 0 && !presentation.text.contains("synthetic-companion-secret"),
                  "Companion must receive privacy-filtered content")
        let originalOutcome = session.outcome
        let originalGeneration = session.generation
        try FileManager.default.removeItem(at: source)
        settings.setTheme(.dark)
        var typography = settings.snapshot.typography
        typography.showsLineNumbers = true
        typography.fontSize = 18
        settings.setTypography(typography)
        settings.setSyntaxStyle(PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.comment]))
        let chosenAppearance = settings.snapshot.appearance
        settings.saveAppearanceProfile(name: "Fixture Profile")
        guard let profile = settings.snapshot.appearanceProfiles.first else {
            throw CheckFailure(description: "Profile was not saved")
        }
        settings.resetAppearance()
        settings.applyAppearanceProfile(id: profile.id)
        try check(settings.snapshot.appearance == chosenAppearance && settings.snapshot.appearanceProfiles == [profile],
                  "Applying a profile must restore every appearance field and preserve saved profiles")
        let beforeInvalid = settings.snapshot
        settings.applyAppearance(PreviewAppearance(typography: PreviewTypography(fontSize: .infinity)))
        settings.saveAppearanceProfile(name: "")
        try check(settings.snapshot == beforeInvalid, "Invalid appearance and profile names must leave choices unchanged")
        try await eventually("Appearance preferences did not save") { settings.saveState == .saved }
        try check(session.outcome == originalOutcome && session.generation == originalGeneration && !session.isLoading,
                  "Appearance changes must not reread a missing source or replace its safe presentation")
        let persisted = await store.load()
        try check(persisted.snapshot == settings.snapshot, "Style and profile changes must persist as one complete snapshot")
        settings.deleteAppearanceProfile(id: profile.id)
        try check(settings.snapshot.appearanceProfiles.isEmpty && settings.snapshot.appearance == chosenAppearance,
                  "Deleting a profile must preserve the current appearance")
        settings.setEnabled(false, for: .json)
        try check(session.outcome == .disabledByUser(.json) && !session.isLoading,
                  "Disabling the recognized type must synchronously clear content despite the source disappearing")
        try await eventually("Disable preference did not save") { settings.saveState == .saved }
    }

    private static func groupChangesAreAtomic(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("group-preferences.json"))
        var initial = PreviewPreferencesSnapshot.disabledContentFallback
        initial.setEnabled(true, for: .plainText)
        initial.theme = .dark
        try await store.save(initial)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let groups = FileTypeSettingsGroup.matching(in: .standard, search: " .ndjson ")
        guard let group = groups.first else { throw CheckFailure(description: "NDJSON search must resolve its group") }
        try check(group.visibleMembers.map(\.id) == [.jsonLines], "Alias search must filter individual rows")
        // Membership comes from the catalog, so new structured formats need no change here.
        let structured = Set(FormatCatalog.standard.descriptors.filter { $0.group == .structured }.map(\.id))
        try check(structured.isSuperset(of: [FormatID.json, .jsonLines, .yaml, .toml, .xml, .csv])
                  && Set(group.members.map(\.id)) == structured,
                  "Search must retain hidden members for whole-group controls")
        let localizedGroup = FileTypeSettingsGroup.matching(in: .standard, search: PreviewStrings.text(group.nameKey))
        try check(localizedGroup.first?.visibleMembers.count == group.members.count,
                  "Localized group-name search must reveal every group member")
        var publications = 0
        let observer = settings.observe { _ in publications += 1 }
        defer { settings.removeObserver(observer) }
        settings.setEnabled(true, for: group.members.map(\.id))
        settings.setEnabled(true, for: group.members.map(\.id))
        try check(publications == 1, "A collection toggle must publish one complete group change")
        try check(group.members.allSatisfy { settings.isEnabled($0.id) } && settings.isEnabled(.plainText),
                  "Whole-group changes must include hidden members and retain unrelated choices")
        try check(!settings.snapshot.defaultEnabled && !settings.isEnabled(FormatID(rawValue: "future.format"))
                  && settings.snapshot.theme == .dark, "Group enablement must preserve global policy and appearance")
        try await eventually("Group preferences did not save") { settings.saveState == .saved }
        let loaded = await store.load()
        try check(loaded.state == .loaded && loaded.snapshot == settings.snapshot, "Group publication must persist completely")

        let unavailable = CompanionSettings(store: nil, storageMode: .unavailable)
        await unavailable.load()
        var unavailablePublications = 0
        let unavailableObserver = unavailable.observe { _ in unavailablePublications += 1 }
        defer { unavailable.removeObserver(unavailableObserver) }
        unavailable.setEnabled(true, for: group.members.map(\.id))
        unavailable.setEnabled(true, for: group.members.map(\.id))
        try check(unavailable.saveState == .failed && unavailablePublications == 1,
                  "Collection writes must remain atomic when storage is unavailable")
    }

    private static func sameValueResetRepairsCorruption(_ root: URL) async throws {
        let url = root.appendingPathComponent("corrupt-preferences.json")
        try Data("broken".utf8).write(to: url)
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        try check(settings.recoveredSettings && settings.snapshot == .disabledContentFallback,
                  "Corrupt storage must use disabled defaults")
        settings.resetAppearance()
        try await eventually("Same-value reset did not repair corrupt storage") { settings.saveState == .saved }
        let loaded = await store.load()
        try check(loaded.state == .loaded && loaded.snapshot == .disabledContentFallback && !settings.recoveredSettings,
                  "Repair must persist the current schema without re-enabling formats")
    }

    private static func sameValueResetRetriesFailedSave(_ root: URL) async throws {
        let parent = root.appendingPathComponent("blocked-parent")
        try Data("not a directory".utf8).write(to: parent)
        let store = PreferenceStore(url: parent.appendingPathComponent("preferences.json"))
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        settings.resetAppearance()
        try await eventually("Unwritable path did not report a save failure") { settings.saveState == .failed }
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        settings.resetAppearance()
        try await eventually("Same-value reset did not retry the failed save") { settings.saveState == .saved }
        let loaded = await store.load()
        try check(loaded.state == .loaded && loaded.snapshot == .disabledContentFallback,
                  "Retry must retain the fail-closed format policy")
    }
}
