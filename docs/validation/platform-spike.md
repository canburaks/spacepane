# Initial implementation and platform validation

Date: 2026-10-03 (Europe/Istanbul). This report distinguishes local compilation/tests from signed Finder validation. A source scaffold is not evidence of a working installed Quick Look extension.

This records the initial slice. Subsequent theme/typography work and the current 57-test result are documented in [appearance-slice.md](appearance-slice.md); its settings GUI audit remains incomplete.

## Scope

The first vertical slice implements the architecture using text and JSON source previews, shared typed outcomes, bounded reads, privacy handling, format enablement and a companion/preview/thumbnail shell. Full JSON tree interaction, additional baseline formats, rich syntax themes and production translations remain tracked in [PLAN.md](../../PLAN.md).

## Observed environment

- Selected developer directory: `/Library/Developer/CommandLineTools`.
- Compiler: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64.
- Host reports macOS 27.2, build `26B5091g`; the deployment target remains macOS 15.
- Full Xcode was not found in `/Applications` or the targeted Spotlight bundle search. No global developer-directory setting was changed.
- No production team, bundle or App Group identifier was supplied. Development placeholders must not be represented as production configuration.

## Implemented slice

| Area | Implemented behavior | Remaining boundary |
|---|---|---|
| Modules | Contracts, orchestration, adapters, preferences and native renderers are separate SwiftPM targets; hosts compose concrete adapters | No external plugin SDK or downloaded code |
| Text | UTF-8 and BOM-marked UTF-16, selectable native read-only text, typed failures | No full syntax-highlighting/theme/typography editor yet |
| JSON | Bounded source validation preserves numeric lexemes and duplicate keys; sensitive fields are concealed before presentation | No interactive JSON tree, JSONL or package.json summary yet; malformed JSON does not expose raw fallback |
| File types | Searchable text/JSON switches, enable/disable all, reset; stable IDs and default/override persistence | Group/mixed-state controls and all additional format families remain open |
| Preferences | Versioned atomic snapshots, schema migration, bounded reads and fail-closed corruption handling | Real App Group cross-process behavior still requires signed testing |
| Companion | Setup, direct file-picker preview, Supported Files, Help and Settings | Drop handling, bundled sample workflow and observed Finder activation receipt remain open |
| Preview extension | Thin controller, request replacement/cancellation, shared safe renderer and settings-error state | Installed lifecycle and sandbox grants unverified |
| Thumbnails | Generic, content-free glyph with dimension checks; no document reads or decoder imports | It deliberately renders the same safe generic representation for enabled and disabled types; no claimed preference-dependent thumbnail content |
| Localization | Typed catalog keys, development-language fallback, canonical catalog/fallback generation and resource validation | English development resources only; reviewed second language, RTL and installed-host language checks remain open |
| Branding/build | Central build-time name, localized bundle-name templates and development-only identity placeholders | Actual team, production identifiers and signed build not configured |

The slice enforces a conservative **1 MiB input cap**, 2 MiB UTF-8 output, 20,000 text lines, 32 KiB per line, JSON depth 64 and 20,000 JSON nodes. These are limits, not speed benchmarks. Oversized content is declined with an explicit state rather than a partial preview in this slice. One retained pipeline owns one serial worker; companion windows receive the same app-owned pipeline, while independent extension controllers own separate pipelines. Cancellation/deadlines are cooperative and cannot preempt a stalled native filesystem operation.

Privacy remains heuristic. Recognized sensitive JSON fields are concealed using parser spans; text assignments, likely credential patterns and ambiguous multiline assignments are handled conservatively. Only safe text reaches the selectable renderer. Generic thumbnails avoid content entirely. This is not a guarantee that every possible secret can be identified.

## Validation record

