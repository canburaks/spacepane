# Version 1.1.0

Prepared 2026-10-15 at the owner's request ("configure all necessary files" for release 1.1.0). This file is the
release record for 1.1.0: what it contains, the build settings, the store text to paste and the steps left. Store
text lives in [app-store-listing.md](app-store-listing.md) for 1.0 and here for 1.1.0 until 1.1.0 is approved, when
the listing file takes it over. Uploading, submitting and releasing happen only on the owner's explicit
instruction.

**Status (2026-10-17):** 1.1.0 (build 5) is submitted and Waiting for Review; build 6, the replacement that fixes the findings of the rejection-risk review, is prepared and archived locally but not uploaded (see the status table below). The
earlier record here, that 1.0.0 (build 3) was waiting for review and 1.1.0 would follow its approval, is history: the
1.0.0 submission no longer exists in App Store Connect.

## Submission status

Read in App Store Connect on 2026-10-17 by the session that wrote [the rejection-risk review](../reviews/2026-10-17-app-store-rejection-risk.md);
times are Europe/Istanbul. "Notes version" is the date of the block in [app-store-submission.md](app-store-submission.md#notes-for-app-review)
that was pasted. The repository recorded the submission of 2026-10-13 as 1.0.0 (build 3); App Store Connect lists two
earlier 1.1.0 submissions as Removed and no 1.0.0 submission at all.

| Date | Version | Build | App Store Connect status | Notes version | Release option |
|---|---|---|---|---|---|
| 2026-10-13 18:09 | 1.0.0 as recorded here; listed under 1.1.0 | 3 | Removed from review (the first submission) | 2026-10-13 | Automatic |
| 2026-10-15 23:23 | 1.1.0 | 4 (uploaded 2026-10-15) | Removed from review (it still linked the unreachable CAD client code, Guideline 2.5.19) | 2026-10-15 | Automatic |
| 2026-10-17 11:08 | 1.1.0 | 5 (uploaded 2026-10-17 10:39) | **Waiting for Review** | 2026-10-15 (the block as it stood before the corrections of 2026-10-17) | **Automatic**; the review readiness plan (R-4) asked for Manual |
| not yet | 1.1.0 | 6 (prepared 2026-10-17; archived locally, **not uploaded**) | Not in App Store Connect | 2026-10-17 (corrected block, without the `com.quicklookpro.*` paragraph) | Manual (to be selected at submission) |
| 2026-10-17 18:39 | 1.1.0 | 6 (merged tree of `build6-integration-2026-10-17`, archived 18:1x, exported with Apple Distribution signing) | Uploaded with `--upload` on the owner's instruction; TestFlight processing; not yet selected for the version, not submitted | corrected block (build 6) | unchanged until the owner edits it |

Also on the version page on 2026-10-17: sign-in required off, attachment `SpacePane-Review-Samples.zip`, six Mac
screenshots, and the description of 1.0 ("That is 74 file types") rather than the 1.1.0 text below. Builds 1.0.0 (1)
and (2) were uploaded on 2026-10-10 and 2026-10-12 and never submitted.

### Replacing the submission

What the owner does if 1.1.0 (5) is to be replaced (by build 6) or its metadata corrected while it waits, in order. The queue position
resets at step 5; a rejection resets it too and adds a reply cycle, which is the trade-off the review names.

1. Remove the version from review (App Store Connect, the submission's menu: Remove from Review). The status returns to
   Prepare for Submission; the build stays attached.
2. Select the new build on the version page if there is one (a replacement build raises `CURRENT_PROJECT_VERSION`
   and keeps `PREV_INCLUDE_CAD = NO`); to correct metadata only, keep build 5. Build 6 is that replacement: it fixes the SQLite, Parquet and RAR type declarations (review finding 0), stops registering generic formats for thumbnails (finding 9), drops the `com.quicklookpro.*` identifiers (finding 11) and empties the stale CAD service key (finding 22); the notes of step 3 name `1.1.0 (build 6)`.
3. Re-paste the Notes for App Review from [app-store-submission.md](app-store-submission.md#notes-for-app-review)
   (the corrected block of 2026-10-17), the What's New and the description below, and switch the release option to
   Manually release this version.
4. Re-attach `SpacePane-Review-Samples.zip`, rebuilt with `python3 script/build_review_samples.py` from the same
   commit as the notes, and replace the two screenshots named in
   [store-listing/screenshots.md](store-listing/screenshots.md) once they are recaptured.
5. Add for Review, then Submit for Review. Record the new submission time in the table above.

The release option is editable while the version is Waiting for Review without any of this; the description may be too
(confirm that App Store Connect accepts the edit), the notes, the attachment, the build and the screenshots are not.

## Build settings

| Setting | Value | Where |
|---|---|---|
| `MARKETING_VERSION` | `1.1.0` | `Configuration/Base.xcconfig` |
| `CURRENT_PROJECT_VERSION` | `5` (build 3 was 1.0.0's submission; build 4 was 1.1.0's first submission and carried the unreachable CAD client code that Guideline 2.5.19 rules out, so it is replaced; macOS build numbers must keep rising) | `Configuration/Base.xcconfig` |
| `PREV_INCLUDE_CAD` | `NO` (decision 028 still holds: no STEP or IGES) | `Configuration/Base.xcconfig` |
| Shipped languages | English only; no translation has a recorded review | `tools/localization/languages.json` |

The app, both extensions and the CAD service read these through `$(MARKETING_VERSION)` and
`$(CURRENT_PROJECT_VERSION)` in their Info.plists; `script/check_release_archive.py` refuses an archive with CAD in it.

## What 1.1.0 contains since 1.0.0 (build 3)

From [CHANGELOGS.md](../../CHANGELOGS.md), 2026-10-14 and 2026-10-15:

- **Safety Lens 2** ([decision 029](../decisions/029-safety-lens-2-what-a-file-will-do.md)): script effects (shell, AppleScript, PowerShell, batch, `.tool`), auto-run configuration (VS Code tasks and workspace files, Claude Code and Cursor hooks, MCP servers, dev containers, `package.json`), readable credential exports, launchd jobs, certificate and profile validity, Mesh Print Check, Copy Findings Report.
- **Safety Lens 3** ([decision 030](../decisions/030-safety-lens-3-models-add-ons-and-packages.md)): seven new formats (GGUF, safetensors, pickle and PyTorch, MCP bundles, editor extensions, browser extensions, Python wheels) and install findings in npm and Python source packages. 74 file types become 81.
- **Tier 1 quick wins**: OpenAPI and Swagger endpoint table, download-then-run across lines, property-list slashes, Command-F in table modes (companion), provenance notes in the information panel.
- **No typed filter in Finder** (PR 9, merged 2026-10-15): Finder previews offer no typed filter, find or go-to-line; the table filter opens on demand in the companion; the invisibles note and the profile's sampling and concealed-column notes are removed.
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

### Description (3,757 of 4,000 characters)

The 1.0 description with one bullet added under STRUCTURE, three under KNOW WHAT'S HIDDEN INSIDE, and 74 changed to 81
(the catalog has 81 `id` entries; recounted 2026-10-17). Name, subtitle and keywords are unchanged. Two bullets were
reworded on 2026-10-17 after the rejection-risk review (finding 13): CSV and TSV carry the "where macOS uses SpacePane"
qualifier, and the model bullet names only 3MF, because on macOS 27.2 Apple's own previewers take STL, OBJ and PLY and
CSV. The keyword field still carries `csv`, `stl` and `obj`; whether to drop them is the owner's call and is not made here.

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
• CSV and TSV as sortable tables with a profile of every column, where macOS uses SpacePane for them
• Mermaid and draw.io diagrams, Parquet files, EPUB books, comics and subtitles
• MIDI files with play and scrub controls
• Source code with syntax coloring for 84 languages
• Text files that have no extension, such as Makefile or zprofile
• 3MF models you can turn

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
"3D models", which 3MF covers, and since 2026-10-17 the description's model bullet names 3MF alone. None of this was
observed before build 5 was submitted on 2026-10-17: the three 1.1.0 samples are `notObserved` on every surface.

## App Review

- Notes: [app-store-submission.md, "Notes for App Review"](app-store-submission.md#notes-for-app-review) names 1.1.0 (build 5; build 4 named it until 2026-10-17) and the three new samples. Corrected on 2026-10-17 after the rejection-risk review: step 1 places the "Open System Settings" button in the banner at the top of the General page (not in the "Turn on the extensions" row), step 4 names `31-model.3mf` as the model and keeps `28-binary.stl` with a Try Preview fallback, the opening names the thumbnail extension without claiming thumbnails, and "Tested on macOS 15.2" is gone until a run is recorded. The block in App Store Connect is still the one pasted on 2026-10-17 (see the status table).
- Prepared replies: the 4.2 reply leads with the Theme page's live previews and names 3MF as the model example; the `com.quicklookpro.*` paragraph (identifiers listed in the supported types, neither imported nor exported) is gone from the notes in build 6, because the identifiers are gone from the supported types.
- Samples: `python3 script/build_review_samples.py` adds `32-model.gguf`, `33-extension.vsix` and `34-package.whl` (36 files); `--check` passes (2026-10-17).

## Steps left, in order

Done by the owner on 2026-10-17 (see the status table): build 5 archived, uploaded and selected, the notes pasted, the packet attached, the version submitted. Steps 1, 3 and 4 of the earlier list are therefore closed or overtaken; PR 9 (step 2) was merged on 2026-10-15 and ships in build 5. What is left:

1. The owner decides whether to let the submission run or to replace it (["Replacing the submission"](#replacing-the-submission)) to correct what App Store Connect holds: the 1.0 description (74 file types against 81), the two live screenshots that show the removed Filter field and a `.step` file ([store-listing/screenshots.md](store-listing/screenshots.md)), and the notes block of 2026-10-15. The corrected text is in this repository.
2. Switch the release option to Manually release this version (editable now).
3. Observe the claim-gate list above on the signed build 5 (TestFlight internal group) and record it in `docs/validation/host-matrix.json`; drop any description bullet Finder contradicts before the text is pasted.
4. After approval: on `spacepane-web`'s `app-store-launch` branch, drop the "Coming in an update" badges for Safety Lens 2 and 3 and count the seven formats, then merge that branch to `main` (the owner merges after approval). Switch the promotional text.
