import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q150 listing name findings and localized risks")
struct Q150ListingNameFindingTests {
    @Test func hiddenNameFindingUsesPluralWordingAndLocaleDigitsWithoutADetail() throws {
        let kind = try #require(PreviewFindingKind(rawValue: "listing.hiddenCharacters"))
        let one = PreviewFinding(kind: kind, count: 1)
        #expect(FindingText.message(for: one, locale: Locale(identifier: "en_US")) == "1 listed name contains hidden characters.")
        #expect(FindingText.detail(for: one, locale: Locale(identifier: "en_US")) == nil)
        for identifier in ["en_US", "de_DE", "ar_EG", "hi_IN"] {
            let locale = Locale(identifier: identifier), finding = PreviewFinding(kind: kind, count: 1_234)
            #expect(FindingText.message(for: finding, locale: locale).contains(1_234.formatted(.number.locale(locale))))
        }
    }

    @Test func folderAndArchiveRisksLocalizeWithoutChangingExactNames() throws {
        let path = "name\u{200B}\u{E0070}\u{E0077}.txt"
        let data = try JSONSerialization.data(withJSONObject: ["entries": [["path": path, "type": "file", "bytes": 1,
                                                       "risks": ["hiddenCharacters", "directionalName"]]]])
        let roots = try #require(SafeStructuredText.json(String(decoding: data, as: UTF8.self)))
        for formatID in [FormatID.folder, .zip, .tar, .rar] {
            let root = try #require(SafeSchemaLabels.localize(roots, formatID: formatID, locale: Locale(identifier: "en_US")).first)
            let entry = try #require(root.children.first { $0.name == PreviewStrings.text(.summaryEntries) }?.children.first)
            #expect(entry.isIssue)
            #expect(entry.children.first { $0.name == PreviewStrings.text(.summaryPath) }?.value.utf8.elementsEqual(path.utf8) == true)
            let risks = try #require(entry.children.first { $0.name == PreviewStrings.text(.summaryRisks) })
            #expect(risks.children.map(\.value) == [PreviewStrings.text(.listingRiskHiddenCharacters),
                                                      PreviewStrings.text(.archiveRiskDirectionalName)])
        }
    }

    @Test func bothNewResourcesResolveInAllFourteenLanguagesWithPluralCounts() {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for language in languages {
            let locale = Locale(identifier: language)
            let label = PreviewStrings.text(.listingRiskHiddenCharacters, languagePreferences: [language])
            #expect(!label.isEmpty && label != "listing.risk.hiddenCharacters")
            for count in [1, 2, 5, 1_234] {
                let message = PreviewStrings.count(.findingListingHiddenCharacters, count, locale: locale, languagePreferences: [language])
                #expect(!message.isEmpty && !message.contains("finding.listing.hiddenCharacters"))
                #expect(message.contains(count.formatted(.number.locale(locale))))
            }
        }
    }
}
