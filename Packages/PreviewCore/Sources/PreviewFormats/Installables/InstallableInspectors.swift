import Foundation
import PreviewContracts

/// Chooses the inspector for a TAR whose members all sit in one top folder (decision 030). A Python
/// source distribution is recognized by its `PKG-INFO` before anything else: its own `package.json`, if
/// it has one, is not read by pip and would be a false alarm. Anything else is left alone, and an
/// archive no inspector recognizes gets exactly the findings its listing already had.
enum InstallableInspectors {
    static func findings(layout: InstallableLayout, capture: InstallableCapture,
                         context: RequestContext) throws -> [PreviewFinding] {
        let recognized: [PreviewFinding]?
        if layout.has("PKG-INFO") {
            recognized = try PythonSourceInspector.findings(layout: layout, capture: capture, context: context)
        } else {
            recognized = try NPMPackageInspector.findings(layout: layout, capture: capture, context: context)
        }
        guard let recognized else { return [] }
        return PreviewFindings.normalized(recognized + (capture.native.finding.map { [$0] } ?? []))
    }
}
