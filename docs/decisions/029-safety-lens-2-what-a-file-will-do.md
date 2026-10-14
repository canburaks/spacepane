# Decision 029 — Safety Lens 2: what a file will do

Date: 2026-10-14. Status: accepted at the owner's request ("Go", after the quick-win list drawn from [the 2026-10-13 research](../market/2026-10-13-new-file-types-and-features.md)). Implementation in progress; this record states the contract and the rules each feature follows.

## Context

The 2026-10-13 research found that format breadth no longer differentiates: a current Quick Look tool exists for many candidate formats. What stayed open was an answer no competitor found gives: what a file will do if it is run, installed or trusted. [Decision 012](012-safety-findings.md) already provides typed findings and a banner. This decision extends them to six quick wins:

1. **Script effects:** what a shell, AppleScript, PowerShell or batch script would do when run.
2. **Auto-run configuration:** editor tasks that run when a folder opens, AI-agent hooks and permissions, MCP servers, dev-container commands and package install scripts.
3. **Readable credential exports:** password-manager and one-time-code exports saved without encryption.
4. **launchd jobs:** what a LaunchAgent or LaunchDaemon property list makes macOS run, and when.
5. **Certificate and provisioning-profile validity:** expired, expiring soon, not yet valid, short RSA keys.
6. **Copy Findings Report:** the findings as a list, with no text from the file.

A seventh, **Mesh Print Check**, brings the existing measurement code to STL, OBJ, PLY and 3MF and adds print-relevant facts. It produces geometry facts, not findings (decision 012: geometry presentations carry no findings).

## Decision

### Lens contract (`PreviewContracts/PreviewTextLens.swift`)

- `PreviewTextLens.findings(in:request:context:)` reads the **displayed, concealed** text, the same text the gutter numbers, and returns findings. It never sees source bytes.
- `PreviewLensRequest` carries the format, the file name, the parent folder's name, the adapter's source-language hint and the text origin. The parent folder's name is URL metadata, read with no file access, and never appears in a finding.
- Lenses attach to registrations with `AdapterRegistration.adding(lenses:)`. `StandardLenses` in `PreviewFormats/Lenses` is the one table that maps formats to lenses; hosts and adapters are unchanged.
- The pipeline runs a registration's lenses after the privacy filter and the hidden-content scan, merges their findings through `PreviewFindings.normalized`, and never calls a lens for an app-made summary. A lens failure drops only that lens's findings; cancellation and the request deadline still end the request.

This is the second deliberate shared-contract change for findings, for the reason decision 001 allows: a new presentation capability that existing adapters cannot express.

### Findings

- New kinds in five groups: `script.*`, `autorun.*`, `export.*`, `launch.*`, and `certificate.*` / `profile.*`. Each has a default severity in the contract and wording in `FindingText`.
- New typed details: `days(Int)` (whole days until a stated end of validity, rounded up) and `seconds(Int)` (a declared repeat interval).
- Decision 012's rules hold unchanged: no source values, lines of the displayed text, bounded counts and positions. A script's URL, a server's command, a password, a program path: none is carried. The finding points at the line instead.

### Rules every lens follows

- **Facts, not verdicts.** Wording states what the file does ("downloads code from the internet and runs it"), never that it is malware or that it is safe. No lens ever reports an all-clear.
- **Conservative recognition.** A configuration lens acts only when the file's name, its folder and its structure agree (for example `tasks.json` in `.vscode` with a `tasks` array). A missed detection is acceptable; a false alarm on ordinary files is a defect.
- **Comments and documentation do not count.** A command inside a shell comment or an AppleScript comment is not reported.
- **Bounded and cancellable.** Work is linear in the displayed text, checks the request's checkpoint in loops, and allocates nothing proportional to an attacker-chosen count beyond the text itself.
- **Never execute, evaluate or decode-and-interpret.** A decode-and-run finding reports that the script decodes text and runs it; it does not decode the payload.

### Validity findings

The certificate and provisioning-profile adapters already take an injected clock. They add `certificate.expired`, `certificate.expiresSoon` (within 30 days), `certificate.notYetValid`, `certificate.weakKey` (RSA shorter than 2,048 bits), `profile.expired` and `profile.expiresSoon` (within 30 days). Tests set the clock; none waits on wall time.

### Copy Findings Report

The banner gains a **Copy Findings Report** action. It writes a plain-text list: a heading with the localized format name, one line per finding with its severity, its wording and its lines, and a footer saying the report holds no text from the file. It never includes the file name, a path, or any source text, so it can be pasted into a ticket. It uses a private pasteboard in tests.

