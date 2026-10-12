import Foundation
import Testing
@testable import PreviewRenderers

/// Plural selection belongs to the generated `.stringsdict` and Foundation's CLDR rules, so these tests need
/// the SwiftPM-processed resources; the Python tooling checks cannot stand in for them. Russian assertions
/// compare forms rather than wording, so a translation review does not break them.
@Suite("Plural localization")
struct PluralStringsTests {
    private static func lines(_ value: Int, locale identifier: String, language: String) -> String {
        PreviewStrings.count(.previewCountLines, value, locale: Locale(identifier: identifier), languagePreferences: [language])
    }

    /// The text with the locale-formatted count replaced, leaving only the plural form.
    private static func form(_ value: Int, locale identifier: String, language: String) -> String {
        let number = value.formatted(.number.locale(Locale(identifier: identifier)))
        return lines(value, locale: identifier, language: language).replacingOccurrences(of: number, with: "#")
    }

    @Test func englishSelectsTheOneAndOtherForms() {
        let locale = Locale(identifier: "en_US")
        #expect(PreviewStrings.count(.previewCountLines, 1, locale: locale, languagePreferences: ["en"]) == "1 line")
        #expect(PreviewStrings.count(.previewCountLines, 2, locale: locale, languagePreferences: ["en"]) == "2 lines")
        #expect(PreviewStrings.count(.previewCountLines, 0, locale: locale, languagePreferences: ["en"]) == "0 lines")
    }

    @Test func russianSelectsTheOneFewAndManyForms() {
        let one = Self.form(1, locale: "ru_RU", language: "ru")
        let few = Self.form(2, locale: "ru_RU", language: "ru")
        let many = Self.form(5, locale: "ru_RU", language: "ru")
        #expect(Set([one, few, many]).count == 3, "one, few and many are three different forms")
        #expect(Self.form(21, locale: "ru_RU", language: "ru") == one, "21 takes the form of 1")
        #expect(Self.form(22, locale: "ru_RU", language: "ru") == few, "22 takes the form of 2")
        #expect(Self.form(11, locale: "ru_RU", language: "ru") == many, "11 is many, not one")
        #expect(Self.form(25, locale: "ru_RU", language: "ru") == many, "25 takes the form of 5")
    }

    @Test func theCountFollowsTheLocaleGroupingAndDigits() {
        #expect(Self.lines(1_204, locale: "en_US", language: "en").contains("1,204"))
        #expect(Self.lines(1_204, locale: "de_DE", language: "de").contains("1.204"))
        // Bengali prints whatever digits Foundation chooses for the locale (CLDR's default numbering for `bn`
        // is Latin; a host may switch it to Bengali digits), and never a bare `%lld` or format directive.
        let locale = Locale(identifier: "bn_BD")
        let bengali = Self.lines(1_204, locale: "bn_BD", language: "bn")
        #expect(bengali.contains(1_204.formatted(.number.locale(locale))), "\(bengali)")
        #expect(!bengali.contains("%"), "\(bengali)")
    }

    @Test func everyLanguagePrintsTheFormattedCountWithoutLeakingTheFormat() {
        for language in RendererResources.bundle.localizations {
            for value in [0, 1, 2, 5, 21, 1_204] {
                let text = Self.lines(value, locale: language, language: language)
                let number = value.formatted(.number.locale(Locale(identifier: language)))
                #expect(text.contains(number), "\(language) \(value): \(text)")
                #expect(!text.contains("%"), "\(language) \(value): \(text)")
            }
        }
    }
}
