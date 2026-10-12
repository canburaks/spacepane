# Language quality and resource lookup — 2026-10-04

This is a local technical/editorial audit of the implementation drafts. It is
**not native-speaker approval, complete linguistic review, layout validation or
Finder effective-language evidence**. All 14 selected languages retain the draft
review status in [the language policy](../../tools/localization/languages.json).
The language and generic Portuguese/Spanish resource choices remain those in
[decision 008](../decisions/008-languages-and-appearance-transfer.md).

## Scope and corrections

The audit compared actual translations for the format descriptions, privacy and
read-only/fallback guidance, setup/provider limits, secondary-view/summary labels,
appearance and MIDI controls. Structural checks cover all **259 runtime keys**,
all 14 locales and the three localized bundle-name templates. This bounded
comparison does not certify every sentence's idiom, grammar or terminology.
No file contents were uploaded and no external reviewer or service received the
translation dictionaries.

Four technical editorial corrections were made; they still require speaker review:

| Language / resource key | Before → after | Rationale and confidence |
|---|---|---|
| German / `format.text.diff.description` | `vereinheitlichte Unterschiede` → `Unified-Diff-Ansicht` in the existing description | Keep the technical Unified Diff format recognizable instead of describing generally harmonized differences. High confidence in the format distinction; final German idiom remains unapproved. |
| Indonesian / `format.archive.tar.description` | `entri jarang` → `entri sparse` | “Sparse” describes TAR files with holes, rather than entries that occur rarely. Retain the technical term pending the reviewer's preferred Indonesian expression. High confidence in the intended parser restriction, not in a complete translation review. |
| Hindi / `midi.pause` | `रोकें` → `विराम दें` | Distinguish temporary pause/resume from stopping/resetting playback. Technical editorial clarification; a Hindi speaker must approve the final control term. |
| Hindi / `midi.playbackHelp` | `चलाएँ या रोकें` → `चलाएँ या विराम दें` | Keep the help consistent with the Pause control. Same pending language review as the button. |

Seven owning String Catalog comments now explain: PPQN's quarter **note**, Pause
versus Stop, Unified Diff, sparse TAR entries, typography points and float precision,
filesystem immediate children, and the translated *suggested* theme export basename.
The English PPQN label and lower-confidence Kurmanji/Hausa wording were left for
contextual speaker review. The suggested basename is app-authored; source filenames,
suffixes, schema keys and persisted identifiers remain exact technical values.

The translation inputs, canonical catalog and generated German/Hindi/Indonesian
`.strings` resources are synchronized. Neither the selected languages nor the
bundle identities, parsing behavior or source files changed.

## Automated evidence

- `python3 tools/validate_localization.py`: **259 keys, 14 locales** passed.
  It verifies key/resource/input correspondence, metadata coverage and formatted
  argument identities/types; it does not approve translation meaning.
- `python3 tools/test_localization.py`: the existing **13 tool tests** passed.
  They were preserved without duplicating their placeholder/merge checks.
- Focused SwiftPM `LocalizationTests`: **11 tests passed**, including five new
  checks for regional aliases, skipping an unavailable first language preference,
  independent English/Turkish decimal formatting, exact Unicode/RTL argument
  spelling and development-language fallback for missing keys in every locale.
- A local scan found no replacement characters, embedded control characters or
  bidi override/isolate characters in the catalog translations. The 12 technical
  format-name/SQL-label resources (`JSON`, `JSON Lines`, `YAML`, `TOML`,
  `package.json`, `Markdown`, `XML`, `OPML`, `SQLite`, `GZIP`, `MIDI`, `SQL`) retain
  their exact spelling in every locale. Official localized product names such as
  Chinese Finder/Quick Look wording are not treated as identifier corruption.

### Actual signed bundle resources

The repeatable read-only checker is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 script/check_bundle_localizations.py \
  --app .build/xcode/Build/Products/Debug/Prev.app
