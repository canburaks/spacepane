# Decision 027: the best-in-class quality program

Date: 2026-10-06. Status reconciled 2026-10-07: **implementation in progress; acceptance open. The owner questionnaire records D1–D27 plus D-chrome and D-3D as answered or explicitly deferred on 2026-10-06; Wave 0 started the same day.** This record sequences the work that takes SpacePane from "level or ahead on substance, behind on presentation and unproven in the host" to best in class across ten dimensions, and it does so for a team that mostly works in cloud sessions without a compiler. It amends and absorbs [decision 026](026-world-class-ux-program.md), whose seven presentation workstreams remain the core of the user-visible work, and it adds the quality work the [ten-dimension review](../reviews/2026-10-06-quality-review/README.md) found: safety, performance, accessibility and localization, architecture and verification, platform evidence, thumbnails and release readiness. Round 2 foundations and selected Round 3 deliverables are implemented; the [continuation plan](../plans/2026-10-07-quality-program-continuation.md) maps all 133 backlog entries to source status, remaining work and verification. The [synchronization record](../validation/quality-program-sync-2026-10-07.md) records the current compile/test boundary. Historical review statements below describe the starting point, not the current tree. The evidence is the ten reports under [docs/reviews/2026-10-06-quality-review/](../reviews/2026-10-06-quality-review/); finding and recommendation identifiers below (CH, SV, DM, CO, PF, SP, AL, AR, PI, TH) refer to them.

## Why a program record and not a list of fixes

Three facts shape the plan. First, the product's substance is ahead of the category while its presentation, its evidence and parts of its copy are behind, so the work is broad rather than deep in any one place. Second, decision 026 cannot be implemented as written: its ownership table, its string-marker rule, its facts contract, three of its gates and one of its principles fail against the code (see "Amendments to decision 026"), so the contracts must be fixed before anyone branches. Third, the sessions that will do most of the writing cannot compile, run or observe anything, while every claim this repository makes must be verified on a Mac. The program therefore separates what can be authored blind from what must be observed, puts the observations first, makes continuous integration the compiler for cloud sessions, and keeps the verification debt visible in one queue.

## Where each dimension stands and what moves it

| Dimension | Now | Target | What moves it (the backlog groups below) |
|---|---|---|---|
| Preview chrome and states | 2 | 4 | Contract commit (B), chrome workstream (C-chrome), the completion-handler decision (D12) |
| Structured views and modes | 3 | 4 | P0 fixes (A), mode policy and typed rows (C-modes), owner decision D1 |
| Documents, media and 3D | 2.5 | 4 | Ebook labels and conditional notices (A), reading layout and 3D legibility (C-documents, C-containers-3d) |
| Companion | 3 | 4 | Honest status and undo (A, C-companion), setup trail after the Mac spike |
| Performance | 3 | 4 | Re-baseline (Wave 1), lazy models, style signature, viewport-first layout (C-performance) |
| Security, privacy and safety | 3.5 | 5 | URL credentials and recall corpus (A), worker executor (B), canary suite and fuzzing (C-safety) |
| Accessibility and localization | 3 | 4 | Plural tooling (A), announcer, order and contrast (B, C-a11y-l10n), VoiceOver passes (Wave 4) |
| Architecture and verification | 3 | 4.5 | Static gate, CI, seams and decomposition (A, B) |
| Platform integration and release | 2 | 4 | The Wave 1 Mac session, host matrix, TestFlight, manifests, OCCT route (Wave 1, C-platform, Wave 4) |
| Thumbnails | 2 | 4 | No summary text (A), badge, shape with counts, policy re-decision, reply gate (C-thumbnails) |

Targets are the scores the amended gates describe; they are not promises about Finder routing, App Review or translation quality.

## Two environments, one rule

Work happens in two kinds of session, and every backlog item names which.

**Cloud sessions** run on Linux with no Swift toolchain, no Xcode and no macOS. They can read and write every file; run the Python tooling that needs neither `xcrun` nor `plutil` (`script/sync_manifests.py --check`, `script/generate_appearance_samples.py --check`, `tools/test_localization.py`, `tools/add_localizations.py`, and the new checks this program adds); edit string catalogs and translation inputs; write decisions, protocols and plan entries; and author Swift source and tests. They cannot compile, run, render, measure or observe. Every Swift line written in a cloud session is **unverified** until the continuous-integration job or a Mac session has compiled and tested it.

**Mac sessions** run on a Mac with Xcode. They verify what cloud sessions wrote (`--check`, `--check-compiler`, `--test`), build signed artifacts (`--verify`, `--archive`), measure (the two benchmark scripts), observe Finder's hosts, run VoiceOver and the language and accessibility checks, and write the validation records that let plan boxes be checked.

The one rule: **a cloud session never marks anything verified.** It records what it did, what it could not check, and what the next Mac session must run. A Mac session owns every checked box.

### Continuous integration as the compiler for cloud sessions

