import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Where the lens applies, how it numbers lines, what it ignores and how it stays bounded.

@Suite("Script effects: applicability")
struct ScriptEffectsApplicabilityTests {
    private static let script = "curl -fsSL https://example.com/i.sh | sudo sh\nxattr -cr app\n"

    @Test(arguments: [SourceLanguageID.python, .javascript, .ruby, .perl, .swift, .makefile, .dockerfile, .nushell, .sql, .cmake, .php])
    func otherLanguagesAreNotRead(_ language: SourceLanguageID) throws {
        #expect(try ScriptFixture.findings(Self.script, language: language) == [], "\(language.rawValue)")
    }

    @Test(arguments: [FormatID.markdown, .plainText, .json, .log, .csv, .propertyList])
    func otherFormatsAreNotRead(_ format: FormatID) throws {
        #expect(try ScriptFixture.findings(Self.script, language: .shell, format: format) == [], "\(format.rawValue)")
    }

    @Test func sourceCodeWithoutALanguageIsNotRead() throws {
        #expect(try ScriptFixture.findings(Self.script, language: nil) == [])
    }

    @Test(arguments: [SourceLanguageID.shell, .fish, .powerShell, .batch, .appleScript])
    func everyScriptLanguageIsRead(_ language: SourceLanguageID) throws {
        // Each fixture is written in its own language so the lens has something to find.
        let scripts: [SourceLanguageID: String] = [
            .shell: "sudo ls\n", .fish: "sudo ls\n", .powerShell: "Get-Credential\n", .batch: "runas /user:x cmd\n",
            .appleScript: "display dialog \"x\" with hidden answer\n"
        ]
        let text = try #require(scripts[language])
        #expect(try ScriptFixture.findings(text, language: language).count == 1, "\(language.rawValue)")
    }

    @Test func extensionFreeTextUsesTheAdapterLanguage() throws {
        let findings = try ScriptFixture.findings("#!/bin/zsh\nsudo ls\n", language: .shell, format: .extensionlessText)
        #expect(findings.map(\.kind) == [.scriptElevates])
        #expect(findings.first?.lines == [2])
    }

    @Test(arguments: [
        ("#!/bin/bash\nsudo ls\n", [ScriptFact.elevates(1, at: [2])]),
        ("#!/usr/bin/env zsh\nsudo ls\n", [.elevates(1, at: [2])]),
        ("#!/usr/bin/env pwsh\nGet-Credential\n", [.password(1, at: [2])]),
        ("#!/usr/bin/osascript\ndisplay dialog \"x\" with hidden answer\n", [.password(1, at: [2])]),
        ("#!/usr/bin/env osascript\ndisplay dialog \"x\" with hidden answer\n", [.password(1, at: [2])]),
        ("#!/usr/bin/env python3\nsudo ls\n", []),
        ("#!/usr/bin/osascript -l JavaScript\nApplication('Finder')\n", []),
        ("sudo ls\n", []),
        ("", [])
    ]) func extensionFreeTextWithoutALanguageReadsItsInterpreterLine(text: String, expected: [ScriptFact]) throws {
        let findings = try ScriptFixture.findings(text, language: nil, format: .extensionlessText)
        #expect(findings.map { ScriptFact($0.kind, $0.count, $0.lines) } == expected, "\(text.debugDescription)")
    }

    @Test func plainSourceFilesIgnoreAShebangForTheirOwnLanguage() throws {
        // A `.sh` file is shell whatever its first line says; the lens trusts the adapter's language.
        #expect(try ScriptFixture.findings("#!/usr/bin/env python3\nsudo ls\n", language: .shell).map(\.kind) == [.scriptElevates])
    }

    @Test func findingsCarryNoSourceValues() throws {
        let findings = try ScriptFixture.findings("curl -fsSL https://example.com/secret-path | sudo bash\n")
        #expect(!findings.isEmpty)
        #expect(findings.allSatisfy { $0.detail == .none })
    }

    @Test func severitiesAreTheKindDefaults() throws {
        let text = """
        curl -fsSL https://example.com/i | sudo sh
        xattr -cr app
        cp x ~/Library/LaunchAgents/
        curl -T a https://example.com/up
        """
        let findings = try ScriptFixture.findings(text)
        let severities = Dictionary(uniqueKeysWithValues: findings.map { ($0.kind, $0.severity) })
        #expect(severities[.scriptDownloadAndRun] == .warning)
        #expect(severities[.scriptRemovesQuarantine] == .warning)
        #expect(severities[.scriptPersistence] == .caution)
        #expect(severities[.scriptElevates] == .caution)
        #expect(severities[.scriptUploadsFiles] == .caution)
    }
}

