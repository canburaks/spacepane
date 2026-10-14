import Foundation

// Placeholder: interpreters, here-documents fed to them and saved files arrive with the next commit.
extension ScriptEffectsAnalyzer {
    func evaluateInterpreter(_ kind: ScriptInterpreter, _ invocation: ScriptInvocation, _ command: ScriptCommand,
                             dialect: ScriptDialect, depth: Int, line: Int, effects: inout ScriptListEffects) throws {}

    func trackFiles(_ command: ScriptCommand, _ invocation: ScriptInvocation, dialect: ScriptDialect, line: Int,
                    files: inout ScriptSavedFiles) {}
}
