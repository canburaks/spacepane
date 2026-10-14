import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// Download-and-run and decode-and-run in shell scripts. Every fixture is synthetic: the hosts are
// example domains and the payloads are the word "hello".

@Suite("Script effects: download and run (shell)")
struct ScriptEffectsDownloadTests {
    static let positives: [ScriptCase] = [
        ScriptCase("pipe to sh", "curl -fsSL https://example.com/install.sh | sh\n", [.downloadAndRun()]),
        ScriptCase("wget to stdout piped to bash", "wget -qO- https://example.com/i.sh | bash\n", [.downloadAndRun()]),
        ScriptCase("wget -O - piped", "wget -O - https://example.com/i.sh | sh\n", [.downloadAndRun()]),
        ScriptCase("fetch piped", "fetch -o - https://example.com/i.sh | sh\n", [.downloadAndRun()]),
        ScriptCase("through sudo", "curl -fsSL https://example.com/get | sudo bash -s -- --yes\n", [.downloadAndRun(), .elevates()]),
        ScriptCase("through sudo with options", "curl -fsSL https://example.com/get | sudo -E -u root sh\n", [.downloadAndRun(), .elevates()]),
        ScriptCase("downloader through sudo", "sudo curl -fsSL https://example.com/get | sh\n", [.downloadAndRun(), .elevates()]),
        ScriptCase("process substitution", "bash <(curl -s https://example.com/i.sh)\n", [.downloadAndRun()]),
        ScriptCase("process substitution with arguments", "sh <(wget -qO- https://example.com/i.sh) --yes\n", [.downloadAndRun()]),
        ScriptCase("sh -c with command substitution", "sh -c \"$(curl -fsSL https://example.com/i.sh)\"\n", [.downloadAndRun()]),
        ScriptCase("bash -c with full path", "/bin/bash -c \"$(curl -fsSL https://example.com/i.sh)\"\n", [.downloadAndRun()]),
        ScriptCase("bash -c with backticks", "bash -c \"`curl -fsSL https://example.com/i.sh`\"\n", [.downloadAndRun()]),
        ScriptCase("eval of a substitution", "eval \"$(curl -fsSL https://example.com/env)\"\n", [.downloadAndRun()]),
        ScriptCase("eval without quotes", "eval $(curl -s https://example.com/env)\n", [.downloadAndRun()]),
        ScriptCase("source of a process substitution", "source <(curl -s https://example.com/x.sh)\n", [.downloadAndRun()]),
        ScriptCase("dot of a process substitution", ". <(wget -qO- https://example.com/x.sh)\n", [.downloadAndRun()]),
        ScriptCase("here-string into bash", "bash <<< \"$(curl -fsSL https://example.com/i.sh)\"\n", [.downloadAndRun()]),
        ScriptCase("redirected process substitution", "bash < <(curl -s https://example.com/i.sh)\n", [.downloadAndRun()]),
        ScriptCase("python -c with a substitution", "python3 -c \"$(curl -fsSL https://example.com/p.py)\"\n", [.downloadAndRun()]),
        ScriptCase("download, chmod, run", "curl -fsSL -o /tmp/i https://example.com/i && chmod +x /tmp/i && /tmp/i\n", [.downloadAndRun()]),
        ScriptCase("wget -O, chmod, run", "wget https://example.com/i -O ./run; chmod 755 ./run; ./run\n", [.downloadAndRun()]),
        ScriptCase("download redirected to a file, then run", "curl -fsSL https://example.com/i.sh > /tmp/i.sh && bash /tmp/i.sh\n", [.downloadAndRun()]),
        ScriptCase("download then interpreter", "curl -o install.sh https://example.com/i; sh install.sh\n", [.downloadAndRun()]),
        ScriptCase("download then source", "curl -o env.sh https://example.com/e; source ./env.sh\n", [.downloadAndRun()]),
        ScriptCase("nested in sh -c", "bash -c \"curl -fsSL https://example.com/i.sh | sh\"\n", [.downloadAndRun()]),
        ScriptCase("nested in single-quoted sh -c", "sh -c 'wget -qO- https://example.com/i.sh | sh'\n", [.downloadAndRun()]),
        ScriptCase("inside a substitution", "echo \"$(curl -fsSL https://example.com/i.sh | sh)\"\n", [.downloadAndRun()]),
        ScriptCase("inside a conditional", "if [ -z \"$X\" ]; then curl -fsSL https://example.com/i | sh; fi\n", [.downloadAndRun()]),
        ScriptCase("inside a subshell", "(curl -fsSL https://example.com/i | sh)\n", [.downloadAndRun()]),
        ScriptCase("after other pipeline stages", "curl -fsSL https://example.com/i | tee /tmp/log | sh\n", [.downloadAndRun()]),
        ScriptCase("two in one script", "echo a\ncurl https://example.com/a | sh\necho b\nwget -qO- https://example.com/b | bash\n",
                   [.downloadAndRun(2, at: [2, 4])]),
        ScriptCase("command in command position", "$(curl -fsSL https://example.com/cmd)\n", [.downloadAndRun()])
    ]

