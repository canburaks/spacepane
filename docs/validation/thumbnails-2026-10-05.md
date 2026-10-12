# Content thumbnails validation — 2026-10-05

Scope: [Decision 022](../decisions/022-content-thumbnails.md). This record separates what was run from what was not. **Real Finder thumbnail invocation, thumbnail-cache behavior, signed-host behavior (App Group snapshot read, sandboxed file access, embedded resource bundles) and visual review of thumbnails in Finder were not verified.** Nothing here shows that Quick Look selects this provider for any type, or that a thumbnail on screen came from this extension.

Host: Apple M5 Pro, macOS 27.2, Xcode with the macOS 27.0 SDK, Swift 6.4, `-swift-version 6 -strict-concurrency=complete -default-isolation nonisolated`, deployment target 15.0 (typechecked, not run on macOS 15). Intel and macOS 15 runtime were not exercised.

## Commands and results

Run from the worktree root on branch `parity/thumbnails`.

| Command | Result |
|---|---|
| `./script/build_and_run.sh --check` | Passed: manifests unchanged (37 preview and 36 thumbnail content types, 16 imported declarations), `validate_project.py` (4 targets, 2 embedded extensions, 31 catalog formats), localization references (365 keys, 14 locales), 13 localization tests, appearance samples for 31 formats, app icon. |
| `./script/build_and_run.sh --check-compiler` | Passed: package built; `Apps/PrevApp`, `Extensions/PrevPreviewExtension`, `Extensions/PrevThumbnailExtension` and `Native/CADImportService` typechecked. The thumbnail extension now imports `PreviewFormats`, `PreviewPreferences`, `PreviewRenderers` and `PreviewThumbnails`. |
| `./script/build_and_run.sh --test` | Passed: 589 Swift Testing tests in 55 suites (the thumbnail target is 125 tests in 16 suites; the earlier suites are unchanged apart from one expectation, see below), plus the companion model checks (11), file-drop checks (3), SQLite snapshot checks, appearance interaction groups (5) and the 248-case adversarial corpus. |
| `swift test --filter PreviewThumbnailsTests` | 125 tests in 16 suites passed. |

No Xcode build, signed launch, `qlmanage`, `pluginkit`, Finder or Quick Look cache action was run.

The only existing expectation changed: `JSONLinesCatalogTests` asserted a `generic` thumbnail policy for JSON Lines; it now asserts `content`.

## Project files

`script/generate_project.py` and `script/validate_project.py` were updated, and `Prev.xcodeproj/project.pbxproj` was changed by a **surgical edit** instead of a regeneration. The checked-in project was already not the generator's byte-for-byte output (it uses Xcode's serialization, object version 71, and hand-assigned identifiers for the CAD service), so regenerating rewrote about 1,600 lines and changed the CAD target's identifiers. The edit adds exactly three package product dependencies and their three framework build files to the thumbnail target (`PreviewCore`, `PreviewFormats`, `PreviewThumbnails`) using the identifiers the generator derives for them (24 added lines, `plutil -lint` OK). `validate_project.py` now requires the thumbnail target to link exactly contracts, core, formats, preferences, renderers and thumbnails, and never the CAD formats product, and accepts `PreviewThumbnails` as an exported product.

## What the tests cover

Everything below runs in SwiftPM with synthetic inputs, no Quick Look host and no App Group.

