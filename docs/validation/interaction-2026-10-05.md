# Interaction and live reload validation — 2026-10-05

Scope: the interaction workstream of [the competitor parity program](../decisions/025-competitor-parity-program.md), designed in [decision 021](../decisions/021-preview-interaction-and-live-reload.md). Branch `parity/interaction`, built on the shared base commit `20acae7`. Host: macOS 27.2 (Darwin 27.2.0), arm64, the full Xcode toolchain selected at `/Applications/Xcode.app` with Swift 6.4 (`swift-driver 1.168.6`), Debug configuration.

## What was run

All three entrypoints pass on the final tree:

| Command | Result |
|---|---|
| `./script/build_and_run.sh --check` | Manifests, project, 388 localization keys in 14 locales, 13 localization script tests, 31 appearance samples and the icon verified. |
| `./script/build_and_run.sh --check-compiler` | `swift build` of the package, then strict-concurrency typecheck (`-swift-version 6 -strict-concurrency=complete -default-isolation nonisolated`) of `Apps/PrevApp`, `Extensions/PrevPreviewExtension`, `Extensions/PrevThumbnailExtension` and `Native/CADImportService`. |
| `./script/build_and_run.sh --test` | `swift test`: 543 tests in 46 suites passed (this workstream adds 79 of them). Then the isolated companion executables: 11 companion model checks, 3 file-drop checks, **5 new live-reload session checks**, the SQLite snapshot checks and 5 appearance interaction groups. |

The 79 new package tests, by file under `Packages/PreviewCore/Tests/`:

| File | Tests | Covers |
|---|---|---|
| `PreviewCoreTests/Interaction/PreviewSourceMonitorTests.swift` | 18 | modify, append, attribute change, atomic save followed to the new file, repeated atomic saves, rename away, delete, delete then recreate, a 60-write burst reported once, maximum delay under endless changes, quiet file, folder watch, unwatchable items (missing file, FIFO, `/dev/null`), stop and `stopAndWait`, a pending report dropped on stop, consumer cancellation, dropping the monitor, 20 lifecycles without a leaked descriptor, no change to the item or its folder |
| `PreviewCoreTests/Interaction/PreviewLiveReloaderTests.swift` | 13 | a change runs load and apply, a burst is one reload, a slow reload that finishes after a newer one is dropped, `stop()` abandons a reload in flight and releases the descriptor, moving to another file drops the earlier watch and its late result, a deleted file reloads once and ends, the real pipeline with edits and atomic saves, reloading turned off, unreadable settings, an unwatchable item, `reloadNow`, which outcomes are watched, dropping the reloader |
| `PreviewRenderersTests/Interaction/InteractionLogicTests.swift` | 9 | zoom steps and bounds, paths (`$.a.b[2]`, quoting, escapes, records), line-number parsing in several scripts, line ranges with every separator, shortcut matching, filter query folding and bounds |
| `PreviewRenderersTests/Interaction/GoToLineAndCopyTests.swift` | 12 | Command-L through `performKeyEquivalent`, inline bar, focus, Escape, jump and scroll, announcements, invalid entries, CRLF and empty text, where the shortcut is declined, bar lifetime, Copy All (concealed text, rendered Markdown, outlines, no content, editing field), context menu, find still reaches the text finder, bar layout |
| `PreviewRenderersTests/Interaction/OutlineFilterAndCopyTests.swift` | 17 | filter matches and ancestors, case and diacritics, no matches, matched containers and markers, restoring after clearing, next and previous match, replacement keeping rows and filter, 20 000-row filter, the bar inside the preview (Command-F, Escape twice, announcements, mode switch, new request), row copy commands, several rows, filtered paths and record documents, the secondary-click menu, accessibility custom actions, Command-Up and Command-Down |
| `PreviewRenderersTests/Interaction/ZoomBadgeAndReloadRenderingTests.swift` | 10 | zoom keys, limits, reload and new request, selection, outline and table restyle, badge only while a preview is shown, verbatim configured name and translated caption, selection and scroll kept across a reload, mode kept and deleted file state, an outline's open rows kept |

