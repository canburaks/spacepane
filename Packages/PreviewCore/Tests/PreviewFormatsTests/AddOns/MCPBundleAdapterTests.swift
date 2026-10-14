import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("MCP bundle summaries")
struct MCPBundleAdapterTests {
    typealias Member = AddOnFixtures.Member

    /// An ordinary Node.js bundle that asks for one API key and one folder.
    static func manifest(_ edit: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var manifest: [String: Any] = [
            "manifest_version": "0.3", "name": "notes-server", "display_name": "Notes Server", "version": "1.2.0",
            "description": "Search and summarize local notes.", "author": ["name": "Example Author", "url": "https://example.test"],
            "license": "MIT",
            "server": ["type": "node", "entry_point": "server/index.js",
                       "mcp_config": ["command": "node", "args": ["${__dirname}/server/index.js"],
                                      "env": ["API_KEY": "${user_config.api_key}", "DEBUG": "false"]]],
            "tools": [["name": "search_notes", "description": "Search the notes by keyword."],
                      ["name": "read_note", "description": "Use this tool when you need the full text of a note."]],
            "prompts": [["name": "summarize", "description": "Summarize a note.", "text": "Summarize the note in three sentences."]],
            "compatibility": ["platforms": ["darwin", "win32"], "runtimes": ["node": ">=18.0.0"]],
            "user_config": ["api_key": ["type": "string", "title": "API key", "sensitive": true, "required": true],
                            "folder": ["type": "directory", "title": "Notes folder", "default": "${HOME}/Notes"]]
        ]
        edit(&manifest)
        return manifest
    }

    static func bundle(_ manifest: [String: Any] = Self.manifest(), files: [Member] = [Member("server/index.js", text: "console.log('ok');\n")]) -> Data {
        AddOnFixtures.zip([Member("manifest.json", AddOnFixtures.json(manifest))] + files)
    }

