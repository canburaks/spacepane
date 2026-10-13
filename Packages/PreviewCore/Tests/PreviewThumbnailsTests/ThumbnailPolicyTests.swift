import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
import PreviewPreferences
@testable import PreviewThumbnails

@Suite("Thumbnail policy")
struct ThumbnailPolicyTests {
    private let catalog = FormatCatalog.standard

    @Test func missingSettingsAndTheSwitchKeepTheGlyph() {
        #expect(ThumbnailPolicyEvaluator.preflight(preferences: nil) == .settingsUnavailable)
        var off = PreviewPreferencesSnapshot.defaults
        off.showsContentThumbnails = false
        #expect(ThumbnailPolicyEvaluator.preflight(preferences: off) == .contentThumbnailsOff)
        #expect(ThumbnailPolicyEvaluator.preflight(preferences: .defaults) == nil)
    }

    @Test func contentThumbnailsAreOnByDefault() {
        #expect(PreviewPreferencesSnapshot.defaults.showsContentThumbnails)
    }

    @Test func unsupportedAndDisabledTypesNeverDraw() {
        #expect(ThumbnailPolicyEvaluator.resolve(.unsupported, catalog: catalog) == .fallback(.unsupportedType))
        #expect(ThumbnailPolicyEvaluator.resolve(.disabledByUser(.json), catalog: catalog) == .fallback(.disabledByUser))
    }

    @Test func contentPolicyDrawsAndEveryOtherPolicyStaysGeneric() throws {
        for descriptor in catalog.descriptors {
            let decision = ThumbnailPolicyEvaluator.resolve(.enabled(descriptor.id), catalog: catalog)
            if descriptor.thumbnail == .content {
                #expect(decision == .draw(descriptor.id), "\(descriptor.id.rawValue)")
            } else {
                #expect(decision == .fallback(.genericPolicy), "\(descriptor.id.rawValue)")
            }
        }
    }

    @Test func aFormatOutsideTheCatalogStaysGeneric() {
        #expect(ThumbnailPolicyEvaluator.resolve(.enabled(FormatID(rawValue: "test.unknown")), catalog: catalog)
                == .fallback(.genericPolicy))
    }

    @Test func geometryPresentationsNeverDrawEvenIfTheCatalogSaidContent() {
        let descriptor = FormatDescriptor(id: FormatID(rawValue: "test.mesh"), contentTypes: [.data], suffixAliases: ["msh"],
                                          group: .media, presentation: .geometry, thumbnail: .content,
                                          nameKey: "n", descriptionKey: "d")
        let custom = FormatCatalog(descriptors: [descriptor])
        #expect(ThumbnailPolicyEvaluator.resolve(.enabled(descriptor.id), catalog: custom) == .fallback(.genericPolicy))
    }

    /// The formats the decision names as concealed-content thumbnails, and the ones it keeps generic.
    @Test func catalogPolicyMatchesDecision022() throws {
        let content: [FormatID] = [.plainText, .sourceCode, .json, .jsonLines, .yaml, .toml, .markdown, .diff, .xml,
                                   .propertyList, .strings, .stringsDictionary, .opml, .csv, .tsv, .subRip, .webVTT,
                                   .nfo, .jupyterNotebook, .packageJSON, .sqlite]
        for id in content {
            #expect(try #require(catalog.descriptor(for: id)).thumbnail == .content, "\(id.rawValue)")
        }
        let generic: [FormatID] = [.environment, .zip, .tar, .gzip, .xip, .folder, .midi]
        for id in generic {
            #expect(try #require(catalog.descriptor(for: id)).thumbnail == .generic, "\(id.rawValue)")
        }
        #expect(try #require(catalog.descriptor(for: .extensionlessText)).thumbnail == .none)
    }

    @Test func environmentFilesStayGenericWhateverTheSwitch() {
        #expect(ThumbnailPolicyEvaluator.resolve(.enabled(.environment), catalog: catalog) == .fallback(.genericPolicy))
    }

    /// Version 1.0 does not ship the CAD formats; the descriptors kept for their return still draw only a generic glyph.
    @Test func keptCADDescriptorsStayGenericWhateverTheSwitch() throws {
        let cad = try CADCatalogFixture.catalog()
        for id in [FormatID.iges, .step] {
            #expect(try #require(cad.descriptor(for: id)).thumbnail == .generic)
            #expect(ThumbnailPolicyEvaluator.resolve(.enabled(id), catalog: cad) == .fallback(.genericPolicy))
        }
    }
}
