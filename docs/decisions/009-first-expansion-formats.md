# 009 — First M4 expansion: delimited tables, captions, text art and notebooks

Date: 2026-10-04. Status: implemented locally with package, corpus and companion-model
evidence; signed Finder preview/thumbnail routing for these types is unverified.
Validation is recorded in [the expansion report](../validation/first-expansion-2026-10-04.md).

## Scope

The plan's first M4 expansion names notebooks, subtitles, CP437/NFO text art and
CSV/TSV tables. Six independently switchable logical types were added through the
standard catalog, registration, manifest and settings path. "Code snippets" remains open.

| Format ID | Canonical type | Suffixes | Group | Safe modes (initial first) |
|---|---|---|---|---|
| `data.csv` | `public.comma-separated-values-text` | `csv` | Structured | Table, Source |
| `data.tsv` | `public.tab-separated-values-text` | `tsv` | Structured | Table, Source |
| `text.subrip` | imported `org.webmeister.spacepane.type.subrip` (plain text) | `srt` | Text | Source, Cues |
| `text.webvtt` | `org.w3.webvtt`, also imported for older systems | `vtt` | Text | Source, Cues |
| `text.nfo` | imported `org.webmeister.spacepane.type.nfo` (text) | `nfo`, `diz` | Text | Source |
| `text.jupyter-notebook` | imported `org.jupyter.ipynb` (conforms to `public.json`) | `ipynb` | Text | Rendered, Source, Outline |

The imported identifiers are app-selected declarations, not claims that a format owner
publishes them. On the development Mac, `UTType(filenameExtension:)` resolved `.srt` to a
third-party `com.goodsnooze.srt` declaration, `.ipynb` to a third-party
`com.quicklookpro.file.ipynb` declaration (conforming to source code), and `.nfo`/`.diz` to
dynamic types. Finder may therefore select another provider or reach this extension
through a broader declared ancestor; suffix classification inside the extension still
selects the specific format and its enablement choice. Only observed host results can
establish routing.

## Shared-contract changes

Each change is additive and leaves existing formats' behavior unchanged:

- `TextSyntax` gains `commaSeparated`, `tabSeparated`, `subRip` and `webVTT` semantic hints so
  safe derived views can select their parser without adapter or host knowledge.
- `TextEncoding.codePage437` and optional `ParsedTextDocument.decodedEncoding` let a binary
  adapter that decodes text itself report provenance. The pipeline's binary path uses it
  instead of a fixed UTF-8 label; every existing binary adapter leaves it `nil`.
- `NativePreviewMode` gains `table` and `cues`. `SafePreviewModes.initialMode(for:)` now owns
  the initial-mode rule: Summary for schema-labelled formats as before, Table when a table
  exists, Rendered for notebooks; otherwise Source.
- A new **table presentation capability**: `SafeTable` and `NativeTablePreviewView`, hosted by
  the existing preview view beside Source and Outline. CSV/TSV are its first users; it is
  intended for later grid views such as SQLite row pages. Restyling never rebuilds data.
- `DelimitedRecords` in `PreviewContracts` is one bounded, cancellable record grammar used
  by the CSV/TSV adapter on raw text and by the renderer on concealed text. Column-based
  concealment is only safe if both sides agree on cell boundaries, and contracts are the
  only module both may import. Subtitle and notebook views follow the existing precedent of
  a renderer-local bounded parser over safe text, kept aligned by mirrored tests.

No orchestration, privacy-filter, host-controller or companion change was required beyond
the one-line provenance assignment and the preview view's table hosting.

## Format contracts

**CSV/TSV.** CSV follows [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180): quoted fields,
doubled quotes, delimiters and line breaks inside quotes, LF/CRLF/CR records. TSV follows
the IANA `text/tab-separated-values` registration: one record per line with literal quotes;
a field beginning with an unbalanced quote is rejected because it may be a spreadsheet's
undefined multi-line field. Structural errors fail closed (`malformedDocument`); there is
no fallback to unconcealed source. Privacy uses exact whole-cell ranges (quotes included)
so concealed text keeps its shape: every cell in a column with a sensitive header, cells
containing a sensitive assignment, columns a wider row could have shifted a value into,
and the value after a short bare-name key cell such as `api_key` (in a two-column first
record too, which may be a headerless export). Formulas, numbers and dates are never
evaluated or coerced. The table view shows at most 20,000 rows, 64 columns, 4,096 UTF-16
units per cell and 500,000 cells, with a localized truncation notice; Copy returns only
safe cells of selected rows as tab-separated lines. Semicolon-separated files, header
detection and Excel-style quoted multi-line TSV are unsupported.

**SubRip/WebVTT.** SubRip follows the de-facto block format described by
[Matroska](https://www.matroska.org/technical/subtitles.html) with documented tolerances
(optional index, `.` milliseconds, trailing coordinates). WebVTT follows the
[W3C grammar and parser](https://www.w3.org/TR/webvtt1/): mandatory signature, header,
NOTE/STYLE/REGION blocks and cues with optional identifiers and settings. Timestamps are
range-checked and `end ≥ start`. Any block that is not a valid cue or permitted block is
`malformedDocument`; nothing is skipped silently. Styles, regions, settings and markup are
never applied. Cue text uses the shared heuristic concealment; NOTE blocks containing a
secret assignment are concealed whole. The Cues view lists exact source timestamps and
joined payload lines. It declines (structure fallback) when concealment collapses cues,
detected by comparing with the adapter's cue count.

**NFO/DIZ.** Valid UTF-8 (optional BOM dropped) decodes as UTF-8; anything else decodes
with the complete [CP437 table](https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/PC/CP437.TXT).
A trailing DOS end-of-file run is dropped. NUL, other C0 controls except TAB/LF/CR, and
DEL are `binaryContent`, matching the shared text path; ANSI escape art is not rendered.
Shared output, line and line-length limits apply after decoding.

**Jupyter notebooks.** nbformat 4 (any minor version) per the
[format description](https://nbformat.readthedocs.io/en/latest/format_description.html);
other versions are `unsupportedFormat`, wrong shapes `malformedDocument`. Cells are never
executed and widgets, HTML, JavaScript, SVG and images are never rendered or decoded.
Because code and output live in JSON strings, the adapter adds whole-string concealment
for decoded sensitive assignments, continuation lines of an open value, PEM blocks,
`--password=` flags and environment subscripts, on top of key-based JSON ranges. The
Rendered view maps Markdown cells verbatim, code/raw cells to collision-safe fences with a
localized label and execution count, stream/`text/plain` outputs to bounded blocks,
errors to `ename: evalue` plus a traceback without terminal escapes, and every other MIME
type to a localized "not shown" placeholder. Large notebooks stop at a cell boundary with
a notice. A notebook with an embedded base64 image line longer than 32 KiB currently fails
the shared line limit (`lineTooLong`), and files above 1 MiB exceed the input budget; a
per-registration budget or explicit image-payload omission needs a separate decision.

## Consequences

The normal format-addition path held: adapters, catalog entries, registrations, fixtures
and localized strings, plus the deliberate presentation additions above. All 30 catalog
formats run through the deterministic adversarial corpus. Finder routing, thumbnails,
VoiceOver, translated layout and native-speaker review remain open gates.
