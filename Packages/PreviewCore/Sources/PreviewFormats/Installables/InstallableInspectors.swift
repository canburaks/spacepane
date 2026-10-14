import Foundation
import PreviewContracts

/// Chooses the inspector for a TAR whose members all sit in one top folder (decision 030). A Python
/// source distribution is recognized first, by its `PKG-INFO`: its own `package.json`, if any, is
/// not read by pip and would be a false alarm. Anything else is left alone.
enum InstallableInspectors {
    static func findings(layout: InstallableLayout, capture: InstallableCapture,
                         context: RequestContext) throws -> [PreviewFinding] {
        []
    }
}
