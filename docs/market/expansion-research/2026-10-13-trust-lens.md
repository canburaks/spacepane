# Trust Lens: what happens if I open, install or trust this file?

Researched 2026-10-13 (Europe/Istanbul). One of 11 parallel expansion-research angles; the lead synthesises. Builds on [decision 012](../../decisions/012-safety-findings.md), [017](../../decisions/017-package-and-certificate-inspection.md), [013](../../decisions/013-archive-listings.md), [the unique-feature research](../2026-10-05-unique-feature-opportunities.md) and [the competitor landscape](../2026-10-05-competitor-landscape.md).

## 1. Method and limits

- **Reading first.** The four decisions and two market documents above, then `PreviewFindings.swift`, `PreviewNameHint`, `FormatCatalog.json` (74 types) and `HiddenContentScanner.swift` to see what the contracts allow.
- **Web.** About 40 searches and fetches. Evidence labels used throughout:
  - **[V]** verified: I opened the primary source, or ran the experiment on this Mac.
  - **[S]** a named source seen through a search-result summary; I did not open it. Dates and counts can differ between secondary reports; I say so where they did.
  - **[I]** my inference or recollection. Not evidence.
- **Local experiments (read-only, macOS 27.2).**
  - `mdls` for the system type of about 50 suffixes.
  - `qlmanage -m` for the legacy Quick Look generators the system still ships.
  - A 40-line script that reads the 512-byte UDIF trailer and the code-signature SuperBlob of 12 DMGs in the researcher's Downloads folder.
  - `codesign -dvv` and `stapler validate` on three installed apps.
  - Nothing was mounted, executed or extracted.
- **What failed, so you can discount accordingly.**
  - The iTunes Search API returned HTTP 403 from both `curl` and WebFetch, and `api.github.com` returned 403. I therefore could **not** repeat the Mac App Store description scan for these types. Every "no Mac tool does this" below means *web search found none*, not *the 151-description scan found none*.
  - Licences of third-party scanners (picklescan, Fickling, zizmor, GuardDog, mcp-scan) could not be checked. They are prior art only; nothing is proposed to be copied.
  - `qlmanage -p` crashed with an `NSInvalidArgumentException` in this session, so I could not see what the system preview of a `.webloc` or `.mobileconfig` actually draws. Where I say what macOS shows, it comes from the generator list and the type tree, not from sight.
- **Not evidence of Finder routing.** As the repository already warns, nothing here shows that Finder will hand a type to SpacePane. That is most uncertain for dynamic (`dyn.*`) types, which need an imported declaration.

## 2. Key findings

1. **The thesis holds for text-, JSON- and ZIP-shaped artifacts, and is weak for packages and apps.** I found no Quick Look tool that tells you what a shell script, project config, npm tarball, extension, agent bundle or configuration profile will do. For installer packages and apps there is serious prior art that already runs in Quick Look: [Suspicious Package ships a Quick Look extension](https://mothersruin.com/software/SuspiciousPackage/quicklook-classic.html) [S] and [Apparency produces a Quick Look preview of signing, notarization and entitlements](https://mothersruin.com/software/Apparency/) [S]. Lead with the open ground.
2. **The 2025–26 evidence moved from "install scripts" to "anything a developer tool runs automatically".** CISA confirms the Shai-Hulud worm compromised over 500 npm packages [V]. In June 2026 "Phantom Gyp" ran code from a 157-byte `binding.gyp` with **no lifecycle script at all** [V, StepSecurity]. npm 12 (GA 2026-07-08) now disables dependency install scripts and implicit `node-gyp` builds by default [V, GitHub changelog]. A useful lens must name every trigger: lifecycle scripts, `binding.gyp`, `.pth` files, VS Code `runOn: folderOpen` tasks, agent hooks, MCP server commands.
3. **ClickFix moved off Terminal in 2026, which makes a file-level script lens timely.** Apple added a Terminal paste warning in macOS 26.4 [S]; the next campaign used an `applescript://` link to open Script Editor with `do shell script "curl … | zsh"` [S, Malwarebytes April 2026]. Apple's check covers pasted text, not files. A shell/AppleScript effects lens is the cheapest high-evidence candidate (S–M, no new parser).
4. **AI-agent artifacts are the freshest and least served.** The MCP Bundle manifest is documented and declares the command to run, its environment and its tools [V]. Phantom Gyp plants `.claude/`, `.cursor/` and `.vscode/` setup files [V]. Check Point reported project-file code execution in Claude Code (CVE-2025-59536, CVE-2026-21852) [S]. A project-config and agent-bundle lens extends the shipped "AI-agent instruction file" escalation naturally.
5. **Offline macOS trust facts are real, but notarization *verification* is not offline.** I verified on 12 local DMGs that the UDIF trailer's code-signature fields (offsets 296 and 304) point to a standard SuperBlob whose slot list shows signature (0x10000) and stapled ticket (0x10002) [V, experiment + Apple's `cs_blobs.h`]. A stapled app carries `Contents/CodeResources` [V, observed on two apps; absent on a third]. By contrast Apparency needs a temporary Mach-lookup exception for `syspolicy` to check notarization [S]. So: show "stapled ticket present or absent", never "notarized".
6. **Two small contract gaps decide feasibility.**
   - `PreviewNameHint` carries only the last path component, so `.vscode/tasks.json` and `.claude/settings.json` cannot be told apart from any `tasks.json` by name. Add a lowercase parent-directory name (metadata only; the URL is already in hand), or detect by structure.
   - Findings carry no source values. "Where does this shortcut really go" needs a host name. Decision 017 already set the precedent: torrent trackers are reduced to scheme, host and port. A typed `hosts` detail with that rule is the one policy change worth making.
7. **Prior art for several ideas is a CLI or web tool, which is exactly why Quick Look is open.** zizmor, picklescan, GuardDog and mcp-scan exist [S, names only]. None runs where a person already looks at the file.
8. **Honest ceiling.** Every finding is a *declared capability* ("runs a command when the folder opens"), not a verdict. Most legitimate files will show some. A lens that cries wolf loses the trust it sells, so severity `warning` is reserved for narrow, high-consequence combinations.

## 3. Ranked candidates

Effort: S = days, M = 1–2 weeks, L = several weeks (including fixtures and 13 translations). "Reuses" names existing SpacePane pieces. Evidence labels as in section 1.

