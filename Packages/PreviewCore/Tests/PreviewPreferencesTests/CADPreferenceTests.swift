import Foundation
import Testing
import PreviewContracts
import PreviewPreferences
import PreviewTestSupport

private let igesID = CADTestFormatIDs.iges
private let stepID = CADTestFormatIDs.step
// Version 1.0 ships without the CAD formats; these tests keep the opt-in rules honest against the two descriptors
// kept in Configuration/CADFormatCatalogEntries.json, for the build that brings them back.
private func cadCatalog() throws -> FormatCatalog { try CADCatalogFixture.catalog() }

@Test func CADStartsDisabledWithoutChangingExistingFormatDefaults() throws {
    let catalog = try cadCatalog()
    let defaults = PreviewPreferencesSnapshot.defaults
    #expect(defaults.isEnabled(.json, catalog: catalog))
    #expect(defaults.isEnabled(.plainText, catalog: catalog))
    #expect(!defaults.isEnabled(igesID, catalog: catalog))
    #expect(!defaults.isEnabled(stepID, catalog: catalog))
}

@Test func CADOptInsAreIndependentAndResetRestoresDefaultOff() throws {
    let catalog = try cadCatalog()
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.setEnabled(true, for: igesID, catalog: catalog)
    #expect(snapshot.isEnabled(igesID, catalog: catalog))
    #expect(!snapshot.isEnabled(stepID, catalog: catalog))
    #expect(snapshot.formatOverrides[igesID] == true)
    snapshot.setEnabled(false, for: igesID, catalog: catalog)
    #expect(!snapshot.isEnabled(igesID, catalog: catalog))
    #expect(snapshot.formatOverrides[igesID] == nil)
    snapshot.setAllEnabled(true, catalog: catalog)
    #expect(snapshot.isEnabled(igesID, catalog: catalog))
    #expect(snapshot.isEnabled(stepID, catalog: catalog))
    snapshot.resetFileTypeChoices()
    #expect(snapshot.defaultEnabled && snapshot.formatOverrides.isEmpty)
    #expect(!snapshot.isEnabled(igesID, catalog: catalog))
    #expect(!snapshot.isEnabled(stepID, catalog: catalog))
}

@Test func ExplicitCADOptInPersistsInSchemaSixWithoutChangingAppearance() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preferences.json")
    let writer = PreferenceStore(url: url)
    let catalog = try cadCatalog()
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.theme = .dark
    snapshot.typography.fontSize = 18
    snapshot.setEnabled(true, for: igesID, catalog: catalog)
    try await writer.save(snapshot)
    let reader = PreferenceStore(url: url)
    let result = await reader.load()
    #expect(result.state == .loaded)
    #expect(result.snapshot == snapshot)
    #expect(result.snapshot.isEnabled(igesID, catalog: catalog))
    #expect(!result.snapshot.isEnabled(stepID, catalog: catalog))
    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 6)
    #expect((object["formatOverrides"] as? [String: Bool])?["cad.iges"] == true)
}

@Test func NewOptInFormatsDoNotInheritEarlierEnableAllConsent() throws {
    let catalog = try cadCatalog()
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.setAllEnabled(true, catalog: catalog)
    let futureID = FormatID(rawValue: "cad.future")
    let futureDescriptor = FormatDescriptor(id: futureID, contentTypes: [.data], suffixAliases: [], group: .media,
        presentation: .geometry, nameKey: "test.future.name", descriptionKey: "test.future.description", defaultEnabled: false)
    let expandedCatalog = FormatCatalog(descriptors: catalog.descriptors + [futureDescriptor])
    #expect(snapshot.isEnabled(igesID, catalog: expandedCatalog))
    #expect(!snapshot.isEnabled(futureID, catalog: expandedCatalog))
    snapshot.setAllEnabled(true, catalog: expandedCatalog)
    #expect(snapshot.isEnabled(futureID, catalog: expandedCatalog))
    snapshot.setAllEnabled(false, catalog: expandedCatalog)
    #expect(!snapshot.isEnabled(igesID, catalog: expandedCatalog))
    #expect(!snapshot.isEnabled(stepID, catalog: expandedCatalog))
    #expect(!snapshot.isEnabled(futureID, catalog: expandedCatalog))
    #expect(snapshot.formatOverrides.isEmpty)
}

