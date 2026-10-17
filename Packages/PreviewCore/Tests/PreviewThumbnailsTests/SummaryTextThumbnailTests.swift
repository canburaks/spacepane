import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewThumbnails

/// Decision 027, Q-10: a thumbnail never draws app-made summary text. A summary is the JSON an adapter
/// writes about a binary, a database or a container; it carries English schema keys that nothing
/// localizes and is not the document's own words. Only the document's pictures may stand for such a file,
/// and otherwise the request declines with `ThumbnailFallbackReason.summaryText`.
@Suite("Summary text thumbnails")
struct SummaryTextThumbnailTests {
    private static let summaryJSON = """
    {
      "dataFormat": "Parquet",
      "formatVersion": 2,
      "rowCount": 3
    }
    """

    /// A service whose plain-text adapter returns a fixed document of the given origin, so the whole
    /// pipeline (classification, concealment, origin hand-over) runs and only the parser is replaced.
    private func service(origin: TextOrigin, text: String = SummaryTextThumbnailTests.summaryJSON,
                         syntax: TextSyntax = .json, images: [PreviewImage] = []) -> ContentThumbnailService {
        let document = ParsedTextDocument(text: text, syntax: syntax, images: images, origin: origin)
        let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .plainText }
            + [AdapterRegistration(formatID: .plainText) { FixedAdapter(document: document) }]
        return makeService(registrations: registrations)
    }

    private func picture(_ role: PreviewImage.Role, side: Int = 40) -> PreviewImage {
        PreviewImage(data: syntheticImage(width: side, height: side), pixelWidth: side, pixelHeight: side, role: role)
    }

    @Test func aSummaryWithoutPicturesDeclinesWithSummaryText() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("summary.txt", "ignored")
        let outcome = await service(origin: .summary).outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene == nil, "\(String(describing: outcome.scene?.content.drawnStrings))")
        #expect(outcome.reason == .summaryText)
    }

    @Test(arguments: [PreviewImage.Role.cover, .icon, .page, .figure])
    func aSummaryWithADecodablePictureDrawsThePicture(role: PreviewImage.Role) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("summary.txt", "ignored")
        let outcome = await service(origin: .summary, images: [picture(role)]).outcome(for: url, geometry: geometry(128))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        guard case .picture(let drawn) = scene.content else { Issue.record("expected a picture"); return }
        #expect(drawn.role == role)
        // The picture stands alone: not one summary key or value reaches the page.
        #expect(scene.content.drawnStrings.isEmpty)
    }

    @Test func aSummaryPrefersACoverToAFigureLikeAnyDocument() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("summary.txt", "ignored")
        let images = [picture(.figure), picture(.cover, side: 30)]
        let scene = try #require(await service(origin: .summary, images: images).outcome(for: url, geometry: standardGeometry).scene)
        guard case .picture(let drawn) = scene.content else { Issue.record("expected a picture"); return }
        #expect(drawn.role == .cover)
    }

    @Test func aSummaryWhosePicturesDoNotDecodeStillDeclinesInsteadOfDrawingText() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("summary.txt", "ignored")
        let broken = PreviewImage(data: Data("not an image".utf8), pixelWidth: 10, pixelHeight: 10, role: .cover)
        let outcome = await service(origin: .summary, images: [broken]).outcome(for: url, geometry: standardGeometry)
        #expect(outcome.scene == nil, "\(String(describing: outcome.scene?.content.drawnStrings))")
        #expect(outcome.reason == .summaryText)
    }

    @Test func aSummaryNeverDrawsEvenWhenItsTextLooksLikeAnOrdinaryDocument() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("summary.txt", "ignored")
        let outcome = await service(origin: .summary, text: "Meeting notes\nbuy milk and eggs\n", syntax: .plain)
            .outcome(for: url, geometry: standardGeometry)
        #expect(outcome.reason == .summaryText)
    }

    @Test func aSourcePresentationStillYieldsText() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "ignored")
        let outcome = await service(origin: .source, text: "Meeting notes\nbuy milk and eggs\n", syntax: .plain)
            .outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(String(describing: outcome.reason))")
        guard case .text = scene.content else { Issue.record("expected a text page"); return }
        #expect(scene.content.drawnStrings.contains { $0.contains("Meeting notes") })
    }

    /// Only a summary is declined: text the file itself holds, regenerated from it or converted from another
    /// representation of it is still the document and is still drawn.
    @Test(arguments: [TextOrigin.source, .reformatted, .converted])
    func everyOriginButSummaryDrawsItsText(origin: TextOrigin) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "ignored")
        let outcome = await service(origin: origin, text: "Meeting notes\nbuy milk and eggs\n", syntax: .plain)
            .outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene, "\(origin): \(String(describing: outcome.reason))")
        #expect(scene.content.drawnStrings.contains { $0.contains("Meeting notes") }, "\(origin)")
    }

    // MARK: The builder alone

    private func presentation(_ text: String, format: FormatID = .plainText, origin: TextOrigin) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                         redactionCount: 0, origin: origin)
    }

    @Test func theBuilderRefusesASummaryByItself() {
        #expect(ThumbnailContentBuilder.textContent(for: presentation("alpha beta", origin: .summary), metrics: metrics(384)) == nil)
        #expect(ThumbnailContentBuilder.textContent(for: presentation(Self.summaryJSON, origin: .summary), metrics: metrics(384)) == nil)
        // A database summary, which the builder once drew as a grid of its first rows, is refused too.
        let database = presentation(#"{"databaseFormat":"SQLite","pages":[{"table":"t","columns":["a"],"rows":[{"a":{"value":"1"}}]}]}"#,
                                    format: .sqlite, origin: .summary)
        #expect(ThumbnailContentBuilder.textContent(for: database, metrics: metrics(384)) == nil)
        #expect(ThumbnailContentBuilder.textContent(for: presentation("alpha beta", origin: .source), metrics: metrics(384)) != nil)
    }
}