### Mesh Print Check

`GeometryMeasurer` moves from the CAD module into the contracts so STL, OBJ, PLY and 3MF are measured with the same code as CAD was. The geometry view then shows, beside surface area, volume and bodies: the size of the bounding box; an estimated material weight and filament length for one stated common material, only when the volume is known and the unit is declared or assumed millimetres; and counts of open edges and of edges shared by more than two faces. Values are approximations of the displayed tessellation.

### Localization

Every new string is a typed `PreviewStrings` key with translator context, added through `tools/localization/additions/safety-lens-2.json` in all 14 chosen languages. Counted findings are plural keys printed through `PreviewStrings.count`. Translations are drafts pending native-speaker review; version 1.0 ships English only.

## Feature boundaries

| Feature | Producer | Owner (tools/ownership.json) |
|---|---|---|
| Script effects | `ScriptEffectsLens` on source code and extension-free text | `sl2-script` |
| Auto-run configuration, credential exports, launchd jobs | `AutoRunConfigLens`, `CredentialExportLens`, `LaunchdJobLens` on JSON, JSON with comments, package.json, CSV, TSV and property lists | `sl2-config` |
| Validity | Certificate and provisioning-profile adapters | `sl2-expiry` |
| Mesh Print Check | Mesh adapters and the shared measurer; the geometry view | `sl2-mesh` |
| Copy Findings Report | The findings banner | `sl2-report` |
| Contract, kinds, wording, string keys, pipeline step, lens table | Lead | `lead` |

## Consequences

- Adding a lens is a lens file plus one row in `StandardLenses`. Adding a kind touches the shared enum, the wording switch and one string key with its translations, as in decision 012.
- Findings remain claims about file content. None of this changes which provider macOS chooses for a type.
- Thumbnails stay content-free and ignore findings.

## Validation

Each lens has positive fixtures, near-miss fixtures that must stay silent (comments, documentation, ordinary configuration), malformed-input and cancellation tests, and a pipeline test that its findings reach the presentation with correct lines. Finder-hosted rendering, VoiceOver review and native-speaker review stay open, as for decision 012.

## Implementation notes — 2026-10-14

Recorded at integration of branch `safety-lens-2`; each point narrows or completes a rule above.

- **Where each configuration lens looks.** The auto-run lens reads `.vscode/tasks.json`; `settings.json` and `settings.local.json` in `.claude`; `.mcp.json` and `claude_desktop_config.json`; `mcp.json` in `.cursor`, `.vscode`, `.roo` or `.amazonq`; `.gemini/settings.json`; `windsurf/mcp_config.json`; `devcontainer.json` and `.devcontainer.json`; and `package.json`. The same text under any other name or folder says nothing. A server marked `"disabled": true` is not counted.
- **VS Code's editor files allow comments.** `tasks.json`, `launch.json`, `keybindings.json` and `mcp.json` are now filename aliases of JSON with comments. VS Code's own `tasks.json` template starts with a comment, which strict JSON refused, so before this change such a file had no preview at all. The website reads these aliases; run `npm run data:sync` in `spacepane-web` when this branch reaches `main`.
- **One-time-code seeds are concealed.** `totp`, `hotp`, `otp` and `otpauth` join the credential words, so a password-manager export's `login_totp` or `OTPAuth` column is concealed like its passwords.
- **Credential exports.** A CSV or TSV is recognized by a header holding complete password, user and address column names; records count only when their password cell is non-empty. Keeper exports have no header row and are not recognized.
- **Script effects.** Command words are recognized only at command positions, after comments, quoted text, `echo` arguments and here-document data are set aside. Shell download-then-run is recognized within one logical line. Ordinary developer scripts can still produce caution-level findings (`sudo`, `launchctl load`, appending to `~/.zshrc`), which is their purpose; warning-level kinds need an explicit run, decode-and-run, quarantine removal, protection change, password prompt or secret read.
- **An IPA reports its embedded profile's validity**, through the same findings as a standalone profile. `PackageSummary.document` takes optional findings.
- **Mesh Print Check.** `GeometryMeasurer` lives in `PreviewContracts` with `package` access. STL, OBJ and PLY keep an undeclared unit (decision 027, Q-11), so their solid-PLA estimate is worded "If the units are millimetres …"; a 3MF, which declares or implies millimetres, gets the plain wording. There is no separate size line: the first summary line already shows the extents. Edges shared by more than two faces include bodies that touch along a face.
- **The banner's buttons stack** vertically when the three no longer fit one row. The report lists every finding in banner order and leaves out decoded hidden text.
