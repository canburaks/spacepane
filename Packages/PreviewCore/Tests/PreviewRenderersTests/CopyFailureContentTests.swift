import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Every failure has its own title and body in every language, bodies end with the next step, and a limit value is
/// printed only when the caller knows it (decision 027, Q-110). Exact English is pinned for the titles and for the
/// bodies that carry a claim about what the app does; the other languages are checked for shape, never for wording.
@Suite("Failure title and body copy")
struct CopyFailureContentTests {
    /// Every `PreviewFailure` case. The production switch is exhaustive, so a new case does not compile without
    /// wording; this list is what the checks below walk, so add the new case here as well.
    static let failures: [PreviewFailure] = [
        .unsupportedFormat, .missingFile, .unreadableFile, .notRegularFile, .unavailableContent,
        .inputTooLarge, .outputTooLarge, .binaryContent, .unsupportedEncoding, .malformedDocument,
        .cadImporterUnavailable, .encryptedContent, .structureTooDeep, .tooManyNodes, .tooManyLines,
        .lineTooLong, .invalidBudget, .deadlineExceeded, .unsupportedVariant, .geometryTooComplex
    ]

    /// The failures whose body can state a limit.
    static let limitFailures: [PreviewFailure] = [
        .inputTooLarge, .outputTooLarge, .structureTooDeep, .tooManyNodes, .tooManyLines, .lineTooLong, .deadlineExceeded
    ]

