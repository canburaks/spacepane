import Foundation
import Testing
import PreviewContracts
import PreviewFormats

// MARK: - MCP servers

@Suite("Auto-run configuration lens: MCP servers")
struct AutoRunMCPServerTests {
    @Test(arguments: [
        (".mcp.json", String?.none), (".mcp.json", "project"), ("claude_desktop_config.json", "Claude"),
        ("mcp.json", ".cursor"), ("mcp.json", ".vscode"), ("mcp.json", ".roo"), ("mcp.json", ".amazonq"),
        ("settings.json", ".gemini"), ("mcp_config.json", "windsurf"), ("MCP.JSON", ".Cursor")
    ])
    func knownConfigurationFilesAreRead(fileName: String, parent: String?) throws {
        let result = try autoRunFindings(autoRunMCPFile, fileName: fileName, parent: parent)
        #expect(autoRunSummary(.autorunLocalServers, in: result) == "1 [4]", "\(fileName) in \(parent ?? "-")")
        #expect(autoRunSummary(.autorunRemoteServers, in: result) == "4 [13, 18, 20, 21]")
        #expect(autoRunSummary(.autorunServerEnvironment, in: result) == "2 [6]")
    }

    @Test(arguments: [
        ("mcp.json", String?.none), ("mcp.json", "src"), ("mcp.json", "settings"), ("mcp.json", ".gemini"),
        ("settings.json", ".cursor"), ("settings.json", String?.none), ("mcp.json.bak", ".cursor"), ("mcp-config.json", ".cursor"),
        ("config.json", ".vscode"), ("mcp_config.json", "src"), ("package.json", ".cursor")
    ])
    func theSameServersInOtherFilesStaySilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunMCPFile, fileName: fileName, parent: parent).isEmpty, "\(fileName) in \(parent ?? "-")")
    }

    @Test func theEditorsServersKeyIsReadOnlyInTheEditorsFolder() throws {
        let text = """
        {
          "inputs": [ { "type": "promptString", "id": "key", "password": true } ],
          "servers": {
            "github": { "type": "http", "url": "https://example.invalid/mcp" },
            "local": { "type": "stdio", "command": "node", "args": ["server.js"], "env": { "A": "1", "B": "2", "C": "3" } }
          }
        }
        """
        let result = try autoRunFindings(text, fileName: "mcp.json", parent: ".vscode")
        #expect(autoRunSummary(.autorunRemoteServers, in: result) == "1 [4]")
        #expect(autoRunSummary(.autorunLocalServers, in: result) == "1 [5]")
        #expect(autoRunSummary(.autorunServerEnvironment, in: result) == "3 [5]")
        #expect(try autoRunFindings(text, fileName: "mcp.json", parent: ".cursor").isEmpty)
        #expect(try autoRunFindings(text, fileName: ".mcp.json", parent: nil).isEmpty)
    }

    @Test func aServerWithBothAnAddressAndATypeCountsOnce() throws {
        let text = #"{ "mcpServers": { "a": { "type": "http", "url": "u", "serverUrl": "v", "httpUrl": "w" } } }"#
        let result = try autoRunFindings(text, fileName: ".mcp.json", parent: nil)
        #expect(autoRunSummary(.autorunRemoteServers, in: result) == "1 [1]")
        #expect(autoRunFinding(.autorunLocalServers, in: result) == nil)
    }

    @Test func environmentKeysAreCountedAcrossServersWithoutTheirValues() throws {
        let text = """
        { "mcpServers": {
          "a": { "command": "x", "env": { "ONE": \(autoRunToken), "TWO": "2" } },
          "b": { "command": "y", "env": { "THREE": \(autoRunToken) } },
          "c": { "command": "z", "env": {} },
          "d": { "command": "w", "env": [ "NOT", "AN", "OBJECT" ] }
        } }
        """
        let result = try autoRunFindings(text, fileName: ".mcp.json", parent: nil)
        #expect(autoRunSummary(.autorunLocalServers, in: result) == "4 [2, 3, 4, 5]")
        #expect(autoRunSummary(.autorunServerEnvironment, in: result) == "3 [2, 3]")
    }

    @Test(arguments: [
        #"{ "mcpServers": {} }"#, #"{ "mcpServers": [] }"#, #"{ "mcpServers": "x" }"#, #"{ "mcpServers": { "a": {} } }"#,
        #"{ "mcpServers": { "a": "npx", "b": 5, "c": null, "d": [] } }"#,
        #"{ "mcpServers": { "a": { "command": "" } } }"#, #"{ "mcpServers": { "a": { "command": null } } }"#,
        #"{ "mcpServers": { "a": { "url": "" } } }"#, #"{ "mcpServers": { "a": { "type": "stdio" } } }"#,
        #"{ "mcpServers": { "a": { "type": "websocket" } } }"#, #"{ "mcpServers": { "a": { "args": ["x"], "env": { "K": "v" } } } }"#,
        #"{ "servers": { "a": { "command": "x" } } }"#, #"{ "name": "a", "command": "x", "url": "y" }"#, "{}", "[]"
    ])
    func filesWithoutRunnableServersStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: ".mcp.json", parent: nil).isEmpty)
    }
}

// MARK: - Dev containers

