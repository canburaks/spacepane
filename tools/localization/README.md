# Translation inputs

The canonical runtime resources are `PreviewRenderers/Resources/Localizable.xcstrings`
and `Configuration/Metadata.xcstrings`. These per-language dictionaries are editable
translation inputs, merged by `tools/merge_localizations.py`. Do not edit generated
`.lproj/Localizable.strings` or `.lproj/Localizable.stringsdict` files.

The user selected English, Turkish, German, French, Simplified Chinese, Japanese,
Hindi, Kurmanji in Latin script, Russian, Indonesian, Bengali, Hausa, Portuguese,
and Spanish. Portuguese and Spanish currently use generic language resources;
country-specific wording can be added after regional review. Language is independent
of App Store storefront, prices, file encoding and source content.

Each dictionary contains `strings` and `metadata` objects keyed by the original
resource identifiers. Keep printf argument types and multiplicity unchanged; use
positional placeholders when reordering multiple arguments. Preserve technical
names, brand placeholders, file suffixes and keyboard shortcuts. Never translate
user file contents. Translations are implementation drafts pending native-speaker,
VoiceOver, translated layout and real Finder-host review; resource completeness is
not approval to advertise reviewed localization.

Run `python3 tools/merge_localizations.py`, `python3 tools/generate_localization.py`,
then `python3 tools/validate_localization.py`. Merging validates every input before
writing either catalog and rejects missing/extra keys, changed placeholders and wrong
plural shapes. Both catalogs and all inputs are written with their keys sorted, so the
order never depends on who added a key last.

## Placeholders

Placeholder parity is checked for every key, at merge time and in the validator, not
only for keys that have a `PreviewStrings.format` call site. Formatted keys (a literal
`PreviewStrings.format(.key, ...)` call site) and bundle metadata are checked strictly:
every percent sign must start a supported directive or be `%%`, and each argument keeps
its position and type, so `%2$@ / %1$@` may reorder two arguments but `%1$@ / %1$@` may
not replace the second with the first. Every other key still compares its supported
directives, but a percent sign that does not start one, or is followed by a space
("100% done"), is literal text, because text-only resources never reach
`String(format:)` and need no escaping.

The validator discovers direct typed `PreviewStrings.format(.key, ...)` and
`PreviewStrings.count(.key, ...)` call sites. A dynamic use, or a case that
`PreviewStrings.swift` does not declare, is an error listed with its file and line next to
the validator's other findings; keep keys explicit. The merge skips such calls so it does
not wait for cases that have not been added yet.

## Plural strings

A count sentence ("1,204 lines", "3 likely secrets hidden") is a plural key. Never
build one with a bare `%lld`: that prints an ungrouped ASCII number and cannot select
a plural form. The String Catalog holds `variations.plural` per language (Apple's
xcstrings shape):

```json
"localizations": {"en": {"variations": {"plural": {
  "one":   {"stringUnit": {"state": "translated", "value": "%2$@ line"}},
  "other": {"stringUnit": {"state": "translated", "value": "%2$@ lines"}}}}}}
```

In a translation input and in an additions file a plural key is an object of
categories per language, never a string; a plain key stays a string. Mixing the two is
rejected at add, merge and validation time:

```json
"preview.count.lines": {"one": "%2$@ строка", "few": "%2$@ строки", "many": "%2$@ строк", "other": "%2$@ строки"}
```

Rules every variant follows:

- The first argument selects the category and is never printed. Each variant prints
  the second argument, `%2$@`, which `PreviewStrings.count` formats with the display
  locale (grouping, and digits such as Bengali numerals). A variant therefore carries
  no digits of its own and never `%1$lld`, and every variant of every language has the
  placeholders of the English `other` variant.
- Each language supplies exactly the categories its CLDR rules define for integers
  (`PLURAL_CATEGORIES` in `validate_localization.py`): `one` and `other` for English,
  Turkish, German, Hindi, Kurmanji, Bengali and Hausa; `one`, `few`, `many` and `other`
  for Russian; `one` and `other` for French, Spanish and Portuguese, which may add
  `many` (multiples of a million) and must when the English has it; `other` only for
  Simplified Chinese, Japanese and Indonesian. A language code without a row fails
  validation until one is added.
- One plural variable per key. The catalog comment says what is counted.

Generation writes, for every language that has at least one plural key,
`<language>.lproj/Localizable.stringsdict` beside `Localizable.strings`. It is Apple's
property list: `NSStringLocalizedFormatKey` `%#@count@` and a `count` dictionary of type
`NSStringPluralRuleType`, value type `lld`, with one entry per category. In
`Localizable.strings` the plural key is written as the format `%#@count@`, so a plain
lookup of the key still finds a value (`PLURAL_FORMAT_IN_STRINGS` in
`validate_localization.py` turns that off if a Mac run shows Foundation preferring the
`.strings` entry to the stringsdict). A language with no plural key gets no stringsdict
and a stale one is removed. The format and the property list shape live in
`validate_localization.py` (`PLURAL_FORMAT`, `stringsdict_entry`), which the generator, the
validator and both input tools share.

