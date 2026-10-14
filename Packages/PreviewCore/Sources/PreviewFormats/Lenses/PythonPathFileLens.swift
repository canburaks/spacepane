import Foundation
import PreviewContracts

/// Reports the startup code in a Python path configuration file (`.pth`), decision 030.
///
/// Python's `site` module reads every `.pth` file in a site-packages folder at every start of the
/// interpreter. It adds each line to the module search path, except that a line beginning with `import`
/// and a space or a tab is executed. That is how the LiteLLM supply-chain file ran code in every Python
/// process on a machine. The finding counts those lines and points at them; it carries nothing from them.
///
/// The lens reads the shown text of a file the pickle adapter returned as source text, so it never sees
/// the summary of a pickle or checkpoint that happens to have a `.pth` name. Comments and path lines are
/// silent. Nothing is run, evaluated or decoded.
public struct PythonPathFileLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        guard request.origin == .source, request.fileName.lowercased().hasSuffix(".pth") else { return [] }
        let lines = try PythonStartupLines.lines(in: text, context: context)
        guard !lines.isEmpty else { return [] }
        return [PreviewFinding(kind: .installStartupCode, count: lines.count, lines: lines)]
    }
}
