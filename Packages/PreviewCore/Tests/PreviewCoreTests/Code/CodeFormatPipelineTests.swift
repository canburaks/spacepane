import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats

private final class Reads: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct CountingReader: PreviewFileReading {
    let data: Data
    let reads: Reads
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
}

private let codePipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
private let secretValue = "synthetic-secret-value"

private func run(_ file: String, _ source: String, preferences: PreviewPreferencesSnapshot = .defaults,
                 budget: PreviewBudget? = nil) async -> PreviewOutcome {
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                   reader: CountingReader(data: Data(source.utf8), reads: Reads()))
    return await pipeline.preview(url: URL(fileURLWithPath: "/unused/" + file), preferences: preferences, budget: budget)
}

@Suite("Catalog entries of the code family")
struct CodeCatalogTests {
    private let catalog = FormatCatalog.standard

    @Test func everyNewFormatHasADescriptorARegistrationAndSharedMetadata() throws {
        let ids: [FormatID] = [.iniConfiguration, .log, .jsonWithComments, .subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD]
        let registered = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for id in ids {
            let descriptor = try #require(catalog.descriptor(for: id), "\(id.rawValue)")
            #expect(registered.contains(id) && descriptor.defaultEnabled)
            #expect(descriptor.nameKey == "format.\(id.rawValue).name" && descriptor.descriptionKey == "format.\(id.rawValue).description")
            #expect(descriptor.thumbnail == (id == .log ? .content : .generic), "\(id.rawValue)")
        }
        // Every catalog format has a registration and vice versa.
        // (The CAD formats are registered by their own module.)
        #expect(Set(catalog.descriptors.map(\.id)).subtracting([.iges, .step]) == registered)
    }

    @Test func noSuffixOrFilenameBelongsToTwoFormats() {
        var suffixOwners: [String: FormatID] = [:]
        var nameOwners: [String: FormatID] = [:]
        for descriptor in catalog.descriptors {
            for suffix in descriptor.suffixAliases {
                #expect(suffixOwners[suffix] == nil, "\(suffix) is claimed by \(suffixOwners[suffix]?.rawValue ?? "") and \(descriptor.id.rawValue)")
                suffixOwners[suffix] = descriptor.id
            }
            for name in descriptor.filenameAliases {
                #expect(nameOwners[name] == nil, "\(name) is claimed by \(nameOwners[name]?.rawValue ?? "") and \(descriptor.id.rawValue)")
                nameOwners[name] = descriptor.id
            }
        }
    }

