import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

private let secret = "synthetic-invisible-key-value"

/// Invisible characters typed into a key name ("pass<ZWSP>word") must not defeat concealment:
/// the key still reads as a password field, and the hidden character is still reported.
@Suite("Invisible characters inside secret key names")
struct InvisibleKeyPrivacyTests {
    static let disguisedKeys = [
        "pass\u{200B}word",        // zero-width space, its own Character
        "pass\u{200D}word",        // zero-width joiner, attaches to the preceding Character
        "pass\u{00AD}word",        // soft hyphen
        "pass\u{FE0F}word",        // variation selector, attaches to the preceding Character
        "pass\u{E0061}word",       // Unicode Tag
        "\u{200B}api_key",          // leading invisible character
        "api\u{2060}_\u{034F}key"  // word joiner and combining grapheme joiner
    ]

    @Test(arguments: disguisedKeys)
    func policyIgnoresInvisibleCharactersInKeys(_ key: String) {
        #expect(SecretFieldPolicy.isSensitive(key))
    }

    @Test func policyStillRejectsOrdinaryKeys() {
        #expect(!SecretFieldPolicy.isSensitive("user\u{200B}name"))
        #expect(!SecretFieldPolicy.isSensitive("comment"))
    }

    @Test(arguments: disguisedKeys)
    func plainTextConcealsTheValueAndReportsTheHiddenCharacter(_ key: String) async {
        let outcome = await preview("\(key) = \(secret)\nnext = visible\n", name: "notes.txt")
        guard case .ready(let presentation) = outcome else { Issue.record("\(outcome)"); return }
        #expect(!presentation.text.contains(secret))
        #expect(presentation.text.contains("visible"))
        #expect(presentation.redactionCount == 1)
        #expect(presentation.findings.contains { $0.kind == .secretSensitiveField })
    }

    @Test func zeroWidthKeysAreConcealedInEnvironmentCSVAndJSON() async {
        let key = "pass\u{200B}word"
        for (name, text) in [("settings.env", "\(key)=\(secret)\n"),
                             ("table.csv", "name,\(key)\nalice,\(secret)\n"),
                             ("config.json", #"{"\#(key)": "\#(secret)"}"#)] {
            let outcome = await preview(text, name: name)
            guard case .ready(let presentation) = outcome else { Issue.record("\(name): \(outcome)"); continue }
            #expect(!presentation.text.contains(secret), "\(name)")
            #expect(presentation.findings.contains { $0.kind == .hiddenZeroWidth }, "\(name)")
        }
    }

    @Test func XMLAndConvertedBinaryPropertyListTextAreScannedWithoutInventingEncoding() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>Re\u{202E}gpj.app</string></dict></plist>
        """
        guard case .ready(let presentation) = await preview(xml, name: "Info.plist") else { Issue.record("xml plist"); return }
        #expect(presentation.findings.contains { $0.kind == .hiddenBidirectionalControls })
        let binary = try PropertyListSerialization.data(fromPropertyList: ["Name": "Re\u{202E}gpj.app", "password": secret], format: .binary, options: 0)
        let parsed = try PropertyListSourceAdapter().parse(FileBytes(data: binary), context: RequestContext(budget: .standard))
        #expect(parsed.decodedEncoding == nil && parsed.origin == .converted)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: BytesReader(data: binary))
        guard case .ready(let derived) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/Info.plist")) else {
            Issue.record("binary plist"); return
        }
        #expect(derived.findings.first { $0.kind == .hiddenBidirectionalControls }?.count == 1)
        #expect(derived.origin == .converted && !derived.text.contains(secret))
    }

    private func preview(_ text: String, name: String) async -> PreviewOutcome {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: BytesReader(data: Data(text.utf8)))
        return await pipeline.preview(url: URL(fileURLWithPath: "/unused/\(name)"))
    }
}
