# Competitor parity program

Date: 2026-10-05. Status: accepted at the user's request ("close the gaps between all competitors by implementing their features in parallel"); implemented and integrated on 2026-10-05, see [the integration validation](../validation/parity-program-2026-10-05.md). Finder routing and signed-host behavior remain unverified. The source analysis is [the competitor landscape](../market/2026-10-05-competitor-landscape.md). Every competitor feature there is a vendor claim, not a tested fact; this program implements our own original versions within the repository's existing safety, privacy, modularity and localization rules.

## Scope

Twelve parallel workstreams, each with its own decision record and validation record. Each one adds catalog formats, adapters, presentations and tests through the existing pipeline. Nothing here claims Finder routing, thumbnail invocation or release readiness until it is observed.

| Workstream | Gaps closed (competitors) | Decision |
|---|---|---|
| archives | RAR 4/5 and 7z listings, bzip2 and xz streams with TAR listings, ZIP-based Java archives (Unfold, Super Quick Look, iPreview, folder/archive specialists) | 013 |
| listings | Folder depth, hidden items, dates, kinds, totals; sortable Files table and nested Tree for every listing; table filtering, sorting and striping (Unfold, Super Quick Look, SpacePeek, FolderPlus, QuickestLook) | 014 |
| markup | Markdown contents/TOC, task lists, footnotes, alerts, front matter, math, strikethrough, RTL paragraphs; LaTeX, BibTeX reference styles, AsciiDoc, reStructuredText, Org, Fountain (Unfold, Peek, QLMarkdown, Super Quick Look) | 015 |
| diagrams | Native Mermaid and draw.io diagrams (Unfold, Super Quick Look, Peek, QLMarkdown) | 016 |
| packages | `.app`, IPA, APK/AAB, provisioning profiles, certificates, installer packages, disk images, torrents (Unfold, LookQuick, QuickLook for IPA & APK, Apparency, Suspicious Package, ProvisionQL) | 017 |
| data | Parquet, Avro, Arrow/Feather, NumPy, HAR, GeoJSON/GPX/KML, richer SQLite tables and schema (Super Quick Look, Quick Data Insights, Python Data Viewer, Fast SQLite Viewer, JSON Loupe, GPX Preview) | 018 |
| code | Language-aware highlighting for many more languages and names, INI/config, logs, JSONC/JSON5, lock files, Apple config files, more subtitle formats, formatted minified JSON, partial previews of large text (Unfold, QuickestLook, Super Quick Look, PeekCode, JSON Loupe, Simple Quick Look) | 019 |
| ebooks | EPUB, FB2, CBZ comics, MHTML text, notebook figures, and the bounded image presentation they need (Unfold, Book Preview, Quick Preview, Python Data Viewer) | 020 |
| interaction | Outline filtering, go to line, copy all, copy key/value/path, temporary zoom, provider badge, live reload (Peek, PeekCode, JSON Loupe, FinderPeek, Unfold, LookQuick) | 021 |
| thumbnails | Concealed content thumbnails for text, code, data, tables, databases and embedded covers (PreviewCode, Fast SQLite Viewer, Python Data Viewer, GoodQuickLook) | 022 |
| settings | Preferences schema 6, built-in color schemes with separate light/dark choices, new behavior switches, provider-conflict diagnostics in the companion (LookQuick, QuickestLook, PeekCode, Code Peek+) | 023 |
| mesh | STL, OBJ, PLY and 3MF through the existing neutral geometry renderer (iPreview, Universal 3D Previewer, mesh-peek, Eyemesh, MakersPreview) | 024 |

## Shared contracts agreed before parallel work

The lead added these before any workstream started, so families never edit each other's files:

- `TextSyntax` cases for the planned families, `SourceLanguageID`, `PreviewImage` and the `images`/`sourceLanguage` fields on parsed documents and presentations. Images bypass text concealment, so adapters only extract pictures that are document content (covers, pages, icons, notebook figures).
- `RequestContext.nameHint` (lowercased name and suffix, metadata only) and `RequestContext.options` (folder depth, hidden items), filled by the pipeline from the preference snapshot. Adapters never read preferences.
- Snapshot fields `reloadsOnFileChange`, `showsContentThumbnails`, `folderDepth` and `showsHiddenFolderItems` with defaults. The settings workstream persists them in schema 6.
- `ThumbnailPolicy.content`, `PreviewFailure.encryptedContent`, five new preview modes (Contents, Diagram, Pages, Files, Tree) with localized titles.
- `SafeModeContentView` and `SafeModeViewRegistry`: a derived mode supplies its own view; `NativePreviewView` creates it lazily and hosts it.
- `SummaryLabelSet`: each family registers the summary fields it owns and their localized labels.
- `ZIPArchiveReader`: one bounded ZIP/ZIP64 reader with CRC-checked member reads for every ZIP-based format.
- `ContainerEntry.modified` and `.encrypted`, written only when known.
- `script/sync_manifests.py` derives all Info.plist type lists from the catalog; `tools/add_localizations.py` adds a batch of keys in all 14 languages.
- Marker comments (`// [family]`, `# [family]`) in the shared registration points. Each family inserts only below its own marker.

## Rejected or deferred, with reasons

- **WebP, AVIF, fonts, PDF, Office, iWork, ordinary video/audio:** macOS previews these itself; registering them would compete with the system for no gain. Extra video codecs (MKV, WebM, AVI) need a codec stack of FFmpeg's size and stay out of scope.
- **Animated themes, custom CSS themes:** animation conflicts with reduced-motion accessibility, and CSS needs a web renderer this product does not use. Built-in color schemes and inert theme files cover the customization gap.
- **PlantUML rendering:** it needs Java or a remote server; the competitor uploads the file. PlantUML stays highlighted source.
- **Clickable links, local Markdown images, remote content:** links stay inert, and the extension has no access to sibling files.
- **Standalone viewer windows, a Finder action that bypasses provider choice:** the companion keeps one window and Try Preview stays behind Developer Mode. The provider-conflict diagnostics explain how to choose a provider instead.
- **Saved scroll positions:** they would be durable per-file history, which the product does not keep.
- **CBR and CB7 comics, RAR/7z member contents:** RAR decompression is proprietary and 7z payload decoding is beyond listing scope; listings show names only.
- **MOBI/AZW, DjVu, DICOM, FITS, PSB, EPS, CHM:** niche or heavy; each needs its own demand and dependency decision.
- **Hex dumps of unknown binaries:** an ASCII column can expose secrets that text concealment cannot reliably find.

## Integration

Each workstream works on its own branch in an isolated worktree, records its own decision and validation documents, and does not edit `CHANGELOGS.md` or `PLAN.md`. The lead merges the branches, resolves key-level unions in the catalog and string files, regenerates derived files (manifests, `.lproj` strings, appearance samples, website data), runs `--check`, `--test` and `--check-compiler` on the integrated tree, and records the program's outcome in the changelog and plan.
