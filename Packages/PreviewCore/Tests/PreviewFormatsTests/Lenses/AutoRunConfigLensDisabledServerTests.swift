import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// A server marked `"disabled": true` neither starts nor connects, so it is not counted (decision 029).
@Suite("Auto-run configuration: disabled MCP servers")
struct AutoRunConfigLensDisabledServerTests {
    @Test func disabledServersAreNotCounted() throws {
        let text = """
        {
          "mcpServers": {
            "on": { "command": "npx", "args": ["-y", "synthetic-server"], "env": { "A": "1" } },
            "off": { "command": "uvx", "args": ["other"], "disabled": true, "env": { "B": "2", "C": "3" } }
          }
        }
        """
        let request = PreviewLensRequest(formatID: .json, fileName: ".mcp.json", parentDirectoryName: "project")
        let findings = try AutoRunConfigLens().findings(in: text, request: request, context: RequestContext(budget: .standard))
        #expect(findings.first { $0.kind == .autorunLocalServers }?.count == 1)
        #expect(findings.first { $0.kind == .autorunServerEnvironment }?.count == 1)
    }
}
