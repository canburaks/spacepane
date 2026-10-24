import Foundation
import PreviewContracts
import PreviewPreferences
import PreviewRenderers

private struct PresentationCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// The companion's presentation models: the neutral status, the restored page and window title, point values,
/// the font list, profile names, theme transfer messages and the scan announcement. Pure values and isolated
/// defaults and storage; no window, no installed font, no VoiceOver.
@MainActor
enum CompanionPresentationChecks {
    private static let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]

    static func run(in root: URL) async throws {
        try settingsStatusIsNeutralUnlessAProblemIsVerified()
        try await theStatusFollowsTheStore(root)
        try routesPersistAndWindowTitlesNameThePage()
        try pointValuesFollowTheLocaleAndUseTheCatalogUnit()
        try fontFamiliesListFixedWidthFirst()
        try profileNamesAreCheckedAfterTrimming()
        try transferMessagesAreProblemsOnlyWhenTheyFail()
        try scanAnnouncementsReadTheConclusion()
        try openingSystemSettingsAdmitsWhatItCannotConfirm()
        print("Passed 9 companion presentation checks (isolated defaults and storage; no window, font or VoiceOver).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PresentationCheckFailure(description: message) }
    }

    private static func eventually(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw PresentationCheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Status

    /// Every combination of what the store knows. Nothing is ever positive: the tone is caution exactly when a
    /// problem is verified, and every other state is one neutral sentence.
    private static func settingsStatusIsNeutralUnlessAProblemIsVerified() throws {
        let storages: [CompanionSettings.StorageMode] = [.shared, .privateOnly, .unavailable]
        let saves: [CompanionSettings.SaveState] = [.idle, .saving, .saved, .failed]
        var combinations = 0
        var titles: Set<PreviewStrings.Key> = []
        for storage in storages {
            for save in saves {
                for recovered in [false, true] {
                    for loading in [false, true] {
                        combinations += 1
                        let status = SettingsStatus(storage: storage, save: save, recovered: recovered, isLoading: loading)
                        let label = "\(storage) \(save) recovered=\(recovered) loading=\(loading)"
                        titles.insert(status.titleKey)
                        try check(Set(status.problemKeys).count == status.problemKeys.count,
                                  "A problem must be listed once: \(label)")
                        try check((status.tone == .caution) == !status.problemKeys.isEmpty,
                                  "The tone is caution exactly when a problem is verified: \(label)")
                        if loading {
                            try check(status.tone == .neutral && status.titleKey == .statusLoading
                                      && status.problemKeys.isEmpty,
                                      "Loading is neutral and verifies nothing: \(label)")
                            continue
                        }
                        let hasProblem = recovered || storage != .shared || save == .failed
                        try check(status.problemKeys.isEmpty == !hasProblem,
                                  "A problem is listed exactly when storage, recovery or a save went wrong: \(label)")
                        if recovered {
                            try check(status.titleKey == .statusRecovered && status.problemKeys.first == .settingsRecovery,
                                      "A recovery leads: \(label)")
                        } else if storage == .unavailable {
                            try check(status.titleKey == .statusUnavailable && status.problemKeys == [.storageUnavailable],
                                      "Unavailable storage is one problem, not also a failed save: \(label)")
                        } else if save == .failed {
                            try check(status.titleKey == .statusSaveFailed && status.problemKeys.contains(.settingsSaveFailed),
                                      "A failed save is named: \(label)")
                        } else if storage == .privateOnly {
                            try check(status.titleKey == .statusAppOnly && status.problemKeys == [.setupNotConfigured],
                                      "App-only settings are a caution that stays: \(label)")
                        } else {
                            let expected: PreviewStrings.Key
                            switch save {
                            case .idle: expected = .statusShared
                            case .saving: expected = .settingsSaving
                            case .saved, .failed: expected = .settingsSaved
                            }
                            try check(status.titleKey == expected && status.tone == .neutral,
                                      "A healthy shared store is one neutral sentence: \(label)")
                        }
                    }
                }
            }
        }
        try check(combinations == 48, "Every combination must be covered: \(combinations)")
        // The words of every title say where settings are or what went wrong, never what Finder or the
        // extensions are doing.
        let forbidden = ["finder", "ready", "active", "enabled", "working", "connected", "using"]
        for key in titles {
            let text = PreviewStrings.text(key, languagePreferences: ["en"]).lowercased()
            try check(!text.isEmpty && forbidden.allSatisfy { !text.contains($0) },
                      "A status title must not claim routing or activity: \(key.rawValue) = \(text)")
        }
    }

    private static func theStatusFollowsTheStore(_ root: URL) async throws {
        let store = PreferenceStore(url: root.appendingPathComponent("status-preferences.json"))
        let shared = CompanionSettings(store: store, storageMode: .shared)
        try check(shared.status.titleKey == .statusLoading && shared.status.tone == .neutral,
                  "Before the first load the status says loading")
        await shared.load()
        try check(shared.status.titleKey == .statusShared && shared.status.tone == .neutral,
                  "A loaded shared store says where settings are, in the neutral tone")
        shared.setAllEnabled(false)
        try check(shared.status.titleKey == .settingsSaving, "While saving the status says so")
        try await eventually("The status check did not finish saving") { shared.saveState == .saved }
        try check(shared.status.titleKey == .settingsSaved && shared.status.tone == .neutral,
                  "A saved choice reads as saved, neutrally")
        let unavailable = CompanionSettings(store: nil, storageMode: .unavailable)
        await unavailable.load()
        try check(unavailable.status.tone == .caution && unavailable.status.titleKey == .statusUnavailable
                  && unavailable.status.problemKeys == [.storageUnavailable],
                  "Unavailable storage is a caution with one problem")
    }

    // MARK: Pages and the window

    private static func routesPersistAndWindowTitlesNameThePage() throws {
        try check(CompanionRoute.allCases.map(\.rawValue) == ["general", "fileTypes", "theme", "about", "tryPreview"],
                  "Route raw values are stored in the defaults and must not change")
        let suite = "prev.model-checks.route.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw PresentationCheckFailure(description: "Could not create an isolated defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CompanionPreferences(defaults: defaults)
        try check(preferences.lastRoute == .general && preferences.restoredRoute == .general,
                  "A fresh window opens on General")
        preferences.setLastRoute(.theme)
        try check(CompanionPreferences(defaults: defaults).restoredRoute == .theme, "The last page must be restored")
        defaults.set("a-page-that-was-removed", forKey: "companion.lastRoute")
        try check(CompanionPreferences(defaults: defaults).restoredRoute == .general,
                  "An unknown stored page must open General")
        preferences.setLastRoute(.tryPreview)
        try check(CompanionPreferences(defaults: defaults).restoredRoute == .tryPreview,
                  "A stored Try Preview is restored: no setting hides it")

        let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        for language in languages {
            for route in CompanionRoute.allCases {
                let title = route.windowTitle(appName: "Fixture App", locale: Locale(identifier: language),
                                              languagePreferences: [language])
                let page = PreviewStrings.text(route.title, languagePreferences: [language])
                try check(title.contains("Fixture App") && title.contains(page) && title != unavailable
                          && !title.contains("%"),
                          "\(language): the window title must name the page and the app: \(title)")
            }
        }
    }

    // MARK: Points

    private static func pointValuesFollowTheLocaleAndUseTheCatalogUnit() throws {
        let english = Locale(identifier: "en_US")
        func text(_ value: Double) -> String {
            TypographyPointFormat.text(value, locale: english, languagePreferences: ["en"])
        }
        try check(text(13) == "13 pt" && text(0.25) == "0.25 pt" && text(13.5) == "13.5 pt" && text(-1) == "-1 pt",
                  "Whole values print without a fraction and fractions keep at most two digits: \(text(13)) \(text(0.25))")
        try check(text(12.999) == "13 pt" && text(13.004) == "13 pt" && text(0) == "0 pt",
                  "Values round to two fraction digits: \(text(12.999)) \(text(13.004)) \(text(0))")
        let german = TypographyPointFormat.text(13.5, locale: Locale(identifier: "de_DE"), languagePreferences: ["de"])
        try check(german.contains("13,5"), "German points must use a decimal comma: \(german)")
        // Digits come from the locale, whichever digits Foundation chooses for it; no ASCII digit may survive
        // when the locale draws its own.
        let probe = Locale(identifier: "bn_BD@numbers=beng")
        let probeDigits = 13.formatted(.number.locale(probe))
        if probeDigits.contains(where: { !$0.isASCII }) {
            let bengali = TypographyPointFormat.text(13, locale: probe, languagePreferences: ["bn"])
            try check(bengali.contains(probeDigits) && !bengali.contains(where: { $0.isASCII && $0.isNumber }),
                      "Points must draw the locale's own digits: \(bengali)")
        }
        let bengaliLocale = Locale(identifier: "bn_BD")
        try check(TypographyPointFormat.number(13.5, locale: bengaliLocale) == 13.5.formatted(.number.locale(bengaliLocale)),
                  "The number must be formatted by the locale, not by a format string")

        func spoken(_ value: Double, _ language: String) -> String {
            TypographyPointFormat.spokenText(value, locale: Locale(identifier: language), languagePreferences: [language])
        }
        try check(spoken(13, "en") == "13 points" && spoken(1, "en") == "1 point",
                  "A whole number is spelled out with its plural: \(spoken(13, "en")) \(spoken(1, "en"))")
        try check(spoken(0.25, "en") == text(0.25), "A fraction is read as it is written: \(spoken(0.25, "en"))")
        let few = spoken(2, "ru").replacingOccurrences(of: "2", with: "")
        let many = spoken(5, "ru").replacingOccurrences(of: "5", with: "")
        try check(few != many && !few.isEmpty && !many.isEmpty, "Russian must use its own plural forms: \(few) | \(many)")
        for language in languages {
            let word = spoken(13, language)
            let digits = 13.formatted(.number.locale(Locale(identifier: language)))
            let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
            try check(word.contains(digits) && !word.contains("%") && word != unavailable,
                      "\(language): the spoken size must exist: \(word)")
        }

        let range = PreviewTypography.fontSizeRange
        try check(TypographyPointFormat.clamped(100, to: range, fallback: 13) == 48
                  && TypographyPointFormat.clamped(-5, to: range, fallback: 13) == 8
                  && TypographyPointFormat.clamped(21.5, to: range, fallback: 13) == 21.5,
                  "A typed size is limited to the supported range")
        try check(TypographyPointFormat.clamped(.nan, to: range, fallback: 13) == 13
                  && TypographyPointFormat.clamped(.infinity, to: range, fallback: 13) == 13,
                  "A size that is not a number changes nothing")
    }

    // MARK: Fonts and profile names

    private static func fontFamiliesListFixedWidthFirst() throws {
        let installed = ["Arial", "Courier New", "Helvetica", "Menlo", "SF Mono", "Times"]
        let list = FontFamilyList(families: installed, fixedWidthFamilies: ["Menlo", "Courier New", "SF Mono", "Not Installed"])
        try check(list.fixedWidth == ["Courier New", "Menlo", "SF Mono"] && list.others == ["Arial", "Helvetica", "Times"],
                  "Fixed-width families come first and each list keeps its order: \(list)")
        try check(list.fixedWidth.count + list.others.count == installed.count
                  && Set(list.fixedWidth + list.others) == Set(installed),
                  "No family is dropped or listed twice")
        try check(list.contains("Menlo") && list.contains("Arial") && !list.contains("Papyrus"),
                  "A family is found in either list")
        try check(FontFamilyList.empty.isEmpty && !list.isEmpty, "The empty list is empty")
    }

    private static func profileNamesAreCheckedAfterTrimming() throws {
        let existing = ["Alpha"]
        let padded = ProfileNameCheck("  Beta \n", existingNames: existing)
        try check(padded.canSave && padded.name == "Beta" && padded.explanationKey == nil,
                  "White space at either end must not disable Save, and Save stores the trimmed name")
        for blank in ["", "   ", " \n\t "] {
            let result = ProfileNameCheck(blank, existingNames: existing)
            try check(result.problem == .empty && result.explanationKey == .profileSaveEmpty && !result.canSave,
                      "An empty name is explained: \(blank.debugDescription)")
        }
        let duplicate = ProfileNameCheck("Alpha ", existingNames: existing)
        try check(duplicate.problem == .duplicate && duplicate.explanationKey == .profileSaveDuplicate,
                  "A duplicate is found after trimming")
        for invalid in ["Line\nBreak", "Tab\tName", "Mark\u{202E}Reversed", String(repeating: "x", count: 129)] {
            let result = ProfileNameCheck(invalid, existingNames: existing)
            try check(result.problem == .invalid && result.explanationKey == .profileSaveInvalid,
                      "An unusable name is explained: \(invalid.debugDescription)")
        }
        try check(ProfileNameCheck(String(repeating: "x", count: 128), existingNames: existing).canSave,
                  "The longest allowed name can be saved")
        let full = (0..<PreviewAppearanceProfile.maximumCount).map { "Name \($0)" }
        let limit = ProfileNameCheck("Valid", existingNames: full)
        try check(limit.problem == .limitReached && limit.explanationKey == .profilesLimit && !limit.canSave,
                  "A full list is explained by its own sentence")
    }

    // MARK: Messages

    private static func transferMessagesAreProblemsOnlyWhenTheyFail() throws {
        typealias Message = AppearanceThemeTransfer.Message
        try check(!Message.imported.isProblem && !Message.exported.isProblem,
                  "A finished import or export is a quiet note")
        try check(Message.failed.isProblem && Message.importError(.invalidDocument).isProblem
                  && Message.importError(.tooLarge).isProblem,
                  "A failed transfer is drawn as a problem")
    }

    private static func scanAnnouncementsReadTheConclusion() throws {
        let english = ["en"]
        let none = QuickLookProviderReport(scannedApplications: 12)
        try check(none.announcement(languagePreferences: english) == PreviewStrings.text(.providersNone, languagePreferences: english),
                  "A scan that found nothing announces the sentence the list opens with")
        let app = QuickLookProviderApp(id: "/Applications/Fixture.app", name: "Fixture", bundleIdentifier: nil,
                                       kinds: .preview, overlappingFormats: [.json])
        let found = QuickLookProviderReport(providers: [app], scannedApplications: 12)
        let text = found.announcement(locale: Locale(identifier: "en_US"), languagePreferences: english)
        try check(text.contains("1") && text != none.announcement(languagePreferences: english),
                  "A scan that found an app announces how many: \(text)")
    }

    // MARK: System Settings

    /// The link may be accepted without the pane showing, so the manual route follows every attempt, and the
    /// application fallback runs exactly when the link was refused.
    private static func openingSystemSettingsAdmitsWhatItCannotConfirm() throws {
        let link = URL(string: "x-apple.systempreferences:synthetic")
        let application = URL(fileURLWithPath: "/System/Applications/Synthetic.app")
        var openedApplications: [URL] = []
        let accepted = SystemSettingsOpening.open(link: link, openLink: { _ in true }, applicationURL: { application },
                                                  openApplication: { openedApplications.append($0) })
        try check(accepted == .linkAccepted && openedApplications.isEmpty,
                  "An accepted link must be reported as such and must not open the application a second time")
        let refused = SystemSettingsOpening.open(link: link, openLink: { _ in false }, applicationURL: { application },
                                                 openApplication: { openedApplications.append($0) })
        try check(refused == .applicationOnly && openedApplications == [application],
                  "A refused link must open System Settings itself, once")
        openedApplications = []
        let unparsable = SystemSettingsOpening.open(link: nil, openLink: { _ in true }, applicationURL: { application },
                                                    openApplication: { openedApplications.append($0) })
        try check(unparsable == .applicationOnly && openedApplications == [application],
                  "Without a usable link System Settings must still open")
        let neither = SystemSettingsOpening.open(link: link, openLink: { _ in false }, applicationURL: { nil },
                                                 openApplication: { openedApplications.append($0) })
        try check(neither == .failed, "A refused link and a missing application must be reported as a failure")
        for result in [SystemSettingsOpening.Result.linkAccepted, .applicationOnly, .failed] {
            try check(SystemSettingsOpening.manualRouteKey(after: result) == .setupSteps,
                      "The manual route must follow every attempt, because no attempt confirms the pane: \(result)")
        }
        let route = PreviewStrings.text(.setupSteps, languagePreferences: ["en"])
        try check(route.contains("Login Items & Extensions") && route.contains("Quick Look"),
                  "The manual route must name the pane in the words System Settings uses: \(route)")
    }
}
