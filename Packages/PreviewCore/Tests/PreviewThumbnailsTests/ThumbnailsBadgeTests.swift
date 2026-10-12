import Foundation
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewThumbnails

/// Decision 027, Q-120: every reply carries a type badge, and the badge is the catalog suffix the file's name
/// matched, never a word taken from the stem. The names below lie on purpose.
@Suite("Thumbnail badge")
struct ThumbnailBadgeTests {
    private let catalog = FormatCatalog.standard

    private func token(_ name: String) -> String? {
        ThumbnailBadge.matching(url: URL(fileURLWithPath: "/tmp/thumbnails/\(name)"), catalog: catalog)?.token
    }

    @Test func theTokenIsTheMatchedSuffixInCapitals() {
        #expect(token("data.json") == "JSON")
        #expect(token("notes.txt") == "TXT")
        #expect(token("README.md") == "MD")
        #expect(token("config.yaml") == "YAML")
        #expect(token("table.csv") == "CSV")
        #expect(token("tool.swift") == "SWIFT")
        #expect(token("bundle.zip") == "ZIP")
        #expect(token("headers.h++") == "H++")
    }

    @Test func aStemThatNamesAnotherTypeNeverDecidesTheBadge() {
        // `report.final.json` is JSON, not FINAL.
        #expect(token("report.final.json") == "JSON")
        #expect(token("json.txt") == "TXT")
        #expect(token("JSON.yaml") == "YAML")
        #expect(token("notes.yaml.txt") == "TXT")
        #expect(token("archive.zip.csv") == "CSV")
        #expect(token("markdown.md") == "MD")
        #expect(token("a.b.c.d.toml") == "TOML")
    }

    @Test func theSuffixIsMatchedWhateverItsCase() {
        #expect(token("DATA.JSON") == "JSON")
        #expect(token("Notes.Md") == "MD")
    }

    @Test func aNameMatchedAsAWholeGivesNoBadge() {
        // The catalog recognized these by their whole name or a name prefix, so no suffix of theirs decided anything.
        for name in ["Dockerfile", "Makefile", "package.json", "tsconfig.json", "tsconfig.base.json", "pipfile.lock",
                     "go.sum", ".env", ".env.local", ".zshrc", "cmakelists.txt"] {
            #expect(token(name) == nil, "\(name)")
        }
    }

    @Test func filesWithoutACatalogSuffixGiveNoBadge() {
        for name in ["README", "photo.png", "scan.pdf", "archive.unknownext", "trailingdot.", ".hidden"] {
            #expect(token(name) == nil, "\(name)")
        }
    }

    @Test func aSuffixTooLongForABadgeIsLeftWithoutOneNotCutShort() {
        #expect(token("Localizable.xcstrings") == nil)
        #expect(token("manifest.webmanifest") == nil)
        #expect(token("embedded.provisionprofile") == nil)
        #expect(token("one.eightchr") == nil)
        #expect(token("tool.swift") != nil)
    }

    @Test func everyCatalogSuffixGivesItsOwnBadgeOrNoneWhenTooLong() {
        var checked = 0
        for descriptor in catalog.descriptors {
            for suffix in descriptor.suffixAliases {
                let badge = ThumbnailBadge.matching(url: URL(fileURLWithPath: "/tmp/thumbnails/sample.\(suffix)"), catalog: catalog)
                if suffix.utf8.count > ThumbnailBadge.maximumLength {
                    #expect(badge == nil, "\(suffix) is longer than \(ThumbnailBadge.maximumLength)")
                } else {
                    #expect(badge?.token == suffix.uppercased(), "\(descriptor.id.rawValue): \(suffix)")
                    // The token is one of the matched descriptor's own suffixes.
                    #expect(descriptor.suffixAliases.contains((badge?.token ?? "").lowercased()), "\(suffix)")
                }
                checked += 1
            }
        }
        #expect(checked > 200, "the catalog's suffixes were all visited")
    }

    @Test func aTokenIsOneToEightLettersDigitsPlusOrMinus() {
        #expect(ThumbnailBadge(token: "json")?.token == "JSON")
        #expect(ThumbnailBadge(token: "C++")?.token == "C++")
        #expect(ThumbnailBadge(token: "a")?.token == "A")
        #expect(ThumbnailBadge(token: "eightchr")?.token == "EIGHTCHR")
        #expect(ThumbnailBadge(token: "") == nil)
        #expect(ThumbnailBadge(token: "ninechars") == nil)
        #expect(ThumbnailBadge(token: "a b") == nil)
        #expect(ThumbnailBadge(token: "a/b") == nil)
        #expect(ThumbnailBadge(token: "é") == nil)
        #expect(ThumbnailBadge(token: "json\n") == nil)
    }
}

