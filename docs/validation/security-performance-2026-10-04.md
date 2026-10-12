# Adversarial input and native rendering validation — 2026-10-04

This continuation adds two small parser corrections, deterministic cross-catalog
failure coverage and a measured native-renderer baseline. It does not close Finder
routing, VoiceOver, macOS 15/Intel, shipping-language review or release performance
gates. Existing uncommitted work was preserved; no new dependency, package target,
production instrumentation framework or provider/cache override was introduced.

## Confirmed defects and narrow fixes

Four XML fixtures demonstrated that secret assignments in CDATA and processing
instruction data survived the safe-source privacy boundary. Comments already used
the shared non-field assignment checker; these two lexical forms did not. The
[XML scanner](../../Packages/PreviewCore/Sources/PreviewFormats/XMLSourceAdapter.swift)
now uses that same bounded checker for all three. It conceals the whole sensitive
payload while retaining delimiters and processing-instruction targets. The regression
fixtures cover ordinary and Unicode/multiline payloads, preserve a safe sibling and
reparse the concealed source as valid XML. Raw payloads never become alternate
renderer inputs. The failure was observed before the production correction.

Direct-adapter conformance checks also reproduced TAR and XIP returning malformed
input for already-cancelled/expired empty sources before checking request state.
Both random-access entrypoints now checkpoint before source validation. The pipeline
already checked request state centrally; this fix makes the concrete adapters honor
the same contract for direct callers. Cancellation still remains cooperative and
cannot forcibly interrupt a noncooperative filesystem/framework call.

The new [request tests](../../Packages/PreviewCore/Tests/PreviewCoreTests/AdversarialInputTests.swift)
exercise cancellation and expired deadlines at every one of the 22 registered
adapter entrypoints, cancellation immediately after a ZIP source read, and a
same-inode/same-size source change after opening a bounded descriptor. The mutation
test verifies timestamps rather than relying only on changed length; only its test
writer changes synthetic bytes. No production contracts or host controllers changed.

Two additional focused bomb fixtures passed without production changes. A 20,000-byte
GZIP member fits the 32,768-byte decoded allowance produced by a 512-byte input
budget; two concatenated copies fail `.outputTooLarge` with unchanged source bytes.
This proves that a member boundary cannot reset the decoded allowance. A crafted
binary plist array referring to itself fails `.malformedDocument` in the existing
preflight before Foundation graph construction. These fixtures complement the prior
overflow, dictionary and repeated-reference checks without constructing huge inputs.

## Deterministic malformed corpus

From an already-built SwiftPM output directory:

```sh
/usr/bin/python3 script/check_adversarial_corpus.py <SwiftPM-bin-directory>
```

The [runner](../../script/check_adversarial_corpus.py) reuses the shared
[synthetic host fixture generator](../../script/generate_host_fixtures.py), creates
its own uniquely owned seed directory and temporary corpus, and compiles a separate
[production-pipeline worker](../../Tests/Integration/AdversarialCorpusChecks.swift).
It removes only those directories it created. It never opens user preferences or
user documents. The deterministic seed is `0x50524556` (`1347568982`).

There are 176 cases: eight variants for each of the 21 file types and eight immediate
folder-metadata cases. File variants retain the original, truncate to zero/one/half
bytes, remove the final byte, flip a seeded bit, replace a seeded word with maximum
bytes, or prepend a seeded invalid header. Folder cases cover empty/immediate/nested
content, a symlink, Unicode names, a sensitive assignment in a filename, a FIFO and
64 children. No FIFO content is opened and no nested child contents are previewed.

The recorded Release-linked run returned 81 ready outcomes, 64 malformed-document,
30 unsupported-encoding and one unsupported-format outcome. Every request terminated
through the production pipeline. Ready output retained its expected format identity
and stayed within the standard output/line bounds. All 22 unmodified baseline
fixtures concealed their synthetic sensitive values; changing arbitrary field names
in a mutation is not treated as a promise of universal secret recognition.

File bytes, directory entries, modes and modification times were unchanged after
the corpus. This endpoint comparison does not prove the absence of every transient
system call. The ignored `.build/performance/adversarial-corpus-results.json` retains
all case/outcome records, the seed and exact worker link command, without source text.
This bounded mutation set is not exhaustive fuzzing, a complete bomb audit or a
proof that every native parser call can be preempted. Existing GZIP expansion,
XZ-dictionary/overflow, repeated-reference plist, SQLite lock/no-sidecar and normal
format fixtures remain separate and continue to apply.

