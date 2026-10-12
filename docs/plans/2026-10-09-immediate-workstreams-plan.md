# Immediate workstreams — execution plan for agents

Self-contained handoff for finishing the three workstreams the user requested on 2026-10-09 ("Finish the immediate unfinished work"): **dataless-file safety (Q-153)**, **document presentation (Q-72–Q-77)** and **image memory (Q-154)**. Everything else in the quality program stays out of scope; see [the continuation plan](2026-10-07-quality-program-continuation.md) for the whole program and its invariants.

Read before starting, in this order: [AGENTS.md](../../AGENTS.md), this file, the "Approved decisions and invariants" and "Ownership and integration protocol" sections of the continuation plan, the Q-72–Q-77 and Q-153/Q-154 rows of [decision 027](../decisions/027-best-in-class-quality-program.md), and the [image footprint record](../validation/quality-program-image-footprint-2026-10-08.md). Do not re-ask the questions answered in [owner-questions.md](../reviews/2026-10-06-quality-review/owner-questions.md).

## 1. Starting state (verified 2026-10-09 13:50 +03)

| Item | Value |
|---|---|
| Worktree | `/Users/cbs/Github/prev/.claude/worktrees/design-system-website-3836bc` |
| Branch | `claude/competitor-ux-ui-analysis-0fab0e` |
| Local HEAD | `0465ae9`, clean |
| [PR #12](https://github.com/canburaks/prev/pull/12) head | `f2e5ebc`, open, mergeable |
| Unpushed | 17 commits `cc26cde..0465ae9` (local is ahead only; nothing to pull) |
| Last stop checkpoint | `0f1c587` |
| Last full green local suite | `389ebcb` (3,486 tests, 22 static checks) |
| Last full PreviewCore run | `0465ae9`: 1,501/1,502; one order-dependent failure (section 4, task L2) |
| Ignored drafts | `.build/quality-work/` (never committed; review against current source before use) |

### Done since `0f1c587`

- Q-153: monitor event/reopen refusal (`d858856`), reloader refusal and generation lifetime (`e247490`), no implicit companion/extension rearm (`0532d4a`, `35cab66`), selected folder root (`389ebcb`), offloaded descendants metadata-only (`939a119`), bundle parse inside the checked scope (`60fe674`), scalar monitor flag transfer (`cc26cde`).
- Q-72/Q-73: native code-card wrapper and continuous cards (`7773860`, `7d99ca6`), safe context-menu copy (`4bf906d`), margin copy buttons (`75f5a25`, `c1ddeb9`), bounded code-body highlighting (`535d0d1`, `0465ae9`).
- Q-77: explicit Mermaid fence identity (`31790da`).
- Q-154: production decode admission defaults to one active decode (`ec22aa0`); report validator capped at one lease (`0465ae9`). The 100 MiB target is still unmet.

## 2. Ground rules for every agent

1. **Test first.** Each change is a pair of commits: `test: specify …` (RED, compiles, fails semantically) then `feat:`/`fix: …` (GREEN). Record RED/GREEN logs under `.build/quality-work/<item>-<topic>-{red,green}.log`. A compiler error is a setup defect, never a RED.
2. **One changelog entry per commit** at the top of `CHANGELOGS.md` (`## 2026-10-DD — <title>` plus 1–3 bullets: what changed, exact test counts, what remains). Only the lead edits `CHANGELOGS.md`, `docs/**` and the queue; specialists hand the lead the text.
3. **Ownership.** The lead records grants before branching and checks them: `python3 tools/check_ownership.py --workstream <owner> --base <batch-base>`. A file is edited by one agent at a time. `NativePreviewView.swift`, `PreviewTextContentView.swift`, `PreviewContracts/**`, `PreviewCore/**`, `Package.swift`, resources and Xcode project are **lead-only** integration points. Specialists propose hooks there as a patch in `.build/quality-work/`.
4. **Strings.** Never edit catalogs directly. Add `tools/localization/additions/<workstream>-<topic>.json` with all 14 languages and translator context (copy the shape of `ux-documents-q73-code-controls.json`). The lead applies additions once, regenerates `Localizable.xcstrings`/`*.lproj`/`translations/*.json`, adds typed `PreviewStrings` cases and runs `python3 tools/validate_localization.py && python3 tools/test_localization.py`.
5. **Safety invariants.** Read-only, bounded, cancellable; no materialization of dataless files; rendered text is the already-concealed safe text; copy/accessibility/highlighting never see unredacted source; generation guards stop late results replacing a newer preview.
6. **Evidence honesty.** Package tests, compiler checks, signed builds and Finder observation are separate evidence levels. Never close a queue row or plan checkbox without its evidence. Never relax a validator or assertion to get green; fix the cause or record the miss.
7. **No production identifiers, no system state changes.** Don't reset Quick Look caches, kill Finder or change extension preferences.

## 3. Team and ownership

At most a lead plus three specialists, matching the program's batch rule.

| Agent | Workstream | Granted files (beyond new test files under its suites) |
|---|---|---|
| **Lead** | Integration, L1–L5, all docs/strings/hooks | Lead globs in `tools/ownership.json` |
| **S-safety** (q-safety) | Q-153, tasks A1–A4 | `PreviewFormats/Packages/**`, `PreviewFormats/Containers/**`, `PreviewFileAccess/**`, `Tests/Integration/Provider*`, `Tests/Integration/Dataless*` |
| **S-docs** (ux-documents) | Q-72–Q-77, tasks B1–B5 | `PreviewRenderers/Markup/**`, `NativeMarkdownStyling.swift`, `ReadingLayout.swift`, `Diagrams/**`, `Notebooks/**`, `Data/NativePlotPreviewView.swift`, `Images/NativeImagePagesView.swift`, `Images/DocumentPresentationNotices.swift`, `MarkdownDiagramFences.swift`, `tools/localization/additions/ux-documents*.json` |
| **S-perf** (q-performance) | Q-154, tasks C1–C4 | `Images/ImagePageDecoder.swift`, `Images/ImageDecodeAdmission.swift`, `Images/ImagePageScheduler.swift`, `script/benchmark_release_images.py`, `script/test_benchmark_release_images.py`, `Tests/Performance/**`, `.build/quality-work/q154-footprint/**` |

Conflict rules:
- `NativeImagePagesView.swift` belongs to S-docs. If S-perf needs its cache constant (`maximumResidentBytes = 192 MiB`) or drawing path changed, S-perf hands the lead a patch and the lead applies it after S-docs' current commit lands.
- S-perf measures in a **separate frozen worktree** (`git worktree add ../q154-measure <sha>`) so other agents' commits never invalidate a Release measurement.

## 4. Lead tasks (do first, in order)

**L1 — Push the unpushed work.** `git push origin claude/competitor-ux-ui-analysis-0fab0e` (fast-forward from `f2e5ebc` to `0465ae9`). Update the PR body from the latest implementation record; keep "not ready to merge".

**L2 — Diagnose the order-dependent failure.** `narrowLongLTRAndRTLContainingBodiesKeepCardPaintAndSelectionInsideTheViewport` in `Packages/PreviewCore/Tests/PreviewRenderersTests/Markup/Q73NativeCodeMarginTests.swift` passes alone and fails in the full run, also without `0465ae9`.
- Reproduce: `swift test --package-path Packages/PreviewCore --filter 'Q73NativeCode'`, then widen the filter (`'Q7[23]|Markup'`, then `PreviewRenderersTests`) until it fails. Add `--no-parallel` to separate ordering from concurrency.
- Likely causes, in order: shared process state leaking between tests (process-wide `ImageDecodeAdmission`, cached fonts/text-system singletons, appearance or `NSApp` effective appearance, a static layout cache, a window left key), or parallel suites sharing a main-actor run loop.
- Fix the leaking state or isolate it explicitly in the test (fresh window/appearance, `.serialized` trait only with a written reason). Do not delete or loosen the viewport/selection assertions.
- Exit: the full PreviewCore run is green twice.

**L3 — Install grants.** Write the section 3 grants, run `python3 tools/check_ownership.py --audit`, record the batch base SHA in the implementation record.

**L4 — Integrate continuously.** For each specialist tranche: rebase/cherry-pick, run the focused suites plus `./script/build_and_run.sh --check-static`, apply strings, write the changelog entry, push. Every ~3 tranches run the full gate (section 8).

**L5 — Close out.** Section 9.

## 5. Workstream A — dataless-file safety (Q-153), S-safety

Goal: no SpacePane code path can make a cloud provider download a file implicitly, in either extension or the companion; a dataless or partially downloaded item yields the typed "unavailable content" result or metadata-only facts.

Current boundary: `PreviewFileAccess/DatalessFiles.swift` (checked no-materialization policy) wraps `BoundedFileReader`, `BoundedRandomAccessFile`, `BoundedReadAccess`, `PreviewFileClassifier`, `PreviewMonitorDescriptor`, `FolderScan`/`DirectoryReadAccess`, `FolderSummaryAdapter`, `BundleDirectory`/`ApplicationBundleAdapter`.

**A1 — Finish bundle descendants** (the stage `60fe674` names as next).
- RED: extend `Packages/PreviewCore/Tests/PreviewFormatsTests/Packages/Q153BundleOwnerTests.swift` (support: `Q153BundleSupport.swift`) with instrumentation of every requested descendant file and walked directory: `Info.plist`, `_CodeSignature`, icon resources, nested frameworks. Assert each open happens inside the checked scope, an offloaded descendant becomes a partial/metadata-only fact rather than a read, and every DIR/descriptor closes before policy restoration.
- GREEN: route each descendant open in `BundleDirectory.swift`/`ApplicationBundleAdapter.swift`/`PackageIconImages.swift`/`BundleInfoSummary.swift`/`CodeSigningSummary.swift` through the same owner as the root. Recheck after open with `fstat` flags (`SF_DATALESS`), map `EDEADLK` to unavailable.
- Release lifetime check: `swift test -c release --package-path Packages/PreviewCore --filter 'Q153Bundle'`.

**A2 — Audit for any remaining unguarded open path.**
- `rg -n 'open\(|openat\(|fdopendir|opendir|readdir|fopen|Data\(contentsOf|FileHandle\(|CGImageSourceCreateWithURL|sqlite3_open|AVURLAsset|MDLAsset\(url' Packages/PreviewCore/Sources Extensions Apps`. At 2026-10-09 the only non-guarded hits were bundle-resource reads (`FormatCatalog.swift`, `AppearanceSampleLibrary.swift`), which are app-owned and fine.
- Check the thumbnail extension, the companion direct preview/drop path, the CAD byte handoff (bytes must come from a guarded reader before the XPC call), MIDI and SQLite (in-memory copy from guarded bytes).
- Add a static guard to `script/check_static.py` (lead applies) that fails when those APIs appear outside an allowlist of guarded owner files, plus a self-test in `script/test_check_static.py`.

**A3 — Partial-download and package cases.** Extend the ignored provider checks (`.build/quality-work/q153-resume/ProviderReadChecks.swift`, `ProviderFolderChecks.swift`, `ProviderFixture.swift`) into the committed `Tests/Integration/DatalessProcessChecks.swift` family:
- A wholly dataless file (existing owned iCloud fixture in `.build/quality-work/q153-provider-fixture.json`), a dataless folder child, a dataless bundle (`.app`-shaped directory) and, if the provider allows, a partially materialized file.
- Evidence per case: typed result, `stat` block count before/after unchanged, no `brctl`/File Provider download observed, descriptors closed. The fixture lives in the user's own iCloud folder with a unique UUID name; never touch other user files; evict with `brctl evict` only for owned fixtures.

**A4 — Records.** Hand the lead the queue-row update for Q-153 (what is now locally proven vs. host-pending) and the implementation-record paragraph.

Exit for A: all Q153 suites green in Debug and Release; provider checks pass on the owned fixtures; static guard committed; the remaining gap is signed Finder/companion and macOS 15 observation only (section 10).

## 6. Workstream B — document presentation (Q-72–Q-77), S-docs

Work in this order; each bullet is one RED/GREEN pair unless noted. Renderer entry points: `Markup/MarkupModel.swift` (decorations: `heading(Int)`, `code`, `quote`, `tableHeader`, `codeBlock`, `alertTitle(MarkupAlertKind)`, `rule`), `Markup/MarkupBuilder.swift`, `NativeMarkdownStyling.swift`, `Markup/NativeQuoteTextBlock.swift` and `Markup/NativeCodeTextBlock.swift` (the established `NSTextBlock` patterns). Follow `Q72NativeCodeCardTests.swift` and the quote tests for pixel/geometry assertions (controlled bitmap, narrow RTL/LTR).

**B1 — Q-72 remaining block styling.**
1. Alert bars: a coloured leading bar plus title for the five `MarkupAlertKind`s, **trailing in RTL**, colour from palette roles (never literal colours), contrast-checked in every theme.
2. Inline-code chips: subtle background and code face, no change to copied text.
3. Tables: tab stops from measured column widths (bounded by visible rows) with numeric right/decimal alignment; header weight; no horizontal scrolling of prose.
4. Modular heading scale relative to the configured size (D2: system prose face), with spacing; verify large-text sizes.
5. Rules drawn as borders/block edges, not glyph runs; selection/copy preserve source characters.
- For every item: appearance-only restyle without re-parse, byte-exact copy, VoiceOver text unchanged, narrow-width wrapping, both directions.

**B2 — Q-73 closure.** Cards, menu, margin buttons and highlighting exist. Remaining:
- Language label on the card from `.codeBlock(language:)` (localized "Copy <language> code" accessibility label; the language name is never translated).
- Verify highlighting stays inside token bounds for each supported language hint, and that large documents cap highlighting (performance bound in tests).
- After L2, make sure the margin tests are order-independent.

**B3 — Q-74 Contents rail.**
- `Markup/MarkupContentsView.swift` already provides Contents as a mode. Add a collapsible leading rail when the pane is wide; keep Contents a mode when compact. Use the existing density/compact state; the width threshold is a **provisional named constant** next to the current 480 pt compact placeholder, explicitly marked for replacement from Finder measurements (S2).
- Current-section tracking: map the visible text range to the nearest preceding heading index and update the selection without stealing focus; announce nothing on scroll.
- Clicking a heading scrolls the text view; keyboard arrows only when the rail has focus (D9); Space stays with Quick Look.
- Copy from the rail uses the injectable host pasteboard (existing copy seam), never `NSPasteboard.general` in tests.
- Integration into `NativePreviewView`/`PreviewTextContentView` is a lead hook: S-docs delivers the view, its model and a hook patch.

**B4 — Q-76 page/ebook/notebook honesty.**
- "Showing chapters 1–12 of 38" for truncated ebooks: chapter counts come from adapter facts (`PreviewFormats/Documents/**`); never infer them in the view.
- Failed page frames: a framed placeholder with a symbol and localized label in `NativeImagePagesView.swift` (never a blank gap).
- "Page 3 of 1,200" in the existing limits strip (Q-51 API; locale number formatting, pluralized).
- Notebook cell cards (input/output grouping) and "Figure 2, shown in Pages" placeholders consistent with D15 (inert placeholders; figures in Pages).

**B5 — Q-77 diagrams and plots.** Drafts: `.build/quality-work/q77-diagrams/` (`CONTRACT.md`, `PlotAntimeridian.swift`, `Q77DiagramFitTests.swift`, `Q77NativePlotSeamTests.swift`, `Q77PlotAntimeridianTests.swift`, `SafeModeLimitReporting.swift`). Re-review each against current source before installing.
1. Typed selection receipt: selected one-based fence index plus total emitted fences (bounded to the first 16), giving "Diagram 1 of 3 is drawn". Count from emitted fences, not successful parses.
2. Legibility floor: if fitting would push text below a minimum point size, draw at the floor with scrolling and show a fitted-scale note.
3. Plot notice moves to the limits strip.
4. Antimeridian: split or unwrap longitude spans crossing ±180° so lines don't streak across the map; tests at −179/179, 0/360 inputs and the poles.

Strings for B1–B5: one additions file per item (`ux-documents-q72-blocks.json`, `-q74-contents.json`, `-q76-honesty.json`, `-q77-diagrams.json`).

Exit for B: every listed bullet implemented and tested in the package; full PreviewCore green; the remaining gap is host layout/VoiceOver/large-document measurement only.

## 7. Workstream C — image memory (Q-154), S-perf

Facts that shape the approach:
- Production decode: `ImagePageDecoder.makeThumbnail` uses `CGImageSourceCreateThumbnailAtIndex` with `ThumbnailMaxPixelSize` capped by `ImagePagesLayout.maximumDecodeSide` (4,096 px) under the 8 MP request policy, and `ShouldCacheImmediately: true`; source cap 40 MP; view cache budget 192 MiB; admission is now one decode at a time.
- Measured (decoder-only, worst-case 8 MP request): a single 40 MP PNG/JPEG peaks about 115 MiB incremental; serialization fixed the concurrent cases (about 125–140 MiB) but cannot fix singles. Subsampling hints did nothing for PNG.
- Real views request display-sized sides (the cache trace shows 2016/1999 px columns), which is much smaller than the 8 MP benchmark request. The decoder-only number is therefore an upper bound, not the user-visible footprint.

**C1 — Repair and complete the native cache/draw measurement.**
- Failure record: `cache-causality-failed-5284690-r1-*` and `cache-refused-layout-causality-5284690-r1-diagnosis.json` in `.build/quality-work/q154-footprint/experiments/candidates/`; protocol `CACHE_MEASUREMENT_PROTOCOL.md`; audit `AUDIT.md`; refusal draft `cache-source-refusal-draft-5284690-r1`.
- Fix 1: for the oversized 100 MP scenario, the validator must accept a refusal (nil bitmap, no admission lease, zero resident/drawn bytes) as that scenario's correct terminal state. Specify this with a new validator test first, scoped only to declared refusal scenarios.
- Fix 2: pair warm samples by request chain (cause → replacement → accepted callback), not by sample index, so a sample with one nil request and a sample with two requests plus a layout replacement are compared correctly. Keep all strictness checks for unexplained cancellations.
- Then freeze a clean SHA in the measurement worktree, rebuild the worker and run production (now serialized by default) with full cold/warm counts. Archive with a SHA-256 manifest like the earlier attempts.

**C2 — Choose an optimization, only if C1 still misses 100 MiB.** Measure each candidate independently against the same frozen inputs with `script/compare_benchmarks.py` (median, 95% bootstrap interval, p95, max; regression bound max(10 ms, 5%)):
1. Request the display-sized side in all paths (verify no path asks for the 8 MP ceiling when the view needs less).
2. `kCGImageSourceShouldCacheImmediately: false` with explicit draw-time decode, if the cache then holds only drawn size.
3. A 4 MP decode ceiling (named variant; previously unselected, never measured).
4. Lower the source cap below 40 MP. This changes what users can preview, so present data and ask the user before adopting it.

**C3 — Adopt.** RED/GREEN in production files; keep source/output/cache budgets, cancellation-owned leases and the admission tests (`ImageDecodeAdmissionTests`, `ImagePageLeaseLifetimeTests`) green; Release check `swift test -c release --package-path Packages/PreviewCore --filter 'ImageDecodeAdmission|ImagePageLease'`.

**C4 — Record.** Append a dated section to the image footprint record with exact SHAs, hashes, tables and the decision; update the Q-154 row in the continuation plan via the lead.

**Escalation:** if no candidate meets 100 MiB on the realistic draw workload without reducing supported input, stop and give the user the measured options (accept a revised target for single 40 MP sources, lower the source cap, or accept the miss for 1.0). Do not redefine the target yourself.

## 8. Validation gates

Per tranche (owner of the tranche):

    swift test --package-path Packages/PreviewCore --filter '<new and related suites>'
    ./script/build_and_run.sh --check-static
    python3 tools/check_swift_syntax.py --all --require
    python3 tools/check_ownership.py --workstream <owner> --base <batch-base>

Full gate (lead; at least after each workstream completes and before every push that closes an item):

    ./script/build_and_run.sh --check
    ./script/build_and_run.sh --check-compiler
    ./script/build_and_run.sh --test
    python3 tools/validate_localization.py && python3 tools/test_localization.py
    python3 script/test_check_static.py
    python3 script/test_benchmark_release_images.py

Hosted CI: dispatch the full macOS workflow on the final SHA (or include `[ci-mac]` in the commit message) and record the run link and counts.

## 9. Close-out (lead)

1. Full gate green at the final SHA; push; hosted macOS run green.
2. Update the implementation record, the Q-72–Q-77/Q-153/Q-154 rows of the continuation plan, and add pending-queue rows per commit group with the exact host observations still needed.
3. Update the PR #12 body. ~~It stays **not ready to merge** until the host and release gates in the continuation plan close.~~ Amended 2026-10-10 by the user's instruction to make the PR ready to merge: merging the development branch into `master` is repository integration, decided by the user, and claims nothing beyond what hosted run 115 proved (compile, type-check, 3,701 parallel and 74 serial package tests, integration executables). The host and release gates stay open in the pending-verification queue and in S2/S5 of the continuation plan; a merged `master` carries the same "verification pending" sentences until a Mac session replaces them. These three workstreams don't finish the program.
4. Report to the user: what is locally proven, what needs a signed host (section 10), and any C2 escalation.

## 10. Requires the user or a signed host (agents prepare, cannot close)

- Fresh signed build (`./script/build_and_run.sh --verify`), then Finder observation of the dataless cases, code cards/copy/Contents rail/alerts in panel and preview pane, VoiceOver, keyboard focus, narrow widths, macOS 15.
- Measured pane widths to replace the 480 pt compact placeholder and the provisional rail threshold.
- Real-host process memory for image-heavy documents.
- Any decision to lower the 40 MP source cap or amend the 100 MiB target.

## 11. Definition of done for this plan

- A1–A4, B1–B5, C1–C4 and L1–L5 completed, with RED/GREEN evidence logs and changelog entries.
- Full gate and hosted macOS run green on the final pushed SHA, with zero order-dependent failures.
- Records updated; every remaining item is explicitly a host/user gate from section 10.
