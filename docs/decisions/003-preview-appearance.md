# Saved preview appearance

Date: 2026-10-03. Status: accepted design; implementation and validation tracked in [PLAN.md](../../PLAN.md).

## Ownership

`PreviewContracts` owns stable theme IDs and validated typography values. `PreviewPreferences` persists them with file-type choices in one versioned atomic snapshot. The companion is the only persistent writer; a Finder request consumes its loaded snapshot. Theme names and every control label belong to the localization catalog, independently of the stable IDs.

`PreviewRenderers` owns AppKit font resolution, palettes, paragraph/text attributes and semantic syntax styling. It receives already-concealed presentation text. It never selects a parser or reads source files. A syntax hint travels from the format adapter through redaction into the presentation model; rendering does not branch on suffixes or concrete format IDs.

The companion's Appearance settings and live synthetic sample reuse the native preview renderer. The sample contains no real credentials or user data. App chrome continues to use system appearance; the selected theme affects preview content.

## Initial controls

- Theme: system, light, dark and high contrast.
- Font: system monospaced default or an installed family; regular, medium, semibold or bold weight; italic.
- Font size, line spacing, character spacing, ligatures, tab width, wrapping and optional line numbers (off by default).
- Reset Appearance restores appearance defaults without changing enabled file types.

Saved values have finite numeric bounds. Font names are bounded inert strings, not file paths or executable content. Unavailable fonts and unsupported requested traits use a safe fallback with a localized notice. No font downloads or installation are involved.

The first syntax styling supports JSON keys, strings, numbers and literals. Plain text remains plain. This is not a claim of general source-language highlighting. The JSON styler only reads concealed output, preserves its exact characters and bounds both scanning and token accumulation; content beyond its styling limits remains readable without syntax colors.

## Update and migration behavior

Schema 4 stores the complete appearance state including `showsLineNumbers`. Schemas 1/2 migrate with supported existing values; schema 3 strictly decodes every previous appearance field and defaults only the new flag to false. All migrations retain enablement policy. Missing required current fields are corrupt data, not defaults. Invalid current-version data and unknown schemas retain the existing fail-closed content policy.

Appearance-only edits restyle the current safe presentation without rereading or reparsing the source. They preserve text selection and scroll position where layout permits. File-type policy changes still cancel/re-evaluate the request and immediately clear disabled content. A new request resets content interaction state even if its text matches the previous file.

Future Finder requests use persisted appearance. This does not promise that an already-open Finder preview or cached thumbnail refreshes immediately. Generic thumbnails remain content-free and do not adopt code colors or fonts.

## Logical line numbers

The native gutter indexes UTF-16 starts in concealed text and draws only visible logical-line labels. Soft-wrapped continuations do not receive new numbers. CRLF is one separator; CR, LF, NEL, line separator and paragraph separator are supported. Empty text has no numbers; a terminal separator creates a final empty line. Labels are outside text storage, selection, find and copied output. A collapsed sensitive value can change displayed line positions, so these numbers are not an original-source mapping.

The gutter inherits resolved fonts and theme contrast, hides without reserved width for disabled/unavailable/loading content, and describes its purpose through localized accessibility metadata rather than thousands of accessibility children. Complete keyboard/VoiceOver verification remains a separate gate.

Appearance uses one adaptive control/sample tree so resizing does not create two native live-preview instances. This is an identity/layout decision, not proof that an external inspection-service failure is fixed.

## A sample for every format — 2026-10-04

The live sample is no longer one fixed JSON text. A menu in the sample frame lists every catalog format, grouped as on the File Types page, and the sample shows a built-in synthetic item of the chosen format: source code, rendered Markdown, a table, an outline, an archive listing, a database, MIDI controls or a 3D model. The saved appearance stays global; this change lets the user see its effect on each kind of preview. Per-format appearance overrides remain out of scope.

Samples are authored by `script/generate_appearance_samples.py` and stored as one bounded manifest in the companion's resources. `--check` requires exactly one sample per catalog format, so adding a format without a sample fails the project check. The two CAD samples are the repository's own analytic boxes. No sample contains user data or a secret-like value; a model check requires zero concealed values.

The chosen sample is written to a private temporary directory and read through the shared pipeline by `AppearanceSampleSession`, so detection, budgets, concealment and rendering are the production path and no parser is duplicated. One request is active at a time, a newer choice drops a late result, and closing the window removes the temporary files. Appearance edits still restyle the kept result without rereading it. The previous sample stays on screen while the next loads, so the single native pane keeps its identity.

A sample is shown even when its type is turned off in File Types, including the default-off CAD types, because it is app-authored content and not a user file. The request uses default preferences with only that type enabled; the user's choices still govern every real file in all three hosts. A caption says when the shown type is turned off. The sample content itself is not localized.

## Remaining scope

Temporary zoom, additional language grammars, per-token style editing, per-format overrides, profile import/export and variable-font axes remain separate plan items. Reviewed translations, baseline macOS 15 runtime checks, full accessibility checks and signed extension-host rendering remain explicit validation gates.
