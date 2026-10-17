# Decision 022 — Concealed content thumbnails

Date: 2026-10-05. Status: accepted at the user's request as part of the [competitor parity program](025-competitor-parity-program.md); implemented in the package and the thumbnail extension, **not yet observed in Finder**. See [the validation record](../validation/thumbnails-2026-10-05.md).

Amendment pending (2026-10-06, [decision 027](027-best-in-class-quality-program.md), owner decision D6a and Q-121): shape-only thumbnails with counts for tabular and columnar formats will be added once the Wave 1 thumbnail table exists; the rule that no cell value is drawn stays. Q-10 and Q-12 of the same record, applied 2026-10-06 without a compiler, make the thumbnail service decline summary-origin text and withhold secret-shaped files; both are queued for Mac verification.

Amended 2026-10-17 (App Store rejection-risk review, [finding 9](../reviews/2026-10-17-app-store-rejection-risk.md)): **the thumbnail extension registers only formats whose policy is `content`.** The sentence below, "both `generic` and `content` register the type", is withdrawn. The generated `QLSupportedContentTypes` of `Thumbnail-Info.plist` (315 types before, 262 after) no longer lists the 36 `generic` formats: folders (`public.folder`), every archive family (ZIP, TAR, GZIP, XIP, 7-Zip, bzip2, xz, JAR, WAR), disk images (`com.apple.disk-image-udif`), installer packages (`com.apple.installer-package-archive`), provisioning profiles, certificates and MIDI. Reason: nothing observed shows that Finder gains from a glyph for these types, and registering them would have SpacePane's glyph replace the system's own icon or thumbnail for every folder, archive, disk image and installer package on the Mac, cached by Finder. A format that has no content to draw gains nothing from a thumbnail provider. No host record observes a folder or archive thumbnail either way; if a later observation shows a benefit, a format can return to the list by setting `content`. `script/sync_manifests.py` and `script/validate_project.py` implement the rule, and `public.data` stays out of the list as before. `package.application` moved from `content` to `generic` in the same change, so app bundles keep their own icon; the glyph and content paths of the provider itself are unchanged and still answer for the registered types. A `generic` policy now means "previewed, never registered for thumbnails"; the provider still draws the glyph for a registered `content` format whose file cannot be summarized (`ThumbnailPolicyEvaluator` draws content only for the `content` policy).

## What changes

Until now every thumbnail was a content-free glyph: a light page with three rules, no preferences read, no parser run. [Decision 007](007-binary-inputs-and-safe-presentations.md), the plan's target data flow and the earlier catalog comment all stated that thumbnails stay content-free and never instantiate adapters. The user asked to close the gap with PreviewCode and the smittytone apps, Fast SQLite Viewer, Python Data Viewer, GoodQuickLook and the book/model viewers, which draw real content. This decision replaces that rule **only for catalog formats whose thumbnail policy is `content`**, and only through the safeguards below. Everything else keeps the glyph.

## Policy

`ThumbnailPolicy.content` was added to the shared contracts by the parity setup. The catalog now sets it for plain text, source code, JSON, JSON Lines, YAML, TOML, Markdown, diff, XML, property list, strings, strings dictionary, OPML, CSV, TSV, SubRip, WebVTT, NFO, Jupyter notebooks, `package.json` and SQLite. It keeps `generic` for environment files, ZIP, TAR, GZIP, XIP, folders, MIDI, IGES and STEP, and `none` for the extension-free text format (no thumbnail registration, system icon stays). Info.plist type lists do not change: both `generic` and `content` register the type.

A thumbnail request is answered in this order, and the first rule that applies decides:

1. The shared App Group snapshot cannot be loaded (no container, corrupt, unreadable, newer schema) — glyph. A missing document is first run and yields the defaults.
2. `showsContentThumbnails` is off — glyph, before the file is classified or read. The setting is a bool in the shared snapshot, **default on**; the settings workstream persists it and adds its switch.
3. Classification (metadata only, shared catalog) finds no supported type — glyph.
4. The user turned that file type off — glyph. **No adapter is constructed and the file is not read**; this is the same pipeline gate as previews.
5. The descriptor's policy is not `content`, or it is a geometry presentation — glyph. CAD and mesh thumbnails stay generic.
6. The shared pipeline runs with a strict thumbnail budget. Failure, timeout, cancellation or an unreadable, oversized, binary or malformed file — glyph.
7. The pipeline concealed any value — glyph (see below).
8. Otherwise the concealed presentation is drawn.