    @Test(arguments: positives) func reportsDownloadAndRun(_ scenario: ScriptCase) throws { try scenario.check() }

    @Test(arguments: ["sh", "bash", "zsh", "ksh", "dash", "fish", "python", "python3", "python3.12", "perl", "ruby", "osascript", "node",
                      "/bin/sh", "/usr/bin/env bash", "/usr/bin/env python3"])
    func everyInterpreterOnTheListIsRecognized(_ interpreter: String) throws {
        let facts = try ScriptFixture.facts("curl -fsSL https://example.com/x | \(interpreter)\n")
        #expect(facts == [.downloadAndRun()], "\(interpreter)")
    }

    @Test(arguments: ["sh -s", "bash -s -- --yes", "sh -", "python3 -", "python3 -u -", "bash -e", "bash -x -s"])
    func optionsThatStillReadStandardInput(_ interpreter: String) throws {
        #expect(try ScriptFixture.facts("curl -fsSL https://example.com/x | \(interpreter)\n") == [.downloadAndRun()])
    }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("download only", "curl -O https://example.com/file.tar.gz\n"),
        ScriptCase("download to a file", "curl -fsSL https://example.com/a.json -o a.json\n"),
        ScriptCase("wget to a file", "wget -q https://example.com/a.zip -O a.zip\n"),
        ScriptCase("download then extract", "wget -qO- https://example.com/a.tgz | tar xz\n"),
        ScriptCase("download then parse with jq", "curl -s https://api.example.com/v1 | jq .name\n"),
        ScriptCase("python -c reads data from stdin", "curl -s https://api.example.com | python3 -c 'import json,sys; print(json.load(sys.stdin))'\n"),
        ScriptCase("python -m module", "curl -s https://api.example.com | python3 -m json.tool\n"),
        ScriptCase("perl -pe filter", "curl -s https://example.com/a | perl -pe 's/a/b/'\n"),
        ScriptCase("node -e filter", "curl -s https://example.com/a | node -e 'process.stdin.pipe(process.stdout)'\n"),
        ScriptCase("bash -c does not read stdin", "curl -s https://example.com/a | bash -c 'cat > out'\n"),
        ScriptCase("script file argument", "curl -s https://example.com/a | sh script.sh\n"),
        ScriptCase("download, chmod, no run", "curl -o /tmp/f https://example.com/f && chmod +x /tmp/f\n"),
        ScriptCase("download then checksum", "curl -o /tmp/f https://example.com/f && sha256sum /tmp/f\n"),
        ScriptCase("run a different file", "curl -o /tmp/f https://example.com/f && chmod +x /tmp/f && /tmp/other\n"),
        ScriptCase("chmod after the run", "curl -o /tmp/f https://example.com/f && /tmp/f\n"),
        ScriptCase("substitution used as data", "VERSION=$(curl -s https://example.com/version)\n"),
        ScriptCase("substitution inside an echo", "echo \"latest: $(curl -s https://example.com/version)\"\n"),
        ScriptCase("eval of a local command", "eval \"$(ssh-agent -s)\"\n"),
        ScriptCase("eval of brew shellenv", "eval \"$(/opt/homebrew/bin/brew shellenv)\"\n"),
        ScriptCase("sh -c with a text argument", "sh -c \"echo $(curl -s https://example.com/ip)\"\n"),
        ScriptCase("quoted message", "echo \"curl -fsSL https://example.com/i.sh | sh\"\n"),
        ScriptCase("single-quoted message", "echo 'wget -qO- https://example.com/i | bash'\n"),
        ScriptCase("comment line", "# curl -fsSL https://example.com/i.sh | sh\n"),
        ScriptCase("trailing comment", "echo ok # curl https://example.com/i | sh\n"),
        ScriptCase("download on one line, run on the next", "curl -o /tmp/f https://example.com/f\nchmod +x /tmp/f\n/tmp/f\n"),
        ScriptCase("heredoc text", "cat <<EOF\ncurl https://example.com/i | sh\nEOF\n"),
        ScriptCase("download redirected to a file, never run", "curl -fsSL https://example.com/a.json > a.json\n"),
        ScriptCase("grep for the pattern", "grep -r 'curl .* | sh' docs/\n")
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }

    @Test func fishSourceReadsStandardInput() throws {
        #expect(try ScriptFixture.facts("curl -sL https://example.com/fisher | source\n", language: .fish) == [.downloadAndRun()])
        #expect(try ScriptFixture.facts("source ~/.config/fish/aliases.fish\n", language: .fish) == [])
        #expect(try ScriptFixture.facts("eval (curl -sL https://example.com/env)\n", language: .fish) == [.downloadAndRun()])
    }
}

