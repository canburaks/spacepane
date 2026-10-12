import Foundation
import Darwin
import Testing
import PreviewContracts
import PreviewPreferences

private struct StoreFixture {
    let directory: URL
    let url: URL
    let store: PreferenceStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("preferences.json")
        store = PreferenceStore(url: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let currentAppearanceDocument = #"{"schemaVersion":6,"defaultEnabled":false,"formatOverrides":{"data.json":true},"theme":"dark","syntaxStyle":{"usesColor":true,"boldRoles":[],"italicRoles":[],"lightScheme":"standard","darkScheme":"standard"},"appearanceProfiles":[],"reloadsOnFileChange":true,"showsContentThumbnails":true,"folderDepth":1,"showsHiddenFolderItems":false,"typography":{"fontSize":18,"wrapsLines":false,"fontFamily":"Menlo","weight":"semibold","italic":true,"lineSpacing":3,"characterSpacing":0.5,"ligatures":false,"tabWidth":8,"showsLineNumbers":true}}"#

private func currentAppearanceObject() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(currentAppearanceDocument.utf8)) as? [String: Any])
}

@Test func missingSettingsHaveDocumentedDefaultsAndCorruptionFailsClosed() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .defaults, state: .defaults))
    try Data("broken".utf8).write(to: fixture.url)
    let corrupt = await fixture.store.load()
    #expect(corrupt.state == .corrupt)
    #expect(!corrupt.snapshot.isEnabled(.plainText))
    #expect(!corrupt.snapshot.isEnabled(.json))
}

@Test func disableAllPersistsAndNewFormatsStayDisabled() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var snapshot = PreviewPreferencesSnapshot.defaults
    snapshot.setAllEnabled(false)
    snapshot.setEnabled(true, for: .json)
    snapshot.typography = PreviewTypography(fontSize: 18, wrapsLines: false)
    try await fixture.store.save(snapshot)
    let restarted = PreferenceStore(url: fixture.url)
    #expect(await restarted.load().snapshot == snapshot)
    #expect(!snapshot.isEnabled(FormatID(rawValue: "future.format")))
    snapshot.setEnabled(false, for: .json)
    #expect(snapshot.formatOverrides.isEmpty)
    snapshot.resetFileTypeChoices()
    #expect(snapshot.defaultEnabled)
    #expect(snapshot.formatOverrides.isEmpty)
}

@Test func schemaOneMigrationPreservesChoicesAndDefaultsTypography() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    try Data(#"{"schemaVersion":1,"defaultEnabled":false,"formatOverrides":{"data.json":true}}"#.utf8).write(to: fixture.url)
    let result = await fixture.store.load()
    #expect(result.state == .migrated)
    #expect(!result.snapshot.isEnabled(.plainText))
    #expect(result.snapshot.isEnabled(.json))
    #expect(result.snapshot.typography == PreviewTypography())
    #expect(result.snapshot.theme == .system)
    try await fixture.store.save(result.snapshot)
    #expect(await fixture.store.load().state == .loaded)
}

@Test func completeCurrentAppearanceDocumentLoadsWithoutReenablingTypes() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    try Data(currentAppearanceDocument.utf8).write(to: fixture.url)
    let result = await fixture.store.load()
    #expect(result.state == .loaded)
    #expect(!result.snapshot.isEnabled(.plainText))
    #expect(result.snapshot.isEnabled(.json))
    #expect(result.snapshot.theme == .dark)
    #expect(result.snapshot.typography == PreviewTypography(fontSize: 18, wrapsLines: false,
        fontFamily: "Menlo", weight: .semibold, italic: true, lineSpacing: 3, characterSpacing: 0.5,
        ligatures: false, tabWidth: 8, showsLineNumbers: true))
}

