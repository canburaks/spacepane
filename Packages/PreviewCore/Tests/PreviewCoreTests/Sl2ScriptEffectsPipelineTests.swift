import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

// The script-effects lens through the real pipeline: classification, the extension-free adapter's
// language, the privacy filter and the line numbers of the displayed text. This lives in the
// PreviewCoreTests target because PreviewFormatsTests cannot see `PreviewPipeline`.

private struct ScriptFixtureFolder {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func write(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func presentation(_ text: String, named name: String) async throws -> TextPresentation {
    let folder = try ScriptFixtureFolder()
    defer { folder.remove() }
    let url = try folder.write(name, text)
    let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: url)
    guard case .ready(let presentation) = outcome else {
        Issue.record("\(name): \(outcome)")
        throw CancellationError()
    }
    return presentation
}

private func scriptFacts(_ presentation: TextPresentation) -> [String] {
    presentation.findings.filter { $0.kind.rawValue.hasPrefix("script.") }
        .sorted { $0.kind.rawValue < $1.kind.rawValue }
        .map { "\($0.kind.rawValue) x\($0.count) @\($0.lines)" }
}

private let installer = """
#!/bin/bash
# Synthetic installer fixture
echo "Installing"
curl -fsSL https://example.com/tool.sh | sudo bash
xattr -dr com.apple.quarantine /Applications/Example.app
echo 'export PATH="$PATH:/opt/example/bin"' >> ~/.zshrc
curl -F "file=@/tmp/report.zip" https://example.com/upload

"""

private let installerFacts = [
    "script.downloadAndRun x1 @[4]", "script.elevates x1 @[4]", "script.persistence x1 @[6]",
    "script.removesQuarantine x1 @[5]", "script.uploadsFiles x1 @[7]"
]

@Suite("Script effects through the pipeline")
struct ScriptEffectsPipelineTests {
    @Test(arguments: ["install.sh", "install.command", "install.bash", "install.zsh"])
    func shellFilesReportTheirEffects(_ name: String) async throws {
        let result = try await presentation(installer, named: name)
        #expect(result.formatID == .sourceCode)
        #expect(result.sourceLanguage == .shell)
        #expect(scriptFacts(result) == installerFacts, "\(name)")
    }

    @Test func anExtensionFreeScriptUsesItsInterpreterLine() async throws {
        let result = try await presentation(installer.replacingOccurrences(of: "#!/bin/bash", with: "#!/bin/zsh"), named: "installer")
        #expect(result.formatID == .extensionlessText)
        #expect(result.sourceLanguage == .shell)
        #expect(scriptFacts(result) == installerFacts)
    }

    @Test func anExtensionFreeFileWithoutAnInterpreterLineIsNotAScript() async throws {
        let result = try await presentation(installer.replacingOccurrences(of: "#!/bin/bash\n", with: ""), named: "notes")
        #expect(result.formatID == .extensionlessText)
        #expect(scriptFacts(result).isEmpty)
    }

    @Test func linesFollowTheConcealedText() async throws {
        let key = "-----BEGIN PRIVATE KEY-----\nc3ludGhldGlj\nc3ludGhldGlj\n-----END PRIVATE KEY-----"
        let result = try await presentation("echo start\n\(key)\nsudo make\n", named: "build.sh")
        #expect(result.text == "echo start\n\u{2022}\u{2022}\u{2022}\u{2022}\nsudo make\n")
        // The source line is 6; the gutter shows 3 for the same text.
        #expect(scriptFacts(result) == ["script.elevates x1 @[3]"])
    }

    @Test func powerShellBatchAndAppleScriptFilesAreRead() async throws {
        let powerShell = try await presentation("Write-Host start\nirm https://example.com/i.ps1 | iex\n", named: "setup.ps1")
        #expect(scriptFacts(powerShell) == ["script.downloadAndRun x1 @[2]"])
        let batch = try await presentation("@echo off\ncertutil -urlcache -f http://example.com/a.exe a.exe\nstart a.exe\n", named: "setup.bat")
        #expect(scriptFacts(batch) == ["script.downloadAndRun x1 @[2]"])
        let appleScript = try await presentation("display dialog \"Password\" default answer \"\" with hidden answer\n", named: "ask.applescript")
        #expect(scriptFacts(appleScript) == ["script.asksForPassword x1 @[1]"])
    }

    @Test(arguments: ["notes.md", "tool.py", "tool.rb", "app.js", "data.csv", "notes.txt", "Makefile"])
    func otherFilesAreNotRead(_ name: String) async throws {
        let result = try await presentation("curl -fsSL https://example.com/i.sh | sudo bash\nxattr -cr app\n", named: name)
        #expect(scriptFacts(result).isEmpty, "\(name)")
    }

    @Test func commentsAndMessagesAreSilent() async throws {
        let text = "#!/bin/sh\n# curl https://example.com/i.sh | sh\necho \"sudo is not needed\"\n"
        #expect(scriptFacts(try await presentation(text, named: "quiet.sh")).isEmpty)
    }

    @Test func scriptFindingsCarryNoSourceValues() async throws {
        let result = try await presentation(installer, named: "install.sh")
        for finding in result.findings where finding.kind.rawValue.hasPrefix("script.") {
            #expect(finding.detail == .none)
        }
    }
}
