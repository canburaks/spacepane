import Foundation
import Testing
import PreviewContracts
import PreviewPreferences

private func schemeAppearance(light: PreviewColorSchemeID = .githubLight,
                              dark: PreviewColorSchemeID = .dracula) -> PreviewAppearance {
    PreviewAppearance(typography: PreviewTypography(fontSize: 21, wrapsLines: false, weight: .medium,
        tabWidth: 8, showsLineNumbers: true), theme: .system,
        syntaxStyle: PreviewSyntaxStyle(usesColor: true, boldRoles: [.key], italicRoles: [.comment],
                                        lightScheme: light, darkScheme: dark))
}

private func object(_ appearance: PreviewAppearance) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: AppearanceThemeCodec.encode(appearance)) as? [String: Any])
}

private func data(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root) }

// MARK: Scheme identifiers

@Test func standardIsAvailableForBothAppearancesAndEverySchemeForExactlyOne() {
    #expect(PreviewColorSchemeID.standard.polarity == nil)
    #expect(PreviewColorSchemeID.standard.isAvailable(for: .light) && PreviewColorSchemeID.standard.isAvailable(for: .dark))
    for scheme in PreviewColorSchemeID.allCases where scheme != .standard {
        #expect(scheme.polarity != nil)
        #expect(scheme.isAvailable(for: .light) == (scheme.polarity == .light))
        #expect(scheme.isAvailable(for: .dark) == (scheme.polarity == .dark))
        #expect(scheme.isAvailable(for: .light) != scheme.isAvailable(for: .dark))
    }
}

@Test func pickersOfferStandardFirstThenTheMatchingSchemesOnly() {
    #expect(PreviewColorSchemeID.choices(for: .light) == [.standard, .githubLight, .solarizedLight, .oneLight, .paper])
    #expect(PreviewColorSchemeID.choices(for: .dark) == [.standard, .githubDark, .solarizedDark, .oneDark, .nord, .dracula, .midnight, .aurora])
    #expect(PreviewColorSchemeID.allCases.count == 12)
    #expect(Set(PreviewColorSchemeID.choices(for: .light) + PreviewColorSchemeID.choices(for: .dark))
            == Set(PreviewColorSchemeID.allCases))
}

@Test func schemeRawValuesAreStablePersistedIdentifiers() {
    let expected: [PreviewColorSchemeID: String] = [
        .standard: "standard", .githubLight: "githubLight", .githubDark: "githubDark",
        .solarizedLight: "solarizedLight", .solarizedDark: "solarizedDark", .oneLight: "oneLight",
        .oneDark: "oneDark", .nord: "nord", .dracula: "dracula", .paper: "paper", .midnight: "midnight",
        .aurora: "aurora"
    ]
    #expect(expected.count == PreviewColorSchemeID.allCases.count)
    for (scheme, raw) in expected { #expect(scheme.rawValue == raw) }
}

@Test func syntaxStyleValidityFollowsPolarityAndStandardIsTheDefault() {
    let standard = PreviewSyntaxStyle()
    #expect(standard.lightScheme == .standard && standard.darkScheme == .standard && standard.isValid)
    #expect(PreviewSyntaxStyle(lightScheme: .paper, darkScheme: .midnight).isValid)
    #expect(!PreviewSyntaxStyle(lightScheme: .nord).isValid)
    #expect(!PreviewSyntaxStyle(darkScheme: .oneLight).isValid)
    #expect(!PreviewAppearance(syntaxStyle: PreviewSyntaxStyle(darkScheme: .githubLight)).isValid)
    #expect(PreviewAppearance(syntaxStyle: PreviewSyntaxStyle(lightScheme: .solarizedLight, darkScheme: .solarizedDark)).isValid)
}

@Test func syntaxStyleCodableRequiresEverySchemeKey() throws {
    let style = PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.comment],
                                   lightScheme: .oneLight, darkScheme: .nord)
    let encoded = try JSONEncoder().encode(style)
    #expect(try JSONDecoder().decode(PreviewSyntaxStyle.self, from: encoded) == style)
    for missing in ["lightScheme", "darkScheme", "usesColor", "boldRoles", "italicRoles"] {
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root.removeValue(forKey: missing)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PreviewSyntaxStyle.self, from: JSONSerialization.data(withJSONObject: root))
        }
    }
}

// MARK: Theme exchange, version 2

@Test func themeExchangeCarriesBothSchemesInVersionTwo() throws {
    #expect(AppearanceThemeCodec.schemaVersion == 2)
    let appearance = schemeAppearance()
    let encoded = try AppearanceThemeCodec.encode(appearance)
    #expect(try AppearanceThemeCodec.decode(encoded) == appearance)
    let root = try object(appearance)
    #expect(root["schemaVersion"] as? Int == 2)
    let syntax = try #require((root["appearance"] as? [String: Any])?["syntaxStyle"] as? [String: Any])
    #expect(Set(syntax.keys) == ["usesColor", "boldRoles", "italicRoles", "lightScheme", "darkScheme"])
    #expect(syntax["lightScheme"] as? String == "githubLight" && syntax["darkScheme"] as? String == "dracula")
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(!text.contains("#") && !text.contains("0x"), "A theme carries scheme identifiers, never color values")
}

