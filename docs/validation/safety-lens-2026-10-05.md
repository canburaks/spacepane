# Safety Lens and insight features — validation, 2026-10-05

Decision: [012 — safety findings](../decisions/012-safety-findings.md). Plan: [Safety Lens and insight features](../../PLAN.md#safety-lens-and-insight-features).

Environment: Apple silicon (M5 Pro), macOS 27.2, Xcode 27.0, Swift 6.4, SwiftPM native build. Dates use Europe/Istanbul. This record covers **package, model and compiler evidence only**. Nothing here was observed in a signed companion or in Finder; see "Not verified".

## How it was built

The lead defined the shared contract first:

- typed findings;
- one definition of a logical line;
- the banner and Copy Concealed Text;
- the hidden-character classifier;
- every string, with English text and translator context.

Then three waves of parallel specialist agents worked in isolated worktrees with disjoint file ownership. The lead reviewed and integrated each patch and ran the gates. A separate pass translated the strings.

| Wave | Feature | Owner area |
|---|---|---|
| 1 | Notebook health | `PreviewFormats/Notebooks` |
| 1 | Archive risk report | `PreviewFormats/Containers`, `SafeSchemaLabels` |
| 1 | Secret inventory, sync-folder warning | `DefaultPrivacyFilter`, `SyncFolderLocation`, pipeline wiring |
| 2 | Hidden-content scanner | `PreviewCore` scanner, mixed-script and Markdown passes, `HiddenCharacters` |
| 2 | Invisibles mode | `SafeInvisibleText`, preview modes, native view |
| 3 | CSV/TSV Profile mode | `SafeDataProfile*`, table view |
| 3 | CAD measurements and header facts | `PreviewCADFormats`, geometry contract, geometry view |

## Automated checks

| Check | Result |
|---|---|
| `./script/build_and_run.sh --test` | **832 package tests in 67 suites** passed (baseline at the start: 464 in 39). Also passed: 11 companion-model checks, 3 file-drop checks, the SQLite cross-process lock and no-write check, 5 appearance-interaction groups, and 248 adversarial corpus cases with the same outcome distribution as before. |
| `./script/build_and_run.sh --check` | 31 catalog formats and the project graph; **466 localization keys in 14 locales**; 13 localization-tool tests; 31 appearance samples; the app icon. |
| `./script/build_and_run.sh --check-compiler` | The companion, both extensions and the CAD import service typecheck. The script needs `rg`, which this shell lacked, so a scratch shim that lists files was used. |
| CAD end to end | Run with a real prebuilt OCCT worker (an APFS clone of the main checkout's ignored `.build/cad`). See the measurements below. |

One pre-existing test, `JSONLinesCooperativeCancellationStopsActiveLargeSource`, failed once under full-suite load. It then passed 5 isolated runs and two complete reruns. It races a 2 ms sleep against parsing and touches no changed code. A follow-up task to make it deterministic was suggested.

## Feature evidence

**Notebook health**
- Out-of-order execution with the exact sequence shown, gaps, cells that never ran, saved errors and the reproducibility hint.
- Cell positions match the rendered view.
- Unusable `execution_count` values never fail a notebook.
- Findings hold integers only; a privacy test seeds markers in every text field.
- The built-in notebook appearance sample produces no findings.

**Archive risks**
- Every rule has positive and negative cases.
- Clean archives produce byte-identical summaries.
- `../` paths and encrypted ZIP members are now listed and flagged. NUL and control-character names still fail, and so does central-directory encryption.
- Risk annotations that alone would exceed the summary budget are dropped, keeping the findings, so archives that listed before still list.

**Secret inventory**
- Concealment output is unchanged; the equivalence and reference suites pass as before.
- Counts per kind sum to the redaction count, checked by a randomized 500-document test.
- Lines match the gutter after multiline concealment.
- Release timing on 4–4.6 MB texts shows no measurable change (for example 562 → 563 ms with no secrets, and 1,712 → 1,718 ms with 16,800 concealments).

**Sync-folder warning**
- Path components only, with no file access.
- Covered: iCloud Drive, `CloudStorage` providers and legacy Dropbox. Lookalike names, remote hosts and relative URLs are rejected.
- A folder name holding an e-mail address never appears in the output.

**Hidden content**
- The classifier is checked against an independent list of hidden ranges across every Unicode scalar; planes 3–13 are sampled.
- Expected text is not flagged: emoji ZWJ sequences, Hindi, Bengali and Persian joiners, subdivision flags, ideographic variation sequences, and direction marks in right-to-left lines.
- An Arabic letter mark no longer hides itself.
- Text encoded in tags is decoded and concealed: AKIA keys, `ghp_` tokens and `password=`.
- Mixed-script negatives such as `10μs`, `Δt`, Russian and Greek prose, and `naïve` are not flagged.
- Markdown fences, inline code and link-reference comments are handled.
- AI-agent file escalation is tested.
- The scan runs only on the file's own text; archive summaries and disabled types are excluded.
- Release cost per MiB, in isolation:

| Text | Scan time | Share of the pipeline |
|---|---|---|
| ASCII | 0.03 ms | negligible |
| Mixed Russian and emoji | 1.5 ms | about 5.5% |
| About 80,000 hidden runs | 7.4 ms | about 10% |
| Markdown pass | 0.5–0.9 ms | — |

**Invisibles mode**
- Markers for every class, and one count-only marker per tag run.
- Identical logical lines across CRLF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR.
- Source stays byte-for-byte the concealed text, and copy there is exact; tested with private pasteboards.
- Marker contrast is at least 7.4:1 in light, dark and increased-contrast palettes, and an underline marks them when color is off.
- The mode is unavailable above its bounds, never truncated.

**Invisible characters inside key names**
- ZWSP, ZWJ, soft hyphen, variation selectors, tags, a leading invisible character, and word and grapheme joiners inside `password` or `api_key` are concealed.
- Covered in plain text, `.env`, CSV and JSON, and the hidden character is still reported.
- XML property lists are now scanned; binary property lists are not.

**CSV/TSV Profile**
- Types, missing values, distinct counts, exact extremes, mean, common values, the sparkline and its spoken description, quality notes, sampling, ragged rows and duplicate names are all tested.
- **Concealed columns:** the header policy, a token in any cell and a token followed by a combining mark are covered. Tests assert that no value, count or statistic of a concealed column appears in cells, descriptions, the status line or copied text.
- Release: 65–71 ms to profile a 20,000 × 64 table (10,000 rows profiled), against a 100 ms target.

**CAD measurements** (real worker, unmodified OCCT tessellation)

| Fixture | Area, mm² (analytic) | Volume, mm³ (analytic) |
|---|---|---|
| Box, STEP and IGES | 2,200 (2,200) | 6,000 (6,000) |
| Cylinder, STEP | 2,507.7 (2,513.3) | 9,377.0 (9,424.8) |
| Sphere, STEP | 1,250.2 (1,256.6) | 4,149.6 (4,188.8) |
| Cone, STEP | 1,303.0 (1,307.7) | 3,110.0 (3,141.6) |
| Cylinder and cone, IGES | reported | unavailable: independently tessellated faces leave cracks |

- Curved parts read slightly low because of chord error.
- The practical worst-case mesh (1.14 M vertices) measures in 0.11 s with +44.7 MiB of extra peak memory.
- Headers:
  - Read from both fixtures: STEP AP214 and IGES 5.3, created with Open CASCADE 7.9.
  - Hostile header cases are covered: truncation at every byte, deep nesting, a 12 MiB file, BOMs, custom IGES delimiters.
  - Author and organization never appear.

## Not verified

- Signed companion and Finder-hosted rendering: the banner, Copy Concealed Text from the Quick Look extension, the Invisibles and Profile modes, and the CAD lines.
- VoiceOver, Full Keyboard Access, large text and increased contrast in a running app. Accessibility values were checked only through AppKit APIs.
- Translations: all 107 new strings are drafts. The translation agents flagged Kurmanji and Hausa as low confidence and several Hindi, Bengali, Russian and Japanese term choices for review.
- Renderer and Finder first-content timing with findings, and macOS 15 or Intel.
- `script/build_cad_worker.py --test` in a fresh worktree: the cloned kernel cache holds absolute CMake paths, so the prebuilt worker was used directly.

## Known limits

- **Markdown comments:** 4-space indented code, code spans that cross lines and HTML blocks are not modelled.
- **Mixed scripts:** Greek-letter variables beside Latin letters (`ρmax`) are flagged as a caution. Whole-script confusables are not detected.
- **Sync warning:** iCloud "Desktop & Documents" and other File Provider locations are not detected.
- **Profile:**
  - Only the first rows are sampled.
  - Comma-grouped numbers are text.
  - Minimum and maximum for slash and dotted date formats are not shown.
- **Archives:** link checks are one level deep, and XIP has no per-entry stored size or encryption flag.
- **CAD:** values are approximations of the displayed tessellation, not certified engineering data.
