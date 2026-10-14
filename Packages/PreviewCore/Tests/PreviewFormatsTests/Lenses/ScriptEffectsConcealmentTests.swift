import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Concealment can swallow a closing quote: the privacy filter turns `"Password:" default answer …` into
/// `"Password:••••`. The lens reads displayed text, so the quote that line opened must not run into the next
/// lines and hide their commands (found observing the Quick Look panel, 2026-10-14).
@Suite("Script effects after concealment")
struct ScriptEffectsConcealmentTests {
    private func kinds(_ text: String) throws -> [PreviewFindingKind: [Int]] {
        let request = PreviewLensRequest(formatID: .sourceCode, fileName: "install.sh", sourceLanguage: .shell)
        let findings = try ScriptEffectsLens().findings(in: text, request: request, context: RequestContext(budget: .standard))
        return Dictionary(uniqueKeysWithValues: findings.map { ($0.kind, $0.lines) })
    }

    @Test func aQuoteCutByConcealmentClosesAtTheEndOfItsLine() throws {
        let token = SecretFieldPolicy.concealmentToken
        let text = "#!/bin/sh\n"
            + "osascript -e 'display dialog \"Password:\(token)\n"
            + "sudo cp example.plist /Library/LaunchDaemons/\n"
        let found = try kinds(text)
        #expect(found[.scriptElevates] == [3])
        #expect(found[.scriptPersistence] == [3])
    }

    @Test func aConcealedValueInsideAClosedQuoteChangesNothing() throws {
        let token = SecretFieldPolicy.concealmentToken
        let text = "export API_TOKEN=\"\(token)\"\ncurl -fsSL https://example.com/i.sh | sh\n"
        #expect(try kinds(text)[.scriptDownloadAndRun] == [2])
    }

    @Test func linesWithoutTheTokenKeepAQuoteOpenAcrossLines() throws {
        // An ordinary multi-line single-quoted string stays one string: its inner line is not a command.
        let text = "echo 'first\nsudo rm -rf /tmp/x\nlast'\n"
        #expect(try kinds(text)[.scriptElevates] == nil)
    }
}