/// The badge travels with every outcome of the service, the glyph's included, because the host sets it on every reply.
@Suite("Thumbnail badge on every reply")
struct ThumbnailBadgeServiceTests {
    private func result(_ name: String, text: String = "hello\n", snapshot: PreviewPreferencesSnapshot? = .defaults) async throws -> ThumbnailResult {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file(name, text)
        return await makeService(snapshot: snapshot).result(for: url, geometry: geometry(384))
    }

    @Test func aContentReplyCarriesTheBadgeOfItsSuffix() async throws {
        let reply = try await result("report.final.json", text: "{\n  \"title\": \"Demo\"\n}\n")
        #expect(reply.outcome.scene != nil)
        #expect(reply.badge?.token == "JSON")
    }

    @Test func aStemThatLiesDoesNotChangeTheBadgeOfAContentReply() async throws {
        let reply = try await result("json.txt", text: "{\"a\": 1}\n")
        #expect(reply.outcome.scene != nil)
        #expect(reply.badge?.token == "TXT")
    }

    @Test func aDisabledTypeGetsTheGlyphWithItsBadge() async throws {
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.setEnabled(false, for: .json)
        let reply = try await result("data.json", text: "{\"a\": 1}", snapshot: snapshot)
        #expect(reply.outcome.reason == .disabledByUser)
        #expect(reply.badge?.token == "JSON")
    }

    @Test func theSwitchBeingOffGetsTheGlyphWithItsBadge() async throws {
        var snapshot = PreviewPreferencesSnapshot.defaults
        snapshot.showsContentThumbnails = false
        let reply = try await result("notes.txt", snapshot: snapshot)
        #expect(reply.outcome.reason == .contentThumbnailsOff)
        #expect(reply.badge?.token == "TXT")
    }

    @Test func unreadableSettingsGetTheGlyphWithItsBadge() async throws {
        let reply = try await result("notes.txt", snapshot: nil)
        #expect(reply.outcome.reason == .settingsUnavailable)
        #expect(reply.badge?.token == "TXT")
    }

    @Test func aContentFreeTypeGetsTheGlyphWithItsBadge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("bundle.zip", Data([0x50, 0x4B, 0x05, 0x06]))
        let reply = await makeService().result(for: url, geometry: geometry(384))
        #expect(reply.outcome.reason == .genericPolicy)
        #expect(reply.badge?.token == "ZIP")
    }

    @Test func aWithheldDocumentGetsTheGlyphWithItsBadge() async throws {
        let concealed = try await result("settings.yaml", text: "name: demo\npassword: \(syntheticSecret)\n")
        #expect(concealed.outcome.reason == .withheldConcealedContent)
        #expect(concealed.badge?.token == "YAML")
        // The name decides this one and is never drawn; the badge is still only the suffix.
        let named = try await result("secrets.yaml", text: "name: demo\n")
        #expect(named.outcome.reason == .withheldSecretShape)
        #expect(named.badge?.token == "YAML")
    }

    @Test func aTypeTheCatalogDoesNotKnowHasNoBadge() async throws {
        let reply = try await result("photo.png")
        #expect(reply.outcome.reason == .unsupportedType)
        #expect(reply.badge == nil)
    }

    @Test func aCancelledRequestStillCarriesTheBadge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "hello\n")
        let subject = makeService()
        let task = Task { () -> ThumbnailResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return await subject.result(for: url, geometry: geometry(384))
        }
        let reply = await task.value
        #expect(reply.outcome.reason == .cancelled)
        #expect(reply.badge?.token == "TXT")
    }

    @Test func theBadgeForAUrlIsTheSameWhateverTheOutcome() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("report.final.json", "{\"a\": 1}\n")
        let subject = makeService()
        let reply = await subject.result(for: url, geometry: geometry(384))
        #expect(subject.badge(for: url) == reply.badge)
        #expect(subject.badge(for: url)?.token == "JSON")
        #expect(subject.badge(for: fixture.directory.appendingPathComponent("missing")) == nil)
    }
}