## What may be drawn

Only two inputs reach the page: `TextPresentation.text` after the pipeline's concealment, and validated `PreviewImage`s that adapters extracted as document content (cover, icon, page, figure). Never a file name, path, URL, date, size, raw bytes, sidecar or anything the pipeline did not pass through concealment. A test asserts that neither the file name nor its directory is among the drawn strings.

- **Text excerpt.** The first lines, in cells, fixed-pitch, clipped (source, configuration) or wrapped (prose, unless the text holds box or block drawing characters). Light semantic tones from a bounded per-line lexer over the concealed text. Leading blank lines are skipped, blank runs collapse, tabs expand, wide characters count two cells.
- **Grid.** CSV and TSV syntaxes, and plain text whose first lines are consistently tab separated, become a small grid through the same `DelimitedRecords` scanner the adapters use, so grid boundaries agree with the boundaries concealment used. Header row, rule, striped body rows, at most eight columns, cells clipped.
- **JSON outline.** Minified or long-line JSON becomes a YAML-like outline (keys with inline scalars, nesting by indent, collapsed beyond depth three) instead of one clipped line. Pretty-printed JSON keeps its own lines. JSON Lines and anything that is not exactly one value fall back to the excerpt.
- **Markdown-like text.** A bold heading plus body text; front matter, fences' markers, rules and link targets are dropped, task lists become checkboxes. Org and AsciiDoc use their own heading marker.
- **Notebook.** The first cells: markdown as heading and prose, code as source. Outputs are never drawn from the text.
- **SQLite.** The column names and first rows of the first loaded table page, read from the concealed summary. NULL and blob cells are drawn as symbols; table names and file names never appear.
- **Picture.** Cover, then icon, then page, then figure, at most three decode attempts. Covers and pages fit the canvas, icons are inset, figures sit on a page.

SQLite and notebooks are the only places that read a presentation by format identity: their text is JSON with a known layout. If the layout does not match (another workstream changes the summary), the thumbnail stays generic. It never falls back to drawing the raw summary JSON.

## Privacy safeguards

- **Concealed-only.** Nothing is drawn that the preview pipeline did not output. A synthetic secret in YAML, TOML, JSON, plain text, source, CSV, TSV, Markdown or a notebook never appears in any drawn string, tested with the withholding limit both at its default and lifted.
- **Withheld whole when anything was concealed.** If the pipeline's `redactionCount` is above `ThumbnailLimits.maximumConcealedValues` (default 0), the document is not summarized at all, pictures included. A thumbnail outlives the preview in a durable cache, and a file that visibly holds secret-like values is more likely to hold ones the filter missed. The cost is that some ordinary files (an example `password:` line) keep the glyph. The limit is a single value in one struct; relaxing it is a conscious later decision.
- **Sensitive formats stay generic.** Environment files, archives, folders, MIDI and CAD never reach a parser from the thumbnail path (tested with counting factories and a counting reader).
- **No picture bypass.** Images come only from adapters, which extract pictures that are document content. Decoding is allow-listed by ImageIO type (PNG, JPEG, GIF, TIFF, BMP, HEIC/HEIF, WebP, ICNS, ICO), refuses a declared size or the real size above 16 megapixels or an encoded size above 8 MiB, decodes only the first frame, never upscales, and caps the decode at the canvas's pixel extent.
- **No app-authored text.** The page draws file content and symbols only, so there is nothing to localize and no raw error text.

## Bounds