| # | Candidate (types) | Audience | Incident evidence | Prior art on the Mac | Route + licence | Reuses | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **Script effects lens** (`.sh .bash .zsh .command .tool .applescript .ps1 .bat`, extension-free shebang files) | Anyone who double-clicks or pastes scripts; support and IT | ClickFix with `base64 -D \| zsh` (Objective-See, Feb 2026) [S]; Script Editor via `applescript://` (Malwarebytes, Apr 2026) [S]; fake Homebrew lures [S] | macOS 26.4 paste warning (pasted text only) [S]. No Quick Look tool found | Own line tokenizer over the concealed text. No dependency | Source adapter, line numbers, findings banner, secret filter | S–M | **Lead with** |
| 2 | **Opens-and-runs project config** (`.vscode/tasks.json`, `.claude/settings.json`, `.mcp.json`, `.cursor/mcp.json`, `.devcontainer/devcontainer.json`, `package.json` scripts) | Developers handed a repo (take-home tests, recruiter repos) | DPRK Contagious Interview `runOn: folderOpen` [S]; Claude Code project-file RCE/key theft [S]; Cursor CurXecute and MCPoison [S]; Phantom Gyp plants these files [V] | VS Code Workspace Trust and Claude's trust prompts, shown after you open. No preview | JSON adapter + structure detection; add `parentName` to the name hint | JSON/JSONC adapter, hidden-content AI-file list, #1 for command strings | S–M | **Lead with** |
| 3 | **Agent bundle lens** (`.mcpb`, `.dxt`, `.skill`, Claude plugin folders, `SKILL.md` bundles) | People installing MCP servers and skills | `postmark-mcp` BCC theft [S]; tool poisoning (Invariant, Apr 2025) [S]; Snyk ToxicSkills: 3,984 skills, 13.4% with a critical issue [S] | Invariant/Snyk `mcp-scan` is a CLI [S]. No Quick Look tool found | ZIP + `manifest.json` (documented [V]). Imported UTType needed | `ZIPArchiveReader`, JSON, hidden-character classifier, secret filter | M | **Lead with** |
| 4 | **Install-time package lens** (npm `.tgz`, PyPI `.whl`/sdist, `package.json`, `binding.gyp`) | Maintainers, reviewers, security staff | Shai-Hulud (CISA [V]); Phantom Gyp [V]; LiteLLM `.pth` (Mar 2026) [S]; chalk/debug (Sep 2025) [S] | Socket, GuardDog, `npm pack --dry-run`: CLI/web [S]. None in Quick Look | Existing gzip/TAR/ZIP readers + bounded member reads | Archive listing, package.json overview, archive risk analyzer | M | **Add** (strong story) |
| 5 | **App capability and trust card** (`.app`, IPA, DMG facts) | Mac users and IT before trusting a download | Hardened-runtime exceptions are documented [V]; right-click-Open lure and AMOS DMGs [S] | Apparency (Quick Look) [S], Unfold/LookQuick list entitlements, App Trust Preview. Risk *grading* not found | Own SuperBlob reader; Security framework optional | Decision 017 app/IPA summary | S–M | **Add** |
| 6 | **Extension permission card** (`.vsix`, `.crx`, `.xpi`) | Developers and IT sideloading extensions | GlassWorm (VS Code/OpenVSX, 2025–26) [S]; ShadyPanda sleeper extensions, 4.3M users [S] | None found in Quick Look | ZIP (+ CRX3 header, documented in Chromium source [S]) | ZIP reader, JSON, hidden-character classifier | M | **Add** (`.vsix` first) |
| 7 | **Configuration profile explainer** (`.mobileconfig`) | IT admins, MDM engineers, anyone sent a "profile" | NetSPI/Jamf research and a 2020 talk covering 400+ profiles [S]. **No 2025–26 campaign verified** | System shows XML as text [I]. Profile editors are apps, not Quick Look | CMSDecoder (already used) + plist | Provisioning-profile CMS path, plist adapter | S–M | **Add** |
| 8 | **Pickle and ML model lens** (`.pkl`, `.pt`, `.pth`, `.ckpt`, NumPy object arrays) | ML engineers, Stable Diffusion users | nullifAI: malicious PyTorch models that evaded picklescan (ReversingLabs, Feb 2025) [S] | picklescan, modelscan, Fickling: CLI [S] | Own bounded pickle opcode walker; ZIP for PyTorch | ZIP reader, NumPy adapter | M | **Add** |
| 9 | **Safe-to-share inventory** (HAR first; logs, notebooks, GPX) | Anyone sending a file to support | Okta 2023: HAR files with cookies and tokens in support cases [V] | Web HAR sanitizers [I]. None in Quick Look found | Existing HAR adapter + secret filter | Secret inventory, concealed copy | M | **Add** |
| 10 | **Launch item plist lens** (`.plist` that is a launchd job) | Mac admins, malware analysts | Launch items are the main macOS persistence path (Huntress, Elastic) [S] | KnockKnock/BlockBlock inspect *installed* items [I]. No file preview found | plist adapter + structure detection | Property-list adapter | S | **Add** |
| 11 | **Internet shortcut destination** (`.webloc .inetloc .fileloc .url .desktop .terminal`) | Everyone | CVE-2023-41067 `.fileloc` [V]; `.inetloc` zero-day 2021 [S] | System `Clippings.qlgenerator` covers `com.apple.internet-location` [V list]; `.url`/`.desktop` none | plist/INI, tiny | plist adapter | S | **Add** |
| 12 | **Own-name and content mismatch** (any claimed type) | Everyone | Janicab RTLO `.fdp.app` [S, via the earlier research] | None found | URL name test + magic sniff | `ListingNameRiskAnalyzer`, `HiddenCharacters` | S | **Add** |
| 13 | **GitHub Actions workflow lens** (`.yml`) | Maintainers, reviewers | tj-actions/changed-files, CVE-2025-30066 [S]; Phantom Gyp injects CI steps [V] | zizmor, actionlint: CLI [S] | YAML adapter + structure | YAML adapter, #1 for `run:` | M | **Niche** |
| 14 | **HTML smuggling and phish-form indicators** (`.html .htm .mhtml`) | Mail recipients, analysts | Microsoft, Nov 2021: NOBELIUM, Mekotio, AsyncRAT, Trickbot [S] | macOS renders HTML itself (`Web.qlgenerator`) [V list] | Source scan | Source adapter, #1 | M | **Niche** |
| 15 | **Container image archive card** (`docker save` `.tar`) | DevOps | Flare: 10,456 Docker Hub images leaking secrets (Dec 2025) [S] | dive, Docker Desktop: not Quick Look | TAR member reads of two JSON files | TAR listing, secret filter | M | **Niche** |
| 16 | **Installer destinations** (`.pkg` Bom and scripts) | Admins | Not searched | **Suspicious Package has a Quick Look extension** [S] | XAR (have) + BOM reader, own | `XARArchiveReader` | M | **Niche** |
| 17 | **Shortcuts** (`.shortcut`) | Shortcuts users | Not found | None | AEA wrapper + LZFSE + Apple Archive + plist | none | L, spike | **Niche** |
| 18 | **Windows LNK/HTA arriving on a Mac** | IT, analysts | ZDI-CAN-25373 `.lnk` padding, 11 groups [S] | None | MS-SHLLINK (open spec [I]) | none | M | **Niche** |
| 19 | **Automation exports** (`.workflow`, `.alfredworkflow`, `.kmmacros`) | Power users | None verified | None | plist/bundles | plist adapter | M each | **Niche** |

## 4. Candidates in detail

### 4.0 Shared design for every lens

- **Wording.** A finding says what the file declares: "Runs a command when the folder opens: 1 task." It never says "malicious", "safe" or "clean". When a scan finds nothing, the banner is silent, and no surface ever says "no problems found".
- **Severity.**
  - `info`: a declared capability that most files of the type legitimately have.
  - `caution`: a capability that is rarely needed or runs without a further user action.
  - `warning`: only narrow combinations with a factual basis, or the hidden-content class that is already `warning` in agent files.
- **Contract additions** (each a deliberate one-line shared change, per decision 012): new `PreviewFindingKind` cases; a closed `labels` detail (for example lifecycle names or entitlement keys) so no source text is carried; a `hosts` detail limited to scheme, host and port, passed through the privacy filter, bounded like `decodedText`; and `parentName` on the name hint.
- **Where findings come from.** Text lenses scan the concealed displayed text (so lines match the gutter and secrets are already covered). Archive-member lenses report against the summary, as archive risks do.
- **Offline trust facts: what works without a network** (used by 4.5, 4.7, 4.11 and 4.16):

| Fact | Offline? | Route | Evidence and caveat |
|---|---|---|---|
| Signature present, CodeDirectory flags (hardened runtime `0x10000`), identifier | Yes | Own SuperBlob reader, or the existing `SecStaticCode` path | Decision 017 already reads these; Security may be denied in the sandbox, observed in no signed host |
| Entitlements | Yes | SuperBlob slots 5 (XML) and 7 (DER) | Slot numbers [V] from Apple's `cs_blobs.h` (APSL 2.0: use the constants as facts, copy no code) |
| Stapled notarization ticket | Yes | DMG/Mach-O: slot `0x10002`. App bundle: file `Contents/CodeResources` | Observed: 9 of 12 DMGs carry the ticket slot (one of them has no other signature slot); two apps stapled with the file; one app with neither. Whether the bundle file name is documented by Apple: **could not verify** |
| Notarization *verified*, Gatekeeper verdict | **No** | `spctl` and `SecAssessment` talk to `syspolicyd`; Apparency needs a Mach-lookup exception for it [S] | Absence of a staple is not "not notarized" (Gatekeeper can check online) |
| Quarantine origin, agent, timestamp | Probably | `URL.resourceValues(forKeys: [.quarantinePropertiesKey])`, documented since macOS 10.10 [V] | Whether the sandboxed extension may read it: **spike**. Show host only; strip query strings |
| Signer certificate subject of a CMS blob | Yes | `CMSDecoder` (already used for profiles) | Never evaluate trust |

