# Native image decode footprint

Measured October 8, 2026 (Europe/Istanbul), from clean commit `293fcb2baa3a1b7dbc07ad5d467ec64e84eb8499`. The production decoder/admission implementation is unchanged from `6408639`. The source, executable, build commands, fixture fingerprints and every sample are retained in [the compressed raw report](artifacts/2026-10-08-image-footprint/release-images-293fcb2.json.gz).

## Result

The starting **100 MiB incremental-footprint target is not met**. Two concurrent 16 MP PNG decodes peak around 250 MiB above baseline; a single 40 MP PNG or JPEG exceeds 115 MiB. The existing source cap and serial admission above 16 MP prevent unbounded work but do not establish the memory target. Oversized 100 MP input is rejected before native admission.

| Scenario | Cold incremental maximum, MiB | Warm incremental maximum, MiB | Absolute sampled maximum, MiB | Immediate footprint after reference release, MiB |
|---|---:|---:|---:|---:|
| 40 MP RGBA PNG | 115.313 | 101.078 | 119.766 | 20.485 |
| 40 MP RGB JPEG | 118.485 | 104.969 | 120.688 | 15.282 |
| Two 16 MP RGBA PNGs | 249.500 | 245.516 | 254.329 | 9.892 |
| 40 MP PNG plus two 16 MP PNGs | 263.282 | 248.422 | 271.767 | 27.360 |
| Rejected 100 MP PNG | 4.485 | 0.109 | 7.094 | 7.094 |
| Tiny AVIF | 5.344 | 0.156 | 7.563 | 7.548 |
| Cancel after admission, then replacement images | 264.985 | 244.813 | 269.173 | 25.798 |

Absolute and after-release columns are maxima across both phases. Physical footprint comes from `TASK_VM_INFO`, not RSS or calculated bitmap sizes. Each 40 MP result contains a 3,578 × 2,236, 8-bit bitmap with a 14,320-byte row stride (32,019,520 bytes of storage); each square result is 2,829 × 2,829 with an 11,328-byte stride (32,046,912 bytes). Those storage values alone do not explain or bound temporary decoder memory.

## Method and scope

Apple M5 Pro / Mac17,8, 48 GiB, macOS 27.2 (26B5091g), Xcode 27.0 (27A266a), Swift 6.4, SDK 27.0, deployment target macOS 15. The package and standalone worker use Release optimization; `-enable-testing` permits the worker to call internal production seams without adding public product API.

Each of seven scenarios has three cold workers and five measured warmed samples after one explicit unmeasured warmup: 56 accepted samples, 3,060 actual probes, all reporting nominal thermal state. A new bounded maximum collector samples every 2 ms during each request; its timer drains before the next sample. The report separately records baseline, held bitmaps, immediate reference release, sampled maximum and the kernel's process-lifetime peak. Sampling can miss shorter peaks; a warmed process's lifetime peak includes earlier work and is not a per-request peak. Dropping Swift references does not guarantee allocator or framework memory has returned to the OS.

Synthetic complete PNGs are generated in bounded rows; JPEG and AVIF encoding occurs in separate processes before measured workers launch. Encoded sizes remain below 8 MiB. Fixture bytes, current source and prepared worker identity are checked around measured processes. The worker launches no children. Its footprint does not measure Finder, shared OS services, drawing, CAD coexistence or the minimum supported OS.

Cancellation is causally requested after an admission event. All eight measured retired tasks returned no bitmap. Whether cancellation occurred inside an active ImageIO C call is deliberately unknown; deterministic continuation-held package tests separately establish native lease lifetime under noncooperative cancellation.

The first harness attempt exposed a Release linker inventory placeholder and the next exposed main-actor inference in a dispatch timer callback. The shared link helper now uses SwiftPM's actual emitted object inventory (six portable tests pass), and both timer callbacks are explicitly Sendable. The accepted report is only from the repaired committed harness above. Harness failures are not decoder measurements.

Further work: use these results to tune admission and decoded output requirements, rerun the same fingerprinted workload, and independently observe actual signed Finder behavior. No Q154 memory or release gate is closed here.

## Q154 follow-up: subsampling rejected as a memory remedy

At clean `36ed46cb4297afe44a7665e673ff33e1272c26d4`, one Release `-O -enable-testing` executable ran the unchanged production decoder control and an ignored safe factor-2 ImageIO candidate through the same production decoder admission/metadata/cancellation path. Each mode recorded all seven scenarios with three fresh cold processes and a fresh warm process containing one unmeasured warmup plus five measured samples: 56 measured samples per mode. Separate policy/fallback checks passed. Both report validators passed; all samples reported thermal state 0.

