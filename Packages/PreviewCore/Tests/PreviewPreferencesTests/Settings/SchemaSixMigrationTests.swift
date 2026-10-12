import Foundation
import Testing
import PreviewContracts
import PreviewPreferences

/// Schema 6 persists the behavior choices and the color schemes. Every earlier schema migrates its own
/// fields strictly and defaults only the fields it did not have; a migration never writes the file.
private struct SixFixture {
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
    func write(_ object: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try data.write(to: url)
        return data
    }
}

private func typographyObject() -> [String: Any] {
    [
        "fontSize": 18, "wrapsLines": false, "fontFamily": "Menlo", "weight": "semibold", "italic": true,
        "lineSpacing": 3, "characterSpacing": 0.5, "ligatures": false, "tabWidth": 8, "showsLineNumbers": true
    ]
}
private let behaviorFields = ["reloadsOnFileChange", "showsContentThumbnails", "folderDepth", "showsHiddenFolderItems"]
private let migratedTypography = PreviewTypography(fontSize: 18, wrapsLines: false, fontFamily: "Menlo",
    weight: .semibold, italic: true, lineSpacing: 3, characterSpacing: 0.5, ligatures: false, tabWidth: 8,
    showsLineNumbers: true)

private func schemeSixObject() -> [String: Any] {
    [
        "schemaVersion": 6, "defaultEnabled": false,
        "formatOverrides": ["data.json": true, "future.disabled": false], "theme": "dark",
        "typography": typographyObject(),
        "syntaxStyle": ["usesColor": false, "boldRoles": ["key"], "italicRoles": ["comment"],
                        "lightScheme": "paper", "darkScheme": "dracula"],
        "appearanceProfiles": [],
        "reloadsOnFileChange": false, "showsContentThumbnails": false, "folderDepth": 3, "showsHiddenFolderItems": true
    ]
}

private let fixtureProfileID = UUID(uuidString: "5B0D4F5E-8E43-4B6B-9E1F-3D1C2A9F0A11")!

private func schemeFiveObject() -> [String: Any] {
    [
        "schemaVersion": 5, "defaultEnabled": false,
        "formatOverrides": ["data.json": true, "future.disabled": false], "theme": "dark",
        "typography": typographyObject(),
        "syntaxStyle": ["usesColor": false, "boldRoles": ["key"], "italicRoles": ["comment"]],
        "appearanceProfiles": [[
            "id": fixtureProfileID.uuidString, "name": "Fixture 🌍",
            "appearance": ["typography": typographyObject(), "theme": "light",
                           "syntaxStyle": ["usesColor": true, "boldRoles": [], "italicRoles": ["heading"]]]
        ]]
    ]
}

/// The state every schema before 6 must produce for the fields that did not exist yet.
private func expectNewFieldsDefaulted(_ snapshot: PreviewPreferencesSnapshot) {
    #expect(snapshot.reloadsOnFileChange)
    #expect(snapshot.showsContentThumbnails)
    #expect(snapshot.folderDepth == 1)
    #expect(!snapshot.showsHiddenFolderItems)
    #expect(snapshot.syntaxStyle.lightScheme == .standard)
    #expect(snapshot.syntaxStyle.darkScheme == .standard)
}

@Test func schemaSixRoundTripsEveryNewFieldAndBothSchemes() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    let profile = PreviewAppearanceProfile(name: "Schemes", appearance: PreviewAppearance(
        typography: migratedTypography, theme: .light,
        syntaxStyle: PreviewSyntaxStyle(boldRoles: [.heading], lightScheme: .solarizedLight, darkScheme: .oneDark)))
    let snapshot = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
        typography: migratedTypography, theme: .dark,
        syntaxStyle: PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.comment],
                                        lightScheme: .githubLight, darkScheme: .nord),
        appearanceProfiles: [profile], reloadsOnFileChange: false, showsContentThumbnails: false,
        folderDepth: 4, showsHiddenFolderItems: true)
    try await fixture.store.save(snapshot)
    // A reader in another process constructs its own store over the same file.
    let reader = PreferenceStore(url: fixture.url)
    #expect(await reader.load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 6)
    #expect(object["reloadsOnFileChange"] as? Bool == false)
    #expect(object["showsContentThumbnails"] as? Bool == false)
    #expect(object["folderDepth"] as? Int == 4)
    #expect(object["showsHiddenFolderItems"] as? Bool == true)
    let syntax = try #require(object["syntaxStyle"] as? [String: Any])
    #expect(syntax["lightScheme"] as? String == "githubLight" && syntax["darkScheme"] as? String == "nord")
    #expect(snapshot.requestOptions == PreviewRequestOptions(folderDepth: 4, includesHiddenItems: true))
}

@Test func defaultsAreTheDocumentedBehaviorAndStandardSchemes() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    expectNewFieldsDefaulted(.defaults)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .defaults, state: .defaults))
    try await fixture.store.save(.defaults)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .defaults, state: .loaded))
}

