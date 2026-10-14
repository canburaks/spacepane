# SpacePane existing research digest for expansion

Compiled 2026-10-13 from existing repository documents; no new research.

Paths and line numbers are relative to the repository root `/Users/cbs/Github/spacepane/spacepane`. Line numbers refer to the files as they stood on 2026-10-13.

**Read for this digest:** `docs/market/2026-10-06-competitor-ux-ui-analysis.md`; the seven files in `docs/market/ux-research/`; `docs/market/2026-10-10-app-store-listing-research.md`; `docs/decisions/013` to `024`; `PLAN.md` lines 150-310; `Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json` (ids and suffixes, via `python3 -I`). Also read because the 013-024 records defer to them for reasons: `docs/decisions/025-competitor-parity-program.md` (lines 39-49, "Rejected or deferred"), `docs/decisions/028-no-cad-in-version-1.md` (lines 7-17, 66), and short extracts of decisions 009, 010, 012, 022, 026 and 027. The two landscape documents were grepped for competitor claims with line numbers only; they were not summarised.

**Catalog baseline.** 74 format ids; 305 suffixes in `extensions`; 412 with `filenameAliases`. Absent from the catalog: `step`, `stp`, `iges`, `igs` (CAD is off for version 1); every image format (`png`, `jpg`, `tif`, `heic`, `webp`, `avif`, `svg`, `psd`, `eps`); video and audio other than `mid`/`midi`; fonts; `pdf`; Office and iWork suffixes; `rtf`; `map`; `tcx`; `snippet`; `mdc`, `apib`, `textbundle`, `multimarkdown`, `mdml`, `ft`; `xsd`, `xsl`, `xslt`; `mobi`, `azw`, `azw3`, `djvu`, `cbr`, `cb7`; `dicom`, `fits`, `chm`; `zst`, `lz4`, `lzh`, `cab`, `arj`, `lzma`; and the 3D exchange formats `usdz`, `usd`, `glb`, `gltf`, `fbx`, `dae`, `3ds`, `dxf`, `wrl`, `abc`, `gcode`. Present among 3D: `stl`, `obj`, `ply`, `3mf`.

---

## 2. Competitor capabilities SpacePane still lacks (vendor claims; nothing tested)

Every competitor item below is a vendor claim or a marketing-screenshot observation recorded in these documents. Nothing was installed or tested. Where a document gives no reason, the table says "none recorded". "Unverified" means the documents do not say whether SpacePane has the item.