- **Policy.** Missing or corrupt settings, the content-thumbnail switch, unsupported types, user-disabled types, every catalog policy (a content format draws, every other policy stays generic, geometry presentations never draw), the exact content and generic lists of the decision, and environment, CAD and extension-free files. Counting factories and a counting reader prove that a disabled type, a generic-policy format (ZIP, TAR, GZIP, XIP, environment, MIDI, IGES, STEP, folder) and a switched-off request construct no adapter and read no bytes.
- **Layout.** Geometry validation (non-finite, non-positive, over 4,096 pixels), page proportions equal to the glyph's, metrics bounds at 16 to 1,024 points at 1x and 2x, cell widths for Latin, CJK, emoji and combining marks, line splitting on every separator, tab expansion, wrapping, row and column caps, blank-line collapse, indentation caps, Unicode and right-to-left text, and early cut-off of 5 MB inputs.
- **Shapes.** Lexer tones and reassembly of every line; Markdown heading and body, front matter, fences, rules, links and images, task lists, quotes, row cost never above the page; JSON outline for minified, nested, array-of-object, escaped, long and malformed input, early stop on a 200,000-element array; CSV and TSV grids with quotes, ragged rows, column and row caps, clipping and the plain-text tab heuristic; SQLite first-page grid with null and blob cells; notebook cells with outputs excluded; shape mismatches that stay generic.
- **Pictures.** Aspect-fit math, decode at the canvas pixel bound, no upscaling, declared and real dimension limits, encoded size limit, type allow-list (an SVG and random bytes are refused), a truncated image, role preference and the three-attempt bound.
- **Pipeline, end to end.** Twenty-one fixtures, one per catalog content format, through the real adapters, privacy filter and bounded reader, asserting shape and visible text, and that neither the file name nor its directory is drawn. A real SQLite file. Files over the 256 KiB budget, binary and malformed files, a whitespace-only file and a missing file fall back. A spinning adapter hits the 50 ms pipeline deadline; a blocking reader is cut off by the hard timeout in well under a second; cancellation answers promptly; 24 concurrent requests all complete. Picture presentations: cover over figure, undecodable and oversized pictures falling back to the excerpt.
- **Privacy.** Ten synthetic-secret files (YAML, TOML, JSON, minified JSON, plain text, source, CSV, TSV, Markdown, notebook) are withheld whole by default, including their pictures; with the withholding limit lifted to its maximum, `synthetic-secret-value` is absent from every drawn string.
- **Rendering.** Core Graphics bitmaps: the glyph (transparent margins, light sheet, rules), text, Markdown, table and picture shapes (cover, page, icon, figure) draw inside their sheet and nothing outside it; colors appear only when the style allows them; every shape draws at 16, 48, 64, 128 and 512 points at 1x and 2x without trapping; non-square canvases center the sheet; eight concurrent draws off the main thread produce identical bitmaps.
- **Concurrency.** The race helper delivers one result under timer, worker, cancellation and 200 interleaved tasks, and a blocked worker does not delay the result.
- **Preferences source.** No container, missing document (defaults), saved choices, corrupt, oversized, newer-schema and directory-in-place-of-file documents.

## Timings

End to end through `ContentThumbnailService` with the extension's default limits (300 ms pipeline deadline, one second hard timeout), 256 point thumbnail at 2x, five requests per file, median and maximum. Debug is the default `swift test`; Release is `THUMBNAIL_TIMINGS=1 swift test -c release -Xswiftc -enable-testing --filter ThumbnailTimingTests` on the host above. These include file read, bounded decoding, concealment, parsing and model building for the page; they exclude Quick Look's own overhead and the final bitmap drawing.

| Input | Debug median / max | Release median / max |
|---|---|---|
| 250 KB plain text | 62 / 67 ms | 29 / 33 ms |
| 250 KB source | 115 / 119 ms | 44 / 46 ms |
| 250 KB pretty JSON (over 20,000 nodes) | 118 / 120 ms | 31 / 32 ms |
| 250 KB minified JSON (one line) | 114 / 130 ms | 33 / 37 ms |
| 250 KB CSV | 162 / 165 ms | 61 / 66 ms |
| 250 KB Markdown | 126 / 131 ms | 44 / 45 ms |
| SQLite, about 1 MB | 49 / 52 ms | 45 / 53 ms |

Every case completes inside the 300 ms deadline even in Debug on this machine. These are single-host numbers; a slower or loaded machine, a cold start, a network volume or a larger SQLite file can exceed the deadline, in which case the result is the glyph. Cold extension launch and memory in the extension process were not measured.

## Visual review

Bitmaps drawn by the tests were reviewed as PNGs written to a scratch directory (set `THUMBNAIL_SAMPLE_DIR` to reproduce): glyph, source excerpt at 64, 128 and 256 points, Markdown, table, Unicode and mixed-direction text, cover, icon and figure. They are legible and stay inside the sheet. This is not a Finder review: Finder composes thumbnails with its own badge, shadow and scaling, and the drawing context's point scale inside Quick Look's reply was assumed to match the original glyph code, not measured.

## Not verified

- That Finder or any Quick Look client invokes this extension for a given file type, and which provider wins when another thumbnail provider is installed.
- The App Group snapshot read in the sandboxed extension, `FormatCatalog.standard` resource loading from the extension bundle (the package resource bundle must be embedded by Xcode), and `HostedConfiguration` in that process. The extension was typechecked, not linked or run.
- Read access to files by the extension for the requested URL, including SQLite sidecar checks (`lstat` of sibling `-wal`, `-shm`, `-journal` paths in the sandbox may decline) and iCloud placeholders.
- Thumbnail cache behavior after the switch, a file-type choice or the file changes, and the OS's own timeout for a thumbnail provider.
- Extension memory and cold-start cost; ImageIO decode memory at the 16 megapixel limit.
- macOS 15 and Intel runtime, VoiceOver (thumbnails carry no accessibility text), right-to-left and Indic shaping in Finder, and localization (thumbnails draw no app-authored text, so none was needed).
- The settings page switch for `showsContentThumbnails`: the snapshot carries the field with default `true`, but the settings workstream owns persisting and presenting it. Until it lands, every installation uses the default.
- Pictures from real adapters: no covers, icons, pages or figures exist yet from other workstreams; the picture path was exercised with synthetic adapters.
