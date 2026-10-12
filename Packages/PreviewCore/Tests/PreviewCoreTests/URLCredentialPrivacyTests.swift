import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

/// A synthetic password. It is neither a recognizable token shape nor a field name, so only the shared
/// URL-credential pattern of the privacy filter can conceal it.
private let password = "synthetic-url-value-7f3a"
private let database = "postgres://app:\(password)@db.example.test:5432/main"
/// A user name without a password: an address, not a credential, so it stays readable.
private let mirror = "ssh://git@git.example.test/team/repo.git"
private let concealedDatabase = "postgres://\(SecretFieldPolicy.concealmentToken)@db.example.test:5432/main"

private let urlPipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

private struct URLCredentialFixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func file(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

/// Credentials in a URL are recognized once, by the shared privacy stage, so they are concealed in every text
/// family, structured ones included, and count as redactions like every other recognizable value.
@Suite("URL credentials in every text format")
struct URLCredentialPrivacyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        var testDescription: String { name }
    }

    private static let notebook = """
    {"cells":[{"cell_type":"code","metadata":{},"outputs":[],"execution_count":null,"source":["engine = connect('\(database)')\\n","mirror = '\(mirror)'"]}],"metadata":{},"nbformat":4,"nbformat_minor":5}
    """

    /// One fixture per text family. Each holds the credential URL and the password-free address.
    static let cases: [Case] = [
        Case(name: ".env", text: "DATABASE_URL=\(database)\nMIRROR_URL=\(mirror)\n"),
        Case(name: "settings.yaml", text: "database_url: \(database)\nmirror_url: \(mirror)\n"),
        Case(name: "project.toml", text: "database_url = \"\(database)\"\nmirror_url = \"\(mirror)\"\n"),
        Case(name: "config.json", text: "{\"database_url\": \"\(database)\", \"mirror_url\": \"\(mirror)\"}\n"),
        Case(name: "config.jsonc", text: "{\n  // connection\n  \"database_url\": \"\(database)\",\n  \"mirror_url\": \"\(mirror)\"\n}\n"),
        Case(name: "README.md", text: "# Setup\n\nConnect with [the database](\(database)) first.\n\nClone from \(mirror) afterwards.\n"),
        Case(name: "notes.txt", text: "Connect with \(database) first.\nClone from \(mirror) afterwards.\n"),
        Case(name: "notes", text: "Connect with \(database) first.\nClone from \(mirror) afterwards.\n"),
        Case(name: "table.csv", text: "name,url\nprimary,\(database)\nmirror,\(mirror)\n"),
        Case(name: "table.tsv", text: "name\turl\nprimary\t\(database)\nmirror\t\(mirror)\n"),
        Case(name: "feed.xml", text: "<?xml version=\"1.0\"?>\n<config><database url=\"\(database)\"/><mirror>\(mirror)</mirror></config>\n"),
        Case(name: "analysis.ipynb", text: notebook),
        Case(name: "change.diff", text: "--- a/settings.env\n+++ b/settings.env\n@@ -1,2 +1,2 @@\n MIRROR_URL=\(mirror)\n+DATABASE_URL=\(database)\n"),
        Case(name: "paper.tex", text: "\\documentclass{article}\n\\begin{document}\nDatabase: \\url{\(database)}\nMirror: \\url{\(mirror)}\n\\end{document}\n")
    ]

    private func preview(_ name: String, _ text: String) async throws -> TextPresentation {
        let fixture = try URLCredentialFixture()
        defer { fixture.remove() }
        let url = try fixture.file(name, text)
        let outcome = await urlPipeline.preview(url: url)
        guard case .ready(let presentation) = outcome else { throw PreviewOutcomeFailure(name: name, outcome: "\(outcome)") }
        return presentation
    }

    private struct PreviewOutcomeFailure: Error, CustomStringConvertible {
        let name: String
        let outcome: String
        var description: String { "\(name) did not preview: \(outcome)" }
    }

    @Test(arguments: cases)
    func thePasswordIsConcealedAndTheHostStaysReadable(item: Case) async throws {
        let presentation = try await preview(item.name, item.text)
        #expect(!presentation.text.contains(password), "\(item.name)")
        // Only the user information is replaced: scheme, host, port and path stay where they were.
        #expect(presentation.text.contains(concealedDatabase), "\(item.name): \(presentation.text)")
        // A user name without a password is an address, not a secret.
        #expect(presentation.text.contains(mirror), "\(item.name)")
        // The concealment counts like every other recognizable value, which is what withholds thumbnails.
        #expect(presentation.redactionCount >= 1, "\(item.name)")
        #expect(presentation.findings.contains { $0.kind == .secretSensitiveField }, "\(item.name)")
    }

    @Test func concealedJSONStaysWellFormed() async throws {
        let presentation = try await preview("config.json", "{\"database_url\": \"\(database)\", \"mirror_url\": \"\(mirror)\"}\n")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: String])
        #expect(object["database_url"] == concealedDatabase)
        #expect(object["mirror_url"] == mirror)
    }

    @Test func eachCredentialIsCountedAndReportedAsASensitiveField() async throws {
        // An empty user, as Redis URLs write it, is concealed with its colon.
        let text = "a \(database)\nb redis://:\(password)@cache.example.test:6379/0\nc \(mirror)\n"
        let presentation = try await preview("notes.txt", text)
        #expect(presentation.text == "a \(concealedDatabase)\nb redis://\(SecretFieldPolicy.concealmentToken)@cache.example.test:6379/0\nc \(mirror)\n")
        #expect(presentation.redactionCount == 2)
        let found = try #require(presentation.findings.first { $0.kind == .secretSensitiveField })
        #expect(found.count == 2 && found.lines == [1, 2])
    }

    @Test func aPasswordMayContainAnAtSign() async throws {
        let presentation = try await preview("notes.txt", "open https://deploy:p@ss-synthetic@git.example.test/team/repo.git now\n")
        #expect(presentation.text == "open https://\(SecretFieldPolicy.concealmentToken)@git.example.test/team/repo.git now\n")
    }

    @Test func addressesWithoutAPasswordStayExactlyAsTheyAre() async throws {
        let text = """
        clone ssh://git@git.example.test:22/team/repo.git
        docs https://example.test/guide
        db postgres://db.example.test:5432/main
        mail mailto:ada@example.test
        api http://localhost:8080/@handle/page
        list mongodb://one.example.test:27017,two.example.test:27017/main

        """
        let presentation = try await preview("notes.txt", text)
        #expect(presentation.text == text)
        #expect(presentation.redactionCount == 0)
    }

    /// The pipeline would refuse a line this long, so the filter is exercised on its own: the scan stays linear.
    @Test func aLongAuthorityWithoutAnAtSignIsLeftAlone() throws {
        let text = "a://user:" + String(repeating: "x:", count: 20_000) + "\n"
        let safe = try DefaultPrivacyFilter().filter(ParsedTextDocument(text: text), context: RequestContext(budget: .standard))
        #expect(safe.text == text)
        #expect(safe.redactionCount == 0)
    }

    /// The code, log and INI adapters used to run their own recognizer; the shared filter is now the only owner.
    @Test func theAdaptersLeaveURLCredentialsToTheSharedFilter() throws {
        let context = RequestContext(budget: .standard)
        let adapters: [(String, any FormatAdapter)] = [
            ("connect \(database)\n", SourceCodeAdapter()),
            ("2026-10-06 12:00:00 INFO connect \(database)\n", LogAdapter()),
            ("[remote]\nurl = \(database)\n", INIConfigurationAdapter())
        ]
        for (text, adapter) in adapters {
            let parsed = try adapter.parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
            #expect(parsed.sensitiveRanges.isEmpty, "\(type(of: adapter))")
            let safe = try DefaultPrivacyFilter().filter(parsed, context: context)
            #expect(!safe.text.contains(password), "\(type(of: adapter))")
            #expect(safe.text.contains(concealedDatabase), "\(type(of: adapter))")
            #expect(safe.redactionCount == 1, "\(type(of: adapter))")
        }
    }

    // MARK: Equivalence with the reference filter

    private func expectSameConcealment(_ text: String, structured: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        let document = ParsedTextDocument(text: text, usesStructuredPrivacy: structured)
        let context = RequestContext(budget: .standard)
        let actual = try? DefaultPrivacyFilter().filter(document, context: context)
        let expected = try? ReferencePrivacyFilter().filter(document, context: context)
        #expect(actual?.text == expected?.text && actual?.redactionCount == expected?.redactionCount,
                "Optimized filter diverged for \(text.debugDescription)", sourceLocation: sourceLocation)
    }

    @Test(arguments: [
        "", "://", "a://", "a://:@", "a://b:c@", "a://b:c@d", "x://:@host", "://b:c@d", "-://b:c@d", "é://b:c@d",
        "scheme://user:pass@host/path?x=1#f", "git+ssh://user:pass@host:22/repo", "svn+ssh://@host", "redis://:p@h:6379",
        "ssh://git@host", "http://host:80/@x", "http://host:80@evil/", "[l](https://a:b@c.test/x)", "<https://a:b@c.test>",
        "{\"u\":\"https://a:b@c.test\",\"v\":\"https://d:e@f.test\"}", "a://b:c@d://e:f@g", "http://a:b@c d://e:f@g",
        "https://ghp_abcdefghijklmnopqrstuvwxyz0123456789:x-oauth-basic@github.com/o/r.git",
        "😀 https://日本語:パスワード@例え.テスト/😀", "a://u:p@h\u{2028}b://v:q@i", "a://u:p@\u{200B}h", "line\r\nhttps://u:p@h\r\n"
    ])
    func handwrittenURLShapesMatchTheReference(text: String) {
        expectSameConcealment(text, structured: false)
        expectSameConcealment(text, structured: true)
    }

    @Test func randomizedURLShapedDocumentsMatchTheReference() {
        var generator = SplitMix64(seed: 0x0D15_EA5E)
        let fragments = [
            "://", "https", "ssh", "postgres", "user", "pw", "pa:ss", "@", "@@", ":", "::", "/", "?", "#", "\"", "'", " ", "\t",
            "\n", "\r\n", ",", ";", ")", "(", "]", "[", "}", "{", "<", ">", "é", "😀", "host.example", ".", "-", "+", "x", "=",
            "\u{2028}", "\u{200B}", "password", "token", "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "Bearer abcdefgh12345678",
            "-----BEGIN PRIVATE KEY-----"
        ]
        for _ in 0..<600 {
            var text = ""
            for _ in 0..<Int(generator.next() % 40) { text += fragments[Int(generator.next() % UInt64(fragments.count))] }
            expectSameConcealment(text, structured: false)
            expectSameConcealment(text, structured: true)
        }
    }
}

/// Deterministic generator so every run covers the same randomized corpus.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