@Test func schemaFiveMigratesSyntaxStyleAndProfilesToStandardSchemesAndDefaultsOnlyNewFields() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    let original = try fixture.write(schemeFiveObject())
    let result = await fixture.store.load()
    #expect(result.state == .migrated)
    let snapshot = result.snapshot
    #expect(!snapshot.defaultEnabled)
    #expect(snapshot.formatOverrides == [.json: true, FormatID(rawValue: "future.disabled"): false])
    #expect(snapshot.theme == .dark)
    #expect(snapshot.typography == migratedTypography)
    #expect(snapshot.syntaxStyle == PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.comment]))
    expectNewFieldsDefaulted(snapshot)
    let profile = try #require(snapshot.appearanceProfiles.first)
    #expect(snapshot.appearanceProfiles.count == 1)
    #expect(profile.id == fixtureProfileID && profile.name == "Fixture 🌍")
    #expect(profile.appearance == PreviewAppearance(typography: migratedTypography, theme: .light,
        syntaxStyle: PreviewSyntaxStyle(italicRoles: [.heading])))
    #expect(!snapshot.isEnabled(FormatID(rawValue: "future.new")))
    #expect(try Data(contentsOf: fixture.url) == original)
    // The first save from the companion publishes schema 6 and the result then loads as current.
    try await fixture.store.save(snapshot)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
}

@Test(arguments: [1, 2, 3, 4, 5])
func everyEarlierSchemaDefaultsOnlyTheFieldsItLacked(schema: Int) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeFiveObject()
    object["schemaVersion"] = schema
    if schema < 5 { object.removeValue(forKey: "syntaxStyle"); object.removeValue(forKey: "appearanceProfiles") }
    if schema < 4 {
        var typography = typographyObject()
        typography.removeValue(forKey: "showsLineNumbers")
        object["typography"] = typography
    }
    if schema < 3 { object.removeValue(forKey: "theme") }
    if schema == 2 { object["typography"] = ["fontSize": 22, "wrapsLines": false] }
    if schema == 1 { object.removeValue(forKey: "typography") }
    let original = try fixture.write(object)
    let result = await fixture.store.load()
    #expect(result.state == .migrated)
    #expect(!result.snapshot.defaultEnabled)
    #expect(result.snapshot.formatOverrides == [.json: true, FormatID(rawValue: "future.disabled"): false])
    #expect(!result.snapshot.isEnabled(FormatID(rawValue: "future.new")))
    expectNewFieldsDefaulted(result.snapshot)
    if schema < 5 {
        #expect(result.snapshot.syntaxStyle == PreviewSyntaxStyle() && result.snapshot.appearanceProfiles.isEmpty)
    }
    #expect(try Data(contentsOf: fixture.url) == original)
}

@Test(arguments: ["usesColor", "boldRoles", "italicRoles"])
func incompleteSchemaFiveSyntaxStyleStillFailsClosed(field: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeFiveObject()
    var syntax = try #require(object["syntaxStyle"] as? [String: Any])
    syntax.removeValue(forKey: field)
    object["syntaxStyle"] = syntax
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: ["id", "name", "appearance"])
func incompleteSchemaFiveProfileStillFailsClosed(field: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeFiveObject()
    var profiles = try #require(object["appearanceProfiles"] as? [[String: Any]])
    profiles[0].removeValue(forKey: field)
    object["appearanceProfiles"] = profiles
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test func schemaFiveProfileNamesStillValidateAfterMigration() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeFiveObject()
    var profiles = try #require(object["appearanceProfiles"] as? [[String: Any]])
    profiles[0]["name"] = " Leading"
    object["appearanceProfiles"] = profiles
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: behaviorFields)
func missingBehaviorFieldInSchemaSixFailsClosed(field: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeSixObject()
    object.removeValue(forKey: field)
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: ["lightScheme", "darkScheme"])
func missingSchemeFieldInSchemaSixFailsClosed(field: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeSixObject()
    var syntax = try #require(object["syntaxStyle"] as? [String: Any])
    syntax.removeValue(forKey: field)
    object["syntaxStyle"] = syntax
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: [
    ("reloadsOnFileChange", "null"), ("reloadsOnFileChange", #""true""#), ("reloadsOnFileChange", "1"),
    ("showsContentThumbnails", "null"), ("showsContentThumbnails", #""yes""#),
    ("showsHiddenFolderItems", "null"), ("showsHiddenFolderItems", "0"),
    ("folderDepth", "null"), ("folderDepth", #""2""#), ("folderDepth", "1.5"), ("folderDepth", "0"),
    ("folderDepth", "-1"), ("folderDepth", "5"), ("folderDepth", "99"), ("folderDepth", "9223372036854775807")
]) func invalidBehaviorValuesInSchemaSixFailClosed(field: String, rawValue: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeSixObject()
    object[field] = try JSONSerialization.jsonObject(with: Data(rawValue.utf8), options: .fragmentsAllowed)
    _ = try fixture.write(object)
    let result = await fixture.store.load()
    #expect(result == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
    #expect(!result.snapshot.isEnabled(.json))
}

@Test(arguments: [
    ("lightScheme", "nord"), ("lightScheme", "githubDark"), ("lightScheme", "midnight"),
    ("darkScheme", "paper"), ("darkScheme", "githubLight"), ("darkScheme", "solarizedLight"),
    ("lightScheme", "unknownScheme"), ("darkScheme", "Standard"), ("lightScheme", ""), ("darkScheme", "null")
]) func unknownOrMismatchedSchemesInSchemaSixFailClosed(field: String, value: String) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeSixObject()
    var syntax = try #require(object["syntaxStyle"] as? [String: Any])
    syntax[field] = value == "null" ? NSNull() : value
    object["syntaxStyle"] = syntax
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test func profileWithAMismatchedSchemeInSchemaSixFailsClosed() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    var object = schemeSixObject()
    object["appearanceProfiles"] = [[
        "id": fixtureProfileID.uuidString, "name": "Bad",
        "appearance": ["typography": typographyObject(), "theme": "dark",
                       "syntaxStyle": ["usesColor": true, "boldRoles": [], "italicRoles": [],
                                       "lightScheme": "dracula", "darkScheme": "standard"]]
    ]]
    _ = try fixture.write(object)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: .disabledContentFallback, state: .corrupt))
}