@Test(arguments: [1, 2, 3, 4, 5, 6])
func HistoricalEnableAllDoesNotOptInCAD(schema: Int) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preferences.json")
    let catalog = try cadCatalog()
    let store = PreferenceStore(url: url)
    try await store.save(.defaults)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    object["schemaVersion"] = schema
    if schema < 6 {
        for field in ["reloadsOnFileChange", "showsContentThumbnails", "folderDepth", "showsHiddenFolderItems"] {
            object.removeValue(forKey: field)
        }
        var syntax = try #require(object["syntaxStyle"] as? [String: Any])
        syntax.removeValue(forKey: "lightScheme"); syntax.removeValue(forKey: "darkScheme")
        object["syntaxStyle"] = syntax
    }
    if schema < 5 { object.removeValue(forKey: "syntaxStyle"); object.removeValue(forKey: "appearanceProfiles") }
    if schema < 4 {
        var typography = try #require(object["typography"] as? [String: Any])
        typography.removeValue(forKey: "showsLineNumbers")
        object["typography"] = typography
    }
    if schema < 3 { object.removeValue(forKey: "theme") }
    if schema == 2 { object["typography"] = ["fontSize": 13, "wrapsLines": true] }
    if schema == 1 { object.removeValue(forKey: "typography") }
    let original = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    try original.write(to: url)
    let result = await store.load()
    #expect(result.state == (schema == 6 ? .loaded : .migrated))
    #expect(result.snapshot.isEnabled(.json))
    #expect(!result.snapshot.isEnabled(igesID, catalog: catalog))
    #expect(!result.snapshot.isEnabled(stepID, catalog: catalog))
    #expect(try Data(contentsOf: url) == original)
}

// MARK: - A saved choice for a format this build does not know

/// A Mac that ran an earlier build, or the owner's test Mac, may hold a saved choice for `cad.step` or `cad.iges`.
/// Version 1.0 has neither format, so those ids are unknown to its catalog; the build that brings them back must
/// still find the choice the person made.
@Test func aSavedChoiceForAnIdTheCatalogDoesNotKnowLoadsIsIgnoredAndSurvivesALaterSave() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preferences.json")
    let store = PreferenceStore(url: url)
    var seed = PreviewPreferencesSnapshot.defaults
    seed.theme = .dark
    seed.setEnabled(false, for: .json)
    try await store.save(seed)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var overrides = try #require(object["formatOverrides"] as? [String: Bool])
    overrides["cad.step"] = true
    overrides["cad.iges"] = true
    overrides["future.unknown-format"] = false
    object["formatOverrides"] = overrides
    try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: url)

    let loaded = await PreferenceStore(url: url).load()
    #expect(loaded.state == .loaded)
    #expect(loaded.snapshot.theme == .dark)
    // The product catalog neither lists nor consults the unknown ids: known formats keep their own choices.
    #expect(FormatCatalog.standard.descriptor(for: stepID) == nil)
    #expect(!loaded.snapshot.isEnabled(.json))
    #expect(loaded.snapshot.isEnabled(.plainText))
    #expect(FormatCatalog.standard.descriptors.allSatisfy { $0.id == .json || loaded.snapshot.isEnabled($0.id) })

    // An unrelated save keeps the stored choices, so a build that knows the ids finds the consent again.
    var changed = loaded.snapshot
    changed.theme = .light
    try await store.save(changed)
    let reloaded = await PreferenceStore(url: url).load()
    #expect(reloaded.state == .loaded)
    #expect(reloaded.snapshot.theme == .light)
    let catalog = try cadCatalog()
    #expect(reloaded.snapshot.isEnabled(stepID, catalog: catalog))
    #expect(reloaded.snapshot.isEnabled(igesID, catalog: catalog))
    let written = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(written["formatOverrides"] as? [String: Bool] == overrides)
}

@Test func theBulkActionsOfABuildWithoutTheIdDropItsStoredChoiceWithoutError() throws {
    var snapshot = PreviewPreferencesSnapshot(formatOverrides: [stepID: true, .json: false])
    snapshot.setAllEnabled(true)
    #expect(snapshot.formatOverrides.isEmpty)
    #expect(snapshot.defaultEnabled)
    snapshot.formatOverrides[stepID] = true
    snapshot.resetFileTypeChoices()
    #expect(snapshot.formatOverrides.isEmpty)
}
