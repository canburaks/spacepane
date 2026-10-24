import Foundation
import Testing
@testable import PreviewRenderers

/// Digits stay ASCII and ungrouped, so the checks below look for the numbers themselves.
private let spokenLocale = Locale(identifier: "en_US_POSIX")

/// Every language the renderer bundle ships, spelled as the bundle installs it.
private func installedLanguages() -> [String] { RendererResources.bundle.localizations }

/// The existing strings that the announcement call sites speak through `PreviewAnnouncer`. A translation that dropped
/// an argument or left a format directive would speak an incomplete or broken result, so each one is checked in every
/// installed language, with explicit arguments and an explicit locale.
@Suite("Spoken results stay complete in every shipped language")
struct A11yL10nSpokenResultsTests {
    @Test func theCheckedLanguagesAreTheShippedSet() {
        #expect(installedLanguages().count >= 14, "A missing resource bundle must not make the loops below pass for nothing")
    }

    @Test func theSortResultKeepsTheColumnTitleAndTheDirectionInEveryLanguage() {
        // A column title is shown, already concealed user data: mixed scripts must survive unchanged.
        let title = "Gr\u{F6}\u{DF}e \u{627}\u{644}\u{627}\u{633}\u{645}"
        for language in installedLanguages() {
            for key in [PreviewStrings.Key.listingSortAscending, .listingSortDescending] {
                let direction = PreviewStrings.text(key, languagePreferences: [language])
                let spoken = PreviewStrings.format(.listingSortAnnouncement, arguments: [title, direction],
                                                   locale: spokenLocale, languagePreferences: [language])
                #expect(spoken.contains(title), "\(language) \(key.rawValue) lost the column title: \(spoken)")
                #expect(spoken.contains(direction), "\(language) \(key.rawValue) lost the direction: \(spoken)")
                #expect(!spoken.contains("%"), "\(language) \(key.rawValue) left a directive: \(spoken)")
            }
        }
    }

    @Test func theRowLineAndMatchResultsKeepEveryNumberInEveryLanguage() {
        for language in installedLanguages() {
            let rows = PreviewStrings.format(.listingFilterStatus, arguments: [Int64(37), Int64(1204)],
                                             locale: spokenLocale, languagePreferences: [language])
            #expect(rows.contains("37") && rows.contains("1204") && !rows.contains("%"), "\(language) rows: \(rows)")
            let jump = PreviewStrings.format(.interactionGoToLineJumped, arguments: [Int64(15), Int64(1204)],
                                             locale: spokenLocale, languagePreferences: [language])
            #expect(jump.contains("15") && jump.contains("1204") && !jump.contains("%"), "\(language) jump: \(jump)")
            let matches = PreviewStrings.format(.interactionFilterMatches, arguments: [Int64(58)],
                                                locale: spokenLocale, languagePreferences: [language])
            #expect(matches.contains("58") && !matches.contains("%"), "\(language) matches: \(matches)")
        }
    }

    @Test func theZoomResultKeepsTheFormattedLevelInEveryLanguage() {
        // The call site passes the already formatted percentage, so the argument itself carries a percent sign.
        let formattedLevel = "125%"
        for language in installedLanguages() {
            let spoken = PreviewStrings.format(.interactionZoomStatus, arguments: [formattedLevel],
                                               locale: spokenLocale, languagePreferences: [language])
            #expect(spoken.contains(formattedLevel) && !spoken.contains("%@"), "\(language) zoom: \(spoken)")
        }
    }

    @Test func theSentencesSpokenAsTheyAreAreCompleteInEveryLanguage() {
        let keys: [PreviewStrings.Key] = [
            .interactionCopied, .findingActionCopied, .interactionFilterNoMatches, .interactionGoToLineNoLines,
            .loading, .cancelled, .disabledTitle, .disabledDescription,
            .geometryFit, .geometryReset, .geometryFront, .geometrySide, .geometryTop,
            .previewModeSource, .previewModeOutline, .previewModeRendered, .previewModeSummary, .previewModeTable
        ]
        for language in installedLanguages() {
            for key in keys {
                let spoken = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!spoken.isEmpty, "\(language) \(key.rawValue)")
                #expect(spoken != key.rawValue, "\(language) \(key.rawValue) would speak its own key")
                #expect(!spoken.contains("%"), "\(language) \(key.rawValue) would speak a directive: \(spoken)")
            }
        }
    }
}