At the original review the repository had no Swift continuous integration (AR-01). The implemented `.github/workflows/package.yml` now runs the Linux static job on pushes and pull requests, and the macOS package job on manual dispatch or a push whose head commit contains `[ci-mac]`. A green static-only run is not a passing package run. Hosted run 33 passed the full Round 2 suite; run 40 compiled Round 3 but failed a cancellation timing assertion before the companion integration checks. The remainder of this paragraph records the original infrastructure rationale. GitHub-hosted `macos-26` runners ship Xcode 26.x, and an `xcode-27` label is in public preview, according to [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [the macOS 26 runner announcement](https://depot.dev/blog/now-available-macos-26-github-actions) read on 2026-10-06; the package needs Swift 6.2 or later (`swift-tools-version: 6.2`, `@concurrent`, `isolated deinit`, an isolated conformance), which Xcode 26 provides. A workflow with a Linux `static` job (the portable gate) and a macOS `package` job (`--check`, `--check-compiler`, `--test`, with the SwiftPM build directory cached) gives every push a compiler within minutes. The first run tells whether the hosted Xcode compiles the package; if it does not, the `xcode-27` label is the fallback. The job proves compilation, the package suite on the runner's OS and the type-check of both extensions; it proves nothing about Xcode project linking, resource embedding, signing, extension registration, Finder, VoiceOver, layout in real hosts or performance (AR R3). The OCCT worker stays out of the pull-request job and goes to a nightly job with its own cache.

### Rules for Swift written without a compiler

These go into AGENTS.md's collaboration section once the owner accepts this record (AR R10). Until then they bind the program.

1. Use only APIs that already have a call site in this repository (find it with `rg` and copy its shape) or that Apple documents as available on macOS 15 with an unchanged signature. The sources contain no availability checks today; never introduce one blind. A first use of an API new to the repository (`NSPopover`, `NSProgressIndicator`, `UndoManager`, `.searchable`, `DispatchSerialQueue`, `NSTextBlock`) goes in its own small commit behind a narrow wrapper and is flagged in the queue.
2. Mirror the repository's concurrency patterns exactly: `@MainActor final class` for every type that touches AppKit or SwiftUI, `@MainActor @Observable final class` for stores, nonisolated `Sendable` value types for models, `isolated deinit` for teardown, `@concurrent` for blocking work, `Mutex` for shared state. The package's default isolation is `nonisolated`, so a forgotten annotation is a real defect, not a warning.
3. Keep blind edits inside one module. Cross-module access changes, implicit memberwise initializers used from another module, `Package.swift` target changes, resource moves and `Prev.xcodeproj` edits wait for a Mac.
4. After adding an enum case, list every `switch` over that enum with `rg` and update each; the compiler cannot remind you.
5. Keep SwiftUI bodies small and extract subviews; type-checker timeouts cannot be detected blind.
6. Tests first, in their own commit, written against named seams and pure models, with exact English expectations and explicit locales. On the Mac, run them against the old code to see them fail for the right reason, then against the change.
7. One concern per commit, about 300 changed Swift lines at most. Run the static gate and the syntax gate before each push. Mark the changelog entry "authored without a compiler; verification pending" and append a row to the queue.
8. Never add a test that waits on wall time; inject the clock or scheduler.
9. Strings go through `tools/add_localizations.py` with translator context and a plural form where a count appears; never a literal in a view.
10. Prefer additive changes (new types, new files, new tests) over edits inside large existing methods; when an existing method must change, keep the old path intact behind the new call until a Mac session has validated the replacement.

### The pending-verification queue

[docs/validation/pending-mac-verification.md](../validation/pending-mac-verification.md) is a table that cloud sessions append to and Mac sessions consume: date, commit, what changed, the commands to run, the observations to record, and the validation record that closed the row. A Mac session works the queue top to bottom, fixes compile and test failures in place, records the outcome in a dated validation record, and only then checks plan boxes. The program is done when the queue is empty and the gates are recorded.

### Batches

Cloud work is grouped into **verification batches** of one subsystem and roughly 1,500 changed Swift lines, so that one Mac session can compile, fix and validate a batch in one sitting. A batch that fails to compile is fixed on the Mac unless the fix would exceed the session; then it is reverted and re-authored in the cloud with the diagnostics in hand. Continuous integration shrinks the batches' compile risk to zero once it runs; the Mac session then spends its time on observation.

### What a Mac session runs, in order

```sh
./script/build_and_run.sh --check
./script/build_and_run.sh --check-compiler 2>&1 | tee .build/check-compiler.log   # new warnings count as regressions
./script/build_and_run.sh --test                                                 # twice when a batch touched timing
# red/green for each test-first commit: swift test --package-path Packages/PreviewCore --filter <NewSuite>
# offscreen renders of the states and strips the batch touched (opt-in test writing PNGs under .build/renders/)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/benchmark_release_native_renderer.py   # when rendering changed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --verify                   # signed companion and extensions
# Finder observation with python3 script/generate_host_fixtures.py fixtures; VoiceOver, 200 % text, de/ru/bn, Reduce Motion/Transparency, Increase Contrast as the batch requires
```

Each step's result goes into a dated validation record with host, OS build, Xcode and Swift versions, in the style of the existing records.

## Amendments to decision 026

These apply before any workstream branches. They change 026's text; its principles, anatomy contracts and seven workstreams stay.

1. **Ownership.** Every file gets an owner: `Interaction/PreviewShortcut.swift` to ux-modes-structure; `NativePreviewPane.swift` and both extension hosts to the lead; `Apps/PrevApp/Stores/*`, `Models/*`, `Support/*`, `Tests/Integration/CompanionModelChecks.swift`, `SettingsModelChecks.swift` and `script/test_companion_models.py` to ux-companion; `PreviewThumbnails/*`, `Extensions/PrevThumbnailExtension/ThumbnailProvider.swift` and `script/probe_thumbnail.swift` to ux-thumbnails; listing models and listing views to one workstream (ux-containers-3d); `Diagrams/*`, `Data/NativePlotPreviewView.swift`, `SafeSubtitleCues.swift`, `NativeMIDIPlayback.swift`, `GeometryMetalRenderer.swift` and `PreviewFormats/Documents/*` to the workstream named in the backlog; every existing test file stays with the lead, and each workstream adds its tests in new files named for it (AR-06, CO-08, DM-14, TH-20). The table lives in `tools/ownership.json` and `tools/check_ownership.py` enforces it.
2. **Strings.** The "below its own marker" rule is replaced: each workstream commits only `tools/localization/additions/<workstream>.json` plus its `PreviewStrings.swift` cases below its marker; the lead applies the additions and regenerates once at integration; catalogs are written sorted (AR R7, AL R9, CH-9).
3. **Facts.** `PresentationFacts` is a typed, value-free contract in a UI-free module (`PreviewContracts` or `PreviewCore`), filled by adapters or family providers, never derived from `lineCount`, `byteCount` or `encoding` for non-text families, and shared by the facts strip and thumbnails (AR-05, CH-8, TH-20). A `TextOrigin` field says whether `text` is the file's own text, reformatted, converted or an app-made summary; "Details" and "Text" labels follow from it (SV2, TH-01).
4. **Limits.** A result that carries the effective budget (`PreviewResult`) replaces "limit values from the presentation"; `tooLarge`, `structureLimit` and `lineLimit` split into one key per limit; "limit 2 MB" is corrected to the input budget of the family (CH-10, AR R6).
5. **Gate 1** counts always-visible filter bars, the MIDI strip and the 3D button rows against the one-row budget; filters open on demand or move below the content guide (CH, SV-21).
6. **Gate 2** depends on the completion-handler policy chosen after the Wave 1 experiment (D12). Until then the gate reads "the companion shows the state view; Finder shows whichever state the policy selects" (CH-11, PF-05, PI-04).
7. **Gate 4** gains a second criterion: `muted` must differ from the foreground by at least 1.25:1 wherever the scheme has 7:1 headroom; Solarized Light, Solarized Dark and One Dark follow owner decision D11; the hairline is decorative at 1.3:1 in normal palettes and 3:1 in High Contrast (CH-7, AL7).
8. **Gate 5** gets an inline fallback: an in-view info panel that pushes content down; the popover is optional until the remote-view spike succeeds (PI-06, CH R12).
9. **Gate 11** is rewritten: a re-baselined benchmark on the current main with CSV, listing, Markdown-with-Contents, `.env`-with-findings and 1 MiB cases; interleaved A/B comparison of medians with a 95 % bootstrap interval; the regression bound is max(10 ms, 5 %); p95 and maximum are reported beside it; physical footprint replaces resident size (PF-07, PF R2).
10. **Principle 2** is scoped: Space and Escape are never bound; arrow keys may act only inside a focused table, outline, page column, canvas or viewport, as listed in the shortcut sheet; the Wave 1 observation decides whether even that is safe (DM-07, AL15).
11. **Overlays.** A floating control group over the 3D viewport and a code-block copy button in the margin are accepted exceptions; dimensions appear in the facts strip, not in a chip as well (DM-14, D10).
12. **Thumbnails** get a gate (G19) and the rejection of real cell values is recorded as an amendment to decision 022, pending D6 (TH-05).
13. **Validation hosts** are macOS 15 (the baseline), macOS 26 and the current release, each named in the records (PI-23).
14. **Companion specifics.** The renderer pill needs a catalog field (`primaryView`) with a drift test, and D1 (CO-08); the scheme gallery is twelve swatch tiles drawn from palette tokens, not 22 live panes (CO); the page title uses `.title2` semibold, since 20 pt has no macOS text style; the storage card also appears for failed-save and recovered states (CO-03); Command-comma follows D23.
15. **Shared contracts list** grows by: `TextOrigin`, `PreviewResult`, `unsupportedVariant`, `GeometryUnitProvenance`, `OmittedResources`, the counted string API, the announcer, the copy callback, the command table, the chrome scheduler, the worker executor and thumbnail admission, the completion policy, host events (see group B).

## Waves

### Wave 0 — stop the bleeding and build the floor (cloud sessions; one Mac run to confirm)

Entry: this record accepted; owner decisions in group A answered or explicitly deferred. Exit: every Blocker fixed in source with tests; the static gate, syntax gate, ownership check and workflow files committed; the plural tooling merged; decision 026 amended; the queue holding every cloud commit. All of it is group A in the backlog.

### Wave 1 — establish the truth (one Mac session, about a day, plus a TestFlight upload)

The program cannot choose its compact threshold, its loading policy, its popover design, its thumbnail policy or its baseline numbers without these observations, so they come first. The session runs the pending queue, then the protocol in the platform report (phases A to K) restricted to:

1. The Wave 0 batches and the first continuous-integration run.
2. The host spike: tooltip, popover, focus and key-equivalent delivery in the remote view with a throwaway branch (PI R9); Space, Escape and the arrows after clicking into text, an outline, Contents, Pages, the 3D viewport and a diagram (DM-07).
3. The completion-handler experiment: handler on state-view install versus after display, time to first content, what Finder shows meanwhile (PF R8, PI R2).
4. Pane widths and the Tahoe safe area for the panel, the preview pane, column view, Gallery and full screen, from Accessibility Inspector frames (PI D2, D3).
5. The macOS 15 runtime symbol check with `dyld_info` and a launch on 15.0–15.3 (PI-03).
6. The Finder routing matrix on the production identity, one fixture per catalog format, with one competing provider installed (PI phase C), the thumbnail provider and system-icon table per type (PI phase H, TH R4), and the `mdls` type table for source suffixes (TH R5).
7. The re-baselined benchmarks with the new fixtures and an Instruments profile of the warm JSON and source workers (PF checklist 1–2).
8. The sandbox scan and the System Settings deep link on 15 and 26 (CO checklist 3–4).
9. A VoiceOver baseline in both hosts (AL checklist 3–4) and the YAML row of the Finder matrix re-run (SV).

Exit: a dated host-matrix record, the measured widths, the chosen completion policy, the thumbnail decisions D6 and D7 answered with evidence, and the baseline numbers gate 11 compares against.

### Wave 2 — foundations (cloud sessions with continuous integration; Mac verification per batch)

The lead's contract commit and the enabling refactors, group B. Exit: `--test` green on a Mac with the contracts in place and unused by features; `NativePreviewView` decomposed behind seams; the worker executor and thumbnail admission measured on a Mac; decision 026's workstreams can branch on disjoint files.

### Wave 3 — parallel workstreams (cloud sessions with continuous integration; Mac batches)

Twelve workstreams on worktrees, each owning disjoint files, each with the items in group C. The lead integrates weekly, regenerates derived files, runs the full gate and keeps the queue. Exit: every group C item merged or explicitly deferred with a reason in this record.

| Workstream | Owns (in addition to decision 026's table, as amended) | Delivers |
|---|---|---|
| ux-chrome | 026's list plus `NativePreviewPane.swift` (lead-approved edits) | C-chrome |
| ux-modes-structure | 026's list plus `PreviewShortcut.swift`, `SafeStructuredText.swift`, `Data/SafeDataPresentation.swift` | C-modes |
| ux-documents | 026's list plus `PreviewFormats/Documents/*` (text-producing lines only) | C-documents |
| ux-containers-3d | 026's list plus listing views, `GeometryMetalRenderer.swift`, `NativeMIDIPlayback.swift` | C-containers-3d |
| ux-companion | 026's list plus `Stores/*`, `Models/*`, `Support/*`, the companion model checks | C-companion |
| ux-copy | 026's list plus the additions files | C-copy |
| ux-thumbnails | `PreviewThumbnails/*`, `ThumbnailProvider.swift`, `script/probe_thumbnail.swift` | C-thumbnails |
| q-performance | `NativeTextStylePass.swift`, `SafeStructuredText.swift` scanner paths, `DefaultPrivacyFilter.swift` (with q-safety), benchmark scripts and workers | C-performance |
| q-safety | `PreviewCore/DefaultPrivacyFilter.swift`, `PreviewContracts` recognizers, `HiddenCharacters.swift`, archive readers, image limits, `check_adversarial_corpus.py`, fuzz harnesses | C-safety |
| q-a11y-l10n | `tools/*localization*`, contrast tests, `PreviewAnnouncer`, companion accessibility edits by agreement with ux-companion | C-a11y-l10n |
| q-platform (lead) | `Extensions/*`, `Configuration/*`, `script/check_release_archive.py`, `validate_project.py`, `Native/*`, host matrix tooling | C-platform |
| website | `web/public/locales/*`, `web/src/data/*`, `Website/*` | C-website |

### Wave 4 — integration, gates and release (Mac sessions)

The amended gates of decision 026 plus G13–G20, the host matrix on macOS 15 and the current release, a TestFlight round (the only way to test the store-signed CAD path, D27), screenshots after the interface settles, native-speaker review of the chrome strings, and the release items. Exit: every gate recorded, the queue empty, the plan boxes checked by a Mac session.

## Backlog

Priority: **P0** blockers and honesty or privacy defects; **P1** foundations that unblock parallel work and verification; **P2** the program's main deliverables; **P3** polish and later. Effort: S under a day, M a few days, L a week or more. "Mac" says whether the item can be finished without one: **yes** (authored and unit-tested in the cloud; a Mac run only confirms), **partial** (authored in the cloud; needs observation or measurement), **no** (observation first). Dependencies name owner decisions (D) and other items (Q).

### Group A — Wave 0: P0 fixes, verification floor, tooling, documents

| ID | Item | Evidence | Pri | Effort | Owner | Mac | Depends on |
|---|---|---|---|---|---|---|---|
| Q-01 | Shared URL-credential recognizer in the privacy filter; delete the three per-adapter calls; tests across every text family and the thumbnail path | SP-01, SP R1 | P0 | S | q-safety | yes | D13 (finding kind) |
| Q-02 | Comic and package page labels: remove the tooltip or filter labels in the pipeline and drop any that change or carry hidden characters | SP-02, SP R2 | P0 | S | q-safety | yes | none |
| Q-03 | Table notice by origin: `SafeTable.Origin`, a true sentence for data summaries and partial reads, no completeness claim | SV1, CH-1, SV R1, CH R1 | P0 | S | ux-modes-structure | yes | ux-copy drafts |
| Q-04 | YAML compact sequences attach to their key or return nil; never re-root | SV4 | P0 | S | ux-modes-structure | yes | none |
| Q-05 | Profile spoken description indexed by `order[row]`; sorted-and-filtered test | SV6, AL1 | P0 | S | ux-modes-structure | yes | none |
| Q-06 | File Types subtitle and header: "Choose which file types SpacePane may preview. macOS decides which app previews each file."; remove the "Previews" header and group state word; fix `setup.notConfigured`, `general.limits.fileSizeHint`, `about.howItWorks.body` | CO-01, CO-11, CO-12, CO-13, CO-27, PI-12 | P0 | S | ux-companion, ux-copy | yes | none |
| Q-07 | Rendered ebooks: drop machine flags, localize known front-matter keys or lay out a title block, one localized "Image: %@" marker for every dialect | DM-01, DM-18, DM R1 | P0 | S | ux-documents | yes | none |
| Q-08 | Citation terms: record the English style-guide exception in decision 015 and the notice, or localize the twelve terms | AL14, AL R7 | P0 | S | ux-documents, lead | yes | D18 |
| Q-09 | Website honesty: replace the "Preview by … status line" test with the info symbol, add "a Mac with Apple silicon" to the OS requirement, hedge routing sentences with "when macOS uses SpacePane for the type", label the STEP hero tile opt-in or lead with a default-on format; all 14 locales and `Website/` | PI-07, PI-08, PI-19, PI-20, PI R5 | P0 | S | website | yes | D5 |
| Q-10 | Thumbnails never draw app-made summary text: a `picture` policy for `.app`, IPA and CBZ; decline otherwise; `TextOrigin` from Q-32 as the signal | TH-01, TH R2 | P0 | S | ux-thumbnails | yes | Q-32 |
| Q-11 | Geometry units and counts: `GeometryUnitProvenance`, `Measurement` formatting, "unit not declared" for STL, OBJ and PLY, "100,000+" when capped, a geometry-specific complexity failure | DM-11, DM R5 | P0 | S–M | ux-containers-3d, lead | yes | Q-32 |
| Q-12 | Small safety fixes: 7z counts bounded by record size and entry cap; bundle identifier as log subsystem; CAD `originatingSystem` mapped or dropped; OCCT extracted with `filter="data"` into a fresh directory | SP-15, SP-18, SP-19, SP-20, SP R16 | P0 | S | q-safety | yes | none |
| Q-13 | Package formats open on Summary as decision 017 says, or amend 017 | SV10 | P1 | S | ux-modes-structure | yes | D17 |
| Q-14 | Markdown offline notice only when something was omitted: `OmittedResources` counted by the renderers, mode-aware notices, BibTeX opens in References | DM-06, DM-16, DM R2 | P1 | S | ux-documents | yes | Q-32 |
| Q-15 | Notebooks with real figures: binary input path with its own budget, inert placeholders for image outputs, figures in Pages; until then name the picture as the cause | DM-13, DM R9 | P1 | M | lead, ux-documents | yes | D16 |
| Q-16 | Secret recognition breadth: token matching, the missing value formats, sibling name/value layouts, call-style definitions, `.netrc` and `.pgpass` grammars; a recall corpus test recording recall and the false-positive ceiling | SP-03, SP R3, SP R13, SP R14 | P1 | M | q-safety | yes | D13 |
| Q-17 | Thumbnail secret-shape withholding before drawing | SP-04, SP R4 | P1 | S | ux-thumbnails | yes | D14 |
| Q-18 | Portable static gate `script/check_static.py` and `--check-static`: manifests, samples, localization tests, a Python `.strings` parser when `plutil` is absent, `bash -n`, decision-number uniqueness, wall-clock test names, failure title/body pairs | AR-02, AR R1 | P1 | S | lead | yes | none |
| Q-19 | Swift syntax gate with tree-sitter over changed files, with a recorded baseline for the three known parser gaps | AR R2 | P1 | S | lead | yes | D25 |
| Q-20 | `tools/ownership.json` and `tools/check_ownership.py --workstream --base` | AR R5, amendment 1 | P1 | S | lead | yes | none |
| Q-21 | Continuous integration: `.github/workflows/package.yml` with a Linux `static` job and a macOS `package` job; nightly `--build-unsigned` with an OCCT cache | AR-01, AR R3 | P1 | M | lead | partial | D25; Q-18 |
| Q-22 | Blind-authoring rules in AGENTS.md, a risk-register row, the pending-verification queue | AR R10 | P1 | S | lead | yes | acceptance of this record |
| Q-23 | Localization tooling: `.stringsdict` generation and validation with CLDR categories per language, `PreviewStrings.count`, placeholder parity for every key at merge time, sorted output, per-workstream additions files, Python fallback for `plutil`, lints for unreferenced keys, identical-to-English values, typography, length budgets and generic comments | CH-9, AL2, AL11, AL12, AR R7, AL R2, AL R9 | P1 | M | q-a11y-l10n | yes | D8 |
| Q-24 | Benchmark tooling: stage signposts and a stage observer, `phys_footprint`, the new fixtures (CSV, listing, Markdown with Contents, `.env` with findings, 1 MiB source, 1 MiB JSON, log append), `script/compare_benchmarks.py` with the interleaved method and a Linux unit test, layout-pass guards | PF-07, PF R1, PF R2 | P1 | S–M | q-performance | partial | none |
| Q-25 | Documentation hygiene: `docs/decisions/README.md` index with the numbering rule, PLAN milestones as a status matrix (implemented, package-tested, compiled, observed), the progress narrative moved to validation records, undated validation files dated, README and PLAN header counts corrected | AR-18, AR R11 | P1 | S | lead | yes | none |
| Q-26 | Amend decision 026 as listed above and record D1–D27 as answered or deferred | amendments 1–15 | P1 | S | lead | yes | owner |
| Q-27 | Archive check hardening: exact entitlement sets per role, identical App Group arrays, runtime flag, no `cs.*` keys, nested Info.plists free of `$(`, CAD peer values, manifests present; `script/test_check_release_archive.py` on synthetic trees | SP-13, PI-13, SP R11, PI R7 | P1 | S | q-platform | yes | none |

### Group B — Wave 2: the lead's contracts and enabling refactors

| ID | Item | Evidence | Pri | Effort | Owner | Mac | Depends on |
|---|---|---|---|---|---|---|---|
| Q-30 | Named test seams (`displayedStatus`, `displayedModes`, `selectedMode`, `contentView(for:)`, one `descendants(of:)`) and migration of the 75 direct-subview lookups; tests only, confirmed green on a Mac before any refactor | AR-04, AR R4 step 0, CH | P1 | S | lead | partial | none |
| Q-31 | Decompose `NativePreviewView` in four "move, do not change" steps: `PreviewStatePresenter`, `PreviewModePolicy` (default-first order and per-origin titles), `PreviewTextContentView`, `PreviewHeaderView`; each step compiled and tested on a Mac before the next | AR-03, AR R4 | P1 | M | lead | partial | Q-30 |
| Q-32 | Contract commit, additive with defaults, tests first: `PresentationFacts` (UI-free), `PreviewResult` with the budget and a pipeline entry point, `PreviewFailure.unsupportedVariant`, `TextOrigin` on `TextPresentation`, `GeometryUnitProvenance` on meshes, `OmittedResources` on documents, `display(_:appearance:locale:limits:)` with the old overload forwarding, split limit keys, the `primaryView` catalog field with its drift test | AR-05, AR-10, AR R6, CH R7, CH R9, SV R2, DM R5, DM R2, TH R2, CO-08 | P1 | M | lead | partial | D1 for `primaryView` |
| Q-33 | `PreviewChrome` metrics and the chrome skeleton: header and content layout guides, a constant mode-control position, notes below the control, zoom as a chip, a bottom limits slot, `accessibilityChildrenInNavigationOrder`, the existing subview order kept, 25 inset literals replaced | CH-2, CH-22, CH R2, CH R11 | P1 | M | lead, ux-chrome | yes | Q-30 |
| Q-34 | `muted` and `hairline` in every scheme, seeded from the comment colour, in the AA and 7:1 tests with a "differs from foreground" case; a size cue where headroom is under 1.5×; every alpha and system secondary ink in chrome replaced; a companion contrast check for hint ink and accent text | CH-6, CH-7, AL6, AL7, CH R3, AL R6 | P1 | S–M | lead, ux-chrome, ux-companion | yes | D11 |
| Q-35 | `NativeStateView` and `NativeStateContent`: title and body per failure formatted at literal call sites, an empty state for 0-byte ready presentations, one accessibility element, an announcement, no action in Finder, `NativePreviewPane` accepting an outcome and a loading flag; a pipeline rule so 0-byte structured files are not malformed | CH-5, CH-17, CH R5, AL R5, CO | P1 | M | lead, ux-chrome | partial | Q-32, D12 |
| Q-36 | `PreviewAnnouncer` with a recorder for tests and the announcement policy (states, mode switches, copies, filter and sort results, zoom, 3D presets; never content, never live reload); `AccessibilityNotification.Announcement` in the companion | AL4, AL R5 | P1 | S | lead, q-a11y-l10n | partial | Q-35 |
| Q-37 | One copy callback adopted by text, outline, table, tree and Contents views; the Copied chip in a reserved slot, no motion under Reduce Motion, one string, one announcement, cancelled by a new generation; an injectable pasteboard in `MarkupContentsView` | CH-15, CH R10, P11 | P1 | S | lead, ux-chrome | yes | Q-33 |
| Q-38 | `PreviewCommand` table driving `PreviewShortcut`, the context menu and the shortcut sheet; digits by key code; layout-independent matching for ⌘C overrides and 3D letters; ⌥⌘1…9 for modes; an explicit key-view loop and focus handoff after a mode switch | CH-16, AL5, SV3, CH R11, AL R3, SV R2 | P1 | S–M | lead, ux-modes-structure | partial | Wave 1 key delivery |
| Q-39 | Chrome scheduler protocol with an injected clock for the spinner delay and the chip; `PreviewTestSupport` target holding one recording byte source, builders, temporary fixtures and `descendants(of:)`; duplicate fixture files deleted | AR-12, AR R9 | P1 | M | lead | partial | none |
| Q-40 | Worker executor on a `DispatchSerialQueue`; thumbnail admission (about half the active processor count); a Dispatch-driven reply gate; a generous preview host timeout with a timed-out state; the CAD client waiting on a continuation instead of `Thread.sleep`; wall-clock tests selected by suite name with a count guard | SP-05, PF-06, PF-16, AR-07, AR-08, TH-07, SP R5, PF R9, AR R8, TH R6 | P1 | M | lead, q-performance, ux-thumbnails | partial | measured in Wave 1 and after |
| Q-41 | Completion policy for Quick Look's handler (on state-view install or after a grace period) as a testable `PreviewHostSession` in the package; both orders observed in Finder first | PF-05, PI-04, CH-11, PF R8, PI R2 | P1 | S | lead | partial | D12 |
| Q-42 | Typed `.debug` host events in both extensions (request start and end, outcome kind, milliseconds, host geometry, settings state; never names, paths or content); `--logs` and `--telemetry` predicates fixed | PI-14, PI R4 | P1 | S | q-platform | yes | none |
| Q-43 | Linear, cancellable concealment in one forward pass returning a native string; the filter's own matches capped; byte-identical oracle tests | PF-04, PF R6 | P1 | S | q-performance, q-safety | yes | none |
| Q-44 | CAD peer requirement accepting the Mac App Store certificate marker or the team OU, in `CADPeerRequirement` with tests; the archive check compares the service's allowed-client values with the preview's identity | PI-02, PI R1 | P1 | S | q-platform | partial | TestFlight (D27) |
| Q-45 | Privacy manifests for the app, both extensions and the CAD service; presence and key checks in `validate_project.py` and the archive check | PI-10, PI R6 | P1 | S | q-platform | partial | none |
| Q-46 | Safe-area pinning for the header and footer; the mode control keeps its intrinsic height; density decided in `display` and `layout()` from the view's own width with hysteresis, before `configureDocumentSize()`; the threshold recorded only after Wave 1 measurements; the Theme sample forced to regular density | PI-15, PI-16, CH-20, CH R13, CH R14, PI R8 | P1 | S | ux-chrome | partial | Wave 1 widths |

### Q-40 implementation exception recorded on 2026-10-07

The CAD XPC client retains its bounded semaphore wait because `GeometryFormatAdapter.parse` is synchronous. The pipeline's dedicated Dispatch worker keeps this wait off the cooperative executor. A reply/invalidation signals immediately; 25 ms slices check cancellation/deadline while waiting, and connection-owned cancellation invalidates the service request on exit. Introducing a continuation solely inside this synchronous boundary would still require blocking or a larger async adapter-contract change. Keep the smallest existing boundary until a measured reason justifies that migration; no `Thread.sleep` polling is used by this client. Nine native XPC wait tests pass, including once-only replies, bounded output, cancellation and deadline handling; actual signed-host lifecycle and delivered-build observations remain separate gates. The five wall-clock pipeline/thumbnail liveness tests now live in three named suites, with a compiled-inventory exact-count guard before the serial pass.

### Group C — Wave 3: the workstreams

**C-chrome (ux-chrome).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-50 | One findings row: collapsed sentence with count and the copying sentence when anything is concealed, Show details, expansion capped at 25 % with internal scrolling, decoded text clipped to two lines, the cloud-folder warning first, a concealment glyph other than `info.circle`, Copy Concealed Text only in Rendered and Invisibles | CH-3, CH-4, CH-13, CH R4, P2, P3 | P2 | M | yes | Q-33, Q-34, Q-23 |
| Q-51 | Typed notices (`PresentationNotice` with kind) and one bottom limits strip; table and listing notices move into it; math and BibTeX notes only in rendered modes; "Showing the first {shown} of {total}" where known | CH-12, CH R8, DM-16 | P2 | M | yes | Q-32, Q-23 |
| Q-52 | Facts strip providers per family under markers (text, table, outline, listing, 3D, MIDI, notebooks, images), locale-formatted, never a source value, four facts regular and two compact | CH-8, CH R7, P13 | P2 | M | yes | Q-32, Q-23 |
| Q-53 | Info button (22 pt, labelled) opening an in-view info panel: read-only, processed on this Mac, "Preview by %@", concealed count, the commands of the current mode; a popover only after the Wave 1 spike | CH-13, P7, CH R12, PI-06 | P2 | M | partial | Q-38, Wave 1 |
| Q-54 | Accessibility order override, mode-control label "View mode", `.layoutChanged` after mode and state changes | CH-14, AL3, AL R4 | P2 | S | partial | Q-33 |
| Q-55 | Compact density behaviour: two facts, hidden gutter (D-chrome-3), hidden rails, a pull-down mode control below the threshold | 026 contract 1 | P2 | M | partial | Q-46, Wave 1 |
| Q-56 | Small chrome fixes: selection colours in the palette or a contrast test, CAD and MIDI wording stated once, the Copy Concealed confirmation cleared, reading-position restore | CH-18, CH R14 | P3 | S | partial | none |

**C-modes (ux-modes-structure).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-60 | Default-first segments and honest labels through `PreviewModePolicy`: "Details" and "Text" for app-made text, "Schema" for schema grids, at most five segments, Invisibles out of the control if D17 allows; a pipeline-backed test over the 76 samples | SV2, SV9, SV21, SV23, SV R2 | P2 | M | partial | Q-31, Q-32, D1, D17 |
| Q-61 | Typed outline rows: `kind` and `wireName` on nodes, SF Symbol glyphs, counts on containers, duplicate badge, dimmed null, tooltips from concealed values when truncated, "Key" and "Value" cell labels, "Hidden value" spoken, key column sized from content | SV7, SV16, SV19, P10, SV R3 | P2 | M | partial | Q-23 (plurals) |
| Q-62 | Interaction parity: one `SafeFilterQuery` and filter bar for outline, table and tree; ⌘F and ⌘G routed to the visible structured view; filter results announced including zero; Escape returns to rows; one row menu and copy format; Copy All copies the shown grid as TSV with a header; match styling and "in loaded content" | SV8, SV18, SV22, P14, SV R5 | P2 | M | partial | Q-38 |
| Q-63 | Quiet grid: right-aligned numeric columns, a muted row-number column outside selection, palette-drawn zebra in the contrast test, dim NULL, an honest range footer from `SafeTable.Extent`, state kept across reload and across Table/Profile | SV12, SV13, SV14, SV15, SV R6 | P2 | M | partial | Q-34, Q-32 |
| Q-64 | Listing markers and facts: parse `risks`, lock and warning glyphs with localized tooltips and help, visible markers for bidirectional and invisible characters in names while copy keeps the exact name, icons in Files, hidden and inaccessible counts to the facts strip | SV5, SV R4, SP-08 | P2 | M | partial | ux-containers-3d for `SafeListing*` |
| Q-65 | SQLite data grid with a table picker and an honest footer; schema grids labelled "Schema" | SV9, SV R7 | P2 | M–L | partial | D17 |
| Q-66 | Path bar with Copy Path in the bottom slot while an outline row is selected; per-family paths (JSONPath, record plus path, XPath-like for XML, wire keys for Summary); hidden in compact density | SV11, SV R8 | P2 | S–M | partial | Q-33, Q-61 |
| Q-67 | JSON Lines: a typed malformed-records finding with count and lines, issue markers in rows and gutter, a compact concealed preview per record instead of `{…}` | SV17, SV R9 | P3 | S | partial | lead for the finding kind |
| Q-68 | Localization cleanup for this area: distinct French words for Outline and Tree, segment comments on mode keys, an own key for Rows | SV20, SV R10 | P3 | S | yes | ux-copy |
| Q-69 | Subtitles open in Cues with readable cue text | DM-25 | P3 | S | partial | Q-60 |

**C-documents (ux-documents).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-70 | Reflow Markdown paragraphs (soft breaks joined, hard breaks kept); amend decision 015 | DM-03, DM R3 | P2 | S | yes | D-documents-6 (confirm) |
| Q-71 | Reading layout for Rendered mode: `ReadingLayout` with a prose face (per D2), about 1.4 leading, a measure of about 70 advances applied as inset, word wrap forced in reading modes, code in the user's code face, gutter and Go to Line hidden in Rendered | DM-02, DM-20, DM-21, DM R6 | P2 | M | partial | Q-70, D2, Q-46 |
| Q-72 | Block styling with `NSTextBlock`: code cards, quote and alert bars (trailing in RTL), inline code chips, table tab stops from measured column widths with alignment, body ink for emphasis, a modular heading scale, rules as borders | DM-04, DM-05, DM-19, DM-29, DM R7 | P2 | M | partial | Q-34, Q-71 |
| Q-73 | Code-block copy in the context menu and a margin button, the language label carried as `.codeBlock(language:)`, highlighting under the token bounds | DM-05, DM R13 | P2 | M | partial | Q-72, Q-37, D10 |
| Q-74 | Contents as a collapsible rail when wide with current-section tracking; a mode when compact; the host's injectable pasteboard | DM-15, DM R12 | P2 | M | partial | Q-46, Q-71 |
| Q-75 | Key policy: remove Space from Contents and Pages, keep arrows only inside focused content per amendment 10, route zoom to the visible mode view through `SafeModeZoomable`, announce "Find is not available here" | DM-07, DM-08, DM-28, DM R4 | P2 | S | partial | D9, Wave 1 |
| Q-76 | Ebook, Pages and notebook honesty polish: "Showing chapters 1–12 of 38", failed page frames with a symbol, "Page 3 of 1,200" in the limits strip, notebook cell cards, "Figure 2, shown in Pages" | DM-17, DM-22, DM-26, DM R10 | P3 | S | yes | Q-51, Q-72 |
| Q-77 | Diagram legibility floor with a fitted-scale note, "Diagram 1 of 3 is drawn", the plot's notice in the limits strip, antimeridian handling | DM-24, DM-31, DM R15 | P3 | S | partial | Q-51 |

**C-containers-3d (ux-containers-3d).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-80 | 3D legibility: a mid-tone material per appearance, ambient at least 0.35, light in view space, an up axis chosen per format (Z for STL and 3MF), a per-view "Up axis" item never persisted; a scheme test asserting a lit spread of at least 25 L* and a darkest face at least 1.5:1; an offscreen Metal pixel check | DM-09, DM-10, DM R8 | P2 | M | partial | D-3D orientation (owner) |
| Q-81 | 3D chrome: a floating control group (icon groups and a text group, labelled, before the viewport in the accessibility order, system material), facts in the strip, a one-time hint kept in process memory only, `NativeStateView` with a spinner during import and for viewport failures | DM-12, P12, DM R11 | P2 | M | partial | Q-35, Q-52, D10 |
| Q-82 | Listing models: `risks` and root facts parsed into `SafeListing`; stored size, mode bits and link targets reach the views; summary header and hidden counts | SV5, SV R4, 026 | P2 | M | partial | Q-64 (views) |
| Q-83 | MIDI: one 30 pt transport row with an icon Play/Pause, the no-autoplay sentence as help, time labelled "Playback position", palette ink, failures in the limits strip, interface updates at no more than 15 Hz | DM-23, CH-18, P17, DM R14 | P3 | S | yes | Q-33 |
| Q-84 | Keep the 3D camera across live reload when format and bounds match | DM-27, DM R16 | P3 | S | yes | none |

**C-companion (ux-companion).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-90 | Honest, failure-aware status in one home: `SettingsStatus` from storage mode, save state, recovery and loading; neutral or caution only; General's pill and green banner removed; the storage card only for problems; the enabled-type count out of the footer | CO-02, CO-03, C2, C4 | P2 | S | yes | Q-06 strings |
| Q-91 | Undo for the eight overwriting actions through `CompanionSettings.perform`, restoring only the replaced slice; an inline Undo row announced to VoiceOver | CO-06, C6, 026 gate 9 | P2 | S–M | yes | amendment 1 |
| Q-92 | Pinned Theme sample: `PinnedSampleLayout` beside a scrolling controls column at 720 pt of content, on top below it; Profiles in the controls column; the refresh note under the sample reusing `settings.extensionRefreshNotice` | CO-04, C1, C10, PI-21, 026 gate 8 | P2 | M | partial | none |
| Q-93 | Setup trail: one numbered card with the System Settings button (`SMAppService.openSystemSettingsLoginItems()` first, the URL as fallback), step 2 naming the embedded extensions read from the app's own `PlugIns`, the conflict summary beside it, step 3 pointing at the Theme sample until D3 | CO-05, CO-07, C3, 026 gate 7 | P2 | M | partial | Wave 1 step 8, Q-90 |
| Q-94 | File Types: an `NSSearchField` representable with a view-scoped ⌘F, result counts announced, a short pattern summary with "and n more", counts and boxes hidden while loading | CO-09, CO-10, CO-22, C7 | P2 | S | partial | none |
| Q-95 | Page hierarchy with `CompanionTypography` (`.title2` semibold titles, `.headline` sections, `.subheadline` notes, never caption), About without the repeated name | C5, CO | P2 | S | yes | none |
| Q-96 | Theme controls cleanup: one visible label per control, a numeric field beside the size stepper, points formatted with locale digits, fixed-pitch families first, Save explained when disabled, the current profile marked, transfer errors in caution style, no fake traffic lights | CO-15, CO-16, CO-28, CO-29, CO-30, C8, C9 | P2 | S | yes | none |
| Q-97 | Try Preview: pane-wide drop, one Open button, the name in the header, a "Check this file" card from `PreviewFileFacts` (metadata only, proven by a spy reader that fails on any read), worded "Supported by SpacePane" | CO-21, C12, closest rivals 7 | P2 | M | partial | Q-32 (`primaryView`), Q-52 |
| Q-98 | Restoration and menus: last page in companion defaults, page name in the window title, the standard "Settings…" title per D23, "SpacePane Help" with a short help section, `info.circle` for About | CO-18, CO-19, CO-28, C13 | P2 | S | yes | D23 |
| Q-99 | Conflict markers per type after a scan ("Also declared by n apps"), the scan time, what the scan cannot see, `/Applications/Utilities` and one bounded subfolder level, platform directory APIs | CO-07, CO-25, PI-18, C11, PI R12 | P2 | M | partial | Wave 1 step 8 |
| Q-100 | Scheme gallery of twelve swatch tiles from a public `PreviewSchemeSwatch` accessor; menus kept for narrow widths | C9, 026 contract 2 | P2 | M | partial | Q-34 |
| Q-101 | Renderer pill from the `primaryView` catalog field | CO-08, 026 contract 2 | P2 | S | partial | Q-32, D1 |
| Q-102 | Error states with actions: Try Again on failed saves, Restore Defaults on recovery, specific loading labels, bodies that add information, storage problems at the top of Theme; a bounded save flush on terminate | CO-14, CO-17, CO-26, PI-17 | P3 | S | yes | none |
| Q-103 | About: Show License Notices revealing the bundled notices, the colour-scheme notice bundled, distinct link paths, link colour; a privacy-safe Copy Diagnostics | CO-23, CO-24, PI R15 | P3 | S | partial | q-platform for bundling |
| Q-104 | Hit targets and labels: whole-row toggles, 20 pt disclosure, clear and close targets, group containers, title case headers | AL10, AL R11, AL R16 | P3 | S | yes | none |
| Q-105 | Sidebar material: a behind-window `NSVisualEffectView` or a fixed `NavigationSplitView`, chosen after observation on 15 and 26 | CO-20, C14 | P3 | S–M | no | D23 |
| Q-106 | Per-format limits in help and hints from the registrations' budgets | CO, data 10 | P3 | S–M | partial | Q-32 |

**C-copy (ux-copy).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-110 | Failure title and body pairs for every case, bodies ending with the next step and the limit value where one applies; `settings.extensionConfigurationUnavailable` without developer wording | CH-10, P15, CH copy inventory | P2 | M | yes | Q-32, Q-23 |
| Q-111 | Apostrophe, period and length sweep (header strings at most 12 words), one string per copy event, jargon out of `preview.summary.*`, per-language typography rules (French spaces, Hausa glottal stop, Turkish suffix apostrophes) | CH-21, AL12, P15 | P2 | S | yes | Q-23 lints |
| Q-112 | Setup and guidance strings naming macOS's own controls per language from Apple's glossaries; English names where macOS ships no interface in that language; one separator; policy recorded in decision 008 | AL8, AL R8 | P2 | S | partial | D19 |
| Q-113 | Translator context for the 271 keys on generic comments, the two count placeholders explained, the Hausa and Kurmanji English leftovers translated, the review queue rebased on 924 keys with chrome, setup, state and failure strings first | AL13, AL R13 | P2 | M | partial | native speakers |
| Q-114 | The content-thumbnail switch subtitle rewritten (what may be drawn, withholding, misses, caches in both directions, sync if TH-09 holds) | TH-18, TH R12 | P3 | S | yes | D6 |

**C-thumbnails (ux-thumbnails).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-120 | `extensionBadge` on every reply from the matched catalog suffix, carried as `ThumbnailBadge`; never derived from the stem | TH-03, TH R1 | P2 | S | partial | amendment 1 |
| Q-121 | Shape with counts for CSV, TSV, SQLite, Parquet, Arrow, Avro, NumPy and record-shaped JSON: header band, column kinds, a count line with locale digits and "+" when partial, no cell values; amend decision 022 | TH-05, TH-01, TH R3 | P2 | M | yes | D6, Q-32 |
| Q-122 | Policy re-decision per type after the Wave 1 table: `none` for content-free binary types whose system icon is better; `generic` with badge and group symbol for secret-bearing text types; regenerated manifests | TH-02, PI-05, TH R4, PI R10 | P2 | S | partial | D7, Wave 1 |
| Q-123 | Concrete system identifiers for source suffixes from the Wave 1 `mdls` table; a catalog test that no registered thumbnail type is an abstract parent | TH-04, TH R5 | P2 | S | partial | Wave 1 |
| Q-124 | Transient fallback reasons answered with an error once the Wave 1 cache check allows; glyph only for policy decisions | TH-06, TH R6 | P2 | S | partial | D6, Q-40 |
| Q-125 | A picture budget for picture formats, a first-picture-only request option, AVIF in the decoder | TH-08, SP-17, TH R7 | P2 | M | yes | Q-10 |
| Q-126 | Page metrics capped near 80 × 45 cells with the font growing past 15 px, one-device-pixel strokes, one page rect, muted at 5.0:1 | TH-10, TH-11, TH-13, TH R8 | P3 | S | yes | none |
| Q-127 | Draw what the text says: drop format-category scalars from drawn runs or withhold, skip comment blocks, figure or cells for notebooks per owner | TH-14, TH R9 | P3 | S | yes | D6 |
| Q-128 | Mermaid and draw.io drawn with `SafeDiagram` from a UI-free target or an injected drawing closure | TH-15, TH R10 | P3 | M | yes | lead module move |
| Q-129 | A thumbnail purpose on the request: skip the hidden-content scan, read preferences only after a `content` policy, a prefix sized to the page | TH-16, TH R11 | P3 | S | yes | Q-32 |
| Q-130 | Tests: one end-to-end sample per content format, real-adapter pictures, the adversarial corpus through the thumbnail service, badge and grid pixel probes, count formatting in four locales; probe flags for scale and icon mode | TH-19, TH R13, TH R14 | P2 | M | yes | Q-120, Q-121 |
| Q-131 | Synced-file policy once TH-09 is verified | TH-09, TH R15 | P3 | M | partial | D6 |

**C-performance (q-performance).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-140 | Lazy or prefetched secondary models decided from cheap facts; a fast safe JSON scanner without `JSONDecoder` per string or a regex per scalar; records numbered while parsing; the old scanner kept as a test oracle | PF-02, PF-17, PF R3 | P2 | S–M | yes | Q-32 (counts from the pipeline) |
| Q-141 | Style signature skipping the storage pass and layout when nothing changed; role attributes as `NSDictionary` built once; base plus tokens applied in one edit | PF-03, PF-08, PF R4 | P2 | S | yes | none |
| Q-142 | Viewport-first layout in TextKit 1: visible rectangle first, an estimated frame from the line index, background completion, an exact frame on completion; full layout only where exactness is required; the layout-pass tests extended | PF-01, PF R5 | P2 | M | partial | Q-24, Q-141 |
| Q-143 | Render inputs prepared off the main actor (`PreparedPresentation`, `display(prepared:)`), generation races dropped | PF R7 | P2 | M | partial | Q-31, Q-140 |
| Q-144 | Link hygiene: `HostedConfiguration` out of `PreviewRenderers`, the thumbnail target no longer linking the renderer module, `NativePreviewPane` in the app; `otool -L` on a Mac | PF-13, AR-15, PF R10 | P3 | S | partial | Mac |
| Q-145 | Live-reload fast paths: byte-identical results skip display; exact-prefix appends extend storage, tokens and the line index | PF-11, PF R11 | P3 | S | partial | Q-142 |
| Q-146 | Hot-loop fixes: key decoding without `JSONDecoder` when escape-free, byte scanning in the per-line privacy pass, coloring the leading 20,000 JSON tokens, views created on first use, Metal state cached per process, formatters and action names built once, exact UTF-16 comparisons on reload, the MIDI update rate | PF-09, PF-10, PF-12, PF-14, PF-15, PF-17, PF-19, PF R12 | P3 | S | yes | none |
| Q-147 | Module split, measured: `PreviewDiagrams` as the pilot, then `PreviewLocalization` and `PreviewPresentation` only if clean and incremental build times justify it | AR R12 | P3 | L | no | Wave 3 complete |

**C-safety (q-safety).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-150 | One hidden-character owner for names and decoded text: `HiddenCharacters.spans` in archive and folder listings, decompressed and ebook text reported with an encoding so it is scanned, classifier ranges extended | SP-08, SP R9 | P2 | M | yes | none |
| Q-151 | Surface-wide concealment canary suite: one canary document per family through every mode, copy path, tooltip, accessibility value, findings text and thumbnail scene; the adversarial checks extended to derived models and image labels | SP-16, SP R8 | P2 | M | yes | Q-39 |
| Q-152 | Structure-aware `--extended` corpus (bombs, nesting, hostile names, long lines, invalid UTF-8, canaries) under AddressSanitizer; libFuzzer harnesses per pure-Swift entry point, 30 s in `--test` and 10 minutes nightly | SP-16, SP R10 | P2 | M | partial | Q-21 nightly job |
| Q-153 | Dataless files never materialized: the I/O policy set in both extensions, `SF_DATALESS` checked after `fstat`, `EDEADLK` mapped to unavailable content | SP-06, SP R6 | P2 | S | partial | Mac provider check |
| Q-154 | Image decode limits: previews at about 40 megapixels, serial decoding above 16, one owned image-type list; a footprint test on a Mac | SP-07, SP-17, SP R7 | P2 | S | partial | Mac |
| Q-155 | Copy hygiene for invisible payloads when the Safety Lens found them; amends decision 012 | SP-09, SP R12 | P3 | S | yes | D15 |
| Q-156 | Try Preview CAD through an app-embedded XPC service, or no CAD in Try Preview | SP-14, SP R15 | P3 | M | partial | D24 |

**C-a11y-l10n (q-a11y-l10n).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-160 | Chrome text follows the preview text size through `PreviewChrome`; "200 %" defined as 26 pt content plus macOS Zoom and Larger Text; layout tests at 13 and 26 pt, 400 pt wide, in 14 languages with a test-only language override | AL9, AL R10, 026 gate 10 | P2 | M | partial | Q-33 |
| Q-161 | Right-to-left readiness: gutter numbers aligned toward the text by layout direction, direction-neutral separators in strings, page arrows in reading order, the MIDI slider kept left to right, File Types rendered in forced RTL | AL18, AL R15 | P3 | S | partial | none |
| Q-162 | Language-selection evidence: preference cases added to the bundle check, per-app language for the companion against a Finder preview observed and documented in decision 008 | AL16, AL R14 | P3 | S | partial | D26 |
| Q-163 | 3D failure text as the viewport's value, presets announced; diagram accessibility children cached | AL17, AL note | P3 | S | yes | Q-36 |

**C-platform (q-platform, lead).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-170 | Machine-readable host matrix (`docs/validation/host-matrix.json`), `script/check_host_matrix.py`, and the website's routing sentences drawn from it | PI-01, PI R14 | P2 | M | partial | Wave 1 data |
| Q-171 | OCCT route: a packaging script that publishes the worker sources, the pinned archive, the manifest edits and the build script with a written offer, or a 1.0 build without CAD | PI-09, PI R11 | P2 | M | partial | D20 |
| Q-172 | Store readiness: the 1.0 language set, localized store text drafted from the catalog, `web/` deployed, the support mailbox created, screenshots scheduled after the gates | PI-11 | P2 | M | partial | D22, Wave 4 |
| Q-173 | Generator drift: retire `script/generate_project.py` or bring it back in line with the checked-in project and check it | AR-09 | P3 | S | partial | D25 |

**C-website (website).**

| ID | Item | Evidence | Pri | Effort | Mac | Depends on |
|---|---|---|---|---|---|---|
| Q-180 | The live demo's provider caption replaced by a demo info symbol; the privacy lede aligned with "likely secrets"; the static privacy page date corrected | PI-07, PI note, PI-11 | P2 | S | yes | Q-09 |
| Q-181 | Real Finder-sized screenshots in both appearances after Wave 4, and the "press Space" demo matched to the shipped chrome | closest rivals 10 | P3 | M | no | Wave 4 |

## Acceptance gates

Decision 026's twelve gates stand as amended above. The program adds:

13. **Performance.** On the re-baselined host and fixtures, warm first-screen p95 for text, JSON, CSV and source does not regress by more than max(10 ms, 5 %) at any chrome change, and after C-performance lands it meets the 200 ms warm target for the ≤256 KiB fixtures; no appearance callback, mode return or zoom step performs a full layout pass when nothing changed (deterministic guards); the physical footprint of one hosted 230 KB JSON preview is recorded.
14. **Safety.** The canary suite reports zero escapes across every surface; the recall corpus records recall and the false-positive rate against the ceiling the owner set; the extended corpus and the fuzz harnesses run without a trap or sanitizer report for the recorded time.
15. **Liveness.** With as many blocked readers as cores, every thumbnail request still answers within 1.5 s and the preview host reaches its timed-out state; a 500-file folder on an SMB share settles without a permanent glyph for a small content file.
16. **Accessibility.** VoiceOver in both hosts reads facts, findings, mode control, bars, content and limits in that order and announces each state, copy and filter result once; every chrome ink, companion hint and accent text measures at least 4.5:1 (7:1 in High Contrast) with non-text cues at 3:1, enforced by tests; the listed shortcuts work on US, AZERTY, Russian, Hindi, Bengali and kana layouts; Space, Escape and the arrows always reach Quick Look.
17. **Localization.** Every count is plural-correct and uses one digit style per locale; the lints find no English leak, no straight apostrophe where the language uses curly, and no chrome string over budget; setup text names macOS's own controls per the recorded policy; the review status of every language is recorded before it is advertised.
18. **Platform.** The host matrix covers every advertised format on the production identity on macOS 15 and the current release with one competing provider; the TestFlight-signed build previews STEP and IGES; the companion and both extensions launch on the oldest supported 15.x; the measured widths set the compact threshold.
19. **Thumbnails.** A per-type Finder table shows a content miniature, a badged generic page or the system icon for every registered type and never a type-less placeholder; no thumbnail draws app-made text or, pending D6, cell values; a burst leaves no permanent timeout glyph.
20. **Release.** Privacy manifests present and checked; the archive check passes with the exact entitlement sets; the OCCT route is met or CAD is out of 1.0; store text exists in the chosen languages; the support and privacy pages are deployed and the mailbox answers.

## Owner decisions

Grouped by when an answer is needed. The five from the analysis keep their numbers. The same decisions are written as answerable questions, with options, the lead's recommendation and what each blocks, in [the owner questionnaire](../reviews/2026-10-06-quality-review/owner-questions.md).

**Before Wave 0 ends (cloud work waits on these).**

- **D8** Plural forms: build `.stringsdict` tooling for 14 languages (recommended; the facts strip, limits strip and privacy row need it), or keep label-colon notation in chrome (CH-9, AL2, SV20).
- **D13** How much over-concealment is acceptable for better recall, what false-positive ceiling the recall test enforces, and whether URL credentials and the new token formats get their own finding kinds (SP R1, SP R3).
- **D14** May a content thumbnail be withheld when the concealed text or the file name merely looks credential-bearing (SP R4)?
- **D6** Thumbnails: shape-only tables and databases (amending decision 022), whether a declined thumbnail answers with a badged glyph or an error, text, shape or glyph for files in synced folders, and whether the switch stays on by default (TH).
- **D16** May notebook Source show inert placeholders instead of exact base64 for image outputs (DM R9)?
- **D17** Package formats open on Summary (decision 017) or Files; the SQLite data grid with a table picker in scope; Invisibles out of the segmented control (SV).
- **D18** Citations: record the English style-guide terms as an exception or localize them (AL14).
- **D19** Setup copy for Bengali, Kurmanji and Hausa: English system names, translated with English in parentheses, or translated only; Apple's names for Quick Look in de, fr, es, pt and ru (AL8).
- **D15** May copy actions strip invisible Unicode Tag characters when the Safety Lens found them, amending decision 012 (SP R12)?
- **D25** Continuous integration on hosted macOS runners as a required check; a development-only Python dependency (`tree-sitter`, `tree-sitter-swift`) for the syntax gate; the `NativePreviewView` decomposition finished before any workstream branches; `script/generate_project.py` retired or repaired (AR).
- **D5** (reframed) The website makes no STEP exclusivity claim; decide whether the hero keeps the STEP tile while STEP is off by default, and accept "when macOS uses SpacePane for the type" on every routing sentence (PI-20, PI-19).

**Before Wave 2 (the contracts wait on these).**

- **D1** Which of JSON, YAML, TOML, XML (and property lists, JSON Lines records, `package.json` summaries) open in a structured view first; the structured-views report lays out the evidence and three options; the Finder matrix's YAML row is re-run in Wave 1 first.
- **D2** A prose face: a fixed system text face with no setting, or a selectable family in schema 7 with the migration the documents report lists (DM R6).
- **D9** Principle 2's scope: focus-scoped arrow keys allowed, Space removed everywhere (DM-07, AL15); the Wave 1 observation informs it.
- **D10** The overlay exception for the 3D control group and margin copy buttons; dimensions in the facts strip, not a chip (DM-14).
- **D11** The muted tier in Solarized Light, Solarized Dark and One Dark: accept muted equal to the foreground with a size cue, or allow darker published foregrounds (CH-7, AL7).
- **D12** The completion-handler policy after the Wave 1 experiment: keep Quick Look's spinner, or call the handler early and show SpacePane's state (CH-11, PF R8, PI R2).
- **D3** A bundled sample reveal from the setup trail, within the sandbox.
- **D7** After the Wave 1 thumbnail table, `thumbnail: none` for folders, apps, disk images, installers, archives, torrents and MIDI (PI-05, TH-02).
- **D4** Content-true 3D thumbnails for STEP and IGES and the 3MF package picture, with the evidence in the thumbnails report (a CAD import costs about 0.5–1.1 s against a 1 s hard limit; geometry has no text to conceal; the thumbnail extension would need its own service).
- **D23** Command-comma's title and destination; the sidebar material route on macOS 26; the conflict scan on demand or on first appearance; a metadata-only file check outside Developer Mode (CO).
- **D24** Try Preview CAD through an isolated app-embedded XPC service, or Finder-only (SP-14).
- **D26** Finder previews following the companion's per-app language (a snapshot field) or each host following its own setting, documented (AL16).
- **D-chrome** May provenance notes move into the info panel; may the gutter hide in compact density when line numbers are on; do the outline and table filter bars open on demand (CH).
- **D-3D** The default up axis for STEP, IGES and PLY, and whether a per-view up-axis toggle is wanted (DM-10).

**Before Wave 4 (release).**

- **D20** CAD in 1.0: meet the OCCT obligation by publishing the worker sources, the pinned archive and the build script with a written offer, or ship 1.0 without STEP and IGES (PI-09).
- **D21** If macOS 15.0–15.3 cannot load the build, raise the minimum to the first 15.x that works or replace `isolated deinit` (PI-03).
- **D22** Ship all 14 languages while 13 are drafts, knowing the store lists them, or only reviewed languages (PI-11).
- **D27** A TestFlight round before submission: the only way to test the store-signed CAD peer requirement and the cleanest way to reach macOS 15 (PI-02).

## Progress log

Entries are written by the session that made the change and say where it was verified. "cloud" means authored without a compiler; a Mac session or the macOS job moves the row in the pending queue and records the outcome.

| Date | Items | Where | State |
|---|---|---|---|
| 2026-10-06 | Owner decisions D1–D27, D-chrome and D-3D answered in the owner questionnaire; `AGENTS.md` "Working without a compiler"; decision 026 amended | cloud | documentation |
| 2026-10-06 | Q-18, Q-19, Q-20, Q-21 (static gate, syntax gate with baseline, ownership table and tool, CI workflow with a manual or `[ci-mac]`-tagged macOS job), Q-23 (plural tooling, `PreviewStrings.count`, `.stringsdict` generation, lints), amendment 2 (additions files) | cloud; Python tests run on Linux | implemented, macOS job and Mac run pending |
| 2026-10-06 | Q-01, Q-02, Q-03, Q-04, Q-05, Q-06, Q-07, Q-08, Q-09, Q-10, Q-12, Q-13, Q-14, Q-180; `TextOrigin` from Q-32 | cloud; syntax gate and static gate only | implemented, unverified (pending queue) |
| 2026-10-06 | Q-32 contract additions (`unsupportedVariant`, `geometryTooComplex`, `GeometryUnitProvenance`, `PresentationFacts`); first macOS job run (repository checks green; one compile error fixed) | cloud; macOS job | implemented, build pending |
| 2026-10-06 | Hosted macOS job: package builds, app and extensions type-check, 2,577 tests in 249 suites pass; five toolchain and host differences fixed (private memberwise init, self-shadowing local, `#expect` comment type, third-party-declared `org.bittorrent.torrent`, host-dependent notebook conformance); shared static test contexts made per use | macOS job (Xcode 26.6, macos-26) | Wave 0 compiled and tested on the runner (run 19, every step green); Finder observation still pending |
| 2026-10-06 | Round 2: Q-30, Q-33 to Q-38, Q-40, Q-43 to Q-46, Q-11, Q-27, Q-75, Q-80, Q-91, Q-95, Q-96, Q-98, Q-110, Q-120, Q-127 (ten workstreams; see the changelog) | cloud; then the macOS job: package, app and extensions compile, 2,942 tests in 291 suites pass (run 31), the companion contrast check is the last open step | implemented; compiled and package-tested on the runner; Mac observation pending |
| 2026-10-07 | Round 2 contrast fix (`CompanionInk.hintInk(for:)`, a dynamic hint colour); Round 3 ownership (`ux-tables`, `ux-setup`) | cloud; macOS job run 33 (workflow dispatch, full): package, app and extensions compile, every package test and integration check passes, the contrast check measures 148 ratios at 4.5:1 or better | compiled and package-tested on the runner; nothing observed |
| 2026-10-07 | Reconciled PR/local history through `f391354`, merged the independent website changes from `master` (`3339304`), synchronized the npm lockfile, added the remaining-work plan and Round 3 queue entries | Mac session; scoped synchronization checks in [the dated record](../validation/quality-program-sync-2026-10-07.md) | no implementation wave or signed-host gate closed; cancellation timing and missing companion integration sources remain open |

## Risks

| Risk | Mitigation in this record |
|---|---|
| Swift authored without a compiler breaks the build for days | Continuous integration (Q-21), the static and syntax gates, the queue, small batches, the blind-authoring rules |
| The hosted runner's Xcode cannot compile the package | The first run tells; the `xcode-27` label is the fallback; Mac sessions remain the final gate |
| Finder never delivers popovers, tooltips or key equivalents to the extension | Wave 1 spike before design freezes; inline fallbacks in the contract (amendments 6, 8, 10) |
| The decomposition of `NativePreviewView` regresses behaviour | Test seams first (Q-30), one move per commit, each compiled and tested before the next, the single-layout-pass invariant kept |
| Plural tooling takes longer than the strings that need it | Label-colon notation stays the fallback (D8); no count sentence lands before the tooling |
| Owner decisions stall the waves | Each decision names the items it blocks; everything else proceeds |
| Measurements on one host are not representative | The benchmark compares interleaved runs on the same host; a second machine and a VM cover macOS 15 (Wave 1, Wave 4) |
| The store-signed build behaves differently from development signing | A TestFlight round (D27) before submission |

## What is not promised

That Finder routes any type to SpacePane, that Quick Look delivers key events, tooltips or popovers, that translated wording is native quality, that the 200 ms target is met on hardware other than the record host, that App Review accepts the submission, or that the hosted runner compiles the package on its first run. Each is observed and recorded, never assumed.

## Rejected

Everything decision 026 rejected stays rejected. In addition: a web renderer for reading documents; TextKit 2 as the first step of the layout work (a later spike behind the same tests); live mini-sample panes for the scheme gallery (twelve native panes restyled on every edit); localized pictures of System Settings (28 images that go stale); "Open With → Change All" guidance as a routing remedy (unverified premise); reordering `addSubview` to fix the accessibility order (breaks 32 test lookups; the navigation-order override is used instead); a crash-reporting SDK; and any status wording, colour or marker that says or implies Finder uses this provider.
