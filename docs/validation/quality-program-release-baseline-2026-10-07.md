# Quality-program Release baseline — 2026-10-07

This is the committed PR-branch baseline before the reading-layout, paragraph-reflow and final privacy changes. It is not a comparison against master, an A/B acceptance run, or Finder first-visible-paint evidence. Performance gates remain open.

## Artifact and method

- Exact clean source: `acec21b395ffc72bc08b27d43f1bcfe56f00f061`; source-tree SHA256 `feb706a57a8e55b9e18fa8fda2c6775b34ec621a572da8df2de556c1b07598fb`. Worker, build-context and fixture fingerprints are retained in the raw reports.
- Mac17,8 / Apple M5 Pro / 48 GiB / arm64; macOS 27.2 (26B5091g), Xcode 27.0 (27A266a), Swift 6.4, macOS 27 SDK; deployment target macOS 15. This beta-host run does not establish minimum-OS or supported-stable-OS coverage.
- Release SwiftPM libraries and `-O` workers. Ten fresh-process first samples plus fifty warm samples after one untallied warm-up for every case: 960 measured pipeline requests and 840 native samples. Cold means fresh process; no filesystem/framework caches were flushed.
- Pipeline scope: production classification, bounded read, adapter, concealment and validation with explicit standard budget. Native scope: actual offscreen 800×600 AppKit view, first display/full TextKit layout/bitmap draw, secondary mode, font/theme restyle, final-viewport draw and immutable log append snapshots. Native uses family-default budgets. It does not measure Finder extension launch, scheduling, window presentation or first visible paint.
- Typed stage hooks were active. Pipeline timings include their recorder overhead; native first-draw intervals include nested renderer stages, so stage times must not be summed as independent totals. Physical footprint uses TASK_VM_INFO; sampled maxima and kernel process-lifetime peaks are separate from RSS and are not a measurement of an app plus CAD helper.
- Team compilation/tests were paused during both measurement loops; edits continued only in a different worktree. General OS/user background activity and power state were not controlled. Source-tree fingerprints matched before/after; synthetic file bytes, names and modification times were unchanged, then temporary fixtures were removed.
- The first two attempts correctly failed obsolete benchmark oracles (oversized text now returns a bounded prefix; logs have an independent catalog ID). Their partial timings are excluded. Both corrected full workers completed successfully.

Raw schema-1 reports (gzip; decompress before `script/compare_benchmarks.py`): [pipeline](artifacts/2026-10-07-release-baseline/pipeline.json.gz), [native](artifacts/2026-10-07-release-baseline/native.json.gz). They include all raw samples, monotonic stage intervals, memory probes, environment/build commands, source/worker/fixture hashes and start/end timestamps.

Commands after preparing each worker with `--build-only`:

```sh
python3 script/benchmark_release_pipeline.py --skip-build --cold-samples 10 --warm-samples 50 --output <pipeline.json>
python3 script/benchmark_release_native_renderer.py --skip-build --cold-samples 10 --warm-samples 50 --output <native.json>
```

## Pipeline results

Durations are milliseconds; nearest-rank p95/max and raw samples are retained. With ten cold samples, cold p95 equals the maximum. These are descriptive measurements, not confidence intervals.

| Case | Input bytes | Cold p95 | Warm median | Warm p95 | Warm max | Peak physical MiB |
|---|---:|---:|---:|---:|---:|---:|
| csv | 258,810 | 40.951 | 34.750 | 35.378 | 35.674 | 8.97 |
| dense-secrets | 784,000 | 111.662 | 104.528 | 106.389 | 106.625 | 12.22 |
| environment | 74 | 3.074 | 0.135 | 0.166 | 0.249 | 6.50 |
| json | 228,159 | 26.348 | 22.412 | 22.785 | 22.938 | 8.38 |
| json-1mib | 1,048,576 | 112.196 | 105.441 | 109.234 | 109.525 | 14.34 |
| json-lines | 252,090 | 30.663 | 26.285 | 26.818 | 28.588 | 9.22 |
| listing | 322,022 | 39.236 | 34.776 | 40.655 | 41.025 | 10.05 |
| log-append | 18,584 | 4.366 | 1.234 | 1.285 | 1.291 | 6.41 |
| malformed-json | 66 | 2.070 | 0.053 | 0.059 | 0.087 | 5.83 |
| malformed-json-lines | 81 | 2.902 | 0.067 | 0.083 | 0.112 | 6.31 |
| markdown-contents | 2,102 | 3.341 | 0.414 | 0.458 | 0.560 | 6.49 |
| oversized-text | 1,048,578 | 14.303 | 11.097 | 11.273 | 11.543 | 8.27 |
| source-1mib | 1,048,576 | 209.013 | 201.997 | 204.851 | 210.312 | 15.58 |
| sqlite | 212,992 | 16.285 | 11.900 | 12.440 | 12.657 | 8.55 |
| text | 181,543 | 31.620 | 19.676 | 20.700 | 22.090 | 8.24 |
| zip | 33,822 | 6.769 | 3.642 | 3.744 | 3.817 | 7.09 |

## Native renderer results

Whole path is the measured pipeline + view construction + first display/draw for each sample. Restyle is a separate changed-font/theme operation; it is not added to whole path. These are actual bitmap draws, not an assertion of interactive frame delivery in Finder.

| Case | Warm whole-path median / p95 / max ms | Display p95 ms | Restyle p95 ms | Peak physical MiB |
|---|---:|---:|---:|---:|
| csv | 71.588 / 78.581 / 81.750 | 35.953 | 16.990 | 38.89 |
| environment | 26.046 / 31.097 / 36.181 | 23.466 | 10.527 | 44.03 |
| json | 146.693 / 151.000 / 160.719 | 122.713 | 12.556 | 88.53 |
| json-1mib | 267.796 / 275.935 / 281.713 | 163.512 | 247.261 | 129.92 |
| json-lines | 141.046 / 144.724 / 147.303 | 111.718 | 15.004 | 92.34 |
| listing | 171.550 / 178.058 / 184.644 | 137.293 | 18.685 | 42.78 |
| log-append | 30.173 / 33.134 / 39.117 | 26.489 | 18.270 | 37.75 |
| markdown | 58.700 / 60.996 / 66.731 | 51.701 | 49.029 | 50.56 |
| markdown-contents | 27.365 / 29.809 / 38.313 | 22.387 | 9.806 | 45.20 |
| source | 99.135 / 101.603 / 102.688 | 73.408 | 104.476 | 75.50 |
| source-1mib | 399.129 / 429.595 / 580.632 | 211.790 | 311.902 | 142.72 |
| sqlite | 52.679 / 58.082 / 59.637 | 38.746 | 13.637 | 44.50 |
| text | 82.145 / 84.787 / 85.507 | 59.422 | 79.644 | 62.74 |
| zip | 58.691 / 64.874 / 68.464 | 56.350 | 18.683 | 47.67 |

The 1 MiB source case has the largest measured whole-path tail (580.632 ms maximum) and changed-style cost (311.902 ms warm p95). This directs the next work toward avoiding unnecessary styling and full-document layout, while preserving exact safe text, current appearance and reading position. The smaller JSON case still spends 151.000 ms at whole-path p95; eager secondary models and safe structure scanning remain candidates. No improvement claim is made without the required five interleaved A/B pairs and 95% bootstrap analysis.

The main/native baseline must be re-established as appropriate for the final comparison. Signed Finder lifecycle, helper-inclusive memory, macOS 15/current stable release, accessibility, 14-language layouts and final exact-artifact performance remain separate gates.
