# Competitor parity program: integration validation

Date: 2026-10-05. Host: Apple silicon (M5 Pro), macOS 27.2, Xcode 27.0, Swift 6.4. Branch `claude/competitor-feature-parity-bfbf59`, integrated from the shared base `20acae7` and twelve workstream branches. The program, its scope and its rejected items are in [decision 025](../decisions/025-competitor-parity-program.md). Each workstream has its own decision (013–024) and validation record; this record covers only the integrated tree.

## What was integrated

The catalog grew from 31 to 76 formats, and from 70 to 309 suffixes. 41 formats draw concealed content thumbnails, 31 keep the generic glyph and 4 leave the system thumbnail in place. IGES and STEP are still the only types off by default.

| Workstream | New formats or features | Decision | Validation |
|---|---|---|---|
| archives | RAR 4/5, 7z (own LZMA/LZMA2), bzip2, xz, JAR/WAR | [013](../decisions/013-archive-listings.md) | [archives](archives-2026-10-05.md) |
| listings | Folder depth and hidden items, Files and Tree modes, sortable and filterable tables | [014](../decisions/014-folder-and-listing-views.md) | [listings](listings-2026-10-05.md) |
| markup | Extended Markdown, Contents, LaTeX, BibTeX (four reference styles), AsciiDoc, reStructuredText, Org, Fountain | [015](../decisions/015-markup-documents.md) | [markup](markup-2026-10-05.md) |
| diagrams | Native Mermaid (flowchart, sequence, pie, state, class, ER) and draw.io | [016](../decisions/016-native-diagrams.md) | [diagrams](diagrams-2026-10-05.md) |
| packages | `.app`, IPA, APK/AAB, provisioning profiles, certificates, `.pkg`, `.dmg`, torrents | [017](../decisions/017-package-and-certificate-inspection.md) | [packages](packages-2026-10-05.md) |
| data | Parquet (with row samples), Avro, Arrow/Feather, NumPy, HAR, GeoJSON/GPX/KML/KMZ with Plot, SQLite schema grid | [018](../decisions/018-columnar-scientific-and-geo-data.md) | [data](data-2026-10-05.md) |
| code | 84 language profiles, 181 source suffixes, INI, logs, JSONC/JSON5, five caption formats, formatted minified JSON, partial reads of large line-oriented text | [019](../decisions/019-code-config-and-text-breadth.md) | [code](code-2026-10-05.md) |
| ebooks | EPUB, FictionBook, CBZ comics, MHTML, notebook figures, Pages view | [020](../decisions/020-ebooks-comics-and-images.md) | [ebooks](ebooks-2026-10-05.md) |
| interaction | Live reload, Go to Line, Copy All, outline filter and row copy, temporary zoom, provider badge | [021](../decisions/021-preview-interaction-and-live-reload.md) | [interaction](interaction-2026-10-05.md) |
| thumbnails | Concealed content thumbnails | [022](../decisions/022-content-thumbnails.md) | [thumbnails](thumbnails-2026-10-05.md) |
| settings | Preferences schema 6, eleven color schemes, behavior switches, Quick Look provider diagnostics | [023](../decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md) | [settings](settings-2026-10-05.md) |
| mesh | STL, OBJ, PLY, 3MF on the existing geometry viewer | [024](../decisions/024-mesh-formats.md) | [mesh](mesh-2026-10-05.md) |

## Integration changes made by the lead

These came from merging or from requests between workstreams; none is in a single workstream's record.

- **Mermaid fences in Markdown.** A Mermaid fence in rendered Markdown, including Markdown converted from ebooks, also opens in the Diagram mode, drawn from the fence's concealed source. Rendered stays first, and the selectable text is unchanged, so copy and find still see exactly the safe text.
- **Markup Source highlighting.** Source mode for the six markup formats uses the markup family's lexers.
- **Container scan budget.** ZIP, TAR, GZIP, XIP, RAR, 7z, bzip2, xz, IPA, APK, installer packages, disk images, comics and EPUB read under `PreviewBudget.containerScan` (16 MiB of reads, 5 s). Before, every member and header read counted against the 1 MiB text budget. Output, node and line limits are unchanged, and an explicit request budget (thumbnails) still wins.
- **Icons are not pages.** The Pages mode uses covers, pages and figures only; application icons have their own Icon mode.
- **Color schemes reach 3D.** The CAD and mesh viewport follows the chosen color schemes.
- **Folder settings reload.** The companion reloads an open preview when folder depth or hidden items change.
- **System 3D thumbnails stay.** STL, OBJ and PLY do not register for thumbnails, so macOS keeps its own 3D thumbnails for them.
- **Groups from the catalog.** Provisioning profiles and certificates are in the Structured group. The companion check now derives that group's members from the catalog.
- **Labels and escaping.** The SQLite schema grid's summary fields have localized labels. Notebook labels escape the new Markdown math and strikethrough markers.
- **Test reconciliation.** Several tests asserted one family's behavior that another family deliberately changed:
  - Markdown now opens in Rendered and draws content thumbnails.
  - Archive listings open in Files.
  - Oversized plain text now draws its leading lines as a thumbnail.
  - New formats join JSON's provider overlap.
  - Two test helper names collided.

  Each expectation was updated to the integrated behavior, and the change is described in its commit.
