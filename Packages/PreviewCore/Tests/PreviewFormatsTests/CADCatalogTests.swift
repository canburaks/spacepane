import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewTestSupport

// Version 1.0 ships without the IGES and STEP previews, so these tests run against the product catalog plus the two
// descriptors kept in `Configuration/CADFormatCatalogEntries.json`: what the catalog must do when they return.

@Test(arguments: ["igs", "iges", "IGS", "IGES", "stp", "step", "STP", "STEP"])
func CADAliasesKeepIndependentIdentityAheadOfTextFallback(suffix: String) throws {
    let catalog = try CADCatalogFixture.catalog()
    let expected = FormatID(rawValue: suffix.lowercased().hasPrefix("ig") ? "cad.iges" : "cad.step")
    #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/model.\(suffix)"), contentType: .plainText) == expected)
}

@Test func CADUsesExplicitImportedTypesAndGenericThumbnails() throws {
    let catalog = try CADCatalogFixture.catalog()
    for rawID in ["cad.iges", "cad.step"] {
        let id = FormatID(rawValue: rawID)
        let descriptor = try #require(catalog.descriptor(for: id))
        #expect(descriptor.group == .media)
        #expect(descriptor.presentation.rawValue == "geometry")
        #expect(descriptor.thumbnail == .generic)
        #expect(!descriptor.defaultEnabled)
        #expect(descriptor.canonicalContentType.identifier.hasPrefix("org.webmeister.spacepane.type."))
        #expect(!descriptor.canonicalContentType.conforms(to: .plainText))
        #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/model"),
                                 contentType: descriptor.canonicalContentType) == id)
    }
    // Plain data identifies only a file without an extension; it never reaches a CAD type.
    #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/model"), contentType: .data) == .extensionlessText)
    #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/model.unknownsuffix"), contentType: .data) == nil)
}

@Test func CatalogDefaultEnablementHasOneOwnerAndPreservesExistingTypes() throws {
    let catalog = try CADCatalogFixture.catalog()
    #expect(CADTestFormatIDs.iges.rawValue == "cad.iges")
    #expect(CADTestFormatIDs.step.rawValue == "cad.step")
    #expect(catalog.descriptors.count == FormatCatalog.standard.descriptors.count + 2)
    for descriptor in catalog.descriptors {
        #expect(descriptor.defaultEnabled == ![CADTestFormatIDs.iges, CADTestFormatIDs.step].contains(descriptor.id))
        #expect(PreviewPreferencesSnapshot.defaults.isEnabled(descriptor.id, catalog: catalog) == descriptor.defaultEnabled)
    }
}

@Test func theKeptCADEntriesAreOnlyTheTwoCADDescriptorsInTheirCatalogOrder() throws {
    let entries = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: CADCatalogFixture.entriesURL)) as? [[String: Any]])
    #expect(entries.compactMap { $0["id"] as? String } == ["cad.iges", "cad.step"])
    let catalog = try CADCatalogFixture.catalog()
    #expect(catalog.unresolvedContentTypes.isEmpty)
}

// MARK: - Version 1.0 truth

@Test func theProductCatalogHasEightyOneFormatsAndNoCADFormat() {
    let descriptors = FormatCatalog.standard.descriptors
    // 74 in build 3, plus the seven formats of decision 030.
    #expect(descriptors.count == 81)
    #expect(!descriptors.contains { $0.id.rawValue.hasPrefix("cad.") })
    #expect(FormatCatalog.standard.descriptor(for: CADTestFormatIDs.iges) == nil)
    #expect(FormatCatalog.standard.descriptor(for: CADTestFormatIDs.step) == nil)
}

@Test func theMeshFormatsStayInTheProductCatalogWithTheGeometryViewer() throws {
    for id in ["model.stl", "model.obj", "model.ply", "model.3mf"] {
        let descriptor = try #require(FormatCatalog.standard.descriptor(for: FormatID(rawValue: id)))
        #expect(descriptor.presentation == .geometry)
        #expect(descriptor.primaryView == .geometry)
    }
}

@Test func noCatalogFormatClaimsASTEPOrIGESSuffixOrType() {
    let claimed = FormatCatalog.standard.descriptors.flatMap { $0.suffixAliases.map { $0.lowercased() } }
    for suffix in ["step", "stp", "igs", "iges"] { #expect(!claimed.contains(suffix)) }
    for descriptor in FormatCatalog.standard.descriptors {
        #expect(!descriptor.canonicalContentType.identifier.hasSuffix(".step"))
        #expect(!descriptor.canonicalContentType.identifier.hasSuffix(".iges"))
    }
    for suffix in ["step", "stp", "igs", "iges"] {
        // A suffix the catalog does not know, with the plain data type a file of that kind resolves to.
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model.\(suffix)"), contentType: .data) == nil)
    }
}

@Test func theGeneratedExtensionManifestsDeclareNoSTEPOrIGESContentType() throws {
    for name in ["Preview-Info.plist", "Thumbnail-Info.plist", "App-Info.plist"] {
        let data = try Data(contentsOf: RepositoryFile.url("Configuration/\(name)"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("org.webmeister.spacepane.type.step"), "\(name)")
        #expect(!text.contains("org.webmeister.spacepane.type.iges"), "\(name)")
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        if name != "App-Info.plist" {
            let extensionInfo = try #require((plist["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any])
            let declared = try #require(extensionInfo["QLSupportedContentTypes"] as? [String])
            #expect(!declared.isEmpty, "\(name)")
            #expect(declared.allSatisfy { !$0.hasSuffix(".step") && !$0.hasSuffix(".iges") }, "\(name)")
        }
        for declaration in plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? [] {
            let tags = (declaration["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String] ?? []
            #expect(Set(tags.map { $0.lowercased() }).isDisjoint(with: ["step", "stp", "igs", "iges"]), "\(name)")
        }
    }
}