### 4.1 Script effects lens (rank 1: lead with)

**Evidence.**
- Objective-See (February 2026) documents an LLM-search lure that told users to run `echo "…" | base64 -D | zsh`, which loaded the MacSync stealer [S, [blog 0x85](https://objective-see.org/blog/blog_0x85.html)].
- Malwarebytes (April 2026) describes a ClickFix variant that opens Script Editor through `applescript://` and runs `do shell script "curl -kSsfL … | zsh"` to fetch Atomic Stealer, after Apple's macOS 26.4 paste warning blocked the Terminal route [S, [Malwarebytes](https://www.malwarebytes.com/blog/news/2026/04/clickfix-finds-new-way-to-infect-macs)]. The paste warning itself: [Malwarebytes, March 2026](https://www.malwarebytes.com/blog/news/2026/03/new-macos-security-feature-will-alert-users-about-possible-clickfix-attacks) [S]; which commands trigger it is undocumented.
- Fake Homebrew sites and ads delivered AMOS through a pasted `curl` command, and a 2026 variant hid it in Base64 [S, [AppleInsider](https://appleinsider.com/articles/26/03/30/that-top-google-result-for-homebrew-could-infect-your-mac)].

**Findings** (all on concealed text, with displayed line numbers).

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `script.downloadsAndRuns` (fetch piped to a shell or interpreter, `sh -c "$(curl …)"`, `bash <(curl …)`) | caution | lines | `hosts` (scheme + host only) |
| `script.decodesAndRuns` (`base64 -d`/`-D`, `xxd -r`, `openssl enc` into a shell, `eval`, `osascript`) | warning | lines | none |
| `script.removesQuarantine` (`xattr -c`, `-d com.apple.quarantine`, `spctl --master-disable`) | caution | lines | none |
| `script.promptsForPassword` (AppleScript `display dialog … hidden answer`, `dscl . -authonly`, `sudo -S`) | caution | lines | none |
| `script.touchesCredentialStores` (Keychains, `security find-generic-password`, browser `Login Data`/`Cookies`, wallet directories, `.ssh`, `.aws`) | caution | lines | `labels` (closed set of store kinds) |
| `script.installsPersistence` (writes under `LaunchAgents`/`LaunchDaemons`, `launchctl bootstrap`, `crontab`, shell-profile append, login-item AppleScript) | caution | lines | none |
| `script.runsWithPrivilege` (`sudo`, `with administrator privileges`) | info | lines | none |
| `script.obfuscatedPayload` (a line over a threshold made almost wholly of Base64/hex, or heavy `\x` escapes) | caution | lines | none |
| `script.collectsAndUploads` (credential-store kinds **and** an outbound upload in one file) | warning | 1 | `labels` |

**False positives and wording.** `curl | sh` is how rustup, nvm and Homebrew install; `sudo` is everywhere. So those two stay `info`/`caution` and say "Downloads content and runs it: 2 lines", never "dangerous". `warning` is for decode-and-execute and for the collect-and-upload combination, both rare in honest scripts. Skip full-line comments so a commented-out example does not count. Windows `.ps1`/`.bat` get `-EncodedCommand`, `IEX`, `-ExecutionPolicy Bypass` and `-WindowStyle Hidden` the same way; only worth the effort if cheap.

**Parse route.** A line tokenizer (continuations, quotes, `$(…)`, heredoc bodies treated as data). Nothing is evaluated or expanded. No dependency.

**Prior art.** macOS 26.4 paste check (pasted text only) [S]. ShellCheck is a linter [I]. Objective-See BlockBlock and LuLu are runtime tools [I]. No Quick Look tool found by web search.

**Effort and verdict.** S–M. Lead with: it covers the one launchable users literally double-click (`.command`), reuses everything shipped, and has the strongest 2026 evidence.

### 4.2 Opens-and-runs project config (rank 2: lead with)

**Evidence.**
- DPRK "Contagious Interview" lures hide a staged downloader in `.vscode/tasks.json` with `runOptions.runOn: "folderOpen"`; it runs once the developer clicks "Trust" [S, [OpenSourceMalware](https://opensourcemalware.com/blog/contagious-interview-vscode), [The Hacker News, Jan 2026](https://thehackernews.com/2026/01/north-korea-linked-hackers-target.html)].
- Check Point (2026-02-25) reports Claude Code project files could run hooks, bypass MCP consent (`enableAllProjectMcpServers`, CVE-2025-59536) and redirect the API endpoint (`ANTHROPIC_BASE_URL`, CVE-2026-21852); all patched [S, [Check Point](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files/)].
- Cursor: CurXecute (CVE-2025-54135) and MCPoison (CVE-2025-54136), both via `mcp.json`, fixed in 1.3.9 and 1.3 [S, [Tenable](https://www.tenable.com/blog/faq-cve-2025-54135-cve-2025-54136-vulnerabilities-in-cursor-curxecute-mcpoison)].
- Phantom Gyp's payload writes backdoor setup files into `.claude/`, `.cursor/` and `.vscode/` of repositories it can reach, including `.claude/setup.mjs` and `.cursor/rules/setup.mdc` [V, [StepSecurity](https://stepsecurity.io/blog/binding-gyp-npm-supply-chain-attack-spreads-like-worm)].

**Findings.**

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `autorun.onFolderOpen` (VS Code task with `runOn: folderOpen`; dev container `initializeCommand`, which runs on the host) | caution; warning if the command trips any #1 `warning` | tasks | none |
| `autorun.agentHook` (Claude Code `hooks` entries) | caution | hooks | `labels` (event names) |
| `autorun.mcpServerCommand` (`mcpServers.*.command`) | caution | servers | none |
| `autorun.preApprovesServers` (`enableAllProjectMcpServers: true`, broad `permissions.allow` such as `Bash(*)`) | warning | 1 | none |
| `autorun.redirectsEndpoint` (`*_BASE_URL` in an `env` block) | caution | 1 | `hosts` |
| `autorun.lifecycleScripts` (`package.json` scripts that run on install) | caution | scripts | `labels` (names) |

**False positives and wording.** Many repos legitimately run `npm install` on open or define hooks. State the declaration and the trigger ("on folder open"), apply the #1 classifier to the command string, and escalate only on that classifier's `warning`. Do not display commands; show the executable's base name only if it passes the privacy filter.

**Parse route.** The JSON/JSONC adapter already parses these. Detection by name where the name is distinctive (`.mcp.json`, `mcp.json`, `devcontainer.json`), by structure otherwise (`"version": "2.0.0"` plus a `tasks` array; a `hooks` object with known event names). Better: add `parentName` to the name hint.

**Prior art.** Workspace Trust prompts appear only after you open the folder. VS Code's own page says extensions run in an extension host with the same permissions as VS Code itself [V, [VS Code docs](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security)]. No preview tool found.

**Effort and verdict.** S–M. Lead with, paired with 4.3 as one "AI-agent and project trust" story that extends the shipped agent-file escalation.

### 4.3 Agent bundle lens (rank 3: lead with)

**Evidence.**
- `postmark-mcp` 1.0.16 (17 September 2025) added one line that BCC'd every email to an external address; 15 earlier versions were clean (Koi Security) [S, [Koi](https://koi.ai/blog/postmark-mcp-npm-malicious-backdoor-email-theft), [The Register](https://www.theregister.com/2025/09/29/postmark_mcp_server_code_hijacked/)].
- Tool poisoning (Invariant Labs, April 2025): instructions hidden in a tool description tell the model to read `~/.ssh` and `mcp.json` and pass them through a spare parameter [S via secondary summary; the original post was not opened].
- Snyk "ToxicSkills" audited 3,984 skills (2026-02-05): 13.4% with a critical issue, 36.82% with any flaw [S, [Snyk](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub)]. Secondary write-ups repeat figures that are not in Snyk's text (for example "36% prompt injection"), so quote only the two above.
- EchoLeak (CVE-2025-32711) used reference-style links and images as the exfiltration channel [S, [SOC Prime](https://socprime.com/blog/cve-2025-32711-zero-click-ai-vulnerability/)].

**Findings** (for `.mcpb`/`.dxt`, whose manifest is documented [V, [MANIFEST.md](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)]).

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `agent.runsLocalProgram` (`server.type` node/python/binary/uv; `mcp_config.command`) | info | 1 | `labels` (runtime kind) |
| `agent.bundledNativeCode` (`binary` type, Mach-O/ELF/PE members, `.node` addons) | caution | files | none |
| `agent.requestsConfiguration` (`user_config` entries; how many are `sensitive`, `file` or `directory`) | info | entries | none |
| `agent.broadPathAccess` (`${HOME}`, `${DOCUMENTS}`, `${DOWNLOADS}` in args or env) | caution | uses | none |
| `agent.toolTextAddressedToAssistant` (tool or prompt text with imperative directives, references to credential files or other tools' config, "do not tell the user", `<IMPORTANT>`-style tags) | caution | tools | none |
| `agent.hookCommands`, `agent.bundledScripts` (plugin folders, `.skill` archives) | caution | files | `labels` |
| existing `hidden.*` classifier run over manifest and skill text | warning in agent context (already) | n/a | n/a |

**False positives.** Imperatives are normal in tool descriptions ("Use this tool when…"). Flag only patterns that point *outside* the tool's job: other files, other tools, concealment from the user. Keep it `caution` and name the count of tools, not the text.

**Parse route.** `.mcpb` is documented as a packaged `manifest.json` with server files; the documentation I opened does not state the container format, so confirm ZIP on a real bundle before building (**could not verify**). Reuse `ZIPArchiveReader`. All three suffixes are dynamic types here, so each needs an imported declaration.

**Prior art.** `mcp-scan` (Invariant, now Snyk) is a CLI [S]. Claude Desktop shows its own install dialog; I could not verify what it lists. No Quick Look tool found.

**Effort and verdict.** M. Lead with.

### 4.4 Install-time package lens (rank 4: add)

**Evidence.**
- **Shai-Hulud** (September 2025): CISA says the worm compromised over 500 packages, harvested GitHub and cloud credentials, published them to a public `Shai-Hulud` repository and republished other packages with the stolen identity [V, [CISA](https://www.cisa.gov/news-events/alerts/2025/09/23/widespread-supply-chain-compromise-impacting-npm-ecosystem)]. CISA's page does not name the mechanism; the `postinstall` hook running `node bundle.js` comes from vendor analyses [S, [Truesec](https://truesec.com/hub/blog/500-npm-packages-compromised-in-ongoing-supply-chain-attack-shai-hulud)]. Shai-Hulud 2.0 moved to `preinstall` with `setup_bun.js` and `bun_environment.js` [S, [Cycode](https://cycode.com/blog/shai-hulud-2-0-deep-dive-and-actionable-steps-you-should-take/)].
- **Phantom Gyp** (3 June 2026): 57 packages, 286 versions; a ~157-byte `binding.gyp` triggers `node-gyp rebuild`, with no scripts declared in `package.json`; the payload sat in a root `index.js` over 4 MB that the package never imports [V, StepSecurity; S, [Chainguard](https://www.chainguard.dev/fr-FR/unchained/chainguard-artifacts-safe-from-miasma-phantom-gyp-npm-attack)].
- **PyPI:** LiteLLM 1.82.7 and 1.82.8 (24 March 2026) shipped a `.pth` file (`litellm_init.pth`) that ran on every Python start; the GitHub source was unmodified, only the artifact [S, [FutureSearch](https://futuresearch.ai/blog/litellm-pypi-supply-chain-attack/), [NetSPI](https://www.netspi.com/blog/executive-blog/ai-ml-pentesting/litellm-supply-chain-compromise/)]. Sources disagree on whether 1.82.7 also used the `.pth`.
- **Limit of the lens:** the 8 September 2025 chalk/debug compromise (18 packages) put browser-side crypto-swapping code in ordinary modules, with no install hook [S, [CyberInsider](https://cyberinsider.com/npm-supply-chain-attack-impacts-packages-with-2-billion-weekly-downloads/)]. This lens would not have caught it. Say so in the documentation.
- **Context:** npm 12 (GA 2026-07-08) disables dependency lifecycle scripts, implicit `node-gyp` builds, git and remote-URL dependencies by default [V, [GitHub changelog](https://github.blog/changelog/2026-07-08-npm-install-time-security-and-gat-bypass2fa-deprecation/)]. Demand shifts from "what will my install run" to "what does this artifact try to run", which is still the reviewer's question.

**Findings.**

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `package.installScripts` (`preinstall`, `install`, `postinstall`, `prepare`) | caution (`info` for the single canonical `node-gyp rebuild`) | scripts | `labels` |
| `package.implicitNativeBuild` (`binding.gyp` present, no matching C/C++ source members) | caution | 1 | none |
| `package.scriptRunsBundledFile` (an install script runs a member over 1 MiB or with very long lines) | caution | 1 | none |
| `package.scriptFetchesOrDecodes` (install script text contains fetch, decode or inline-eval patterns; reuse #1) | warning | scripts | none |
| `package.largeUnreferencedScript` (root script over a threshold that `main`/`exports` never names) | caution | files | none |
| `package.nativeBinaries` (Mach-O, ELF, PE, `.node` by magic) | info | files | none |
| `package.pthExecutes` (a `.pth` line beginning `import`) | warning | files | none |
| `package.buildHooksInSdist` (`setup.py`, custom in-tree build backend) | info | 1 | none |
| `package.remoteDependencies` (git or URL dependencies) | caution | deps | none |

**False positives.** `esbuild`, `puppeteer`, `husky` and every native addon have install scripts or `binding.gyp`. `info`/`caution` wording only; `warning` needs the fetch/decode or `.pth import` evidence.

**Parse route.** `.tgz` is already routed through the gzip and TAR readers; wheels and PyTorch files are ZIP. New: bounded member reads (the ZIP reader has CRC-checked reads; the TAR reader lists only) of `package/package.json`, `binding.gyp`, `entry_points.txt`, and the first bytes of selected members for magic. No decompression of nested archives. Decision 013 records reading entry bytes as a later bounded step.

**Prior art.** Socket and GuardDog (Datadog) scan packages, `npm audit` reports known advisories only [S/I]. None in Quick Look found.

**Effort and verdict.** M. Add. A concern: how often does a Mac user preview a tarball in Finder? The single-file `package.json` half (in 4.2) is the part most people will see.

### 4.5 App capability and trust card (rank 5: add)

Extends the shipped `.app`/IPA summary from "what is it" to "what can it do and what do we know about its trust".

**Evidence and prior art.** Apple's [Hardened Runtime page](https://developer.apple.com/documentation/security/hardened-runtime) [V] lists the exception entitlements (`allow-jit`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, `disable-library-validation`, `disable-executable-page-protection`, `debugger`) and the resource-access entitlements; Apple states what each permits but not a risk grade, so any grading is ours. Apparency "mainly wraps `codesign` and `spctl`" and shows the results [S, [FAQ](https://mothersruin.com/software/Apparency/faq.html)]. LookQuick and Unfold list entitlements (earlier research). The right-click-Open lure: macOS 15 removed the Control-click override, leaving System Settings → Open Anyway [S, [AppleInsider](https://appleinsider.com/inside/macos-sequoia/tips/whats-changed-in-runtime-protection-for-macos-sequoia)] (sources disagree on whether it is fully gone). I did not find a verified 2025–26 incident that hinges on a specific entitlement, so the case rests on the documented risk of the exceptions and the AMOS-in-DMG pattern [S].

**Findings.**

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `app.unsignedOrAdHoc` | caution | 1 | `labels` |
| `app.noHardenedRuntime` (signed, flag `0x10000` absent) | info | 1 | none |
| `app.noStapledTicket` (never "not notarized") | info | 1 | none |
| `app.weakensRuntime` (the six exceptions above) | caution | keys | `labels` |
| `app.debuggableBuild` (`get-task-allow` in a Developer ID or store build) | caution | 1 | none |
| `app.requestsPersonalData` (camera, microphone, location, contacts, calendars, photos) | info | keys | `labels` |
| `app.automatesOtherApps` (`automation.apple-events`) | info | 1 | none |
| `app.sandboxTemporaryExceptions` (`temporary-exception.*`) | caution | keys | none |
| `app.installsHelpers` (privileged helper, `Contents/Library/LaunchDaemons`, `LoginItems`, system extension, network or Endpoint Security entitlements) | caution | items | `labels` |
| `app.embeddedExecutables` (Mach-O outside the main binary) | info | files | none |

**False positives.** Browsers, IDEs and Electron apps legitimately carry `disable-library-validation` and JIT. Phrase as a list of declared exceptions, with severity `caution` at most, and never a combined score.

**Parse route.** Decision 017's route, plus an own SuperBlob reader for Mach-O `LC_CODE_SIGNATURE` so facts survive if Security calls are denied in the extension sandbox. The same reader handles DMG (below). Entitlements need no Security call.

**DMG facts** (rank 5, same card). Verified on 12 DMGs: 8 carry a CodeDirectory, requirements, CMS signature and ticket slot; 1 is signed without a ticket; 2 have no embedded signature; 1 reports "not signed at all" through `codesign` yet carries a ticket-only SuperBlob. Show "embedded signature: present/absent; stapled ticket: present/absent; team identifier when present" as plain facts. **Do not** warn on "unsigned DMG" (common and not the whole picture). The lure image inside the volume cannot be seen from the container (compressed filesystem); see section 5.

**Effort and verdict.** S–M. Add.

### 4.6 Extension permission card (rank 6: add)

**Evidence.** GlassWorm hid payloads in invisible characters in VS Code and OpenVSX extensions (Koi, from October 2025) [S, [Endor Labs](https://www.endorlabs.com/reports/invisible-threats-glassworm-unicode-vscode)], then shifted to native `.node` binaries; in April 2026 Aikido described Zig-built `mac.node`/`win.node` droppers that install a second `.vsix` into every VS Code-compatible editor on the machine [S, [Aikido](https://www.aikido.dev/blog/glassworm-zig-dropper-infects-every-ide-on-your-machine)]. ShadyPanda: extensions behaved for years, then a 2024 update enabled hourly remote-JavaScript downloads, reaching about 4.3 million Chrome and Edge users [S, [Dark Reading](https://www.darkreading.com/endpoint-security/shadypanda-hackers-weaponize-browsers)]. A static card cannot detect that sleeper step; say so.

**Findings.**

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `extension.activatesAtStartup` (`activationEvents` has `*` or `onStartupFinished`) | info | 1 | none |
| `extension.bundlesNativeCode` (`.node`, Mach-O, `.dll`, `.exe` members) | caution | files | none |
| `extension.installsOtherExtensions` (`extensionPack`, `extensionDependencies`) | info | entries | none |
| `extension.allSitesAccess` (`<all_urls>`, `*://*/*`, host permissions) | caution | patterns | none |
| `extension.sensitivePermissions` (`cookies`, `webRequest`, `history`, `nativeMessaging`, `debugger`, `proxy`, `management`, `downloads`, `clipboardRead`) | caution | permissions | `labels` |
| `extension.selfHostedUpdates` (`update_url` outside the store) | caution | 1 | `hosts` |
| `extension.relaxedScriptPolicy` (`unsafe-eval` in the content security policy) | caution | 1 | none |
| `hidden.*` classifier over manifest and bounded script members | warning | by kind | existing |

**Parse route.** `.vsix` is a ZIP with `extension.vsixmanifest` and `extension/package.json`. A CRX3 file is `Cr24`, version 3, a little-endian header length, a protobuf header, then a ZIP; Chromium's verifier rejects headers over 256 KiB [S, [crx3.proto](https://chromium.googlesource.com/chromium/src/+/e9b1018/components/crx_file/crx3.proto)]. `.xpi` is a ZIP with `manifest.json`. Skip `.safariextz` (legacy XAR, retired). All three suffixes are dynamic types except `.crx` (`org.chromium.extension`, [V local]). Scanning script members for hidden characters costs I/O; bound it (for example the first 256 KiB of 20 files).

**Prior art.** The stores show permissions at install; Koi sells analysis [S]. No Quick Look tool found; CRXcavator's status **could not be verified**.

**Effort and verdict.** M. Add, `.vsix` first (offline installs of editor extensions are common and the GlassWorm evidence is directly about them).

### 4.7 Configuration profile explainer (rank 7: add)

**Evidence.** Older and thinner than the others. NetSPI's [Malicious MobileConfigs](https://www.netspi.com/blog/technical-blog/mobile-application-pentesting/malicious-mobile-configs/) demonstrates a phishing profile that installs trusted certificates and a proxy to capture HTTPS traffic [S]. Jamf's [Malicious profiles](https://www.jamf.com/blog/malicious-profiles-come/) describes rogue VPN and root CA risk [S]. An Objective by the Sea 2020 talk reports analysing 400+ profiles, a DNS-changer profile in the Roaming Mantis chain, and web clips that cannot be removed when `IsRemovable` is false [S, [talk](https://infocondb.org/con/objective-by-the-sea/objective-by-the-sea-version-30/mimic-in-configuration)]. **I could not verify any 2025–26 campaign.** The value is IT-admin clarity more than incident volume.

**Findings.** `PayloadType` strings verified against [Apple's device-management repository](https://github.com/apple/device-management/tree/release/mdm/profiles) [V, directory listing; the listing was truncated at 100 files, so VPN, web clip and content-filter names are from memory [I]].

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `profile.addsCertificates` (`security.root`, `pkcs1`, `pkcs12`, `pem`) | caution | certs | none (never evaluate trust) |
| `profile.routesTraffic` (VPN, `proxy.http.global`, `dnsSettings.managed`, `dnsProxy.managed`, `relay.managed`, content filter) | caution | payloads | `hosts` (server URLs) |
| `profile.enrollsInManagement` (`com.apple.mdm`: server host, access rights) | warning | 1 | `hosts` |
| `profile.grantsPrivacyAccess` (`TCC.configuration-profile-policy`) | caution | services | `labels` |
| `profile.allowsExtensionsOrLoginItems` (`loginitems.managed`, system-extension policy) | info | payloads | none |
| `profile.cannotBeRemoved` (`PayloadRemovalDisallowed`) | caution | 1 | none |
| `profile.unsigned` / signer subject | info | 1 | subject name only |

**Wording.** "Installing this profile would add 1 root certificate and set a DNS server (host: …)" is a statement about what the file asks for. Apple's own install dialog follows; ours helps before that point.

**Parse route.** Plist, and CMS-wrapped plist through `CMSDecoder` (the provisioning-profile path, signer status never requested). Type is `com.apple.mobileconfig`, conforming to `public.xml`, so the XML adapter may already claim it; the profile view needs priority for this type.

**Prior art.** macOS shows the XML via the Text generator [V list for `public.xml`; contents not seen]. Profile editors (iMazing Profile Editor, ProfileCreator) are apps [I]. No Quick Look tool found.

**Effort and verdict.** S–M. Add; lead for IT-heavy audiences.

### 4.8 Pickle and ML model lens (rank 8: add)

**Evidence.** ReversingLabs (February 2025) found two Hugging Face PyTorch models whose pickle began with a reverse shell and ended in a deliberately broken stream, packed with 7z so `torch.load` and picklescan failed to flag them [S, [ReversingLabs](https://www.reversinglabs.com/blog/rl-identifies-malware-ml-model-hosted-on-hugging-face)]. A JFrog count of malicious models could not be verified in my searches. Python documents `pickle` as unsafe for untrusted data [I].

**Findings.** Static opcode walk only; nothing is unpickled.

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `pickle.importsProcessOrEval` (`GLOBAL`/`STACK_GLOBAL` naming `os.system`, `subprocess.*`, `builtins.eval/exec/__import__`) | warning | imports | `labels` (module class, never names) |
| `pickle.importsNetworkOrFile` (`socket`, `urllib`, `requests`, `shutil`, `builtins.open`) | caution | imports | `labels` |
| `pickle.importsOther` (anything not in an allow-list of tensor and container rebuilders) | info | imports | none |
| `pickle.brokenStream` (unknown opcode or truncation after imports; the nullifAI shape) | caution | 1 | none |
| `pickle.objectArray` (NumPy `descr` contains an object dtype, so loading needs `allow_pickle=True`) | caution | arrays | none |

**Hard rule.** Never display "no dangerous imports found" or any all-clear. A static walk can be evaded; say "static check only" when the banner is silent by omission, and never claim safety.

**Parse route.** Own pickle opcode reader, protocols 0–5, bounded. PyTorch `.pt`/`.pth` and `.ckpt` are ZIP archives containing `data.pkl` (existing ZIP reader); NumPy `.npy` headers are already parsed. A safe companion preview for `.safetensors` (a JSON header of tensor names, dtypes and shapes) and GGUF metadata is cheap and would make the same types useful, but is outside this angle.

**Prior art.** picklescan, modelscan and Fickling are CLI tools [S/I; licences unverified]. Hugging Face scans on upload. No Quick Look tool searched for specifically: **web search not run for ML-model Quick Look apps**.

**Effort and verdict.** M. Add. The audience (Apple Silicon ML users downloading checkpoints) is large and underserved by file-level tools.

### 4.9 Safe-to-share inventory (rank 9: add)

**Evidence.** Okta's October 2023 support-system breach: attackers viewed files customers had uploaded to support cases; Okta warned that HAR files can hold cookies and session tokens, and told customers to sanitize credentials and cookies or session tokens in a HAR file before sharing it [V, [Okta](https://sec.okta.com/articles/2023/10/tracking-unauthorized-access-oktas-support-system/)]. Counts of affected customers vary between reports and Okta's own page gives none.

**What exists.** SpacePane conceals secrets, inventories them by kind and line, and offers Copy Concealed Text. The gap is a *share-readiness* view for structured files, and counts of personal identifiers that are not secrets.

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `privacy.sessionMaterial` (HAR: cookie, `Set-Cookie`, `Authorization`, API-key headers) | caution | headers | `hosts` count only |
| `privacy.credentialsInBodies` (HAR `postData` fields named like passwords or tokens; JSON responses with `access_token`) | caution | fields | none |
| `privacy.homePathUsernames` (`/Users/<name>/`, `C:\Users\<name>\`, `/home/<name>/`) | info | paths | distinct-name count only |
| `privacy.contactIdentifiers` (e-mail addresses, public IPv4/IPv6, MAC addresses) | info | by kind | `labels` |
| `privacy.preciseLocation` (GPX/KML/GeoJSON: start and end within a stated distance, so a likely home or work place) | info | 1 | distance band |
| `privacy.authorMetadata` (EPUB `dc:creator`, CBZ ComicInfo, notebook author metadata) | info | by kind | none |

**Wording.** "Holds 41 cookie headers and 12 Authorization headers across 7 hosts. Values are concealed here but are in the file." Do not infer which cookies matter.

**Action.** An explicit **Copy sanitized HAR** (cookie, auth and body values replaced with the existing concealment token, structure preserved) is the HAR analogue of Copy Concealed Text. It needs a decision on copy semantics because it produces valid JSON, not the displayed text. Optional.

**Risks.** E-mail and IP regexes are noisy; restrict to e-mail and to non-private ranges, and keep severity `info`.

**Prior art.** Web-based HAR sanitizers exist [I, not opened]; no Quick Look tool found. **Effort and verdict.** M. Add; the HAR piece alone is S–M.

### 4.10 Launch item plist lens (rank 10: add)

**Evidence.** Launch agents and daemons are the dominant macOS persistence mechanism (Huntress; Elastic names RustBucket, Shlayer, CloudMensis) [S]. Objective-See publishes an annual malware review (the 2025 edition exists, ten years running) [S]. A circulating "78%" persistence figure could not be confirmed and is not used.

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `launchd.runsAtLoadOrKeepsAlive` | info | 1 | none |
| `launchd.runsAsRoot` (`UserName` root, or located in a daemons folder) | info | 1 | none |
| `launchd.runsInterpreterWithInlineCode` (`sh`, `zsh`, `python`, `osascript`, `perl`, `node` with `-c`/`-e`) | caution | 1 | none |
| `launchd.programInWritablePath` (`/tmp`, `/Users/Shared`, hidden directories) | caution | 1 | none |
| `launchd.fetchesRemoteContent` (`curl`/`wget` in arguments) | caution | 1 | `hosts` |
| `launchd.impersonatesAppleLabel` (label `com.apple.*` whose program is not under a system path) | caution | 1 | none |
| `launchd.listensOnNetwork` (`Sockets`) | info | sockets | none |

**Parse route.** The plist adapter; recognize a launchd job by `Label` plus `Program` or `ProgramArguments`. The URL's folder (`LaunchAgents`, `LaunchDaemons`) is a free path test without file access. **Prior art.** KnockKnock and BlockBlock inspect installed items [I]; I found no preview of a standalone file. **Effort and verdict.** S. Add.

### 4.11 Internet shortcut destination (rank 11: add)

**Evidence.**
- Jamf: a `.fileloc` pointing at an unsigned or ad-hoc-signed app in `/Applications` showed the wrong Gatekeeper prompt; CVE-2023-41067, fixed in macOS 14.0, published 2024-08-30 [V, [Jamf](https://www.jamf.com/blog/gatekeeper-flaws-on-macos/)].
- A 2021 Finder zero-day let `.inetloc` files run embedded commands; Apple blocked only lowercase `file://`, so `File://` still worked [S, [SSD Disclosure](https://ssd-disclosure.com/ssd-advisory-macos-finder-rce/), [Intego](https://www.intego.com/mac-security-blog/remotely-exploitable-inetloc-zero-day-vulnerability-hits-the-mac/)]. Mozilla also fixed a download-protection bypass via `.inetloc` (CVE-2021-38510) [S].
- The Script Editor ClickFix route uses an `applescript://` URL, which a shortcut can carry [S, 4.1].

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `shortcut.opensLocalItem` (`file://` target; whether it names an app, script or installer) | caution | 1 | `labels` |
| `shortcut.opensNetworkShare` (`smb://`, `afp://`, `nfs://`, UNC) | caution | 1 | `hosts` |
| `shortcut.opensNonWebScheme` (anything but http and https, notably `applescript:`, `javascript:`, `data:`, `search-ms:`) | warning for `applescript:`, `javascript:`, `data:`; caution otherwise | 1 | `labels` |
| `shortcut.lookalikeHost` (punycode `xn--`, mixed-script label, a `user@host` prefix) | caution | 1 | `hosts` |
| `shortcut.runsCommand` (`.terminal` `CommandString`, `.desktop` `Exec=`) | caution | 1 | none |
| `shortcut.paddedTarget` (long whitespace runs; analogous to the Windows `.lnk` trick [S]) | caution | 1 | none |

Show only scheme, host and port; never path or query (tokens, per decision 017's tracker rule).

**Provider caveat.** The system keeps `Clippings.qlgenerator` for `com.apple.internet-location` [V list], the parent type of `.webloc`. Per decision 025, claim `.webloc`/`.inetloc`/`.fileloc` only after observing that the system preview shows the destination without classification. `.url` (`com.microsoft.internet-shortcut`) had no generator in the filtered list; I did not check the `.desktop` type.

**Effort and verdict.** S. Add.

### 4.12 Own-name and content mismatch (rank 12: add, small)

The name test covers the file itself, not archive entries.

| Kind | Severity | Count | Detail |
|---|---|---|---|
| `file.nameDirectionalOverride` | warning | 1 | none |
| `file.nameInvisibleCharacters` | caution | 1 | none |
| `file.nameDoubleExtension` (document-like suffix followed by an executable-like suffix: `.pdf.app`, `.txt.command`) | caution | 1 | none |
| `file.contentLooksLike` (a text or data type whose bytes begin like a Mach-O, ELF, PE, ZIP, gzip, PDF, OLE, shebang or HTML document) | caution | 1 | `labels` (family) |

**Evidence.** Janicab's `RecentNews.fdp.app` rendered as a PDF with a right-to-left override [S, [Macworld](https://www.macworld.com/article/221449/new-digitally-signed-mac-malware-confuses-users-with-right-to-left-file-name-tricks.html), via the earlier research]. I did not search for 2025–26 file-level name-spoofing incidents.

**Route.** `ListingNameRiskAnalyzer` and `HiddenCharacters` already classify names for archive entries; apply them to `URL.lastPathComponent`. Magic sniffing reuses the first bytes each adapter already reads. **Honest value:** a `.txt` that is a ZIP already looks wrong; the gain is a clear sentence. **Effort and verdict.** S. Add.

### 4.13 GitHub Actions workflow lens (rank 13: niche)

**Evidence.** The `tj-actions/changed-files` compromise (14–15 March 2025) retargeted tags to a malicious commit that dumped CI secrets to logs; CVE-2025-30066, added to CISA's KEV catalog on 18 March 2025 [S, [CISA](https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-github-action-cve-2025-30066)]. Phantom Gyp injects CI steps [V]. Findings: `workflow.unpinnedAction` (third-party `uses:` not pinned to a 40-hex commit), `workflow.pullRequestTarget` with a pull-request checkout, `workflow.expressionInjection` (`${{ github.event.* }}` inside `run:`), `workflow.broadPermissions`, plus #1 on `run:` blocks. Detect by structure (`on` plus `jobs`).

**Verdict.** Niche. zizmor, actionlint and similar tools exist as CLIs [S]; few people review workflows in Finder. Effort M.

### 4.14 HTML smuggling and phish-form indicators (rank 14: niche)

**Evidence.** Microsoft (November 2021): HTML smuggling, with NOBELIUM in May 2021 and later Mekotio, AsyncRAT/NJRAT and Trickbot campaigns [S, [Microsoft](https://www.microsoft.com/en-us/security/blog/2021/11/11/html-smuggling-surges-highly-evasive-loader-technique/)]. I did not retrieve its technical section, so `atob`/`Blob` as indicators are [I]. Findings: `html.decodesAndOffersDownload`, `html.passwordFormPostsElsewhere` (host only), `html.obfuscatedScript`, `html.autoRedirect`, `html.dataUrlNavigation`.

**Caveat.** macOS renders `public.html` itself via `Web.qlgenerator` [V list]; SpacePane already shows HTML as source. Verdict: niche, M. Real phishing attachments are read in Mail, where the system preview applies.

### 4.15 Container image archive card (rank 15: niche)

**Evidence.** Flare scanned November 2025 uploads and found 10,456 Docker Hub images leaking at least one secret, 42% with five or more; most leaks were `.env`, Python and config files, with some in image manifests [S, [Flare](https://flare.io/learn/resources/docker-hub-secrets-exposed)]. Because only the image config JSON is read (layers are nested tars, which the project rules forbid recursing into by default), the card shows: base image platform, `User` (root or not), entrypoint and command, exposed ports, environment variable *names* with values concealed, and `history[].created_by` lines tripping #1. Findings `image.runsAsRoot`, `image.environmentSecrets`, `image.historyDownloadsAndRuns`. It misses the main leak path (files in layers), so say what it does not scan. Verdict: niche, M.

### 4.16 Installer destinations (rank 16: niche)

Suspicious Package's Quick Look extension already shows files, scripts, signatures and notarization [S]; its older description says that preview does no issue checking, while the full app lists issues [S]. SpacePane's differentiator would be typed findings from the payload's Bill of Materials (`pkg.installsLaunchItem`, `pkg.installsPrivilegedHelper`, `pkg.installsKernelOrSystemExtension`, `pkg.writesToSudoersOrShellProfile`) and a #1 scan of `postinstall`. Reading script contents reverses decision 017 ("never read"), so it needs a new decision. Verdict: niche, M, with high prior art. I did not search for pkg-specific incident evidence.

### 4.17–4.19 Smaller or riskier ideas

- **Shortcuts (`.shortcut`).** Signed shortcuts start with `AEA1`, are signed but not encrypted, wrap an LZFSE-compressed Apple Archive that holds a property list (Apple Wiki, community) [S, [AEA1](https://theapplewiki.com/wiki/AEA1)]. The plist lists action identifiers such as Run Shell Script, Run AppleScript and Get Contents of URL, which would make a good "actions this shortcut performs" view. Unproven: whether AppleArchive streams work inside the sandbox, and offsets I read are version-fragile. No incident evidence found. Spike first; L.
- **Windows `.lnk`/`.hta` on a Mac.** ZDI-CAN-25373 (CVE-2025-9491): arguments padded with whitespace to hide commands, exploited by 11 state-linked groups; Microsoft changed Properties display in November 2025 [S, [The Hacker News](https://thehackernews.com/2025/12/microsoft-silently-patches-windows-lnk.html)]. Real, but few Mac users open these. Niche.
- **Automation exports (`.workflow`, Alfred, Keyboard Maestro).** The format is readable (a `document.wflow` plist lists actions), but I found **no verified incident** and did not search per tool. Niche, M each.

## 5. Ruled out, and what cannot be claimed or verified offline

- **Notarization verification, Gatekeeper verdicts, revocation.** Needs `syspolicyd` and a network; Apparency requires a Mach-lookup exception for `syspolicy` [S]. Decision 025 already forbids network lookups. Report stapled-ticket presence only.
- **Reputation and malware verdicts** (hash lookups, "known bad" lists). Online, and a verdict not a typed fact.
- **DMG internals, including the right-click-Open lure.** The volume is compressed HFS+/APFS. Seeing the lure background or the bundle inside means decompressing and parsing a filesystem: large, risky, and beyond the container facts above. Not recommended.
- **Compiled AppleScript (`.scpt`, `.scptd`).** A run-only script has no recoverable source; `osadecompile` fails with `errOSASourceNotAvailable` (-1756) [V, [SentinelOne](https://www.sentinelone.com/labs/fade-dead-adventures-in-reversing-malicious-run-only-applescripts/)]. Static recovery exists only through a third-party disassembler of an undocumented format (`FasdUAS` header; hard-coded strings and Apple-event codes) [V], and routing through OSAKit risks loading AppleScript components and any installed scripting additions (**I could not verify OSAKit's loading behaviour; avoid**). AppleScript *source* (`.applescript`) is covered by 4.1. A strings-only inventory for `.scpt` is possible but low-confidence; skip.
- **Office macros, PDF JavaScript, iWork.** Types macOS previews itself (decision 025); the brief also bars them.
- **`.ics` and `.eml`.** `com.apple.ical.ics` is handled by the system's `iCal.qlgenerator` [V list]. `.eml` is `com.apple.mail.email`; I could not see who previews it (no legacy generator listed; an extension may exist). If Finder shows only an icon, a header-based lens (From versus Reply-To mismatch, double-extension attachments, display-text-versus-URL mismatch) is a clean fit; **spike before any claim**. `.msg` is a dynamic OLE type; skip.
- **QR codes in documents.** Our image types are few; not cheap.
- **ISO/IMG/VHD.** macOS mounts them; the Windows mark-of-the-web motive does not apply on a Mac.
- **`.deb`/`.rpm`, JetBrains plugins, Homebrew formulas and casks.** Rare on a Mac Finder; the Homebrew incidents are lookalike sites (4.1), not formula files. Casks and formulas are Ruby code, so a real lens needs a Ruby parser.
- **Rust crates, Go modules, NuGet, Maven, Composer.** Structurally the same pattern as 4.4 (`build.rs`, `go generate` is not automatic, `install.ps1` is ignored for PackageReference [I], Composer `scripts`). No verified incident in this research; add only on demand. A JAR `Main-Class` is the one genuine double-click launchable in this set; not researched.
- **Login items, background items.** No file artifact to preview; covered by `app.installsHelpers`.
- **Hex dumps, string dumps, "explain this with a cloud model", executing or evaluating anything.** Rejected by decision 025.
- **A single risk score.** Combines unrelated facts into a verdict; conflicts with the typed-finding rule.

## 6. Sources

Labels: [V] opened or run; [S] seen in a search-result summary; [I] inference.

**Repository documents [V].** `docs/decisions/012-safety-findings.md`, `017-package-and-certificate-inspection.md`, `013-archive-listings.md`, `025-competitor-parity-program.md`; `docs/market/2026-10-05-unique-feature-opportunities.md`, `2026-10-05-competitor-landscape.md`; `Packages/PreviewCore/Sources/PreviewContracts/PreviewFindings.swift`, `PreviewModels.swift`; `PreviewCore/HiddenContentScanner.swift`.

**Local experiments [V]** (macOS 27.2): `mdls`, `qlmanage -m`, UDIF trailer and SuperBlob read of 12 local DMGs, `codesign -dvv` and `xcrun stapler validate` on three installed apps; `qlmanage -p` crashed.

**Supply chain**
- [CISA, Widespread supply chain compromise impacting npm](https://www.cisa.gov/news-events/alerts/2025/09/23/widespread-supply-chain-compromise-impacting-npm-ecosystem) [V]
- [StepSecurity, Phantom Gyp](https://stepsecurity.io/blog/binding-gyp-npm-supply-chain-attack-spreads-like-worm) [V]; [Chainguard on Miasma/Phantom Gyp](https://www.chainguard.dev/fr-FR/unchained/chainguard-artifacts-safe-from-miasma-phantom-gyp-npm-attack) [S]
- [GitHub changelog 2026-07-08, npm 12](https://github.blog/changelog/2026-07-08-npm-install-time-security-and-gat-bypass2fa-deprecation/) [V]; [The Hacker News, npm 12](https://thehackernews.com/2026/07/npm-12-disables-install-scripts-by.html) [V]
- [Truesec on Shai-Hulud](https://truesec.com/hub/blog/500-npm-packages-compromised-in-ongoing-supply-chain-attack-shai-hulud) [S]; [Cycode on Shai-Hulud 2.0](https://cycode.com/blog/shai-hulud-2-0-deep-dive-and-actionable-steps-you-should-take/) [S]
- [FutureSearch on LiteLLM](https://futuresearch.ai/blog/litellm-pypi-supply-chain-attack/) [S]; [NetSPI on LiteLLM](https://www.netspi.com/blog/executive-blog/ai-ml-pentesting/litellm-supply-chain-compromise/) [S]
- [CyberInsider on chalk/debug](https://cyberinsider.com/npm-supply-chain-attack-impacts-packages-with-2-billion-weekly-downloads/) [S]
- [Aikido on GlassWorm Zig droppers](https://www.aikido.dev/blog/glassworm-zig-dropper-infects-every-ide-on-your-machine) [S]; [Endor Labs on GlassWorm](https://www.endorlabs.com/reports/invisible-threats-glassworm-unicode-vscode) [S]
- [Dark Reading on ShadyPanda](https://www.darkreading.com/endpoint-security/shadypanda-hackers-weaponize-browsers) [S]
- [CISA on tj-actions](https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-github-action-cve-2025-30066) [S]
- [Flare on Docker Hub secrets](https://flare.io/learn/resources/docker-hub-secrets-exposed) [S]
- [ReversingLabs on malicious ML models](https://www.reversinglabs.com/blog/rl-identifies-malware-ml-model-hosted-on-hugging-face) [S]

**AI-agent artifacts**
- [MCPB MANIFEST.md](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md) [V]
- [Koi on postmark-mcp](https://koi.ai/blog/postmark-mcp-npm-malicious-backdoor-email-theft) [S]; [The Register](https://www.theregister.com/2025/09/29/postmark_mcp_server_code_hijacked/) [S]
- [Check Point on Claude Code project files](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files/) [S]
- [Tenable on CurXecute and MCPoison](https://www.tenable.com/blog/faq-cve-2025-54135-cve-2025-54136-vulnerabilities-in-cursor-curxecute-mcpoison) [S]
- [Snyk ToxicSkills](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub) [S]
- [Tool poisoning summary](https://kayssel.substack.com/p/mcp-security-poisoning-the-tools) [S, secondary; Invariant's original not opened]
- [SOC Prime on EchoLeak](https://socprime.com/blog/cve-2025-32711-zero-click-ai-vulnerability/) [S]
- [OpenSourceMalware on Contagious Interview](https://opensourcemalware.com/blog/contagious-interview-vscode) [S]; [The Hacker News, Jan 2026](https://thehackernews.com/2026/01/north-korea-linked-hackers-target.html) [S]
- [VS Code extension runtime security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security) [V]

**macOS trust and launchables**
- [Jamf, Gatekeeper flaws (`.fileloc`)](https://www.jamf.com/blog/gatekeeper-flaws-on-macos/) [V]
- [SSD Disclosure, Finder `.inetloc` RCE](https://ssd-disclosure.com/ssd-advisory-macos-finder-rce/) [S]; [Intego](https://www.intego.com/mac-security-blog/remotely-exploitable-inetloc-zero-day-vulnerability-hits-the-mac/) [S]
- [SentinelOne, run-only AppleScripts](https://www.sentinelone.com/labs/fade-dead-adventures-in-reversing-malicious-run-only-applescripts/) [V]
- [Malwarebytes, ClickFix and Script Editor](https://www.malwarebytes.com/blog/news/2026/04/clickfix-finds-new-way-to-infect-macs) [S]; [Malwarebytes, Terminal paste warning](https://www.malwarebytes.com/blog/news/2026/03/new-macos-security-feature-will-alert-users-about-possible-clickfix-attacks) [S]; [Objective-See blog 0x85](https://objective-see.org/blog/blog_0x85.html) [S]; [Moonlock](https://moonlock.com/new-clickfix-bypasses-terminal-protections) [S]
- [AppleInsider, fake Homebrew result](https://appleinsider.com/articles/26/03/30/that-top-google-result-for-homebrew-could-infect-your-mac) [S]
- [Mothers Ruin, UDIF format](https://mothersruin.com/software/Archaeology/reverse/udif.html) [V]
- [Apple xnu `cs_blobs.h`](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/kern/cs_blobs.h) [V] (APSL 2.0)
- [Apple, Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) [V]
- [Apple, `quarantinePropertiesKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/quarantinepropertieskey) [V]
- [Apple device-management profile payloads](https://github.com/apple/device-management/tree/release/mdm/profiles) [V] (licence not shown on the page)
- [NetSPI, Malicious MobileConfigs](https://www.netspi.com/blog/technical-blog/mobile-application-pentesting/malicious-mobile-configs/) [S]; [Jamf, Malicious profiles](https://www.jamf.com/blog/malicious-profiles-come/) [S]; [OBTS v3, Mimic in Configuration](https://infocondb.org/con/objective-by-the-sea/objective-by-the-sea-version-30/mimic-in-configuration) [S]
- [AppleInsider, Sequoia runtime protection](https://appleinsider.com/inside/macos-sequoia/tips/whats-changed-in-runtime-protection-for-macos-sequoia) [S]
- [Apple Wiki, AEA1](https://theapplewiki.com/wiki/AEA1) [S]
- [Chromium `crx3.proto`](https://chromium.googlesource.com/chromium/src/+/e9b1018/components/crx_file/crx3.proto) [S]

**Prior art**
- [Suspicious Package Quick Look](https://mothersruin.com/software/SuspiciousPackage/quicklook-classic.html) [S]
- [Apparency](https://mothersruin.com/software/Apparency/) [S]; [Apparency FAQ](https://mothersruin.com/software/Apparency/faq.html) [S]; [Eclectic Light on Apparency](https://eclecticlight.co/2024/08/16/how-to-tell-if-an-app-is-notarized/) [S]

**Other**
- [Okta, support-system incident](https://sec.okta.com/articles/2023/10/tracking-unauthorized-access-oktas-support-system/) [V]
- [Microsoft, HTML smuggling](https://www.microsoft.com/en-us/security/blog/2021/11/11/html-smuggling-surges-highly-evasive-loader-technique/) [S]
- [The Hacker News, Windows LNK fix](https://thehackernews.com/2025/12/microsoft-silently-patches-windows-lnk.html) [S]
- [Macworld, Janicab](https://www.macworld.com/article/221449/new-digitally-signed-mac-malware-confuses-users-with-right-to-left-file-name-tricks.html) [S, from earlier research]

**Could not verify.** App Store coverage of these types (API blocked); third-party scanner licences (API blocked); the JFrog malicious-model count; 2025–26 configuration-profile campaigns; whether `.mcpb` is a ZIP; Apple documentation of `Contents/CodeResources` as the staple location; the system preview of `.webloc`/`.mobileconfig` (preview crash); sandbox access to quarantine attributes and to `Security` signing calls.
