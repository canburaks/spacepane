# Parallel expansion — 2026-10-04

This report distinguishes implemented parser/rendering behavior from installed Finder
coverage and release acceptance. Tested machine: Apple silicon, macOS 27.2; Xcode
27.0 / Swift 6.4 / SDK 27, Swift 6 strict concurrency, deployment target macOS 15.
A deployment target is not macOS 15 runtime evidence.

## Implemented scope

One shared catalog now contains 22 logical types, each independently controlled by
saved stable-ID policy before reader/factory invocation. Filename-specific `.env*`
and `package.json` classification precedes shared text/JSON UTTypes. Explicit imports
and static extension manifests are validated; no provider priority was changed.

| Type | Implemented presentation | Principal limits |
|---|---|---|
| Plain text | Selectable concealed UTF-8/UTF-16 source | Existing bounded reading; Finder may choose another provider |
| Source code | Semantic-role lexical colors, selection, gutter/find | Bounded lexical categories, not complete language grammars |
| JSON | Safe source and native outline | Exact numeric lexemes; duplicate-key flags; depth/node caps |
| JSON Lines | Safe source and record outline | UTF-8 without BOM; malformed records wholly concealed; no misleading record mapping after line collapse |
| YAML | Source and common configuration outline | Advanced aliases/tags/flow mappings/block forms use safe source; single-line arrays remain opaque scalars; uncertain escaped sensitive syntax may conceal more content |
| TOML | Source, assignment/table subset outline | Single-line arrays remain opaque scalars; array-of-table headers, inline tables and multiline structure use safe source |
| Environment | Concealed assignments and summary | No substitutions or shell execution |
| package.json | Source/outline and selected project fields | Scripts are inert strings; independent toggle from ordinary JSON |
| Markdown | Source and native rendered subset | Headings, emphasis, fences, lists/quotes, pipe tables; links are inert text; no image/resource fetch |
| Diff/patch | Highlighted additions/deletions source | Does not apply patches |
| XML | Source and outline | DTD/entity declarations rejected; no external entities or XSLT |
| Property lists | Normalized JSON source/outline | XML and preflighted binary plist; data becomes byte-count metadata; binary spelling is not original source |
| Strings | Concealed localization source | Strict bounded string-pair syntax |
| Strings dictionaries | Normalized plist source/outline | No localized-string execution |
| OPML | Safe XML source/outline | No feed fetching |
| SQLite | Localized schema and bounded row-page outline | Read-only private snapshot, rollback mode only; no live WAL; 200 rows total, 50 columns, 4 KiB cells; no interactive later-page loading yet |
| ZIP/ZIP64 | Central-directory metadata summary | No extraction/payload reads; split/encrypted/unsafe-path/malformed directories declined |
| TAR | Header/PAX/GNU-name listing | No extraction, bounded logical scan/read work; sparse entries unsupported; partial listing explicit |
| GZIP | Concealed supported text, TAR listing or binary metadata | Bounded compressed input/decode; concatenated members supported; CRC/truncation/bombs checked |
| XIP | XAR metadata and bounded PBZX/CPIO inner listing | Signature **not verified**; compressed chunk too large can yield partial/empty listing; bounded XZ dictionaries |
| Folder | Immediate-child names/type/file sizes | No recursion, symlink traversal or recursive-size claim; inaccessible/partial enumeration reported |
| MIDI | Metadata and explicit native play/pause/scrubber | SMF 0/1 PPQN only; format 2/SMPTE declined; <=20,000 channel events and one hour; no SysEx/text metadata/autoplay; seek restores controller/program/pitch state without replaying earlier notes |

The small internal C target uses the system SQLite library and public configuration APIs; no third-party parser package was added. Native audio uses the system DLS instrument and an installed bank located through platform library/bundle APIs, with a typed unavailable fallback.

Current standard request defaults are 1 MiB cumulative input reads, 2 MiB displayed
UTF-8, depth 64, 20,000 nodes/lines, 32 KiB per source line and a cooperative two-second
deadline. Family-specific decoded/entry/event/statement limits further restrict work;
these are implemented bounds, not the broader unmeasured performance targets in PLAN.
Rendered secondary views additionally cap text at 262,144 UTF-16 units and use source
fallback when structure/rendering exceeds their bounds.

Source and secondary presentations share concealed data. App-generated summary
labels are localized by known schema path, preserving user column names and source
values. Generic content-free thumbnails do not parse any source or instantiate audio.
The optional MIDI payload contains only validated channel events/timing.

## Customization and resources

Schema 5 adds semantic role color/bold/italic controls and up to 32 named appearance
profiles while retaining earlier schema fields and independent file-type choices.
Inert JSON theme transfer is capped at 16 KiB and rejects unknown/executable/policy
fields. Reset Appearance leaves format policy intact. The companion alone has
user-selected read/write permission to save an exported theme through the system
sheet; all source readers remain read-only and both extensions retain read-only
permissions. Theme data never contains previewed file content.

Fourteen chosen languages are recorded in `tools/localization/languages.json`:
English, Turkish, German, French, Simplified Chinese, Japanese, Hindi, Kurmanji Latin,
Russian, Indonesian, Bengali, Hausa, Portuguese and Spanish. All translations are
**implementation drafts pending native-speaker and installed-host review**. The
canonical catalogs, typed lookup, generated package resources and generated app/
extension metadata are separate from a claim of reviewed shipping localization.

## Evidence and remaining gates

The signed three-target Xcode build succeeded during integration. Direct opening of
synthetic files in the singleton companion showed:

- JSON Source concealing a synthetic password, then Outline visibly preserving
  `9007199254740993` exactly with the password still concealed.
- Markdown Source and Rendered with headings/emphasis/table text, an inert example
  URL, and the synthetic password concealed in both modes.
- The current single-window tab shell and attached file-open sheet remained intact.

AX inspection returned `AXError.failure` after switching native preview modes;
screenshots were usable. Selecting Customization again closed the native automation
pipe. A new `SkyComputerUseService-2026-10-04-115952.ips` crash appeared while the
companion process stayed alive. This is not evidence of a companion crash or a pass
for VoiceOver/customization interaction. Do not work around the inspection service
by changing app behavior without an independently reproduced app defect.

The modern `QLThumbnailGenerator` probe produced the generic image, but process
attribution exposed an obsolete Xcode DerivedData artifact with the old placeholder
thumbnail identifier. Therefore that result does **not** prove invocation of the
current configured thumbnail bundle. `script/probe_thumbnail.swift` makes public-API
probing repeatable; fresh output and separate process/bundle attribution are required.
No Quick Look caches, Finder process or extension-selection preferences were reset.

Earlier fresh JSON Finder preview with the companion stopped remains the only
recorded positive Finder-format observation. JSONL resolved to another vendor's
UTType and plain text used another provider on this machine. New parser/manifest
support does not extend that evidence automatically. Real Finder drag grants,
Finder thumbnail surfaces beyond the public generator, macOS 15/Intel, cold reinstall/update lifecycle,
Finder MIDI/audio and full multilingual/keyboard/VoiceOver checks remain open.

### Current thumbnail identity resolved

Rebuilding the obsolete artifact through the same Xcode project into its existing
DerivedData directory replaced the placeholder configuration. Read-only `pluginkit`
inspection then reported no old `invalid.example.previewprototype.thumbnail` entry.
A fresh synthetic JSON request through `QLThumbnailGenerator` started
`com.canburaksofyalioglu.filepreview.thumbnail` from the current `.build/xcode` bundle
(PID 23575); its signed bundle identifier was checked independently. The 256 × 256
output was the expected content-free page icon. A second fresh request with the
companion process stopped via SIGTERM also produced that icon. This establishes
current extension invocation through the modern generator and independence from the
running companion; it is not graceful app-quit, cold extension-start, every Finder
thumbnail surface or macOS 15 validation. The attempted native Command-Q step was
blocked by the inactive/crashed automation service, so it was not counted.

A reproducible cross-process SQLite lock check now holds the pending/reserved/shared
byte range from the Python runner, invokes the production reader in a separate Swift
executable, and expects unavailable content while locked and successful reads before/
after. Original bytes and directory entries are unchanged. This verifies that specific
local POSIX locking boundary; live-WAL and Finder sibling grants remain unsupported/
unverified respectively.

### Final automated verification

- `PREV_VALIDATE_AUDIO=1 ./script/build_and_run.sh --test`: **162 package tests in
  10 suites**, four isolated companion-model groups, three private-pasteboard drop
  groups, and the independent-process SQLite lock/no-write check passed.
- The opt-in audio check opened, started, silenced and closed the native DLS device
  without playing notes. It is a local unsandboxed runtime smoke test, not proof of
  audible or Finder-hosted playback. The unsupported sound-bank property found in
  the first smoke check was replaced by validated system-bundle resource lookup.
- `./script/build_and_run.sh --check`: three targets, 22 logical types, 259 keys and
  all 14 language resources/metadata dictionaries passed consistency checks.
- `./script/build_and_run.sh --check-compiler`: all three host source sets passed
  Swift 6 complete-concurrency type checking. The final navigation style was also
  compiled by the subsequent successful signed Xcode build.
- Debug `xcodebuild` with Xcode 27.0 succeeded for the app and both extensions.
  Signatures, sandbox entitlements, matching App Group metadata, all 14 metadata
  localizations and all 14 renderer localizations were checked in each built bundle.
  The companion alone has user-selected write access for explicit theme export.
- Corrected all three metadata build phases to declare every language output;
  script sandboxing remains enabled. The validator now catches catalog/output drift.
  The existing project generator already derives this list from the metadata catalog;
  the project was edited narrowly and was not regenerated.
- Added early plist normalization output accounting before full serialization:
  repeated binary references, escaped strings/keys and pretty-print overhead spend
  a cumulative conservative bound. A small repeated-reference fixture proves early
  rejection. Conservative Unicode accounting may decline before the actual UTF-8
  output reaches the cap. ZIP payload-offset and XZ padded-size overflow regressions
  also pass.

### Portuguese and Spanish launch checks

The signed app was launched separately with temporary process-only `AppleLanguages`
arguments for `pt` and `es`; no persistent system language preference was changed.
Both launches resolved translated Setup copy, toolbar labels, all six tab labels
and native menus. At the default 980 × 700 size, Portuguese initially pushed the
entire automatic tab control into toolbar overflow. Explicit native
[GroupedTabViewStyle](https://developer.apple.com/documentation/swiftui/groupedtabviewstyle)
(macOS 15+) keeps tabs in the content area. The rebuilt app visibly displayed all six
Portuguese and Spanish tabs with readable Setup copy. Native Command-Q ended these
companion runs; the app was then relaunched with normal language selection.

These checks cover two Setup layouts and tab discoverability only. They do not close
translation review, other screens/languages, VoiceOver, minimum-width layout, Finder
language selection or graceful-quit extension lifecycle gates. Native Customization
inspection remains blocked by the separate automation-service failure described above.