The package suite passed 179 tests in 12 suites with the first five new request
regressions and concurrently integrated language checks. The two later bomb fixtures
also passed in the focused seven-test request suite. The opt-in native audio device
smoke test was skipped in this run; no audible/Finder audio claim is made. Python
syntax and whitespace checks passed. Integrated final-suite evidence is recorded
by the lead separately.

## Native Release benchmark

The [native measurement worker](../../Tests/Performance/ReleaseNativeRendererBenchmark.swift)
uses the actual shared `NativePreviewView`, `NSTextView`, `NSOutlineView`, syntax
styling, line-number gutter, safe secondary modes and inert Markdown renderer. It
creates no app window and uses no UI automation or companion preference storage.
AppKit is initialized in a separate process with prohibited activation, then the
800 × 600 view is laid out and drawn into an AppKit bitmap. It is an isolated renderer
benchmark, not an observation of a Finder host or on-screen first visible content.

```sh
/usr/bin/python3 script/benchmark_release_native_renderer.py
```

For coordinated measurement, `--build-only` prepares the package/worker and
`--skip-build` measures the prepared worker after builds have stopped. The runner
uses its own `Packages/PreviewCore/.build/performance-renderer` scratch directory,
SwiftPM Release and a Swift worker compiled with `-O`, Swift 6 complete checking and
macOS 15.0 deployment target. Counts are bounded to 1–200. It reuses the core benchmark
fixture builder and adds synthetic source/Markdown cases; no dependency is added.

Each sample first obtains a production safe outcome, recording pipeline duration
separately. It then measures construction, initial display/layout/drawing with line
numbers, an available secondary mode, appearance restyling and the last viewport's
layout/drawing. AppKit layout is forced for native text containers and the view is
cached into a bitmap to include real native drawing. Assertions and memory probes
are outside those stage timers. Each sample constructs a fresh renderer; warm samples
retain the process/pipeline and initialized framework caches, rather than reusing one
already-populated view. Restyling itself uses the loaded safe outcome and performs no
source read. No MIDI playback/audio graph, web view or helper process is created.

Each case uses ten newly launched processes with one measured sample each, followed
by a new process with one untallied warm-up and fifty measured samples. The final run
contains 420 measured renderer sequences plus seven warm-ups. Cold means a new
process, not a cold disk or flushed framework cache. Source files are freshly
generated and their hashes, names and modification times are checked after every
case, then their uniquely owned temporary directory is removed. No system caches
or Finder process were changed.

The final run began at `2026-10-04T10:42:48.906150Z` (13:42 Europe/Istanbul) on the
MacBook Pro `Mac17,8`, Apple M5 Pro, arm64, 48 GiB physical memory. Host OS was
macOS 27.2 build `26B5091g`; Xcode 27.0 `27A266a`, SDK 27.0, Apple Swift 6.4
`swiftlang-6.4.0.34.1`. Package source was frozen and team builds/tests stopped
during the measurement loop. Other local processes, CPU frequency, thermals and
power state were not controlled. A preliminary one-cold/one-warm smoke run passed
all seven cases and is excluded from the final distributions.

The final raw artifact is `.build/performance/release-native-renderer-results.json`.
It records all stage durations, process wall times, memory samples, exact commands
and environment. First/warm distributions use nearest rank; first-process p95 with
ten samples is the maximum. No confidence interval or speed pass threshold is
inferred. All source checks and concealed native-text assertions passed.

### Native timing results

Durations are milliseconds, p50 / p95, rounded to three decimals. Initial display
includes safe secondary-model construction, source styling, native layout and bitmap
drawing. JSON/JSONL/Markdown initially show Source; the secondary stage selects
Outline/Records/Rendered respectively. ZIP/SQLite start on Summary, so their initial
stage includes that native outline and no separate secondary switch is timed. Text
and source code expose only Source. Restyling happens in the then-selected mode.