    static func summary(_ data: Data) throws -> ([String: Any], ParsedTextDocument) {
        let document = try MCPBundleAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context)
        return (PackageTestSupport.object(document), document)
    }

    // MARK: The card

    @Test func anOrdinaryBundleShowsItsDeclaredFacts() throws {
        let (summary, document) = try Self.summary(Self.bundle())
        #expect(summary["name"] as? String == "notes-server")
        #expect(summary["displayName"] as? String == "Notes Server")
        #expect(summary["version"] as? String == "1.2.0")
        #expect(summary["description"] as? String == "Search and summarize local notes.")
        #expect(summary["author"] as? String == "Example Author")
        #expect(summary["license"] as? String == "MIT")
        #expect(summary["manifestVersion"] as? String == "0.3")
        #expect(summary["serverType"] as? String == "node")
        #expect(summary["entryPoint"] as? String == "server/index.js")
        #expect(summary["command"] as? String == "node")
        #expect(summary["arguments"] as? [String] == ["${__dirname}/server/index.js"])
        #expect(summary["environment"] as? [String] == ["API_KEY", "DEBUG"])
        #expect(summary["platforms"] as? [String] == ["darwin", "win32"])
        #expect(summary["runtimes"] as? [String] == ["node >=18.0.0"])
        #expect(summary["tools"] as? [String] == ["search_notes", "read_note"])
        #expect(summary["prompts"] as? [String] == ["summarize"])
        let settings = try #require(summary["settings"] as? [[String: Any]])
        #expect(settings.compactMap { $0["name"] as? String } == ["api_key", "folder"])
        #expect(settings[0]["sensitive"] as? Bool == true && settings[0]["required"] as? Bool == true)
        #expect(settings[1]["type"] as? String == "directory" && settings[1]["sensitive"] as? Bool == false)
        #expect(summary["archiveFormat"] as? String == "ZIP")
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String } == ["manifest.json", "server/index.js"])
        #expect(document.origin == .summary)
        #expect(AddOnFixtures.counts(document) == [.bundleRunsProgram: 1, .bundleAsksForSecrets: 1])
        #expect(document.findings.allSatisfy { $0.lines.isEmpty && $0.detail == .none })
    }

    @Test func theEarlierDXTVersionKeyIsRead() throws {
        let data = Self.bundle(Self.manifest { $0["manifest_version"] = nil; $0["dxt_version"] = 0.1 })
        #expect(try Self.summary(data).0["manifestVersion"] as? String == "0.1")
    }

    @Test func theRandomAccessAndByteRoutesAgree() throws {
        let data = Self.bundle()
        let viaBytes = try MCPBundleAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context)
        let viaSource = try MCPBundleAdapter().parse(DataByteSource(data), context: AddOnFixtures.context)
        #expect(viaBytes.text == viaSource.text && viaBytes.findings == viaSource.findings)
    }

    @Test func aBundleWithOnlyNamesStillShowsWhatItHas() throws {
        let data = Self.bundle(["name": "bare", "server": ["type": "python"]], files: [])
        let (summary, document) = try Self.summary(data)
        #expect(summary["name"] as? String == "bare" && summary["serverType"] as? String == "python")
        #expect(summary["tools"] == nil && summary["settings"] == nil && summary["command"] == nil)
        #expect(AddOnFixtures.counts(document) == [.bundleRunsProgram: 1])
    }

    @Test func aManifestInsideADeflatedMemberIsRead() throws {
        let data = AddOnFixtures.zip([Member("manifest.json", AddOnFixtures.json(Self.manifest()), deflated: true)])
        #expect(try Self.summary(data).0["name"] as? String == "notes-server")
    }

    @Test func longListsAreCutAndTheSummaryStillFits() throws {
        let tools = (0..<400).map { ["name": "tool_\($0)", "description": "Does thing \($0)."] }
        let settings = Dictionary(uniqueKeysWithValues: (0..<200).map { ("setting_\($0)", ["type": "string", "title": "S"]) })
        let env = Dictionary(uniqueKeysWithValues: (0..<200).map { ("VAR_\($0)", "x") })
        let files = (0..<6_000).map { Member("assets/file-\($0).txt", text: "x") }
        let data = Self.bundle(Self.manifest {
            $0["tools"] = tools
            $0["user_config"] = settings
            $0["server"] = ["type": "node", "mcp_config": ["command": "node", "args": (0..<300).map { "arg\($0)" }, "env": env]]
        }, files: files)
        let (summary, _) = try Self.summary(data)
        #expect((summary["tools"] as? [String])?.count == AddOnLimits.listItems)
        #expect((summary["environment"] as? [String])?.count == AddOnLimits.listItems)
        #expect((summary["arguments"] as? [String])?.count == AddOnLimits.listItems)
        #expect((summary["settings"] as? [Any])?.count == AddOnLimits.listItems)
        #expect(summary["partial"] as? Bool == true)
    }

    // MARK: Privacy

    @Test func environmentValuesAndDefaultsNeverAppear() throws {
        let secret = AddOnFixtures.secret
        let data = Self.bundle(Self.manifest {
            $0["server"] = ["type": "node", "entry_point": "server/index.js",
                            "mcp_config": ["command": "node", "env": ["API_KEY": secret, "SERVICE_TOKEN": secret, "PLAIN": "visible-plain-value"],
                                           "platform_overrides": ["win32": ["env": ["WIN_SECRET": secret]]]]]
            $0["user_config"] = ["api_key": ["type": "string", "sensitive": true, "default": secret]]
        })
        let (summary, document) = try Self.summary(data)
        #expect(summary["environment"] as? [String] == ["API_KEY", "PLAIN", "SERVICE_TOKEN", "WIN_SECRET"])
        #expect(!document.text.contains(secret) && !document.text.contains("visible-plain-value"))
    }

    @Test func credentialArgumentsAreConcealedUnderSensitiveKeys() throws {
        let secret = AddOnFixtures.secret
        let data = Self.bundle(Self.manifest {
            $0["server"] = ["type": "node", "mcp_config": ["command": "node",
                "args": ["server.js", "--api-key", secret, "--token=\(secret)", "SECRET_TOKEN=\(secret)", "--port", "8080", "--verbose"]]]
            $0["description"] = "Needs api_key: \(secret) to run."
        })
        let (summary, document) = try Self.summary(data)
        let visible = PackageTestSupport.concealedText(document)
        #expect(!visible.contains(secret), "a credential-looking value must be concealed")
        #expect(visible.contains("server.js") && visible.contains("--port") && visible.contains("8080") && visible.contains("--api-key"))
        #expect((summary["arguments"] as? [String])?.count == 8)
        #expect(document.sensitiveRanges.count >= 4)
    }

    // MARK: Malformed input

    @Test func malformedBundlesFailClosed() throws {
        let valid = Self.bundle()
        let notObject = AddOnFixtures.zip([Member("manifest.json", text: "[\"manifest\"]")])
        let noManifest = AddOnFixtures.zip([Member("server/index.js", text: "x")])
        let nested = AddOnFixtures.zip([Member("bundle/manifest.json", AddOnFixtures.json(Self.manifest()))])
        let oversized = AddOnFixtures.zip([Member("manifest.json", Data("{\"description\": \"".utf8) + Data(repeating: 0x61, count: 1_100_000) + Data("\"}".utf8))])
        let samples: [Data] = [Data(), Data("PK".utf8), Data("not a zip at all".utf8), valid.dropLast(), Data(valid.prefix(valid.count / 2)),
                               Data(valid.dropFirst(10)), notObject, noManifest, nested, oversized]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try MCPBundleAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context) }
        }
        #expect(throws: PreviewFailure.inputTooLarge) { try MCPBundleAdapter().parse(FileBytes(data: oversized), context: AddOnFixtures.context) }
    }

    @Test func aCorruptedManifestChecksumIsRejected() throws {
        var data = Self.bundle()
        // The manifest is the first member: flip a byte of its stored text (after the 30-byte header and 13-byte name).
        data[30 + 13 + 5] ^= 0x01
        #expect(throws: PreviewFailure.malformedDocument) { try MCPBundleAdapter().parse(FileBytes(data: data), context: AddOnFixtures.context) }
    }

    @Test func cancellationStopsAnActiveParse() async throws {
        let data = Self.bundle(files: (0..<300).map { Member("server/s\($0).js", text: "let a;\n") })
        let document = try await CancellationTest.expectStopsActiveParse(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)) { context in
            try MCPBundleAdapter().parse(DataByteSource(data), context: context)
        }
        #expect(PackageTestSupport.object(document)["name"] as? String == "notes-server")
    }
}
