import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The typography and length rules of decision 027 (Q-111) for the values the copy sweep changed. English and French use
/// the typographic apostrophe; the header and notice sentences that were shortened stay within twelve words and still
/// say what they have to say. Hausa and Turkish keep their own apostrophe conventions until a native reviewer decides.
@Suite("Copy typography and length")
struct CopyTypographyTests {
    /// A straight apostrophe between two letters is a typing shortcut for U+2019.
    static func hasStraightApostropheBetweenLetters(_ text: String) -> Bool {
        let characters = Array(text)
        guard characters.count >= 3 else { return false }
        for index in 1..<(characters.count - 1) where characters[index] == "'" {
            if characters[index - 1].isLetter && characters[index + 1].isLetter { return true }
        }
        return false
    }

    @Test func noEnglishOrFrenchValueHasAStraightApostropheBetweenLetters() {
        var offenders: [String] = []
        for language in ["en", "fr"] {
            for key in PreviewStrings.Key.allCases {
                let value = PreviewStrings.text(key, languagePreferences: [language])
                if Self.hasStraightApostropheBetweenLetters(value) { offenders.append("\(language) \(key.rawValue)") }
            }
            // The format names and descriptions are catalog keys, not typed cases.
            for descriptor in FormatCatalog.standard.descriptors {
                for catalogKey in [descriptor.nameKey, descriptor.descriptionKey] {
                    let value = PreviewStrings.text(catalogKey: catalogKey, languagePreferences: [language])
                    if Self.hasStraightApostropheBetweenLetters(value) { offenders.append("\(language) \(catalogKey)") }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func theApostropheCheckSeesWhatItShouldAndNothingElse() {
        #expect(Self.hasStraightApostropheBetweenLetters("file's"))
        #expect(Self.hasStraightApostropheBetweenLetters("l'archive"))
        #expect(!Self.hasStraightApostropheBetweenLetters("file\u{2019}s"))
        #expect(!Self.hasStraightApostropheBetweenLetters("'quoted' text"))
        #expect(!Self.hasStraightApostropheBetweenLetters("rock 'n' roll"))
        #expect(!Self.hasStraightApostropheBetweenLetters("ab"))
    }

    @Test func theShortenedNoticesStayWithinTwelveWords() {
        let keys: [PreviewStrings.Key] = [.dataPlotSimplified, .listingPartialNotice, .packageNoticeSignature]
        for key in keys {
            let words = PreviewStrings.text(key, languagePreferences: ["en"]).split { $0.isWhitespace }
            #expect(words.count <= 12, "\(key.rawValue): \(words.count) words")
        }
    }

    @Test func theShortenedNoticesStillSayWhatTheyHaveToSay() {
        // The listing notice keeps the honest claim that totals cover only what is shown.
        #expect(PreviewStrings.text(.listingPartialNotice, languagePreferences: ["en"])
                == "This listing is partial, so totals cover only the entries shown.")
        // Signatures are shown as stored; nothing about their validity or notarization is claimed.
        #expect(PreviewStrings.text(.packageNoticeSignature, languagePreferences: ["en"])
                == "Signatures are shown as stored and not verified; notarization is not checked.")
        // Source is the name of the Source mode and keeps pointing at it.
        #expect(PreviewStrings.text(.dataPlotSimplified, languagePreferences: ["en"])
                == "Long paths show only some points. Source lists the drawn points.")
    }

    @Test func theSweptEnglishValuesUseTheTypographicApostrophe() {
        let unsupported = PreviewStrings.text(.unsupported, languagePreferences: ["en"])
        #expect(unsupported == "This file type isn\u{2019}t supported.")
        #expect(PreviewStrings.text(.generalFoldersSubtitle, languagePreferences: ["en"])
                == "Summarize a folder\u{2019}s direct contents in Quick Look.")
        #expect(PreviewStrings.text(.dataPlotHelp, languagePreferences: ["en"]).contains("file\u{2019}s coordinates"))
    }
}
