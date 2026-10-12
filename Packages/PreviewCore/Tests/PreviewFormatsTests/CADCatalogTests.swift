import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts

@Test(arguments: ["igs", "iges", "IGS", "IGES", "stp", "step", "STP", "STEP"])
func CADAliasesKeepIndependentIdentityAheadOfTextFallback(suffix: String) {
    let expected = FormatID(rawValue: suffix.lowercased().hasPrefix("ig") ? "cad.iges" : "cad.step")
    #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model.\(suffix)"),
                                          contentType: .plainText) == expected)
}

@Test func CADUsesExplicitImportedTypesAndGenericThumbnails() throws {
    for rawID in ["cad.iges", "cad.step"] {
        let id = FormatID(rawValue: rawID)
        let descriptor = try #require(FormatCatalog.standard.descriptor(for: id))
        #expect(descriptor.group == .media)
        #expect(descriptor.presentation.rawValue == "geometry")
        #expect(descriptor.thumbnail == .generic)
        #expect(!descriptor.defaultEnabled)
        #expect(descriptor.canonicalContentType.identifier.hasPrefix("org.webmeister.spacepane.type."))
        #expect(!descriptor.canonicalContentType.conforms(to: .plainText))
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model"),
                                               contentType: descriptor.canonicalContentType) == id)
    }
    // Plain data identifies only a file without an extension; it never reaches a CAD type.
    #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model"), contentType: .data) == .extensionlessText)
    #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model.unknownsuffix"), contentType: .data) == nil)
}

@Test func CatalogDefaultEnablementHasOneOwnerAndPreservesExistingTypes() {
    #expect(FormatID.iges.rawValue == "cad.iges")
    #expect(FormatID.step.rawValue == "cad.step")
    for descriptor in FormatCatalog.standard.descriptors {
        #expect(descriptor.defaultEnabled == ![FormatID.iges, .step].contains(descriptor.id))
        #expect(PreviewPreferencesSnapshot.defaults.isEnabled(descriptor.id) == descriptor.defaultEnabled)
    }
}
