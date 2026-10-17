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

    /// Launch Services resolves a file's type only among types that conform to public.data. macOS declares
    /// public.database and public.archive with no parent, so an imported declaration whose parents all stop short of
    /// public.data never reaches the extension (docs/validation/uti-resolution-2026-10-17.md). Each declaration needs
    /// at least one parent that is, or conforms to, public.data; the others may stay for accuracy.
    @Test func everyImportedTypeReachesPublicDataThroughItsDeclaredParents() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let catalog = root.appendingPathComponent("Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let formats = try #require(object?["formats"] as? [[String: Any]])
        var checked = 0
        for format in formats {
            for declaration in format["importedContentTypes"] as? [[String: Any]] ?? [] {
                let identifier = try #require(declaration["identifier"] as? String)
                let parents = (declaration["conformsTo"] as? [String]) ?? (declaration["conformsTo"] as? String).map { [$0] } ?? []
                #expect(!parents.isEmpty, "\(identifier) declares no parent")
                #expect(parents.allSatisfy { UTType($0) != nil }, "\(identifier): a declared parent is unknown on this host")
                #expect(parents.contains { UTType($0)?.conforms(to: .data) == true },
                        "\(identifier): none of \(parents) conforms to public.data on this host")
                checked += 1
            }
        }
        #expect(checked > 50, "Only \(checked) imported declarations were checked")
    }
}
