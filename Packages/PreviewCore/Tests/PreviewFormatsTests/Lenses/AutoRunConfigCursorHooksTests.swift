import Foundation
import Testing
import PreviewContracts
import PreviewFormats

// Cursor's `hooks.json`, read from a `.cursor` folder (project `.cursor/hooks.json` or the user's `~/.cursor`):
// `hooks` maps each event to a list of entries, and an entry with a non-empty string `command` runs it.

/// Commands at 5 (beforeShellExecution) and 10 (afterFileEdit). The empty command, the prompt entry at 7
/// and the entries without a string command are not counted.
let autoRunCursorHooksFile = """
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      { "command": "./scripts/check-shell.sh" },
      { "command": "" },
      { "type": "prompt", "prompt": "Is this safe?" }
    ],
    "afterFileEdit": [
      { "command": "./hooks/format.sh", "timeout": 10 }
    ]
  }
}
"""

@Suite("Auto-run configuration lens: Cursor hooks")
struct AutoRunCursorHooksTests {
    @Test func commandsOnEveryEventAreCountedAsAgentHooks() throws {
        let result = try autoRunFindings(autoRunCursorHooksFile, fileName: "hooks.json", parent: ".cursor")
        #expect(result.map(\.kind) == [.autorunAgentHooks])
        #expect(autoRunSummary(.autorunAgentHooks, in: result) == "2 [5, 10]")
        #expect(result.first?.detail == PreviewFindingDetail.none)
    }

    @Test func nameAndFolderMatchIgnoringCase() throws {
        let result = try autoRunFindings(autoRunCursorHooksFile, fileName: "Hooks.JSON", parent: ".Cursor")
        #expect(autoRunSummary(.autorunAgentHooks, in: result) == "2 [5, 10]")
    }

    @Test(arguments: [
        ("hooks.json", String?.none), ("hooks.json", "project"), ("hooks.json", ".vscode"), ("hooks.json", "cursor"),
        ("hooks.json", ".cursor-old"), ("hooks.json", ".claude"), ("hooks.json", "src"),
        ("hooks.json.bak", ".cursor"), ("hook.json", ".cursor"), ("cursor-hooks.json", ".cursor"),
        ("mcp.json", ".cursor"), ("settings.json", ".cursor")
    ])
    func theSameHooksElsewhereStaySilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunCursorHooksFile, fileName: fileName, parent: parent).isEmpty, "\(fileName) in \(parent ?? "-")")
    }

    @Test(arguments: [
        #"{ "version": 1, "hooks": { "stop": [ { "command": 5 }, { "command": null }, { "command": ["a"] }, { "command": { "a": "b" } }, {}, "string", 7, null, [] ] } }"#,
        #"{ "version": 1, "hooks": { "stop": { "command": "a" } } }"#,
        #"{ "version": 1, "hooks": [ { "command": "a" } ] }"#,
        #"{ "version": 1, "hooks": "afterFileEdit" }"#,
        #"{ "version": 1 }"#,
        #"{ "version": 1, "hooks": {} }"#,
        #"{ "version": 1, "hooks": { "stop": [] } }"#,
        #"{ "version": 1, "hooks": { "stop": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "a" } ] } ] } }"#
    ])
    func entriesWithoutAStringCommandStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "hooks.json", parent: ".cursor").isEmpty, "\(text)")
    }

    @Test func unknownKeysAndEventNamesAreTolerated() throws {
        let text = """
        {
          "version": 2,
          "owner": { "team": "tools" },
          "hooks": {
            "customEvent": [ { "command": "./a.sh", "failClosed": true, "matcher": "*", "loop_limit": null } ]
          }
        }
        """
        let result = try autoRunFindings(text, fileName: "hooks.json", parent: ".cursor")
        #expect(autoRunSummary(.autorunAgentHooks, in: result) == "1 [5]")
    }

    @Test func claudeShapedHooksAreNotReadAsCursorHooks() throws {
        #expect(try autoRunFindings(autoRunClaudeSettings, fileName: "hooks.json", parent: ".cursor").isEmpty)
    }

    @Test(arguments: [
        "", "{", "{\"hooks\": {\"stop\": [{\"command\": \"a\"", "[1,", "not json", "{\"a\": 1} trailing"
    ])
    func malformedHooksFilesProduceNothingAndDoNotThrow(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "hooks.json", parent: ".cursor").isEmpty, "\(text)")
    }
}
