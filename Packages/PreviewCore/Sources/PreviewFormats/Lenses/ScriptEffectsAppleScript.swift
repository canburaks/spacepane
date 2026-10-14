import Foundation

// Placeholder: the AppleScript scanner and rules arrive in a later commit.
extension ScriptEffectsAnalyzer {
    func analyzeAppleScript(_ body: UnsafeBufferPointer<UInt8>, startLine: Int, depth: Int) throws {}

    func evaluateAppleScript(_ text: String, depth: Int, line: Int, effects: inout ScriptListEffects) throws {}
}
