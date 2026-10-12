# Decision 012 — Safety findings ("Safety Lens")

Date: 2026-10-05. Status: accepted at the user's request; implemented with package-level evidence in [the validation record](../validation/safety-lens-2026-10-05.md). Native-speaker review, Finder-hosted rendering and accessibility review are open in [PLAN](../../PLAN.md#safety-lens-and-insight-features).

## Context

[The unique-feature research](../market/2026-10-05-unique-feature-opportunities.md) found that no Quick Look competitor reports what is risky or surprising inside a file. The user asked to implement, in order:

1. Three quick wins: notebook health, archive risks, and a secret inventory with a sync-folder warning and a redacted copy.
2. The hidden-content detector, as the headline feature.
3. A CSV data profile and CAD dimensions.

Features 1 and 2 report the same kind of thing: a typed fact, a severity, a count and a position. Renderers derive every view from the **concealed** text, so they cannot recompute facts that only the source or the parser knows (notebook execution counts, ZIP encryption flags, which secret pattern matched). Those facts must travel with the presentation. This is the "genuinely new presentation capability" that [decision 001](001-format-extensibility.md) allows to change a shared contract.

## Decision

### Contract (`PreviewContracts/PreviewFindings.swift`)

- `PreviewFinding` holds a `kind`, a `severity`, a `count` (at least 1), `lines` and a typed `detail`.
- `PreviewFindingKind` is a closed `String` enum with stable dotted raw values (`archive.unsafePath`), grouped by owning feature. The renderer maps kinds to wording with an exhaustive `switch`, so adding a kind without localized text does not compile. Each new kind is a deliberate one-line shared-contract change.
- `PreviewFindingSeverity` is `info`, `caution` or `warning`. Each kind has a default; a producer may raise it.
- `PreviewFindingDetail` is a closed enum of typed values: an execution sequence, cell positions, a compression ratio, expanded bytes, a sync provider, or decoded text.
- `ArchiveEntryRisk` names the per-entry risk codes written into archive summaries, so the container writer and the renderer share one typed vocabulary.
- `PreviewFindings.normalized` merges findings of one kind (summing counts, uniting lines, keeping the highest severity and the first detail). It orders them by severity, then by declaration order, and keeps at most 32.

### What findings may carry

- **No source values.** Kinds, counts, numbers and positions only.
- **One exception:** `decodedText`, text decoded from invisible characters (Unicode Tags). It must pass the shared privacy filter before it is attached. It is bounded to 512 characters, compares by exact code units, and is displayed only as inert label text.
- A cloud-storage folder name is never carried; it can contain an account address. Only the provider enum is.

### Lines

`lines` are one-based logical lines of the **displayed, concealed** text, the same numbering the line-number gutter uses. They are ascending, unique and bounded to 64 per finding; `count` still includes every occurrence. A producer that cannot state a displayed line leaves `lines` empty. Archive entries use the summary itself instead, and notebook findings use cell positions. This follows the AGENTS rule never to imply original line positions after concealment.

### Flow

```text
adapter ── ParsedTextDocument.findings ─┐
privacy ── SafeText.findings ───────────┼─ PreviewFindings.normalized ─> TextPresentation.findings ─> NativeFindingsBanner
pipeline-level scans (hidden content, ──┘
sync-folder location)
```

- Disabled types never reach an adapter, so they never produce findings.
- Thumbnails stay content-free and ignore findings.
- Geometry presentations carry no findings.

### Presentation (`PreviewRenderers/Findings/`)

- `NativeFindingsBanner` sits between the status line and the mode control, in the companion and in the Finder extension alike. It shows one row per finding, most serious first. After six rows a "More findings: N" row summarizes the rest. It collapses to zero height when empty, and clears for loading, disabled, unavailable, cancelled and geometry outcomes.
- Each row is a selectable wrapping label. Its accessibility label begins with the localized severity, so VoiceOver reads one item per finding. Severity is carried by the symbol's shape. Color only reinforces it: orange for warnings, text color otherwise, which keeps contrast under every theme.
- **Copy Concealed Text** appears whenever the presentation concealed anything. It writes the whole concealed text, whatever the current mode shows, to the pasteboard. It is an explicit user action, never reads source bytes, and announces its confirmation to VoiceOver. Tests use a private pasteboard.

### Localization

- Every message is a typed `PreviewStrings` key with translator context.
- There is no plural resource generator yet, so wording uses the existing count-label style ("Code cells that never ran: %lld."). It never builds singular or plural sentences.
- Numbers, byte counts and position lists use the presentation locale. Execution sequences are joined with arrows; none of the 14 languages is right-to-left.
- Brand names of sync services are localizable keys, because Apple localizes "iCloud Drive" in some languages.

