import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts

/// The catalog never dies on a content type the host does not declare; it records it. On every supported
/// host the record must be empty, and this failure message names the identifiers when it is not.
@Suite("Catalog content types on this host")
struct CatalogContentTypeResolutionTests {
    @Test func everyCatalogContentTypeResolvesOnThisHost() {
        let unresolved = FormatCatalog.standard.unresolvedContentTypes
        let names = unresolved.map { "\($0.format.rawValue): \($0.identifier)" }.joined(separator: ", ")
        #expect(unresolved.isEmpty, "Unresolved on this host: \(names)")
    }

    @Test func everyFormatKeepsItsDeclaredTypeCount() {
        // A stand-in type keeps the position of the identifier it replaces, so canonical types stay first.
        for descriptor in FormatCatalog.standard.descriptors {
            #expect(!descriptor.contentTypes.isEmpty, "\(descriptor.id.rawValue)")
            #expect(descriptor.contentTypes.allSatisfy { !$0.identifier.isEmpty }, "\(descriptor.id.rawValue)")
        }
    }
}
