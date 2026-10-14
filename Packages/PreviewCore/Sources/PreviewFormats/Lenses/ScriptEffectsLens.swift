import Foundation
import PreviewContracts

/// Script effects lens: what a shell, AppleScript, PowerShell or batch script would do when run.
/// Decision 029. Workstream `sl2-script` owns this file. Placeholder until the workstream lands.
public struct ScriptEffectsLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        []
    }
}
