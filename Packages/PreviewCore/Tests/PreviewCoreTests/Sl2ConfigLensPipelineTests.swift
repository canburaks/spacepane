import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

/// The configuration lenses of decision 029 through the real pipeline: files written into the folder
/// structure the tools use, read, concealed and lensed exactly as a Finder preview would.
@Suite("Configuration lenses in the pipeline")
struct Sl2ConfigLensPipelineTests {
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    /// Writes `files` (paths relative to a fresh temporary folder) and runs `body` on the folder.
    private func withTree<T>(_ files: [String: Data], _ body: (URL) async throws -> T) async throws -> T {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return try await body(root)
    }

    private func presentation(_ root: URL, _ path: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> TextPresentation {
        let outcome = await pipeline.preview(url: root.appendingPathComponent(path))
        guard case .ready(let presentation) = outcome else {
            Issue.record("\(path): \(outcome)", sourceLocation: sourceLocation)
            throw PreviewFailure.unavailableContent
        }
        return presentation
    }

    private func finding(_ kind: PreviewFindingKind, in presentation: TextPresentation) -> PreviewFinding? {
        presentation.findings.first { $0.kind == kind }
    }

    private func kinds(_ presentation: TextPresentation, prefix: String) -> Set<PreviewFindingKind> {
        Set(presentation.findings.map(\.kind).filter { $0.rawValue.hasPrefix(prefix) })
    }

    /// The gutter's line of the first occurrence of `needle` in the displayed text.
    private func line(of needle: String, in presentation: TextPresentation, sourceLocation: SourceLocation = #_sourceLocation) throws -> Int {
        let range = try #require(presentation.text.range(of: needle), "missing \(needle)", sourceLocation: sourceLocation)
        let offset = range.lowerBound.utf16Offset(in: presentation.text)
        return try #require(LogicalLines.lineNumbers(forUTF16Offsets: [offset], in: presentation.text).first, sourceLocation: sourceLocation)
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Editor tasks and agent settings

    private let tasks = """
    {
      "version": "2.0.0",
      "tasks": [
        { "label": "build", "type": "shell", "command": "make" },
        {
          "label": "setup",
          "type": "shell",
          "command": "./setup.sh",
          "runOptions": { "runOn": "folderOpen" }
        }
      ]
    }
    """

    @Test func aFolderOpenTaskInDotVSCodeIsReportedAtItsLine() async throws {
        try await withTree([".vscode/tasks.json": data(tasks), "src/tasks.json": data(tasks), "tasks.json": data(tasks)]) { root in
            let result = try await presentation(root, ".vscode/tasks.json")
            #expect(result.formatID == .json)
            let task = try #require(finding(.autorunFolderOpenTask, in: result))
            #expect((task.count, task.lines) == (1, [try line(of: "\"runOn\"", in: result)]))
            #expect(task.lines == [9])
            // The same text outside .vscode says nothing.
            for path in ["src/tasks.json", "tasks.json"] {
                #expect(kinds(try await presentation(root, path), prefix: "autorun.").isEmpty, "\(path)")
            }
        }
    }

    @Test func agentSettingsInDotClaudeReportHooksAndPermissionsAndKeepSecretsConcealed() async throws {
        let settings = """
        {
          "env": { "API_TOKEN": "synthetic-token-value-1234" },
          "permissions": { "allow": ["Bash(*)", "Read"], "defaultMode": "bypassPermissions" },
          "hooks": {
            "PostToolUse": [
              { "matcher": "Edit", "hooks": [ { "type": "command", "command": "./format.sh" } ] }
            ]
          }
        }
        """
        try await withTree([".claude/settings.json": data(settings), "settings.json": data(settings)]) { root in
            let result = try await presentation(root, ".claude/settings.json")
            #expect(!result.text.contains("synthetic-token-value-1234"))
            #expect(result.text.contains(SecretFieldPolicy.concealmentToken))
            let hooks = try #require(finding(.autorunAgentHooks, in: result))
            #expect((hooks.count, hooks.lines) == (1, [try line(of: "\"command\"", in: result)]))
            let permissions = try #require(finding(.autorunAgentPermissions, in: result))
            #expect(permissions.count == 2)
            #expect(permissions.lines == [try line(of: "\"allow\"", in: result)])
            #expect(finding(.secretSensitiveField, in: result)?.lines == [2])
            #expect(kinds(try await presentation(root, "settings.json"), prefix: "autorun.").isEmpty)
        }
    }

    @Test func devContainerWithCommentsAndTrailingCommasIsRead() async throws {
        let container = """
        {
          // synthetic dev container
          "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
          "initializeCommand": "echo host",
          "postCreateCommand": "make deps",
        }
        """
        let mcp = #"{ "mcpServers": { "local": { "command": "npx", "env": { "API_KEY": "synthetic-key-value-1234" } } } }"#
        let package = #"{ "name": "demo", "scripts": { "build": "tsc", "postinstall": "node setup.js" } }"#
        try await withTree([".devcontainer/devcontainer.json": data(container), ".mcp.json": data(mcp),
                            "package.json": data(package)]) { root in
            let devContainer = try await presentation(root, ".devcontainer/devcontainer.json")
            #expect(devContainer.formatID == .jsonWithComments)
            #expect(finding(.autorunHostCommand, in: devContainer)?.lines == [4])
            #expect(finding(.autorunContainerCommands, in: devContainer)?.lines == [5])

            let servers = try await presentation(root, ".mcp.json")
            #expect(!servers.text.contains("synthetic-key-value-1234"))
            #expect(finding(.autorunLocalServers, in: servers)?.count == 1)
            #expect(finding(.autorunServerEnvironment, in: servers)?.count == 1)

            let manifest = try await presentation(root, "package.json")
            #expect(manifest.formatID == .packageJSON)
            #expect(finding(.autorunInstallScripts, in: manifest)?.lines == [try line(of: "\"postinstall\"", in: manifest)])
        }
    }

    // MARK: launchd jobs

    private func launchAgent(program: [String], runAtLoad: Bool = true) -> [String: Any] {
        [
            "Label": "com.example.agent", "ProgramArguments": program, "RunAtLoad": runAtLoad, "KeepAlive": true,
            "StartInterval": 600, "WatchPaths": ["/var/watch/a", "/var/watch/b"],
            "EnvironmentVariables": ["API_TOKEN": "synthetic-token-value-1234"]
        ]
    }

    private func plist(_ object: [String: Any], format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
    }

    @Test(arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary])
    func aLaunchAgentIsReportedFromXMLAndBinaryPropertyLists(format: PropertyListSerialization.PropertyListFormat) async throws {
        let agent = try plist(launchAgent(program: ["/bin/bash", "-c", "echo synthetic"]), format: format)
        try await withTree(["Library/LaunchAgents/com.example.agent.plist": agent]) { root in
            let result = try await presentation(root, "Library/LaunchAgents/com.example.agent.plist")
            #expect(result.formatID == .propertyList)
            #expect(result.origin == .converted)
            #expect(!result.text.contains("synthetic-token-value-1234"))
            #expect(kinds(result, prefix: "launch.") == [.launchJob, .launchAtLoad, .launchKeepAlive, .launchInterval,
                                                           .launchWatchPaths, .launchInlineScript])
            #expect(finding(.launchJob, in: result)?.lines == [try line(of: "\"Label\"", in: result)])
            #expect(finding(.launchAtLoad, in: result)?.lines == [try line(of: "\"RunAtLoad\"", in: result)])
            #expect(finding(.launchKeepAlive, in: result)?.lines == [try line(of: "\"KeepAlive\"", in: result)])
            let interval = try #require(finding(.launchInterval, in: result))
            #expect(interval.detail == .seconds(600))
            #expect(interval.lines == [try line(of: "\"StartInterval\"", in: result)])
            let watch = try #require(finding(.launchWatchPaths, in: result))
            #expect((watch.count, watch.lines) == (2, [try line(of: "\"WatchPaths\"", in: result)]))
            #expect(finding(.launchInlineScript, in: result)?.lines == [try line(of: "\"ProgramArguments\"", in: result)])
            // No finding carries a path or an argument.
            #expect(result.findings.filter { $0.kind.rawValue.hasPrefix("launch.") }.allSatisfy {
                if case .none = $0.detail { true } else if case .seconds = $0.detail { true } else { false }
            })
        }
    }

    @Test func aJobFromATemporaryFolderIsReportedAndAnOrdinaryOneIsNot() async throws {
        let temporary: [String: Any] = ["Label": "com.example.tmp", "Program": "/private/tmp/agent", "RunAtLoad": false]
        let ordinary: [String: Any] = ["Label": "com.example.ordinary", "Program": "/usr/local/bin/agent"]
        let notAJob: [String: Any] = ["CFBundleIdentifier": "com.example.app", "RunAtLoad": true]
        try await withTree(["tmp.plist": try plist(temporary, format: .binary), "ordinary.plist": try plist(ordinary, format: .xml),
                            "app.plist": try plist(notAJob, format: .xml)]) { root in
            let hidden = try await presentation(root, "tmp.plist")
            #expect(kinds(hidden, prefix: "launch.") == [.launchJob, .launchHiddenLocation])
            #expect(finding(.launchHiddenLocation, in: hidden)?.lines == [try line(of: "\"Program\"", in: hidden)])
            #expect(kinds(try await presentation(root, "ordinary.plist"), prefix: "launch.") == [.launchJob])
            #expect(kinds(try await presentation(root, "app.plist"), prefix: "launch.").isEmpty)
        }
    }

    // MARK: Credential exports

    @Test func aBitwardenCSVReportsItsLoginsAndKeepsPasswordsConcealed() async throws {
        let export = """
        folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
        ,,login,Example One,"line one
        line two",,0,https://one.invalid,user-one,synthetic-pass-one,
        Work,1,login,Example Two,,,0,https://two.invalid,user-two,synthetic-pass-two,JBSWY3DPEHPK3PXP
        ,,note,A note,text,,0,,,,
        """
        let generic = "id,name,email,city\n1,A,a@example.invalid,Paris\n"
        try await withTree(["exports/bitwarden_export.csv": data(export), "table.csv": data(generic)]) { root in
            let result = try await presentation(root, "exports/bitwarden_export.csv")
            #expect(result.formatID == .csv)
            #expect(!result.text.contains("synthetic-pass-one") && !result.text.contains("synthetic-pass-two"))
            let logins = try #require(finding(.exportReadableLogins, in: result))
            #expect((logins.count, logins.lines, logins.severity) == (2, [1], .warning))
            #expect(kinds(try await presentation(root, "table.csv"), prefix: "export.").isEmpty)
        }
    }

    @Test func unencryptedAndEncryptedJSONExportsThroughThePipeline() async throws {
        let bitwarden = """
        {
          "encrypted": false,
          "folders": [],
          "items": [
            { "id": "1", "type": 1, "name": "One", "login": { "username": "user-one", "password": "synthetic-pass-one", "totp": null } },
            { "id": "2", "type": 2, "name": "Note", "login": null }
          ]
        }
        """
        let encrypted = #"{ "encrypted": true, "passwordProtected": true, "salt": "c3ludGhldGlj", "data": "2.c3ludGhldGlj|c3ludGhldGlj" }"#
        let andOTP = #"[ { "secret": "JBSWY3DPEHPK3PXP", "issuer": "Synthetic", "type": "TOTP", "digits": 6 } ]"#
        try await withTree(["bitwarden.json": data(bitwarden), "encrypted.json": data(encrypted), "andotp.json": data(andOTP)]) { root in
            let plain = try await presentation(root, "bitwarden.json")
            #expect(!plain.text.contains("synthetic-pass-one"))
            #expect(finding(.exportReadableLogins, in: plain)?.lines == [try line(of: "\"login\": {", in: plain)])
            #expect(kinds(try await presentation(root, "encrypted.json"), prefix: "export.").isEmpty)
            let codes = try await presentation(root, "andotp.json")
            #expect(!codes.text.contains("JBSWY3DPEHPK3PXP"))
            #expect(finding(.exportReadableCodeSecrets, in: codes)?.count == 1)
        }
    }
}