Text input is capped at 256 KiB (a larger file shows the glyph; head-only reads were rejected for now because truncating breaks JSON, XML, property lists and databases and would need per-format handling), output at 512 KiB, 100,000 JSON nodes, 300 ms pipeline deadline. SQLite gets 4 MiB of input and 500 ms because only the schema and a first page of rows are read. A one-second hard timeout, independent of the pipeline's cooperative deadline, answers with the glyph even if a native read or decode blocks. Each request builds its own pipeline, so the serial parsing worker of one request never queues another request's time budget. The page is built at most `rows × columns` cells for the requested size, so a larger thumbnail shows more of the page, not a larger font.

Quick Look exposes no cancellation callback to a thumbnail provider. Cancellation therefore means the deadlines above, plus Swift task cancellation honored by the service for any caller that cancels. The completion handler is called exactly once, by the single task that answers the request.

Amended 2026-10-06 ([decision 027](027-best-in-class-quality-program.md), Q-40, Q-120, Q-127; authored without a compiler, verification pending): the provider answers through a once-only reply gate armed on a Dispatch timer, so the single reply is the work's result or the timed-out glyph even when a read blocks; content thumbnails pass an admission of about half the active processors (at least one), waiters holding no thread and leaving the queue when cancelled; every reply carries the matched catalog suffix as its type badge (`ThumbnailBadge`, never derived from the file stem; whole-name matches and suffixes over eight characters get none); drawn runs lose bidirectional, zero-width and Tag characters through the shared `HiddenCharacters` classifier, and Markdown, AsciiDoc and Org comments are not drawn. The owner's answer on notebooks (D6, 2026-10-06): a notebook draws its first cells, never its first figure, because an output picture is untrusted document content that bypasses the text rules.

## Presentation

Thumbnails are not appearance adaptive: one light page in the glyph's style and 4:5 proportions, filling 76% of the shorter canvas side (the glyph keeps 64%, so the glyph is unchanged). Colors are the app's light palette, fixed; the user's color-scheme setting only decides whether tones are drawn at all (`syntaxStyle.usesColor`). Drawing uses Core Graphics, Core Text and ImageIO only, with no AppKit view and no main-actor work, inside the reply's drawing block after parsing, decoding and layout have finished.

## Caches

macOS keeps thumbnails in a durable cache and may show an older image after the user turns content thumbnails off, disables a file type, edits the file or changes the settings. This product does not clear shared caches. Turning the switch off or a type off controls **new** requests only; it is not a secure erase of thumbnails already drawn. The release notes and the setting's copy should say so. Because concealment is pattern based, a secret it fails to recognize can appear in a thumbnail and persist in that cache; this residual risk is the reason for the default-on switch being a visible choice, the withholding rule, the generic formats and the bounded excerpt.

## Architecture

- `PreviewThumbnails` is a SwiftPM library depending on `PreviewContracts`, `PreviewCore` and `PreviewPreferences` with the shared extension-safe flags. It has no AppKit, no format adapters and no CAD client. The extension composes `StandardFormatAdapters.registrations` and injects them (dependency inversion, as for previews), so `PreviewFormats` is linked by the extension and the tests, not by the library.
- The pure layers (policy, geometry and metrics, text and cell layout, lexer, shapes, grid, outline, picture fit) are tested without Quick Look or a context; the renderer is tested against `CGBitmapContext`.
- The thumbnail extension now links `PreviewCore`, `PreviewFormats` and `PreviewThumbnails` in addition to its former contracts, preferences and renderers products. It still never links `PreviewCADFormats`. `validate_project.py` pins this exact product set. `HostedConfiguration` still comes from `PreviewRenderers`; only its Foundation-only file is referenced.
- Adding a format needs no thumbnail code when its presentation is text with a known `TextSyntax` or carries `PreviewImage`s: set `thumbnail: content` on its catalog entry and register its adapter. A genuinely new shape (for example a new JSON summary layout) belongs in `ThumbnailContentBuilder`.

## Not decided here

Partial-file thumbnails for files over the input cap, a content thumbnail for CAD or mesh formats, appearance-adaptive thumbnails, per-format thumbnail switches and the settings page copy are separate decisions. Whether Finder shows these thumbnails, which provider Quick Look selects for a type, and how the cache behaves on the supported OS versions are unverified; see the validation record.
