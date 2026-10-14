import Foundation
import Testing
import PreviewContracts
import PreviewFormats

// MARK: - Editor tasks

@Suite("Auto-run configuration lens: editor tasks")
struct AutoRunEditorTaskTests {
    @Test(arguments: [FormatID.json, .jsonWithComments])
    func tasksThatRunWhenTheFolderOpensAreCountedAtTheirRunOnKeys(format: FormatID) throws {
        let result = try autoRunFindings(autoRunTasksFile, fileName: "tasks.json", parent: ".vscode", format: format)
        #expect(result.map(\.kind) == [.autorunFolderOpenTask])
        #expect(autoRunSummary(.autorunFolderOpenTask, in: result) == "2 [15, 24]")
        #expect(result.first?.detail == PreviewFindingDetail.none)
    }

    @Test func nameAndFolderMatchIgnoringCase() throws {
        #expect(autoRunFinding(.autorunFolderOpenTask, in: try autoRunFindings(autoRunTasksFile, fileName: "Tasks.JSON", parent: ".VSCode")) != nil)
    }

    @Test(arguments: [
        ("tasks.json", String?.none), ("tasks.json", "src"), ("tasks.json", ".vscode-test"), ("tasks.json", ".claude"),
        ("task.json", ".vscode"), ("tasks.json.bak", ".vscode"), ("mytasks.json", ".vscode"), ("launch.json", ".vscode"),
        ("settings.json", ".vscode")
    ])
    func theSameTextAnywhereElseStaysSilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunTasksFile, fileName: fileName, parent: parent).isEmpty)
    }

    @Test(arguments: [
        #"{ "version": "2.0.0" }"#,
        #"{ "tasks": {} }"#,
        #"{ "tasks": "folderOpen" }"#,
        #"{ "tasks": [ { "runOptions": { "runOn": "FolderOpen" } } ] }"#,
        #"{ "tasks": [ { "runOptions": { "runOn": "default" } } ] }"#,
        #"{ "tasks": [ { "runOptions": "folderOpen" } ] }"#,
        #"{ "tasks": [ { "runOn": "folderOpen" } ] }"#,
        #"{ "tasks": [ { "runOptions": { "runOn": 1 } }, 5, null, [] ] }"#,
        #"{ "runOptions": { "runOn": "folderOpen" } }"#,
        #"[ { "runOptions": { "runOn": "folderOpen" } } ]"#
    ])
    func tasksThatDoNotRunOnOpenStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "tasks.json", parent: ".vscode").isEmpty)
    }

    @Test func aConcealedRunOnValueIsNotJudged() throws {
        let text = "{ \"tasks\": [ { \"runOptions\": { \"runOn\": \(autoRunToken) } } ] }"
        #expect(try autoRunFindings(text, fileName: "tasks.json", parent: ".vscode").isEmpty)
    }
}

// MARK: - AI agent settings

@Suite("Auto-run configuration lens: agent settings")
struct AutoRunAgentSettingsTests {
    @Test(arguments: ["settings.json", "settings.local.json"])
    func hooksAndPermissionsAreCountedAtTheirLines(fileName: String) throws {
        let result = try autoRunFindings(autoRunClaudeSettings, fileName: fileName, parent: ".claude")
        #expect(Set(result.map(\.kind)) == [.autorunAgentHooks, .autorunAgentPermissions])
        #expect(autoRunSummary(.autorunAgentHooks, in: result) == "3 [18, 19, 24]")
        #expect(autoRunSummary(.autorunAgentPermissions, in: result) == "5 [5, 6, 7, 10, 12]")
    }

