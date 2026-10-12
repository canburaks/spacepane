# JSON Lines, group controls and line-number validation

Date: 2026-10-03 (Europe/Istanbul). This continues the [appearance slice](appearance-slice.md), preserving the broader [platform gates](platform-spike.md).

## Scope

- Third logical format: JSON Lines/NDJSON, validated concealed source using the existing text presentation. This is not records navigation, per-record error recovery or compressed-stream support.
- Catalog-derived native group checkboxes, search including suffix aliases and group names, explicit whole-group scope, atomic publications and preserved unrelated/default choices.
- Optional line numbers in a separate native gutter, with strict schema 4 persistence and migrations from schemas 1–3.
- One adaptive Appearance control/sample tree, and repeatable checks of real companion models through injected temporary storage.

The [format/group decision](../decisions/004-json-lines-and-group-controls.md) and [appearance decision](../decisions/003-preview-appearance.md) define the contracts. App-authored copy remains internationalized with typed resource references; only development English is present.

## Verification

| Check | Result | What it proves |
|---|---|---|
| `--test` | **90 package tests in 4 suites passed**, including parameterized cases; **4 companion model checks passed** | Parsing, shared privacy, policy, migrations, actual companion model behavior and native renderer behavior on this host |
| `--check` | **Passed: 3 formats, 3 targets, 2 embedded extension declarations, 101 keys** | Catalog/manifest/import/localized metadata consistency and resource references |
| `--check-compiler` | **All 3 hosts passed** | Swift 6 complete checking and macOS 15 deployment targeting; not a macOS 15 runtime result |
| `--run-companion` | **Built, ad hoc signed, launched; process verified** | CLT companion with package resources and imported types; no embedded Quick Look extensions |
| Supported Files UI | **Observed JSON Lines enabled with both aliases and localized description** | The rebuilt companion loads the extended catalog |
| Settings UI audit | **Incomplete: inspection service crashed again** | Opening Settings disconnected native inspection; companion remained alive |

The default developer directory changed during this run from Command Line Tools to `/Applications/Xcode.app/Contents/Developer`. Subsequent default commands returned exit 69 because Xcode's license was unaccepted. Final local commands explicitly used:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./script/build_and_run.sh --test
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./script/build_and_run.sh --check
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./script/build_and_run.sh --check-compiler
DEVELOPER_DIR=/Library/Developer/CommandLineTools ./script/build_and_run.sh --run-companion
```

No license was accepted and no global toolchain selection was changed by this work. The existing native SwiftPM build-system deprecation warning remains; installed extension checks need a usable full Xcode setup plus real signing identities.

## Behavior covered

JSON Lines tests cover exact large-number spellings/duplicate keys, LF/CRLF/final newline, scalar records, escaped sensitive keys after Unicode records, whole-file rejection for malformed/blank records, cumulative nodes, depth, bytes, output, line length/count, UTF-8/BOM constraints, cancellation, unchanged source bytes and disabled aliases avoiding both reads and parser construction. Existing JSON behavior, including its BOM acceptance, remains covered. The scanner now checks progress through long digits and whitespace as well as strings.

Catalog tests cover known suffix priority over conflicting metadata, uppercase aliases, exact types without suffixes, loading before imported declarations are registered, and choosing a narrower declared ancestor over generic text. Constructing an imported type in an unregistered process preserves its identifier; it does not prove that the system has registered its conformance graph. Installed type behavior remains unverified. `public.ndjson` was observed in this host's CoreTypes declarations; availability on macOS 15 is not assumed. Both suffixes are also included in the explicit imported declaration.

Eight native gutter tests cover UTF-16 and Unicode separators, CRLF as one separator, final empty lines, wrapped first fragments, scrolling into a continuation, actual viewport narrowing/restoration, selection/scroll retention, exact copy to an isolated pasteboard, digit/font-dependent width, hidden fallback states and zero/narrow hosts. Numbers derive from concealed displayed text, not source metadata. An initial NSRulerView version exposed a real geometry issue: scroll content insets reserved the ruler without reducing the content size used by wrapping. The final sibling gutter has explicit layout width and avoids that mismatch.

Preference checks strictly preserve all prior schema 3 fields and introduce only a default-false line-number flag. Current-schema missing fields remain corrupt; unknown versions retain disabled fallback. The four companion checks compile actual production models and verify:

1. An already-safe preview survives appearance changes after its temporary source is deleted, without a new generation; disabling its recognized type clears it synchronously.
2. Searching `.ndjson` hides JSON's row while a group action still changes both types exactly once, preserves unrelated choices/appearance, keeps future formats disabled after Disable All, and persists the complete snapshot. Repeated collection writes remain no-ops with unavailable storage.
3. Same-value Reset Appearance repairs corrupt storage without enabling content.
4. Same-value reset retries a failed write once its temporary blocked path becomes writable.

These tests use unique temporary files/preferences and never the user's preference location. They do not replace UI, accessibility, cross-process App Group or Finder tests.

## UI limitation and cleanup

The new native inspection failure again reports `EXC_BREAKPOINT`/`SIGTRAP` in `SkyComputerUseService`, with `Array.remove(at:)` in its triggered stack. A screenshot request also disconnected. The app process stayed alive. The single Appearance tree did not resolve this tool failure; its accessibility correctness is still unverified.

The original 109-byte prototype preference snapshot was backed up and verified byte-for-byte unchanged after this attempt. No actual file, Finder cache or system extension preference was changed. Temporary model fixtures are removed by the check runner.

## Open gates

- [ ] Observe Appearance controls, line-number alignment and mixed group toggles through a working native inspection/keyboard/VoiceOver session, including wide/narrow layouts.
- [ ] Complete reset/retry/relaunch interaction checks through the actual companion UI.
- [ ] Configure usable full Xcode/signing and validate installed preview/thumbnail registration, App Group snapshots, disabled handling and macOS 15 runtime.
- [ ] Implement JSON/JSONL outlines/record navigation and safe per-record error presentation; source-only support does not complete M2.
- [ ] Complete additional grammars, Markdown and the remaining baseline adapters.
- [ ] Validate reviewed shipping translations, RTL behavior, accessibility and Release performance.