### 2a. 3D and CAD

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| STEP `.step`, `.stp` preview and thumbnails | Universal 3D Previewer; StepPreview; Unfold (3.2.0 changelog, per the landscape correction) | `docs/market/2026-10-05-competitor-landscape.md:223-224`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md:26` | Off in version 1. "Version 1.0 ships without the STEP and IGES 3D previews" (`docs/decisions/028-no-cad-in-version-1.md:7`). OCCT is LGPL 2.1 and the licence is not cleared (028:11-12). Entries are kept outside the catalog (`AGENTS.md`). |
| IGES `.igs`, `.iges` | None found: "No app found previews IGES" (landscape:229). Four standalone viewers at $4.99 to $24.99 (listing:179) | `docs/market/2026-10-05-competitor-landscape.md:229`; `docs/market/2026-10-10-app-store-listing-research.md:179` | Same as STEP (028:7, 028:11-12). |
| SolidWorks `.sldprt`, `.sldasm`; G-code; XCS and LAC laser files; `.scad` | Universal 3D Previewer (landscape:223); MakersPreview (landscape:225); mesh-peek (landscape:227) | the three landscape lines | None recorded. |
| FBX; glTF and GLB (with Draco); COLLADA `.dae`; 3DS; WRL; DXF; Alembic `.abc`; USDZ | Eyemesh, 16 formats (landscape:226); iPreview FBX (`docs/market/ux-research/2026-10-06-breadth-leaders.md:177`, `:182`); MakersPreview GLB (`docs/market/ux-research/2026-10-06-folders-archives-3d.md:292`); Universal 3D Previewer, Alembic (landscape:223) | as listed | None recorded. Context: decision 024 covers only STL, OBJ, PLY and 3MF (`docs/decisions/024-mesh-formats.md:5-17`). Its Hydra note names USD, Alembic and MaterialX as declared by Apple's extension on the development Mac (024:53). macOS USDZ look is "not documented" (`docs/market/ux-research/2026-10-06-system-and-benchmarks.md:81`). |
| Rendered thumbnails for 3D models (STL, OBJ, PLY, 3MF, CAD) | StepPreview "preview and thumbnails" (landscape:224); MakersPreview thumbnails (landscape:225); mesh-peek colour and thumbnails (landscape:227) | as listed | STL, OBJ, PLY use thumbnail policy `none` so Apple's glyph stays (`docs/decisions/024-mesh-formats.md:59-61`). 3MF uses a generic glyph. Content thumbnails for CAD or mesh are "Not decided here" (`docs/decisions/022-content-thumbnails.md:71-72`). |
| Wireframe, skeleton, cross-section, section tool, gizmo, animation | Eyemesh (landscape:226; folders-archives-3d.md:419); iPreview skeleton and wireframe (breadth-leaders.md:182) | as listed | "Not promised": "Colours, materials, textures, UV maps, vertex colours, animation, skeletons ... cross-sections or wireframes" (`docs/decisions/024-mesh-formats.md:70`). |

### 2b. Images, documents, media (macOS-owned or unlisted)

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| Standalone PNG, JPEG, TIFF, GIF previews | Folder Preview thumbnails for images (landscape:211) | landscape:211 | None recorded. Apple lists images among the types Quick Look previews natively (`docs/market/ux-research/2026-10-06-system-and-benchmarks.md:72`). |
| WebP, AVIF | iPreview (landscape:131); niche list (landscape:240) | as listed | "macOS previews these itself; registering them would compete with the system for no gain" (`docs/decisions/025-competitor-parity-program.md:41`). |
| HEIC, PSD | GoodQuickLook (landscape:151) | landscape:151 | None recorded. Note: `docs/decisions/010-companion-sidebar-redesign.md:44` says "47 formats including PDF, DOCX and PSD" is "the real catalog". That is stale; none of those types is in the catalog. |
| SVG (standalone) | GoodQuickLook (landscape:151); QuickestLook "Web: HTML, XML and SVG" (landscape:118); Super Quick Look (landscape:90); Folder Preview thumbnails (landscape:211) | as listed | No standalone decision recorded. Indirect reasons: notebooks never render SVG (`docs/decisions/009-first-expansion-formats.md:92-93`); ebook images are never SVG (`docs/decisions/020-ebooks-comics-and-images.md:39`); no web renderer (`docs/decisions/025-competitor-parity-program.md:42`). |
| PDF; searchable `.ePDF` workaround | Peek Quick Action (landscape:142); Folder Preview thumbnails (landscape:211) | as listed | "macOS previews these itself" (025:41). |
| Office (DOCX, XLSX, PPTX); iWork (Pages, Numbers, Keynote); RTF; OpenDocument | LookQuick marketing card with DOCX (breadth-leaders.md:106); Unfold FAQ on macOS-owned types including RTF, Office, iWork (breadth-leaders.md:68) | as listed | Office and iWork: "macOS previews these itself" (025:41). RTF: none recorded. |
| Video: MP4, MOV, M4V, MKV, WebM, AVI, FLV, WMV, OGV | QLVideo (landscape:174); QLPlay and QLMedia (landscape:234); LookQuick video player window (`docs/market/2026-10-10-app-store-listing-research.md:127`) | as listed | Ordinary video and audio are macOS-owned (025:41). Extra codecs "need a codec stack of FFmpeg's size and stay out of scope" (025:41). |
| Audio: MP3, Ogg | GoodQuickLook MP3 (landscape:152); QLMedia Ogg (landscape:234) | as listed | MP3: macOS-owned (025:41). Ogg: none recorded. MIDI is supported (`audio.midi`). |
| Fonts: TTF, OTF, WOFF | LookQuick "fonts" (landscape:100); GoodQuickLook OTF and TTF (landscape:152) | as listed | Fonts are in the macOS-previewed list (025:41). |

### 2c. Ebooks, comics, archives, containers

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| MOBI, AZW, AZW3 | Quick Preview (landscape:214); Book Preview (landscape:236) | as listed | "niche or heavy; each needs its own demand and dependency decision" (025:48). Out of scope (`docs/decisions/020-ebooks-comics-and-images.md:26`). |
| DjVu | Book Preview (landscape:236) | landscape:236 | Same as MOBI (025:48). |
| CBR, CB7 comics | Unfold "CBZ and CBR/CB7" (landscape:76); Book Preview (landscape:236) | as listed | "CBR and CB7 comics" in the not-included list (025:47); "CBR/CB7" not promised (`docs/decisions/013-archive-listings.md:187`). CBZ is supported. |
| Ebook reading features: page turning, reading themes, resume position, font controls, chapter list | Unfold book themes "Aa" (breadth-leaders.md:75) and chapter list (breadth-leaders.md:295); Quick Preview two-page reader (folders-archives-3d.md:185) | as listed | "page-turning fidelity, reading themes, resume position or font controls" not promised (`docs/decisions/020-ebooks-comics-and-images.md:221`). Contents navigation is "the markup workstream's mode" (020:223). |
| Recursive folder size, folder total, size breakdown, largest items, dashboard | SpacePeek (landscape:213); FolderPlus dashboard (landscape:212) | as listed | "No recursive size, no complete folder total" (`docs/decisions/014-folder-and-listing-views.md:159-165`); "no number is ever a recursive total" (014:53-60). `largestItems` is described as "the stretch item" (014:53-60); its status is not stated. |
| Folder grid or gallery view | FolderPlus gallery (landscape:212); SpacePeek grid (landscape:213); list and grid toggle as table stakes (folders-archives-3d.md:408) | as listed | None recorded. The recorded listing views are the Files table and the Tree (`docs/decisions/014-folder-and-listing-views.md:19`). |
| Password-protected archives: prompt or decrypt | FolderPlus (landscape:212) | landscape:212 | "RAR or 7z member passwords; encrypted headers (reported, not listed)" (`docs/decisions/013-archive-listings.md:185`). Encrypted ZIP members are listed but not inspected (`PLAN.md:300`). |
| Inline preview or extraction of an archive member | Archive Quick Look "extracts small previewable files on demand" (landscape:216); Super Quick Look inline preview (`docs/market/2026-10-06-competitor-ux-ui-analysis.md:100`) | as listed | "Extracting, previewing or decompressing archive members" not promised (`docs/decisions/013-archive-listings.md:184`). Rejected: "no extraction; listings only" (ux-analysis:100). |
| LZMA, LZ4, XZ-style containers; `.zst`, `.cab`, `.arj`, `.lzh`, `.ear` | Folder QuickLook (landscape:217) | landscape:217 | "not claimed" (`docs/decisions/013-archive-listings.md:36-38`); "not promised" (013:187-188). `.ear` would need a declaration other Java tools own (013:36-37). |
| BMW diagnostic files; UTM and VMware virtual machines; animated JXL | LookQuick (landscape:100) | landscape:100 | None recorded. |
| Archive footer with compressed, uncompressed and ratio; "Archive vs Unpacked" sizes | LookQuick (`docs/market/ux-research/2026-10-06-breadth-leaders.md:158`); FolderPlus (`docs/market/ux-research/2026-10-06-folders-archives-3d.md:80`) | as listed | Partly present: listed bytes and an extreme-compression finding exist (`docs/decisions/014-folder-and-listing-views.md:53-60`; `PLAN.md:209`). A ratio footer is not recorded. |

### 2d. Markup, diagrams, text

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| Mermaid diagram types beyond the supported set: gantt, journey, mindmap, timeline, gitGraph, C4 | Apps that draw Mermaid (named in `docs/decisions/016-native-diagrams.md:7-9`) | 016:7-9 | "gantt ... not implemented" (`docs/decisions/016-native-diagrams.md:70-71`); other types unsupported (016:70-72). |
| PlantUML rendered diagrams | Super Quick Look (landscape:90); PlantUML QuickLook (landscape:238) | as listed | "rendering needs Java or a remote server, and the competitor uploads the file. It stays highlighted source" (`docs/decisions/016-native-diagrams.md:14`). |
| HTML and XML rendered as web pages; XSD, XSL, XSLT | QuickestLook (landscape:118); Super Quick Look markup list including XSD and XSL/XSLT (landscape:90); SpacePeek "passive HTML previews" (landscape:213) | as listed | Web rendering: "CSS needs a web renderer this product does not use" (025:42). XML is `data.xml`, shown structured. XSD, XSL, XSLT: none recorded. |
| Markdown: `.mdc`, `.apib`, TextBundle, `.multimarkdown`, `.mdml`, `.ft` | QLMarkdown (landscape:172); Markdown Preview by Anybox, TextBundle (landscape:192); Bitfield (landscape:195) | as listed | None recorded. |
| Typeset math (KaTeX) | Markdown Preview by Anybox (landscape:192) | landscape:192 | Typeset formulas not promised (`docs/decisions/015-markup-documents.md:112`). A Unicode math subset ships (015:51, "## Math"). |
| Copy-on-code-block and whole-document copy icons | Peekdown (landscape:194); other apps named in `docs/market/ux-research/2026-10-06-code-markdown.md` | as listed | Planned, unchecked: "copy on code blocks" (`PLAN.md:247`). |
| Markdown contents rail that shows when wide | Peek rail; Unfold outline sidebar (breadth-leaders.md:295) | as listed | Contents mode exists (`docs/decisions/015-markup-documents.md:57-60`). The rail is unchecked: "Contents rail when wide" (`PLAN.md:247`). |
| Prose font family for Markdown | PreviewMarkdown body font popup (code-markdown.md:173) | code-markdown.md:173 | Open owner decision: "a prose font family ... worth a schema 7 field" (`docs/market/2026-10-06-competitor-ux-ui-analysis.md:109`). Prose uses the system face (`docs/decisions/015-markup-documents.md:127-129`). |
| Space key toggles rendered and source; print or PDF export | Markdown Peek (landscape:196) | landscape:196 | Space toggle: unverified. Print or PDF export: none recorded. |
| Source highlighting for 200+ languages | Syntax Highlight (landscape:171); Source Code Preview 50+ (landscape:183) | as listed | 84 language profiles and 181 suffixes (`docs/decisions/019-code-config-and-text-breadth.md:9-10`). No reason recorded for the gap. |
| Hex dump of unknown binaries | None named in these documents | n/a | Out of scope (`docs/decisions/019-code-config-and-text-breadth.md:17`). |
| JSON source maps `.map` | JSON Loupe (landscape:202) | landscape:202 | None recorded. |
| JSON Pretty Text (expand escaped `\n`); dual line gutters | QLook JSON (landscape:203) | landscape:203 | None recorded. |

### 2e. Data and databases

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| SQLite table picker across several tables | Fast SQLite Viewer (landscape:204) | landscape:204 | "A table picker over multiple tables is not implemented" (`docs/decisions/018-columnar-scientific-and-geo-data.md:142-143`); "No table picker for SQLite" (018:186). |
| SQLite ER diagram | Fast SQLite Viewer; Quick Data Insights (`docs/market/ux-research/2026-10-06-data-db.md:239`) | as listed | None recorded. A schema grid exists (`docs/decisions/018-columnar-scientific-and-geo-data.md:132-144`). |
| Lazy paging over millions of rows | Fast SQLite Viewer (landscape:204) | landscape:204 | None recorded. Reads are bounded by row and cell limits (018:141). |
| SQLite data-grid thumbnails with real values | Fast SQLite Viewer (landscape:204) | landscape:204 | Rejected. See section 4. |
| Copy `CREATE TABLE`; extract notebook code to Python; export `.py` or Markdown | Quick Data Insights (landscape:205); Python Data Viewer (landscape:206) | as listed | None recorded. |
| Heatmap or chart for `.npy` and `.npz` | Python Data Viewer (landscape:206) | landscape:206 | None recorded. The Plot mode covers geographic paths and points only (`docs/decisions/018-columnar-scientific-and-geo-data.md:123-126`). |
| TCX (training activity files) | GPX Preview (landscape:239) | landscape:239 | "TCX ... not decoded" (018:186-187). |
| Map view with basemap tiles | GPX Preview (landscape:239) | landscape:239 | Plot draws "no map tiles and no network" (018:124-125). Design, not a recorded rejection. |
| Avro bzip2, xz and zstandard codecs; Parquet ZSTD, LZ4, Brotli, LZO; Feather v1; nested Parquet columns | None named | n/a | "are not decoded" (018:186-188). |

### 2f. Preview interaction and presentation

| Item | Competitor(s) | Source | Reason recorded for not having it |
|---|---|---|---|
| Shortcut labels on screen; shortcut sheet | Peek, the only app that labels shortcuts (`docs/market/2026-10-06-competitor-ux-ui-analysis.md:22`) | ux-analysis:22 | Planned, unchecked: "info popover with the shortcut sheet" (`PLAN.md:245`). Self-audit: shortcuts "Revealed anywhere in UI? ... Right-click" (`docs/market/ux-research/2026-10-06-spacepane-self-audit.md:230-252`). |
| In-preview find with match counts; jump-to-line HUD | Peek (ux-analysis:22; code-markdown.md, first recommendation) | as listed | Partly present: Go to Line (`docs/decisions/021-preview-interaction-and-live-reload.md:43`); outline and table filter (021:51). Match counts and a HUD: unverified. |
| Trust statement card ("Offline by design") | Quick Data Insights (`docs/market/2026-10-06-competitor-ux-ui-analysis.md:40`) | ux-analysis:40 | Planned, unchecked: "info popover" (`PLAN.md:245`). |
| Masked secrets with a reveal switch | QuickestLook (`docs/market/ux-research/2026-10-06-closest-rivals.md:223`); Gander (`docs/market/2026-10-10-app-store-listing-research.md:101-104`) | as listed | None recorded. By design, copy and filter see only concealed text (`docs/decisions/021-preview-interaction-and-live-reload.md:11`). "Copy Concealed Text" writes the concealed text (`docs/decisions/012-safety-findings.md:53`). |
| Compact density for the Finder preview pane | LookQuick and iPreview show both sizes (ux-analysis:54) | ux-analysis:54 | Planned, unchecked and unmeasured: "compact density" (`PLAN.md:245`, `:252`); threshold "without measuring real pane widths" is not promised (`docs/decisions/026-world-class-ux-program.md:114`). |
| Settings: live sample pinned above controls on every format page; settings search | Unfold (`docs/market/ux-research/2026-10-06-breadth-leaders.md:74`) | breadth-leaders.md:74 | Theme page sample is built (`PLAN.md:172`). Per-type sample choice is open (`PLAN.md:173`). Settings search: unverified (File Types search is in the contract, `PLAN.md:287`). |
| Several app interface languages (competitors declare 4 to 11) | Source Code Preview 11, GoodQuickLook 10, iPreview 6, Unfold 4 (`docs/market/2026-10-10-app-store-listing-research.md:105-106`) | listing:105-106 | "Version 1.0 ships English only" (`AGENTS.md`), although the chosen set has 14 languages (`AGENTS.md`). |
| Right-to-left language support | Markdown Preview by Anybox (landscape:192) | landscape:192 | "no RTL language is shipped (decision 008 set)" (`docs/market/ux-research/2026-10-06-spacepane-self-audit.md:262`). |
| Per-token scheme editor; wide scheme library (Base16, Kwrite, Godot, jEdit) | Syntax Highlight (landscape:171; `docs/market/ux-research/2026-10-06-code-markdown.md:79`) | as listed | "per-token style editing, per-format overrides, profile import/export ... remain separate plan items" (`docs/decisions/003-preview-appearance.md:52`). Twelve built-in schemes ship (`docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:137-156`). |
| Sibling pager: next and previous file in the same folder | SpacePeek (`docs/market/ux-research/2026-10-06-folders-archives-3d.md:415`) | folders-archives-3d.md:415 | Security section of decision 015 lists "no sibling lookup" among the rules (`docs/decisions/015-markup-documents.md:98`). |

---

## 3. Ideas already proposed in our own documents, not implemented

Status wording is quoted from the source. "Unchecked" means the plan box is `- [ ]`.

| Idea | Status wording (quoted) | Source |
|---|---|---|
| Facts strip, limits strip, one privacy row with a height cap, info popover, Copied chip, gutter hairline, compact density | "ux-chrome: ..." unchecked | `PLAN.md:245` |
| Designed non-content states; failure copy with next steps | "ux-copy: title/body failure strings with next steps and limit values ..." unchecked | `PLAN.md:250`; self-audit top-20 #1 in `docs/market/ux-research/2026-10-06-spacepane-self-audit.md:267-294` |
| Default-first mode order and labels; keyboard mode switching | "ux-modes-structure: default-first mode ordering and labels, keyboard mode switching ..." unchecked | `PLAN.md:246` |
| Typed outline rows with counts; path bar; quiet grid with range footer; row-action and filter parity; JSONL separators | same box, unchecked | `PLAN.md:246` |
| Markdown: Contents rail when wide; copy on code blocks; blockquote bar; capped measure | "ux-documents: capped measure, Contents rail when wide, ... copy on code blocks ..." unchecked | `PLAN.md:247` |
| Folder and archive summary header; hidden counts; encrypted states | "ux-containers-3d: folder and archive summary header and hidden counts, encrypted states ..." unchecked | `PLAN.md:248` |
| 3D control cluster; dimensions with declared units; one-time camera hint | same box, unchecked | `PLAN.md:248` |
| Companion: setup trail; pinned Theme sample with scheme gallery; renderer pills; Undo for bulk actions; Try Preview inspector; page hierarchy | "ux-companion: ..." unchecked. Partial status: a pinned Theme sample and scheme gallery were "integrated" in Round 3 (`PLAN.md:269`) | `PLAN.md:249`, `:269` |
| Thumbnails: type badge; shape with counts for tabular and columnar formats | "ux-thumbnails: ..." unchecked. "shape-only thumbnails with counts ... will be added once the Wave 1 thumbnail table exists" | `PLAN.md:251`; `docs/decisions/022-content-thumbnails.md:5-7` |
| Validate the twelve acceptance gates in signed host and Finder | "Validate the twelve acceptance gates ..." unchecked | `PLAN.md:252`; Wave 4 unchecked at `PLAN.md:275` |
| Prose font face for Markdown, notebooks, ebooks | "prose face if approved" unchecked; open owner question | `PLAN.md:247`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md:109` |
| JSON, YAML, TOML, XML open in Outline by default | "Should JSON, YAML, TOML and XML open in Outline by default (self-audit P6)?" (open) | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:108`; deferred in `docs/decisions/026-world-class-ux-program.md:116` |
| Content-true 3D thumbnails, opt-in per CAD type | "until the owner decides the five questions in the analysis" | `docs/decisions/026-world-class-ux-program.md:116`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md:111`; "Not decided here" at `docs/decisions/022-content-thumbnails.md:71-72` |
| Sample reveal in Finder (bundled sample file) | Open question; "D3 A bundled sample reveal from the setup trail" listed in decision 027 (status not recorded) | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:110`; `docs/decisions/027-best-in-class-quality-program.md:399` |
| Per-format appearance overrides; sample choice in the real window (incl. CAD samples) | "decide whether per-format appearance overrides are wanted (a separate schema change)" unchecked | `PLAN.md:173` |
| Live resize across breakpoints; Open System Settings link; Website row | unchecked | `PLAN.md:174` |
| Shared master switch; default view mode; configurable limits "(schema 6)"; feedback About links; technical identifiers following the name | "Decide separately whether to add ..." unchecked. Stale or unclear: schema 6 shipped with behaviour switches (`docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:13-27`) | `PLAN.md:176` |
| VoiceOver, Full Keyboard Access, large text, increased contrast; translated layouts | unchecked | `PLAN.md:156`, `:175`, `:225` |
| Dotfiles, other volumes, competing `public.data` provider; executable-bit files | "decide whether to cover executable-bit files" unchecked. "executable-bit files are not covered" | `PLAN.md:183`; `docs/decisions/019-code-config-and-text-breadth.md:97-99` |
| App Store acceptance of the `public.data` declaration; remove stale extension copies | unchecked | `PLAN.md:184` |
| Observe new formats, modes, thumbnails, live reload in signed Finder hosts | unchecked. "not yet observed in Finder" | `PLAN.md:196`; `docs/decisions/022-content-thumbnails.md:3` |
| Signed build: Security CMS, code-signing calls, provider scan, file monitoring in sandbox | unchecked | `PLAN.md:197` |
| Native-speaker review of new strings; Kurmanji and Hausa lowest confidence | unchecked | `PLAN.md:198`, `:226` |
| Carried-forward gaps: notebook figures above about 24 KiB; whole-file formats over 1 MiB (HAR, geographic, torrents); only the first Mermaid fence; assumed millimetres for STL, OBJ, PLY; table position across live reloads | "Decide the carried-forward gaps ..." unchecked. The notebook limit was superseded by a 16 MiB input budget (`docs/decisions/020-ebooks-comics-and-images.md:200-207`) but the plan box still lists it | `PLAN.md:199` |
| Units for STL, OBJ, PLY: flag "units are assumed"; face count saturates above 100,000 | "Requests for the lead" (status not recorded) | `docs/decisions/024-mesh-formats.md:61-66`, `:76-83` |
| Source performance: text 216 ms, JSON 434 ms, JSON Lines 365 ms, source 250 ms (warm p95) above the 200 ms target | "still exceeds 200 ms" unchecked | `PLAN.md:160` |
| Incremental preview memory and Finder first-visible timing | unchecked | `PLAN.md:161` |
| Hidden-content scan: binary property lists; iCloud "Desktop & Documents" and File Provider in sync warning; JSON Lines profile; more AI-agent file names | "Decide whether to cover:" unchecked | `PLAN.md:229-233` |
| IGES shape sewing for volume reporting | "Decide on sewing IGES shapes ..." unchecked; needs native and dependency review | `PLAN.md:228` |
| CAD return | "Settle the licence first." Options listed; no outcome recorded | `docs/decisions/028-no-cad-in-version-1.md:66` |
| Missing format coverage: snippets (planned; the catalog has no snippet suffix) | "notebooks, subtitles, snippets, NFO, CSV/TSV next" | `PLAN.md:292` |
| Archives: prefix-decoding partial listing; larger budget for compressed streams | "is the natural follow-up and needs a shared-contract decision" | `docs/decisions/013-archive-listings.md:196-198` |
| Packages: larger budget or tolerant ZIP mode for apps over about 3,000 members | "it belongs to the lead" | `docs/decisions/017-package-and-certificate-inspection.md:86-87` |
| SQLite: table picker; `table` label not in the database label set | "until the lead lets the data sets also cover SQLite" | `docs/decisions/018-columnar-scientific-and-geo-data.md:142-143`, `:188-190` |
| Markdown: source highlight delegation for six markup syntaxes | "Until then they use the generic lexical rules." Status not recorded | `docs/decisions/015-markup-documents.md:106` |
| Notebook labels: escape `$`, `~`, `^` | "Also escape `$`, `~` and `^`." Status not recorded | `docs/decisions/015-markup-documents.md:107` |
| Geometry viewport colours follow the syntax scheme | "Until then the geometry viewport uses Standard colors." | `docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:121-123` |
| Folder depth or hidden-item change does not reload an open folder preview | "does not reload an open folder preview in Try Preview until that method also compares requestOptions" | `docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:124-125` |
| Thumbnails read `TextPresentation.images`; front-matter display of `drm` and `partial` | "Requests" (status not recorded) | `docs/decisions/020-ebooks-comics-and-images.md:233-234` |
| Partial-file thumbnails over the 256 KiB cap; per-format thumbnail switches; appearance-adaptive thumbnails | "head-only reads were rejected for now"; "Not decided here" | `docs/decisions/022-content-thumbnails.md:50`, `:71-72` |
| Live reload: event-only open unverified; sandboxed reopen after atomic save unverified; network volumes | "Not promised" | `docs/decisions/021-preview-interaction-and-live-reload.md:35-41` |
| Folder `largestItems` | "the stretch item" (status not stated) | `docs/decisions/014-folder-and-listing-views.md:53-60` |
| Mermaid: gantt | "not implemented" | `docs/decisions/016-native-diagrams.md:70-71` |
| draw.io colours, images, links, pages | "Not promised" | `docs/decisions/016-native-diagrams.md:199-202` |
| Ebook chapter count notice | Amended 2026-10-10: "Showing n of m chapters" | `docs/decisions/020-ebooks-comics-and-images.md:237` |
| Parquet and Avro partial decode; nested columns | "not decoded; those columns or files show their structure without values" | `docs/decisions/018-columnar-scientific-and-geo-data.md:184-188` |
| Geographic distances estimated; antimeridian not handled | "Longitude wrap at the antimeridian is not handled." | `docs/decisions/018-columnar-scientific-and-geo-data.md:193-195` |
| Dates shown as ISO strings, not locale-formatted | "the label mechanism has no date field type" | `docs/decisions/013-archive-listings.md:199-201` |
| Source-code breadth for `.conf` and `.cfg` as INI | "an outline appears only when every line fits" | `docs/decisions/019-code-config-and-text-breadth.md:100` |

### Stale or conflicting statuses to know before reusing these documents

- `docs/decisions/010-companion-sidebar-redesign.md:44` says "47 formats including PDF, DOCX and PSD" is "the real catalog". The catalog has 74 formats and none of those types.
- `PLAN.md:191` records "76 catalog types, 309 suffixes". Two CAD entries were removed later, so the count is now 74 and 305 (`AGENTS.md`).
- `docs/decisions/014-folder-and-listing-views.md:159-165` says the depth and hidden-item controls appear "only once the settings workstream persists them" and that there is "no live reload". Both are superseded: schema 6 persists them (`docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:13-27`) and live reload exists (`docs/decisions/021-preview-interaction-and-live-reload.md:13`).
- `docs/decisions/020-ebooks-comics-and-images.md:183-199` (notebook figure limit) is superseded by the amendment at 020:200-207. `PLAN.md:199` still lists it as open.
- The app-store research assumes IGES and STEP ship (`docs/market/2026-10-10-app-store-listing-research.md:233-234`, `:312`). Version 1 does not ship them (`docs/decisions/028-no-cad-in-version-1.md:7`).
- Breadth research says not to scan other apps' bundles (`docs/market/ux-research/2026-10-06-breadth-leaders.md:331`). Decision 023 implements a provider scan of `/Applications` and other roots (`docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md:99-112`). This is a deliberate later choice that the older research does not reflect.
- The "landscape correction" that Unfold lists STEP previews rests on Unfold's own changelog. It is an untested vendor claim (`docs/market/2026-10-06-competitor-ux-ui-analysis.md:26`).

---

## 4. Explicitly rejected, with the stated reason

| Item | Stated reason (quoted or closely paraphrased from source) | Source |
|---|---|---|
| Animated themes; patterned backgrounds | "animation conflicts with reduced-motion accessibility" | `docs/decisions/025-competitor-parity-program.md:42`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md:92` |
| Custom CSS themes; web-rendered content | "CSS needs a web renderer this product does not use"; "no web view for content, inert theme data" | `docs/decisions/025-competitor-parity-program.md:42`; ux-analysis:93 |
| Masking every value with identical pills | "findings are typed and selective" (decision 012) | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:94` |
| Status wording "ready", "Enabled", "Active", "Installed Correctly" | the companion reports where settings are saved, never routing | ux-analysis:95 |
| Reset Quick Look cache; Restart Finder | "prohibited by AGENTS"; "Not possible in the sandbox, no durable cache exists by policy" | ux-analysis:96; `docs/decisions/010-companion-sidebar-redesign.md:40` |
| Brand chips in content; watermarks | "content first" | ux-analysis:97 |
| Controlling the Quick Look window size | "macOS owns the host window" | ux-analysis:98 |
| Once-per-launch network heartbeat | "the app has no network entitlement" | ux-analysis:99 |
| Inline full previews or extraction of archive members | "no extraction; listings only" (decision 013) | ux-analysis:100; `docs/decisions/013-archive-listings.md:184` |
| Real cell values in thumbnails | "no sensitive content in thumbnails" (decision 022); withheld whole when anything is concealed | ux-analysis:101; `docs/decisions/022-content-thumbnails.md:43` |
| Head-only reads for thumbnails | "truncating breaks JSON, XML, property lists and databases and would need per-format handling" | `docs/decisions/022-content-thumbnails.md:50` |
| Separate viewer window; Finder action that bypasses provider choice | single window; "Try Preview stays behind Developer Mode" | ux-analysis:102; `docs/decisions/025-competitor-parity-program.md:45` |
| Polling; FSEvents; persisting zoom or filter; new window | kernel vnode events only; "wider access and heavier than a vnode watch for one file"; "temporary by definition"; "inline bars only" | `docs/decisions/021-preview-interaction-and-live-reload.md:90-93` |
| Saved scroll positions | "they would be durable per-file history, which the product does not keep" | `docs/decisions/025-competitor-parity-program.md:46` |
| Hex dumps of unknown binaries | "an ASCII column can expose secrets that text concealment cannot reliably find" | `docs/decisions/025-competitor-parity-program.md:49`; `docs/decisions/019-code-config-and-text-breadth.md:17` |
| PlantUML rendering | "needs Java or a remote server; the competitor uploads the file" | `docs/decisions/016-native-diagrams.md:14`; `docs/decisions/025-competitor-parity-program.md:43` |
| WebP, AVIF, fonts, PDF, Office, iWork, ordinary video and audio | "macOS previews these itself; registering them would compete with the system for no gain" | `docs/decisions/025-competitor-parity-program.md:41` |
| MKV, WebM, AVI codecs | "need a codec stack of FFmpeg's size and stay out of scope" | `docs/decisions/025-competitor-parity-program.md:41` |
| CBR, CB7 comics; RAR and 7z member contents | "RAR decompression is proprietary and 7z payload decoding is beyond listing scope; listings show names only" | `docs/decisions/025-competitor-parity-program.md:47`; `docs/decisions/013-archive-listings.md:187` |
| MOBI, AZW, DjVu, DICOM, FITS, PSB, EPS, CHM | "niche or heavy; each needs its own demand and dependency decision" | `docs/decisions/025-competitor-parity-program.md:48` |
| CAD (STEP, IGES) in version 1 | "CAD may return in a later version if the licence exception is bought or the licence question is otherwise cleared"; "this decision is a choice of scope, not a finding about the LGPL" | `docs/decisions/028-no-cad-in-version-1.md:7` |
| Content thumbnails for STL, OBJ, PLY | "Finder would show a content-free glyph where Apple's Hydra thumbnail extension shows a rendering" | `docs/decisions/024-mesh-formats.md:59-61` |
| Clickable links; local Markdown images; remote content | "links stay inert, and the extension has no access to sibling files" | `docs/decisions/025-competitor-parity-program.md:44` |
| Lock-file suffix claim | "it would route every lock file of any tool here" | `docs/decisions/019-code-config-and-text-breadth.md:107` |
| One imported type per source suffix | rejected to keep manifests small | `docs/decisions/019-code-config-and-text-breadth.md:108` |
| Partial-read registration flag | would edit registration lines owned by other families | `docs/decisions/019-code-config-and-text-breadth.md:105` |
| AsciiDoc claiming `.asc` | "it is armored PGP" | `docs/decisions/015-markup-documents.md:82` |
| Typeset math, LaTeX packages, macros, bibliography resolution | "Not promised" | `docs/decisions/015-markup-documents.md:112` |
| Notebook cell execution | "Cells are never executed" | `docs/decisions/009-first-expansion-formats.md:92` |

### 4b. Not promised (scope limits recorded in 013-024 and 025)

- Archive: member extraction, RAR and 7z member passwords, self-extracting archives, split archives (`docs/decisions/013-archive-listings.md:184-186`).
- Folders: recursive size, complete total, live reload at that time (`docs/decisions/014-folder-and-listing-views.md:159-165`).
- Ebooks: page-turning fidelity, reading themes, resume position, font controls, DRM removal, web-archive rendering (`docs/decisions/020-ebooks-comics-and-images.md:217-225`).
- Mesh: colours, materials, textures, animation, skeletons, cross-sections, wireframes, repair of non-manifold meshes, non-convex triangulation (`docs/decisions/024-mesh-formats.md:67-75`).
- Packages: contents of scripts, payloads and asset catalogues; `.p12`, `.pfx`, `.mpkg`; encrypted images (`docs/decisions/017-package-and-certificate-inspection.md:82-89`).
- Images in ebooks: WebP, HEIC and AVIF decoding on every supported macOS 15 system (020:221-222).
- Thumbnails for ebooks, notebooks, geometry: the thumbnails workstream owns drawing (020:219).
- Live reload: Finder may stop delivering events (`docs/decisions/021-preview-interaction-and-live-reload.md:37-41`).
- Diagram: visual parity with mermaid.js or diagrams.net (`docs/decisions/016-native-diagrams.md:197-203`).
- Hex: out of scope (019:17).
- Finder routing and provider priority: not promised for any new type (`docs/decisions/013-archive-listings.md:190`; `docs/decisions/019-code-config-and-text-breadth.md:95-96`; `docs/decisions/024-mesh-formats.md:67-69`).

---

## 5. Competitor weaknesses and user complaints recorded

These are openings. Each is a recorded observation, not a tested result.

### 5a. Limits, states and honesty

| Weakness | Competitor | Source |
|---|---|---|
| No screenshot in about 150 frames shows a truncated listing, a too-large state, an encrypted archive, an unsupported type or an error | Whole category | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:20`; `docs/market/ux-research/2026-10-06-breadth-leaders.md:302`; `docs/market/ux-research/2026-10-06-closest-rivals.md:232`; `docs/market/ux-research/2026-10-06-code-markdown.md:439`; `docs/market/ux-research/2026-10-06-data-db.md:247`; `docs/market/ux-research/2026-10-06-folders-archives-3d.md:423` |
| Limits appear only in support pages or FAQ, not in the product | QuickLook Pro; BetterZip; Unfold FAQ | `docs/market/ux-research/2026-10-06-closest-rivals.md:43`; `docs/market/ux-research/2026-10-06-folders-archives-3d.md:231`; `docs/market/ux-research/2026-10-06-breadth-leaders.md:68` |
| Empty archives shown as blank zebra rows with no summary or empty-state text | Folder Preview; Archive Quick Look | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:53`, `:176` |
| Dates and names silently truncated in tables | Super Quick Look | `docs/market/ux-research/2026-10-06-closest-rivals.md:171` |
| Free-tier quota falls back to a weaker preview without notice | GoodQuickLook | `docs/market/ux-research/2026-10-06-breadth-leaders.md:280` |
| Encryption support sold with no UI for it | FolderPlus | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:84`, `:424` |
| Store copy claims a format the support page disclaims | QuickLook Pro | `docs/market/ux-research/2026-10-06-closest-rivals.md:65` |
| Marketing counts disagree across App Store, site and extension list | Unfold | `docs/market/ux-research/2026-10-06-breadth-leaders.md:96` |
| Promotes STEP with an STL screenshot | Universal 3D Previewer | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:254` |
| Long Raw lines clipped with no wrap cue; mid-token wrapping | QLook JSON; JSON Loupe; PeekCode | `docs/market/ux-research/2026-10-06-data-db.md:51`, `:89`; `docs/market/ux-research/2026-10-06-code-markdown.md:353` |

### 5b. Privacy, secrets, network

| Weakness | Competitor | Source |
|---|---|---|
| Trust statements exist only as copy, never in the preview | Whole category | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:21`; `docs/market/ux-research/2026-10-06-breadth-leaders.md:301` |
| Private key printed under "Safe for secrets" | QLook JSON | `docs/market/ux-research/2026-10-06-data-db.md:87`, `:246` |
| `.env` secrets shown in clear in the headline screenshot | FinderPeek | `docs/market/ux-research/2026-10-06-data-db.md:188` |
| Masks every value, including plainly non-secret ones, with identical pills | QuickestLook | `docs/market/ux-research/2026-10-06-closest-rivals.md:118` |
| Once-per-launch status request to the vendor, despite "everything stays local" | QuickestLook | `docs/market/ux-research/2026-10-06-closest-rivals.md:107`, `:119` |
| CDN-linked scripts by default; web view architecture | QLMarkdown; Glance | `docs/market/ux-research/2026-10-06-code-markdown.md:126`, `:417` |
| Tracker script on the site of a privacy-sensitive utility | iPreview | `docs/market/ux-research/2026-10-06-breadth-leaders.md:224` |