    @Test func sourceCodeCoversAtLeast150SuffixesAndNeverTakesAnotherFormatsSuffix() throws {
        let descriptor = try #require(catalog.descriptor(for: .sourceCode))
        #expect(descriptor.suffixAliases.count >= 150)
        // Suffixes owned by the markup, diagram, data, ini, log and caption families stay with them.
        let reserved: Set<String> = ["tex", "cls", "sty", "bib", "mmd", "map", "sub", "json", "yaml", "toml", "md", "csv", "ini", "log", "ass",
                                     "ssa", "ttml", "lrc", "sbv", "cfg", "conf", "properties", "xcconfig", "plist", "xml", "lock"]
        #expect(Set(descriptor.suffixAliases).isDisjoint(with: reserved))
        // Documented collisions resolve to the declared language reading, not to another format.
        for suffix in ["ts", "m", "pl", "v", "d", "r", "s", "fs", "sc", "vh"] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/a.\(suffix)")) == .sourceCode, "\(suffix)")
        }
    }

    @Test func wellKnownBuildAndIgnoreFilesAreSourceCodeByName() {
        for name in ["Containerfile", "Jenkinsfile", "Vagrantfile", "Procfile", "Justfile", "Fastfile", "Cartfile", "CMakeLists.txt",
                     "meson.build", "BUILD", "WORKSPACE", "BUILD.bazel", ".gitignore", ".dockerignore", ".npmignore", "go.mod"] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/\(name)")) == .sourceCode, "\(name)")
        }
    }

    @Test func lockFilesMapOnlyToCompatibleExistingFormats() {
        let expected: [(String, FormatID)] = [
            ("Cargo.lock", .toml), ("poetry.lock", .toml), ("uv.lock", .toml), ("Pipfile.lock", .json), ("composer.lock", .json),
            ("Gemfile.lock", .plainText), ("yarn.lock", .plainText), ("Podfile.lock", .yaml), ("pubspec.lock", .yaml)
        ]
        for (name, format) in expected {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/\(name)")) == format, "\(name)")
        }
        // Any other .lock file is not guessed.
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/other.lock")) == nil)
    }

    @Test func appleAndWebConfigurationFilesMapToExistingFormats() {
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/App.entitlements")) == .propertyList)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/Localizable.xcstrings")) == .json)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/site.webmanifest")) == .json)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/Debug.xcconfig")) == .iniConfiguration)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/my.code-workspace")) == .jsonWithComments)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/tsconfig.json")) == .jsonWithComments)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/tsconfig.build.json")) == .jsonWithComments)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/package.json")) == .packageJSON)
        for name in [".editorconfig", ".gitconfig", ".gitmodules", ".npmrc", ".pypirc"] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/\(name)")) == .iniConfiguration, "\(name)")
        }
    }

    @Test func newImportedTypesLoadWithoutARegisteredHostAndSystemTypesAreUsedWhereTheyExist() throws {
        let log = try #require(catalog.descriptor(for: .log))
        // Another product's optional aliases load only where that product is installed.
        #expect(log.contentTypes.filter { !$0.identifier.hasPrefix(Self.thirdPartyAliasPrefix) }
                == [UTType("com.apple.log")].compactMap { $0 })
        for id in [FormatID.iniConfiguration, .jsonWithComments, .subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD] {
            let descriptor = try #require(catalog.descriptor(for: id))
            #expect(descriptor.canonicalContentType.identifier.hasPrefix("org.webmeister.spacepane.type."), "\(id.rawValue)")
        }
        // None of them claims a root type.
        for descriptor in catalog.descriptors where descriptor.id != .extensionlessText {
            #expect(!descriptor.contentTypes.contains(.data) && !descriptor.contentTypes.contains(.item) && !descriptor.contentTypes.contains(.content))
        }
    }

    private static let thirdPartyAliasPrefix = "com.quicklookpro."

    /// Where another product has typed a file with its own identifier, the file still reaches the
    /// matching format. The aliases exist only on Macs with that product installed.
    @Test func thirdPartyAliasesAreNeverCanonicalAndClassifyToTheirFormat() {
        for descriptor in catalog.descriptors {
            #expect(!descriptor.canonicalContentType.identifier.hasPrefix(Self.thirdPartyAliasPrefix), "\(descriptor.id.rawValue)")
            for type in descriptor.contentTypes where type.identifier.hasPrefix(Self.thirdPartyAliasPrefix) {
                #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/sample"), contentType: type) == descriptor.id,
                        "\(type.identifier)")
            }
        }
    }
}

