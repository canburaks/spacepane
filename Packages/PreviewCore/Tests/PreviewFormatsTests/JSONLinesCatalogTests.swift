import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts

private let jsonLinesID = FormatID(rawValue: "data.json-lines")

@Test(arguments: ["jsonl", "ndjson", "JSONL", "NDJSON"])
func JSONLinesAliasesKeepIndependentIdentity(suffix: String) {
    let catalog = FormatCatalog.standard
    let url = URL(fileURLWithPath: "/unused/sample.\(suffix)")
    #expect(catalog.classify(url: url, contentType: .plainText) == jsonLinesID)
    #expect(catalog.classify(url: url, contentType: .json) == jsonLinesID)
}

@Test func JSONLinesCatalogLoadsWithoutRegisteredHostAndDoesNotConformToJSON() throws {
    let descriptor = try #require(FormatCatalog.standard.descriptor(for: jsonLinesID))
    #expect(descriptor.canonicalContentType.identifier == "org.jsonlines.jsonl")
    #expect(!descriptor.canonicalContentType.conforms(to: .json))
    #expect(descriptor.group == .structured)
    #expect(descriptor.presentation == .text)
    // Decision 022: concealed content thumbnails, still gated by the user's switches.
    #expect(descriptor.thumbnail == .content)
    #expect(descriptor.suffixAliases == ["jsonl", "ndjson"])
}

@Test func JSONLinesExactTypesRemainIndependentOfGenericText() throws {
    let catalog = FormatCatalog.standard
    let descriptor = try #require(catalog.descriptor(for: jsonLinesID))
    let noAlias = URL(fileURLWithPath: "/unused/records")
    #expect(catalog.classify(url: noAlias, contentType: descriptor.canonicalContentType) == jsonLinesID)
    if let ndjson = UTType("public.ndjson") {
        #expect(catalog.classify(url: noAlias, contentType: ndjson) == jsonLinesID)
        #expect(!ndjson.conforms(to: .json))
    }
}

@Test func catalogSelectsMostSpecificDeclaredConformance() {
    let specificID = FormatID(rawValue: "test.specific-text")
    let catalog = FormatCatalog(descriptors: [
        FormatDescriptor(id: .plainText, contentTypes: [.text], suffixAliases: [], group: .text,
                         nameKey: "test.generic.name", descriptionKey: "test.generic.description"),
        FormatDescriptor(id: specificID, contentTypes: [.plainText], suffixAliases: [], group: .text,
                         nameKey: "test.specific.name", descriptionKey: "test.specific.description")
    ])
    #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/source"), contentType: .utf8PlainText) == specificID)
}
