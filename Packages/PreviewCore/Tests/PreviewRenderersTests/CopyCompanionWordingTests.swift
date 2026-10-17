import Foundation
import Testing
@testable import PreviewRenderers

/// The companion's own sentences that review findings reworded: what a switch enables, and words a person who
/// never opens Xcode can read. English is the language that ships; the other languages are drafts, so they are
/// checked only for what must hold in every language.
@Suite("Companion wording")
struct CopyCompanionWordingTests {
    static let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]

    static func english(_ key: PreviewStrings.Key) -> String {
        PreviewStrings.text(key, languagePreferences: ["en"])
    }

    // MARK: Developer Mode (review finding 23)

    @Test func developerModeNamesEverythingItEnables() {
        let subtitle = Self.english(.developerModeSubtitle)
        // The switch reveals the Try Preview page (⌘5) and the Open File command (⌘O), not only a sidebar row.
        for fragment in ["Try Preview", "Open File", "⌘O", "⌘5"] {
            #expect(subtitle.contains(fragment), "Developer Mode subtitle must name \(fragment): \(subtitle)")
        }
    }

    // MARK: Storage wording (review finding 24)

    @Test func theAppOnlyStorageStatesNameNoDeveloperConcepts() {
        let developerWords = ["App Group", "App-Group", "AppGroup"]
        for language in Self.languages {
            for key in [PreviewStrings.Key.setupNotConfigured, .statusAppOnly] {
                let text = PreviewStrings.text(key, languagePreferences: [language])
                for word in developerWords {
                    #expect(!text.localizedCaseInsensitiveContains(word), "\(language) \(key): \(word) in \(text)")
                }
            }
        }
        // "Build" is the developer's word for a version of the app.
        let english = Self.english(.setupNotConfigured)
        #expect(english.range(of: #"\bbuild\b"#, options: [.regularExpression, .caseInsensitive]) == nil, "\(english)")
        #expect(english.contains("saved for this app only"), "\(english)")
    }

    // MARK: Product framing (review finding 25)

    @Test func theProductIsDescribedByWhatItDoesNotByItsComponentType() {
        for key in [PreviewStrings.Key.shellSubtitle, .aboutDescription] {
            let text = Self.english(key)
            for word in ["extension", "plug-in", "plugin"] {
                #expect(!text.localizedCaseInsensitiveContains(word), "\(key) calls the product a \(word): \(text)")
            }
        }
        #expect(Self.english(.shellSubtitle).localizedCaseInsensitiveContains("Finder"), "\(Self.english(.shellSubtitle))")
    }

    @Test func theTechnicalFactsStayInTheAboutHelp() {
        // The Help section on the About page is where the Quick Look extensions are named and switched on.
        #expect(Self.english(.setupSteps).contains("Quick Look extensions"), "\(Self.english(.setupSteps))")
        #expect(Self.english(.aboutHowItWorksBody).contains("Quick Look provider"), "\(Self.english(.aboutHowItWorksBody))")
    }
}
