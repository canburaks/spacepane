import Foundation
import PreviewContracts

/// launchd job lens: what a LaunchAgent or LaunchDaemon property list makes macOS run, and when.
/// Decision 029. Workstream `sl2-config` owns this file. Placeholder until the workstream lands.
public struct LaunchdJobLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        []
    }
}
