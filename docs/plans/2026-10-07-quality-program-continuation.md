# SpacePane remaining implementation plan

Implementation order for the remaining quality-program work after synchronizing [PR #12](https://github.com/canburaks/prev/pull/12) and the local worktrees. The [sync validation record](../validation/quality-program-sync-2026-10-07.md) records the completed synchronization and website checks. Milestones below remain open unless an individual administrative step is explicitly recorded as completed.

## Evidence boundary and completion rule

The native source inventory below uses PR head `f391354cf9e1b77c4c407c7ecf359f9d05361981`. The synchronized tree adds master `33393045f85167584ea21a4cf9708dc6716a40a2`, including its website motion, language-menu and Safari date work; the synchronization changes no native code. The sync validation records npm ci/check/build, 42 production Chromium hydration loads and static gates; retain the missing tree-sitter skip and recorded visual-reference drift as limitations, without rerunning these checks merely to reconstruct history.

[Decision 027](../decisions/027-best-in-class-quality-program.md) amends and absorbs [decision 026](../decisions/026-world-class-ux-program.md). Decision 027's Waves 0–4 describe dependencies and acceptance. Actual Rounds 1–3 describe the batches already authored; they are not equivalent to those waves. The remaining batches S0–S6 below preserve that distinction.

The backlog contains **133 actual Q-items**. Q-181 is the highest identifier, not an item count. Every identifier appears once in the coverage table.

Evidence states remain independent: implemented source; package-tested; compiled on a named toolchain; observed in the signed companion or a named Finder surface; release-verified. Existing source and a historical green run never close a later commit's gate. At the initial audit, the last complete green documented run was hosted run 33 at 8ce6ec7. Run 40 at 1b7d392 compiled the package, app and both extensions and ran 2,946 tests in 293 suites, but failed the thumbnail cancellation timing assertion. Head run 41 at f391354 ran the static job and skipped the macOS package job. That historical baseline failure is repaired as recorded below.

S0 update: `a063847` repaired the cancellation check and recovered all three missing integration files; the full local entrypoint and [hosted macOS run 37648392943](https://github.com/canburaks/prev/actions/runs/37648392943) passed. Subsequent implementation and validation are tracked in [the implementation record](../validation/quality-program-implementation-2026-10-07.md); rows without later evidence retain the historical starting point. The latest integrated local checkpoint `3862820` passes 3,355 parallel tests in 364 suites, six isolated timing tests and every native integration executable. Its unchanged production sources pass all four host-source compiler checks; all 22 portable steps pass without skips. This includes Q52 facts, Q53 inline information and Q55 compact mode/gutter behavior. The completed full hosted static/macOS run [37899995290](https://github.com/canburaks/prev/actions/runs/37899995290) passes the compact-header checkpoint `e798e9c`; it does not validate the October 9 additions.

The program finishes when the amended decision 026 gates and decision 027 gates G13–G20 have their required evidence, every included deliverable is complete or explicitly deferred with a reason, and the pending Mac queue is empty. Source-present rows below are not checked acceptance boxes.

## Merge readiness decision — 2026-10-10

The user asked for [PR #12](https://github.com/canburaks/prev/pull/12) to be made ready to merge. The PR head carries `master` (`3339304`) with no conflict, has no open review threads, and hosted macOS run 115 on `8fb7383` is green (build, app and extension type-check, 3,701 parallel tests in 416 suites with 2 recorded known issues, 74 serial wall-clock tests, every integration executable). Those are the merge criteria for a development branch under decision 027: a hosted compile and package tests. Merging does not close any S2 signed-host or S5 release gate, does not check a plan box, and does not remove a "verification pending" sentence; the 2026-10-10 queue rows list the Finder, VoiceOver, macOS 15 and layout readings a Mac session still owes, and the two `withKnownIssue` expectations (Q-72 RTL tab stops, Q-74 zero-host container tracking) stay visible in every run until then. The GitGuardian check on the PR reports synthetic credential fixtures in privacy tests; they are deliberate, documented test inputs, not live secrets.

## Latest local integration — 2026-10-09

Clean `9134675` passes 3,444 parallel tests in 378 suites, six isolated timing tests, every native integration executable, the package/four-host compiler check and all 22 static checks without skips. This includes guarded classification, both extension process entrypoints and revision-bound safe code copying. The latest full hosted static/macOS run [37904351897](https://github.com/canburaks/prev/actions/runs/37904351897) passes the earlier `1c5747d`; it does not cover the later random-access, code-body, classifier/bootstrap or safe-copy changes. Signed `ed97406` builds, verifies and launches, with 33 bundle-language cases passing, but predates safe-copy source. Signed `3a97e4f` remains the latest observed Finder artifact. See the implementation record for exact logs and limits.

## Immediate work resumed — 2026-10-09

Current clean local checkpoint `389ebcb` passes 3,486 parallel tests, six isolated timing tests, every native integration executable, all four host-source compiler groups and 22 static checks. Monitor/reloader/host lifecycle, native cards, code context-menu copying and selected-folder root refusal are integrated. One owned wholly-dataless iCloud fixture remains offloaded across guarded reads, monitor/pipeline refusal and parent metadata listing. Child-directory/bundle integration, margin buttons/highlighting/remaining document stages and the fixed image comparison continue; no host acceptance gate closes from this checkpoint.

The user explicitly requested finishing the three immediate workstreams: dataless-file safety (monitor/rearm/directory integration and provider proof), document presentation (code cards/copy/highlighting and remaining block/Contents/page/diagram work), and image-memory validation/optimization. The stop below is historical. Preserve the existing boundaries and separate implementation evidence from host acceptance. Other backlog groups remain outside this resumed scope.

## Historical second development stop — 2026-10-09

The user requested stopping after the active tasks. The monitor descriptor-owner tranche is complete at `40ec8b5`: 40 related Debug tests, nine optimized Release tests and all 22 static checks pass. The failed cache measurement and current ignored drafts are preserved; synchronize this checkpoint and stop. Do not install the monitor Core/event/rearm follow-up or native code-card drafts, rerun the cache experiment, or begin another backlog batch without a later request. The descriptor owner is a tested internal foundation; production monitor integration remains open. The earlier resume and October 8 stop below are historical.

Local ignored handoff: `.build/quality-work/q153-resume/monitor/` holds the uninstalled Core/event and rearm work; `.build/quality-work/q72-code-card/` holds the approved narrow wrapper and five uncompiled RED tests; `.build/quality-work/q154-footprint/experiments/candidates/` holds the frozen failed measurement and separate refusal-only protocol/test preparation. These drafts are not shipped, compiled or accepted evidence. Preserve their manifests and review against the then-current source before any later installation.

## Development resumed — 2026-10-09

The user explicitly resumed development. The October 8 stop below is historical. Q153 now has an isolated checked dataless-policy wrapper (`97a60b7`, `f45d307`) with 14 Debug/Release tests and complete/leading reader integration (`bc83c18`) with 27 focused/native controls; random-access integration (`0cc43d7`) now passes 50 related Debug and 12 Release tests; guarded classification (`47dd6ed`) and both extension request entrypoints (`ed97406`) are integrated; monitor/rearm, directories and provider observations remain. Q154 cache/draw attempts remain rejected on native layout/geometry validation, with raw evidence retained and no production memory policy changed. Q72 quote/emphasis integration (`2f24f0f`) passes 98 focused/nearby tests, including actual bar pixels and narrow RTL/LTR wrapping. No host or release acceptance gate is closed by this checkpoint.

## Historical development stop — 2026-10-08

The user requested stopping after the current tasks. Compact-header implementation and validation are complete locally; synchronize the PR and then stop. Q55 still needs signed-host/VoiceOver and measured density acceptance. Do not automatically begin Q154's prepared cache/draw experiment, Q153's uninstalled file-access policy, Q72/Q73 reading improvements or the other remaining batches. The ignored local drafts remain preparation, not shipped or verified behavior. A later user request is required to resume development.

## Approved decisions and invariants to preserve

- Preserve the production identity org.webmeister.spacepane and App Group Z743N6D8DS.org.webmeister.spacepane.shared. Visible branding is replaceable; format IDs, storage and technical identities are stable.
- Keep one native companion window with General, File Types, Theme and About, plus Developer Mode-only Try Preview. Settings… selects General; SpacePane Help selects About. Do not add a Settings scene, second window or automatic provider scan.
- Processing remains local, read-only, bounded and cancellable. Disabled formats stop before parser construction and cannot fall through to generic text. Source, clipboard, accessibility, search, images and thumbnails obey the shared privacy policy.
- D1: JSON and property lists open in Outline when it exists, otherwise Source; JSON Lines opens in Records; package.json in Summary. YAML, TOML and XML retain Source until their subsets and the Wave 1 evidence justify a recorded change. Apply default-first ordering through one mode policy after the measurement.
- D2: Rendered prose uses the system text face at the configured size; code uses the chosen code family. A selectable prose family/schema 7 is deferred.
- D3/D4: no bundled sample reveal in Finder and no content-true CAD thumbnails for 1.0. Setup step 3 can point to the Theme sample.
- D6/D7: tables and databases use shape/count thumbnails without cell values; content thumbnails remain on by default. Use badged glyphs for policy decisions, conditional transient-error replies after the cache experiment, and system icons where the host table proves they are preferable. Synced-folder behavior awaits evidence.
- D8/D13/D14: plural tooling is approved; broader concealment targets at least 95% positive recall with at most 2% false-positive ordinary-text lines; URL credentials/new formats use the existing sensitive-value kind for now; secret-shaped thumbnails may be withheld.
- D9/D10/D-chrome: Space and Escape belong to Quick Look; arrows are focus-scoped and tested in hosts. Only the floating 3D group and margin code-copy buttons are approved overlay exceptions. Dimensions appear once in facts. Filters open on demand behind a visible search affordance; compact mode may hide the gutter; provenance can move to the info panel.
- D11: Solarized Light/Dark and One Dark retain published foregrounds with a size cue where muted cannot be lighter while meeting contrast.
- D12 remains deliberately empirical: choose the completion policy after the Mac experiment; a roughly 150 ms grace period is a prior, not an implemented or approved measured value.
- D15/D16/D17/D18/D19: approved tag-payload copy hygiene; inert notebook image placeholders with figures in Pages; package Summary and SQLite data grid/table picker; Invisibles can leave the five-segment control; citation style-guide English terms have a documented exception; setup system names follow the recorded language policy and actual macOS labels.
- D23/D24/D26: conflict scans stay on demand, the file inspector stays in Developer Mode, companion CAD isolation uses an app-embedded XPC service at lower priority, and each host's effective language is documented without a preferences schema change.
- D20/D21/D22/D27: meet the OCCT source/relinking route with legal review or exclude CAD from 1.0; raise the macOS 15 patch minimum only if runtime evidence requires it; advertise only reviewed shipping languages; TestFlight is required before submission.
- D25: retain deliberate manual or [ci-mac]-triggered macOS CI and push/PR Linux static CI. Decompose the renderer before further concurrent hub edits. Retire the stale project generator after a dependency inventory proves it is unused.
- Keep all 14 development resource sets and translator context. Human review determines the release language set. Never infer routing, cache refresh, App Review acceptance or translation quality from compilation.

The delegation recorded in [owner-questions.md](../reviews/2026-10-06-quality-review/owner-questions.md) already supplies the choices above. Do not ask the 29 questions again. Record evidence-dependent outcomes in their existing answer lines and decision records.

## S0 — stabilize the synchronized branch

Dependencies: PR/local synchronization and conflict resolutions owned by the lead. Exit: the exact integrated SHA containing the repairs has a full green portable gate, compiler gate, package suite and every integration executable.

1. Administrative synchronization is completed in the linked sync record: master was merged, conflicts resolved, locks reconciled and records updated. Preserve this baseline and record each implementation batch against its exact commit.
2. Reproduce ContentThumbnailServiceTests.cancellationAnswersWithTheGlyphPromptly under the complete suite. Separate semantic once-only/cancellation behavior from incidental scheduler timing. Use the existing injected scheduler/clock seams or add a narrowly owned seam; retain a generous independently justified wall-clock safety check only where the product deadline itself is under test. Do not merely weaken the assertion until CI passes. Keep the Dispatch-driven reply and blocked-reader liveness acceptance intact.
3. Recover or implement the three committed-source omissions: Tests/Integration/CompanionLayoutChecks.swift, CompanionErrorStateChecks.swift and CompanionGalleryChecks.swift. The driver and CompanionModelChecks call them, but they are absent from f391354. Add meaningful regression checks for the actual pinned-layout/error/gallery models; do not remove the driver calls to conceal the missing coverage.
4. Run the missing integration stage after the package failure is fixed. A package pass alone is insufficient; the driver omission was hidden because run 40 stopped earlier.
5. Run the full hosted macOS job on the final repaired SHA, with a full-mode workflow dispatch if the commit lacks the trigger. Record test counts, toolchain, warnings and outcome. Run local --check, --check-compiler and --test before treating this as the implementation baseline.
6. The sync has added five exact-commit Round 3 queue rows and removed stale “nothing implemented” summaries. During recovery, separate compile/test closure from host observations and retain the older open rows and historical failures.

Team: lead plus one focused thumbnail/test specialist and one companion-model specialist. Their files are disjoint; the lead owns the common test driver, existing test files, resources and integration records. No feature expansion is concurrent with baseline repair.

## S1 — finish the shared foundations and measurement tools

Dependencies: S0. Safe to author from source, but cross-module edits and each refactor step require a Mac compiler before the next step. Exit: unused/additive contracts and enabling refactors pass the complete baseline.

- Q-24: add stage observation/signposts, physical-footprint collection, the missing CSV/listing/Markdown-with-Contents/.env-with-findings/1 MiB/log-append fixtures, interleaved A/B comparison and script/compare_benchmarks.py with portable statistical tests. Report medians with 95% bootstrap intervals, p95 and maximum, and use max(10 ms, 5%) as the regression bound. Preserve the distinction between core-pipeline timing and first visible native/Finder content.
- Q-30/Q-31: finish the seam audit and move NativePreviewView into PreviewStatePresenter, PreviewModePolicy, PreviewTextContentView and PreviewHeaderView in separate “move, then validate” commits. First establish tests against existing behavior; do not mix these moves with a visual change.
- Q-32: add a UI-free PreviewResult carrying the actual effective family budget and a pipeline entry point; forward the old overload during migration. Complete all callers, split limit/failure variants and use primaryView drift tests. Existing TextOrigin, PresentationFacts, unit provenance and primaryView are retained.
- Q-39: create the shared test-support target/builders and migrate duplication behind explicit ownership. Reuse the scheduler already added rather than adding a competing timer mechanism.
- Q-40/Q-41/Q-42: complete the preview timeout/host-session contract after S2's timing experiment; record the semaphore-versus-continuation exception or migrate with tests and measured cancellation/liveness. Add typed debug host events and repair log predicates without filenames, paths, source values or content.
- Q-34/Q-35/Q-37/Q-46: finish remaining palette-role migration, copy callbacks, empty structured-input policy and effective-budget state copy. Leave compact-width selection and Finder completion behavior empirical.

Team: lead owns PreviewContracts, PreviewCore composition, Package.swift, resources, host controllers and the renderer decomposition contract. At most three specialists: ux-chrome for the permitted renderer moves, q-performance for benchmark tooling, q-platform for host-event/verification tooling. The lead grants exact files before branching. A shared NativePreviewView edit is serialized.

## S2 — establish signed-host facts

Dependencies: S0 and benchmark tooling from S1 for a valid baseline; the host experiments may proceed while independent S1 tools are authored. This is decision 027's planned Wave 1, which has not been closed by Rounds 1–3.

Use a clean signed build on the production identity. Record host, OS build, hardware, Xcode/Swift, artifact SHA and competing providers. Preserve system preferences, caches and Finder.

1. Consume queue rows for plural formatting/resource embedding, signed companion changes, thumbnail policies, geometry, first-use APIs and real accessibility.
2. Observe panel, preview pane, column/Gallery, full screen and Spotlight where applicable: widths, safe-area geometry, title-bar overlap, focus, key equivalents, tooltips and popover delivery. Measure the compact threshold; replace the current 480 pt placeholder only from this evidence.
3. Compare completion on state installation versus content readiness/grace period. Record what Finder shows and first-content latency; decide D12 from the result.
4. Test Space/Escape/arrows and mode/find/copy/zoom chords on the specified keyboard layouts, after focusing each native presentation.
5. Run oldest supported 15.x runtime/symbol checks and current-release launch tests. Apply D21 only if a failure is demonstrated.
6. Fill per-format/per-surface production observations and thumbnail/system-icon/source-UTType tables. The current 76-format matrix is historical, from one retired-identity host; every Finder thumbnail is unobserved.
7. Test the System Settings route, bounded on-demand provider scan, real sandboxed file drop, app-quit/cold lifecycle, live reload and snapshot updates.
8. Verify VoiceOver baseline, actual plural resources and effective languages separately in companion/preview/thumbnail hosts; confirm Apple's localized setup labels.
9. Run the re-baselined native/host benchmarks and profiling on identical bounded fixtures. Record source integrity and physical footprint.

Exit: exact evidence records choose density, completion/info fallback, thumbnail fallback/cache/system-icon behavior, runtime baseline and benchmark baseline. Conditional decisions are resolved without repeating already delegated product choices.

Team: lead conducts and records host observations. One q-platform specialist can prepare fixtures/matrix tooling and one q-a11y-l10n specialist can prepare localization/keyboard protocols. Observations and machine-specific results have one owner.

## S3 — finish the user-facing work in small rounds

Dependencies: S1 contracts and decomposed boundaries. Host-dependent portions additionally wait for S2. Preserve Round 3 pinned sample/gallery/error states already in source and finish their missing coverage.

Batch A: ux-chrome completes facts/limits/privacy/info/density (Q-50–Q-56); ux-companion completes/verifies status, Undo, pinned sample, typography, gallery and recovery (Q-90–Q-92, Q-95–Q-96, Q-100, Q-102–Q-104); ux-documents completes notebook input and reading layout/code/Contents (Q-15, Q-70–Q-77). The lead integrates shared header/state/facts hooks; specialists do not concurrently edit NativePreviewView.

Batch B: ux-modes-structure completes default policy, typed outlines, paths, JSONL/cues and its filter portion (Q-60–Q-62, Q-66–Q-69); ux-tables completes grid extent/numerics/row gutter, row/filter parity and SQLite picker (Q-62–Q-65); ux-setup completes numbered General, native File Types search/markers/pills, pane-drop inspector and help limits (Q-93–Q-94, Q-97, Q-99, Q-101, Q-106). A single SafeFilterQuery contract is agreed first. Listing model/view work stays with ux-containers-3d, so Q-64 handoff is sequential.

Batch C: ux-containers-3d completes listing verdicts/risks/facts and the floating 3D/MIDI/camera work (Q-64, Q-81–Q-84); ux-thumbnails completes shape-with-counts, budgets/scaling/purpose and scene tests (Q-121, Q-125–Q-130), then applies S2's policy decisions (Q-122–Q-124, Q-131); ux-copy completes failure/budget/typography/setup/thumbnail guidance (Q-110–Q-114). Translator-input editing is serialized with q-a11y-l10n.

Whole UI acceptance: one header row when nothing needs saying; counts/limits come from real family facts and effective budgets; one capped findings row; accessible default-first honest modes; visible discoverability and copy feedback; pinned Theme sample at every supported width; Undo for overwrites; no redundant status or routing claims. Filters count against the chrome budget and open on demand.

## S4 — finish performance, privacy and accessibility

Dependencies: S1's measurement contracts and test seams; S2 baseline; stable S3 presentation models. Safety improvements that do not depend on the UI can proceed earlier after S0.

- Q-16/Q-150/Q-151/Q-155: add the missing credential grammars/positive and negative recall corpora, one hidden-character ownership path for names and decoded text, surface-wide canaries and approved Tag-copy hygiene. Assert zero escapes across all visible/clipboard/accessibility/thumbnail surfaces and the approved recall/false-positive targets.
- Q-152: extend structured adversarial fixtures, sanitizer coverage and bounded fuzz entry points. D25 retains deliberate manual or [ci-mac]-triggered native/OCCT execution; do not introduce a nightly schedule from the older proposal. Keep routine CI bounded. The explicit development-runtime pilot passed runtime/object instrumentation and a real ASan canary, but stopped because ZIP probes supplied no parser-attributed PCs. No seed replay/continuous fuzz or JSON result is accepted; execution and diagnosis are stopped.
- Q-153/Q-154/Q-156: prove dataless/provider no-download behavior, complete shared image decode limits/footprint and isolate companion CAD through the approved embedded service. Cross-target resource/entitlement changes require Mac builds.
- Q-140–Q-146: use cheap facts for lazy secondary models, scanner oracles, a style signature, viewport-first layout, off-main prepared render inputs and safe live-reload fast paths. Each optimization keeps byte-exact safe output and generation/cancellation invariants and is measured independently.
- Q-160–Q-163: finish chrome scaling and 13/26 pt × 14-language layout tests, RTL behavior across all direction-sensitive controls, cached diagram accessibility and actual effective-language documentation. Validate VoiceOver order and announcements once per event in both hosts.
- Q-147 is conditional: measure build/link costs after stable features, pilot a diagrams split only if justified, and record a deferral if it offers no demonstrated benefit.

Team: at most q-performance, q-safety and q-a11y-l10n plus lead. The existing ownership table intentionally overlaps SafeStructuredText, DefaultPrivacyFilter, image-limit files and translation inputs. Grant disjoint file subsets per batch; never let the performance and safety agents edit the same privacy/scanner file concurrently. The lead owns cross-module/public contracts and merges each measured change.

## S5 — close platform and release work

Dependencies: S2 policy/evidence, S3/S4 acceptance and exact final artifact.

- Complete Q-170's production host matrix and derive truthful website observations from it. Historical development results remain attributable to their retired identity.
- Complete Q-171: execute/review the source-offer packaging, remove placeholders, pin/check provenance, obtain the legal review and satisfy the publication/relinking obligation. The draft offer and packaging script are not publication. Apply the approved CAD-exclusion fallback if the obligation cannot be met before submission.
- Complete Q-172: reviewed shipping language set, accurate localized store copy, deployed web/support/privacy pages, working support mailbox and screenshots after the interface settles.
- Q-173 generator retirement is complete: the Mac dependency inventory found no callers, the stale signing-repair hint was replaced, the generator was removed, and Xcode target listing/project validation passed. See the implementation record; this does not close other S5 gates.
- Complete Q-181's real Finder-sized screenshots in both appearances and update the interactive demo to the final shipped chrome. Preserve the website's repository-established bento style and the independently merged motion system; update DESIGN.md for an actual style-default change.
- Verify privacy manifests in every actual bundle, exact archive entitlements, runtime flags, helper identifiers, allowed CAD clients and source notices. Run TestFlight CAD/oldest-OS tests before submission.
- Country pricing, commercial configuration, App Store upload and public deployment remain explicit release actions in the applicable authorized release task. This implementation plan does not execute them.

Team: lead plus q-platform, website and ux-copy/q-a11y-l10n, with copy and language resources assigned to one active owner. Real host evidence, legal review and speaker review cannot be replaced by agent source inspection.

## S6 — record completion

Run the amended G1–G12 and G13–G20 against the exact installed artifact. Record the performance confidence intervals/physical footprint, zero-leak canaries, recall floor and false-positive ceiling, blocked-reader deadline, keyboard/layout/VoiceOver matrix, source integrity, every advertised format/surface, TestFlight CAD and release checks. Close queue rows with exact validation-record links; then update checkboxes/status columns. A justified deferred P3 item has a recorded reason, owner and effect on advertised scope. No completion claim comes from a missing check, skipped CI job or intended driver call.

## Ownership and integration protocol

tools/ownership.json remains the base authorization table. Before each specialist batch, the lead records the exact active file grants and checks them with tools/check_ownership.py. Do not create a twelve-agent team: the largest useful batch is three specialists plus lead, and smaller baseline/host batches use fewer.

- Lead: contracts/core composition, Package.swift/project/configuration, extension hosts, generated catalogs/resources/typed strings, existing shared tests, PLAN/decisions/CHANGELOGS/queue, integration and validation.
- Renderer ownership: ux-chrome; ux-modes-structure; ux-tables; ux-documents; ux-containers-3d use their existing disjoint globs. NativePlot overlaps document/table ownership and is assigned to only one active batch. The original preview hub stays serialized until decomposition.
- Companion ownership: ux-companion owns appearance/settings/shell/stores/app; ux-setup owns General/File Types/direct preview/provider diagnostics. Shared CompanionRoute/app callbacks are integrated by the lead.
- Core/thumbnail/platform ownership: q-performance, q-safety, ux-thumbnails and q-platform use their listed globs with overlaps narrowed before dispatch.
- Strings: specialists submit tools/localization/additions/<workstream>*.json; the lead applies additions and typed cases/regenerates catalogs once. No parallel catalog writes.
- Tests: existing files stay with their established lead/granted owner; specialists add meaningful new tests named for their workstream. New files receive an ownership entry before parallel edits.

## Verification commands

Portable source gate and tooling, as applicable to the batch:

    ./script/build_and_run.sh --check-static
    python3 tools/check_swift_syntax.py --all --require
    python3 tools/check_ownership.py --audit
    python3 tools/check_ownership.py --workstream <assigned-owner> --base <batch-base>
    python3 tools/test_localization.py
    python3 tools/validate_localization.py
    python3 script/test_check_static.py
    python3 script/test_check_release_archive.py
    python3 script/test_check_host_matrix.py
    python3 script/test_package_cad_source_offer.py

Mac/compiler/integration baseline, using the configured Xcode:

    ./script/build_and_run.sh --check
    ./script/build_and_run.sh --check-compiler
    ./script/build_and_run.sh --test
    swift test --package-path Packages/PreviewCore --filter ContentThumbnailServiceTests
    swift test --package-path Packages/PreviewCore --filter 'CatalogPrimaryViewTests|CatalogPrimaryViewDriftTests|CatalogContentTypeResolutionTests'
    swift test --package-path Packages/PreviewCore --filter <batch-new-suites>

`--test` discovers the validation binary directory and passes it to the companion integration driver; do not invoke that driver without its required argument. Run test-first suites against old behavior for a meaningful failure, then the implementation. Timing changes receive an independently justified full-suite rerun; normal low-risk changes do not prompt unbounded repeated testing.

Rendering, signed hosts and release evidence:

    python3 script/benchmark_release_pipeline.py
    python3 script/benchmark_release_native_renderer.py
    python3 script/compare_benchmarks.py <interleaved-baseline> <candidate>
    ./script/build_and_run.sh --run-companion
    ./script/build_and_run.sh --verify
    python3 script/check_bundle_localizations.py --app <built-app>
    mkdir -p .build/quality-probes
    xcrun swiftc -parse-as-library script/probe_thumbnail.swift -o .build/quality-probes/thumbnail
    .build/quality-probes/thumbnail <synthetic-input-file> <new-output.png> --scale 2 --icon-mode
    ./script/build_and_run.sh --archive

The comparison tool and its portable tests are implemented; actual accepted A/B optimization results remain a separate gate. Signed observations follow the queue and decision 027's Mac protocol; inspect source integrity, accessibility and all host surfaces directly.

Website, after reading [web/README.md](../../web/README.md) and [DESIGN.md](../../web/DESIGN.md), from `web/`:

    npm ci
    npm run check
    npm run build

Start `npm run start -- --port 3100` from `web/` and `python3 -m http.server 4180 --directory Website` from the repository root in separate shells. With both servers running, execute from `web/`:

    npm run test:hydration -- --base http://localhost:3100
    npm run visual:compare -- --ref http://127.0.0.1:4180 --next http://localhost:3100 --sections header --widths 1440,375

Stop only the servers started for the check. Broaden visual sections when the change touches them. The sync's 42 hydration loads passed; the header reference differences of 1.50%/0.57% remain recorded drift. Preserve that distinction and do not relax thresholds to label divergence a pass.

## Exhaustive backlog coverage

Statuses: **S** = stated deliverable substantially present in source; **P** = partial source or incomplete source/test coverage; **R** = remaining implementation; **H** = observation-first/conditional work. S still requires exact-head tests and the applicable Mac/host gates. “Host” is closure evidence, not a claim that source is missing.

The initial audit used `f391354`. Rows with later implementation evidence have been reconciled, including the October 9 review of Q31/Q32/Q34/Q40/Q42/Q54/Q70/Q71/Q84/Q121/Q173 against the implementation record. Other rows retain the initial source audit; these source states never close observation gates.

| Q item | Source state | Remaining closure / planned batch |
|---|---|---|
| Q-01 | S | Shared URL-credential concealment and cross-family tests present; host/canary verification in S2/S4. |
| Q-02 | S | Image labels removed from the contract/tooltips; verify actual Pages accessibility in S2. |
| Q-03 | S | Origin-aware truthful table notices present; real partial CSV/data views in S2. |
| Q-04 | S | YAML compact-sequence correction present; re-run the host YAML fixture in S2. |
| Q-05 | S | Profile speech indexes sorted order; VoiceOver sorted/filtered Profile in S2. |
| Q-06 | S | Truthful File Types/setup/About copy and retired headings; signed multilingual layout in S2. |
| Q-07 | S | Localized converted-document labels/image markers; EPUB/FB2/MHTML host review in S2. |
| Q-08 | S | Citation English-term exception/notice recorded; verify References wording in S2. |
| Q-09 | S | Website routing/Apple-silicon/STEP honesty changes in 14 locales; S0/S5 browser evidence. |
| Q-10 | S | Pictures tried before summary-origin text refusal; real-adapter picture and fallback verification in S2. |
| Q-11 | S | Unit provenance/capped counts/complexity failure and worker-unit source present; CAD/locale/Metal verification in S2. |
| Q-12 | S | 7z count bounds, logger identity and safer worker extraction present; native-worker/archive checks in S0/S2. |
| Q-13 | S | Package/security summaries open in Summary; signed initial-mode checks in S2. |
| Q-14 | S | Conditional omitted-resource notices/BibTeX behavior present; real-mode notice verification in S2. |
| Q-15 | S | Bounded notebook byte input, inert image placeholders and saved PNG/JPEG figures pass focused and combined Mac checks at `7e062b9`; new image Pages/Finder acceptance remains open. |
| Q-16 | S | Expanded credential grammars and exact-code-unit compatibility are integrated through `070c91b`; the bounded recognition corpus reports 228/228 positives and 120/120 ordinary lines unchanged. Broader actual adapter/host exposure evidence remains in Q150/Q151 and S4. |
| Q-17 | S | Secret-shaped thumbnail withholding present; cache/privacy fixtures in S2/S4. |
| Q-18 | S | Portable static gate and self-tests present; exact synchronized baseline in S0. |
| Q-19 | S | Pinned syntax parser/baseline gate present; exact synchronized baseline in S0. |
| Q-20 | S | Ownership table/tool present; narrow overlapping grants before every S1–S5 batch. |
| Q-21 | P | Manual/tagged macOS and push/PR static CI present; full exact-head run S0, scheduled OCCT/native job S4. |
| Q-22 | S | Blind-authoring rules/risk/queue present; reconcile exact-SHA queue rows in S0. |
| Q-23 | P | CLDR/count API/catalog generation/lints present; finish language lint coverage and runtime plural resource proof in S2/S4. |
| Q-24 | S | Bounded Release fixtures, pipeline/native stage hooks, physical-footprint probes, fingerprints and the tested interleaved comparator are implemented. Measured image experiments are recorded; optimization acceptance and real-host/process totals remain separate. |
| Q-25 | S | Status matrix/index/count/README hygiene done with link-preserving documented exceptions; remove stale progress summaries in S0. |
| Q-26 | S | Decision 026 amendments and owner answers recorded; refresh stale “proposed/nothing implemented” wording in S0. |
| Q-27 | S | Hardened archive checker and synthetic tests present; exact signed/archive/profile-injected validation in S2/S5. |
| Q-30 | P | Named seams/helper and 82 lookups migrated; audit remaining direct lookups before S1 decomposition. |
| Q-31 | S | Four focused renderer components are extracted and compiled/tested in S1; retain facade invariants and verify actual host density/completion behavior. |
| Q-32 | S | Origin/facts/unit/failure/primaryView contracts and effective-budget PreviewResult/caller migration are implemented; verify actual host budget and provenance presentation. |
| Q-33 | S | Chrome metrics/guides/slots/skeleton present; preserve during S1, validate safe-area layout in S2. |
| Q-34 | S | Renderer palette-role migration is complete, including image captions/placeholders and plot frames; actual signed-host color/contrast observations remain. |
| Q-35 | P | Shared state view exists; complete empty structured-file policy/effective-budget bodies and D12 Finder behavior in S1/S2. |
| Q-36 | S | Announcer/recorder/policy present; once-only real host speech in S2/S4. |
| Q-37 | S | Shared copy reporting/chip for text/outline/table/tree/Contents present; generation/clipboard/VoiceOver observation in S2. |
| Q-38 | S | Command table/key-code mode chords/focus handoff present; keyboard-layout/host delivery matrix in S2. |
| Q-39 | P | Injectable chrome scheduler exists; common test-support target/builders/duplicate migration in S1. |
| Q-40 | S | Worker/admission/reply/session timeout and isolated liveness checks are implemented; CAD synchronous wait exception is documented and tested. Host completion and blocking measurements remain. |
| Q-41 | H | Completion policy/PreviewHostSession waits for S2 experiment, then lead implementation in S1 closure. |
| Q-42 | S | Typed content-free host events and debug predicates are implemented in both extensions and compiled/tested; observe actual signed Finder unified-log delivery. |
| Q-43 | S | Linear cancellable concealment/oracles present; retain exact-output guarantees in S4 profiling/canaries. |
| Q-44 | S | Store-marker/team CAD peer requirement present; actual archive and TestFlight acceptance in S5. |
| Q-45 | S | Privacy manifests and validation source present; real bundle embedding/archive check in S2/S5. |
| Q-46 | P | Safe-area guides/density state/forced Theme density present; measured threshold and complete width behavior in S2/S3. |
| Q-50 | S | Collapsed pluralized summary, 25% scrolling disclosure, full bounded findings, copy-mode policy and action announcements pass focused Mac checks in `34ea9b6`; signed-host and translated/VoiceOver acceptance remain open. |
| Q-51 | S | Unified bottom-strip limits, conservative row totals and cached listing notices pass full integration at `070c91b`; real-host layout/language acceptance remains in S2/S3. |
| Q-52 | S | Cached truthful family facts, existing-read sizes and the single-row four/two-scalar header pass full integration at `a73ac03`. Signed-host density/VoiceOver and reviewed language evidence remain open. |
| Q-53 | S | Native 22 pt information disclosure, bounded inline panel and live capability-based help pass full Mac integration at `bfcb7c1`; actual host/VoiceOver acceptance remains open. |
| Q-54 | S | Typed hierarchy transitions and localized mode labels are implemented with nine native regressions; actual VoiceOver order/delivery and signed Finder behavior remain. |
| Q-55 | P | Native compact pull-down, cached hidden gutter and two-fact row pass full integration at `3862820`. Selection, focus, viewport and no-reparse behavior are covered; measured threshold, signed-host/VoiceOver and future rail behavior remain open. |
| Q-56 | P | Generation-aware chip behavior exists; reading-position/notice/selection polish and host checks in S3. |
| Q-60 | R | Default-first/origin labels/five-segment policy and 76-sample policy tests in S3 after S2. |
| Q-61 | R | Typed nodes/glyphs/container counts/duplicate/null/truncated-value presentation in S3. |
| Q-62 | P | Existing filters/command/copy plumbing present; shared query, row menus, tree parity, shown-grid TSV and match semantics in S3. |
| Q-63 | R | Numeric alignment/muted row gutter/NULL/range footer/reload extent state in S3 tables. |
| Q-64 | R | Listing risk/name markers/icons/hidden and inaccessible facts in S3 containers, coordinated with tables. |
| Q-65 | R | SQLite data table picker/grid/honest extent footer in S3 tables. |
| Q-66 | R | Selected-row path bar and per-family paths/Copy Path in S3 modes. |
| Q-67 | R | Typed malformed-JSONL finding, record/gutter markers and concealed record summaries in S3. |
| Q-68 | P | Localization normalization exists; finish distinct Outline/Tree/Rows mode terminology and contexts in S3 copy. |
| Q-69 | R | Cues-first readable subtitle policy in S3 modes. |
| Q-70 | S | Markdown soft-break reflow, hard-break/structural boundaries and exact Source preservation are implemented and tested; real-host reading/selection/VoiceOver acceptance remains. |
| Q-71 | S | System prose face, leading, measure, wrapping, code face and reading-mode gutter/Go-to-Line policy are implemented and tested; signed-host and measured reading acceptance remain. |
| Q-72 | P | Native quote bars and body emphasis implemented at `2f24f0f` (98 focused/nearby tests). Alert bars, inline chips, measured table tab stops, heading scale and rules authored at `488a9e3` and compiled by hosted run 109 (RED `a08648d`); the RTL tab placement, chip contrast and host acceptance stay in the pending-verification queue. |
| Q-73 | P | Exact bounded code-body ranges and canonical typed language hints at `9274dfc` pass 186 related renderer tests. Native generation-bound safe copy at `762eb0b` passes 61 related tests. The code language label (`CodeLanguageName`, `NativeCodeLanguageLabels`) authored at `488a9e3` and compiled by hosted run 109; margin/context controls, bounded highlighting and VoiceOver acceptance remain. |
| Q-74 | P | Wide-pane Contents rail, policy and section tracker authored at `5d98b20` (RED `2a6c7db`) and compiled by hosted run 109; the start-of-text rule followed at `4f7fbb6`. Two layout readings (RTL flip, zero-host container tracking) and Finder/VoiceOver acceptance stay in the pending-verification queue. |
| Q-75 | S | Space removal/focus-scoped navigation/mode zoom present; host/keyboard verification in S2. |
| Q-76 | P | Localized page labels exist; chapter facts and the "Showing n of m chapters" notice, failed page frames, the Pages position in the limits slot and notebook figure lines with cell-group rules authored at `cfd7cc2` (RED `20ffd10`) and passed by hosted run 109. Real EPUB/notebook host observation remains. |
| Q-77 | P | Diagram legibility floor, selection receipt, plot notice and antimeridian framing authored at `da78704` (RED `8b0b9c5`) and compiled by hosted run 109; the Persian receipt wording and the 7 pt floor await Mac observation. |
| Q-80 | S | Lighting/material/up-axis tests/source present; actual Metal/geometry/appearance proof in S2. |
| Q-81 | R | Floating accessible 3D controls/facts/one-time hint/import and viewport states in S3 containers. |
| Q-82 | R | Listing risk/root-fact/model fields and summary/hidden counts in S3 containers. |
| Q-83 | P | MIDI palette/announcements exist; 30 pt transport, help-only no-autoplay, limits failures and update-rate cap in S3. |
| Q-84 | S | Compatible same-format/full-bounds reload preserves the camera; incompatible/reset/cleared sessions reset it. Native tests pass; actual Finder reload delivery remains. |
| Q-90 | S | Failure-aware neutral sidebar status/one home and count removal present; signed save/recovery/UI checks in S2. |
| Q-91 | S | Slice-aware Undo/Redo for overwrite actions present; real Edit menu/announcements in S2. |
| Q-92 | P | Pinned layout source present; restore absent layout-check source in S0, verify all widths/heights in S2/S3. |
| Q-93 | R | Numbered setup card/exact embedded extension names/adjacent on-demand conflicts in S3 setup after S2. |
| Q-94 | R | Native view-scoped Cmd-F search/counts/pattern truncation/loading behavior in S3 setup. |
| Q-95 | S | Semantic page/section/note hierarchy and About cleanup present; multilingual/large-text review in S2. |
| Q-96 | S | Typography/profile/control cleanup present; actual font/locale/transfer/hit-target review in S2. |
| Q-97 | R | Pane-wide drop/single Open/metadata-only inspector and spy-reader proof in S3 setup. |
| Q-98 | S | Route restoration/window title/Settings…→General/Help→About present; relaunch/menu observation in S2. |
| Q-99 | R | Per-type conflicts/time/limitations/Utilities/bounded subfolder scan in S3 setup after sandbox observation. |
| Q-100 | P | Swatch/gallery/narrow fallback source present; restore absent gallery checks in S0 and validate real widths in S2. |
| Q-101 | R | primaryView is available, renderer pill is absent; implement pill in S3 setup after final D1 mode policy. |
| Q-102 | P | Retry/recovery/save-flush source present; restore absent error checks in S0 and prove bounded terminate/save failure behavior in S2/S3. |
| Q-103 | R | License reveal/bundled color notices/distinct links/privacy-safe diagnostics in S3 companion with lead bundling. |
| Q-104 | P | Several control labels improved; whole-row/disclosure/clear/group target audit and fixes in S3/S4. |
| Q-105 | H | Sidebar material route waits for appearance observation on 15/current OS; implement approved vibrancy after S2. |
| Q-106 | R | Per-format help/limit hints from effective registration budgets in S3 after Q-32. |
| Q-110 | P | Failure title/body API and keys present; effective family-budget propagation/remaining limit values in S1/S3. |
| Q-111 | P | Apostrophe/length normalization/lints partly present; remaining Summary jargon and native typography review in S3/S4. |
| Q-112 | H | Confirm Apple's actual system-control labels in S2, then finish approved localized setup policy in S3 copy. |
| Q-113 | P | Draft improvements/lints/context exist; generic comments/leftovers/rebased human review queue in S3/S4. |
| Q-114 | R | Truthful shape/withholding/cache/synced-folder thumbnail switch guidance in S3 after policy decisions. |
| Q-120 | S | Matched catalog suffix badge and reply tests present; actual Finder icon/scale observation in S2. |
| Q-121 | S | Value-free grid scenes and bounded count facts are implemented for table/database/record producers, including JSON and inferred-grid privacy boundaries; Finder pixel/cache/routing observations remain. |
| Q-122 | H | Per-type none/generic/system-icon policies need S2 host table, then catalog/manifest integration. |
| Q-123 | H | Concrete source UTType registrations and no-abstract-parent test need S2 mdls table. |
| Q-124 | H | Error-versus-glyph transient behavior needs S2 cache experiment; once-only reply gate retained. |
| Q-125 | P | Picture-selection policy exists; dedicated picture budget/first-picture request/AVIF support in S3. |
| Q-126 | R | Thumbnail grid density/font/stroke/page/contrast metrics in S3 thumbnails. |
| Q-127 | S | Hidden/comment filtering, summary refusal and notebook-cells policy present; drawn-run/privacy verification in S2/S4. |
| Q-128 | R | UI-free SafeDiagram/injected drawing for Mermaid/draw.io thumbnails; lead module boundary plus S3 thumbnails. |
| Q-129 | R | Thumbnail request purpose/skip hidden scan/preferences ordering/page-sized prefix in S3/S4. |
| Q-130 | P | Badge/admission/text/picture tests exist; complete all-content-format/corpus/grid-pixel/four-locale coverage in S3/S4. |
| Q-131 | H | Verify thumbnail sync/provider behavior in S2; apply approved glyph policy if it syncs. |
| Q-140 | R | Cheap-fact lazy models/fast scanner/record numbering/oracle in S4 performance. |
| Q-141 | R | Style signature/no-op storage-layout guards/cached role dictionaries in S4. |
| Q-142 | R | Viewport-first TextKit 1 layout/background completion/exactness guards in S4. |
| Q-143 | R | Off-main PreparedPresentation/visible-mode preparation/generation-safe display in S4. |
| Q-144 | R | Hosted configuration/pane boundary and thumbnail-renderer linking hygiene, measured on Mac in S4. |
| Q-145 | R | Exact-identical reload skip and exact-prefix append storage/token/index path in S4. |
| Q-146 | P | Existing bounds/lazy baseline and R2 improvements present; profile/implement remaining hot-loop optimizations independently in S4. |
| Q-147 | H | Measure modular build/link cost after S3/S4; diagrams pilot only if justified, otherwise explicit deferral. |
| Q-150 | S | Shared text/name classifier, converted/decompressed/ebook paths and typed listing findings pass combined local/hosted Mac checks at `7e062b9`; broader corpus and signed-host acceptance remain open. |
| Q-151 | P | Real pipeline/native/copy/AX/thumbnail canaries now cover 14 representative fixture families and all 18 mode identities, integrated at `070c91b`. Broader adapter families, actual find/log/Finder/VoiceOver surfaces remain open. |
| Q-152 | P | Deterministic adversarial corpus passes. Explicit pinned-runtime pilot at `6256117` audits 176 instrumented package objects and verifies a real ASan canary, then fails the ZIP parser-PC reachability gate. No continuous fuzz/JSON result is accepted. Execution is stopped; D25 retains deliberate manual Mac CI. |
| Q-153 | P | Wrapper `f45d307` passes 14 Debug/Release tests; complete/leading reads at `bc83c18` pass 27 focused/native controls. Random-access `0cc43d7` passes 50 related Debug/12 Release tests; classification `47dd6ed` passes 131 related tests; process entrypoints `ed97406` compile and link explicitly. The static dataless guard (`1ef3895`, RED `0f6877e`) fails the gate on an unguarded file-opening call outside the allowlisted owners. Monitor/rearm/directory integration and actual provider no-materialization proof remain open; S4 safety. |
| Q-154 | P | Shared source/decode/admission bounds are verified; the [Release report](../validation/quality-program-image-footprint-2026-10-08.md) records the memory miss. Subsampling was ineffective; explicit 8 MP serialization roughly halves concurrent peaks but lengthens requests and still misses 100 MiB. Production remains unchanged pending actual draw/cache evidence; signed/minimum-OS proof remains open. |
| Q-155 | S | Rows and References now use the existing facade copy policy/reporting; private-pasteboard and all-mode canaries pass full integration at `070c91b`. AppKit normalization is independently checked. Actual signed-host clipboard/VoiceOver acceptance remains open. |
| Q-156 | R | Isolated app-embedded CAD XPC service for companion/Theme in S4/S5, lower priority with signed proof. |
| Q-160 | P | Chrome metrics and layout tests exist; size-following chrome/13–26 pt/14-language matrix and real Zoom/Larger Text in S4. |
| Q-161 | P | RTL gutter/neutral separators landed; reading arrows/MIDI direction/forced-RTL File Types completion in S4. |
| Q-162 | H | Actual companion per-app versus Finder host language and bundle evidence in S2/S4; document without schema change. |
| Q-163 | P | Geometry announcements/value work present; finish cached diagram accessibility and actual failure speech in S4. |
| Q-170 | P | Matrix/schema/checker/website projection present; production per-format/surface/OS evidence in S2/S5. |
| Q-171 | P | Source-offer/tooling/protocol tests present; legal review, real artifacts/publication/relinking or CAD fallback in S5. |
| Q-172 | R | Reviewed release language set/store copy/live pages/mailbox/screenshots in S5. |
| Q-173 | S | Mac dependency inventory completed and stale Xcode generator removed; checked-in project/shared scheme validated with four targets. Preserve historical references only. |
| Q-180 | S | Demo info, likely-secret copy, generated static privacy date/website data wiring present; production browser validation in S0/S5. |
| Q-181 | H | Real final Finder screenshots and matching demo await stable UI and Wave 4 host proof in S5. |

## Documentation reconciliation and remaining caveats

Completed during synchronization: decisions 026/027 now acknowledge implementation and recorded owner answers; PLAN names the remaining Wave 0/2/3 subparts; the queue identifies the absent benchmark comparison tool and amended median/interval/5% method; five Round 3 commits have explicit queue rows. The sync record separates source, CI, browser checks and observations. These administrative corrections do not close implementation gates.

- Restore the three missing companion test files in S0 and record actual integration results.
- A CAD semaphore wait differs from Q-40's planned continuation; document the measured exception or migrate deliberately. Do not silently claim the original contract was met.
- The 76-type historical matrix and source-offer draft do not close production Finder or legal release gates.
- Keep future publication/commercial milestones separate from source implementation and PR synchronization.
