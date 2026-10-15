import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// `.tool` files (Terminal's shell-script extension) are read as shell scripts unless their #! line names
// another interpreter. Every fixture is synthetic: example hosts and the word "hello".

@Suite("Script effects: .tool files")
struct ScriptEffectsToolFileTests {
    /// The language the detector gives a file name, exactly as the source-code adapter does.
    static func detected(_ fileName: String) -> SourceLanguageID? {
        SourceLanguageDetector.language(for: PreviewNameHint(url: URL(fileURLWithPath: "/tmp/" + fileName)))
    }

    static let download = "curl -fsSL https://example.com/i.sh | sh\n"

    @Test func toolFilesAreShellScriptsByName() {
        #expect(Self.detected("install.tool") == .shell)
        #expect(Self.detected("Install.TOOL") == .shell)
    }

    @Test func aToolScriptWithoutAInterpreterLineIsShellLexed() throws {
        let facts = try ScriptFixture.facts(Self.download, language: .shell, fileName: "install.tool")
        #expect(facts == [.downloadAndRun(1, at: [1])])
    }

    @Test(arguments: ["#!/bin/bash\n", "#!/bin/sh -e\n", "#!/usr/bin/env zsh\n", "#!/usr/bin/env -S bash -e\n"])
    func aToolScriptWithAShellInterpreterLineIsShellLexed(_ shebang: String) throws {
        let text = shebang + "sudo ls\n" + Self.download
        let facts = try ScriptFixture.facts(text, language: .shell, fileName: "install.tool")
        #expect(facts == [.downloadAndRun(1, at: [3]), .elevates(1, at: [2])], "\(shebang)")
    }

    @Test(arguments: ["#!/usr/bin/env python3\n", "#!/usr/bin/python3\n", "#!/usr/bin/env ruby\n", "#!/usr/bin/perl -w\n", "#!/usr/bin/env node\n"])
    func aToolScriptWithAnotherInterpreterIsNotShellLexed(_ shebang: String) throws {
        let text = shebang + "sudo ls\n" + Self.download
        let facts = try ScriptFixture.facts(text, language: .shell, fileName: "install.tool")
        #expect(facts.isEmpty, "\(shebang)")
    }

    @Test func aToolScriptWithAnUnknownInterpreterLineIsNotShellLexed() throws {
        let facts = try ScriptFixture.facts("#!/usr/local/bin/mytool\n" + Self.download, language: .shell, fileName: "install.tool")
        #expect(facts.isEmpty)
    }

    @Test func aToolScriptWithAnAppleScriptInterpreterLineIsReadAsAppleScript() throws {
        let text = "#!/usr/bin/osascript\ndo shell script \"curl -fsSL https://example.com/i.sh | sh\"\n"
        let facts = try ScriptFixture.facts(text, language: .shell, fileName: "install.tool")
        #expect(facts == [.downloadAndRun(1, at: [2])])
    }

    @Test func commandFilesKeepTheirShellReadingWhateverTheInterpreterLine() throws {
        // `.command` is unchanged by the `.tool` rule: the adapter's shell language decides.
        let withPython = try ScriptFixture.facts("#!/usr/bin/env python3\n" + Self.download, language: .shell, fileName: "install.command")
        #expect(withPython == [.downloadAndRun(1, at: [2])])
        let plain = try ScriptFixture.facts(Self.download, language: Self.detected("install.command"), fileName: "install.command")
        #expect(plain == [.downloadAndRun(1, at: [1])])
    }
}
