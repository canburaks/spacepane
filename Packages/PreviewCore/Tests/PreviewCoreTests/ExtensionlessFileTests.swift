import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct ExtensionlessFixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    func file(_ name: String, _ text: String) throws -> URL { try file(name, Data(text.utf8)) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private let extensionlessPipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

@Suite("Files without an extension")
struct ExtensionlessFileTests {
    private let catalog = FormatCatalog.standard

    @Test func plainDataIdentifiesOnlyANameWithoutASuffix() {
        let named = URL(fileURLWithPath: "/tmp/notes")
        #expect(catalog.classify(url: named, contentType: .data) == .extensionlessText)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/.hidden"), contentType: .data) == .extensionlessText)
        // A suffix that happens to resolve to plain data is not an extension-free file.
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/notes.unknownsuffix"), contentType: .data) == nil)
        // Metadata-only classification never guesses without a type.
        #expect(catalog.classify(url: named) == nil)
    }

    @Test func plainDataIsNeverAConformanceAncestor() throws {
        // Every one of these conforms to public.data; none is the extension-free format.
        for type in [UTType.png, .pdf, .mpeg4Movie, .unixExecutable, .executable, .archive, .image] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/item"), contentType: type) == nil, "\(type.identifier)")
        }
        let dynamic = try #require(UTType(filenameExtension: "unknownsuffix"))
        #expect(dynamic.conforms(to: .data))
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/item.unknownsuffix"), contentType: dynamic) == nil)
        // Existing conformance routing is unchanged: a text subtype still reaches plain text.
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/item"), contentType: .utf8PlainText) == .plainText)
    }

    @Test func wellKnownNamesAreSourceCodeWithoutReadingTheFile() {
        for name in ["zprofile", ".zprofile", ".zshrc", ".bash_profile", "Makefile", "Dockerfile", "Gemfile"] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/\(name)")) == .sourceCode, "\(name)")
        }
    }

    @Test func onlyThePreviewManifestMayRegisterPlainData() throws {
        let descriptor = try #require(catalog.descriptor(for: .extensionlessText))
        #expect(descriptor.contentTypes == [.data] && descriptor.suffixAliases.isEmpty && descriptor.filenameAliases.isEmpty)
        #expect(descriptor.thumbnail == .none && descriptor.defaultEnabled)
        #expect(catalog.descriptors.filter { $0.contentTypes.contains(.data) }.count == 1)
    }

    @Test func textWithoutAnExtensionIsPreviewedAndConcealed() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes", "First line\npassword=synthetic-extensionless-secret\n")
        guard case .ready(let presentation) = await extensionlessPipeline.preview(url: url) else {
            Issue.record("Expected a text preview"); return
        }
        #expect(presentation.formatID == .extensionlessText && presentation.syntax == .plain)
        #expect(presentation.text.contains("First line"))
        #expect(presentation.redactionCount > 0 && !presentation.text.contains("synthetic-extensionless-secret"))
    }

    @Test func scriptsNamingAnInterpreterAreSourceCode() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("deploy", "#!/bin/sh\necho ready\n")
        guard case .ready(let presentation) = await extensionlessPipeline.preview(url: url) else {
            Issue.record("Expected a source preview"); return
        }
        #expect(presentation.formatID == .extensionlessText && presentation.syntax == .sourceCode)
    }

    @Test func shellProfilesFollowTheSourceCodeChoice() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("zprofile", "# login shell\nexport EDITOR=vim\nexport API_TOKEN=synthetic-profile-secret\n")
        guard case .ready(let presentation) = await extensionlessPipeline.preview(url: url) else {
            Issue.record("Expected a source preview"); return
        }
        #expect(presentation.formatID == .sourceCode && presentation.syntax == .sourceCode)
        #expect(presentation.text.contains("EDITOR=vim") && !presentation.text.contains("synthetic-profile-secret"))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .sourceCode)
        // The broader extension-free type must not render a disabled, more specific one.
        #expect(await extensionlessPipeline.preview(url: url, preferences: preferences) == .disabledByUser(.sourceCode))
    }

    @Test func binaryContentIsNeverShownAsText() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        // A Mach-O header, bytes that are not UTF-8, a NUL inside ASCII, and a control character.
        let samples: [(String, Data)] = [
            ("macho", Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01])),
            ("latin", Data([0x63, 0x61, 0x66, 0xE9, 0x0A])),
            ("nul", Data("text\u{0}more\n".utf8)),
            ("control", Data("text\u{1}more\n".utf8)),
            ("utf16-truncated", Data([0xFF, 0xFE, 0x41])),
        ]
        for (name, data) in samples {
            let url = try fixture.file(name, data)
            #expect(await extensionlessPipeline.preview(url: url) == .unavailable(.binaryContent), "\(name)")
        }
    }

    @Test func markedEncodingsAreDecodedAndReported() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let utf8 = try fixture.file("utf8", Data([0xEF, 0xBB, 0xBF]) + Data("café 日本語\n".utf8))
        guard case .ready(let marked) = await extensionlessPipeline.preview(url: utf8) else { Issue.record("UTF-8"); return }
        #expect(marked.text == "café 日本語\n" && marked.encoding == .utf8)
        let utf16 = try fixture.file("utf16", Data([0xFF, 0xFE]) + "héllo\n".data(using: .utf16LittleEndian)!)
        guard case .ready(let wide) = await extensionlessPipeline.preview(url: utf16) else { Issue.record("UTF-16"); return }
        #expect(wide.text == "héllo\n" && wide.encoding == .utf16LittleEndian)
        let empty = try fixture.file("empty", Data())
        guard case .ready(let nothing) = await extensionlessPipeline.preview(url: empty) else { Issue.record("empty"); return }
        #expect(nothing.text.isEmpty)
    }

    @Test func turningTheTypeOffStopsBeforeReading() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes", "text\n")
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .extensionlessText)
        #expect(await extensionlessPipeline.preview(url: url, preferences: preferences) == .disabledByUser(.extensionlessText))
        // Plain Text being enabled must not let the disabled type through as generic text.
        #expect(preferences.isEnabled(.plainText))
    }

    @Test func unknownSuffixesStayUnsupported() async throws {
        let fixture = try ExtensionlessFixture()
        defer { fixture.remove() }
        let url = try fixture.file("notes.unknownsuffix", "text\n")
        #expect(await extensionlessPipeline.preview(url: url) == .unavailable(.unsupportedFormat))
    }
}
