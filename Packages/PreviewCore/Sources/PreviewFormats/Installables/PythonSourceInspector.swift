import Foundation
import PreviewContracts

/// Install-time facts of a Python source distribution (decision 030). A source distribution is not
/// installed as it is: pip builds it first, and a build runs code from the package. The tarball is
/// recognized by its layout (one top folder holding `PKG-INFO`, as every sdist does) and reports that a
/// build script is present when the folder also holds a `setup.py`, or a `pyproject.toml` whose
/// `[build-system]` names a `backend-path`, an in-tree build backend. A source tree without `PKG-INFO` is
/// an ordinary archive, and a `.pth` file inside an sdist is not installed, so neither says anything.
enum PythonSourceInspector {
    /// The findings for a source distribution that carries a build script, or `nil` for any other archive.
    static func findings(layout: InstallableLayout, capture: InstallableCapture,
                         context: RequestContext) throws -> [PreviewFinding]? {
        guard layout.has("PKG-INFO") else { return nil }
        var runsBuildCode = layout.has("setup.py")
        if !runsBuildCode, layout.has("pyproject.toml"), let data = capture.payloads[layout.path(of: "pyproject.toml")] {
            runsBuildCode = try PyprojectBuildSystem.declaresBackendPath(data, context: context)
        }
        guard runsBuildCode else { return nil }
        return [PreviewFinding(kind: .installBuildScript, count: 1)]
    }
}