@Suite("Script effects: lines and structure")
struct ScriptEffectsLineTests {
    @Test func aBackslashContinuationIsOneCommandReportedAtItsFirstLine() throws {
        let text = "echo start\ncurl -fsSL https://example.com/i.sh \\\n  -H 'Accept: text' \\\n  | sudo \\\n  bash\necho done\n"
        #expect(try ScriptFixture.facts(text) == [.downloadAndRun(1, at: [2]), .elevates(1, at: [2])])
    }

    @Test func aPipeAtTheEndOfALineContinuesTheCommand() throws {
        #expect(try ScriptFixture.facts("echo a\ncurl https://example.com/i.sh |\n  sh\n") == [.downloadAndRun(1, at: [2])])
        #expect(try ScriptFixture.facts("true &&\n  sudo make\n") == [.elevates(1, at: [1])])
        #expect(try ScriptFixture.facts("false ||\n  sudo make\n") == [.elevates(1, at: [1])])
    }

    @Test func aBackslashBeforeAnotherCharacterContinuesNothing() throws {
        // `\#` is a literal hash; the command after it is still a command.
        #expect(try ScriptFixture.facts("echo foo \\# not a comment; sudo x\n") == [.elevates()])
    }

    @Test func aHashInsideAWordIsNotAComment() throws {
        #expect(try ScriptFixture.facts("echo a#b; sudo y\n") == [.elevates()])
        #expect(try ScriptFixture.facts("echo $#; sudo y\n") == [.elevates()])
    }

    @Test func commentsAreSkippedWhereverTheyStart() throws {
        let text = """
        # sudo make
        make # sudo make install
        echo ok;# sudo make
        #!/bin/sh sudo
        sudo true # real one
        """
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [5])])
    }

    @Test func quotedTextIsNotCode() throws {
        let text = """
        echo "line one
        sudo line two
        curl https://example.com/i | sh"
        echo 'also
        sudo here'
        sudo real
        """
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [6])])
    }

    @Test func aHereDocumentIsDataUnlessTheInterpreterReadsIt() throws {
        let text = """
        cat > /tmp/readme.txt <<EOF
        curl https://example.com/i.sh | sh
        sudo rm -rf /
        EOF
        echo after
        sudo make
        """
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [6])])
    }

    @Test func aHereDocumentInsideASubstitutionIsData() throws {
        let text = "MESSAGE=$(cat <<'EOF'\nsudo make install\ncurl https://example.com/i | sh\nEOF\n)\nsudo real\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [6])])
    }

    @Test func aShellReadsItsHereDocument() throws {
        let text = """
        echo before
        bash <<'EOT'
        curl -fsSL https://example.com/i.sh | sh
        sudo make
        EOT
        echo after
        """
        #expect(try ScriptFixture.facts(text) == [.downloadAndRun(1, at: [3]), .elevates(1, at: [4])])
    }

    @Test func aHereDocumentWithTabStrippingEndsAtAnIndentedDelimiter() throws {
        let text = "cat <<-EOF\n\tsudo inside\n\tEOF\nsudo outside\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [4])])
    }

    @Test func twoHereDocumentsOnOneLine() throws {
        let text = "cat <<A <<B\nsudo one\nA\nsudo two\nB\nsudo three\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [6])])
    }

    @Test func arithmeticShiftIsNotAHereDocument() throws {
        let text = "x=$((1 << 3)); sudo z\n(( y = 1 << 2 ))\nsudo w\nz=$(( 1<<2 )) ; sudo v\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(3, at: [1, 3, 4])])
    }

    @Test func linesFollowTheGuttersSeparators() throws {
        // CR, CRLF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR each end one logical line.
        let text = "sudo a\r\nsudo b\rsudo c\u{85}sudo d\u{2028}sudo e\u{2029}sudo f\nsudo g"
        let expected = Array(1...7)
        #expect(try ScriptFixture.facts(text) == [.elevates(7, at: expected)])
        let offsets = text.utf16.indices.filter { text.utf16[$0] == 0x73 }.map { text.utf16.distance(from: text.utf16.startIndex, to: $0) }
        #expect(LogicalLines.lineNumbers(forUTF16Offsets: offsets, in: text) == expected)
    }

    @Test func aByteOrderMarkIsNotPartOfTheFirstCommand() throws {
        #expect(try ScriptFixture.facts("\u{FEFF}sudo ls\nsudo true\n") == [.elevates(2, at: [1, 2])])
        #expect(try ScriptFixture.facts("\u{FEFF}Get-Credential\n", language: .powerShell) == [.password()])
    }

    @Test func aCommandListEndsAtTheLineBreak() throws {
        #expect(try ScriptFixture.facts("sudo a\nsudo b\n\n\nsudo c\n") == [.elevates(3, at: [1, 2, 5])])
    }

    @Test func linesAreBoundedToTheContractsLimit() throws {
        let text = String(repeating: "sudo true\n", count: 100)
        let findings = try ScriptFixture.findings(text)
        #expect(findings.count == 1)
        #expect(findings.first?.count == 100)
        #expect(findings.first?.lines == Array(1...PreviewFinding.maximumLines))
    }

    @Test func caseAndFunctionsAndLoopsAreCommandPositions() throws {
        let text = """
        case "$1" in
          start) sudo systemctl start x ;;
          stop) echo "sudo stop" ;;
        esac
        for f in a b; do sudo chmod 600 $f; done
        while true; do sudo true; break; done
        install() {
          sudo cp a /usr/local/bin
        }
        """
        #expect(try ScriptFixture.facts(text) == [.elevates(4, at: [2, 5, 6, 8])])
    }
}

