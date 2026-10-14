import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The wheel summary's label set (decision 030). Registering it in `SafeSchemaLabels` and applying the
/// strings are the lead's steps, so these tests read the set itself.
@Suite("Python wheel summary labels")
struct Sl3InstallLabelsTests {
    private let set = SummaryLabelSet.installables

    @Test func theSetBelongsToWheelsOnly() {
        #expect(set.formats == [.pythonWheel])
    }

    @Test func everyLabelledFieldHasAKeyAndEveryKeyIsReachable() {
        let labelled = (set.fields([]) ?? []).union(set.fields(["entries", "[]"]) ?? [])
        for field in labelled { #expect(set.keys[field] != nil, "\(field)") }
        #expect(Set(set.keys.keys) == labelled)
    }

    @Test func theWheelsOwnFieldNamesAreTranslatedWithKeysOfTheInstallGroup() {
        let wheelOnly = ["summary", "requiresPython", "dependencies", "license", "wheelVersion", "generator", "pureLibrary",
                         "tags", "commands", "startupFiles", "installedScripts", "nativeModules"]
        for field in wheelOnly {
            #expect(set.keys[field]?.rawValue == "preview.install.\(field)", "\(field)")
        }
    }

    @Test func authorTextAndArchiveValuesAreNeverLabelled() {
        // Values inside lists (requirements, tags, commands, file names) and entry values have no labels.
        for path in [["dependencies", "[]"], ["tags", "[]"], ["commands", "[]"], ["startupFiles", "[]"],
                     ["installedScripts", "[]"], ["entries", "[]", "path"], ["unknown"]] {
            #expect(set.fields(path) == nil, "\(path)")
        }
        for field in ["name", "version", "summary", "requiresPython", "license", "wheelVersion", "generator", "path", "modified"] {
            #expect(set.verbatimFields.contains(field), "\(field)")
        }
    }

    @Test func flagsAndCountsUseTheLocaleAndEntryKindsAreWorded() {
        #expect(set.booleanFields == ["partial", "pureLibrary"])
        #expect(set.countFields == ["listedEntries", "bytes", "nativeModules"])
        #expect(set.valueLabels["type"]?["file"] != nil)
    }
}
