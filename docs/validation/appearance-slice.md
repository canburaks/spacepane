# Preview appearance validation

Date: 2026-10-03 (Europe/Istanbul). Environment remains the Apple silicon Command Line Tools host recorded in [platform-spike.md](platform-spike.md). Full Xcode and production signing are not configured.

This is the historical appearance-slice result. The [JSON Lines and controls continuation](json-lines-and-controls.md) supersedes its schema/test totals and adds repeatable model checks without retroactively claiming its unfinished GUI checks passed.

## Implemented

- Typed system/light/dark/high-contrast themes and validated font family, size, weight, italic, line/character spacing, ligatures, tab width and wrapping.
- Complete schema 3 snapshots, migration from schemas 1/2, fail-closed invalid data and independent appearance/file-type resets.
- Separate native Appearance settings with a live inert JSON/Unicode sample using the shared renderer; localized fallback, saving, saved and failure states.
- Appearance-only session updates retain the safe presentation without starting source reads. File-type changes retain cancellation and disabled-content handling.
- JSON key/string/number/literal colors applied only to concealed text, using a semantic syntax hint instead of format-ID switches in rendering.
- Bounded decoration: at most 262,144 UTF-16 units and 20,000 tokens. Above either limit the same content receives plain styling. This cap does not reduce the core's content budget.
- Native selection and viewport preservation during style changes; correct unwrapped document width; deferred measurement until a usable host viewport exists; a filled preview background for forced themes.

The architecture and scope are specified in [the appearance decision](../decisions/003-preview-appearance.md). This is not general source-language highlighting, a profile editor or full M2 completion.

## Observed checks

| Check | Result | Evidence boundary |
|---|---|---|
| `./script/build_and_run.sh --test` | **57 tests in 3 suites passed**, including parameterized cases | Shared contracts, preferences, parsing/privacy and native AppKit rendering on this host |
| `./script/build_and_run.sh --check` | **Passed**, 93 localization keys, 3 targets, 2 embedded extension declarations, 2 formats | Resource and project consistency; development English only |
| `./script/build_and_run.sh --check-compiler` | **Passed** | Companion and both extensions type-check with Swift 6 complete checking and a macOS 15 deployment target |
| `--build-companion` / `--run-companion` | **Passed** | Ad hoc signed companion-only prototype builds and runs; no Finder extensions installed |
| Native JSON preview smoke check | **Passed** | Screenshot and accessibility text show syntax colors and concealed synthetic credentials; safe text remains visible |
| Appearance settings GUI interaction audit | **Incomplete: inspection-service failure** | Opening/inspecting Appearance repeatedly terminated `SkyComputerUseService`; the companion process remained running |

The renderer tests verify Unicode UTF-16 token ranges, escaped strings, malformed numeric runs with linear bounded traversal, decoration limits, contrast ratios (at least 4.5:1 normally and 7:1 for high contrast), missing-font and unsupported-italic fallback, paragraph attributes, exact safe-text preservation, selection/viewport retention, narrow and zero-width hosts, horizontal sizing and theme header contrast. These are behavioral tests, not Release performance benchmarks or a full accessibility certification.

Preference tests verify every theme/weight round trip, finite bounds, missing required current-schema fields, unknown IDs, invalid font names, migration preserving disabled choices, reset independence, nonmutation on migration and atomic publication. Source review also fixed same-value reset/retry after corrupt storage or a failed save; the reset must publish a valid snapshot while retaining disabled policy.

## GUI limitation and cleanup

The inspection service failed with `EXC_BREAKPOINT` / `SIGTRAP` in `Array.remove(at:)`. Resetting its session and restarting the companion restored inspection of the main window, but inspecting Appearance failed again. No companion crash was observed. This tool failure does not establish whether the full settings accessibility hierarchy is correct; that audit remains open.

The planned interactive checks for changing appearance after a fixture is moved, resetting appearance with disabled formats and verifying saved choices after relaunch were not completed. Do not report them as passed. The corresponding renderer/persistence unit coverage does not replace those end-to-end checks. Original preference bytes were verified unchanged, and the temporary copied fixture was restored. No real user file or system Quick Look preference was modified.

## Remaining gates

- [ ] Complete the Appearance controls/live-sample interaction audit at wide and narrow window sizes, including keyboard and VoiceOver.
- [ ] Verify appearance-only changes keep an already-open preview after its source becomes unavailable, and confirm settings across an actual companion relaunch.
- [ ] Exercise reset/retry through the UI after corrupted or unwritable settings, preserving disabled file types.
- [ ] Validate increased contrast, appearance transitions, missing fonts and language/RTL behavior in signed Finder hosts and on macOS 15.
- [ ] Measure Release rendering cost near the content/styling limits before making performance claims.
- [ ] Complete remaining customization: temporary zoom, additional grammars, token-level customization and later profiles.