Source, executable, build context, environment and fixture fingerprints matched across modes. Source SHA-256 was `aa4776e766de24726847c951a94788400c1d6bfa41c2ac047f8465bc93001493`, executable SHA-256 `6a829d2f42b51b3b65b7605d6d8bb35ebb48af7fc51ffa4fdcf111ba3f612575`, and build-context SHA-256 `e1bd7ed86fd7e2962700ec55677ac8c38313c5fdc230cc721e4e562d863dc8d8`. Requested sides, decoded dimensions, component depth, row strides and bitmap storage matched across all 112 measured samples. The candidate recorded 32 hinted calls, 56 unhinted calls and zero fallbacks; these counters identify requested hints, not effective internal subsampling.

Maximum sampled incremental footprint above each sample's baseline, MiB:

| Scenario | Production cold / warm | Candidate cold / warm |
| --- | ---: | ---: |
| 40 MP PNG | 115.063 / 101.156 | 115.047 / 101.156 |
| 40 MP JPEG | 116.422 / 107.078 | 115.438 / 107.078 |
| Two 16 MP PNGs | 249.407 / 245.110 | 249.485 / 245.078 |
| 40 MP PNG + two 16 MP PNGs | 263.422 / 245.031 | 263.204 / 247.610 |
| Cancel after admission + replacement | 265.063 / 246.922 | 264.922 / 246.078 |

The PNG and pair results show no meaningful improvement. JPEG cold sampled ranges were 110.094–116.422 MiB for production and 106.266–115.438 MiB for the candidate; warm ranges were 101.438–107.078 and 96.391–107.078 MiB. JPEG kernel lifetime peaks increased from 120.751 to 121.782 MiB cold and from 120.048 to 123.735 MiB warm, so the sampled maximum alone cannot establish benefit. Mixed/cancellation distributions vary substantially: low samples observed one active admission lease and high samples observed two. Exact request-arrival order was not recorded. Warm kernel lifetime peaks include the earlier warmup and previous samples and cannot be assigned to one request.

All 100 MP requests remained refused; AVIF and 16 MP requests bypassed the hint. Each mode's eight cancelled retired tasks returned no bitmap; cancellation inside the native C call remained unobservable. Held-reference and immediate post-drop probes do not prove AppKit materialization, actual held-cache memory or allocator release.

No production optimization was selected. The 100 MiB starting incremental target, actual drawing/cache, Finder, combined CAD/process totals and minimum-OS runtime gates remain open. Serialized production decoding at unchanged 8 MP is a separate pending experiment; 4 MP variants remain unselected. Raw results/logs are `experiments/production-36ed46c.{json,log}` and `experiments/safe-subsample-2-36ed46c.{json,log}`, with build/policy logs and complete distributions in `experiments/comparison-36ed46c.{md,json}`. Accepted `release-images-293fcb2.json` evidence remains unchanged.

The [experiment archive](artifacts/2026-10-08-image-footprint/subsample-experiment-36ed46c.tar.gz) preserves both full raw reports, logs, comparison distributions, the ignored runner and Swift experiment sources with an independently checked SHA-256 manifest. To reproduce, use clean source commit `36ed46c` and restore those experiment files to `.build/quality-work/q154-footprint/experiments/`; rebuild the worker before measuring. The source-only archive contains no executable or private fixture.

### Q154 follow-up: serialized production decoding at unchanged 8 MP

At clean `058335a08bff228ee7870a4f1b61f002d62523ba`, one Release `-O -enable-testing` executable compared the unchanged production ImageIO decoder under default admission and one retained capacity-one instance of the same production gate. Both modes preserved the 8 MP request policy and 40 MP source cap. Build and separate policy checks passed without repairs. Each mode recorded all seven scenarios with three fresh cold processes and a fresh warm process containing one unmeasured warmup plus five measured samples: 56 measured samples per mode. All report/occupancy/geometry checks passed and all thermal states were zero.

Source, executable, build context, environment and fixture fingerprints matched. Source SHA-256 was `2964708c0659546f91bae87569e363c6f35c281e122d4afdd377a3297c833905`, executable SHA-256 `318f2f12d73f80b1b1c11b3c47c39a06c7928c2f8188897cf707042455e7f021`, and build-context SHA-256 `c1e3806c251748cc8cb6337b53a7837d1f871584f0ebb77fa331d540e32d2778`. Exact source inventories, encoded bytes, requested sides, decoded dimensions, component depths, row strides and bitmap storage matched across all 112 measured samples. Both modes produced 3578×2236-pixel 40 MP results (14,320-byte rows; 32,019,520 bytes each), 2829×2829-pixel 16 MP results (11,328-byte rows; 32,046,912 bytes each), and 32×24-pixel AVIF results (128-byte rows; 3,072 bytes), all at eight bits per component. The control's 16 MP pair observed two active leases in every sample; the candidate observed one for every admitted heavy/mixed/cancellation sample. Both gates drained before reset. Four MP variants were not selected.

Maximum sampled incremental footprint above each sample baseline, MiB:

| Scenario | Production cold / warm | Serialized cold / warm |
| --- | ---: | ---: |
| 40 MP PNG | 115.094 / 101.094 | 115.203 / 101.078 |
| 40 MP JPEG | 116.438 / 107.016 | 116.391 / 107.063 |
| Two 16 MP PNGs | 249.453 / 245.063 | 126.625 / 123.531 |
| 40 MP PNG + two 16 MP PNGs | 263.313 / 244.922 | 140.516 / 126.453 |
| Cancel after admission + replacement | 264.797 / 244.860 | 142.219 / 124.031 |

Serialization reduces overlapping-group memory substantially: the 16 MP pair's maximum falls 49.2% cold and 49.6% warm. Single 40 MP peaks remain effectively unchanged. The pair's median duration rises from 60.785 to 106.875 ms cold (75.8%) and 56.570 to 110.958 ms warm (96.1%). Mixed medians rise from 156.722 to 195.635 ms cold and 148.426 to 194.459 ms warm. These sample durations include source loading/checks, decoding, memory probes and sampler drain; they are not Finder first-visible latency.

Independent kernel lifetime peaks also fall for groups: the pair goes from 251.673 to 128.845 MiB cold and 252.751 to 130.704 MiB warm; mixed goes from 265.548 to 142.720 MiB cold and 269.282 to 150.939 MiB warm. Warm kernel peaks include warmup and earlier samples, and cannot be assigned to one request. JPEG's warm kernel peak rises from 120.032 to 122.110 MiB despite almost unchanged sampled maxima. Full distributions and both ledgers are retained.

All 100 MP requests remain refused. Each mode's eight retired tasks return no bitmap after causal admission cancellation; cancellation inside C remains unobservable. No production policy was selected. Every heavy scenario's cold and warm maximum still exceeds the 100 MiB starting incremental target. Actual AppKit held/drawn cache, Finder, combined CAD/child/shared process totals and minimum-OS runtime gates remain open; held CGImage references and immediate post-drop readings do not establish cache materialization or allocator release.

Evidence lives under `experiments/serialized8/`: `production-058335a.{json,log}`, `serialized-8mp-058335a.{json,log}`, `build-058335a.log`, `policy-058335a.log`, and `comparison-058335a.{md,json}`. The deterministic source-only archive is `source-only-058335a.tar.gz` with its manifest and SHA-256 file. Accepted `293fcb2` baseline and `36ed46c` rejected-subsample evidence remain unchanged.

Tracked reproducibility: [experimental sources](artifacts/2026-10-08-image-footprint/serialized8-source-058335a.tar.gz) (SHA-256 `a291574ea26590903ac4554ab6131575f30c329b7b102ec50e17c55a5987cc37`) and [complete raw evidence](artifacts/2026-10-08-image-footprint/serialized8-evidence-058335a.tar.gz) (per-file SHA-256 manifest). Restore the source archive in the ignored serialized8 directory on clean `058335a`, then rebuild before measuring. Neither archive contains executables or private fixtures.


### Q154 native cache/draw causal attempt — 2026-10-09

Clean `52846900723deb640ef28539d6b2b0ed31673361` builds the fresh Release worker and passes the experimental policy check. The production run validates the PNG40, JPEG40, PNG16 pair and mixed scenarios, then stops in the oversized 100 MP refusal scenario: the unchanged replacement-chain validator requires an accepted bitmap, while the source correctly returns no bitmap. No serialized process runs and no paired result is accepted.

The recorded warm replacement changes the actual column from 2048 to 2031 points (2016 to 1999 requested pixels) at actual scale 1. Its old UUID is cancelled by the latest wanted geometry; a distinct replacement finishes current and uncancelled, invokes the native callback with nil, and leaves an unavailable page with zero resident/drawn image bytes. No native admission lease is taken. This is diagnostic evidence, not an accepted measurement. Warm sample 0 has one nil/refusal request; later warm samples have two requests with a layout replacement. That multiplicity difference also prevents treating one warm sample as a uniform reference under the current strict pairing rule.

The immutable local archive `.build/quality-work/q154-footprint/experiments/candidates/cache-causality-failed-5284690-r1-dov36rme` contains the source/build identity, exact executable, seven inputs, protocol, tests, logs and 20 raw worker triples with verified hashes in `MANIFEST.json`. The bounded trace diagnosis is `cache-refused-layout-causality-5284690-r1-diagnosis.json`. No validator relaxation or native rerun is part of this checkpoint. A separate ignored refusal-only protocol/test draft is preparation; any later attempt needs review and a fresh source/input freeze.

The production 40 MP source limit, 8 MP decode ceiling, 192 MiB cache budget and admission policy remain unchanged. The 100 MiB target remains unmet. The user subsequently requested stopping after the active tasks; do not resume this experiment automatically.
