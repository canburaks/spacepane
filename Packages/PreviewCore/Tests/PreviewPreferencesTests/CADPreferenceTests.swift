import Foundation
import Testing
import PreviewContracts
import PreviewPreferences

private let igesID = FormatID.iges
private let stepID = FormatID.step

@Test func CADStartsDisabledWithoutChangingExistingFormatDefaults() {
    let defaults = PreviewPreferencesSnapshot.defaults
    #expect(defaults.isEnabled(.json))
    #expect(defaults.isEnabled(.plainText))
    #expect(!defaults.isEnabled(igesID))
    #expect(!defaults.isEnabled(stepID))
}

@Test func CADOptInsAreIndependentAndResetRestoresDefaultOff() {
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.setEnabled(true, for: igesID)
    #expect(snapshot.isEnabled(igesID))
    #expect(!snapshot.isEnabled(stepID))
    #expect(snapshot.formatOverrides[igesID] == true)
    snapshot.setEnabled(false, for: igesID)
    #expect(!snapshot.isEnabled(igesID))
    #expect(snapshot.formatOverrides[igesID] == nil)
    snapshot.setAllEnabled(true)
    #expect(snapshot.isEnabled(igesID))
    #expect(snapshot.isEnabled(stepID))
    snapshot.resetFileTypeChoices()
    #expect(snapshot.defaultEnabled && snapshot.formatOverrides.isEmpty)
    #expect(!snapshot.isEnabled(igesID))
    #expect(!snapshot.isEnabled(stepID))
}

@Test func ExplicitCADOptInPersistsInSchemaSixWithoutChangingAppearance() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preferences.json")
    let writer = PreferenceStore(url: url)
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.theme = .dark
    snapshot.typography.fontSize = 18
    snapshot.setEnabled(true, for: igesID)
    try await writer.save(snapshot)
    let reader = PreferenceStore(url: url)
    let result = await reader.load()
    #expect(result.state == .loaded)
    #expect(result.snapshot == snapshot)
    #expect(result.snapshot.isEnabled(igesID))
    #expect(!result.snapshot.isEnabled(stepID))
    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 6)
    #expect((object["formatOverrides"] as? [String: Bool])?["cad.iges"] == true)
}

@Test func NewOptInFormatsDoNotInheritEarlierEnableAllConsent() {
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.setAllEnabled(true)
    let futureID = FormatID(rawValue: "cad.future")
    let futureDescriptor = FormatDescriptor(id: futureID, contentTypes: [.data], suffixAliases: [], group: .media,
        presentation: .geometry, nameKey: "test.future.name", descriptionKey: "test.future.description", defaultEnabled: false)
    let expandedCatalog = FormatCatalog(descriptors: FormatCatalog.standard.descriptors + [futureDescriptor])
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
    #expect(!result.snapshot.isEnabled(igesID))
    #expect(!result.snapshot.isEnabled(stepID))
    #expect(try Data(contentsOf: url) == original)
}
