# Release core-pipeline benchmark — 2026-10-04

This is a measured local SwiftPM core-pipeline baseline. It exercises real bounded file access, classification, adapters, privacy filtering and final text validation. It does **not** establish Quick Look extension launch, Finder scheduling, native layout, first visible content, scrolling, renderer allocations or release readiness. The broader M5 performance and OS/hardware gates remain open.

## Repeatable command and scope

From the repository root:

```sh
/usr/bin/python3 script/benchmark_release_pipeline.py
```

The [runner](../../script/benchmark_release_pipeline.py) builds the package with `swift build --build-system native -c release` in its own ignored `Packages/PreviewCore/.build/performance` scratch directory, links the [Swift worker](../../Tests/Performance/ReleasePipelineBenchmark.swift) with `swiftc -O`, creates eight synthetic files in a uniquely owned system temporary directory, checks outcomes and source changes, and removes that directory. It never accesses companion preferences or user documents. No package targets, production APIs or dependencies were added.

The default output is `.build/performance/release-pipeline-results.json`. It contains environment information, exact build/link commands, all raw durations and memory samples, and nearest-rank min/p50/p95/max distributions. The file is an ignored local artifact; rerunning regenerates it. Optional `--cold-samples`, `--warm-samples` and `--output` arguments are documented by `--help`; sample counts are bounded to 1–200. The normal command needs the repository's selected macOS Swift 6.2+ toolchain. The existing native build-system deprecation warning also appears here.

Each case uses ten separately launched worker processes with one measured first request each. A further new process retains one pipeline, performs one untallied warm-up request, then measures fifty sequential requests. Thus the recorded set has 480 timed requests and eight additional warm-up requests. The warm process's first request remains in the raw data but is excluded from the warm distribution.

The monotonic request timer begins immediately before `pipeline.preview` and ends when its safe outcome returns. It includes worker dispatch, source access, decode/parse, privacy filtering and final output validation. It excludes pipeline construction, outcome assertions, memory probes, JSON output, parent-side checks and rendering. Pipeline construction is recorded separately; across the cold cases it ranged from 3.733 to 6.220 ms.

Parent-measured cold process wall time spans child launch through child exit and includes loading, composition, one request, assertions, probes and JSON reporting. It is reported separately below. “Cold” means a new process: fixtures were just created, filesystem and framework caches were not flushed, and this is not a cold-disk or Finder-host measurement. No system caches, extensions or Finder preferences were changed.

## Recorded environment

The recorded run began at `2026-10-04T10:20:46.963427Z` (13:20 Europe/Istanbul).

| Item | Recorded value |
|---|---|
| Hardware | MacBook Pro, `Mac17,8`, Apple M5 Pro, 18 cores, arm64 |
| Physical memory | 51,539,607,552 bytes / 48 GiB |
| Host OS | macOS 27.2, build `26B5091g` |
| Xcode / SDK | Xcode 27.0 (`27A266a`), macOS SDK 27.0 |
| Swift | Apple Swift 6.4, `swiftlang-6.4.0.34.1`, clang `2100.3.34.1` |
| Package / worker | Release; package `-O` / whole-module optimization; worker `-O` |
| Language / deployment | Swift 6, complete concurrency checking, nonisolated shared logic; arm64 macOS 15.0 deployment target |
| Request policy | Unmodified `PreviewBudget.standard`: 1,048,576 input bytes, 2,097,152 output bytes, depth 64, 20,000 nodes/lines, 32,768 bytes/line, 2,000 ms cooperative deadline |

The current standard input cap is 1 MiB; the plan's 2 MiB text policy remains a starting target rather than a silently substituted benchmark configuration. This host run does not provide macOS 15 runtime, Intel, baseline-device or supported-stable-OS coverage. Team package edits were frozen and team compilations paused during the recorded measurement loop. Other local processes, power state, CPU frequency and thermal conditions were not controlled. A later expanded run after builds resumed is excluded from this report.

## Results

Durations below are milliseconds, rounded to three decimals. p95 uses nearest rank; with ten cold samples it is the maximum. These are empirical samples without confidence intervals or pass/fail speed thresholds.

