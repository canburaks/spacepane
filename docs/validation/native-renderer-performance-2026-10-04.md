# Native renderer performance continuation — 2026-10-04

This pass addresses the native AppKit costs identified in the
[original measurements](security-performance-2026-10-04.md). It keeps the existing
file adapters, safe presentation boundary, preferences schema, format policy and
single-window product behavior. Performance evidence here is isolated offscreen
rendering; Finder scheduling and visible first-content latency remain separate.

## Diagnosis and implementation

A four-second `sample` of the original optimized worker processing synthetic JSON
Lines showed work in repeated outline root expansion, Swift object equality during
AppKit item lookup, and layout/styling of hidden source text. Stack sample counts
overlap and are not an additive allocation or CPU-percentage breakdown. The ignored
profile is `.build/render-profile-o_yggy0g/sample.txt`.

- Outline items now have native `NSObject` identity. Root expansion retains the
  previous nonrecursive semantics and batches updates. A proposed nil-root bulk
  expansion was rejected because characterization tests showed missing expansion.
- Outline fields are reused by column identifier. Reconfiguration replaces safe
  text, attributes, tooltips and accessibility help, clearing obsolete duplicate-key
  metadata. Appearance changes update all available rows, including prefetched rows;
  newly requested cells use the current style.
- One request-local styling pass resolves the twelve semantic role dictionaries.
  It contains no source content and is replaced with the current font, palette and
  traits. It is shared by selectable source text and outline cells.
- Summary-first previews defer hidden text materialization. Source-to-outline mode
  changes retain already-safe source selection but skip hidden text styling/layout.
  A replacement generation immediately clears old hidden text and selection.
  Returning to Source applies current appearance without rereading a file.
- Full attributed-storage styling and typing attributes replace redundant whole-text
  font/color setters. Logical line gutters, selection, wrapping, find and safe copy
  continue using their established paths.

Review also reproduced an existing Unicode invalidation defect: Swift's canonical
String equality let a newly supplied decomposed spelling retain the previous composed
characters in Source and Outline. A three-surface test failed before the correction.
Source storage and renderer-local model comparisons now use exact UTF-16/UTF-8 units;
the public presentation contract and file decoding are unchanged. The same regression
passes for visible Source replacement, hidden Outline-to-Source and outline key/value
replacement. These comparisons do not normalize or translate file contents.

## Correctness verification

The final `./script/build_and_run.sh --test` passed 196 Swift tests in 16 suites,
five companion-model groups, five appearance-interaction groups, three private
pasteboard drop groups, the independent-process SQLite lock/no-source-write check
and the 176-case all-format adversarial corpus. The opt-in audio hardware test is
not evidence of audible playback in this run.

New tests cover:

- [Deferred source styling](../../Packages/PreviewCore/Tests/PreviewRenderersTests/DeferredSourceStylingTests.swift):
  no hidden restyle, current appearance on return, safe selection retention,
  summary-first materialization and clearing replaced/disabled content.
- [Outline behavior](../../Packages/PreviewCore/Tests/PreviewRenderersTests/NativeOutlinePerformanceRegressionTests.swift):
  every root expanded once, nested expansion and selection retained, actual cell
  reuse with stale accessibility metadata cleared, and cached/scrolled row restyling.
- [Style dictionaries](../../Packages/PreviewCore/Tests/PreviewRenderersTests/NativeTextStylePassTests.swift):
  equivalence with prior attributes across twelve semantic roles, typography,
  traits, themes and fallback fonts; current-pass refresh and safe Unicode text.
- [Exact Unicode replacement](../../Packages/PreviewCore/Tests/PreviewRenderersTests/NativeSourceUnicodeRegressionTests.swift):
  three surfaces compare code units rather than equality that would mask the defect.

Existing appearance, line-number, safe Markdown/link, selection and interaction
checks also pass. `--check` passed project/catalog validation, 259 localization
keys across 14 locales, and 13 localization-tool tests. No user preferences, source
documents, system Quick Look caches or extension settings were changed.

## Measurement method

The benchmark worker and runner are unchanged. Each of seven fixtures uses ten
new-process samples and fifty warm samples after one untallied warm-up: 420 measured
sequences in total. Every sample creates a fresh 800 × 600 native renderer with line
numbers and forces AppKit layout plus bitmap drawing. Secondary mode, appearance
restyling and the final viewport are timed separately. Source integrity and concealed
text assertions remain enabled. Cold process startup is distinct from a cold disk.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 script/benchmark_release_native_renderer.py --build-only
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 script/benchmark_release_native_renderer.py --skip-build \
  --output .build/performance/release-native-renderer-optimized-2026-10-04.json
