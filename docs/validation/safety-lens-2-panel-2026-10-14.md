# Safety Lens 2 in the Quick Look panel — 2026-10-14

Evidence for [decision 029](../decisions/029-safety-lens-2-what-a-file-will-do.md) on a real Quick Look host. It is not Finder evidence: AGENTS requires Finder, thumbnails and VoiceOver to be observed separately.

## Setup

- macOS 27.2, Xcode 27.0, Apple silicon.
- Debug, development-signed build of branch `safety-lens-2`, built and registered by `./script/build_and_run.sh` from `.build/xcode`. PlugInKit listed `org.webmeister.spacepane.preview` as enabled. No store build was installed.
- Host: `qlmanage -p <file>`, which opens the Quick Look panel. The provider was attributed by whether the `PrevPreviewExtension` process ran during the preview; the extension was stopped before each file.
- Fixtures: synthetic, inert, non-executable files written with the file tool into the session's temporary folder. None was run.
- Pictures: each capture shows only the panel's own window (`screencapture -l`). They were inspected and not committed. One earlier full-screen capture showed unrelated windows; it was deleted at once and not used.

## Findings shown

| Fixture | Provider | Collapsed banner | Notes |
|---|---|---|---|
| `.vscode/tasks.json` that starts with a comment and runs a task on folder open | SpacePane | "1 finding to review." | Previewed as JSON with comments. Before this branch, strict JSON refused the file |
| Launch agent property list (`/bin/sh -c`, RunAtLoad, KeepAlive, StartInterval 300) | SpacePane | "5 findings to review." | Job, start at load, keep alive, interval, inline script |
| `install.sh` with download-and-run, decode-and-run, quarantine removal, a hidden-answer password dialog and `sudo cp … /Library/LaunchDaemons/` | Apple's text previewer at first, then SpacePane | First "1 likely secret hidden.", then "6 findings to review." | See the three defects below |

**Copy Findings Report** appeared beside Show details in every SpacePane panel.

## Defects found and fixed on the branch

1. **Shell scripts went to Apple's previewer.** The extension claimed `.sh` only through `public.source-code`; Apple's text previewer won. Claiming `public.shell-script` exactly made SpacePane serve it (commit 6f86e8c).
2. **Concealment cut a quote.** The privacy filter turned `"Password:" default answer …` into `"Password:••••`, the quote never closed, and the lens read the next line (`sudo cp … LaunchDaemons`) as quoted text. Lines that hold the concealment token now end with the lexer's cut marker (commit c7c151a).
3. **The collapsed banner hid the warnings.** With any secret concealed it read "1 likely secret hidden" while three warnings waited behind Show details. A warning other than the secret-inventory kinds now leads with "N findings to review" (commit 7b19bdd). Cautions keep the earlier Q50 summary.

## Routing survey

The 31 files of `dist/review-samples/SpacePane-Review-Samples` plus five script fixtures, each opened with `qlmanage -p`:

| Result | Types |
|---|---|
| SpacePane | JSON, JSON Lines, YAML, TOML, XML, property list, SQLite, ZIP, TAR, GZIP, XIP, 7z, folder, notebook, Markdown, patch, Mermaid, draw.io, Parquet, EPUB, CBZ, MIDI, 3MF, PowerShell |
| SpacePane after commit 3ef8b98 | Swift, Python, `.sh`, `.zsh`, `.command`, AppleScript text |
| Another provider | CSV (`public.comma-separated-values-text`); STL, OBJ and PLY (Apple's Hydra and SceneKit previewers claim the same types exactly); SRT (`com.goodsnooze.srt`, a type another installed app exports); RAR (its metadata still showed a dynamic type) |

What the survey shows, on macOS 27.2 and in this host:

- A type that the extension claims only through a parent type loses to Apple's previewer.
- Claiming the exact type wins against Apple's text previewer.
- It does not win against Apple's dedicated 3D previewers, nor for CSV.

Commit 3ef8b98 therefore claims 31 of Apple's own source and script types exactly. HTML, CSS, `.ts` and types exported by other apps stay unclaimed.

Consequences for decision 029:

- **The script effects lens and the auto-run configuration lens reach the panel.**
- **The credential-export guard reaches the panel for JSON exports only.** CSV exports go to another provider on macOS 27.2.
- **Mesh Print Check reaches the panel for 3MF only.** STL, OBJ and PLY go to Apple's previewers on macOS 27.2.
- **Both still work in the companion's direct preview.** Whether macOS 15 or 26 routes CSV, STL, OBJ and PLY differently is not established.

## Not established

- Finder's Space-bar panel and preview pane.
- Thumbnails.
- VoiceOver and keyboard access to the report action.
- The expanded findings rows, which were not opened.
- The copied report text in a real pasteboard.
- Any macOS other than 27.2.
- A store-signed build.

## Cosmetic issues seen, not fixed

- In the script preview, syntax decoration still colours the line after a concealed quote as a string; the lens itself reads it correctly.
- The launch agent's converted JSON shows escaped slashes (`\/bin\/sh`); this predates the branch.