- **Wall-clock tests run alone.** Six tests assert that a timer beats blocked or cancelled work. Each passes reliably by itself, but in the 2,080-test parallel run, CPU-bound tests from other suites held the shared thread pool past those deadlines. `--test` now runs them in a separate serial pass after the parallel run.
- **Shared tooling.**
  - `script/sync_manifests.py` derives the Info.plist type lists from the catalog and runs in `--check`.
  - `tools/add_localizations.py` adds keys in all 14 languages at once.
  - `tools/test_localization.py` no longer pins the exact set of formatted keys.
  - `--check-compiler` uses `find` instead of ripgrep.

## Commands and results

All commands were run from the worktree root on the final integrated tree.

| Command | Result |
|---|---|
| `./script/build_and_run.sh --check` | Passed. 101 preview and 97 thumbnail content types, 53 imported declarations; project and target graph; 817 localization keys in 14 locales; 13 localization-tool tests; 76 appearance samples; app icon. |
| `./script/build_and_run.sh --check-compiler` | Passed. The package built; the companion, both extensions and the CAD service typechecked with Swift 6 complete checking. |
| `./script/build_and_run.sh --test` | Passed. 2,080 Swift tests in 205 suites (parallel) plus 6 wall-clock tests (serial); 8 settings, 11 companion, 3 file-drop and 5 live-reload model checks; the cross-process SQLite lock and no-write check; 5 appearance interaction groups; 648 adversarial cases across 81 fixture formats with no source change. |
| `xcodebuild -target PrevThumbnailExtension CODE_SIGNING_ALLOWED=NO` | Build succeeded. The binary links the system `libbz2`, `libsqlite3`, Security, ImageIO and CoreText. |
| `node web/scripts/sync-app-data.mjs --check`, `node web/scripts/check-locales.mjs`, `python3 Website/tools/generate_formats.py --check` | Passed after regenerating the website's format data from the merged catalog. |

The suite grew from 464 tests (39 suites) at the base to 2,086 tests. The adversarial corpus grew from 248 cases across 31 formats to 648 cases.

## Not verified

- **Finder.** No Finder-hosted preview or thumbnail was observed for any new format, mode or feature. Which provider Finder picks is unknown for every new type, especially those macOS or other apps also preview (STL/OBJ/PLY, EPUB, certificates, `.app`).
- **Signed builds.** The signed app, the preview extension and the CAD service were not rebuilt with Xcode in this worktree, because that needs the OCCT kernel. Only the thumbnail extension was built, unsigned. Security calls, provider scanning and live reload under the App Sandbox are unverified.
- **Accessibility and languages.** VoiceOver, keyboard focus in Quick Look, translated layout and native-speaker review were not checked. All new strings are drafts.
- **Platforms and performance.** No Release performance was measured for the integrated pipeline. macOS 15 and Intel were not tested.
- **Website.** The website's TypeScript, lint, build and pixel comparison were not run, because `node_modules` is not installed in this worktree. Only its data and locale checks ran.

## Known gaps carried forward

- **Notebook figures.** Figures above about 24 KiB still fail in notebooks, which use the text input path.
- **Large whole-file formats.** HAR, GeoJSON, GPX, KML and torrents over 1 MiB fail as too large.
- **Mermaid.** Only the first parseable Mermaid fence in a Markdown document opens in Diagram.
- **Mesh units.** The mesh viewer labels all dimensions in millimetres, which is an assumption for STL, OBJ and PLY.
- **Table mode on reload.** Live reload does not preserve the scroll position or selection in table mode.

## Integration with the Safety Lens (2026-10-06)

The branch merged `master` after PR #5 (Safety Lens, CSV/TSV Profile, CAD measurements; [decision 012](../decisions/012-safety-findings.md)). Both changed the same core files. The resolution keeps both features:

- **Shared contracts.** Parsed documents and presentations carry master's `findings` as well as this program's images, source-language hint, partial-read size and reformat flag. The pipeline also runs master's hidden-content scan and sync-folder findings.
- **Listing entries.** One `ContainerEntry` combines master's stored size, Unix mode, link target and encryption with this program's modification date and folder item count. Its summary writes the optional fields and master's per-entry `risks`.
- **One ZIP parser.** Master's ZIP listing re-parsed the central directory itself; it now reads through the shared `ZIPArchiveReader`. The reader gained the host and external attributes master needs, and a listing path policy.
- **Unsafe names.** Master lists unsafe names and flags them as risks instead of failing. RAR and 7z now do the same and are risk-assessed, along with bzip2 and xz TAR payloads, so an unsafe name is never listed silently. Formats that read members by name keep the strict `safeArchivePath`.
- **Renderer.** `NativePreviewView` keeps master's findings banner, Invisibles markers and Profile tables alongside this program's mode views, accessory bar and notices. Profile is offered only where a profile was prepared (CSV/TSV), not for every family's table. The palette keeps the color schemes and adds master's invisible-marker color.
- **Test expectations.** Tests on each side were reconciled with the combined behavior:
  - Archives open in Files.
  - Markdown opens in Rendered.
  - Unsafe archive names are listed and flagged.
  - An oversized listing becomes a flagged partial listing instead of failing.

  Two test helpers named `RecordingSource` were renamed apart.
- **Decision numbers.** This program's record moved from 012 to [025](../decisions/025-competitor-parity-program.md), because master's Safety Lens record took 012 first.

Validation after the merge, on the same host:
- `--check` passed: 924 localization keys in 14 locales, 76 samples.
- `--check-compiler` passed.
- `--test` passed: 2,448 parallel and 6 serial Swift tests, every integration check, and 648 adversarial cases with no source changed.
