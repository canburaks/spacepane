# Competitor landscape: Quick Look apps for macOS

Researched 2026-10-05 (Europe/Istanbul). Sources are each developer's own App Store description (US storefront, retrieved through Apple's public iTunes Search/Lookup API), product websites and GitHub repositories, plus one community thread. **Every feature below is the vendor's own claim, not verified by testing.** Apple's API returns no ratings for Mac apps, so popularity is not compared. Prices are US list prices on the research date.

## Key findings

1. **The category is crowded and young.** Of roughly 70 Quick Look apps on the Mac App Store, most of the general-purpose ones launched in 2025–2026. macOS 15 dropped the old `.qlgenerator` plugins, and many classics stopped working ([TidBITS](https://talk.tidbits.com/t/what-are-your-favorite-quick-look-extensions/29323), [Michael Tsai](https://mjtsai.com/blog/2024/11/05/sequoia-no-longer-supports-quicklook-generator-plug-ins)).
2. **The closest match to SpacePane is QuickLook Pro.** It also targets macOS 15+ and offers JSON/JSONL trees, YAML/TOML, read-only SQLite, `.env` files with secrets hidden, package.json overviews, folder/ZIP/ZIP64/XIP/TAR/GZIP listings, MIDI playback and dotfile or extension-free text.
3. **Secret masking is not unique.** QuickLook Pro and QuickestLook both hide likely secrets by default. QuickestLook adds a reveal toggle.
4. **Per-type on/off switches are not unique either.** QuickestLook has per-renderer switches, Code Peek+ has file-type toggles, and Unfold exposes 13 separately switchable extensions.
5. **STEP/IGES 3D in a general-purpose app is SpacePane's clearest differentiator.** Only specialists preview STEP (StepPreview, Universal 3D Previewer). iPreview renders mesh formats (STL, OBJ, FBX and others) but not STEP or IGES. None of the general apps found offers IGES. *Amended 2026-10-06:* [Unfold's changelog](https://unfold.tools/changelog) lists 3.2.0 (2026-10-03) with interactive 3MF and STEP previews and Finder thumbnails, while the App Store API still returned 3.0.2 (vendor claim, not tested). STEP is therefore no longer a SpacePane-only feature among general-purpose apps; IGES still is, among the apps found. See [the UX/UI analysis](2026-10-06-competitor-ux-ui-analysis.md).
6. **SpacePane's biggest gaps against the leaders:**
   - Content thumbnails: SpacePane's are generic, while PreviewCode, Fast SQLite Viewer, mesh-peek and others draw real content.
   - RAR and 7z archives, which most folder/archive apps and Unfold, Super Quick Look and iPreview support.
   - Markdown extras: Mermaid, math, table of contents.
   - Breadth: Unfold lists 262 extensions, LookQuick claims 1000+ types, Super Quick Look adds Parquet, Avro, Arrow, LaTeX and draw.io.
   - Ebooks and comics, `.app` bundle inspection, WebP/AVIF images, live reload, and in-preview search or jump-to-line (Peek).
7. **Pricing is one-time or free; nobody uses subscriptions.** Paid all-in-ones cost $3.99–$9.99. Specialists cost $0.99–$4.99. Freemium is common (LookQuick, GoodQuickLook, SpacePeek, JSON Loupe, Fast SQLite Viewer). PSB Quick Look HD at $34.99 is the outlier.
8. **Provider conflicts are a known pain point, and some apps tackle them.** LookQuick shows a "made by" badge, scans for conflicting plugins, and adds an action extension and keyboard shortcut to force its own preview. QuickestLook documents the "Open with → Change All" workaround. macOS sends each type to a single provider, so a user with several of these apps sees unpredictable previews.

## Comparison with SpacePane

✓ = claimed · – = not offered or explicitly unsupported · ? = not stated in the vendor's material

| Capability | SpacePane | QuickLook Pro | Unfold | Super Quick Look | LookQuick | QuickestLook | iPreview | Peek |
|---|---|---|---|---|---|---|---|---|
| Price | not set | $3.99 | $9.99 (trial) | $3.99 | Free + IAP themes | Free (tips) | $6.99 | $7.99 |
| Minimum macOS | 15 | 15 | 15.6 | 12 | 14 | 26 | 12 | 10.15 |
| Last updated | in development | 2026-09-22 | 2026-09-12 | 2026-09-15 | 2026-09-15 | 2026-05-01 | 2026-10-03 | **2022-04-02** |
| Source code highlighting | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Rendered Markdown | ✓ | ? (source and highlighting stated) | ✓ TOC, Mermaid | ✓ | ✓ | ✓ | ✓ math | ✓ TOC, MathJax, Mermaid |
| JSON tree/outline | ✓ | ✓ | ✓ | ✓ summary | ? (plist tree) | ✓ | as code | as code |
| CSV/TSV table | ✓ | – (uses Apple's) | TSV/TAB only | ✓ | ? | ✓ | ? | – |
| Jupyter notebooks | ✓ | ? | ✓ | ✓ | ? | ✓ | ✓ | ? |
| SQLite | ✓ read-only | ✓ read-only | – | ✓ | ? | – | – | – |
| ZIP / TAR / GZIP | ✓ | ✓ (+ZIP64) | ✓ | ✓ | ✓ | ZIP only | ✓ | – |
| RAR / 7z | – | – | ✓ | ✓ | ? | – | ✓ | – |
| XIP | ✓ | ✓ | – | – | ? | – | – | – |
| Folder previews | ✓ (top level) | ✓ | ✓ 3 layouts, depth | ✓ expandable | ✓ split pane | – | ✓ tree | – |
| Subtitles | ✓ SRT, VTT | ? | ✓ 10 formats | – | ? | ✓ SRT, VTT, TTML | ✓ SRT, ASS | ? |
| MIDI playback | ✓ | ✓ | – | – | ? | – | – | – |
| STEP / IGES 3D | ✓ opt-in | – | – | – | ? | – | mesh formats only | – |
| Secret masking | ✓ | ✓ | – | – | – | ✓ (+ reveal toggle) | – | – |
| Per-type switches | ✓ 31 | ? | 13 extensions | ? | ? | ✓ per renderer | – | ? |
| Themes / typography | ✓ Light, Dark, High Contrast, System + typography, profiles | ? | ? | ? | ✓ 20 + 21 animated, fonts | ✓ 2 + custom CSS | ✓ code themes | ✓ 70+ + CSS |
| Content thumbnails | – generic only | thumbnail extension (content ?) | ? | ? | ? | ? | ? | ? |
| Extension-free text | ✓ | ✓ | ✓ | named files only | ✓ (+ hex fallback) | ? | Dockerfile etc. | dotfiles |
| Interface languages | 14 (drafts) | ? | ? | ? | ? | ? | ? | ? |

## General-purpose competitors

### QuickLook Pro — Mucahit Tutuncu
$3.99 · v1.1, 2026-09-22 · macOS 15+ · [App Store](https://apps.apple.com/us/app/quicklook-pro-file-preview/id6812534537) · [quicklookpro.com](https://quicklookpro.com/) · tagline "QuickLook, supercharged" · site claims 300+ file types
- JSON trees and JSONL records, with fast Tree/Raw switching.
- Common YAML and TOML configurations. Advanced syntax falls back to highlighted text.
- SQLite tables, schema and indexes without changing the database.
- Environment files with likely secrets hidden by default.
- Markdown and source code with selectable text, syntax highlighting and line numbers.
- Overview of package.json projects.
- Folders, ZIP, ZIP64 and XIP listings without extraction. Supported GZIP content and TAR listings.
- MIDI playback with play/pause and a scrubber: SMF formats 0 and 1 using the macOS sound bank.
- UTF-8 and UTF-16 text, including dotfiles and extension-free files when Finder routes them to it.
- Preview and thumbnail extensions. The setup app can quit while previews keep working.
- No account, subscription or uploads; processing is local.
- **Stated limits:** split ZIPs and sparse TAR files are unsupported. XIP signatures are not verified. Standard CSV uses Apple's preview.

### Unfold — flew llc
$9.99 on the App Store, or $10 direct with a free trial · v3.0.2, 2026-09-12 · macOS 15.6+ · [App Store](https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758) · [unfold.tools](https://unfold.tools)
- **Breadth:** 262 extensions across folders, apps, torrents, web archives, plain text (29), comics and ebooks (4), Markdown (19), LaTeX (4), source code and JSON (172), archives (17), tabular data (2) and subtitles (10).
- **Folders:** Native, List or Grid layouts. Image thumbnails, file details, expandable subfolders, adjustable scan depth, optional hidden items and folder-size totals.
- **Code and config:** syntax highlighting for 100+ languages, special filenames and dotfiles (Makefile, Dockerfile, CMakeLists.txt, .gitignore, .env).
- **JSON:** JSON, JSONC, JSON5, JSONL and Canvas files in a native, syntax-coloured viewer with line numbers and collapsible objects and arrays.
- **Tables:** .tab and .tsv files as tables.
- **Markdown:** rendered document with tables, code blocks, a navigable table of contents and a source view. Optional hot reload.
- **Mermaid and Jupyter:** Mermaid files render as zoomable diagrams. Jupyter notebooks show formatted Markdown, highlighted code, math, images and saved outputs.
- **Comics:** CBZ and CBR with a continuous reading view and thumbnail navigation.
- **Archives:** ZIP, RAR, 7Z, TAR, compressed TAR and package formats with nested folders, without extraction.
- **Web archives:** MHT and MHTML rendered locally, with remote loading, external navigation and page JavaScript disabled.
- **LaTeX and BibTeX:** TeX, LaTeX and LTX with formatted structure and math, plus a source view. BibTeX becomes a reference list in APA, MLA, Chicago or IEEE style.
- **Ebooks:** EPUB and FB2 with covers, contents navigation, adjustable reading size, automatic, black, light or sepia themes, and resume position.
- **Subtitles:** SRT with timing and style highlighting, plus VTT, ASS and other subtitle formats.
- **Other text:** logs, NFO, Fountain scripts, extension-free and unfamiliar text files.
- **App bundles:** a `.app` shows icon, name, version, bundle ID, architecture, minimum macOS, size, signing identity, App Sandbox and hardened runtime status. Torrent files can also be inspected.
- **Since v3.0:** live reload for code, JSON, text, LaTeX, Mermaid, notebooks, subtitles and tables. Progressive loading for comics and EPUB, and fallbacks when a document is too complex to render.
- 13 extensions that can each be switched on or off in System Settings. Processing is local.

### Super Quick Look — Lumik LLC
$3.99 · v1.0.3, 2026-09-15 · macOS 12+ · [App Store](https://apps.apple.com/us/app/super-quick-look/id6783296336)
- **Code:** about 40 languages, from Swift, C, Rust and Go to Solidity, Zig, Verilog, Nushell and batch files.
- **Markup and documents:** Markdown, MDX, reStructuredText, AsciiDoc, LaTeX, HTML, XML, XSD, XSL/XSLT, Mermaid, PlantUML, draw.io and Jupyter notebooks.
- **Config and developer files:** YAML, TOML, INI, SQL, GraphQL, Protocol Buffers, HCL/Terraform, CMake, Bazel, Dockerfile, Makefile, shell, PowerShell, .env, diffs, patches, logs, PEM/certificate/key files, README, LICENSE, Gemfile, authorized_keys, known_hosts and more.
- **Data:** JSON, JSON Lines, NDJSON, CSV, TSV, property lists, SQLite, Parquet, Avro and Apache Arrow/Feather, each with a structured summary.
- **Archives:** ZIP, ZIPX, TAR, GZIP, TAR.GZ, TAR.BZ2, TAR.XZ, TAR.ZST, 7z, RAR, JAR, WAR, EAR, IPA and variants.
- **Folders:** expandable hierarchy with item counts, depth, modified dates, kinds, sizes and native icons. Large folders load previews on demand.
- Local rendering; no account, subscription or upload.

### LookQuick — Inspirationull, LLC
Free, with a PRO in-app purchase for animated themes · v3.2, 2026-09-15 · macOS 14+ · 54 MB · [App Store](https://apps.apple.com/us/app/lookquick/id6759767692) · [inspirationull.com/LookQuick](https://inspirationull.com/LookQuick)
- Claims dedicated previews for 1000+ file types. Files without a dedicated preview get a hex analysis or strings dump.
- **Unusual types:** UTM and VMware VMs, pkg, apk, ipa, apps, fonts, BMW diagnostic files, torrents, HAR and animated JXL.
- **Media:** 50+ extra formats playable through QuickTime (WebM, AVI, WMV, RealMedia, MKV and others). SWF plays on Intel Macs.
- **Code:** line numbers, word wrap, custom fonts, 20 syntax themes and 21 animated PRO themes. Animation level can be Off, Low, Medium or High.
- Markdown with its own adjustable font, and collapsible plist trees.
- Browsable directory previews with split-pane file inspection. Archives are inspected without extraction.
- **App inspection:** sandbox, signing, App Store status, build number, bundle ID, privacy usage strings and entitlements. The same for iOS installers, xcarchives, Xcode projects and provisioning profiles.
- **Customization:** theme, font family and size, line numbers, word wrap and maximum file size. Themes can apply to every preview or only to text.
- **Provider conflicts:** a badge names the extension that made each preview. The app checks extension status and scans folders for conflicting plugins. An in-app preview, a Quick Action and a keyboard-shortcut service bypass whichever plugin macOS chose.

### QuickestLook — Oliver Herbelin (Helaia)
Free, with optional supporter purchases that unlock nothing · v1.0, 2026-05-01 · **macOS 26+** · [App Store](https://apps.apple.com/us/app/quickestlook/id6765485652) · [helaia.com/tools/quickestlook](https://helaia.com/tools/quickestlook/)
- **Code:** Swift, Python, Rust, Go, TypeScript, JavaScript, Ruby, Kotlin, Dart, GraphQL, Vue, Svelte, SCSS, Sass, Less and more.
- **Apple formats:** .plist, .entitlements, .xcconfig, .strings and .xcstrings as key-value trees.
- **Data and config:** JSON as a collapsible tree, plus JSONL, YAML, TOML, INI, .env, the .gitignore family and lock files for major package managers.
- **Notebooks:** .ipynb with Markdown cells, highlighted code and embedded image outputs.
- **Tables:** CSV and TSV with sticky headers and zebra striping.
- **Logs:** timestamps, coloured severity levels and stack-trace formatting.
- ZIP archives as a browsable tree, and .dmg metadata.
- **Web:** HTML, XML and SVG.
- **Subtitles:** SRT, VTT and TTML as timelines.
- **Secrets:** likely API keys, tokens and passwords in config files are masked automatically, with a reveal toggle. Detection runs locally.
- **Themes:** Calm and Vivid, or custom CSS.
- **Settings:** per-renderer switches, font size and family, file-size caps, theme choice and the reveal-secrets toggle.
- No analytics, telemetry or tracking. Documents the "Get Info → Open with → Change All" fix for provider conflicts.

### iPreview: Enhanced Quick Look — Appful (seller 晨姣 李)
$6.99 · v3.3.0, 2026-10-03 (first released 2020) · macOS 12+ · [App Store](https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509) · [appful.dev](https://www.appful.dev/)
- **Folders:** full directory tree, file counts and an overview.
- **Code:** 30+ types, including extension-free files such as Dockerfile and Podfile. Highlighting with several themes, adjustable tab width, line numbers and Dark Mode.
- **Documents:** Markdown, Jupyter and AsciiDoc, with math typesetting.
- **3D models:** .3ds, .3mf, .ac, .ase, .b3d, .blend, .cob, .dae, .csm, .dxf, .fbx, .lwo, .md2, .md5mesh, .mdl, .ms3d, .nff, .obj, .off, .ply, .q3o, .smd, .stl and more. Physics-effect, bounding-box, wireframe and skeleton render modes, with animation playback.
- **Images:** WebP and AVIF, with resolution and size information.
- **Archives:** ZIP, RAR, 7Z, GZ and TAR with name, size and date, without extraction.
- **Subtitles:** SRT and ASS.
- README, LICENSE and other developer configuration files.

### Peek — A Quick Look Extension — Big Z Labs
$7.99 · v2.6.4, **last updated 2022-04-02** · macOS 10.15+ · [App Store](https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898) · bigzlabs.com/peek (its HTTPS certificate had expired on the research date) · a TidBITS user cites 530+ file types
- Rich previews of Markdown, TextBundle, PostScript and .ePDF.
- In-preview search and jump to line or page, with system shortcuts (find, jump, scroll to start or end).
- **Markdown:** GitHub-flavoured, with an optional table of contents. Code blocks load any of 191 HighlightJS or 273 PrismJS languages. Lazy highlighting, MathJax (TeX, inline), Mermaid, and local absolute and relative links.
- Force click for Look Up. Scroll position is saved and restored.
- A Quick Action renames a PDF to .ePDF, for searchable dark-mode PDF previews.
- Preview sizes from 5 KB to 1 MB.
- Automatic language detection, 70+ light and dark themes or a custom CSS stylesheet, and optional line numbers.
- Developer files such as Cartfile, Podfile, .gitignore, .swiftlint.yml, .xcconfig, .swift, .c and .py.
- **Stated limits:** cannot handle .txt, .rtf, HTML/XML/web archives, .ts, PDF, Office files including CSV, OpenDocument or iWork.

### GoodQuickLook — KwiKwi, LLC
Free, with a Pro Lifetime in-app purchase that removes plugin limits · v1.0.4, 2026-06-13 · macOS 13+ · [App Store](https://apps.apple.com/us/app/goodquicklook/id6770471994) · [funnytoys.app/goodquicklook](https://funnytoys.app/goodquicklook)
- 30+ formats: code, Markdown (headings, code blocks, table of contents), JSON, YAML, plist, ZIP, RAR, 7z, app packages and binaries.
- **Images:** HEIC, SVG and PSD with dimensions, pixel count, format and location.
- MP4 and MP3, ebooks and PDFs, and OTF and TTF fonts.
- Folder structure and size.
- Custom thumbnails for supported files.
- Finder toolbar integration.
- Themes (GitHub, Dracula, GitHub Modern), dark mode, font settings and a limit on simultaneous plugins.
- Files never leave the Mac.

### Simple Quick Look — 俊全 颜
Free · v1.0, 2026-04-26 · macOS 11+ · [App Store](https://apps.apple.com/us/app/simple-quick-look/id6762875743)
- **Code:** Swift, Kotlin, JSX/TSX, Gradle, ProGuard, GraphQL, Prisma, Protocol Buffers and Svelte.
- **Config:** TOML, YAML, INI, Properties, Conf, Cfg, .env, lock files and diffs.
- **Subtitles:** SRT, VTT, ASS, SSA, SUB and TTML.
- Chinese mini-program files (WeChat, Alipay, Douyin, Baidu, QQ and Kuaishou), SCSS, Sass, Markdown, JSON, XML and plist.
- Plain-text rendering only, plus a built-in list of supported extensions.

## Free and open-source

| Project | Status | Features |
|---|---|---|
| [Syntax Highlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) (sbarex) | Active; GPL-3.0; macOS 12+ | 200+ languages; built-in light/dark schemes with a GUI editor and custom CSS; HTML or RTF engines; line numbers, word wrap, fonts, tab expansion; per-format syntax overrides, preprocessors and Language Server Protocol support; Git/Mercurial change marks; data limits; window sizing; CLI tool; extension-free files. **No thumbnails.** Reserved system types such as .ts and .html can't be handled. |
| [QLMarkdown](https://github.com/sbarex/QLMarkdown) (sbarex) | Active; GPL-3.0 | cmark-gfm Markdown, plus .rmd, .mdx, .mdc, .qmd, .apib, .mermaid and textbundle; tables, task lists, definition lists, GitHub alerts, mentions, hashtags, wikilinks, emoji, sub/superscript, highlights, smart quotes; code highlighting; MathJax; Mermaid; inline local images; YAML header; heading anchors; GitHub light/dark or custom CSS; table-of-contents sidebar; font size; render-as-source; CLI and Shortcuts actions. |
| [Glance](https://github.com/samuelmeuli/glance) | **Archived since 2020-11-13**; MIT | Code (Chroma), Markdown (goldmark), TAR/ZIP, Jupyter, TSV; skips large files; network disabled in its web view. A free App Store build still exists (last updated 2024-07). |
| [QLVideo / QuickLook Video](https://github.com/Marginal/QLVideo) (Jonathan Harris) | Active; GPL-2; $3.99 on the App Store, free on GitHub | Finder thumbnails, Quick Look previews and Get Info metadata for MKV, WebM, WMV, OGV, AVI, MOV, FLV, Real Media and MXF; codecs from VP6–VP9, AV1, HEVC and VVC to Dolby Vision, Theora, DXV, HAP and DivX. Works through a Spotlight extension plus two AVFoundation media extensions. |
| [smittytone Preview apps](https://smittytone.net/previewmarkdown/) (Tony Smith) | Active; [PreviewBundle 2](https://apps.apple.com/bb/app-bundle/previewbundle-2/id1709782189) $5.99 | PreviewMarkdown ($2.99; YAML front matter), PreviewCode ($2.99; 50+ languages, ~100 themes), PreviewYaml ($1.99), PreviewJson and PreviewText (free; extension-free text, .toml, .nfo, .srt, .sub). **Every app ships a thumbnail extension.** |
| QLStephen | Legacy | Extension-free text. Users report it has been broken since Catalina, and `.qlgenerator` plugins no longer load on macOS 15. |

## Specialists by category

### Code
| App | Price | Features |
|---|---|---|
| [Source Code Preview](https://apps.apple.com/us/app/source-code-preview/id6759270528) (Anybox) | $4.99 | 50+ languages; font, size and colour themes; lazy text view for huge files and large JSON. No .ts or .html. |
| Code Peek+ (Onder Kadagan) | Free | Code, Markdown, Jupyter text and TSV tables; VS Code Dark+, Dracula, Nord, Solarized and GitHub themes, or a fully custom palette; line numbers, word wrap and a minimap; setup app with typography controls and **file-type toggles**; Lottie JSON previews. |
| PeekCode | Free | 500+ extensions; JSON formatting; Markdown with a table of contents; 80+ themes with separate light/dark choices; line numbers; one-click copy of the whole file; truncation for large files. |
| FinderPeek (Moustafa Elsayed) | $4.99 | Interactive JSON tree (expand/collapse); select and copy in all views; broad developer formats. |
| PreviewCode (smittytone) | $2.99 | 50+ languages including assembly dialects; **thumbnails**. |

### Markdown
| App | Price | Features |
|---|---|---|
| Markdown Preview (Anybox) | $1.99 | Preview/source toggle; right-to-left languages; KaTeX; Mermaid; code highlighting; TextBundle; MDX. |
| Marked QL (Brett Terpstra) | $9.99 | Companion to Marked; Apex processor that merges Markdown flavours. |
| Peekdown | $4.99 | GitHub-style tables, footnotes, LaTeX and Mermaid; copy code blocks; full viewer and editor with Spaces, annotations exported as AI prompts, auto-reload and a +/- diff view. |
| Markdown Quick Look (Bitfield) | $4.99 | Simple rendered preview for .md, .mdown, .markdown, .mdwn, .mdml, .multimarkdown, .mkd, .mmd and .ft. |
| Markdown Peek | Free | GitHub-style rendering; Space toggles rendered and source views; print/PDF; auto-reload; copy in both views. |
| MD QuickView / MarkLook / quicklook.md | Free / Free / $14.99 | Basic readers. quicklook.md shows monospaced source only. |

### JSON, YAML and data
| App | Price | Features |
|---|---|---|
| [JSON Loupe](https://jsonloupe.weinmayr.co/) | Free; Pro $4.99 | JSON, JSONL, NDJSON, YAML, TOML, GeoJSON, JSONC, JSON5, HAR, webmanifest, .ipynb and .map; Pretty and Raw views with exact line numbers; broken records flagged inline; head-only reads for huge files with a notice; base64 images inline; clickable URLs; no network. **Pro:** tree with copy key/value/path, compact log view and a standalone window. |
| QLook JSON | $2.99 | Pretty view (keeps key order and JSONC comments, folding), Raw and YAML views; "Pretty Text" expands escaped `\n`; JSONL for AI-agent logs; dual line numbers. |
| [Fast SQLite Viewer](https://makeshif.tma.tt/projects/sqlite-viewer-for-macos) | Free; Pro IAP | **Data-grid thumbnails**; interactive table picker; lazy paging over millions of rows; sort and filter; schema inspector (types, keys, defaults, indexes, foreign keys, CREATE SQL); strictly read-only and opened immutable; system SQLite. **Pro:** ER diagram, schema and CSV export. |
| Quick Data Insights | $4.99 | Parquet, SQLite and Jupyter; first 100 rows; schema view; copy CREATE TABLE; extract notebook code to Python. |
| Python Data Viewer | $1.99 | Notebooks rendered with cached outputs and plots; .npy/.npz as a grid, heatmap or chart; **thumbnails that show notebook figures**; export to .py or Markdown. |

### Folders and archives
| App | Price | Features |
|---|---|---|
| Folder Preview (Anybox) | $1.99 | Folders plus zip, tar, gz, 7z and rar; columns can be hidden; copy file or path; thumbnails for images, SVG and PDF. |
| FolderPlus | $1.99 | Tree, gallery and dashboard (stats, largest files) views; sorting; ZIP, TAR, 7Z, RAR and GZ including **password-protected** archives; keyboard navigation; offline. |
| SpacePeek | Free; Pro IAP | Size and storage breakdown, largest items; list or grid with breadcrumbs and search; Markdown, code and passive HTML previews; ZIP, TAR, gzip and bzip2 with search inside. **Pro:** deeper navigation. |
| Quick Preview: Folder Preview | $2.99 | Folders, archives, Markdown and ebooks (EPUB, MOBI, AZW, AZW3); settings for scan depth, hidden files and archive size limit; multilingual interface. |
| Loupe (Eduard Bruch) | $3.99 | Folders, ZIP, RAR, 7z, TAR, TAR.GZ and TAR.BZ2. **No network entitlement**, so privacy is enforced by the system; interface in 40+ languages. |
| Archive Quick Look | $2.99 | ZIP, TAR, GZIP, BZIP2, XZ, RAR and 7-Zip in Quick Look and Finder column view; list and grid; extracts small previewable files on demand. |
| Folder Quick Look, Preview Folders, FolderPreview, Folder QuickLook, FolderVitrine | $0.99–$3.99 | Variations on folder lists and archive browsing (Folder QuickLook also lists LZMA, LZ4 and XZ). |
| Scope | Free trial | Folder and ZIP browsing, plus bookmarking files from Quick Look into an organiser app. |

### 3D and CAD
| App | Price | Features |
|---|---|---|
| [Universal 3D Previewer](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617) | Free | **STEP/STP**, STL, OBJ, PLY, Alembic, 3MF, G-code and **SOLIDWORKS** (.sldprt, .sldasm, .slddrw, .sldlfp); previews, thumbnails and a standalone viewer. |
| StepPreview (Shanghai Adaila) | $4.99 | **STEP** preview and thumbnails, plus a lightweight viewer. |
| MakersPreview (Shanghai Adaila) | $4.99 | 3MF from Bambu Studio, PrusaSlicer, OrcaSlicer and Cura (with plate previews), GLB including AI-generated models, and XCS/LAC laser files; thumbnails; rotate, zoom and pan viewer. |
| Eyemesh | Free | 16 formats (FBX, glTF/GLB with Draco, USDZ, OBJ, PLY, STL, DAE, 3DS, 3MF, ABC, WRL, DXF and others); 3D thumbnails; wireframe, cross-section and skeleton views; animation; side-by-side comparison; tagging and library management. |
| mesh-peek / Peek3D / 3MF Viewer | $2.99 / Free / $1.99 | STL, 3MF, OBJ and SCAD (mesh-peek, with colour and thumbnails) · interactive STL, OBJ and 3MF · 3MF with colour and thumbnails. |

No app found previews **IGES**.

### Media and other
| App | Price | Features |
|---|---|---|
| QLPlay / QLMedia / Ogg Quicklook | Free / Free / $0.99 | Extra video formats (MKV, WebM, FLV, WMV) · WebM, MKV, ASF and FLV · Ogg audio with autoplay. |
| Sequences | $4.99 | MIDI player with a Quick Look plug-in, scrubbing, looping and shortcuts. |
| Book Preview | $7.99 | EPUB/KEPUB, MOBI, DJVU, FB2 and CBZ/CBR/CB7 with metadata and thumbnails. |
| QuickLook for IPA & APK | $1.99 | IPA, APK and AAB: names, versions, icons, permissions, entitlements, provisioning profiles; icon thumbnails. |
| PlantUML QuickLook | $0.99 | Rendered diagrams, but rendering **sends the file to a PlantUML server** (public or self-hosted). |
| GPX Preview | $1.99 | GPX, KML, KMZ and TCX on a map. |
| Niche formats | $2–$34.99 | DICOM (two apps), FITS, PSB, WebP, EPS, inddPreview, ChmPages. |

### Adjacent tools mentioned by users ([TidBITS thread](https://talk.tidbits.com/t/what-are-your-favorite-quick-look-extensions/29323))
- **Apparency:** app bundle details.
- **Suspicious Package:** installer package contents.
- **Pacifist** ($20): archives and packages.
- **BetterZip:** free Quick Look extension for ZIP, RAR, 7-zip, tar, xz and winmail.dat.
- **ProvisionQL:** provisioning profiles.

## What this means for SpacePane

- **Differentiators to lead with:**
  - STEP/IGES 3D inside a general-purpose app; IGES is offered by no one else found.
  - Read-only SQLite combined with MIDI, XIP, subtitles, notebooks and CSV tables in one app.
  - Per-type switches for every format.
  - Accessible themes plus typography profiles that can be shared as files.
  - A 14-language interface, once the translations are reviewed.
- **Claims to make carefully:** "local", "secrets hidden" and "no account" are now standard. Lead with them as table stakes, not as unique selling points.
- **Gaps worth evaluating** (decisions, not commitments):
  - Content thumbnails for data, code and 3D.
  - RAR and 7z listing (licence audit needed).
  - Markdown table of contents, math and Mermaid (would need the web-renderer review in AGENTS).
  - In-preview search and copy affordances.
  - A way to explain or work around provider conflicts, as LookQuick and QuickestLook do.
- **Pricing context:** paid all-in-ones cost $3.99–$9.99 one-time, and free tiers are common. The market has no subscriptions, which matches the existing country-pricing policy (no subscription implied).
