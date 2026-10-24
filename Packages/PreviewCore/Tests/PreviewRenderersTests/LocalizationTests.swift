import Foundation
import Testing
@testable import PreviewContracts
@testable import PreviewRenderers

@Suite("Owned localization resources")
struct LocalizationTests {
    @Test func everyTypedKeyResolvesFromPackageBundle() {
        for key in PreviewStrings.Key.allCases {
            let value = PreviewStrings.text(key)
            #expect(!value.isEmpty)
            #expect(value != key.rawValue)
        }
    }

    @Test func everySelectedLanguageHasCompleteOwnedResources() throws {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for language in languages {
            // SwiftPM lowercases script subtags in generated resource directories.
            // Ask Foundation for the installed spelling rather than assuming source casing.
            let installedLanguage = try #require(RendererResources.bundle.localizations.first { $0.caseInsensitiveCompare(language) == .orderedSame })
            let path = try #require(RendererResources.bundle.path(forResource: installedLanguage, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in PreviewStrings.Key.allCases {
                let value = bundle.localizedString(forKey: key.rawValue, value: "MISSING_TRANSLATION", table: nil)
                #expect(value != "MISSING_TRANSLATION")
                #expect(!value.isEmpty)
                #expect(PreviewStrings.text(key, languagePreferences: [language]) == value)
            }
            if language != "en" {
                #expect(PreviewStrings.text(.tryPreview, languagePreferences: [language]) != PreviewStrings.text(.tryPreview, languagePreferences: ["en"]))
            }
        }
    }

    @Test func catalogNamesAndDescriptionsResolve() {
        for descriptor in FormatCatalog.standard.descriptors {
            for key in [descriptor.nameKey, descriptor.descriptionKey] {
                let value = PreviewStrings.text(catalogKey: key)
                #expect(!value.isEmpty)
                #expect(value != key)
                #expect(value != PreviewStrings.text(.resourceUnavailable))
            }
        }
    }

    @Test func missingResourceDoesNotExposeTechnicalKey() {
        let missing = "test.deliberately-missing-resource"
        let value = PreviewStrings.text(catalogKey: missing)
        #expect(!value.isEmpty)
        #expect(value != missing)
        #expect(value == PreviewStrings.text(.resourceUnavailable))
    }

    @Test func unsupportedLanguageUsesDevelopmentFallback() {
        for key in PreviewStrings.Key.allCases {
            #expect(PreviewStrings.text(key, languagePreferences: ["zz-ZZ"])
                    == PreviewStrings.text(key, languagePreferences: ["en"]))
        }
    }

    @Test func regionalPreferencesResolveTheSelectedLanguageResources() {
        let preferences = [
            ("en-GB", "en"), ("tr-TR", "tr"), ("de-AT", "de"), ("fr-CA", "fr"),
            ("zh-Hans-CN", "zh-Hans"), ("ja-JP", "ja"), ("hi-IN", "hi"),
            ("ku-Latn-TR", "ku-Latn"), ("ru-RU", "ru"), ("id-ID", "id"),
            ("bn-BD", "bn"), ("ha-Latn-NG", "ha"), ("pt-BR", "pt"), ("es-MX", "es")
        ]
        for (regional, selected) in preferences {
            #expect(PreviewStrings.text(.tryPreview, languagePreferences: [regional])
                    == PreviewStrings.text(.tryPreview, languagePreferences: [selected]))
        }
        #expect(PreviewStrings.text(.tryPreview, languagePreferences: ["pt-PT"])
                == PreviewStrings.text(.tryPreview, languagePreferences: ["pt"]))
        #expect(PreviewStrings.text(.tryPreview, languagePreferences: ["es-ES"])
                == PreviewStrings.text(.tryPreview, languagePreferences: ["es"]))
    }

    @Test func unavailablePreferenceDoesNotHideTheNextSelectedLanguage() {
        #expect(PreviewStrings.text(.tryPreview, languagePreferences: ["zz-ZZ", "tr-TR"])
                == PreviewStrings.text(.tryPreview, languagePreferences: ["tr"]))
    }

    @Test func typographyFormattingUsesTheRequestedRegionalDecimalSeparator() {
        let english = PreviewStrings.format(.typographyPointValue, arguments: [12.5], locale: Locale(identifier: "en_US"))
        let turkish = PreviewStrings.format(.typographyPointValue, arguments: [12.5], locale: Locale(identifier: "tr_TR"))
        #expect(english.contains("12.50"))
        #expect(turkish.contains("12,50"))
        // Locale controls numbers; choosing a formatting region must not switch UI language.
        #expect(english.replacingOccurrences(of: "12.50", with: "NUMBER")
                == turkish.replacingOccurrences(of: "12,50", with: "NUMBER"))
    }

    @Test func localizedInterpolationPreservesUserSpellingAndBidirectionalCharacters() {
        let name = "package.json / .env.* / İı / e\u{301} / 9007199254740993 / مثال"
        for region in ["en_US", "tr_TR", "ar_SA", "bn_BD"] {
            let result = PreviewStrings.format(.deleteProfileNamed, arguments: [name], locale: Locale(identifier: region))
            #expect(result.contains(name))
            #expect(result.components(separatedBy: name).count == 2)
        }
    }

    @Test func geometrySummaryKeepsEveryComputedArgumentInAllLanguages() {
        let width = "0,5"
        let height = "1.25"
        let depth = "9007199254740993"
        let arguments: [CVarArg] = ["12", "34", width, height, depth, "mm"]
        for language in RendererResources.bundle.localizations {
            let result = String(format: PreviewStrings.text(.geometrySummaryDimensions, languagePreferences: [language]),
                                locale: Locale(identifier: "en_US_POSIX"), arguments: arguments)
            for value in ["12", "34", width, height, depth, "mm"] { #expect(result.contains(value)) }
            #expect(!result.contains("%"))
        }
    }

    @Test func missingResourceUsesDocumentedDevelopmentFallbackInEveryLanguage() {
        let fallback = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        for language in RendererResources.bundle.localizations {
            #expect(PreviewStrings.text(catalogKey: "test.deliberately-missing-resource", languagePreferences: [language]) == fallback)
        }
    }

    @Test func stagedAppResolvesEmbeddedResourcesWithoutBuildCacheFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("ResourceFixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "invalid.example.resource-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let host = try #require(Bundle(url: app))

        let contractDestination = resources.appendingPathComponent("PreviewCore_PreviewContracts.bundle")
        let rendererDestination = resources.appendingPathComponent("PreviewCore_PreviewRenderers.bundle")
        try FileManager.default.copyItem(at: ContractResources.bundle.bundleURL, to: contractDestination)
        try FileManager.default.copyItem(at: RendererResources.bundle.bundleURL, to: rendererDestination)

        var fallbackUsed = false
        let contracts = ContractResources.resolve(in: host) { fallbackUsed = true; return .main }
        let renderers = RendererResources.resolve(in: host) { fallbackUsed = true; return .main }
        #expect(!fallbackUsed)
        #expect(contracts.bundleURL.standardizedFileURL == contractDestination.standardizedFileURL)
        #expect(renderers.bundleURL.standardizedFileURL == rendererDestination.standardizedFileURL)
        #expect(contracts.url(forResource: "FormatCatalog", withExtension: "json") != nil)
        #expect(renderers.path(forResource: "en", ofType: "lproj") != nil)
    }
}