@Suite("Auto-run configuration lens: dev containers")
struct AutoRunDevContainerTests {
    @Test(arguments: [
        ("devcontainer.json", String?.some(".devcontainer")), ("devcontainer.json", String?.none), ("devcontainer.json", "templates"),
        (".devcontainer.json", String?.none), (".devcontainer.json", "project"), ("DevContainer.JSON", ".devcontainer")
    ])
    func hostAndContainerCommandsAreCounted(fileName: String, parent: String?) throws {
        let result = try autoRunFindings(autoRunDevContainer, fileName: fileName, parent: parent, format: .jsonWithComments)
        #expect(Set(result.map(\.kind)) == [.autorunHostCommand, .autorunContainerCommands])
        #expect(autoRunSummary(.autorunHostCommand, in: result) == "1 [5]")
        #expect(autoRunSummary(.autorunContainerCommands, in: result) == "3 [6, 7, 8]")
    }

    @Test(arguments: [
        ("devcontainer.json.bak", String?.some(".devcontainer")), ("devcontainers.json", ".devcontainer"), ("container.json", ".devcontainer"),
        ("devcontainer.jsonc", ".devcontainer"), ("devcontainer-lock.json", ".devcontainer"), ("settings.json", ".devcontainer")
    ])
    func otherFileNamesStaySilent(fileName: String, parent: String?) throws {
        #expect(try autoRunFindings(autoRunDevContainer, fileName: fileName, parent: parent).isEmpty)
    }

    @Test func everyLifecycleCommandIsCountedOnceAndOnlyWhenItHasContent() throws {
        let text = """
        {
          "onCreateCommand": "a",
          "updateContentCommand": "b",
          "postCreateCommand": "c",
          "postStartCommand": "d",
          "postAttachCommand": "e",
          "initializeCommand": \(autoRunToken)
        }
        """
        let result = try autoRunFindings(text, fileName: "devcontainer.json", parent: ".devcontainer")
        #expect(autoRunSummary(.autorunContainerCommands, in: result) == "5 [2, 3, 4, 5, 6]")
        #expect(autoRunSummary(.autorunHostCommand, in: result) == "1 [7]")
    }

    @Test(arguments: [
        #"{ "image": "x", "features": { "ghcr.io/devcontainers/features/node:1": {} } }"#,
        #"{ "initializeCommand": "", "onCreateCommand": [], "postCreateCommand": {}, "postStartCommand": null }"#,
        #"{ "Initializecommand": "x", "oncreatecommand": "y" }"#,
        #"{ "customizations": { "vscode": { "initializeCommand": "x", "postCreateCommand": "y" } } }"#,
        #"[ { "postCreateCommand": "x" } ]"#, "{}"
    ])
    func containersWithoutCommandsStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "devcontainer.json", parent: ".devcontainer").isEmpty)
    }
}

// MARK: - Package scripts

@Suite("Auto-run configuration lens: package scripts")
struct AutoRunPackageScriptTests {
    @Test(arguments: [FormatID.packageJSON, .json])
    func installTimeScriptsAreCountedAtTheirKeys(format: FormatID) throws {
        let result = try autoRunFindings(autoRunPackageFile, fileName: "package.json", parent: "demo", format: format)
        #expect(result.map(\.kind) == [.autorunInstallScripts])
        #expect(autoRunSummary(.autorunInstallScripts, in: result) == "3 [6, 7, 8]")
    }

    @Test func allSixLifecycleNamesCount() throws {
        let text = """
        { "scripts": {
          "preinstall": "a", "install": "b", "postinstall": "c",
          "prepare": "d", "preprepare": "e", "postprepare": "f"
        } }
        """
        #expect(autoRunSummary(.autorunInstallScripts, in: try autoRunFindings(text, fileName: "package.json", parent: nil)) == "6 [2, 3]")
    }

    @Test(arguments: [
        #"{ "scripts": { "build": "tsc", "test": "vitest", "start": "node .", "lint": "eslint", "dev": "vite", "clean": "rm -rf dist" } }"#,
        #"{ "scripts": { "prepublishOnly": "npm test", "prepack": "x", "postpack": "y", "pretest": "z", "posttest": "w" } }"#,
        #"{ "scripts": { "postinstall": "", "install": null, "preinstall": 5, "prepare": ["a"], "postprepare": {} } }"#,
        #"{ "scripts": [ "postinstall" ] }"#, #"{ "scripts": "postinstall" }"#, #"{ "postinstall": "node setup.js" }"#,
        #"{ "name": "x", "dependencies": { "postinstall": "1.0.0" } }"#, #"{ "scripts": { "Postinstall": "x", "post-install": "y" } }"#,
        "{}", "[]"
    ])
    func ordinaryScriptsStaySilent(text: String) throws {
        #expect(try autoRunFindings(text, fileName: "package.json", parent: nil).isEmpty)
    }

    @Test(arguments: ["package-lock.json", "composer.json", "package.json.bak", "packages.json", "tsconfig.json", "bower.json"])
    func otherManifestsStaySilent(fileName: String) throws {
        #expect(try autoRunFindings(autoRunPackageFile, fileName: fileName, parent: nil).isEmpty)
    }

    @Test func aConcealedScriptStillCounts() throws {
        let text = "{ \"scripts\": { \"postinstall\": \(autoRunToken) } }"
        #expect(autoRunSummary(.autorunInstallScripts, in: try autoRunFindings(text, fileName: "package.json", parent: nil)) == "1 [1]")
    }
}

