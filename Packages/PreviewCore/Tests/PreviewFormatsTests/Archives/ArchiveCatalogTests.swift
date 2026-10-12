import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewFormats

@Suite("Archive family catalog")
struct ArchiveCatalogTests {
    private let archiveIDs: [FormatID] = [.rar, .sevenZip, .bzip2, .xz]

    @Test func everyArchiveFormatHasADescriptorWithAGenericThumbnailAndOneRegistration() throws {
        let registered = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for id in archiveIDs {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: id), "\(id.rawValue)")
            #expect(descriptor.thumbnail == .generic)
            #expect(descriptor.group == .containers)
            #expect(descriptor.defaultEnabled)
            #expect(descriptor.nameKey == "format.\(id.rawValue).name")
            #expect(registered.contains(id))
        }
        #expect(registered.count == StandardFormatAdapters.registrations.count)
    }

    @Test func formatIdentifiersAreTheStablePersistedSpellings() {
        #expect(archiveIDs.map(\.rawValue) == ["archive.rar", "archive.7z", "archive.bzip2", "archive.xz"])
    }

    @Test(arguments: [
        ("a.rar", "archive.rar"), ("A.RAR", "archive.rar"), ("a.7z", "archive.7z"),
        ("a.bz2", "archive.bzip2"), ("a.tbz", "archive.bzip2"), ("a.tbz2", "archive.bzip2"), ("a.tar.bz2", "archive.bzip2"),
        ("a.xz", "archive.xz"), ("a.txz", "archive.xz"), ("a.tar.xz", "archive.xz"),
        ("a.jar", "archive.zip"), ("a.war", "archive.zip"), ("a.zip", "archive.zip"), ("a.tgz", "archive.gzip")
    ])
    func suffixesSelectTheirOwnFormat(name: String, expected: String) {
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/\(name)"))?.rawValue == expected)
    }

    @Test func javaArchivesUseTheSystemDeclaredTypesOnlyWhereTheyExist() throws {
        let zip = try #require(FormatCatalog.standard.descriptor(for: .zip))
        #expect(zip.contentTypes.map(\.identifier).contains("com.sun.java-archive"))
        #expect(zip.contentTypes.map(\.identifier).contains("com.sun.web-application-archive"))
        // No system type declares .ear, so it is not routed; a dynamic type must not be claimed.
        #expect(!zip.suffixAliases.contains("ear"))
    }

    @Test func archiveTypesDoNotClaimGenericRootTypes() {
        let forbidden: Set<UTType> = [.data, .item, .content, .archive]
        for id in archiveIDs {
            let types = Set(FormatCatalog.standard.descriptor(for: id)?.contentTypes ?? [])
            #expect(types.isDisjoint(with: forbidden))
        }
    }

    @Test func tarVariantsInsideBzip2AndXzAreRoutedByTheirOwnTypes() {
        let bzip2 = FormatCatalog.standard.descriptor(for: .bzip2)
        let xz = FormatCatalog.standard.descriptor(for: .xz)
        #expect(bzip2?.contentTypes.map(\.identifier) == ["public.bzip2-archive", "public.tar-bzip2-archive"])
        #expect(xz?.contentTypes.map(\.identifier) == ["org.tukaani.xz-archive", "org.tukaani.tar-xz-archive"])
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/noext"), contentType: UTType("public.tar-bzip2-archive")) == .bzip2)
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/noext"), contentType: UTType("org.tukaani.tar-xz-archive")) == .xz)
    }

    @Test func rarUsesAnAppSelectedImportedTypeBecauseTheSystemDeclaresNone() throws {
        let descriptor = try #require(FormatCatalog.standard.descriptor(for: .rar))
        #expect(descriptor.canonicalContentType.identifier == "org.webmeister.spacepane.type.rar")
        #expect(descriptor.suffixAliases == ["rar"])
    }
}