| Command/check | Result | What it establishes |
|---|---|---|
| `./script/build_and_run.sh --test` | **Passed: 33 tests**, including parameterized cases | Shared modules compile and the listed core/preferences/format/resource behaviors pass on this host |
| `./script/build_and_run.sh --check` | **Passed** | Three-target graph, embedded extension products, catalog/manifest agreement, extension-safe settings, 59 UI resource keys and generated bundle-name metadata |
| `./script/build_and_run.sh --check-compiler` | **Passed** | Companion and both extension sources type-check with Swift 6 complete concurrency checking and macOS 15 deployment target |
| `./script/build_and_run.sh --build-companion` | **Passed** | Companion-only app links, stages both package bundles under `Contents/Resources` and passes strict ad hoc signature verification |
| Companion launch and UI smoke check | **Passed** | Native JSON preview conceals synthetic sensitive values, disabling JSON clears active content, and resetting choices restores the redacted preview |
| `./script/build_and_run.sh --build-unsigned` | **Blocked: full Xcode unavailable** | The script reports the environment limitation before claiming a bundle build |

Tests cover disabled requests avoiding reader/parser construction; source nonmutation; UTF-8/BOM UTF-16 and malformed encoding; input/output/line limits including CRLF, CR, NEL and Unicode line/paragraph separators; JSON syntax/depth/node limits, duplicate keys and numeric preservation; synthetic-secret concealment and no malformed-JSON raw fallback; cooperative pre-start/mid-parse cancellation and deadlines; serial worker behavior; special-file rejection; preference defaults/corruption/migration/atomic reads and writes; and package localization lookup/fallback. Atomic reader/writer tests use independent actors in one process, not separate signed extension processes. Test timing is not a Release performance benchmark.

The prototype at `dist/PrevPrototype.app` has private settings and no sandbox/App Group entitlements or embedded extensions. Native compilation and this launch do not establish installed Finder behavior. The UI check used only `Fixtures/Sensitive/redaction.json`: both synthetic credential values were absent from the displayed/accessibility text while the safe message remained visible. Settings were restored to their defaults. This was a focused smoke check, not a VoiceOver or full accessibility audit.

Package resource resolvers prefer their host's standard `Contents/Resources` bundles and fall back lazily to SwiftPM's module bundle. A regression test stages both bundles into a synthetic app and verifies lookup without the build-cache fallback. Actual extension-host resource lookup remains part of signed validation.

The final companion rebuild also launched successfully after pipeline injection moved to the app root. Accessibility inspection confirmed explicit “Plain Text” and “JSON” switch names and persisted enabled defaults. The companion was left open on Setup.

### Toolchain compatibility

The selected SDK exposes both the original SwiftUI `State` property wrapper and a newer `State` macro, but the Command Line Tools installation lacks the newer SwiftUI macro plugin. The companion uses a small documented `CompanionState` alias to the public property-wrapper type, retaining its normal SwiftUI ownership semantics. It does not implement a replacement state system. Deployment remains macOS 15; runtime compatibility must still be verified on that OS.

The default SwiftBuild path in this Command Line Tools installation failed to locate the Testing macro plugin on a rebuild. The script uses the native SwiftPM build system and derives the Testing framework/plugin/linker paths from the selected developer/toolchain directories for CLT test execution. The resulting test command passes. SwiftPM emits a native-build-system deprecation warning; revalidate/remove this compatibility path when a full supported Xcode toolchain is available. No global toolchain setting or external dependency was changed.

## Finder validation still required

- [ ] Build the three targets with full Xcode and real development signing/App Group configuration.
- [ ] Install the app, enable both extensions manually and prove invocation for each declared type.
- [ ] Repeat with the companion quit and with competing providers installed.
- [ ] Exercise preview panel, preview pane/column, compact hosts, selection/copy, keyboard and accessibility.
- [ ] Verify disabled types, preference changes and actual cache behavior without promising provider handoff.
- [ ] Verify sandbox file grants, resource bundle lookup and language selection in both extension processes.
- [ ] Exercise rapid replacement, dismissal and inaccessible/moved/cloud-backed items without stale results or blocked UI.
- [ ] Repeat on macOS 15; compilation against this host SDK alone does not prove baseline runtime compatibility.

## Decision

Continue building and testing the reusable slice with the available toolchain. M0 remains open until signed host evidence exists; dependent production claims remain gated. Do not install dependencies or change Finder/provider settings as a substitute for those checks.
