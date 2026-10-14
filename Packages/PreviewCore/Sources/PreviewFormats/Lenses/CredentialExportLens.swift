import Foundation
import PreviewContracts

/// Readable credential exports: password-manager and one-time-code exports saved without encryption.
/// Decision 029. Workstream `sl2-config` owns this file. Placeholder until the workstream lands.
public struct CredentialExportLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        []
    }
}