    static let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]

    /// A full stop, an ideographic full stop or a danda: where a sentence ends in the shipped languages.
    static let sentenceEnds: Set<Character> = [".", "\u{3002}", "\u{0964}"]

    /// Whether a text ends the way a sentence does in the shipped languages.
    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return sentenceEnds.contains(last)
    }

    static func viewLocale(_ language: String) -> Locale {
        Locale(identifier: language == "en" ? "en_US" : language)
    }

    static func copy(_ failure: PreviewFailure, _ language: String,
                     limits: PreviewLimitsSummary? = nil) -> (title: String, body: String) {
        PreviewFailureCopy.content(for: failure, locale: viewLocale(language), limits: limits, languagePreferences: [language])
    }

    // MARK: Coverage and shape

    @Test func everyFailureHasATitleAndABodyInEveryLanguage() {
        for language in Self.languages {
            for failure in Self.failures {
                let entry = Self.copy(failure, language)
                #expect(!entry.title.isEmpty && !entry.body.isEmpty, "\(language) \(failure)")
                #expect(!entry.title.contains("failure.") && !entry.body.contains("failure."), "\(language) \(failure)")
                #expect(!entry.title.contains("%") && !entry.body.contains("%"), "\(language) \(failure)")
            }
        }
    }

    @Test func everyOtherLanguageIsTranslatedNotCopiedFromEnglish() {
        for failure in Self.failures {
            let english = Self.copy(failure, "en")
            for language in Self.languages where language != "en" {
                let entry = Self.copy(failure, language)
                #expect(entry.title != english.title, "\(language) \(failure) title")
                #expect(entry.body != english.body, "\(language) \(failure) body")
            }
        }
    }

    @Test func aTitleNamesWhatHappenedWithoutAFullStopAndABodyEndsAsASentence() {
        for language in Self.languages {
            for failure in Self.failures {
                let entry = Self.copy(failure, language)
                #expect(!Self.endsSentence(entry.title), "\(language) \(failure) title")
                #expect(Self.endsSentence(entry.body), "\(language) \(failure) body")
            }
        }
    }

    @Test func noTwoFailuresShareATitleOrABodyInEnglish() {
        let copies = Self.failures.map { Self.copy($0, "en") }
        #expect(Set(copies.map { $0.title }).count == copies.count)
        #expect(Set(copies.map { $0.body }).count == copies.count)
    }

    // MARK: Reviewed English

    @Test func theEnglishTitlesAreTheReviewedWording() {
        let titles: [(PreviewFailure, String)] = [
            (.unsupportedFormat, "This file type is not supported"),
            (.missingFile, "The file was not found"),
            (.unreadableFile, "The file could not be read"),
            (.notRegularFile, "This item cannot be previewed"),
            (.unavailableContent, "The file is not on this Mac"),
            (.inputTooLarge, "The file is too large to preview"),
            (.outputTooLarge, "The preview would be too large"),
            (.binaryContent, "This file cannot be shown as text"),
            (.unsupportedEncoding, "The text encoding is not supported"),
            (.malformedDocument, "The file is not valid"),
            (.cadImporterUnavailable, "The CAD importer is not available"),
            (.encryptedContent, "The file is encrypted"),
            (.structureTooDeep, "The document is nested too deeply"),
            (.tooManyNodes, "The document has too many items"),
            (.tooManyLines, "The file has too many lines"),
            (.lineTooLong, "A line in the file is too long"),
            (.invalidBudget, "The preview could not start"),
            (.deadlineExceeded, "The preview took too long"),
            (.unsupportedVariant, "This variant of the format is not supported"),
            (.geometryTooComplex, "The model is too complex")
        ]
        #expect(titles.count == Self.failures.count)
        for (failure, title) in titles {
            #expect(Self.copy(failure, "en").title == title, "\(failure)")
        }
    }

    @Test func bodiesThatMakeAClaimAboutTheAppSayExactlyThat() {
        // The app never downloads a cloud file and never promises to; it names the next step for the reader.
        #expect(Self.copy(.unavailableContent, "en").body
                == "Its content is stored online, for example in iCloud Drive. Download it first, then preview it again.")
        // The encodings the decoder reads, named so that the reader knows what to save the file as.
        #expect(Self.copy(.unsupportedEncoding, "en").body
                == "This preview reads UTF-8 and UTF-16 text. Save the file in one of these encodings, then preview it again.")
        // Nothing is decrypted or guessed.
        #expect(Self.copy(.encryptedContent, "en").body == "Its content cannot be shown. Open it in an app that can unlock it.")
        // The importer failure suggests retrying and checking the installation; it never requires a reinstall.
        let importer = Self.copy(.cadImporterUnavailable, "en").body
        #expect(importer == "It may be busy or interrupted. Try again, or check that the app is installed correctly.")
        #expect(!importer.localizedCaseInsensitiveContains("reinstall"))
    }

    // MARK: Limits

    @Test func aBodyNeverPrintsALimitItDoesNotKnow() {
        let unknown: [PreviewLimitsSummary?] = [
            nil, PreviewLimitsSummary(),
            // A value that is not positive is not a limit.
            PreviewLimitsSummary(inputBytes: 0, outputBytes: -1, lines: 0, lineBytes: 0, nodes: -5, depth: 0, milliseconds: 0)
        ]
        for language in Self.languages {
            for failure in Self.limitFailures {
                for limits in unknown {
                    let body = Self.copy(failure, language, limits: limits).body
                    #expect(body.rangeOfCharacter(from: .decimalDigits) == nil, "\(language) \(failure): \(body)")
                    #expect(!body.contains("%"), "\(language) \(failure): \(body)")
                    #expect(body == Self.copy(failure, language).body, "\(language) \(failure)")
                }
            }
        }
    }

    @Test func aKnownLimitIsPrintedInTheLocaleOfTheView() {
        let budget = PreviewBudget.standard
        let limits = PreviewLimitsSummary(budget: budget)
        for language in Self.languages {
            let locale = Self.viewLocale(language)
            func size(_ bytes: Int) -> String { Int64(bytes).formatted(.byteCount(style: .file).locale(locale)) }
            func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
            let time = Duration.milliseconds(budget.maxMilliseconds)
                .formatted(.units(allowed: [.seconds, .milliseconds], width: .wide).locale(locale))
            let expected: [(PreviewFailure, String)] = [
                (.inputTooLarge, size(budget.maxInputBytes)),
                (.outputTooLarge, size(budget.maxOutputUTF8Bytes)),
                (.lineTooLong, size(budget.maxLineUTF8Bytes)),
                (.deadlineExceeded, time),
                (.structureTooDeep, number(budget.maxJSONDepth)),
                (.tooManyNodes, number(budget.maxJSONNodes)),
                (.tooManyLines, number(budget.maxTextLines))
            ]
            for (failure, text) in expected {
                let entry = Self.copy(failure, language, limits: limits)
                #expect(entry.body.contains(text), "\(language) \(failure): \(entry.body)")
                #expect(!entry.body.contains("%"), "\(language) \(failure): \(entry.body)")
                // The title does not change with the limit.
                #expect(entry.title == Self.copy(failure, language).title, "\(language) \(failure)")
            }
        }
    }

    @Test func theEnglishLimitSentencesAreTheReviewedWording() {
        let locale = Self.viewLocale("en")
        let size = Int64(1_048_576).formatted(.byteCount(style: .file).locale(locale))
        let time = Duration.milliseconds(2_000)
            .formatted(.units(allowed: [.seconds, .milliseconds], width: .wide).locale(locale))
        let step = "Open it in an app made for this type of file."
        let retry = "Try again, or open it in an app made for this type of file."
        let cases: [(PreviewFailure, PreviewLimitsSummary, String)] = [
            (.inputTooLarge, PreviewLimitsSummary(inputBytes: 1_048_576),
             "This file is larger than the \(size) this preview can read. \(step)"),
            (.outputTooLarge, PreviewLimitsSummary(outputBytes: 1_048_576),
             "Showing this file would take more than the \(size) this preview allows. \(step)"),
            (.lineTooLong, PreviewLimitsSummary(lineBytes: 1_048_576),
             "One line is longer than the \(size) this preview can show. Open the file in a text editor."),
            (.deadlineExceeded, PreviewLimitsSummary(milliseconds: 2_000),
             "This preview allows \(time) to process a file, and this one took longer. \(retry)"),
            (.structureTooDeep, PreviewLimitsSummary(depth: 64),
             "This preview reads documents nested up to 64 levels deep, and this one goes deeper. \(step)"),
            (.tooManyNodes, PreviewLimitsSummary(nodes: 20_000),
             "This preview reads documents of up to 20,000 items, and this one has more. \(step)"),
            (.tooManyLines, PreviewLimitsSummary(lines: 20_000),
             "This preview shows up to 20,000 lines, and this file has more. Open it in a text editor to read all of it.")
        ]
        for (failure, limits, body) in cases {
            #expect(Self.copy(failure, "en", limits: limits).body == body, "\(failure)")
        }
    }

    @Test func englishSelectsTheOneAndOtherFormOfACountedLimit() {
        #expect(Self.copy(.tooManyLines, "en", limits: PreviewLimitsSummary(lines: 1)).body.contains("up to 1 line,"))
        #expect(Self.copy(.tooManyLines, "en", limits: PreviewLimitsSummary(lines: 2)).body.contains("up to 2 lines,"))
        #expect(Self.copy(.structureTooDeep, "en", limits: PreviewLimitsSummary(depth: 1)).body.contains("up to 1 level deep,"))
        #expect(Self.copy(.tooManyNodes, "en", limits: PreviewLimitsSummary(nodes: 1)).body.contains("up to 1 item,"))
    }

    @Test func russianChoosesTheFormOfACountedLimit() {
        let locale = Self.viewLocale("ru")
        func form(_ value: Int) -> String {
            let body = Self.copy(.tooManyLines, "ru", limits: PreviewLimitsSummary(lines: value)).body
            return body.replacingOccurrences(of: value.formatted(.number.locale(locale)), with: "#")
        }
        // The form follows the last digits, and the check compares forms rather than wording, so a translation
        // review does not break it: 21 reads like 1, 22 like 2, 11 and 25 like 5.
        #expect(form(21) == form(1), "21 takes the form of 1")
        #expect(form(22) == form(2), "22 takes the form of 2")
        #expect(form(11) == form(5), "11 is many, not one")
        #expect(form(25) == form(5), "25 takes the form of 5")
        #expect(form(1) != form(2), "one and few are different forms")
        #expect(form(1) != form(5), "one and many are different forms")
    }

    @Test func aBudgetFillsEveryLimitFromItsOwnField() {
        // Seven different values, so that two fields swapped by mistake cannot pass.
        let budget = PreviewBudget(maxInputBytes: 11, maxOutputUTF8Bytes: 22, maxJSONDepth: 33, maxJSONNodes: 44,
                                   maxTextLines: 55, maxLineUTF8Bytes: 66, maxMilliseconds: 77)
        let limits = PreviewLimitsSummary(budget: budget)
        #expect(limits.inputBytes == 11)
        #expect(limits.outputBytes == 22)
        #expect(limits.depth == 33)
        #expect(limits.nodes == 44)
        #expect(limits.lines == 55)
        #expect(limits.lineBytes == 66)
        #expect(limits.milliseconds == 77)
        #expect(PreviewLimitsSummary() == PreviewLimitsSummary(inputBytes: nil, outputBytes: nil, lines: nil, lineBytes: nil,
                                                               nodes: nil, depth: nil, milliseconds: nil))
    }

    @Test func aFailureWithoutALimitIgnoresTheLimitsItIsGiven() {
        let limits = PreviewLimitsSummary(budget: .standard)
        for language in Self.languages {
            for failure in Self.failures where !Self.limitFailures.contains(failure) {
                let withLimits = Self.copy(failure, language, limits: limits)
                let without = Self.copy(failure, language)
                #expect(withLimits == without, "\(language) \(failure)")
            }
        }
    }
}
