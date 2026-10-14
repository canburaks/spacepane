import Foundation
import Testing
import PreviewContracts
import PreviewFormats

// Shared helpers and fixtures of the auto-run configuration lens tests.

let autoRunToken = SecretFieldPolicy.concealmentToken

func autoRunFindings(_ text: String, fileName: String, parent: String?, format: FormatID = .json) throws -> [PreviewFinding] {
    let request = PreviewLensRequest(formatID: format, fileName: fileName, parentDirectoryName: parent)
    return try AutoRunConfigLens().findings(in: text, request: request, context: RequestContext(budget: .standard))
}

func autoRunFinding(_ kind: PreviewFindingKind, in findings: [PreviewFinding]) -> PreviewFinding? {
    findings.first { $0.kind == kind }
}

/// "count [lines]" of a kind, or "none".
func autoRunSummary(_ kind: PreviewFindingKind, in findings: [PreviewFinding]) -> String {
    autoRunFinding(kind, in: findings).map { "\($0.count) \($0.lines)" } ?? "none"
}

/// Lines: runOn keys at 15 and 24.
let autoRunTasksFile = """
{
  // See the editor documentation.
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "make"
    },
    {
      "label": "setup",
      "type": "shell",
      "command": "./setup.sh",
      "runOptions": {
        "runOn": "folderOpen"
      }
    },
    {
      "label": "watch",
      "runOptions": { "runOn": "default", "instanceLimit": 1 }
    },
    {
      "label": "other",
      "runOptions": { "runOn": "folderOpen" },
    },
  ]
}
"""

/// Broad allow entries at 5, 6 and 7, defaultMode at 10, enableAllProjectMcpServers at 12, hook commands at 18, 19 and 24.
let autoRunClaudeSettings = """
{
  "permissions": {
    "allow": [
      "Bash(npm test)",
      "Bash",
      "Bash(*)",
      "Bash(:*)",
      "Read(**)"
    ],
    "defaultMode": "bypassPermissions"
  },
  "enableAllProjectMcpServers": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "./check.sh" },
          { "type": "command", "command": "./log.sh" }
        ]
      }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "echo hi" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "prompt", "prompt": "done?" } ] }
    ]
  }
}
"""

/// Local command at 4; remote addresses at 13, 18 and 20 and a bare type at 21; env at 6.
let autoRunMCPFile = """
{
  "mcpServers": {
    "local": {
      "command": "npx",
      "args": ["-y", "some-server"],
      "env": {
        "API_KEY": \(autoRunToken),
        "REGION": "us"
      }
    },
    "remote": {
      "type": "http",
      "url": "https://example.invalid/mcp",
      "headers": { "Authorization": \(autoRunToken) }
    },
    "legacy": {
      "type": "sse",
      "serverUrl": "https://example.invalid/sse"
    },
    "gemini": { "httpUrl": "https://example.invalid/h" },
    "typed": { "type": "streamable-http" }
  }
}
"""

/// Host command at 5; container commands at 6, 7 and 8.
let autoRunDevContainer = """
{
  // synthetic
  "name": "demo",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "initializeCommand": "echo host",
  "onCreateCommand": "make deps",
  "updateContentCommand": ["make", "update"],
  "postCreateCommand": { "a": "npm i", "b": "pip install -r r.txt" },
  "postStartCommand": "",
  "postAttachCommand": null,
}
"""

/// Install scripts at 6, 7 and 8.
let autoRunPackageFile = """
{
  "name": "demo",
  "scripts": {
    "build": "tsc",
    "test": "vitest",
    "preinstall": "node check.js",
    "postinstall": "node setup.js",
    "prepare": "husky",
    "prepublishOnly": "npm test"
  }
}
"""