| Case | Input bytes | First-process initial | Warm initial | Warm secondary | Warm restyle | Warm last viewport |
|---|---:|---:|---:|---:|---:|---:|
| Text | 181,543 | 131.871 / 157.002 | 140.525 / 171.161 | — | 63.548 / 75.952 | 3.287 / 5.657 |
| JSON | 228,159 | 318.598 / 339.525 | 365.307 / 494.113 | 156.757 / 193.784 | 151.290 / 173.412 | 4.705 / 7.290 |
| JSON Lines | 252,090 | 258.538 / 288.701 | 266.342 / 308.395 | 480.426 / 563.839 | 149.403 / 182.591 | 18.207 / 23.562 |
| ZIP | 33,822 | 56.670 / 65.848 | 52.561 / 74.360 | — | 25.338 / 36.999 | 4.646 / 9.010 |
| SQLite | 212,992 | 111.286 / 132.448 | 153.273 / 176.106 | — | 71.695 / 93.141 | 5.063 / 7.100 |
| Source code | 145,431 | 192.855 / 206.959 | 194.475 / 224.773 | — | 102.035 / 123.590 | 3.284 / 4.402 |
| Markdown | 31,962 | 83.089 / 86.189 | 73.995 / 78.820 | 34.744 / 37.527 | 34.863 / 37.717 | 3.360 / 4.006 |

The warm pipeline p95 range for these same samples was 11.294–66.050 ms, measured
separately. Fresh native construction had warm p95 3.659–5.042 ms and first-process
p95 19.975–33.399 ms. The JSON/JSONL/source native initial stage alone exceeds the
plan's provisional 200 ms warm useful-content target. This directly shows why the
earlier core-only timings cannot close native performance acceptance. It does not
equate offscreen full layout/drawing with first visible Finder content.

The largest warm JSONL Records stage was 951.258 ms (p95 563.839 ms); that tail is
retained without an attribution to a particular parser/layout/OS operation. These
figures justify focused profiling of large safe structured presentations before a
release claim. No optimization was introduced merely to improve the benchmark.
Cold process wall includes the whole sequence, including mode change, restyle and
scroll, and is therefore not a cold first-useful-content metric. Its JSON p50/p95 was
815.035/870.174 ms and JSONL 1,140.413/1,355.179 ms; all raw samples remain available.

### Process memory results

Values are MiB, rounded to three decimals. Maximum growth subtracts each process's
baseline lifetime peak from its later peak, then takes the largest observed growth.

| Case | Largest baseline RSS | Largest sampled RSS | Largest lifetime peak RSS | Largest peak growth |
|---|---:|---:|---:|---:|
| Text | 6.906 | 112.859 | 114.703 | 107.797 |
| JSON | 6.938 | 151.469 | 153.328 | 146.422 |
| JSON Lines | 6.938 | 169.484 | 171.359 | 164.453 |
| ZIP | 6.906 | 81.359 | 83.219 | 76.312 |
| SQLite | 6.938 | 92.422 | 94.281 | 87.375 |
| Source code | 6.922 | 133.844 | 135.688 | 128.781 |
| Markdown | 6.906 | 88.203 | 90.062 | 83.156 |

Process peaks exceed the earlier core-only baseline substantially. Several peaks
are above 100 MiB; these totals include AppKit initialization and the broader
renderer sequence, so they cannot establish or directly disprove the plan's ordinary
incremental-preview memory target. Allocations/VM profiling in a real host is still
needed. The bounded inputs and passing correctness tests are not proof of meeting
the release latency/memory targets.

## Measurement limits

RSS comes from public Mach `task_info`; process-lifetime peak comes from Darwin
`getrusage`, whose `ru_maxrss` is in bytes. Baselines precede AppKit/pipeline
initialization; after samples retain the safe result and renderer but not a saved
bitmap. Peak growth includes runtime/framework initialization, pipeline work,
native layout/drawing and retained framework caches. It is not isolated allocation
or physical-footprint accounting. Python, compiler, Finder, companion and Quick Look
host processes are excluded. This process total cannot establish the plan's
incremental preview-memory target.

Full text-container layout, offscreen bitmap drawing and repeated renderer creation
are explicit costs here. They differ from progressive on-screen compositing and
from a Finder request's extension launch, scheduling or host controls. Keyboard
selection/copy and accessibility API assertions remain existing focused tests; this
measurement does not verify human VoiceOver, native event delivery or translated
layout. A deployment target does not prove macOS 15 runtime behavior. OS/hardware
and actual-host performance gates remain open.

## Final integrated verification

After the parallel UI/language changes and MIDI follow-up, the lead's final
`--test` run passed **184 Swift tests in 12 suites**, five companion-model groups,
five appearance-interaction groups, three drop groups, cross-process SQLite checks
and the same 176-case corpus. The default corpus JSON now describes that latest
Debug-linked integration run (including its exact link command); the earlier
Release-linked run above produced the same outcome counts. The separate native
Release timing artifact was not replaced or rerun after the MIDI-only change;
none of its seven measured cases creates or plays a MIDI device.