```

The original raw artifact is preserved at
`.build/performance/release-native-renderer-results.json`, SHA-256
`a86400050fdf998df18b3665d081cb80db4fc25d77374e9476795ebe7183d1ae`.
Its recorded start was `2026-10-04T10:42:48.906150Z`. Both runs use this Apple M5 Pro
MacBook Pro with 48 GiB, macOS 27.2 (26B5091g), Xcode 27.0 (27A266a), Swift 6.4 and
macOS SDK 27.0. The deployment target remains macOS 15. Other local processes,
thermal behavior and power state are uncontrolled.

The completed optimized run began at `2026-10-04T11:16:22.700185Z`. Builds and tests
were stopped during all measured sequences. Its raw artifact has SHA-256
`24d052782e7ba52b334fc2c900c9992b5712cee36e3378ac55e724e1c1c14a1a`.
All source integrity checks and concealed native-text assertions passed. Raw files
are local ignored evidence; these tables preserve the results in the repository.

### Timing results

Values are milliseconds, nearest-rank p95. Warm samples retain a process but each
constructs a fresh view. Initial drawing excludes the separately timed pipeline and
view construction. ZIP/SQLite initially display Summary; JSON/JSON Lines/Markdown
secondary modes are Outline/Records/Rendered. Restyling occurs in that selected mode.

| Case | Warm initial before → after | Warm secondary before → after | Warm restyle before → after | New-process initial after | Warm final viewport after |
|---|---:|---:|---:|---:|---:|
| Text | 171.161 → 160.333 | — | 75.952 → 61.260 | 134.051 | 4.220 |
| JSON | 494.113 → 380.692 | 193.784 → 15.956 | 173.412 → 7.820 | 318.818 | 5.587 |
| JSON Lines | 308.395 → 300.315 | 563.839 → 70.755 | 182.591 → 12.579 | 254.967 | 14.767 |
| ZIP | 74.360 → 16.237 | — | 36.999 → 6.103 | 36.739 | 4.381 |
| SQLite | 176.106 → 28.603 | — | 93.141 → 9.504 | 46.227 | 4.863 |
| Source code | 224.773 → 198.117 | — | 123.590 → 86.716 | 186.325 | 3.279 |
| Markdown | 78.820 → 86.817 | 37.527 → 37.481 | 37.717 → 32.783 | 89.168 | 4.909 |

The strongest observed gains are mode switching and outline restyling, consistent
with removing hidden source work and native outline lookup/cell costs. JSON Lines
Records switching fell about 87%; JSON Outline switching about 92%. Initial JSON
and source-code median times changed much less than their p95: JSON 365.307 →
359.847 ms, source 194.475 → 192.113 ms. Markdown initial p95 increased about 10%
while its median was nearly unchanged (73.995 → 73.667 ms). These sequential local
runs do not establish statistical significance or universal improvements.

Do not equate the 198 ms source drawing figure with the whole useful-content goal.
Summing pipeline, construction and initial drawing **within each raw sample**, then
computing p95, gives the following broader local metric. It still excludes process
startup/host scheduling and on-screen presentation.

| Case | New-process pipeline + construction + initial p95 | Warm pipeline + construction + initial p95 |
|---|---:|---:|
| Text | 206.774 | 215.592 |
| JSON | 392.893 | 434.096 |
| JSON Lines | 344.017 | 364.804 |
| ZIP | 70.698 | 32.190 |
| SQLite | 121.380 | 81.592 |
| Source code | 255.968 | 249.826 |
| Markdown | 120.040 | 105.891 |

The ≤200 ms warm useful-content gate remains open for text, JSON, JSON Lines and
source code in this broader local measurement. A next focused profile should separate
initial full-document TextKit layout, safe secondary-model construction and attributed
storage application. Any further change must preserve exact text, copy/find, wrapping,
line numbers, selection and accessible last-line navigation; reducing fixture size,
removing drawing stages or suppressing content is not a performance fix.

Maximum whole-process peak RSS in the optimized run was 160.781 MiB (JSON), compared
with 171.359 MiB in the baseline. Per-case peaks were Text 116.375, JSON Lines
152.141, ZIP 72.453, SQLite 75.656, Source 131.391 and Markdown 90.984 MiB. This
includes framework initialization, initialized caches, safe models, source/outline
stages and drawing allocations across the process lifetime. It is not a measured
incremental memory cost for a single hosted preview, so the memory gate stays open.

## Signed build and live smoke

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./script/build_and_run.sh --verify` built, strictly verified and launched the signed
Debug companion plus both extensions. The final bundle localization probe passed
33 explicit language cases in all three signed artifacts, 259 keys each, without
changing resources. This does not establish effective Finder language selection.

The companion's existing Open sheet loaded an owned 64-record JSON Lines fixture.
Observed Source → Records → Source in the same `companion.main` window, initially
expanded record roots, a manually expanded nested object, concealed password,
Turkish/Japanese/decomposed-accent/emoji text, and keyboard scrolling to Record 64.
Returning to Source retained the complete concealed text. Appearance restyling is
covered by native tests; the known Customization automation-service issue was not
repeated or claimed fixed.

The already registered development artifact was rebuilt from the same final source
at `~/Library/Developer/Xcode/DerivedData/Prev-bosallybkatpeoahvdcemrlwmrbk/Build/Products/Debug/Prev.app`.
The companion was quit through its native command. A newly generated JSON fixture
then showed this app's Source → Outline → Source in Finder's Space-bar panel,
including manual nested/array disclosure and concealed values. Process 53301 started
at 14:20:54 Europe/Istanbul and ran the preview executable inside that exact registered
bundle; no `Prev` companion process remained. Its host app and both extensions passed
strict signature verification. Both owned smoke-fixture SHA-256 hashes were unchanged.

Mode clicks sometimes returned transient `AXError.failure`; a fresh native state and
screenshot confirmed that the requested mode had changed. This observation is not a
VoiceOver audit or a proof that every accessibility client behaves identically. No
provider preferences, extension toggles, user settings or Quick Look caches changed.

## Remaining acceptance boundaries

This work does not establish effective Finder language selection, human translation
review, VoiceOver behavior, real sandboxed Finder drag grants, audible MIDI quality,
per-format thumbnail coverage or macOS 15/Intel runtime behavior. Absolute process
RSS includes framework initialization and multiple rendering stages; it cannot be
compared directly with the plan's incremental-preview memory target.
