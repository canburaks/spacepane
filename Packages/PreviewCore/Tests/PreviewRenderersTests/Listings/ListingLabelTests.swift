import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Listing labels")
struct ListingLabelTests {
    private let summary = #"""
    {"archiveFormat":"directory","listedEntries":2,"partial":true,
     "entries":[
       {"path":"modified","type":"package","bytes":null,"modified":"2026-10-05T12:30:00Z","encrypted":true,"items":1500},
       {"path":"depth","type":"file","bytes":1234567}],
     "scope":"nestedFolders","inaccessibleEntries":0,"recursive":false,"depth":2,"hiddenEntries":1234,
     "fileCount":1,"folderCount":0,"listedBytes":1234567,"timeZone":"UTC",
     "largestItems":[{"path":"type","bytes":99999},{"path":"b","bytes":5}]}
    """#

    private func localized(_ locale: Locale, format: FormatID = .folder) throws -> SafeOutlineNode {
        let roots = try #require(SafeStructuredText.json(summary))
        return try #require(SafeSchemaLabels.localize(roots, formatID: format, locale: locale).first)
    }

    private func child(_ node: SafeOutlineNode, _ name: String) throws -> SafeOutlineNode {
        try #require(node.children.first { $0.name == name })
    }

    @Test func everyNewSummaryFieldHasALocalizedLabelAndLocaleAwareCounts() throws {
        let root = try localized(Locale(identifier: "de_DE"))
        func label(_ key: PreviewStrings.Key) -> String { PreviewStrings.text(key) }
        #expect(try child(root, label(.listingHiddenEntries)).value == "1.234")
        #expect(try child(root, label(.listingFileCount)).value == "1")
        #expect(try child(root, label(.listingFolderCount)).value == "0")
        #expect(try child(root, label(.listingListedBytes)).value == "1.234.567")
        #expect(try child(root, label(.listingDepth)).value == "2")
        #expect(try child(root, label(.summaryScope)).value == label(.listingScopeNestedFolders))
        // The time zone is a technical identifier and stays exact.
        #expect(try child(root, label(.listingTimeZone)).value == "UTC")
        let ranking = try child(root, label(.listingLargestFiles))
        #expect(ranking.children.count == 2)
        #expect(ranking.children[0].children.map(\.name) == [label(.summaryPath), label(.summaryBytes)])
        #expect(ranking.children[0].children[1].value == "99.999")
    }

    @Test func entryFieldsAreLabelledButPathsDatesAndWireNamesStayExact() throws {
        let root = try localized(Locale(identifier: "en_US"))
        let entries = try child(root, PreviewStrings.text(.summaryEntries))
        let package = entries.children[0]
        #expect(package.children.map(\.name) == [PreviewStrings.text(.summaryPath), PreviewStrings.text(.summaryType), PreviewStrings.text(.summaryBytes),
                                                 PreviewStrings.text(.listingModified), PreviewStrings.text(.listingEncrypted), PreviewStrings.text(.listingItems)])
        // A file named like a field is a value, never translated.
        #expect(package.children[0].value == "modified")
        #expect(entries.children[1].children[0].value == "depth")
        #expect(package.children[1].value == PreviewStrings.text(.listingKindPackage))
        #expect(package.children[3].value == "2026-10-05T12:30:00Z", "ISO 8601 values are exact, language-neutral facts")
        #expect(package.children[4].value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(package.children[5].value == "1,500")
    }

    @Test func everyListingFormatSharesTheSchemaAndFutureFormatsInheritIt() throws {
        for format in [FormatID.zip, .tar, .gzip, .xip, .folder] {
            let root = try localized(Locale(identifier: "en_US"), format: format)
            #expect(root.children.contains { $0.name == PreviewStrings.text(.listingDepth) })
        }
        let derived = SummaryLabelSet.containers.applying(to: [.midi])
        #expect(derived.fields(["entries", "[]"])?.isSuperset(of: ["path", "type", "bytes", "modified", "encrypted", "items"]) == true)
        #expect(derived.fields(["largestItems", "[]"]) == ["path", "bytes"])
        #expect(derived.fields(["unknown"]) == nil)
    }

    @Test func unlabelledSchemasAreNotTranslated() throws {
        let roots = try #require(SafeStructuredText.json(#"{"depth":3,"entries":[]}"#))
        let untouched = SafeSchemaLabels.localize(roots, formatID: .json, locale: Locale(identifier: "de_DE"))
        #expect(untouched[0].children.map(\.name) == ["depth", "entries"])
    }

    @Test func everyNewKeyKeepsItsPlaceholdersInEveryLanguage() {
        let keys: [PreviewStrings.Key] = [
            .listingModified, .listingModifiedUTC, .listingEncrypted, .listingHiddenEntries, .listingFileCount, .listingFolderCount,
            .listingListedBytes, .listingDepth, .listingTimeZone, .listingItems, .listingLargestFiles, .listingKindPackage,
            .listingScopeNestedFolders, .listingColumnKind, .listingColumnSize, .listingAtLeast, .listingPartialNotice,
            .listingTreeAccessibilityLabel, .listingFilterPlaceholder, .listingFilterLabel, .listingFilterHelp, .listingFilterStatus,
            .listingSortMenu, .listingSortAscending, .listingSortDescending, .listingSortAnnouncement
        ]
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        func placeholders(_ text: String) -> [String] {
            let pattern = try? NSRegularExpression(pattern: #"%(\d+\$)?(lld|@)"#)
            let range = NSRange(text.startIndex..., in: text)
            return (pattern?.matches(in: text, range: range) ?? []).compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
        }
        for key in keys {
            let english = PreviewStrings.text(key, languagePreferences: ["en"])
            for language in languages {
                let value = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!value.isEmpty && value != key.rawValue, Comment(rawValue: "\(key.rawValue) \(language)"))
                #expect(placeholders(value) == placeholders(english), Comment(rawValue: "\(key.rawValue) \(language)"))
                if !["id", "ku-Latn", "ha"].contains(language), key != .listingKindPackage, key != .listingFilterPlaceholder {
                    // Draft translations must not be English copies (a few short words coincide in some languages).
                    #expect(language == "en" || value != english || english.count < 6, Comment(rawValue: "\(key.rawValue) \(language)"))
                }
            }
        }
        #expect(PreviewStrings.format(.listingAtLeast, arguments: ["4 KB"], locale: Locale(identifier: "en_US")) == "At least 4 KB")
        #expect(PreviewStrings.format(.listingFilterStatus, arguments: [Int64(3), Int64(10)], locale: Locale(identifier: "en_US")) == "3 of 10 rows")
        #expect(PreviewStrings.format(.listingSortAnnouncement, arguments: ["Size", "Ascending"], locale: Locale(identifier: "en_US")) == "Sorted by Size, Ascending")
    }
}