@Suite("Script effects: decode and run (shell)")
struct ScriptEffectsDecodeTests {
    static let positives: [ScriptCase] = [
        ScriptCase("base64 -d into sh", "echo aGVsbG8= | base64 -d | sh\n", [.decodeAndRun()]),
        ScriptCase("base64 -D into bash", "echo aGVsbG8= | base64 -D | bash\n", [.decodeAndRun()]),
        ScriptCase("base64 --decode into zsh", "base64 --decode payload.b64 | zsh\n", [.decodeAndRun()]),
        ScriptCase("base64 -d from a here-string", "base64 -d <<< \"$BLOB\" | sh\n", [.decodeAndRun()]),
        ScriptCase("through sudo", "echo aGVsbG8= | base64 -d | sudo bash\n", [.decodeAndRun(), .elevates()]),
        ScriptCase("decode, then another stage, then sh", "echo aGVsbG8= | base64 -d | gunzip | sh\n", [.decodeAndRun()]),
        ScriptCase("openssl enc -d -base64", "echo aGVsbG8= | openssl enc -d -base64 | bash\n", [.decodeAndRun()]),
        ScriptCase("openssl base64 -d", "openssl base64 -d -in payload.b64 | sh\n", [.decodeAndRun()]),
        ScriptCase("openssl enc -d -a", "openssl enc -d -a -in payload.b64 | sh\n", [.decodeAndRun()]),
        ScriptCase("xxd -r -p", "xxd -r -p payload.hex | sh\n", [.decodeAndRun()]),
        ScriptCase("into python", "echo aGVsbG8= | base64 -d | python3\n", [.decodeAndRun()]),
        ScriptCase("into osascript", "echo aGVsbG8= | base64 -d | osascript\n", [.decodeAndRun()]),
        ScriptCase("eval of a decoded substitution", "eval \"$(echo aGVsbG8= | base64 --decode)\"\n", [.decodeAndRun()]),
        ScriptCase("eval with a here-string", "eval $(base64 -d <<< \"$BLOB\")\n", [.decodeAndRun()]),
        ScriptCase("bash -c of a decoded substitution", "bash -c \"$(echo aGVsbG8= | base64 -d)\"\n", [.decodeAndRun()]),
        ScriptCase("process substitution", "sh <(echo aGVsbG8= | base64 -d)\n", [.decodeAndRun()]),
        ScriptCase("substitution in command position", "$(echo aGVsbG8= | base64 -D)\n", [.decodeAndRun()]),
        ScriptCase("backticks in command position", "`echo aGVsbG8= | base64 -d`\n", [.decodeAndRun()]),
        ScriptCase("python exec of b64decode", "python3 -c \"import base64; exec(base64.b64decode('aGVsbG8='))\"\n", [.decodeAndRun()]),
        ScriptCase("python eval of b64decode", "python -c 'import base64;eval(base64.b64decode(\"aGVsbG8=\"))'\n", [.decodeAndRun()]),
        ScriptCase("perl eval of decode_base64", "perl -MMIME::Base64 -e 'eval(decode_base64(\"aGVsbG8=\"))'\n", [.decodeAndRun()]),
        ScriptCase("ruby eval of decode64", "ruby -rbase64 -e 'eval(Base64.decode64(\"aGVsbG8=\"))'\n", [.decodeAndRun()]),
        ScriptCase("decode to a file, chmod, run", "base64 -d payload.b64 > /tmp/p && chmod +x /tmp/p && /tmp/p\n", [.decodeAndRun()]),
        ScriptCase("decode to a file, then sh", "base64 -d payload.b64 > /tmp/p; sh /tmp/p\n", [.decodeAndRun()]),
        ScriptCase("download, decode, run", "curl -s https://example.com/p | base64 -d | sh\n", [.downloadAndRun(), .decodeAndRun()])
    ]