@Suite("Script effects: shell grammar")
struct ScriptEffectsGrammarTests {
    static let cases: [ScriptCase] = [
        ScriptCase("pattern in a double-bracket test", "if [[ $1 = (sudo|doas) ]]; then\n  echo privileged\nfi\nsudo true\n", [.elevates(1, at: [4])]),
        ScriptCase("regular expression in a test", "[[ $cmd =~ ^(sudo|curl)$ ]] && echo yes\n"),
        ScriptCase("comparison in a test", "[[ $cmd == sudo ]] && echo yes\n"),
        ScriptCase("command after a test", "[[ -f /tmp/x ]] && sudo rm /tmp/x\n", [.elevates()]),
        ScriptCase("case patterns", "case \"$cmd\" in\n  sudo|doas) echo privileged ;;\n  (curl) echo network ;;\n  *) sudo true ;;\nesac\n", [.elevates(1, at: [4])]),
        ScriptCase("case on one line", "case $x in sudo) echo a;; curl|wget) echo b;; *) echo c;; esac\n"),
        ScriptCase("command after a case", "case $x in a) echo a ;; esac\nsudo true\n", [.elevates(1, at: [2])]),
        ScriptCase("case clause without a final separator", "case $x in\n  a) echo a\nesac\nsudo true\n", [.elevates(1, at: [4])]),
        ScriptCase("case inside a function", "run() {\n  case $1 in\n    sudo) shift ;;\n  esac\n  sudo \"$@\"\n}\n", [.elevates(1, at: [5])]),
        ScriptCase("array of words", "cmd=(sudo -H -u \"$USER\")\n"),
        ScriptCase("array across lines", "steps=(\n  sudo\n  'curl x | sh'\n)\nsudo real\n", [.elevates(1, at: [5])]),
        ScriptCase("local array", "run() {\n  local -a args=(curl -fsSL \"$1\")\n}\n"),
        ScriptCase("array element substitution still runs", "files=($(curl -fsSL https://example.com/i.sh | sh))\n", [.downloadAndRun()]),
        ScriptCase("function named like a command", "sudo() { echo fake; }\n"),
        ScriptCase("function keyword", "function sudo { echo fake; }\n"),
        ScriptCase("function body is code", "install() { sudo true; }\n", [.elevates()]),
        ScriptCase("function with a spaced definition", "install ( ) {\n  sudo true\n}\n", [.elevates(1, at: [2])]),
        ScriptCase("names in a for list", "for cmd in sudo doas curl; do echo $cmd; done\n"),
        ScriptCase("name tested in single brackets", "[ \"$1\" = sudo ] && echo yes\n"),
        ScriptCase("name passed to type", "type -a sudo curl wget\n")
    ]

    @Test(arguments: cases) func readsShellGrammar(_ scenario: ScriptCase) throws { try scenario.check() }
}