### 5c. Provider conflicts and setup

| Weakness | Competitor | Source |
|---|---|---|
| No in-app provider-conflict diagnosis; guidance only on websites | Whole category | `docs/market/ux-research/2026-10-06-closest-rivals.md:233`; `docs/market/ux-research/2026-10-06-breadth-leaders.md:304`; `docs/market/ux-research/2026-10-06-folders-archives-3d.md:428` |
| Overclaimed status words: "Quick Look is ready", "Enabled", "Active", "Installed Correctly" | Super Quick Look; Loupe; FinderPeek | `docs/market/ux-research/2026-10-06-closest-rivals.md:169`; `docs/market/ux-research/2026-10-06-folders-archives-3d.md:143`; `docs/market/ux-research/2026-10-06-data-db.md:187` |
| Troubleshooting by logging out, or by "Reopen Finder" first | PreviewCode; Quick Preview | `docs/market/ux-research/2026-10-06-code-markdown.md:162`; `docs/market/ux-research/2026-10-06-folders-archives-3d.md:205` |
| Older Quick Look plug-ins stopped working after a macOS upgrade (reviewer report) | Category, reviewers of iPreview and Peek | `docs/market/2026-10-10-app-store-listing-research.md:140-141` |
| QLStephen broken since Catalina; `.qlgenerator` plug-ins do not load on macOS 15 | QLStephen | `docs/market/2026-10-05-competitor-landscape.md:176` |
| Settings do not teach: no first-run walkthrough with an annotated System Settings image | Whole category | `docs/market/ux-research/2026-10-06-code-markdown.md:440` |