```

It verifies each supplied host's signature and inspects that app's own embedded
renderer bundle and `InfoPlist.strings`. It never launches the companion or either
extension and has no fallback to a SwiftPM build cache. Explicit Foundation
localization selection covers the 14 selected tags, 14 regional aliases,
Portuguese/Spanish alternate regions, an unsupported tag, an unsupported tag before
Turkish, and an Arabic-region fallback/Unicode stress case: **33 cases in three
bundle contexts**. Every canonical runtime value, localized bundle name and imported
type description must match; arguments preserve exact technical/Unicode spelling,
and resource/property-list hashes must stay unchanged.

The first run correctly rejected the previous signed artifact's now-stale German
diff description, instead of reading the new repository copy or treating resource
presence as enough. Rebuilt-artifact execution is recorded below. The helper's
signatures/resource selection establish artifact contents,
not a Finder host's chosen language or the system's displayed UTType descriptions.

An initial standalone command-line experiment with `-AppleLanguages` did not change
the helper's nested bundle preference selection. The checker therefore uses explicit
`Bundle.preferredLocalizations(..., forPreferences:)` and installed `.lproj` bundles.
That limitation is not represented as an actual companion/Finder language test.
There are no system, companion or extension preference writes.

**Rebuilt artifact result:** the command above passed all **33 explicit language
cases × three signed bundles × 259 runtime keys = 25,641 exact string comparisons**.
Every bundle also passed localized names and all ten imported-type description
lookups, two runtime interpolation checks per case, and unchanged resource hashes.
Observed on this Apple silicon macOS 27.2 / Xcode 27.0 host. The executable targets
macOS 15; this is not macOS 15 runtime evidence. Later artifact changes should rerun
the checker, particularly after catalog, metadata, branding or bundle-layout changes.

## Formatting, source preservation and plural boundaries

`PreviewStrings` owns bundle lookup and the documented English development fallback.
Its explicit language preferences choose UI resources; a formatting `Locale` does
not switch that UI language. The new decimal test observes `12.50` for `en_US` and
`12,50` for `tr_TR` while retaining the same surrounding localized wording.

`SafeSchemaLabels` localizes only known adapter-owned schema paths. User database
table/column names, SQL, paths, cell text and source lexemes are excluded from value
formatting, including strings that look numeric or boolean. Generated counts use
locale-aware integer formatting. The existing schema regression checks this boundary
with German formatting; the new interpolation test preserves `package.json`,
`.env.*`, Turkish `İı`, a decomposed accent, `9007199254740993` and Arabic text exactly.
These are value-level checks, not proof of bidi rendering, selection or copy in a
native view. The source/presentation separation remains unchanged.

All current catalog localizations use simple `stringUnit` values. There are no plural
variations to approve. `Record %lld` identifies one numbered record, and summary
counts use separate labels/values; those do not by themselves require a translated
count sentence. The fixed 32-profile limit still needs grammatical review in each
language. Any future variable-count sentence must introduce explicit catalog plural
validation and `.stringsdict` generation first: the current generator/validator
deliberately reject unsupported variation shapes. Speaker review should exercise
0, 1, 2, 3, 5, 11, 21 and 32 rather than assuming English plural behavior.

Every selected language uses a left-to-right script. The Arabic-region case is
unsupported-language fallback and an interpolation stress case, not Arabic shipping
support. Actual RTL layout stress must preserve source/code/timeline direction while
using semantic UI alignment; the tests here do not establish that layout behavior.

## Per-language review queue

Every row remains **draft / no native-speaker sign-off**. The priorities are concrete
review prompts, not assertions that the remaining wording is incorrect. The same
full resource and host acceptance checklist below applies to each row.

| Resource tag | Regional lookup case | First contextual questions for the reviewer |
|---|---|---|
| `en` | `en-GB` | Is “Ticks per quarter” clear as quarter-note timing? Distinguish bounded parsing, concealed source and a private snapshot from promises of trust or encryption. |
| `tr` | `tr-TR` | Check `appearance.wrapLines` and `appearance.lineNumbersHint`: does “kaydır” clearly mean visual wrapping rather than scrolling? Review source/outline terminology, ligatures and shared-settings recovery. |
| `de` | `de-AT` | Approve the Unified Diff correction and privacy wording such as “wahrscheinliche Geheimnisse”; verify the longest Settings/tab labels at minimum width. |
| `fr` | `fr-CA` | Check “source sécurisée”, fallback wording, companion-app terms and actual System Settings labels; distinguish concealment from trusted/validated source. |
| `zh-Hans` | `zh-Hans-CN` | Confirm Simplified Chinese terminology for Finder, Quick Look, schema, byte limits and typography points; verify compact labels and punctuation with selectable source. |
| `ja` | `ja-JP` | Review native-view/readonly terminology, fallback/source distinctions and MIDI bank help; check line breaks, narrow controls and VoiceOver pronunciations of format names. |
| `hi` | `hi-IN` | Approve Pause versus Stop in both corrected keys; review “native view”, ligatures and bounded configuration terminology; validate Devanagari shaping and label expansion. |
| `ku-Latn` | `ku-Latn-TR` | Review Kurmanji Latin spelling and inflection, filesystem “children”, musical quarter-note timing and the explicit-playback description; confirm it cannot imply autoplay. |
| `ru` | `ru-RU` | Review secret/concealment wording, semibold versus bold, metadata case/number and the fixed 32-profile phrase; check long Cyrillic labels and keyboard access. |
| `id` | `id-ID` | Approve sparse TAR wording; distinguish structured records from audio recording, native versus local views, and source from external resources. |
| `bn` | `bn-BD` | Review key/record loanwords, native versus local view terminology and fixed count phrases; validate Bengali conjuncts, fallback fonts and text selection. |
| `ha` | `ha-Latn-NG` | Review digital media versus broadcast-media wording, MIDI tracks versus songs, quarter-note timing and schema/source terms; verify hooked letters and apostrophe handling. |
| `pt` | `pt-BR`, `pt-PT` | Review the generic Portuguese voice consistently without silently changing the chosen regional policy; distinguish “Origem”/source, archive/folder terms and fixed count grammar. |
| `es` | `es-MX`, `es-ES` | Review neutral Spanish terminology/voice consistently across buttons and instructions; check Unified Diff, sparse entries, row limits and menu/keyboard phrasing. |

For each language, record the reviewer's name/locale, review date, exact catalog/input
revision, all 259 text keys plus bundle names/imported-type descriptions inspected,
approved wording and unresolved key-specific notes. A correction requires context
and rationale; do not mark a locale approved solely because all values exist or a
machine comparison found no differences.

Use the existing singleton companion and independently invoked signed Finder hosts
for these remaining checks:

- Confirm the effective language separately for companion, preview extension and
  thumbnail/system-facing descriptions, with process/artifact attribution. Resource
  selection in the explicit helper cannot establish cross-process behavior.
- Review all six tabs, menus, setup/provider limits, enabled/disabled/loading/error
  states, every shipped format description, privacy/fallback wording and the
  accessible labels/hints of source, outlines, records, Markdown, summaries and MIDI.
- Exercise default/minimum widths, long translations, 200% content enlargement,
  both appearances, increased contrast and unavailable fonts. Verify glyph shaping,
  punctuation, wrapping, focus visibility and no hidden/truncated actionable controls.
- Check keyboard navigation/shortcuts and VoiceOver reading/action names in each
  language. A resource lookup or screenshot cannot approve those interactions.
- Compare display, selection, Find and copied safe content using synthetic
  credentials, Unicode/bidi text and exact filenames/paths/numeric lexemes. Localized
  UI/metadata may change; user source spelling and concealed-copy behavior must hold.
- Verify region formatting independently of UI language for counts, decimal points,
  durations and any human-readable dates/byte units; preserve original file values.
  Storefront/country pricing remains independent of both.

Existing companion observations for German, Portuguese and Spanish are recorded in
[expansion](parallel-expansion-2026-10-04.md) and
[interaction continuation](interaction-continuation-2026-10-04.md). Their limited
default-size screens do not close this per-language checklist. Native-speaker review,
actual Finder effective-language behavior and full accessibility/layout remain open.
