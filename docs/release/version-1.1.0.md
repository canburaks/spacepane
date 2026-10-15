# Version 1.1.0

Prepared 2026-10-15 at the owner's request ("configure all necessary files" for release 1.1.0). This file is the
release record for 1.1.0: what it contains, the build settings, the store text to paste and the steps left. Store
text lives in [app-store-listing.md](app-store-listing.md) for 1.0 and here for 1.1.0 until 1.1.0 is approved, when
the listing file takes it over. Uploading, submitting and releasing happen only on the owner's explicit
instruction.

**Status:** configured, not built for the store, not uploaded. Version 1.0.0 (build 3) is still waiting for App
Review; 1.1.0 is submitted only after 1.0.0 is approved (or rejected and resolved).

## Build settings

| Setting | Value | Where |
|---|---|---|
| `MARKETING_VERSION` | `1.1.0` | `Configuration/Base.xcconfig` |
| `CURRENT_PROJECT_VERSION` | `4` (build 3 was 1.0.0's submission; macOS build numbers must keep rising) | `Configuration/Base.xcconfig` |
| `PREV_INCLUDE_CAD` | `NO` (decision 028 still holds: no STEP or IGES) | `Configuration/Base.xcconfig` |
| Shipped languages | English only; no translation has a recorded review | `tools/localization/languages.json` |

The app, both extensions and the CAD service read these through `$(MARKETING_VERSION)` and
`$(CURRENT_PROJECT_VERSION)` in their Info.plists; `script/check_release_archive.py` refuses an archive with CAD in it.

## What 1.1.0 contains since 1.0.0 (build 3)

From [CHANGELOGS.md](../../CHANGELOGS.md), 2026-10-14 and 2026-10-15:

- **Safety Lens 2** ([decision 029](../decisions/029-safety-lens-2-what-a-file-will-do.md)): script effects (shell, AppleScript, PowerShell, batch, `.tool`), auto-run configuration (VS Code tasks and workspace files, Claude Code and Cursor hooks, MCP servers, dev containers, `package.json`), readable credential exports, launchd jobs, certificate and profile validity, Mesh Print Check, Copy Findings Report.
- **Safety Lens 3** ([decision 030](../decisions/030-safety-lens-3-models-add-ons-and-packages.md)): seven new formats (GGUF, safetensors, pickle and PyTorch, MCP bundles, editor extensions, browser extensions, Python wheels) and install findings in npm and Python source packages. 74 file types become 81.
- **Tier 1 quick wins**: OpenAPI and Swagger endpoint table, download-then-run across lines, property-list slashes, Command-F in table modes (companion), provenance notes in the information panel.
- **If PR 9 is merged first:** Finder previews offer no typed filter, find or go-to-line; the table filter opens on demand in the companion; three notes removed. Merge it before archiving 1.1.0 or record that it is left for 1.1.1.
- 31 of Apple's exact source and script types are now claimed, so `.swift`, `.py`, `.sh`, `.zsh`, `.command` and AppleScript reach SpacePane in the panel (observed 2026-10-14).

## Store text for 1.1.0 (drafts)

Lengths counted with python3 on 2026-10-15.

### What's New (730 of 4,000 characters)

```text
Previews now tell you what a file will do if you run, install or trust it.
• Scripts: downloads that run, hidden decoded commands, quarantine removal, password prompts and login items
• Editor tasks, AI agent hooks and MCP servers that start on their own
• AI model files (GGUF, safetensors, PyTorch): a summary from the header, and what loading would import
• Editor and browser extensions, MCP bundles, and Python and npm packages: permissions and install-time code
• Password exports in readable form, and certificates that are expired or about to expire
• 3D models: size, volume and an estimate of filament for printing
• OpenAPI and Swagger files as a table of endpoints
• Copy a report of the findings
81 file types in all.
```

### Promotional text (169 of 170 characters)

Promotional text can change without a new version; switch to this when 1.1.0 is released.

```text
Press Space and see what a file will do: scripts, editor tasks, AI models, extensions and packages explained. Made on your Mac, read-only, with likely secrets concealed.
```

### Description (3,740 of 4,000 characters)

The 1.0 description with one bullet added under STRUCTURE, three under KNOW WHAT'S HIDDEN INSIDE, and 74 changed to 81.
Name, subtitle and keywords are unchanged.

```text
Quick Look previews that tell you what's really in a file.

Select a file in Finder and press Space. Where your Mac shows a blank icon or a wall of text, SpacePane shows structure: JSON opens as an outline you can fold, a SQLite database as its tables, an archive as a list of what's inside. It also points out what you can't see, such as hidden characters, risky archive entries and likely passwords and keys, which appear as ••••. Everything is read on your Mac and nothing is changed.

HOW IT WORKS
SpacePane is a small setup app with two Quick Look extensions: SpacePane Preview and SpacePane Thumbnails. Turn them on once in System Settings, then use Quick Look as you always do. There is no new app to switch to and nothing to learn.

macOS chooses which app previews each file type. When it uses SpacePane, you get:

STRUCTURE, NOT A WALL OF TEXT
• JSON, JSON Lines, YAML, TOML, XML and property lists as outlines, with the source one click away
• SQLite databases with their tables, columns and row counts, opened read-only
• ZIP, TAR, GZIP, XIP, RAR and 7z archives, and folders, listed without extracting anything
• Jupyter notebooks with their cells and saved outputs, never run
• Markdown as a readable document with a Contents view
• Diffs and patches in color
• CSV and TSV as sortable tables, with a profile of every column
• Mermaid and draw.io diagrams, Parquet files, EPUB books, comics and subtitles
• MIDI files with play and scrub controls
• Source code with syntax coloring for 84 languages
• Text files that have no extension, such as Makefile or zprofile
• STL, OBJ, PLY and 3MF models you can turn

• GGUF and safetensors models, PyTorch files, MCP bundles, editor and browser extensions and Python wheels, summarized without running anything

That is 81 file types, each with its own switch.

KNOW WHAT'S HIDDEN INSIDE
Most previews show what a file looks like. SpacePane also tells you what to check first.
• Likely secrets such as passwords, tokens and keys are concealed, and counted by kind
• Invisible and look-alike characters are flagged, including text hidden in instruction files for AI coding tools
• Archive entries that would land outside the destination folder, disguised names and encrypted entries are called out
• Notebooks whose cells ran out of order are noted
• Scripts, editor tasks, AI agent hooks and MCP servers: what would run, and when
• AI model files: what loading would import; extensions and packages: their permissions and install-time code
• Password exports in readable form and expired certificates are flagged
These are things for you to review, not a verdict that a file is safe.

PRIVATE BY DESIGN
• Every preview is made on your Mac
• The app and its extensions have no network access
• Files are only read, never changed
• Scripts inside files never run
• No account, no analytics, no ads

MAKE IT YOURS
• Turn any file type off and SpacePane leaves it alone
• Light, Dark and High Contrast themes with 12 color schemes
• Your font, size, spacing and line numbers
• Save your look as a profile and share it as a small theme file

GOOD TO KNOW
• If macOS or another app already previews a type, such as plain text or some source code, SpacePane can't override that choice. An info symbol in the preview shows when SpacePane made it, and the app can list other apps that preview the same types.
• Concealing secrets relies on patterns and can miss an unusual one.
• Files kept only in the cloud are previewed once they are downloaded.
• Thumbnails skip files that hold secrets, and some types keep their usual icon.

Requires a Mac with Apple silicon and macOS 15 or later.

Mac, macOS, Finder and Quick Look are trademarks of Apple Inc. SpacePane is not affiliated with Apple.
```

### Claim gate

The listing's rule holds: advertise only what was observed on the store-signed build
([app-store-listing.md, "Validation gate"](app-store-listing.md#validation-gate-what-the-copy-may-claim)). Before
pasting, observe in the Quick Look panel on the 1.1.0 build at least: a script with findings, a `.vscode/tasks.json`,
`32-model.gguf`, `33-extension.vsix`, `34-package.whl`, an OpenAPI JSON file, and the 3MF print lines. Drop any
bullet whose feature Finder does not show. On macOS 27.2 Apple's previewers keep CSV, STL, OBJ and PLY, so the 3D
print line holds for 3MF in Finder and for the other three only in the companion; the What's New wording says
"3D models", which 3MF covers.

## App Review

- Notes: [app-store-submission.md, "Notes for App Review"](app-store-submission.md#notes-for-app-review) now names 1.1.0 (build 4) and the three new samples.
- Samples: `python3 script/build_review_samples.py` adds `32-model.gguf`, `33-extension.vsix` and `34-package.whl` (36 files); `--check` passes.

## Steps left, in order

1. 1.0.0 (build 3) approved by App Review.
2. Decide on PR 9 and merge it, or leave it for 1.1.1.
3. Observe the claim-gate list above on a development-signed build of `main`, then archive: `./script/build_and_run.sh --archive`, then `python3 script/check_release_archive.py` on the archive.
4. On the owner's instruction: upload (`--upload`), create version 1.1.0 in App Store Connect, select build 4, paste What's New and the description, attach `SpacePane-Review-Samples.zip`, paste the notes, submit.
5. After approval: on `spacepane-web`'s `app-store-launch` branch, drop the "Coming in an update" badges for Safety Lens 2 and 3 and count the seven formats, then merge that branch to `main` (the owner merges after approval). Switch the promotional text.
