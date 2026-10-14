import Foundation

// Placeholder: the PowerShell rules arrive in a later commit.
extension ScriptEffectsAnalyzer {
    func evaluateWindows(_ list: ScriptCommandList, _ invocations: [ScriptInvocation?], dialect: ScriptDialect, depth: Int, line: Int,
                         inSubstitution: Bool, effects: inout ScriptListEffects) throws {}

    func evaluatePowerShellInvocation(_ arguments: [ScriptWord], depth: Int, line: Int, effects: inout ScriptListEffects) throws {}

    func evaluatePowerShellTool(_ tool: ScriptTool, _ texts: [String], effects: inout ScriptListEffects) {}
}