    @Test(arguments: [
        ("settings.json", String?.none), ("settings.json", ".vscode"), ("settings.json", "claude"), ("settings.json", ".claude-old"),
        ("settings.local.json", "src"), ("config.json", ".claude"), ("settings.json.bak", ".claude"), ("settings.yaml", ".claude")
    ])
    func theSameSettingsElsewhereStaySilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunClaudeSettings, fileName: fileName, parent: parent).isEmpty)
    }

    @Test func aHookIsACommandByTypeOrByItsCommandString() throws {
        let text = """
        { "hooks": { "Stop": [ { "hooks": [
          { "type": "command", "command": "a" },
          { "command": "b" },
          { "type": "command" },
          { "type": "command", "command": \(autoRunToken) },
          { "type": "prompt", "prompt": "p" },
          { "type": "http", "url": "https://example.invalid" },
          { "type": "agent", "prompt": "q" },
          "string", 5, null
        ] } ] } }
        """
        let result = try autoRunFindings(text, fileName: "settings.json", parent: ".claude")
        #expect(autoRunSummary(.autorunAgentHooks, in: result) == "4 [2, 3, 4, 5]")
    }

    @Test(arguments: [
        #"{ "hooks": {} }"#, #"{ "hooks": [] }"#, #"{ "hooks": { "Stop": [] } }"#, #"{ "hooks": { "Stop": [ {} ] } }"#,
        #"{ "hooks": { "Stop": [ { "hooks": [] } ] } }"#, #"{ "hooks": { "Stop": { "hooks": [ { "command": "a" } ] } } }"#,
        #"{ "hooks": "command" }"#, #"{ "hooks": { "Stop": [ { "matcher": "Bash", "command": "a" } ] } }"#,
        #"{ "env": { "A": "b" }, "model": "opus" }"#
    ])
    func settingsWithoutHookCommandsStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "settings.json", parent: ".claude").isEmpty)
    }

    @Test(arguments: [
        (#"{ "permissions": { "allow": ["Bash"] } }"#, "1 [1]"),
        (#"{ "permissions": { "allow": ["Bash(*)", "Bash(:*)"] } }"#, "2 [1]"),
        (#"{ "permissions": { "defaultMode": "bypassPermissions" } }"#, "1 [1]"),
        (#"{ "enableAllProjectMcpServers": true }"#, "1 [1]")
    ])
    func eachBroadPermissionCounts(text: String, expected: String) throws {
        let result = try autoRunFindings(text, fileName: "settings.json", parent: ".claude")
        #expect(autoRunSummary(.autorunAgentPermissions, in: result) == expected)
    }

    @Test(arguments: [
        #"{ "permissions": { "allow": ["Bash(npm test)", "Bash(git:*)", "Read", "WebFetch", "bash", "Bash(*) "] } }"#,
        #"{ "permissions": { "deny": ["Bash", "Bash(*)"], "ask": ["Bash(:*)"] } }"#,
        #"{ "permissions": { "defaultMode": "acceptEdits" } }"#,
        #"{ "permissions": { "defaultMode": "plan" } }"#,
        #"{ "permissions": { "defaultMode": "default" } }"#,
        #"{ "permissions": { "defaultMode": "bypassPermissionsX" } }"#,
        #"{ "enableAllProjectMcpServers": false }"#,
        #"{ "enableAllProjectMcpServers": "true" }"#,
        #"{ "allow": ["Bash"], "defaultMode": "bypassPermissions" }"#,
        #"{ "permissions": { "allow": "Bash" } }"#,
        #"{ "permissions": { "allow": [ ["Bash"], { "Bash": 1 } ] } }"#
    ])
    func narrowOrUnrelatedPermissionsStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "settings.json", parent: ".claude").isEmpty)
    }

    @Test func serversDeclaredInSettingsAreCountedAsServers() throws {
        let text = #"{ "mcpServers": { "a": { "command": "npx" }, "b": { "url": "https://example.invalid" } } }"#
        let result = try autoRunFindings(text, fileName: "settings.json", parent: ".claude")
        #expect(Set(result.map(\.kind)) == [.autorunLocalServers, .autorunRemoteServers])
    }
}

// MARK: - Every configuration

@Suite("Auto-run configuration lens: malformed input and cancellation")
struct AutoRunRobustnessTests {
    @Test(arguments: [
        ("tasks.json", ".vscode"), ("settings.json", ".claude"), (".mcp.json", ""), ("devcontainer.json", ".devcontainer"), ("package.json", "")
    ])
    func malformedTextProducesNothingAndDoesNotThrow(fileName: String, parent: String) throws {
        for text in ["", "{", "{\"tasks\": [", "{\"scripts\": {\"postinstall\": }", "[1,", "not json", "{\"a\": 1} trailing"] {
            #expect(try autoRunFindings(text, fileName: fileName, parent: parent.isEmpty ? nil : parent).isEmpty, "\(text)")
        }
    }

    @Test func otherFormatsAndUnrecognizedFilesAreIgnored() throws {
        #expect(try autoRunFindings(autoRunTasksFile, fileName: "notes.json", parent: ".vscode").isEmpty)
        #expect(try autoRunFindings(autoRunPackageFile, fileName: "data.json", parent: nil).isEmpty)
    }

    @Test func cancellationStopsAnActiveRead() async throws {
        var text = "{\n  \"version\": \"2.0.0\",\n  \"tasks\": [\n"
        for index in 0..<400 {
            text += "    { \"label\": \"task\(index)\", \"command\": \"make\", \"runOptions\": { \"runOn\": \"folderOpen\" } },\n"
        }
        text += "    { \"label\": \"last\" }\n  ]\n}\n"
        let source = text
        let completed = try await CancellationTest.expectStopsActiveParse(budget: .standard) { context in
            let request = PreviewLensRequest(formatID: .json, fileName: "tasks.json", parentDirectoryName: ".vscode")
            let result = try AutoRunConfigLens().findings(in: source, request: request, context: context)
            return ParsedTextDocument(text: "\(result.first?.count ?? 0)")
        }
        #expect(completed.text == "400")
    }
}
