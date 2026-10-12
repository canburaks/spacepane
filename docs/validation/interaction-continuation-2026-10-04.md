# Interaction and localization continuation — 2026-10-04

This pass continues the 22-format implementation. It distinguishes code regressions,
companion observations, actual Finder invocation and release gates. Host: Apple
silicon macOS 27.2, Xcode 27.0, macOS 15 deployment target.

## Companion observations and fixes

- Command-comma selected Settings inside the existing `companion.main` window.
  Typing `package.json` into search showed the matching type and the explicit
  whole-group action scope. No file-type preference was changed.
- Catalog rows displayed only suffixes, leaving exact-name types without filename
  details and omitting `.env.*`. A shared companion presentation model now derives
  suffix, exact-filename and prefix patterns from the catalog, removes duplicates
  and uses locale-aware list formatting. The exact protocol filenames remain
  unchanged. Folder rows do not invent extensions. Both Supported Files and
  Settings consume this model; Settings accessibility hints describe the format.
- Clicking Setup and pressing Right did not change tabs or establish tab focus on
  this host. That attempt is not counted as keyboard-only navigation verification.
  System keyboard-access preferences were not modified.
- Inspecting Customization again terminated `SkyComputerUseService`, producing
  `SkyComputerUseService-2026-10-04-131304.ips`; the companion process (PID 28183)
  stayed alive. Screenshot inspection also failed through the same service. The
  companion was restarted and the documented UI tool reset restored access to
  other screens. The Customization/VoiceOver gate remains open; this is not evidence
  of an app crash and no alternate automation API was used to bypass the failure.

## Confirmed renderer regressions

Seven focused tests cover four fixes and retained behavior:

- An unfocused outline intercepted Command-C. It now handles that key equivalent
  only when it owns first-responder focus; another text responder keeps its copy
  command. The regression does not touch the general clipboard.
- Reapplying appearance to the same safe hierarchy discarded row selection.
  Reloading existing cells now retains selection and expansion. A new request
  generation still explicitly clears selection, even when safe content is identical.
- New and cleared MIDI presentations exposed enabled playback/scrubbing controls.
  Those controls now start disabled and return to disabled/reset state on clear.
- Outline fields repeated their exact safe text in accessibility label and value.
  They now use native static-text value semantics while retaining duplicate-key
  help. This corrects attributes; actual VoiceOver speech remains unverified.

Rendered Markdown characterization also confirms safe selection persists across
restyling, private-pasteboard copy contains only concealed text, and a synthetic
JavaScript-looking link remains inert text. No document code or audio was executed.

## Finder observations after native companion quit

The companion was quit using Command-Q. A separate process check confirmed that
`Prev` was absent. Three newly created synthetic local fixtures were selected in
Finder and opened with Space. No cache reset, provider-selection override, Finder
restart or extension-preference change was used.

| Fixture | Resolved Spotlight content type | Observed Quick Look behavior |
|---|---|---|
| `configuration.yaml` | `public.yaml` | Native concealed source; the synthetic password is replaced by bullets. The block sequence triggers the explicit structured-view fallback. |
| `document.md` | `net.daringfireball.markdown` | Concealed Source and Rendered modes. Selecting Rendered showed native heading/bold text, the offline-resource notice and the concealed synthetic password. |
| `listing.zip` | `public.zip-archive` | Native Summary reports ZIP, one entry and no partial listing. Expanding Entries and its first item shows `example.txt`, File and 26 bytes. No extraction was requested. |

The running preview extension (PID 36009) was attributed to the existing Xcode
DerivedData build of `com.canburaksofyalioglu.filepreview.preview`; its signature
was verified. This is the signed baseline artifact rebuilt in the previous pass,
not proof that subsequent interaction fixes have been loaded by that process.
The separate final canonical Xcode build validates those source changes.

All three SHA-256 digests were unchanged after inspection:

| Fixture | SHA-256 |
|---|---|
| `configuration.yaml` | `0c45c49289f1aaff785d67480c1401f47af8704b457f3fcc79312ed339e0244d` |
| `document.md` | `d07221ed24c894fb7cd25732f03864eee0f36f1bd3012edc6176e5ed4782cc7a` |
| `listing.zip` | `745450df1c83033af7c2e45292343d85ddcc9192e125a9eb73e856edc52757e5` |

Fixture sources are under ignored `.build/host-probe/continuation-20261004/` and
contain synthetic data only. Markdown mode changes intermittently returned an AX
failure; the screenshot visibly confirmed rendering. ZIP expansion was confirmed
by the accessibility tree. Neither is a complete VoiceOver audit.

This adds three format-specific Space-bar observations after graceful companion
quit. It does not prove cold extension startup, all Finder surfaces, every variant,
per-format thumbnails, effective Finder language selection, macOS 15/Intel or the
real Finder-to-companion sandboxed drag grant.

## Localization and final validation

The translation checker previously discarded positional argument indices, allowing
`%1$@ / %1$@` to pass against `%1$@ / %2$@`. Validation and merge now share a parser
that preserves argument identity, type, multiplicity and numeric format; legitimate
positional reordering remains supported. Unsupported directives and mixed positional/
sequential formats are rejected. Strict checking applies to typed formatted resource
calls and bundle-name templates. Text-only copy can contain literal percentages
without displaying doubled percent signs. Dynamic/unrecognized formatted-key call
sites fail static validation instead of silently escaping coverage.

- `--check`: three targets, 22 formats, 259 keys and 14 languages validated; all
  **13 Python localization-tool regression tests** passed.
- `--test`: **169 Swift tests in 11 suites**, five isolated companion-model groups,
  three private-pasteboard drop groups and the independent SQLite lock/no-write
  integration check passed. The optional audio-device smoke was not enabled in this
  pass; prior evidence is recorded separately.
- The final signed Debug Xcode build succeeded for all three targets, followed by
  deep/strict signature verification. No project regeneration or identity changes.
- A temporary German launch showed all six tabs, translated Setup/Settings copy,
  exact `.env` and `.env.*` identifiers with German list wording, and localized
  accessible format descriptions. Search preserved the group-action scope. The
  attempted minimum-width resize was rejected by the UI service with
  `windowNotFoundAtPosition`; no minimum-width result is claimed. The app was quit
  and relaunched with normal language selection afterward.
- [Release measurements](release-pipeline-benchmark-2026-10-04.md) record separate
  processing and process-launch timings. They do not close the complete rendering,
  Finder scheduling, keyboard/VoiceOver or supported-OS performance gates.

The cross-tool memory lookup was attempted but its local service was unreachable;
these repository reports contain the durable evidence for this pass.
