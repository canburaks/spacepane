import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Token soup: scripts assembled from the fragments the lexers treat specially, in a fixed pseudo-random
// order. The lens must finish on all of them and never trap; what it reports is not asserted.

@Suite("Script effects: token soup")
struct ScriptEffectsFuzzTests {
    private static let fragments: [String] = [
        "\"", "'", "$(", ")", "(", "`", "$((", "))", "${", "}", "{", "<<EOF", "<<-X", "<<<", "EOF", "X", "\n", "\r\n", "\u{85}", "\u{2028}",
        "|", "||", "&&", "&", ";", ";;", "\\", "\\\n", "#", "<", ">", ">>", "&>", "2>&1", "<(", ">(", " ", "\t", "=", "+=", "!",
        "sudo", "curl", "wget", "sh", "bash", "-c", "-s", "-S", "-o", "-F", "base64 -d", "xattr -cr", "eval", "source", ".", "osascript -e",
        "case", "esac", "in", "a)", "[[", "]]", "function", "if", "then", "fi", "do", "done", "x=(", "$x", "~/.ssh/id_rsa", "LaunchAgents/",
        "<#", "#>", "@\"", "\"@", "@'", "'@", "iex", "irm", "-enc", "Get-Credential", "-Verb", "RunAs", "$(", "%x%", "^", "rem", "::",
        "(*", "*)", "--", "¬", "with hidden answer", "do shell script", "make login item", "\u{0}", "\u{FEFF}", "é", "日本", "\u{200B}"
    ]

    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    @Test(arguments: [SourceLanguageID.shell, .fish, .powerShell, .batch, .appleScript])
    func randomFragmentsNeverTrapOrHang(_ language: SourceLanguageID) throws {
        var generator = Generator(state: 0x5EED)
        for _ in 0..<400 {
            var text = ""
            for _ in 0..<(20 + generator.next(180)) {
                text += Self.fragments[generator.next(Self.fragments.count)]
                if generator.next(3) == 0 { text += " " }
            }
            _ = try ScriptFixture.findings(text, language: language)
        }
    }
}
