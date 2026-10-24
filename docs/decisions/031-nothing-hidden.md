# Decision 031 — Nothing hidden

Date: 2026-10-24. Status: decided by the owner ("Get rid of everything and make the app approveable") after App Review rejected 1.1.0 (6). Supersedes the Developer Mode rule of [decision 010](010-companion-sidebar-redesign.md) and the matching line of `AGENTS.md`.

## Context

On 2026-10-23 App Review rejected version 1.1.0, build 6 (submitted 2026-10-17 19:14), under Guideline 5.6, Developer Code of Conduct:

> We've identified a pattern of unusual behavior with the app that is commonly associated with fraudulent activity. Specifically, the app contains features that appear to have been intentionally hidden during the review process.

The message names no feature. Guideline 2.5.19, added in Apple's revision of October 2026, states the same rule: no hidden, dormant or undocumented features; functionality must be clear to users and App Review. An inspection of build 6, its review notes and its store page on 2026-10-24 found these candidates, ranked by evidence:

1. **The Developer Mode switch.** Off by default on the General page, it revealed a whole page (Try Preview, Command-5), the File > Open command (Command-O), which was otherwise missing from the File menu, and a longer keyboard Help text. The review notes told the reviewer to turn it on to see an STL model. Disclosed or not, a switch that reveals pages and commands is what this rejection describes.
2. **Features missing from the store description.** Build 6 ships the Safety Lens 2 and 3 previews (decisions 029 and 030): what scripts, editor tasks, agent hooks and MCP servers would run; AI model files, editor and browser extensions and Python packages; password exports and expired certificates. The description in `docs/release/version-1.1.0.md` names them in four lines, but the description saved in App Store Connect for build 6 was the older text without them. A reviewer who opened the attached `32-model.gguf`, `33-extension.vsix` or `34-package.whl` met features the product page never mentions.
3. **Text of a feature the build does not offer.** All three executables still carried the CAD importer failure (`cadImporterUnavailable` and its two strings), and the strings resources carried the Open CASCADE acknowledgements, the "Open-source notices" link title and the STEP and IGES format names. The About page showed the Open CASCADE section only when the bundle held an `OCCT-Notices` folder, which no build without CAD has: UI that appears only in another build.
4. **The submission pattern.** Four submissions of 1.1.0 between 2026-10-13 and 2026-10-17, three removed, seven builds uploaded, an internal TestFlight build with CAD (build 2) and two submitted builds that still linked the unreachable CAD client (builds 3 and 4). This cannot be undone; it argues for one clean resubmission and no further remove-and-resubmit cycles.

Checked and not found in build 6: network access, remote configuration, launch-argument or environment switches, hidden preferences, date, region or account gates, debug-only code, file types switched off by default, and another developer's type identifiers.

## Decision

1. **No switch reveals anything.** The Developer Mode switch, its preference, its sidebar section, its strings in every language and its tests are removed. Try Preview is always the fifth page (Command-5) and File > Open (Command-O) is always in the File menu. The keyboard Help names both. The stored `companion.developerMode` value of earlier builds is left alone: the app never reads it, and code to delete it would ship the very text this decision removes.
2. **Every capability is in the store description.** The App Store Connect description is replaced with the text in `docs/release/version-1.1.0.md`, which now also names Try Preview. A new capability does not ship before its description line exists.
3. **A build carries nothing of a feature it does not offer.** The CAD importer failure case and its strings are removed (the CAD module, which no build without CAD links, reports `unreadableFile` instead); the About page's Open CASCADE section, its notice folder, its open-source link kind and their strings are removed; the four `format.cad.*` strings are removed; `PREV_OPEN_SOURCE_URL` is empty. Decision 028, "Bringing CAD back", lists what to restore.
4. **The archive check enforces it.** For a build without CAD, `script/check_release_archive.py` fails when an executable or a `.strings`/`.stringsdict` resource contains `companion.developerMode`, `developerMode`, `Developer Mode`, `cadImporterUnavailable`, `Open CASCADE`, `openCascade` or `spacepane-cad-source`, in addition to the `PreviewCADFormats` check of 2026-10-17.
5. **Build 8 is reviewed code.** It is `origin/main` plus the build 7 records and this decision. The UI polish commit `685dbf4` that build 7 carried was never reviewed or merged and fails a table test that passes on main (`tablesThatDifferOnlyByOriginOrPartialReadAreNotEqualSoTheViewRefreshes`); it is kept on the local branch `ui-ux-waves-2026-10-20` and can return through its own pull request.
6. **The review notes describe, never instruct to unlock.** They state that every page is visible from the first launch and that nothing depends on a setting, date, region, account or server; `script/test_build_review_samples.py` fails when the notes contain "Developer Mode", "turn on" or "unlock".

## Consequences

- An optional capability that is not ready is either finished and described, or left out of the build. It is never present and switched off.
- Settings that change how visible features behave (file-type switches, appearance, folder previews) stay: they are visible, described and change nothing hidden.
- The reply to App Review is drafted in `docs/release/app-review-reply-2026-10-24.md`; it is sent, and build 8 uploaded and submitted, only on the owner's instruction.
- Appealing to the App Review Board without these changes was rejected as an option: a repeated 5.6 finding can lead to a review of the developer account.