Tests that touch the pasteboard use `NSPasteboard(name:)` with a unique name, released afterwards; none reads or writes the general pasteboard. Tests that need first responders, key equivalents or menus use an off-screen `NSWindow` and call `performKeyEquivalent` with synthesized key events. Live-reload tests use temporary directories only. The descriptor leak checks use a process-wide counter that the monitor maintains; the suite is serialized because the counter is process-wide.

The session checks (`Tests/Integration/PreviewLiveReloadChecks.swift`, compiled with the production `PreviewSession`) show: an edit reloads under the same `generation` without a loading state; an atomic save and a following edit are followed; a deleted file shows `.unavailable(.missingFile)`; turning the preference off and on, and hiding and showing the page, stop and resume watching; closing or cancelling stops reloading; a file-type policy change still replaces the request and live reload resumes under it.

One existing check changed: `CompanionModelChecks.appearanceRetainsSafeContent` deletes the opened file to prove that appearance edits never reread it; it now opens the file with live reload off, since a live reload would legitimately show the deletion. A format-key list in `tools/test_localization.py` gained the six new formatted keys.

## What was not verified

State this plainly, because none of it follows from the results above:

- **Finder-hosted behavior.** No signed build, no Quick Look extension launch and no Finder interaction was run. Whether Finder delivers key events (Command-L, Command-F, Command-Plus, Command-Shift-C) to the extension's view, keeps the extension alive, or lets a sandboxed extension open the previewed file for events and keep that access after the completion handler, is unknown. Live reload may simply be absent in Finder if any of that fails; the preview is unaffected.
- **Companion window with a real user.** Key equivalents were tested through `performKeyEquivalent` in an off-screen window, not through SwiftUI's responder and menu routing. Whether a SwiftUI command or the main menu ever takes Command-L, Command-0 or the zoom keys before the preview does is unverified.
- **Real keyboard focus** inside Quick Look, Tab order between the bars and the content, and the system find bar inside the remote view.
- **VoiceOver.** Accessibility labels, help, custom actions and announcements are set and their values are tested, but nothing was spoken or navigated with VoiceOver.
- **Native-speaker review.** The 23 `preview.interaction.*` strings in 14 languages are drafts. Placeholder structure is validated; wording, layout at text expansion, right-to-left layout and the Bengali, Hindi and Kurmanji digit and keyboard-name conventions are not reviewed.
- **Sandboxed re-open after an atomic save** in the companion with a security-scoped URL, and event delivery on network, FUSE or cloud-synced volumes.
- **Revoke.** The `.revoked` path (volume unmount) is implemented but not exercised.
- **Performance.** The 20 000-row filter is a loose bound in a Debug test (under 5 s), not a measured Release budget. Live-reload latency (300 ms debounce, 2 s maximum) is a design value, not a measurement.
- **Tables.** Row replacement still resets a table's scroll and selection (the listings workstream's view). Table filtering, and Command-Up and Command-Down in tables, are not part of this workstream's code or tests; Command-Up and Command-Down are verified for outlines only through the document-boundary commands the key bindings produce.
- **3D previews.** Reload re-imports geometry and keeps the camera, but this was only unit-reviewed, not exercised with a CAD file.

## Reproducing

```
./script/build_and_run.sh --check
./script/build_and_run.sh --check-compiler
./script/build_and_run.sh --test
```

Focused runs: `swift test --package-path Packages/PreviewCore --filter "PreviewCoreTests.LiveReload"` and `--filter "PreviewRenderersTests"`. A failing run during development (a descriptor count compared against a baseline taken while an earlier test's descriptor was still closing) was fixed by waiting for the counter to drain at the start of each test; it showed only under the load of the full parallel run.
