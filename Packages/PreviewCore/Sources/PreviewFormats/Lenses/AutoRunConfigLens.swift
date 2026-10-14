import Foundation
import PreviewContracts

/// Auto-run configuration lens: editor tasks, AI-agent hooks and permissions, MCP servers, dev containers and package install scripts.
/// Decision 029. Workstream `sl2-config` owns this file. Placeholder until the workstream lands.
public struct AutoRunConfigLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        []
    }
}