## Feature boundaries

| Feature | Producer | Owns | Notes |
|---|---|---|---|
| Notebook health | `JupyterNotebookAdapter` | `PreviewFormats/Notebooks` | Execution order, gaps, unexecuted cells, saved errors and a reproducibility hint. Nothing runs. |
| Archive risks | ZIP/TAR/GZIP/XIP listing adapters through one shared analyzer | `PreviewFormats/Containers`, archive labels in `SafeSchemaLabels` | Entries are listed and flagged, never extracted. See the behavior change below. |
| Secret inventory | `DefaultPrivacyFilter`; a pipeline-level location check | `PreviewCore` | Kinds come from the same patterns that conceal. The location check is a URL test with no file access. |
| Hidden content | A pipeline-level scan of the concealed text for text inputs | `PreviewCore` scanner; an *Invisibles* derived mode in renderers | Source mode stays exact for copy and find; markers appear only in the derived mode. |
| CSV profile, CAD dimensions | A renderer-side profile of concealed tables; geometry measurements in the CAD adapter | See their sections below | They are not findings. |

### Behavior change: risky archive entries are listed instead of failing

Before this decision, a ZIP, TAR or XIP entry with an absolute path or a `..` component made the whole archive "malformed", and an encrypted ZIP entry made it "unsupported". Listing such an entry is safe: nothing is extracted, and the name is shown as inert text. Failing hid the most useful fact. Those entries are now listed and reported as `archive.unsafePath` or `archive.encrypted`.

The following still fail as before:

- names containing NUL or other C0 control characters;
- central-directory encryption;
- structural inconsistencies, such as overlapping members or header mismatches.

### Hidden content

The detector has three parts.

- **Shared classifier.** `HiddenCharacters` (contracts) is the single classifier. The scanner and the renderer both use it, so the banner and the markers always agree. It reports:
  - bidirectional controls;
  - zero-width and other invisible format characters;
  - Unicode Tags;
  - variation selectors outside a valid sequence;
  - private-use characters.

  It skips characters that are expected in their context:
  - emoji joiners and selectors;
  - joiners in scripts that need them (Devanagari, Bengali, Arabic, Persian and others);
  - subdivision-flag tag sequences;
  - ideographic variation sequences;
  - direction marks in lines that hold right-to-left letters.
- **Scanner.** The pipeline calls it after concealment, on the displayed text, only for text that is the file's own:
  - registrations of the `.text` input path;
  - binary adapters that report a decoded encoding, such as files without an extension and XML property lists.

  Archive and folder summaries, SQLite, MIDI and geometry are not scanned. It also reports:
  - words that mix Latin with Cyrillic or Greek look-alike letters;
  - HTML and link-reference comments in Markdown. GitHub and most viewers hide these; this app's Rendered view shows them as text.

  In AI-agent instruction files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `SKILL.md`, `mcp.json` and `*.mdc`, it adds a context finding and raises invisible-character, look-alike and comment findings to warnings. Text decoded from Unicode Tags passes through the injected privacy filter before it is attached. ASCII text costs one byte test.
- **Invisibles mode.** A derived preview mode shows each hidden character as a technical, non-localized marker such as `⟨U+202E RLO⟩`. A run of tag characters becomes one `⟨TAG ×N⟩` marker that states only the count: their code points would bypass the concealment applied to the decoded message.
  - Markers never contain line breaks, so line numbers match the banner.
  - Copy and find in this mode use the marked text. Source stays byte-for-byte the concealed text.
  - The mode is offered only when invisible-character findings exist. It is unavailable above 100,000 hidden characters or 4 MiB, and never truncated.

### Invisible characters inside secret key names

While building the scanner, a pre-existing gap appeared: a zero-width character typed into a key name (`pass<ZWSP>word = …`) stopped plain-text concealment, because the key pattern and the key normalization treated it as a boundary or as part of a letter.

- `SecretFieldPolicy` now owns one shared assignment pattern. That pattern, and the variants used by notebooks, comments and archive summaries, accept invisible format characters, the combining grapheme joiner and variation selectors inside keys.
- `isSensitive` ignores those characters before normalizing.

This only adds concealment, and the hidden character is still reported.

### CSV and TSV data profile

A **Profile** preview mode, placed after Table, shows one row per source column with these fields:

- **Type:** empty, integer, decimal, boolean, date, text, mixed or concealed.
- **Missing:** a count and a locale percentage.
- **Distinct:** a count, capped at 10,000.
- **Minimum and maximum:** the exact source spelling of the extreme cell, never reformatted.
- **Mean:** for numeric columns.
- **Most common:** the three most common values.
- **Distribution:** an 8-bin sparkline with a spoken description for VoiceOver.
- **Notes:** mixed types, leading zeros, date formats that differ, surrounding spaces and duplicate names.