@Test func schemaTwoMigrationPreservesTypographyAndDisabledChoicesWithoutWriting() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    let original = Data(#"{"schemaVersion":2,"defaultEnabled":false,"formatOverrides":{"data.json":true,"future.disabled":false},"typography":{"fontSize":22,"wrapsLines":false}}"#.utf8)
    try original.write(to: fixture.url)
    let result = await fixture.store.load()
    #expect(result.state == .migrated)
    #expect(result.snapshot.defaultEnabled == false)
    #expect(result.snapshot.formatOverrides == [.json: true, FormatID(rawValue: "future.disabled"): false])
    #expect(!result.snapshot.isEnabled(FormatID(rawValue: "future.new")))
    #expect(result.snapshot.typography == PreviewTypography(fontSize: 22, wrapsLines: false))
    #expect(result.snapshot.theme == .system)
    #expect(try Data(contentsOf: fixture.url) == original)
    try await fixture.store.save(result.snapshot)
    let header = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any])
    #expect(header["schemaVersion"] as? Int == 6)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: result.snapshot, state: .loaded))
}

@Test func schemaThreeMigrationPreservesEveryAppearanceValueAndPolicyWithoutWriting() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var document = try currentAppearanceObject()
    document["schemaVersion"] = 3
    document["formatOverrides"] = ["data.json": true, "future.disabled": false]
    var typography = try #require(document["typography"] as? [String: Any])
    typography.removeValue(forKey: "showsLineNumbers")
    document["typography"] = typography
    let original = try JSONSerialization.data(withJSONObject: document)
    try original.write(to: fixture.url)
    let result = await fixture.store.load()
    let expected = PreviewPreferencesSnapshot(defaultEnabled: false,
        formatOverrides: [.json: true, FormatID(rawValue: "future.disabled"): false],
        typography: PreviewTypography(fontSize: 18, wrapsLines: false, fontFamily: "Menlo",
            weight: .semibold, italic: true, lineSpacing: 3, characterSpacing: 0.5, ligatures: false, tabWidth: 8),
        theme: .dark)
    #expect(result == PreferencesLoadResult(snapshot: expected, state: .migrated))
    #expect(!result.snapshot.typography.showsLineNumbers)
    #expect(!result.snapshot.isEnabled(FormatID(rawValue: "future.new")))
    #expect(try Data(contentsOf: fixture.url) == original)
    try await fixture.store.save(result.snapshot)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: expected, state: .loaded))
}

@Test(arguments: ["fontFamily", "weight", "italic", "lineSpacing", "characterSpacing", "ligatures", "tabWidth"])
func incompleteSchemaThreeStillFailsClosed(field: String) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var document = try currentAppearanceObject()
    document["schemaVersion"] = 3
    var typography = try #require(document["typography"] as? [String: Any])
    typography.removeValue(forKey: "showsLineNumbers")
    typography.removeValue(forKey: field)
    document["typography"] = typography
    try JSONSerialization.data(withJSONObject: document).write(to: fixture.url)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: PreviewTheme.allCases, PreviewFontWeight.allCases)
func everyThemeAndWeightRoundTripsWithCompleteTypography(theme: PreviewTheme, weight: PreviewFontWeight) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    let typography = PreviewTypography(fontSize: 27.5, wrapsLines: false, fontFamily: "Missing Synthetic Family 🌍",
        weight: weight, italic: true, lineSpacing: 7.5, characterSpacing: 1.25, ligatures: false, tabWidth: 12,
        showsLineNumbers: true)
    let snapshot = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.plainText: true],
        typography: typography, theme: theme)
    try await fixture.store.save(snapshot)
    #expect(await PreferenceStore(url: fixture.url).load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
}

