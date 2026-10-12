import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewThumbnails

/// Synthetic documents shared by the pure and the end-to-end suites. Nothing here is a real credential.
enum SecretShapeSamples {
    static let readme = "# Project\n\nA short paragraph with **bold** text and a [link](https://example.invalid/docs).\n\n- first\n- second\n"
    static let swiftSource = "import Foundation\n\nstruct Point {\n    var x: Int\n    var y: Int\n}\n\nlet origin = Point(x: 0, y: 0)\nprint(\"Hello, \\(origin)\")\n"
    static let csv = "id,name,city\n1,Ada Lovelace,London\n2,Grace Hopper,New York\n3,Alan Turing,Wilmslow\n"
    static let gitLog = "commit 3f2a9c1d8e7b6a5f4c3d2e1f0a9b8c7d6e5f4a3b\nAuthor: Ada <ada@example.invalid>\n\n    Fix the thing\n"
    /// 32 ASCII letters and digits mixing both cases: the shortest run the rule withholds.
    static let tokenLikeRun = "aB3aB3aB3aB3aB3aB3aB3aB3aB3aB3aB"
}

/// Decision 027, D14 (Q-17): a thumbnail is withheld, before anything is drawn, when its concealed text or its
/// file name still looks credential-bearing. The rule is deliberately over-inclusive (a false positive costs
/// the glyph, a miss reaches Finder's durable cache) but must not withhold ordinary documents.
@Suite("Thumbnail secret shape")
struct ThumbnailSecretShapeTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        var testDescription: String { name }
    }

    private func mayHold(_ text: String, fileName: String = "notes.txt", parent: String? = "Documents") -> Bool {
        ThumbnailSecretShape.mayHoldSecret(Substring(text), fileName: fileName, parentFolderName: parent)
    }

    // MARK: Text

    static let withheldText: [Case] = [
        Case(name: "user and password in a URL", text: "DATABASE_URL = postgres://app:synthetic-password@db.internal:5432/app"),
        Case(name: "an empty user with a password", text: "cache: redis://:synthetic-password@cache.internal:6379"),
        Case(name: "credentials in a quoted https URL", text: "remote: \"https://deploy:synthetic-password@example.invalid/repo.git\""),
        Case(name: "a password with punctuation", text: "mongodb://app:p%40ss.w0rd!*@db.internal/app"),
        Case(name: "a private key block", text: "-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----\n"),
        Case(name: "a certificate marker", text: "-----BEGIN CERTIFICATE-----"),
        Case(name: "a marker after more dashes", text: "------BEGIN OPENSSH PRIVATE KEY------"),
        Case(name: "the base64 marker alone", text: "data: LS0tLS1CRUdJTi"),
        Case(name: "a base64 encoded private key", text: "data: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCg=="),
        Case(name: "a 32 character mixed run", text: "build: aB3aB3aB3aB3aB3aB3aB3aB3aB3aB3aB"),
        Case(name: "a token that starts with a digit", text: "build: 7Qx4Lm9Rt2Vw6Yb1Nc5Hd8Jf3Pg0KsZa4Xe7Uo"),
        Case(name: "a base64 payload without separators", text: "blob: Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MEFCQ0RFRkdISUpL"),
        Case(name: "a token in the middle of prose", text: "Deploy notes: use the key 9Zk3Qx7Lm2Rt6Vw1Yb5Nc8Hd4Jf0PgKsXe afterward.")
    ]

    static let drawnText: [Case] = [
        Case(name: "a README", text: "# Project\n\nA short paragraph with **bold** text and a [link](https://example.invalid/docs).\n\n- first\n- second\n"),
        Case(name: "Swift source", text: "import Foundation\n\nstruct Point {\n    var x: Int\n    var y: Int\n}\n\nlet origin = Point(x: 0, y: 0)\nprint(\"Hello, \\(origin)\")\n"),
        Case(name: "a CSV of names", text: "id,name,city\n1,Ada Lovelace,London\n2,Grace Hopper,New York\n3,Alan Turing,Wilmslow\n"),
        Case(name: "a git commit hash in a log", text: "commit 3f2a9c1d8e7b6a5f4c3d2e1f0a9b8c7d6e5f4a3b\nAuthor: Ada <ada@example.invalid>\n\n    Fix the thing\n"),
        Case(name: "an upper-case SHA-256 digest", text: "sha256: E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"),
        Case(name: "a lower-case SHA-256 digest", text: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        Case(name: "a lower-case UUID", text: "id: 8f0c5a1e-3b2d-4c6f-9a7e-1d2c3b4a5f60"),
        Case(name: "an upper-case UUID", text: "id: 8F0C5A1E-3B2D-4C6F-9A7E-1D2C3B4A5F60"),
        Case(name: "an SSH URL with a user and no password", text: "git clone ssh://git@github.invalid/owner/repo.git"),
        Case(name: "a URL with a port and no user information", text: "Open https://example.invalid:8443/path?query=1 in a browser."),
        Case(name: "an address after a URL in prose", text: "Visit http://localhost:3000 or write to me@example.invalid."),
        Case(name: "a long identifier without digits", text: "let thisIdentifierIsDeliberatelyLongWithoutAnyDigitsAtAll = 1"),
        Case(name: "a long lower-case word with digits", text: "aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd12"),
        Case(name: "a mixed run one character short", text: "build: aB3aB3aB3aB3aB3aB3aB3aB3aB3aB3a"),
        Case(name: "mixed runs broken by hyphens", text: "ABC123def-ABC123def-ABC123def-ABC123def-ABC123def"),
        Case(name: "a marker with four dashes", text: "----BEGIN PRIVATE KEY----"),
        Case(name: "a lower-case marker", text: "-----begin private key-----"),
        Case(name: "BEGIN in SQL", text: "BEGIN\n  SELECT 1;\nEND;"),
        Case(name: "a truncated base64 marker", text: "LS0tLS1CRUd"),
        Case(name: "empty text", text: ""),
        Case(name: "non-ASCII prose", text: "Größe: 42 — 日本語のテキスト and Ελληνικά")
    ]

    @Test(arguments: withheldText)
    func textThatLooksCredentialBearingIsWithheld(sample: Case) {
        #expect(mayHold(sample.text), "\(sample.name)")
    }

    @Test(arguments: drawnText)
    func ordinaryTextIsNotWithheld(sample: Case) {
        #expect(!mayHold(sample.text), "\(sample.name)")
    }

    /// The base64 form is computed here, so the test does not depend on the production constant.
    @Test func aBase64EncodedPrivateKeyIsFoundWhateverFollowsIt() {
        let encoded = Data("-----BEGIN PRIVATE KEY-----\n".utf8).base64EncodedString()
        #expect(encoded.hasPrefix("LS0tLS1CRUdJTi"))
        #expect(mayHold("tls.key: " + encoded))
        #expect(mayHold("tls.key: " + String(encoded.prefix(14)) + "/+"))
    }

    /// A git commit hash is hexadecimal, so it has one letter case and never mixes both; a digest in either
    /// case, however long, is therefore never a token-like run.
    @Test func hexadecimalDigestsNeverCountHoweverLong() {
        #expect(!mayHold(String(repeating: "3f2a9c1d", count: 64)))
        #expect(!mayHold(String(repeating: "3F2A9C1D", count: 64)))
        // One letter of the other case in a long run does make it mixed: the rule has no hexadecimal exception.
        #expect(mayHold("3f2a9c1d8e7b6a5f4c3d2e1f0a9b8c7d6e5f4a3B"))
    }

    @Test func theRunNeedsAllThreeKindsOfCharacter() {
        let letters = String(repeating: "aB", count: 40)
        let digits = String(repeating: "0", count: 80)
        let lowerAndDigits = String(repeating: "a1", count: 40)
        let upperAndDigits = String(repeating: "A1", count: 40)
        for run in [letters, digits, lowerAndDigits, upperAndDigits] { #expect(!mayHold("x " + run + " y"), "\(run)") }
        #expect(mayHold("x " + letters + "7 y"))
    }

    @Test func theRunBoundaryIsThirtyTwoCharacters() {
        let run = String(repeating: "aB3", count: 11)
        #expect(!mayHold(String(run.prefix(31))))
        #expect(mayHold(String(run.prefix(32))))
        #expect(mayHold(run))
        // A separator splits one run into two short ones.
        #expect(!mayHold(String(run.prefix(16)) + "-" + String(run.prefix(16))))
    }

    @Test func userInformationNeedsAColonAndAPassword() {
        #expect(mayHold("postgres://app:x@host"))
        #expect(!mayHold("postgres://app:@host"), "an empty password is not a credential")
        #expect(!mayHold("postgres://app@host:5432"), "a user alone is a name")
        #expect(!mayHold("postgres://host:5432/db?user=app@home"), "the path ended the authority")
        #expect(!mayHold("see https://example.invalid/a:b@c"), "a slash ends the user information")
        #expect(!mayHold("<https://example.invalid:8080> mail a@b.invalid"), "a bracket ends the user information")
        #expect(!mayHold("url = 'http://localhost:3000' mail a@b.invalid"), "a quote ends the user information")
        // The scan looks no further than the bound past the scheme separator.
        #expect(!mayHold("https://u:" + String(repeating: "p", count: 300) + "@host"))
        #expect(mayHold("https://u:" + String(repeating: "p", count: 200) + "@host"))
    }

    @Test func theScanIsBoundedToTheLeadingBytes() {
        let run = String(repeating: "aB3", count: 11)
        let window = 262_144
        #expect(mayHold(run + String(repeating: " ", count: window)))
        #expect(!mayHold(String(repeating: " ", count: window) + run), "past the window nothing is examined")
        #expect(!mayHold(String(repeating: " ", count: window - 20) + run), "a run cut short by the window is short")
        #expect(mayHold(String(repeating: " ", count: window - 32) + run), "a run that fits the window exactly is seen")
    }

    @Test func largeAndMultiByteTextIsScannedWithoutTrouble() {
        #expect(!mayHold(String(repeating: "lorem ipsum ", count: 100_000)))
        // 300,000 bytes of three-byte scalars: the window ends inside a scalar.
        #expect(!mayHold(String(repeating: "€", count: 100_000)))
        #expect(!mayHold(""))
    }

    // MARK: Names

    static let withheldNames: [String] = [
        "secrets.yaml", "Secrets.json", "AWS_CREDENTIALS", "credentials.csv", "access-token.json",
        "TOKEN.txt", "passwords.md", "passwd.txt", "Passwort.txt", "kubeconfig",
        "dev.kubeconfig.yaml", ".netrc", "backup.netrc.txt", "id_rsa", "id_rsa.pub",
        "id_ed25519", "ID_ED25519.PUB"
    ]
    static let drawnNames: [String] = [
        "README.md", "main.swift", "people.csv", "notes.txt", "config.json",
        "docker-compose.yml", "Dockerfile", "package.json", "report.final.json", "idea.txt",
        "summary.txt"
    ]

    @Test(arguments: withheldNames)
    func aFileNameThatSaysCredentialsIsWithheldWhateverTheText(name: String) {
        #expect(mayHold("ordinary words", fileName: name))
        #expect(mayHold("", fileName: name))
    }

    @Test(arguments: drawnNames)
    func anOrdinaryFileNameDecidesNothing(name: String) {
        #expect(!mayHold("ordinary words", fileName: name))
    }

    @Test func aDockerConfigIsWithheldOnlyDirectlyUnderADockerFolder() {
        #expect(mayHold("{}", fileName: "config.json", parent: ".docker"))
        #expect(mayHold("{}", fileName: "CONFIG.JSON", parent: ".Docker"))
        #expect(!mayHold("{}", fileName: "config.json", parent: "Documents"))
        #expect(!mayHold("{}", fileName: "config.json", parent: nil))
        #expect(!mayHold("{}", fileName: "config.json", parent: "docker"))
        #expect(!mayHold("{}", fileName: "daemon.json", parent: ".docker"))
        #expect(!mayHold("{}", fileName: "config.json.bak", parent: ".docker"))
    }

    @Test func theSwitchDefaultsToOn() {
        #expect(ThumbnailLimits.standard.withholdsSecretShapes)
        #expect(relaxedLimits.withholdsSecretShapes)
    }
}

/// The same rule through the real pipeline and service: where it sits relative to the concealed-content check,
/// that it withholds pictures too, that the name is never drawn and that the switch lifts it.
@Suite("Thumbnail secret shape through the service")
struct ThumbnailSecretShapeServiceTests {
    private var lifted: ThumbnailLimits {
        var limits = relaxedLimits
        limits.withholdsSecretShapes = false
        return limits
    }

    @Test func aTokenLikeRunWithholdsTheWholeDocumentUnlessTheSwitchIsLifted() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.txt", "Meeting notes\nbuild: \(SecretShapeSamples.tokenLikeRun)\n")
        let withheld = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(withheld.scene == nil)
        #expect(withheld.reason == .withheldSecretShape)
        let drawn = try #require(await makeService(limits: lifted).outcome(for: url, geometry: geometry(384)).scene)
        #expect(drawn.content.drawnStrings.contains { $0.contains("Meeting notes") })
    }

    @Test(arguments: ["secrets.txt", "Credentials.txt", "access-token.md", "passwords.txt", "kubeconfig.txt",
                      "backup.netrc.txt", "id_rsa.txt", "id_ed25519.txt"])
    func aCredentialNamedFileIsWithheldAndItsNameIsNeverDrawn(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file(name, "Meeting notes\nbuy milk and eggs\n")
        let withheld = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(withheld.scene == nil, "\(name)")
        #expect(withheld.reason == .withheldSecretShape, "\(name)")
        // Lifted, the same file draws; the name still decides nothing about what is drawn.
        let scene = try #require(await makeService(limits: lifted).outcome(for: url, geometry: geometry(384)).scene, "\(name)")
        let drawn = scene.content.drawnStrings.joined()
        #expect(drawn.contains("Meeting notes"))
        #expect(!drawn.contains(name) && !drawn.contains(fixture.directory.path))
    }

    @Test func aDockerConfigFileIsWithheldOnlyUnderADockerFolderEndToEnd() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let json = Data(#"{"experimental":"enabled","stackOrchestrator":"swarm"}"#.utf8)
        let folder = fixture.directory.appendingPathComponent(".docker", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("config.json")
        try json.write(to: inside)
        let outside = try fixture.file("config.json", json)
        #expect(await makeService().outcome(for: inside, geometry: geometry(384)).reason == .withheldSecretShape)
        #expect(await makeService().outcome(for: outside, geometry: geometry(384)).scene != nil)
        #expect(await makeService(limits: lifted).outcome(for: inside, geometry: geometry(384)).scene != nil)
    }

    /// The check comes after the concealed-content check: a document with concealed values keeps that reason
    /// even when its name also looks credential-bearing.
    @Test func theConcealedValueReasonComesFirst() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file("secrets.yaml", "name: demo\npassword: \(syntheticSecret)\n")
        #expect(await makeService().outcome(for: url, geometry: geometry(384)).reason == .withheldConcealedContent)
    }

    @Test func theSecretShapeWithholdsPicturesToo() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cover = PreviewImage(data: syntheticImage(width: 30, height: 30), pixelWidth: 30, pixelHeight: 30, role: .cover)
        func service(text: String, limits: ThumbnailLimits) -> ContentThumbnailService {
            let document = ParsedTextDocument(text: text, images: [cover])
            let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != .plainText }
                + [AdapterRegistration(formatID: .plainText) { FixedAdapter(document: document) }]
            return makeService(registrations: registrations, limits: limits)
        }
        // By name.
        let named = try fixture.file("token-cover.txt", "ignored")
        #expect(await service(text: "caption", limits: relaxedLimits).outcome(for: named, geometry: standardGeometry).reason == .withheldSecretShape)
        let picture = try #require(await service(text: "caption", limits: lifted).outcome(for: named, geometry: standardGeometry).scene)
        guard case .picture = picture.content else { Issue.record("expected the cover once the switch is lifted"); return }
        // By text.
        let plain = try fixture.file("cover.txt", "ignored")
        let withheld = await service(text: "caption \(SecretShapeSamples.tokenLikeRun)", limits: relaxedLimits).outcome(for: plain, geometry: standardGeometry)
        #expect(withheld.reason == .withheldSecretShape)
        // An ordinary name and text draw the cover.
        #expect(await service(text: "caption", limits: relaxedLimits).outcome(for: plain, geometry: standardGeometry).scene != nil)
    }

    @Test(arguments: [("README.md", SecretShapeSamples.readme), ("main.swift", SecretShapeSamples.swiftSource),
                      ("people.csv", SecretShapeSamples.csv), ("history.log", SecretShapeSamples.gitLog)])
    func ordinaryDocumentsStillDraw(name: String, text: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.file(name, text)
        let outcome = await makeService().outcome(for: url, geometry: geometry(384))
        #expect(outcome.scene != nil, "\(name): \(String(describing: outcome.reason))")
    }
}
