# Quality program synchronization — 2026-10-07

Scope: synchronize the existing PR and local work, reconcile source with its records, and plan the remaining implementation. No native feature or test behavior was changed in this synchronization. Dates use Europe/Istanbul.

## Git and source boundary

- PR: [#12](https://github.com/canburaks/prev/pull/12), `claude/competitor-ux-ui-analysis-0fab0e` into `master`.
- The named local worktree was clean at `4a1580c`; the live PR was at `f391354`, 47 commits later. Its saved remote reference was still `942de09`. Fetch and fast-forward recovered the committed continuation without discarding local changes.
- The common base with `master` was `e64ad5a`. Master's independent `3339304` added Fluid Functionalism interactions and the en-GB Safari month fix. The synchronization merge retains these alongside the PR's hydration changes, scripts and UI/data changes. It does not merge the PR into master.
- The only textual merge conflict was the two branches' prepended changelog entries. Both histories were retained. `web/DESIGN.md` and `web/package.json` merged additively; an independent read-only review confirmed both sets of scripts, dependencies, design rules and date behavior were preserved.
- Master's `pnpm-lock.yaml` already represented its new dependencies, but `package-lock.json` omitted the three direct dependencies. `npm install --package-lock-only --ignore-scripts --no-audit --no-fund` synchronized the npm lock. The generated diff adds the missing direct dependency metadata, Framer Motion packages and optional bundled WASM metadata; it changes no existing locked package version. `npm ci --ignore-scripts --no-audit --no-fund` then succeeded. Both lockfiles remain supported.
- The [continuation plan](../plans/2026-10-07-quality-program-continuation.md) maps the 133 backlog entries and defines implementation order. Decision 027 and PLAN now distinguish source presence, hosted checks and observed acceptance. No implementation wave is checked complete by this synchronization.

## Checks performed here

Host: arm64 macOS 27.2 (26B5091g), Xcode 27.0 (27A266a), Apple Swift 6.4. Website commands used Node 26.8.2 and npm 11.19.1; the portable gate used system Python 3.9.6.

| Check | Result and limit |
|---|---|
| `./script/build_and_run.sh --check-static` | 16 steps passed, one skipped, zero failed. Includes 103 localization tests, 73 archive-check tests, 38 host-matrix tests, 52 source-offer tests, six kernel-free CAD protocol tests, generated data, manifest and ownership-tool checks. Swift syntax skipped because the pinned tree-sitter packages are unavailable to this interpreter; no Swift was edited here. |
| `npm ci --ignore-scripts --no-audit --no-fund` in `web/` | Passed with the synchronized npm lock. |
| `npm run check` in `web/` | Passed: data/static privacy/locale parity, 19 host-matrix projection tests, TypeScript and ESLint. Two pre-existing vendored Fluid Functionalism warnings remain (unused `_scrollHideDelay`, effect-cleanup ref capture). |
| `npm run build` in `web/` | Passed; 70 static pages generated. Existing middleware-deprecation and 153 kB home-page data warnings remain. |
| Production `npm run test:hydration -- --base http://localhost:3137` | Passed: no hydration warnings, page errors or wrong-language responses in 42 page loads (14 languages × home/support/privacy), using the repository's Chromium test. Not a Safari or VoiceOver result. |
| `npm run visual:compare -- --ref http://127.0.0.1:4187 --next http://localhost:3137 --sections header --widths 1440,375` | Exited 1: header differs from the static reference by 1.50% at 1440 px and 0.57% at 375 px. These match the percentages already recorded for master's Fluid Functionalism work. No page errors occurred. This is recorded reference drift, not a claim of pixel parity; no threshold was relaxed. |
| Repository source/diff inspection | Both branch histories and both package manifests/locks preserved; three missing companion integration files confirmed from the committed tree (below). All local Markdown link targets in the seven changed records and all 133 unique backlog IDs checked; no missing or extra IDs, unresolved conflict markers or whitespace errors. |

No Swift package rebuild, signed app installation, Finder cache reset, provider preference change, OCCT kernel build, TestFlight upload or release publication was performed for this sync. The existing native failures remain explicit next work, rather than being hidden behind website checks.

## Native baseline to recover before new features

1. [Hosted run 33](https://github.com/canburaks/prev/actions/runs/37586232781), commit `8ce6ec7`: last fully green native run. It passed 2,942 package tests, integration checks and 148 measured contrast ratios. It precedes the Round 3 companion integration.
2. [Hosted run 40](https://github.com/canburaks/prev/actions/runs/37614532446), commit `1b7d392`: package build and companion/extension typechecks passed. The package suite ran 2,946 tests in 293 suites with one issue: `cancellationAnswersWithTheGlyphPromptly` returned `.cancelled`, then exceeded its one-second time bound (1.06401175 s). This requires isolated and loaded-run investigation; neither a harmless flake nor a product regression is established. The catalog `primaryView` drift test passed in this run.
3. Run 40 stopped before companion integration. `script/test_companion_models.py` references `Tests/Integration/CompanionLayoutChecks.swift`, `CompanionErrorStateChecks.swift` and `CompanionGalleryChecks.swift`, but all three are absent at `f391354`. `CompanionModelChecks.swift` calls the first two types. Recover intended tests from original authoring artifacts if available; otherwise implement meaningful checks from the layout/error/gallery contracts. Do not remove the references or substitute empty checks to obtain a green run.
4. [Hosted run 41](https://github.com/canburaks/prev/actions/runs/37614673060), commit `f391354`: static passed, macOS package job skipped. A green PR status from this job does not verify the native suite. The synchronization commit likewise needs the native recovery batch before it can be described as fully verified.

The [pending queue](pending-mac-verification.md) retains its older open entries and gains five identified Round 3 commit rows. These rows distinguish compilation from runtime resources, real-window layout, OCCT helper execution, privacy-offer publication and Finder behavior. The new machine-readable host matrix serializes retired-development-identity evidence; it does not establish production-identity routing.

## Remaining evidence

The first native recovery batch restores the missing checks, diagnoses the timing failure and runs `--check`, `--check-compiler` and `--test` on its exact integrated commit. Later host sessions close the queue with dated records: production identity, supported OS versions, actual pane widths/safe areas, input delivery and loading policy, VoiceOver/translations, thumbnail persistence and Release performance. CAD source-offer tooling is present, but its draft offer, publishing destinations and legal/relinking review remain open.

The user authorized synchronization and an implementation plan here. The [recorded owner answers](../reviews/2026-10-06-quality-review/owner-questions.md) remain in force; evidence-dependent choices stay pending their experiments. The continuation plan does not silently waive gates or introduce new product decisions.