@Test func appearanceAndFileTypeResetsPreserveTheOtherSettings() {
    let typography = PreviewTypography(fontSize: 24, wrapsLines: false, fontFamily: "Menlo", weight: .bold,
        italic: true, lineSpacing: 2, characterSpacing: 0.5, ligatures: false, tabWidth: 8, showsLineNumbers: true)
    let original = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
        typography: typography, theme: .highContrast)
    var appearanceReset = original
    appearanceReset.resetAppearance()
    #expect(appearanceReset.typography == PreviewTypography())
    #expect(appearanceReset.theme == .system)
    #expect(appearanceReset.defaultEnabled == original.defaultEnabled)
    #expect(appearanceReset.formatOverrides == original.formatOverrides)
    var fileTypeReset = original
    fileTypeReset.resetFileTypeChoices()
    #expect(fileTypeReset.typography == typography)
    #expect(fileTypeReset.theme == .highContrast)
    #expect(fileTypeReset.defaultEnabled && fileTypeReset.formatOverrides.isEmpty)
}

@Test(arguments: [
    PreviewTypography(fontSize: 8, fontFamily: String(repeating: "a", count: 128),
                      lineSpacing: 0, characterSpacing: -1, tabWidth: 1),
    PreviewTypography(fontSize: 48, fontFamily: String(repeating: "é", count: 64),
                      lineSpacing: 20, characterSpacing: 10, tabWidth: 16),
    PreviewTypography()
]) func typographyBoundsAndSystemFontDefaultArePersistable(typography: PreviewTypography) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    #expect(typography.isValid)
    let snapshot = PreviewPreferencesSnapshot(typography: typography)
    try await fixture.store.save(snapshot)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
    let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any])
    let storedTypography = try #require(document["typography"] as? [String: Any])
    #expect(storedTypography.keys.contains("fontFamily"))
    if typography.fontFamily == nil { #expect(storedTypography["fontFamily"] is NSNull) }
}

@Test(arguments: [
    PreviewTypography(fontSize: .nan), PreviewTypography(fontSize: .infinity),
    PreviewTypography(fontSize: 7.99), PreviewTypography(fontSize: 48.01),
    PreviewTypography(lineSpacing: .nan), PreviewTypography(lineSpacing: .infinity),
    PreviewTypography(lineSpacing: -0.01), PreviewTypography(lineSpacing: 20.01),
    PreviewTypography(characterSpacing: .nan), PreviewTypography(characterSpacing: -.infinity),
    PreviewTypography(characterSpacing: -1.01), PreviewTypography(characterSpacing: 10.01),
    PreviewTypography(tabWidth: 0), PreviewTypography(tabWidth: 17), PreviewTypography(tabWidth: .max),
    PreviewTypography(fontFamily: ""), PreviewTypography(fontFamily: " "),
    PreviewTypography(fontFamily: " Menlo"), PreviewTypography(fontFamily: "Menlo "),
    PreviewTypography(fontFamily: "Menlo\nOther"), PreviewTypography(fontFamily: "Menlo\u{0000}"),
    PreviewTypography(fontFamily: "Menlo\u{2028}Other"), PreviewTypography(fontFamily: "Menlo\u{202E}"),
    PreviewTypography(fontFamily: String(repeating: "a", count: 129)),
    PreviewTypography(fontFamily: String(repeating: "é", count: 65))
]) func invalidTypographyCannotReplaceSavedChoices(typography: PreviewTypography) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    try await fixture.store.save(.disabledContentFallback)
    #expect(!typography.isValid)
    await #expect(throws: PreferencesStoreError.invalidSnapshot) {
        try await fixture.store.save(PreviewPreferencesSnapshot(typography: typography))
    }
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .loaded))
}

@Test(arguments: ["defaultEnabled", "formatOverrides", "theme", "syntaxStyle", "appearanceProfiles", "typography", "fontSize", "wrapsLines",
                  "fontFamily", "weight", "italic", "lineSpacing", "characterSpacing", "ligatures", "tabWidth", "showsLineNumbers",
                  "reloadsOnFileChange", "showsContentThumbnails", "folderDepth", "showsHiddenFolderItems"])
