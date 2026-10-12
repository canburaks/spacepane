# CAD implementation and validation

Date: 2026-10-04, Europe/Istanbul. Host: Apple M5 Pro, 48 GiB, macOS 27.2 (26B5091g); Xcode 27.0 (27A266a), SDK 27.0. Product minimum remains macOS 15. These observations do not establish Intel or macOS 15 runtime behavior.

## Implemented boundaries

- Two opt-in formats: IGES (`.igs`, `.iges`) and STEP (`.step`, `.stp`). Both default off for new/existing snapshots and Reset; explicit Enable All includes current opt-in types without changing future defaults.
- Shared numeric mesh contracts, per-format budgets, isolated native import and native Metal rendering. No vendor types cross the adapter boundary. Disabled requests stop before source reads/factory construction; ordinary text never constructs geometry/device state.
- CAD input 16 MiB; output 32 MiB; 500,000 triangles; 100,000 faces; parent wall deadline 20 seconds. Native helper CPU limit 15 seconds with 16-second hard backstop, sampled 512 MiB physical-footprint guard. Sampling permits overshoot; aggregate host/GPU memory and worst-case CAD complexity remain measurement gates.
- No source-path argument, temp source snapshot, document scripts, remote resource resolution or raw metadata output. Geometry itself is shown as stored. Generic thumbnails never render model contents.

## Automated evidence

`PREV_VALIDATE_METAL=1 ./script/build_and_run.sh --test` with full Xcode selected passed **239 Swift tests** after XPC, remote-visibility and input-handling integration, including a real offscreen Metal shader/depth test. Five isolated companion-model groups, three drop groups, five appearance groups and the independent SQLite cross-process/no-source-write checks passed. The deterministic corpus now contains **192 cases across 24 types**: 176 existing parser cases plus 16 default-off CAD policy cases. These 16 do not test CAD parsing; the separate native checks do.

`python3 script/build_cad_worker.py --architecture arm64 --test` passed **11 native process checks**. Fixtures cover box dimensions/normals/winding, translated geometry, explicit inch-to-mm conversion, trimmed holes by area, curved/pole topology, malformed/oversized data, external references, depth/entity limits, omitted synthetic metadata, source hashes/no sibling files and process kill/reap. The STEP fixture is AP214; complete AP203/AP242 coverage is not established.

The Swift CAD integration harness successfully imported both synthetic boxes and the supplied private IGES model. The source hash stayed `8b3cf85f657008002abe3294ffa0f8d07b77963cf3b7a3c2475c57f4bedfa21f`. The private model remains outside the repository and was not copied or uploaded. It produced all **720 faces**, **18,813 vertices**, **27,335 triangles** and **779,604 bytes** of numeric payload.

One fresh Release worker run took approximately 1.11 seconds with peak RSS 138,018,816 bytes (about 132 MiB), physical footprint 129,614,376 bytes. Later fresh processes with warm storage completed the same import around 0.52–0.65 seconds. These are individual observations, not cold/warm percentile benchmarks or Finder latency measurements. They justify opt-in defaults and do not replace the application's existing unresolved performance targets.

Project checks passed four targets, both embedded extensions and all 24 catalog types. Localization validation passed 277 keys in 14 draft languages, plus 13 localization-tool tests and CAD metadata/resource projections. All 33 explicit language-selection cases passed against the 277 runtime keys in each of the three signed visible bundles, with unchanged resources. Translations still need speaker/UI review. All 24 host fixtures parsed through the production pipeline with explicit CAD opt-in and unchanged source contents/entries.

## Signed companion observation

Both canonical and previously registered development paths built successfully with embedded, signed helpers. Deep signature verification passed. Helpers have only `com.apple.security.app-sandbox` and `com.apple.security.inherit`; the worker links only Apple's libc++/System dynamically. Xcode's script sandbox remains enabled: helper signing occurs inside its allowed temporary directory, followed by copying to explicitly declared outputs. Six OCCT/generated-parser notice files are packaged.

The signed companion displayed both new settings switches **off** before testing. After temporary explicit opt-in, opening the supplied IGES file showed actual shaded geometry, a 720-face/27,335-triangle summary and the localized metadata-omission notice in Try Preview. Side view and Zoom In changed the geometry view. The app stayed in its singleton tabbed window. The subsequent initial-camera improvement uses isometric orientation and an extent-derived fit radius; automated renderer tests cover it.

## Signed Finder observation

An older registered development build initially showed a generic icon. Rebuilding it exposed a real sandbox boundary: Foundation reported file-not-found for the correct helper path, and direct public `posix_spawn` confirmed `EPERM`. The final preview extension uses a standard embedded `CADImportService.xpc` with its own sandbox and accepted-peer signing requirement. Only the companion directly launches a worker. The service receives bytes, owns cancellation and runs at most two imports per service process; it declines extra requests without queuing file contents. This is not a machine-wide memory cap.

The service entitlement source contains only App Sandbox; signed Debug builds also receive Xcode's normal `get-task-allow`. Its helper contains exactly App Sandbox and sandbox inheritance. No network/user-file/App Group permissions were added to the service. Both clean canonical and registered signed builds passed; deep code-sign verification passed. Generator and validator preserve the four-target graph, and 19 graph/identity/sandbox mutations were rejected.

The remote Quick Look window initially reported occluded despite being displayed, which prevented GPU construction. A host-managed visibility mode now uses controller appear/disappear lifecycle for Finder while the companion retains ordinary window-occlusion cleanup. An occluded-window regression failed before this change and passed afterward, including attachment, suspension, camera retention and text replacement. Metal remains event-driven and lazy.

On this host, Finder's Space-bar preview visibly rendered synthetic STEP and IGES boxes (6 faces, 12 triangles, 10 × 20 × 30 mm), including closing/reopening and the Side view control. It also rendered the supplied private IGES model with all 720 faces and 27,335 triangles. The companion was stopped. The attributed extension PID 93868 and embedded service PID 93873 ran from the registered development path; XPC and worker logs recorded successful imports. A later process snapshot showed no remaining worker. Source SHA-256 remained unchanged. No Finder restart, Quick Look cache reset or extension-preference manipulation was used.

Both temporary CAD opt-ins were restored to **off** through the companion Settings tab, with saved-state confirmation. Viewport input now prevents window dragging, accepts first-click focus and uses local point deltas, with regression coverage for movement and lifecycle cleanup. Physical orbit/pan gestures and keyboard forwarding remain unverified in Finder: automated input sometimes reached the underlying Finder selection instead of the remote view. The rendered geometry and standard-view button observations establish the stated files on this OS/build, not universal CAD routing or all Finder thumbnail surfaces.

## Remaining release evidence

- Human verification of physical orbit/pan/zoom gestures and keyboard forwarding in both the companion and Finder hosts.
- Minimum-OS/Intel/universal execution, broad independent CAD corpus, human VoiceOver/full keyboard/language validation, cold/warm host/GPU/whole-process measurements and longer hostile-input tests.
- Native static-link license/source/relinking distribution review and final App Store archive/policies. See [dependency audit](../dependencies/occt.md).
