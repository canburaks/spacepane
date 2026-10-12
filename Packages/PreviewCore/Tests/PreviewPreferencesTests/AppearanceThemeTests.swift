import Foundation
import Darwin
import Testing
import PreviewContracts
import PreviewPreferences

private func themeAppearance() -> PreviewAppearance {
    PreviewAppearance(typography: PreviewTypography(fontSize: 26, wrapsLines: false, fontFamily: "Missing Fixture Family",
        weight: .medium, italic: true, lineSpacing: 5, characterSpacing: 1, ligatures: false, tabWidth: 8,
        showsLineNumbers: true), theme: .highContrast,
        syntaxStyle: PreviewSyntaxStyle(usesColor: false, boldRoles: [.key, .heading], italicRoles: [.comment]))
}

@Test func appearanceExchangeRoundTripsAllFieldsAndExcludesFilePolicyAndContent() throws {
    let data = try AppearanceThemeCodec.encode(themeAppearance())
    #expect(try AppearanceThemeCodec.decode(data) == themeAppearance())
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(root.keys) == ["schemaVersion", "appearance"])
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("formatOverrides"))
    #expect(!text.contains("defaultEnabled"))
    #expect(!text.contains("text"))
}

@Test(arguments: ["schemaVersion", "appearance", "theme", "typography", "syntaxStyle", "fontFamily", "showsLineNumbers", "usesColor", "boldRoles", "italicRoles"])
func incompleteThemeImportsFailWithoutChangingAppearance(field: String) throws {
    var root = try #require(JSONSerialization.jsonObject(with: AppearanceThemeCodec.encode(themeAppearance())) as? [String: Any])
    if root[field] != nil { root.removeValue(forKey: field) }
    else {
        var appearance = try #require(root["appearance"] as? [String: Any])
        if appearance[field] != nil { appearance.removeValue(forKey: field) }
        else {
            let section = ["usesColor", "boldRoles", "italicRoles"].contains(field) ? "syntaxStyle" : "typography"
            var nested = try #require(appearance[section] as? [String: Any])
            nested.removeValue(forKey: field)
            appearance[section] = nested
        }
        root["appearance"] = appearance
    }
    #expect(throws: AppearanceThemeError.invalidDocument) {
        try AppearanceThemeCodec.decode(JSONSerialization.data(withJSONObject: root))
    }
}

@Test func themeImportRejectsUnknownExecutableAndPolicyFieldsAndInvalidValues() throws {
    let data = try AppearanceThemeCodec.encode(themeAppearance())
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for field in ["script", "remoteURL", "defaultEnabled", "formatOverrides"] {
        var modified = root
        modified[field] = "inert-fixture"
        #expect(throws: AppearanceThemeError.invalidDocument) {
            try AppearanceThemeCodec.decode(JSONSerialization.data(withJSONObject: modified))
        }
    }
    var unsupported = root
    unsupported["schemaVersion"] = 99
    #expect(throws: AppearanceThemeError.unsupportedVersion) {
        try AppearanceThemeCodec.decode(JSONSerialization.data(withJSONObject: unsupported))
    }
    var appearance = try #require(root["appearance"] as? [String: Any])
    var syntax = try #require(appearance["syntaxStyle"] as? [String: Any])
    syntax["boldRoles"] = ["downloadedScript"]
    appearance["syntaxStyle"] = syntax
    var invalid = root
    invalid["appearance"] = appearance
    #expect(throws: AppearanceThemeError.invalidDocument) {
        try AppearanceThemeCodec.decode(JSONSerialization.data(withJSONObject: invalid))
    }
    #expect(throws: AppearanceThemeError.tooLarge) {
        try AppearanceThemeCodec.decode(Data(repeating: 32, count: AppearanceThemeCodec.maximumDocumentBytes + 1))
    }
    #expect(throws: AppearanceThemeError.invalidDocument) { try AppearanceThemeCodec.decode(Data("broken".utf8)) }
    #expect(throws: AppearanceThemeError.invalidDocument) {
        try AppearanceThemeCodec.encode(PreviewAppearance(typography: PreviewTypography(fontSize: .infinity)))
    }
}

@Test func profilePersistenceResetAndApplicationPreserveFilePolicy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = PreviewAppearanceProfile(name: "Fixture 🌍", appearance: themeAppearance())
    var snapshot = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
        appearanceProfiles: [profile])
    snapshot.appearance = profile.appearance
    #expect(!snapshot.defaultEnabled && snapshot.formatOverrides == [.json: true])
    let store = PreferenceStore(url: directory.appendingPathComponent("preferences.json"))
    try await store.save(snapshot)
    #expect(await store.load() == PreferencesLoadResult(snapshot: snapshot, state: .loaded))
    snapshot.resetAppearance()
    #expect(snapshot.appearance == PreviewAppearance())
    #expect(snapshot.appearanceProfiles == [profile])
    #expect(!snapshot.defaultEnabled && snapshot.formatOverrides == [.json: true])
    snapshot.resetFileTypeChoices()
    #expect(snapshot.appearanceProfiles == [profile])
}

@Test(arguments: ["", " ", " Leading", "Trailing ", "line\nname", "nul\u{0000}", "direction\u{202E}", String(repeating: "é", count: 65)])
func unsafeProfileNamesAreRejected(name: String) {
    #expect(!PreviewAppearanceProfile(name: name, appearance: themeAppearance()).isValid)
}

@Test func invalidAndDuplicateProfilesCannotReplaceExistingChoices() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PreferenceStore(url: directory.appendingPathComponent("preferences.json"))
    try await store.save(.disabledContentFallback)
    let profile = PreviewAppearanceProfile(name: "Safe", appearance: themeAppearance())
    for profiles in [[profile, profile], Array(repeating: profile, count: 33),
                     [PreviewAppearanceProfile(name: "", appearance: themeAppearance())]] {
        await #expect(throws: PreferencesStoreError.invalidSnapshot) {
            try await store.save(PreviewPreferencesSnapshot(appearanceProfiles: profiles))
        }
        #expect(await store.load().snapshot == .disabledContentFallback)
    }
}

@Test func themeFileReadIsBoundedReadOnlyAndRejectsSpecialFilesAndSymlinks() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("theme.json")
    let original = try AppearanceThemeCodec.encode(themeAppearance())
    try original.write(to: url)
    let reader = AppearanceThemeReader()
    #expect(try await reader.read(at: url) == themeAppearance())
    #expect(try Data(contentsOf: url) == original)
    let link = directory.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    await #expect(throws: AppearanceThemeError.cannotRead) { try await reader.read(at: link) }
    let fifo = directory.appendingPathComponent("fifo.json")
    #expect(fifo.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) } == 0)
    await #expect(throws: AppearanceThemeError.cannotRead) { try await reader.read(at: fifo) }
    try Data(repeating: 32, count: AppearanceThemeCodec.maximumDocumentBytes + 1).write(to: url)
    await #expect(throws: AppearanceThemeError.tooLarge) { try await reader.read(at: url) }
}