In Swift call `PreviewStrings.count(.key, value, locale: locale)`. The validator requires
a count call site to name a plural key and rejects `PreviewStrings.text` or
`PreviewStrings.format` on one, which would show the raw `%#@count@`. Category selection by
Foundation, SwiftPM's processing of the generated file and the locale digits are verified
on macOS by `PluralStringsTests`, not by these Python checks.

## Additions files

Workstreams never edit the catalogs or the inputs. Each adds
`tools/localization/additions/<workstream>.json` in the format `tools/add_localizations.py`
accepts, plus one extra field per key, `case`, naming the `PreviewStrings.Key` case that
will refer to it:

```json
{
  "preview.table.truncatedSummary": {
    "case": "previewTableTruncatedSummary",
    "comment": "Shown under a data-summary table when only the rows the preview read are shown.",
    "en": "Only the first rows the preview read are shown.",
    "tr": "...", "de": "...", "fr": "...", "zh-Hans": "...", "ja": "...", "hi": "...",
    "ku-Latn": "...", "ru": "...", "id": "...", "bn": "...", "ha": "...", "pt": "...", "es": "..."
  }
}
```

Every language and a translator comment are required; the comment says whether the key is
formatted and what each placeholder is. `add_localizations.py` ignores `case`, rejects keys
that already exist (reviewed text is never replaced), checks every value as merging does and
writes nothing unless every entry is valid. A plural key gives an object per language, as
above. The lead applies each file once at integration with `add_localizations.py`, adds the
cases to `PreviewStrings.swift`, then runs `merge_localizations.py`,
`generate_localization.py` and `validate_localization.py`. Every file adds distinct keys and
the tools write sorted output, so parallel workstreams do not conflict in the catalogs.

## Lints and allowlists

`validate_localization.py` fails on: a missing, empty or mismatched value; wrong plural
categories, placeholders or digits in a variant; a count call site for a key that is not
plural; stale or missing generated resources; and any catalog key that neither
`PreviewStrings.swift` nor the format catalog references. A key kept on purpose goes in
`unreferenced-allowlist.json` as `{"keys": {"the.key": "why it stays"}}`; the validator warns
when an entry is referenced again or no longer exists, so retire the entry then.

It only warns (the exit status never changes; `--verbose` lists every item instead of the
first five) about:

- values identical to English outside `technical-names.json` (`{"names": [...]}`, the
  English values that stay as they are, such as format and product names); text with no
  letters outside placeholders is skipped;
- a straight apostrophe between letters in English or French values, where a curly one
  (U+2019) is expected;
- French punctuation: an ordinary space before `: ; ? ! »` or after `«`, which breaks the line
  there, and no space at all; the space is a no-break space, U+00A0 (or the narrow U+202F);
- the Hausa glottal stop (hamza, as in `nau'in` and `na'ura`) written with any apostrophe or
  quotation mark between two letters; it is U+02BC MODIFIER LETTER APOSTROPHE, a letter, so a
  word stays whole in selection, search and sorting, and quote substitution and the English and
  French apostrophe rules never touch it (`HAUSA_GLOTTAL_STOP`; the native reviewer may pick U+2019
  instead, which is one constant and one run of the normalizer below);
- German quotation marks other than `„…“` (U+201E and U+201C): straight quotes, the English
  closing mark, guillemets, and a mark that is not paired;
- German formal address (`Sie`, `Ihnen`, `Ihr*`) and mid-sentence uppercase informal address
  (`Du`, `Dir`, `Dich`, `Dein*`), keeping sentence-initial third-person `Sie` (`Sie enthält…`,
  `Sie werden…`);
- a translation longer than its language's budget (below);
- English values over 12 words for keys whose comment mentions a header or notice. A key under
  `format.` is skipped, because a format description is a File Types row, not a header or notice.

`ShippedTypographyTests` in `test_localization.py` holds the French, Hausa and German rules to
zero warnings on the shipped catalog. The mechanical ones, French spaces and the Hausa
character, are fixed by `python3 tools/normalize_localization_typography.py --write` for the
translation inputs and by adding `--additions tools/localization/additions/<workstream>.json` for
an additions file before the lead applies it; without `--write` it only reports. Run `merge` and
`generate` afterwards. The tool never inserts a missing space and never touches German quotes or
address forms.

### Length budgets