Table-level notes appear in the status line: rows profiled, ragged rows, shared names and concealed columns.

Rules:

- The profile is derived only from the concealed table.
- **Concealed columns:** a column is concealed when its header names a secret field, or when any of its cells, or its header, holds the concealment token. The token is matched by code units, not characters. A concealed column shows only how many of its cells are empty; empty cells are never concealed.
- **Computation:** lazily, the first time Profile is selected, on at most the first 10,000 rows.
- **Shared token:** the concealment token has one owner, `SecretFieldPolicy.concealmentToken`, so the privacy stage and every safe view agree on it.

### CAD measurements

The CAD adapter derives measurements from the decoded mesh after import: surface area, volume and the number of connected bodies. Volume is reported only when the welded surface is closed and consistently oriented. It also reads a few header facts from the first 64 KiB of the file:

- the STEP application protocol or IGES version;
- the originating system, only when it is at most 64 characters of a technical alphabet.

The importer, its wire format and the XPC protocol are unchanged. Author, organization, file name and timestamps are never read into the model. Values are approximations of the displayed tessellation, not certified engineering data. Independently tessellated IGES faces can leave cracks, so the volume of such a model is reported as unavailable rather than guessed.

## Consequences

- One shared-contract change: `findings` added with empty defaults to `ParsedTextDocument`, `SafeText` and `TextPresentation`, and one merge line in the pipeline. Existing adapters and hosts are unchanged and their tests still pass.
- Adding a finding kind touches the shared enum, the wording switch, one string key and its 13 translations. Everything else stays in the owning feature module.
- Findings are claims about file content. The Finder preview, the companion and the copy action all use the same pipeline. None of this changes which provider macOS chooses.

## Validation

Contract tests cover the following:

- normalization and its bounds;
- exact code-unit comparison of decoded text;
- pipeline pass-through from adapter and privacy stages;
- disabled types producing no findings;
- wording and placeholder resolution for every kind;
- banner rows, overflow, collapse and clearing;
- Copy Concealed Text, using a private pasteboard.

Translations of the new keys are drafts pending native-speaker review, like the rest of the catalog. Finder-hosted rendering of the banner, VoiceOver and keyboard review, and translated layout remain open; see PLAN.

## Amendment — copy hygiene (D15 / Q-155, 2026-10-08)

The approved quality-program decision narrows the earlier exact-copy rule: when the current concealed presentation has a Unicode Tags finding or a hidden listing-name finding, explicit copies remove only unsafe Tag spans classified by `HiddenCharacters`. Classification uses the whole displayed text before intersecting a selection, so partial selections of valid subdivision flags remain exact. Other invisible characters, ordinary whitespace and source code units remain unchanged. The on-screen Source storage, search and selection are not modified. No Tag payload is decoded or placed on the clipboard.

This policy applies to native text selections, multiple selections, Copy All, Copy Concealed Text, outline key/value/path actions, tables, listings and Contents. Rich-text copies use an ephemeral attributed snapshot retaining inert style attributes; links, attachments and opaque attributes are omitted under the finding gate because their serialized values can carry content absent from the visible string. The original attributed storage is unchanged. A selection made entirely of unsafe Tags intentionally replaces previous clipboard content with an empty string.

Only a successful write produces the one copy chip and one announcement. When Tags were removed, their wording is “Copied; invisible payload removed”; otherwise it remains the ordinary confirmation. Tests use private pasteboards, exercise AppKit's native representations and include failed writes and replacement generations. This is package/native evidence; signed Finder-hosted clipboard and spoken VoiceOver acceptance remain open.

## Amendment — shared decoded-text and listing-name classification (Q-150, 2026-10-08)

The post-concealment scanner now includes truthful converted text from ebooks/web archives and actual decoded text from binary/random-access inputs. Summary origin is excluded before input-path dispatch. Compressed text reports its real encoding; opaque and container-summary results do not invent one. The shared classifier and byte prefilter additionally cover interlinear, musical and Egyptian formatting controls, stray Mongolian selectors and adjacent Braille blank runs while preserving expected script/emoji/flag contexts.

Archive and folder names use the same classifier through `ListingNameRiskAnalyzer`, with a separate scalar bidi predicate preserving filename-direction warnings. The new `listing.hiddenCharacters` finding counts affected entries once, with no names, lines or decoded text, and a localized `hiddenCharacters` per-entry risk. Folders inspect metadata only and do not inherit archive execution or link-escape judgments. When annotation overhead alone exceeds a listing budget, count findings survive beside the original unannotated summary. This uses one owner without scanning generated summary JSON as if it were file text.