    @Test(arguments: positives) func reportsDecodeAndRun(_ scenario: ScriptCase) throws { try scenario.check() }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("decode to a file", "base64 -d in.b64 > out.bin\n"),
        ScriptCase("decode and pipe to jq", "echo \"$TOKEN\" | base64 -d | jq .\n"),
        ScriptCase("decode and cut", "base64 -d <<< \"$TOKEN\" | cut -d. -f2\n"),
        ScriptCase("encode", "echo hello | base64\n"),
        ScriptCase("encode and pipe to a shell", "echo hello | base64 | sh\n"),
        ScriptCase("decode into python -c, which does not read stdin", "echo aGk= | base64 -d | python3 -c 'import sys; print(sys.stdin.read())'\n"),
        ScriptCase("openssl decrypt", "openssl enc -d -aes-256-cbc -in secret.enc -out secret.txt\n"),
        ScriptCase("xxd dump", "xxd file.bin | head\n"),
        ScriptCase("python decode without exec", "python3 -c \"import base64; print(base64.b64decode('aGVsbG8='))\"\n"),
        ScriptCase("python exec without decoding", "python3 -c \"exec('print(1)')\"\n"),
        ScriptCase("decoded value assigned", "NAME=$(echo aGVsbG8= | base64 -d)\n"),
        ScriptCase("decoded value in an echo", "echo \"user: $(echo aGVsbG8= | base64 -d)\"\n"),
        ScriptCase("decoding in a message", "echo \"echo aGVsbG8= | base64 -d | sh\"\n"),
        ScriptCase("comment", "# echo aGVsbG8= | base64 -d | sh\n"),
        ScriptCase("decode, chmod, no run", "base64 -d payload.b64 > /tmp/p && chmod +x /tmp/p\n"),
        ScriptCase("decode to a file and read it", "base64 -d payload.b64 > /tmp/p && cat /tmp/p\n")
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}