### 5d. Accessibility, languages, listing

| Weakness | Competitor | Source |
|---|---|---|
| Accessibility not evidenced by any competitor | Whole category | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:70`; `docs/market/ux-research/2026-10-06-breadth-leaders.md:305`; `docs/market/ux-research/2026-10-06-code-markdown.md:441`; `docs/market/ux-research/2026-10-06-data-db.md:250` |
| Animated backgrounds behind text without a reduce-motion or contrast guard | LookQuick; GoodQuickLook (tinted blocks) | `docs/market/ux-research/2026-10-06-breadth-leaders.md:161`, `:281`; `docs/market/2026-10-05-competitor-landscape.md:102` |
| None of the 14 profiled apps declares Turkish, Indonesian, Bangla, Hausa or Kurmanji; translated store pages are rare | Whole category | `docs/market/2026-10-10-app-store-listing-research.md:106-111` |
| Accessibility labels declared only by iPreview and Unfold ("Dark Interface") | Peek, GoodQuickLook, Simple Quick Look, Source Code Preview declare nothing | `docs/market/2026-10-10-app-store-listing-research.md:113-114` |
| Reviewers ask for text selection in the preview and for plain-text treatment of unusual extensions | Category reviewers | `docs/market/2026-10-10-app-store-listing-research.md:142` |
| Blockquotes marked by colour only | PreviewMarkdown | `docs/market/ux-research/2026-10-06-code-markdown.md:196` |
| Shortcuts shown nowhere, except Peek's floating pills | Whole category | `docs/market/2026-10-06-competitor-ux-ui-analysis.md:22` |

### 5e. 3D and structured views

| Weakness | Competitor | Source |
|---|---|---|
| Dimensions shown without units | Eyemesh | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:343` |
| No Quick Look 3D preview shows units, part counts or how to orbit | Whole 3D cluster | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:425-426`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md:25` |
| Zero affordance for camera movement; no ground or axis reference | Universal 3D Previewer; Peek3D | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:255`, `:400` |
| Cropped first view; unlabelled icon toggles | StepPreview; MakersPreview | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:280-281`, `:310` |
| Floating overlays cover content; clipped breadcrumbs | SpacePeek | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:116-117` |
| System files listed with no hide control; "Kind" shown as "Document" for `.DS_Store` | FolderPlus; Archive Quick Look | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:85`, `:174` |
| Tree in Quick Look: no type glyphs, no counts, proportional font for values | FinderPeek; JSON Loupe (Tree is Pro-gated) | `docs/market/ux-research/2026-10-06-data-db.md:189`, `:249` |
| Different renderers disagree on basic Markdown syntax | Markdown Peek | `docs/market/ux-research/2026-10-06-code-markdown.md:384` |
| Marketing with garbled text | Code Peek+ | `docs/market/ux-research/2026-10-06-code-markdown.md:322` |

