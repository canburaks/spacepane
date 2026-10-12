import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The title and body of every non-content state (decision 027, Q-110): loading, empty, a failure, a disabled type and
/// the two settings states. The failure wording itself is covered by `CopyFailureContentTests`.
@Suite("State title and body copy")
struct CopyStateContentTests {
    static let kinds: [NativeStateContent.Kind] = [
        .loading, .empty, .unavailable(.missingFile), .disabled, .settingsUnavailable, .configurationUnavailable
    ]

    static func copy(_ kind: NativeStateContent.Kind, _ language: String,
                     limits: PreviewLimitsSummary? = nil) -> (title: String, body: String) {
        PreviewFailureCopy.content(forState: kind, locale: CopyFailureContentTests.viewLocale(language), limits: limits,
                                   languagePreferences: [language])
    }

    @Test func everyKindHasATitleInEveryLanguageAndEveryKindButLoadingHasABody() {
        for language in CopyFailureContentTests.languages {
            for kind in Self.kinds {
                let entry = Self.copy(kind, language)
                #expect(!entry.title.isEmpty, "\(language) \(kind) title")
                if kind != .loading { #expect(!entry.body.isEmpty, "\(language) \(kind) body") }
                #expect(!entry.title.contains("%") && !entry.body.contains("%"), "\(language) \(kind)")
                #expect(!entry.title.contains("state.") && !entry.body.contains("state."), "\(language) \(kind)")
            }
        }
    }

    @Test func loadingSaysPreparingAndHasNoBody() {
        let entry = Self.copy(.loading, "en")
        #expect(entry.title == PreviewStrings.text(.loading, languagePreferences: ["en"]))
        #expect(entry.title == "Preparing preview…")
        #expect(entry.body.isEmpty)
    }

    @Test func aFailureStateIsTheFailureCopyWithItsLimits() {
        for language in CopyFailureContentTests.languages {
            for failure in CopyFailureContentTests.failures {
                #expect(Self.copy(.unavailable(failure), language) == CopyFailureContentTests.copy(failure, language),
                        "\(language) \(failure)")
            }
        }
        let limits = PreviewLimitsSummary(lines: 20_000)
        let state = Self.copy(.unavailable(.tooManyLines), "en", limits: limits)
        #expect(state == CopyFailureContentTests.copy(.tooManyLines, "en", limits: limits))
        #expect(state.body.contains("20,000"))
    }

    @Test func aDisabledTypeKeepsTheReviewedKeys() {
        for language in CopyFailureContentTests.languages {
            let entry = Self.copy(.disabled, language)
            #expect(entry.title == PreviewStrings.text(.disabledTitle, languagePreferences: [language]), "\(language)")
            #expect(entry.body == PreviewStrings.text(.disabledDescription, languagePreferences: [language]), "\(language)")
        }
    }

    @Test func theEnglishWordingOfTheStatesWithoutAFailureIsTheReviewedWording() {
        let emptyBody = "It has no content, so there is nothing to preview."
        let settingsBody = "The saved settings may be damaged or come from a newer version. Open the companion app to review setup and saved choices."
        let configurationBody = "This copy of the app cannot share settings with its previews, and opening the app will not change that. Reinstall it from its original source."
        let empty = Self.copy(.empty, "en")
        #expect(empty.title == "This file is empty")
        #expect(empty.body == emptyBody)
        let settings = Self.copy(.settingsUnavailable, "en")
        #expect(settings.title == "Settings are unavailable")
        #expect(settings.body == settingsBody)
        let configuration = Self.copy(.configurationUnavailable, "en")
        #expect(configuration.title == "The app is not set up correctly")
        #expect(configuration.body == configurationBody)
    }

    @Test func theSettingsStatesAreWordedForUsersNotDevelopers() {
        let developerWords = ["App Group", "App-Group", "entitlement", "provisioning", "sandbox", "signing", "Signatur", "signature"]
        for language in CopyFailureContentTests.languages {
            for kind in [NativeStateContent.Kind.settingsUnavailable, .configurationUnavailable] {
                let entry = Self.copy(kind, language)
                for word in developerWords {
                    #expect(!entry.title.localizedCaseInsensitiveContains(word), "\(language) \(kind) title: \(word)")
                    #expect(!entry.body.localizedCaseInsensitiveContains(word), "\(language) \(kind) body: \(word)")
                }
            }
        }
    }

    @Test func noTwoStatesShareATitleInEnglish() {
        let titles = Self.kinds.map { Self.copy($0, "en").title }
        #expect(Set(titles).count == titles.count)
    }
}