@Suite("Code formats through the shared pipeline")
struct CodeFormatPipelineTests {
    @Test(arguments: [
        ("a.ini", FormatID.iniConfiguration), ("a.log", .log), ("a.jsonc", .jsonWithComments), ("a.json5", .jsonWithComments),
        ("a.ass", .subStationAlpha), ("a.ssa", .subStationAlpha), ("a.ttml", .timedText), ("a.dfxp", .timedText),
        ("a.sbv", .subViewer), ("a.lrc", .lyrics), ("a.sub", .microDVD)
    ]) func disabledTypesAreNeverReadOrFallBackToText(file: String, id: FormatID) async {
        let reads = Reads()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: CountingReader(data: Data("x".utf8), reads: reads))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: id)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/" + file), preferences: preferences) == .disabledByUser(id))
        #expect(reads.value == 0)
        #expect(await pipeline.inspect(url: URL(fileURLWithPath: "/unused/" + file), preferences: preferences) == .disabledByUser(id))
    }

    @Test func disablingOneFormatLeavesItsNeighboursOn() async {
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .jsonWithComments)
        guard case .ready(let json) = await run("a.json", "{\"a\": 1}", preferences: preferences) else {
            Issue.record("Disabling JSONC must not disable JSON"); return
        }
        #expect(json.formatID == .json)
        preferences.setEnabled(false, for: .iniConfiguration)
        guard case .ready(let plain) = await run("a.txt", "x", preferences: preferences) else { Issue.record("text stays on"); return }
        #expect(plain.formatID == .plainText)
    }

    @Test func cancellationPrecedesSourceAccessForEveryNewFormat() async {
        for file in ["a.ini", "a.log", "a.jsonc", "a.ass", "a.ttml", "a.sbv", "a.lrc", "a.sub", "a.swift"] {
            let reads = Reads()
            let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                           reader: CountingReader(data: Data("x".utf8), reads: reads))
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await pipeline.preview(url: URL(fileURLWithPath: "/unused/" + file))
            }
            #expect(await task.value == .cancelled, "\(file)")
            #expect(reads.value == 0, "\(file)")
        }
    }

    @Test func syntheticSecretsNeverReachAnyNewPresentation() async {
        let cases: [(String, String)] = [
            ("a.ini", "[s]\npassword = \(secretValue)\n"),
            ("a.log", "2026-10-05 INFO x\nAuthorization: Bearer \(secretValue)\n"),
            ("a.jsonc", "{\"token\": \"\(secretValue)\", // c\n}"),
            ("a.ass", "[Script Info]\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,D,,0,0,0,,secret = \(secretValue)\n"),
            ("a.ttml", "<tt><body><p begin=\"1s\" end=\"2s\">secret = \(secretValue)</p></body></tt>"),
            ("a.sbv", "0:00:01.000,0:00:02.000\nsecret = \(secretValue)\n"),
            ("a.lrc", "[00:01.00]secret = \(secretValue)\n"),
            ("a.sub", "{1}{2}secret = \(secretValue)\n"),
            ("a.swift", "let url = \"https://u:\(secretValue)@h.example.test\"\n"),
            ("deploy.sh", "run --password \(secretValue)\n"),
            ("Dockerfile", "ENV API_TOKEN \(secretValue)\n"),
            (".npmrc", "//registry.example.test/:_authToken=\(secretValue)\n")
        ]
        for (file, source) in cases {
            guard case .ready(let presentation) = await run(file, source) else { Issue.record("Expected \(file) to preview"); continue }
            #expect(!presentation.text.contains(secretValue), "\(file)")
            #expect(presentation.redactionCount > 0, "\(file)")
        }
    }

    @Test func minifiedJSONIsFormattedThroughThePipelineAndMarkedReformatted() async throws {
        let long = "{\"payload\":\"" + String(repeating: "abcdefgh", count: 5) + "\",\"password\":\"\(secretValue)\",\"list\":[1,2,3]}"
        let narrow = PreviewBudget(maxLineUTF8Bytes: 64)
        guard case .ready(let presentation) = await run("a.json", long, budget: narrow) else { Issue.record("Expected a formatted preview"); return }
        #expect(presentation.isReformatted && presentation.syntax == .json && presentation.formatID == .json)
        #expect(!presentation.text.contains(secretValue))
        #expect(presentation.text.contains("\"password\": ••••") && presentation.text.contains("\"list\": [1, 2, 3]"))
        #expect(presentation.lineCount == 5)
        // Other formats keep the line budget: a long text line still fails.
        #expect(await run("a.txt", String(repeating: "x", count: 100), budget: narrow) == .unavailable(.lineTooLong))
        // And a JSON document whose lines fit is untouched.
        guard case .ready(let normal) = await run("a.json", "{\"a\": 1}\n", budget: narrow) else { Issue.record("Expected JSON"); return }
        #expect(!normal.isReformatted && normal.text == "{\"a\": 1}\n")
    }

    @Test func packageJSONAndOtherJSONFilesShareTheFormattedPath() async {
        let long = "{\"name\":\"" + String(repeating: "n", count: 30) + "\",\"version\":\"" + String(repeating: "v", count: 30) + "\"}"
        for file in ["package.json", "Localizable.xcstrings", "site.webmanifest", "Pipfile.lock"] {
            guard case .ready(let presentation) = await run(file, long, budget: PreviewBudget(maxLineUTF8Bytes: 64)) else {
                Issue.record("Expected \(file) to preview"); continue
            }
            #expect(presentation.isReformatted, "\(file)")
        }
    }

    @Test func vobSubSubFilesAreBinaryContentAndMicroDVDTextPreviews() async {
        let vobSub = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: CountingReader(data: Data([0x00, 0x00, 0x01, 0xBA, 0x44, 0x00, 0x04, 0x00]), reads: Reads()))
        #expect(await vobSub.preview(url: URL(fileURLWithPath: "/unused/movie.sub")) == .unavailable(.binaryContent))
        guard case .ready(let text) = await run("movie.sub", "{1}{1}25\n{25}{50}hello\n") else { Issue.record("Expected MicroDVD"); return }
        #expect(text.formatID == .microDVD && text.syntax == .microDVD && text.sourceRecordCount == 1 && text.encoding == .utf8)
    }

    @Test func malformedCaptionAndJSONCFilesHaveNoRawFallback() async {
        #expect(await run("a.jsonc", "{\"a\": }") == .unavailable(.malformedDocument))
        #expect(await run("a.ass", "not an ass file") == .unavailable(.malformedDocument))
        #expect(await run("a.sbv", "plain text") == .unavailable(.malformedDocument))
        #expect(await run("a.lrc", "plain text") == .unavailable(.malformedDocument))
        #expect(await run("a.ttml", "<root/>") == .unavailable(.malformedDocument))
    }

    @Test func iniAndLogAcceptAnyTextButNotBinary() async {
        guard case .ready(let nginx) = await run("nginx.conf", "server {\n  listen 80;\n}\n") else { Issue.record("Expected a preview"); return }
        #expect(nginx.formatID == .iniConfiguration && nginx.syntax == .ini)
        #expect(await run("a.log", "text\u{0}binary") == .unavailable(.binaryContent))
    }

    @Test func languageHintTravelsFromTheNameThroughThePipeline() async {
        guard case .ready(let swift) = await run("main.swift", "let x = 1\n") else { Issue.record("Expected a preview"); return }
        #expect(swift.sourceLanguage == .swift && swift.syntax == .sourceCode)
        guard case .ready(let make) = await run("Makefile", "all:\n\ttrue\n") else { Issue.record("Expected a preview"); return }
        #expect(make.sourceLanguage == .makefile)
        guard case .ready(let script) = await run("tool", "#!/usr/bin/env python3\nprint(1)\n") else {
            // Files without a suffix are only classified with a content type; the adapter test covers them.
            return
        }
        #expect(script.sourceLanguage == .python)
    }
}

@Suite("Extension-free scripts name their language")
struct ExtensionlessLanguageTests {
    @Test func interpreterLineSetsTheLanguageAndSourceStyle() throws {
        let adapter = ExtensionlessTextAdapter()
        let source = "#!/usr/bin/env python3\nprint('hi')\n"
        let parsed = try adapter.parse(FileBytes(data: Data(source.utf8)), context: RequestContext(budget: .standard))
        #expect(parsed.syntax == .sourceCode && parsed.sourceLanguage == .python)
        let plain = try adapter.parse(FileBytes(data: Data("just notes\n".utf8)), context: RequestContext(budget: .standard))
        #expect(plain.syntax == .plain && plain.sourceLanguage == nil)
    }
}