### 5f. Pricing and stale apps

| Weakness | Competitor | Source |
|---|---|---|
| Reviewer: $7.99 "a lot" for syntax highlighting when free tools exist | Peek | `docs/market/2026-10-10-app-store-listing-research.md:147-148` |
| Last updated 2022-04-02; HTTPS certificate expired on the research date | Peek | `docs/market/2026-10-05-competitor-landscape.md:137` |
| Archived since 2020-11-13 | Glance | `docs/market/2026-10-05-competitor-landscape.md:173` |
| Basic drill-down paywalled ("reads as a limit rather than a feature") | SpacePeek | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:118` |
| Conflicting price statements across store and site | Loupe | `docs/market/ux-research/2026-10-06-folders-archives-3d.md:145` |
| Locked modes shown in free control | JSON Loupe | `docs/market/ux-research/2026-10-06-data-db.md:50` |
| Stale screenshots (0.1.5 against 1.0.3) | Super Quick Look | `docs/market/ux-research/2026-10-06-closest-rivals.md:161` |

Performance: no performance complaint is recorded in these documents. Claims that exist: a "lazy text view for huge files" (landscape:183) and skipping large files (landscape:173). Neither is tested.

---

## 6. Listing and keyword notes (App Store research)

- **Head term.** "Quick Look" is "the head term, and it is winnable": 11 of the top 12 results carry it (`docs/market/2026-10-10-app-store-listing-research.md:29-31`). Subtitle placement is enough to rank (:32-33). "Quick Look" is not on Apple's trademark list; absence is not clearance (:34-37).
- **Format demand.** Autocomplete completes `json`, `csv`, `sqlite`, `yaml`, `stl` and `step` with "viewer". No Quick Look app is in the top 10 for those queries (:40-42). Of these, `step` is not in version 1.
- **Zero Quick Look apps in the top 10:** "json viewer, csv viewer, sqlite viewer, xml viewer, plist viewer" (:199); "step viewer, stl viewer, cad viewer, 3d viewer" (:201, with "stp" 18 results and "iges" 17); "zip viewer, rar, 7z" (:202); "epub reader, comic reader, midi player" (:203); "syntax highlight" (:200); "markdown, json, yaml, toml" (:198).
- **Thin long-tail terms.** IGES has no Quick Look app; STEP has two (:54-56, :179). "No specialist names CSV, notebooks, subtitles, draw.io or certificates in its name or the subtitles read" (:55-56, :180). These are SpacePane's own formats.
- **Keyword field, as recommended:** viewer, syntax, highlight, file, plugin, csv, sqlite, yaml, toml, plist, xml, jupyter, zip, rar, step, iges, stl, cad, epub, srt (:233-234). Caveat: `step`, `iges` and `cad` depend on CAD, which version 1 does not ship (028:7).
- **Must carry:** quick look, preview, json, markdown; code once source code opens in SpacePane (:231-232). **Skip:** previewer, finder, thumbnail, folder, source, log, diff, hex (:235). `log` and `diff` are SpacePane formats; the research says to skip them as keywords, not that they are missing.
- **Subtitle:** "Spend the subtitle on formats proven to open in SpacePane" (:310). The CAD long-tail advice is conditional: "if IGES and STEP ship" (:312).
- **Safety claim.** None of 151 descriptions searched mentions hidden-character detection, archive risk notes or notebook health (:51-53). "Local, no upload" appears in 9 of 19 (:98). Gander's "Press Space" and masked `.env` copy: SpacePane "should not lean on" those alone (:101-104).
- **Languages.** None of the 14 apps declares Turkish, Indonesian, Bangla, Hausa or Kurmanji (:106). Translated store pages are rare (:107-111). Recommendation: "Launch in English" (:315-316), consistent with `AGENTS.md` ("Version 1.0 ships English only").
- **Ratings.** No Mac app has a usable rating (:20, :47-48). "Treat a visible rating as a goal" (:317).
- **Categories and price points.** Every app launched since September chose Developer Tools (:92-93). Common paid points are $1.99, $2.99 and $4.99 (:176).
- **Phrasing.** Users say "Quick Look plug-in" for the old `.qlgenerator` and "Quick Look extension" for the new one (:223-224).
- **Keyword rules.** Plurals count as duplicates; keywords longer than two characters; 100-byte limit (:263-265).
- **Unverified on the research date:** whether any app was rejected for "Quick Look" in its name (:304-305).
