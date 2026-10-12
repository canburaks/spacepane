import Testing
import PreviewContracts

/// The catalog's `primaryView` field (decision 027, Q-32; owner decision D1). The renderer-side drift test
/// (`CatalogPrimaryViewDriftTests`) checks the values against the mode policy; this one checks the shape.
struct CatalogPrimaryViewTests {
    @Test func geometryFormatsAndOnlyTheyOpenInTheViewport() {
        for descriptor in FormatCatalog.standard.descriptors {
            #expect((descriptor.presentation == .geometry) == (descriptor.primaryView == .geometry),
                    "\(descriptor.id.rawValue): \(descriptor.presentation) opens in \(descriptor.primaryView)")
        }
    }

    @Test func theFamiliesOpenWhereTheirDecisionsPutThem() {
        let catalog = FormatCatalog.standard
        #expect(catalog.descriptor(for: FormatID(rawValue: "data.csv"))?.primaryView == .table)
        #expect(catalog.descriptor(for: FormatID(rawValue: "archive.zip"))?.primaryView == .files)
        #expect(catalog.descriptor(for: FormatID(rawValue: "package.application"))?.primaryView == .summary)
        #expect(catalog.descriptor(for: FormatID(rawValue: "text.markdown"))?.primaryView == .rendered)
        #expect(catalog.descriptor(for: FormatID(rawValue: "archive.comic-book"))?.primaryView == .pages)
        #expect(catalog.descriptor(for: FormatID(rawValue: "model.stl"))?.primaryView == .geometry)
        // Owner decision D1 is implemented only after the Wave 1 measurement: until then these open in Source.
        #expect(catalog.descriptor(for: FormatID(rawValue: "data.json"))?.primaryView == .source)
        #expect(catalog.descriptor(for: FormatID(rawValue: "data.json-lines"))?.primaryView == .source)
    }

    @Test func everyViewNameIsAStableWireValue() {
        #expect(PrimaryView.allCases.map(\.rawValue) == ["source", "outline", "records", "rendered", "summary", "table",
                                                          "rows", "plot", "files", "pages", "diagram", "geometry"])
        let fallback = FormatDescriptor(id: FormatID(rawValue: "test.plain"), contentTypes: [.plainText],
                                        suffixAliases: ["tst"], group: .text, nameKey: "n", descriptionKey: "d")
        #expect(fallback.primaryView == .source)
    }
}