A translation may have at most `ratio × the English characters` for English values of up to 60
characters (longer English text wraps), and never less than 16 characters, so a one-word label
cannot warn. The ratios: 1.5 for German, French, Russian, Spanish, Portuguese, Indonesian and
Turkish; 2.0 for Bengali, Hindi, Kurmanji and Hausa; 0.8 for Simplified Chinese and Japanese,
whose full-width characters are about twice a Latin letter, so 0.8 of the English count is about
1.6 times its width. Characters are counted without combining marks and format characters (a
Devanagari consonant with its virama counts once). The table is `LENGTH_BUDGETS` in
`validate_localization.py`. The summary lists the largest overshoots first. A flagged value is
not wrong, it is a prompt for a reviewer to look at the string in its control; the ones a reviewer
accepts go in `length-allowlist.json`:

```json
{"keys": {"appearance.wrapLines": {"languages": ["fr"], "reason": "Checked at 640 pt in the sidebar row."},
          "action.undo": "Fits every button; checked in all languages."}}
```

A text entry accepts every language; an object limits the acceptance to its `languages`. A reason
is required, and an entry that accepts nothing (the key is gone, or nothing exceeds the budget any
more) is reported so it can be retired.

### Separators and direction

Strings never join two values with a hyphen, a slash or an arrow (decision 027, Q-161): they read
the same in a right-to-left layout only when the relation is in words, in the language's own
phrase for "of" or "total" (`%1$lld of %2$lld`, `%1$lld von %2$lld`, `%2$lld में से %1$lld`),
or in a mark that is neutral in direction. The one structural mark is a path through System
Settings, written with `>` (U+003E): it is a mirrored character, so it turns around inside a
right-to-left run, where an arrow (U+2192) keeps pointing right. Kept as they are: the em dash of
`window.title` and the Russian dash, which are punctuation, an en dash for a range, a slash between
alternatives that names them (`front/side/top`, `1/2/3`, `+/−`, `key/value`), and `KML / KMZ`, two
technical names.

### Tone, register and translator prompt

Avoid direct forms of address across translations. Write neutrally and descriptively in the
platform's UI style: use infinitives for actions, hints and recovery steps (*Die Datei in einem
Texteditor öffnen*, not *Öffnen Sie die Datei…*), nominalizations for clauses (*vor dem
Entpacken*, *beim Drücken von „Wiedergabe“*), and neutral determiners (*auf dem Mac*, *mit den
aktuellen Einstellungen*, *Zugriff auf den Benutzerordner*) instead of possessive pronouns.

In German (`de`), never use formal `"Sie"` (`Sie`, `Ihnen`, `Ihr*`). When direct address is
genuinely unavoidable, use informal `"du"` (`du`, `dir`, `dich`, `dein*`, spelled lowercase
mid-sentence per Duden). Keep valid sentence-initial third-person `Sie` when referring to a
feminine or plural noun such as *die Datei* or *Signaturen* (*Sie enthält Binärdaten…*, *Sie
werden nicht geprüft…*).

Reusable translator prompt snippet:

> Translate into natural, concise macOS UI copy. Avoid addressing the reader directly: prefer
> neutral statements, infinitives for instructions and tooltips, nominalizations (e.g. *vor dem
> Entpacken*), and neutral articles (*auf dem Mac*, *den Benutzerordner*) instead of *you/your*.
> In German (`de`), never use formal *Sie/Ihnen/Ihr\**; if direct address cannot be avoided, use
> informal *du/dir/dich/dein\** (lowercase mid-sentence per Duden) and German quotes `„…“`.
> Preserve printf placeholders (`%@`, `%1$@`, `%2$@`, `%lld`), technical names, keyboard
> shortcuts and `>` in System Settings paths.

Generated `.strings` files are compared with the catalog through `plutil` when it is
installed. Without it (Linux), a strict reader accepts only the generator's own output: the
header comment, then one JSON-quoted `"key" = "value";` line per entry. The generated
`.stringsdict` is read with `plistlib` on every platform. Run
`python3 tools/test_localization.py` for focused format, plural, merge, add and lint checks,
also included in `--check`.

Inspect a rebuilt signed app and its two embedded extensions with
`python3 script/check_bundle_localizations.py --app PATH_TO_APP` (use the selected
Xcode `DEVELOPER_DIR` when needed). This checks all canonical values and metadata
through explicit Foundation locale lookup in the supplied artifacts, regional and
unsupported-language fallback, Unicode argument preservation and unchanged resources.
It does not launch hosts or change language preferences, and does not establish actual
companion/Finder effective language, layout, VoiceOver or native-speaker approval.
The per-language review queue and precise evidence are in
`docs/validation/language-quality-2026-10-04.md`.
