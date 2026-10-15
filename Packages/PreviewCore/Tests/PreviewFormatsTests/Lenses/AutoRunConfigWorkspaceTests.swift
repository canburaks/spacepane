import Foundation
import Testing
import PreviewContracts
import PreviewFormats

// VS Code workspace files (`*.code-workspace`): their tasks sit one level down under `tasks.tasks[]`,
// their editor servers under `settings.mcp.servers`, and the name only has to end in `.code-workspace`.

/// Folder-open tasks at 22 and 25; editor servers: a local command at 8 with two environment keys on the
/// same line, a remote address at 9; the disabled server at 10 is not counted.
let autoRunWorkspaceFile = """
{
  // A workspace file: comments and trailing commas are accepted.
  "folders": [ { "path": "." }, ],
  "settings": {
    "editor.tabSize": 2,
    "mcp": {
      "servers": {
        "local": { "type": "stdio", "command": "npx", "args": ["-y", "synthetic"], "env": { "API_KEY": \(autoRunToken), "REGION": "us" } },
        "remote": { "type": "http", "url": "https://example.invalid/mcp" },
        "off": { "command": "uvx", "disabled": true }
      }
    }
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      { "label": "build", "type": "shell", "command": "make" },
      {
        "label": "setup",
        "type": "shell",
        "command": "./setup.sh",
        "runOptions": { "runOn": "folderOpen" }
      },
      { "label": "watch", "runOptions": { "runOn": "default", "instanceLimit": 1 } },
      { "label": "other", "runOptions": { "runOn": "folderOpen" }, },
    ],
  },
}
"""

@Suite("Auto-run configuration lens: VS Code workspace files")
struct AutoRunWorkspaceTests {
    @Test(arguments: [FormatID.json, .jsonWithComments])
    func folderOpenTasksAndEditorServersAreCounted(format: FormatID) throws {
        let result = try autoRunFindings(autoRunWorkspaceFile, fileName: "Demo.code-workspace", parent: nil, format: format)
        #expect(Set(result.map(\.kind)) == [.autorunFolderOpenTask, .autorunLocalServers, .autorunRemoteServers, .autorunServerEnvironment])
        #expect(autoRunSummary(.autorunFolderOpenTask, in: result) == "2 [22, 25]")
        #expect(autoRunSummary(.autorunLocalServers, in: result) == "1 [8]")
        #expect(autoRunSummary(.autorunRemoteServers, in: result) == "1 [9]")
        #expect(autoRunSummary(.autorunServerEnvironment, in: result) == "2 [8]")
        #expect(result.first { $0.kind == .autorunFolderOpenTask }?.detail == PreviewFindingDetail.none)
    }

    @Test(arguments: [
        ("Demo.code-workspace", String?.none), ("team-frontend.code-workspace", "project"),
        ("Team.CODE-WORKSPACE", ".vscode"), ("my.project.code-workspace", "src")
    ])
    func anyWorkspaceFileIsReadWhateverItsNameOrFolder(fileName: String, parent: String?) throws {
        let result = try autoRunFindings(autoRunWorkspaceFile, fileName: fileName, parent: parent)
        #expect(autoRunSummary(.autorunFolderOpenTask, in: result) == "2 [22, 25]", "\(fileName) in \(parent ?? "-")")
    }

    @Test(arguments: [
        ("code-workspace", String?.none), ("Demo.code-workspace.bak", String?.none), ("Demo.code-workspaces", String?.none),
        ("Demo.workspace", String?.none), ("Demo.json", String?.none), ("workspace.json", ".vscode")
    ])
    func otherNamesStaySilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunWorkspaceFile, fileName: fileName, parent: parent).isEmpty, "\(fileName) in \(parent ?? "-")")
    }

    @Test func commentsAndTrailingCommasAreAccepted() throws {
        let text = """
        {
          /* block comment */
          "tasks": { "tasks": [ { "runOptions": { "runOn": "folderOpen", }, }, ], }, // trailing
        }
        """
        let result = try autoRunFindings(text, fileName: "Demo.code-workspace", parent: nil, format: .jsonWithComments)
        #expect(autoRunSummary(.autorunFolderOpenTask, in: result) == "1 [3]")
    }

    @Test(arguments: [
        #"{ "tasks": { "version": "2.0.0", "tasks": [ { "label": "build", "command": "make" } ] } }"#,
        #"{ "tasks": { "tasks": [ { "runOptions": { "runOn": "default" } } ] } }"#,
        #"{ "tasks": { "tasks": [ { "runOptions": { "runOn": "FolderOpen" } } ] } }"#,
        #"{ "tasks": { "tasks": [ { "runOn": "folderOpen" } ] } }"#,
        #"{ "tasks": { "tasks": "folderOpen" } }"#,
        #"{ "tasks": { "runOptions": { "runOn": "folderOpen" } } }"#,
        #"{ "tasks": [ { "runOptions": { "runOn": "folderOpen" } } ] }"#,
        #"{ "tasks": { "tasks": [ { "runOptions": { "runOn": 1 } }, 5, null, [] ] } }"#,
        #"{ "folders": [ { "path": "." } ], "settings": { "editor.tabSize": 2 } }"#
    ])
    func workspaceTasksThatDoNotRunOnOpenStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "Demo.code-workspace", parent: nil, format: .jsonWithComments).isEmpty, "\(text)")
    }

    @Test(arguments: [
        #"{ "mcp": { "servers": { "a": { "command": "npx" } } } }"#,
        #"{ "settings": { "mcpServers": { "a": { "command": "npx" } } } }"#,
        #"{ "settings": { "mcp": { "mcpServers": { "a": { "command": "npx" } } } } }"#,
        #"{ "settings": { "mcp": { "servers": [ { "command": "npx" } ] } } }"#,
        #"{ "settings": { "mcp": "servers" } }"#,
        #"{ "settings": { "mcp": { "servers": { "a": { "command": "npx", "disabled": true } } } } }"#
    ])
    func serversOutsideSettingsMcpStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "Demo.code-workspace", parent: nil, format: .jsonWithComments).isEmpty, "\(text)")
    }

    @Test func settingsThatHoldClaudeOrVSCodeAgentShapesDoNotApply() throws {
        let text = #"{ "settings": { "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "x" } ] } ] }, "permissions": { "defaultMode": "bypassPermissions" }, "enableAllProjectMcpServers": true } }"#
        #expect(try autoRunFindings(text, fileName: "Demo.code-workspace", parent: nil, format: .jsonWithComments).isEmpty)
    }

    @Test(arguments: [
        "", "{", "{\"tasks\": {\"tasks\": [", "{\"settings\": {\"mcp\": {\"servers\": {\"a\": }", "[1,", "not json", "{\"a\": 1} trailing"
    ])
    func malformedWorkspaceFilesProduceNothingAndDoNotThrow(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "Demo.code-workspace", parent: nil, format: .jsonWithComments).isEmpty, "\(text)")
    }
}
