import AppKit
import Foundation
import Testing
@testable import PreviewContracts
@testable import PreviewRenderers

@Suite("Archive summaries and labels")
struct ArchiveRendererTests {
    private let rarSummary = """
    {"archiveFormat":"RAR5","listedEntries":1234,"partial":false,"entries":[{"path":"solid/locked.txt","type":"file","bytes":2048,\
    "modified":"2026-01-01T00:00:00Z","encrypted":true},{"path":"dir","type":"directory","bytes":0}],\
    "solid":true,"multiVolume":true,"volumeNumber":1500,"locked":false,"recoveryRecord":true}
    """
    private let archiveIDs: [FormatID] = [.rar, .sevenZip, .bzip2, .xz]

    @Test func everyArchiveFormatOwnsExactlyOneLabelSet() {
        for id in archiveIDs {
            #expect(SafeSchemaLabels.formats.contains(id))
            #expect(SafeSchemaLabels.labelSets.filter { $0.formats.contains(id) }.count == 1)
        }
        // The shared listing set is unchanged for the formats that existed before.
        for id in [FormatID.zip, .tar, .gzip, .xip, .folder] { #expect(SafeSchemaLabels.labelSet(for: id)?.formats.contains(.rar) == false) }
    }

    @Test func summaryFieldsAreTranslatedWhileUserValuesStayExact() throws {
        let roots = try #require(SafeStructuredText.json(rarSummary))
        let locale = Locale(identifier: "de_DE")
        let localized = SafeSchemaLabels.localize(roots, formatID: .rar, locale: locale)
        let root = try #require(localized.first)
        func child(_ key: PreviewStrings.Key) -> SafeOutlineNode? { root.children.first { $0.name == PreviewStrings.text(key) } }
        #expect(child(.summaryArchiveFormat)?.value == "RAR5")
        #expect(child(.summaryListedEntries)?.value == "1.234")
        #expect(child(.archiveSolid)?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(child(.archiveLocked)?.value == PreviewStrings.text(.summaryBooleanFalse))
        #expect(child(.archiveRecoveryRecord)?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(child(.archiveMultiVolume)?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(child(.archiveVolumeNumber)?.value == "1.500")
        let entries = try #require(child(.summaryEntries))
        let first = try #require(entries.children.first)
        let second = try #require(entries.children.last)
        func field(_ node: SafeOutlineNode, _ key: PreviewStrings.Key) -> String? { node.children.first { $0.name == PreviewStrings.text(key) }?.value }
        #expect(field(first, .summaryPath) == "solid/locked.txt")
        #expect(field(first, .summaryType) == PreviewStrings.text(.summaryKindFile))
        #expect(field(first, .summaryBytes) == "2.048")
        #expect(field(first, .archiveEntryModified) == "2026-01-01T00:00:00Z")
        #expect(field(first, .archiveEntryEncrypted) == PreviewStrings.text(.summaryBooleanTrue))
        #expect(field(second, .summaryType) == PreviewStrings.text(.summaryKindDirectory))
        #expect(field(second, .archiveEntryEncrypted) == nil)
    }

    @Test func fieldNamesInsideEntriesOnlyTranslateWhenTheyAreSchemaFields() throws {
        // A file whose entry list contains a key named like a schema field is still just a path value.
        let source = #"{"entries":[{"path":"solid","type":"file","bytes":1}],"solid":false}"#
        let roots = try #require(SafeStructuredText.json(source))
        let localized = try #require(SafeSchemaLabels.localize(roots, formatID: .sevenZip, locale: Locale(identifier: "en_US")).first)
        let entry = try #require(localized.children.first { $0.name == PreviewStrings.text(.summaryEntries) }?.children.first)
        #expect(entry.children.first { $0.name == PreviewStrings.text(.summaryPath) }?.value == "solid")
    }

    @Test func archivePresentationsOpenInTheFilesTableWithSummaryAvailable() throws {
        let presentation = TextPresentation(formatID: .sevenZip, text: rarSummary, lineCount: 1, byteCount: 400,
                                            encoding: .utf8, redactionCount: 0, syntax: .json)
        let modes = SafePreviewModes(presentation, locale: Locale(identifier: "en_US"))
        #expect(modes.summary != nil)
        #expect(modes.outline == nil)
        #expect(modes.available.contains(.summary) && modes.available.contains(.source))
        // Every listing-shaped summary opens in the shared Files table (decision 014).
        #expect(modes.available.contains(.files) && modes.available.contains(.tree))
        #expect(modes.initialMode(for: .sevenZip) == .files)
        #expect(!modes.hasStructureFallback)
        // Plain-text payloads of bzip2/xz keep the ordinary text modes.
        let text = TextPresentation(formatID: .bzip2, text: "hello\n", lineCount: 1, byteCount: 6, encoding: .utf8, redactionCount: 0)
        #expect(SafePreviewModes(text, locale: Locale(identifier: "en_US")).initialMode(for: .bzip2) == .source)
    }

    @Test func everyNewStringIsTranslatedInEveryOtherLanguage() {
        let keys: [PreviewStrings.Key] = [.archiveSolid, .archiveMultiVolume, .archiveVolumeNumber, .archiveLocked,
                                           .archiveRecoveryRecord, .archiveEntryModified, .archiveEntryEncrypted]
        let languages = ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for key in keys {
            let english = PreviewStrings.text(key, languagePreferences: ["en"])
            #expect(!english.isEmpty)
            for language in languages {
                let value = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!value.isEmpty && value != key.rawValue)
                #expect(value != english, "\(key.rawValue) in \(language)")
            }
        }
    }

    @Test func formatNamesAndDescriptionsResolveInEveryLanguage() {
        let ids = ["rar", "7z", "bzip2", "xz"]
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        let missing = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        for id in ids {
            let english = PreviewStrings.text(catalogKey: "format.archive.\(id).description", languagePreferences: ["en"])
            for language in languages {
                let name = PreviewStrings.text(catalogKey: "format.archive.\(id).name", languagePreferences: [language])
                let description = PreviewStrings.text(catalogKey: "format.archive.\(id).description", languagePreferences: [language])
                #expect(!name.isEmpty && name != missing)
                #expect(description != missing && !description.isEmpty)
                if language != "en" { #expect(description != english, "\(id) description in \(language)") }
            }
        }
    }
}