/// The real adapters that write summaries, through the real pipeline and the real service. A fixed adapter
/// proves the rule; these prove that each family's adapter hands the origin over to it.
@Suite("Real summary adapters through the thumbnail service")
struct RealSummaryAdapterThumbnailTests {
    /// A 3 x 4 float64 array, as the data pipeline tests use it.
    private static let numpyArray = Data(base64Encoded: "k05VTVBZAQB2AHsnZGVzY3InOiAnPGY4JywgJ2ZvcnRyYW5fb3JkZXInOiBGYWxzZSwgJ3NoYXBlJzogKDMsIDQpLCB9ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAoAAAAAAAAAAJqZmZmZmbk/mpmZmZmZyT8zMzMzMzPTPwAAAAAAAPA/mpmZmZmZ8T8zMzMzMzPzP83MzMzMzPQ/AAAAAAAAAEDNzMzMzMwAQJqZmZmZmQFAZmZmZmZmAkA=")!

    @Test func aNumPyArrayDrawsAShapeWithoutItsSummaryOrValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("matrix.npy", Self.numpyArray)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        let scene = try #require(outcome.scene)
        guard case .grid(let grid) = scene.content else { Issue.record("Expected value-free NumPy grid"); return }
        #expect(grid.headers.isEmpty)
        #expect(grid.columnCount == 4 && grid.rowCount == 3)
        #expect(scene.content.drawnStrings == [grid.countLine])
    }

    /// An application's summary comes from `PackageSummary.document`, which builds its own document from the
    /// summary writer's text; this proves that hand-over keeps the writer's origin. Since 2026-10-17 the shipped
    /// catalog gives application bundles the `generic` policy, so the thumbnail extension never registers them
    /// (decision 022); this test admits them with the `content` policy to keep checking the pipeline behind it.
    @Test func anApplicationBundleWithoutAnIconIsDeclinedNotDrawnAsItsSummary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundle = fixture.directory.appendingPathComponent("Synthetic.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleName": "Synthetic", "CFBundleIdentifier": "com.example.synthetic", "CFBundleExecutable": "Synthetic"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try Data("not a mach-o".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/Synthetic"))
        let catalog = FormatCatalog(descriptors: FormatCatalog.standard.descriptors.map { descriptor in
            guard descriptor.id == .applicationBundle else { return descriptor }
            return FormatDescriptor(id: descriptor.id, contentTypes: descriptor.contentTypes,
                suffixAliases: descriptor.suffixAliases, group: descriptor.group,
                presentation: descriptor.presentation, thumbnail: .content,
                nameKey: descriptor.nameKey, descriptionKey: descriptor.descriptionKey,
                filenameAliases: descriptor.filenameAliases, filenamePrefixes: descriptor.filenamePrefixes,
                defaultEnabled: descriptor.defaultEnabled, primaryView: descriptor.primaryView)
        }, unresolvedContentTypes: FormatCatalog.standard.unresolvedContentTypes)
        let service = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
                                              preferences: .fixed(.defaults), catalog: catalog, limits: relaxedLimits)
        let outcome = await service.outcome(for: bundle, geometry: geometry(384))
        #expect(outcome.scene == nil, "\(String(describing: outcome.scene?.content.drawnStrings))")
        #expect(outcome.reason == .summaryText)
    }
}