func missingCurrentSchemaFieldsFailClosed(field: String) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var document = try currentAppearanceObject()
    if document.keys.contains(field) { document.removeValue(forKey: field) }
    else {
        var typography = try #require(document["typography"] as? [String: Any])
        typography.removeValue(forKey: field)
        document["typography"] = typography
    }
    try JSONSerialization.data(withJSONObject: document).write(to: fixture.url)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: [
    ("fontSize", "1e99"), ("lineSpacing", "-0.01"), ("lineSpacing", "20.01"),
    ("characterSpacing", "-1.01"), ("characterSpacing", "10.01"),
    ("tabWidth", "0"), ("tabWidth", "17"), ("tabWidth", "1.5"),
    ("fontFamily", #""""#), ("fontFamily", #""Menlo\nOther""#),
    ("weight", #""heavy""#), ("italic", #""true""#), ("ligatures", "null"),
    ("showsLineNumbers", "null"), ("showsLineNumbers", #""true""#)
]) func invalidImportedAppearanceFailsClosed(field: String, rawValue: String) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var document = try currentAppearanceObject()
    var typography = try #require(document["typography"] as? [String: Any])
    typography[field] = try JSONSerialization.jsonObject(with: Data(rawValue.utf8), options: .fragmentsAllowed)
    document["typography"] = typography
    try JSONSerialization.data(withJSONObject: document).write(to: fixture.url)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test func unknownThemeFailsClosed() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    var document = try currentAppearanceObject()
    document["theme"] = "unknownTheme"
    try JSONSerialization.data(withJSONObject: document).write(to: fixture.url)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: [
    #"{"schemaVersion":99,"defaultEnabled":true,"formatOverrides":{}}"#,
    #"{"schemaVersion":2,"defaultEnabled":true,"formatOverrides":{},"typography":{"fontSize":999,"wrapsLines":true}}"#,
    #"{"schemaVersion":2,"defaultEnabled":true,"formatOverrides":{}}"#,
    #"{"schemaVersion":2,"defaultEnabled":true,"formatOverrides":{"bad ID":true},"typography":{"fontSize":13,"wrapsLines":true}}"#
]) func invalidExistingSettingsNeverReenableContent(document: String) async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    try Data(document.utf8).write(to: fixture.url)
    let result = await fixture.store.load()
    #expect(!result.snapshot.defaultEnabled)
    #expect(result.snapshot.formatOverrides.isEmpty)
    #expect(result.state == .corrupt || result.state == .unsupportedVersion)
}

@Test func invalidSnapshotAndWriteFailuresAreTyped() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    let invalid = PreviewPreferencesSnapshot(typography: PreviewTypography(fontSize: .infinity))
    await #expect(throws: PreferencesStoreError.invalidSnapshot) { try await fixture.store.save(invalid) }
    let blocked = PreferenceStore(url: fixture.directory)
    await #expect(throws: PreferencesStoreError.cannotWrite) { try await blocked.save(.defaults) }
}

@Test func independentReadersObserveCompleteAtomicSnapshots() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    let enabled = PreviewPreferencesSnapshot.defaults
    let disabled = PreviewPreferencesSnapshot.disabledContentFallback
    try await fixture.store.save(enabled)
    let reader = PreferenceStore(url: fixture.url)
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for index in 0..<50 { try await fixture.store.save(index.isMultiple(of: 2) ? enabled : disabled) }
        }
        group.addTask {
            for _ in 0..<100 {
                let result = await reader.load()
                #expect(result.state == .loaded)
                #expect(result.snapshot == enabled || result.snapshot == disabled)
            }
        }
        try await group.waitForAll()
    }
}

@Test func settingsSpecialFilesAndOversizedDocumentsFailClosed() async throws {
    let fixture = try StoreFixture()
    defer { fixture.remove() }
    let created = fixture.url.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
    #expect(created == 0)
    #expect(await fixture.store.load().state == .unreadable)
    try FileManager.default.removeItem(at: fixture.url)
    try Data(repeating: 65, count: 65_537).write(to: fixture.url)
    #expect(await fixture.store.load().state == .corrupt)
}