| Synthetic case | Input bytes | First request p50 / p95 | Warm request p50 / p95 | Cold process wall p50 / p95 |
|---|---:|---:|---:|---:|
| Plain text, 1,500 Unicode lines and one secret assignment | 181,543 | 53.548 / 65.915 | 50.679 / 55.390 | 71.938 / 455.072 |
| JSON, 1,200 records and one sensitive root field | 228,159 | 53.842 / 57.139 | 50.133 / 52.910 | 72.598 / 76.113 |
| JSONL, 1,200 Unicode records with sensitive fields | 252,090 | 63.354 / 65.890 | 60.883 / 68.699 | 82.207 / 84.917 |
| Malformed JSON containing a synthetic secret | 66 | 2.556 / 2.944 | 0.065 / 0.244 | 13.983 / 15.371 |
| JSONL with a damaged second record | 81 | 4.068 / 5.356 | 0.116 / 0.190 | 17.505 / 21.173 |
| Text two bytes over the standard input cap | 1,048,578 | 3.321 / 3.988 | 0.061 / 0.165 | 16.385 / 16.867 |
| ZIP directory with 200 Unicode filenames | 33,822 | 15.093 / 17.685 | 11.743 / 12.313 | 27.657 / 32.010 |
| SQLite snapshot, 1,200 rows with sensitive columns | 212,992 | 55.223 / 62.994 | 50.945 / 62.447 | 70.301 / 78.523 |

The first text worker's 455.072 ms process wall outlier is retained. Its timed request was 65.915 ms; the harness does not attribute the remaining time to a particular loading, scheduling or OS activity. Larger repeated cold samples and launch tracing are needed before calling that tail stable. Warm maxima were 62.355 ms text, 58.663 ms JSON, 70.404 ms JSONL, 12.431 ms ZIP and 64.669 ms SQLite.

All ordinary ready fixtures are at most 256 KiB and their core-only warm p95 values are below the plan's provisional 200 ms useful-content target. This does not close that target: native highlighting/layout and first visible content are absent. Likewise, process wall time below the provisional 700 ms cold target is not evidence of Finder-hosted useful content.

### Process memory

Current resident bytes are sampled using public Mach `task_info` / `MACH_TASK_BASIC_INFO` before and after each request; the after sample retains that request's safe result. Public Darwin `getrusage(RUSAGE_SELF).ru_maxrss` provides a process-lifetime peak in bytes, including transient allocations between RSS samples. Baselines precede pipeline construction. “Peak growth” subtracts each process's baseline lifetime peak from its later lifetime peak, then reports the largest growth; it is not an isolated allocation or a physical-footprint measurement.

| Case | Largest baseline RSS MiB | Largest sampled RSS MiB | Largest lifetime peak RSS MiB | Largest lifetime peak growth MiB |
|---|---:|---:|---:|---:|
| Text | 6.953 | 25.328 | 25.328 | 18.391 |
| JSON | 6.953 | 25.109 | 25.109 | 18.156 |
| JSONL | 6.938 | 26.328 | 26.328 | 19.391 |
| Malformed JSON | 6.938 | 23.156 | 23.156 | 16.219 |
| Malformed JSONL | 6.938 | 23.375 | 23.375 | 16.438 |
| Oversized text | 6.938 | 22.828 | 22.828 | 15.891 |
| ZIP | 6.969 | 23.859 | 23.859 | 16.922 |
| SQLite | 6.938 | 26.359 | 26.406 | 19.469 |

The executable links the repository's package libraries through the existing link helper, including unused preference/renderer objects and their framework dependencies. These figures include its loaded runtime/library overhead, pipeline initialization and measured work. They exclude Python, builds, the companion, Finder, Quick Look hosts and any other processes. No renderer, web view or helper process is created by the worker. Although the observed process peaks are below 100 MiB, they do not establish the plan's ordinary native preview incremental-memory target. Instruments allocation/VM profiles and actual-host combined memory remain outstanding.

## Correctness and source checks

Every invocation checked the expected stable format and outcome. Ready text/JSON/JSONL concealed their synthetic secret values (one, one and 1,200 redactions respectively). Malformed JSON returned `.unavailable(.malformedDocument)`. Damaged JSONL returned ready safe content with record 2 wholly concealed and original record count 3. Oversized text returned `.unavailable(.inputTooLarge)` using the production budget. ZIP output contained no synthetic member payload. SQLite output concealed sensitive values (201 redactions) and remained bounded to its initial page rather than reading all 1,200 rows into presentation.

After each scenario the parent compared SHA-256 file contents, directory filenames and file modification timestamps for all eight fixtures. They were unchanged, with no SQLite WAL/SHM/journal or other additional entries. This is an observed endpoint check, not a system-call trace proving that no transient write could ever occur. Synthetic temporary files were removed by scoped `TemporaryDirectory` cleanup. The worker emits metrics and outcome summaries, never source/presentation text.

A preliminary one-cold/one-warm smoke command also passed all eight scenarios. Python syntax validation and whitespace checks passed. This harness measures a representative subset; it does not replace cancellation, bombs, permissions, live-source races, UI privacy, accessibility, or full format conformance tests, and does not benchmark every shipped adapter.