@Test(arguments: [0, 5, -1, 99])
func savingAnOutOfRangeFolderDepthIsRejectedAndKeepsTheSavedChoices(depth: Int) async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    let saved = PreviewPreferencesSnapshot(folderDepth: 2)
    try await fixture.store.save(saved)
    await #expect(throws: PreferencesStoreError.invalidSnapshot) {
        try await fixture.store.save(PreviewPreferencesSnapshot(folderDepth: depth))
    }
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: saved, state: .loaded))
}

@Test func savingAMismatchedSchemeIsRejectedAndKeepsTheSavedChoices() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    let saved = PreviewPreferencesSnapshot(syntaxStyle: PreviewSyntaxStyle(lightScheme: .paper, darkScheme: .midnight))
    try await fixture.store.save(saved)
    for style in [PreviewSyntaxStyle(lightScheme: .nord), PreviewSyntaxStyle(darkScheme: .githubLight)] {
        await #expect(throws: PreferencesStoreError.invalidSnapshot) {
            try await fixture.store.save(PreviewPreferencesSnapshot(syntaxStyle: style))
        }
    }
    let profile = PreviewAppearanceProfile(name: "Bad", appearance: PreviewAppearance(
        syntaxStyle: PreviewSyntaxStyle(lightScheme: .dracula)))
    await #expect(throws: PreferencesStoreError.invalidSnapshot) {
        try await fixture.store.save(PreviewPreferencesSnapshot(appearanceProfiles: [profile]))
    }
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: saved, state: .loaded))
}

@Test func everyBehaviorChoicePreservesFileTypeChoicesAndAppearanceAcrossResets() {
    var snapshot = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
        syntaxStyle: PreviewSyntaxStyle(lightScheme: .oneLight, darkScheme: .dracula),
        reloadsOnFileChange: false, showsContentThumbnails: false, folderDepth: 3, showsHiddenFolderItems: true)
    snapshot.resetAppearance()
    #expect(snapshot.syntaxStyle == PreviewSyntaxStyle(), "Reset restores Standard for both appearances")
    #expect(!snapshot.reloadsOnFileChange && !snapshot.showsContentThumbnails && snapshot.folderDepth == 3
            && snapshot.showsHiddenFolderItems, "Appearance reset leaves behavior choices alone")
    snapshot.resetFileTypeChoices()
    #expect(!snapshot.reloadsOnFileChange && snapshot.folderDepth == 3, "File-type reset leaves behavior alone")
    snapshot.setAllEnabled(false)
    #expect(snapshot.showsHiddenFolderItems)
}

@Test func aFullDocumentWithSchemesAndBehaviorFieldsStaysWithinTheBound() async throws {
    let fixture = try SixFixture()
    defer { fixture.remove() }
    let profiles = (0..<PreviewAppearanceProfile.maximumCount).map { index in
        PreviewAppearanceProfile(name: "Profile \(index) " + String(repeating: "é", count: 50), appearance: PreviewAppearance(
            typography: PreviewTypography(fontFamily: String(repeating: "é", count: 64)), theme: .dark,
            syntaxStyle: PreviewSyntaxStyle(boldRoles: Set(PreviewSyntaxRole.allCases),
                italicRoles: Set(PreviewSyntaxRole.allCases), lightScheme: .solarizedLight, darkScheme: .solarizedDark)))
    }
    let allValid = profiles.allSatisfy { $0.isValid }
    #expect(allValid)
    let overrides = Dictionary(uniqueKeysWithValues: (0..<500).map { (FormatID(rawValue: "format.\($0)"), true) })
    let snapshot = PreviewPreferencesSnapshot(formatOverrides: overrides, appearanceProfiles: profiles,
                                              reloadsOnFileChange: false, folderDepth: 4)
    try await fixture.store.save(snapshot)
    #expect(try Data(contentsOf: fixture.url).count <= 65_536)
    #expect(await fixture.store.load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
}
