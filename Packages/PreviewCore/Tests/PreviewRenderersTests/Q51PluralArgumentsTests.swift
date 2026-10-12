import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Q51 plural row limits")
struct Q51PluralArgumentsTests {
    @Test func shownRowsSelectThePluralEvenWhenTotalIsMany() {
        let locale = Locale(identifier: "en_US")
        #expect(PreviewStrings.count(.previewTableShownRowsOfTotal, 1,
            additionalArguments: ["98,765"], locale: locale, languagePreferences: ["en"])
            == "Showing the first 1 row of 98,765.")
        #expect(PreviewStrings.count(.previewTableShownRowsOfTotal, 2,
            additionalArguments: ["98,765"], locale: locale, languagePreferences: ["en"])
            == "Showing the first 2 rows of 98,765.")
    }

    @Test func everyResourceSetKeepsBothCountsAndNoFormatDirectives() {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn",
                         "ru", "id", "bn", "ha", "pt", "es"]
        for language in languages {
            let locale = Locale(identifier: language)
            for shown in [0, 1, 2, 5, 21, 12_345] {
                let total = 98_765.formatted(.number.locale(locale))
                let number = shown.formatted(.number.locale(locale))
                let text = PreviewStrings.count(.previewTableShownRowsOfTotal, shown,
                    additionalArguments: [total], locale: locale, languagePreferences: [language])
                #expect(text.contains(number) && text.contains(total), "\(language): \(text)")
                #expect(!text.contains("%"), "\(language): \(text)")
                for key in [PreviewStrings.Key.previewTableShownRows, .previewProfileShownRows] {
                    let single = PreviewStrings.count(key, shown, locale: locale, languagePreferences: [language])
                    #expect(single.contains(number) && !single.contains("%"), "\(language): \(single)")
                }
            }
        }
    }

    @Test func languageAndNumberRegionRemainIndependent() {
        let locale = Locale(identifier: "de_DE")
        #expect(PreviewStrings.count(.previewTableShownRowsOfTotal, 1_204,
            additionalArguments: [98_765.formatted(.number.locale(locale))], locale: locale,
            languagePreferences: ["en"]) == "Showing the first 1.204 rows of 98.765.")
    }
}