@Test(arguments: PreviewColorSchemeID.allCases)
func everySchemeSurvivesAThemeRoundTripInItsOwnAppearance(scheme: PreviewColorSchemeID) throws {
    let appearance = scheme.isAvailable(for: .light) ? schemeAppearance(light: scheme, dark: .standard)
                                                     : schemeAppearance(light: .standard, dark: scheme)
    #expect(try AppearanceThemeCodec.decode(AppearanceThemeCodec.encode(appearance)) == appearance)
}

@Test func versionOneThemesStillImportAndUseTheStandardSchemes() throws {
    var root = try object(schemeAppearance())
    root["schemaVersion"] = 1
    var appearance = try #require(root["appearance"] as? [String: Any])
    var syntax = try #require(appearance["syntaxStyle"] as? [String: Any])
    syntax.removeValue(forKey: "lightScheme")
    syntax.removeValue(forKey: "darkScheme")
    appearance["syntaxStyle"] = syntax
    root["appearance"] = appearance
    let imported = try AppearanceThemeCodec.decode(data(root))
    #expect(imported.syntaxStyle == PreviewSyntaxStyle(usesColor: true, boldRoles: [.key], italicRoles: [.comment]))
    #expect(imported.syntaxStyle.lightScheme == .standard && imported.syntaxStyle.darkScheme == .standard)
    #expect(imported.typography == schemeAppearance().typography && imported.theme == .system)
}

@Test func versionMustMatchTheShapeItDeclares() throws {
    // A version 1 file may not carry scheme fields, and a version 2 file may not omit them.
    var withSchemes = try object(schemeAppearance())
    withSchemes["schemaVersion"] = 1
    #expect(throws: AppearanceThemeError.invalidDocument) { try AppearanceThemeCodec.decode(data(withSchemes)) }
    for missing in ["lightScheme", "darkScheme"] {
        var root = try object(schemeAppearance())
        var appearance = try #require(root["appearance"] as? [String: Any])
        var syntax = try #require(appearance["syntaxStyle"] as? [String: Any])
        syntax.removeValue(forKey: missing)
        appearance["syntaxStyle"] = syntax
        root["appearance"] = appearance
        #expect(throws: AppearanceThemeError.invalidDocument) { try AppearanceThemeCodec.decode(data(root)) }
    }
    for version in [0, 3, 99, -1] {
        var root = try object(schemeAppearance())
        root["schemaVersion"] = version
        #expect(throws: AppearanceThemeError.unsupportedVersion) { try AppearanceThemeCodec.decode(data(root)) }
    }
}

@Test(arguments: [
    ("lightScheme", "nord"), ("lightScheme", "githubDark"), ("darkScheme", "paper"), ("darkScheme", "oneLight"),
    ("lightScheme", "javascript:alert(1)"), ("darkScheme", "#112233"), ("lightScheme", ""), ("darkScheme", "Dracula")
]) func unknownAndMismatchedSchemesAreRejectedOnImport(field: String, value: String) throws {
    var root = try object(schemeAppearance())
    var appearance = try #require(root["appearance"] as? [String: Any])
    var syntax = try #require(appearance["syntaxStyle"] as? [String: Any])
    syntax[field] = value
    appearance["syntaxStyle"] = syntax
    root["appearance"] = appearance
    #expect(throws: AppearanceThemeError.invalidDocument) { try AppearanceThemeCodec.decode(data(root)) }
}

@Test func extraSyntaxFieldsStillRejectedAndExportOfAnInvalidSchemeFails() throws {
    var root = try object(schemeAppearance())
    var appearance = try #require(root["appearance"] as? [String: Any])
    var syntax = try #require(appearance["syntaxStyle"] as? [String: Any])
    syntax["customColors"] = ["key": "#FF0000"]
    appearance["syntaxStyle"] = syntax
    root["appearance"] = appearance
    #expect(throws: AppearanceThemeError.invalidDocument) { try AppearanceThemeCodec.decode(data(root)) }
    #expect(throws: AppearanceThemeError.invalidDocument) {
        try AppearanceThemeCodec.encode(schemeAppearance(light: .nord, dark: .dracula))
    }
}

@Test func profilesAndThemeFilesKeepSchemesWhileFilePolicyStaysOut() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("theme.json")
    try AppearanceThemeCodec.encode(schemeAppearance()).write(to: url)
    #expect(try await AppearanceThemeReader().read(at: url) == schemeAppearance())
    var snapshot = PreviewPreferencesSnapshot(defaultEnabled: false, formatOverrides: [.json: true],
                                              reloadsOnFileChange: false, folderDepth: 3)
    snapshot.appearance = try await AppearanceThemeReader().read(at: url)
    #expect(snapshot.syntaxStyle.lightScheme == .githubLight && snapshot.syntaxStyle.darkScheme == .dracula)
    #expect(!snapshot.defaultEnabled && snapshot.formatOverrides == [.json: true],
            "Applying a theme never changes file-type choices")
    #expect(!snapshot.reloadsOnFileChange && snapshot.folderDepth == 3, "...or behavior choices")
}
