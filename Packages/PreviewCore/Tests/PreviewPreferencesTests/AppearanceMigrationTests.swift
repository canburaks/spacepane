import Foundation
import Testing
import PreviewContracts
import PreviewPreferences

@Test func schemaFourMigrationPreservesCompleteAppearanceAndFileTypeChoices() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preferences.json")
    let original = Data(#"{"schemaVersion":4,"defaultEnabled":false,"formatOverrides":{"data.json":true,"future.disabled":false},"theme":"dark","typography":{"fontSize":18,"wrapsLines":false,"fontFamily":"Menlo","weight":"semibold","italic":true,"lineSpacing":3,"characterSpacing":0.5,"ligatures":false,"tabWidth":8,"showsLineNumbers":true}}"#.utf8)
    try original.write(to: url)
    let store = PreferenceStore(url: url)
    let loaded = await store.load()
    #expect(PreferenceStore.schemaVersion == 6)
    #expect(loaded.state == .migrated)
    #expect(loaded.snapshot.defaultEnabled == false)
    #expect(loaded.snapshot.formatOverrides == [.json: true, FormatID(rawValue: "future.disabled"): false])
    #expect(loaded.snapshot.theme == .dark)
    #expect(loaded.snapshot.typography == PreviewTypography(fontSize: 18, wrapsLines: false,
        fontFamily: "Menlo", weight: .semibold, italic: true, lineSpacing: 3, characterSpacing: 0.5,
        ligatures: false, tabWidth: 8, showsLineNumbers: true))
    #expect(try Data(contentsOf: url) == original)
}
