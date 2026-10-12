import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewThumbnails

/// URL credentials are concealed by the shared privacy stage in every text format, so a document that holds one
/// counts as having concealed values and its thumbnail is withheld whole. Before the shared pattern only the
/// code, log and INI adapters concealed them, and the other formats drew the password into Finder's durable cache.
@Suite("URL credentials and content thumbnails")
struct URLCredentialThumbnailTests {
    private static let database = "postgres://app:\(syntheticSecret)@db.example.test:5432/main"
    private static let mirror = "ssh://git@git.example.test/team/repo.git"

    private static let files: [(name: String, text: String)] = [
        ("settings.yaml", "name: demo\ndatabase_url: \(database)\nmirror_url: \(mirror)\n"),
        ("project.toml", "[package]\nname = \"demo\"\ndatabase_url = \"\(database)\"\n"),
        ("data.json", "{\"name\":\"demo\",\"database_url\":\"\(database)\"}"),
        ("README.md", "# Guide\n\nConnect with [the database](\(database)).\n"),
        ("notes.txt", "remember\nconnect with \(database)\n"),
        ("people.csv", "name,url\nAda,\(database)\nBob,\(mirror)\n"),
        ("nb.ipynb", "{\"cells\":[{\"cell_type\":\"code\",\"metadata\":{},\"outputs\":[],\"execution_count\":null,\"source\":[\"engine = connect('\(database)')\"]}],\"metadata\":{},\"nbformat\":4,\"nbformat_minor\":5}")
    ]

    @Test func aYAMLFileWithURLCredentialsIsWithheldWhole() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("settings.yaml", "name: demo\ndatabase_url: \(Self.database)\n")
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.reason == .withheldConcealedContent, "\(String(describing: outcome.scene?.content.drawnStrings))")
    }

    @Test(arguments: files.map(\.name))
    func everyTextFormatWithURLCredentialsIsWithheldWhole(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try #require(Self.files.first { $0.name == name }).text
        let url = try fixture.file(name, text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.reason == .withheldConcealedContent, "\(name): \(String(describing: outcome.scene?.content.drawnStrings))")
    }

    /// Even when the withholding limit is lifted, only the pipeline's concealed text reaches the page.
    @Test(arguments: files.map(\.name))
    func theCredentialIsNeverInAnyDrawnString(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try #require(Self.files.first { $0.name == name }).text
        let url = try fixture.file(name, text)
        var limits = relaxedLimits
        limits.maximumConcealedValues = .max
        let outcome = await makeService(limits: limits).outcome(for: url, geometry: geometry(512))
        if let scene = outcome.scene {
            for drawn in scene.content.drawnStrings { #expect(!drawn.contains(syntheticSecret), "\(name): \(drawn)") }
        }
    }

    /// An address without a password is not a secret: nothing is concealed, so the concealment rule does not
    /// withhold the file. (A thumbnail-only secret-shape check belongs to the thumbnail service, not to this rule.)
    @Test func addressesWithoutAPasswordAreNotWithheldAsConcealedContent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("settings.yaml",
                                   "name: demo\ndatabase_url: postgres://db.example.test:5432/main\nmirror_url: \(Self.mirror)\n")
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.reason != .withheldConcealedContent, "\(String(describing: outcome.reason))")
    }
}
