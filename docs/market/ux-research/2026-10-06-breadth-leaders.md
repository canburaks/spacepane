# Breadth leaders and theme-heavy apps — UX/UI observations
Researched 2026-10-06. Sources are vendor marketing (App Store, websites, repositories); nothing was installed or tested.

Everything below is **observed in marketing material**. "Not shown" means no screenshot or page showed it. Screenshot URLs are the App Store 1600x1000 variants (replace `1600x1000bb.jpg` with `800x500bb.jpg` for the original size). Feature inventory is in `docs/market/2026-10-05-competitor-landscape.md` and is not repeated.

## Apps covered
| App | App Store ID / repo | Version seen | Screenshots inspected | Sources |
|---|---|---|---|---|
| Unfold (flew) | 6760872758 | App Store API 3.0.2; changelog on site lists 3.2.0 (2026-10-03) | 10 App Store + 12 website tiles/images | https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758, https://unfold.tools, https://unfold.tools/changelog, https://unfold.tools/FAQ |
| LookQuick (inspiratioNULL) | 6759767692 | App Store 3.2 (2026-09-15); site page says 3.0 | 6 App Store + 7 additional site images (3 repeat) | https://apps.apple.com/us/app/lookquick/id6759767692, https://inspirationull.com/lookquick.html |
| iPreview (appful) | 1519213509 | 3.3.0 (2026-10-03) | 8 App Store + 6 site images | https://apps.apple.com/us/app/id1519213509, https://www.appful.dev/ |
| GoodQuickLook (funnytoys) | 6770471994 | 1.0.4 (2026-06-13), macOS 13+ | 5 App Store; site has no image files (HTML mock-ups read as text) | https://apps.apple.com/app/goodquicklook, https://funnytoys.app/goodquicklook, https://funnytoys.app/goodquicklook/support |

Metadata came from `https://itunes.apple.com/lookup?id=<ID>&entity=macSoftware&country=us`. No demo video was inspected (none was linked on the four sites). The App Store API still returned Unfold 3.0.2 while its own changelog lists 3.2.0 with interactive 3MF and STEP previews and Finder thumbnails; treat the competitor-landscape claim that STEP is a SpacePane-only differentiator as no longer safe for "general apps" (observed in marketing material, not tested).

A note common to all four: the title bar of every preview (close, the "no entry" sandbox icon, a share glyph, an "Open with <app>" pill) is drawn by Quick Look itself, so it is not a design choice of these apps. Only what sits below it is theirs.

---

## Unfold
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Hero collage: dark Markdown window with heading-outline sidebar, tilted code and EPUB windows behind | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/6a/9e/3e/6a9e3e23-df07-b288-dfb0-1a773df1f67b/Main@2x.png/1600x1000bb.jpg |
| 2 | Markdown preview: left outline tree (nested disclosure rows, current heading highlighted) + rendered Mermaid flowchart | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/97/e7/67/97e7677e-b1f6-2eff-c92e-ba13eda1863b/Markdown_Preview@2x.png/1600x1000bb.jpg |
| 3 | Folder preview: back/forward, "Scanned size: 55 MB / 2 folders, 18 files", list/grid segmented control, sort and "..." menus, Name/Date/Size/Kind columns | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/40/a4/33/40a433c3-30f6-d622-a8cc-9bb08eb8584a/Folder_Preview.png/1600x1000bb.jpg |
| 4 | Archive preview (ZIP): same column table, nested disclosure folders, "Uncompress" button in title bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/62/fe/0e/62fe0e98-6fde-d186-80de-fe3964760d3c/Archive_Preview@2x.png/1600x1000bb.jpg |
| 5 | EPUB preview: left chapter list, right reading column with illustration, "Open with Books" button | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/40/c5/74/40c57443-7225-3cde-75d0-b80831392da2/EBook_Preview@2x.png/1600x1000bb.jpg |
| 6 | Source code (Swift): 13-line gutter in dimmed grey, large mono, light syntax colors on near-black | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/3b/ea/2d/3bea2daf-86e2-62ae-ac2a-a70a08a6729f/Source_Code_Preview@2x.png/1600x1000bb.jpg |
| 7 | LaTeX preview: rendered heading, inline and display math | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/1a/55/3f/1a553f23-d77c-4366-e3ca-e296f5d7af09/LaTeX_Preview@2x.png/1600x1000bb.jpg |
| 8 | Companion app, General page: sidebar with Search Settings + per-format pages, toggles, "transparent background for" checkboxes, live code sample, font/size/line numbers/wrap | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/46/ce/92/46ce9294-5f7f-98ca-ac2d-174f0392f8fe/Settings_Page_1@2x.png/1600x1000bb.jpg |
| 9 | Companion app, Ebooks page: live EPUB sample with outline, Aa theme chips (Auto/Black/Light/Sepia/Glass), zoom slider, TOC toggle and auto-expand level picker | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e0/7b/f0/e07bf059-1fae-c29e-a0b4-359f95f992cf/Settings_Page_2@2x.png/1600x1000bb.jpg |
| 10 | Companion app, Source Code page: live code sample, font, size slider, line numbers, wrap, JSON folding toggle with explanatory caption | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/2f/55/32/2f553218-92c3-6f0b-b01f-782e97213fa8/Settings_Page_3@2x.png/1600x1000bb.jpg |
| W1 | Website tile: folder preview with full path breadcrumb bar at the bottom ("Macintosh HD > Users > ...") | https://unfold.tools/assets/folder-quick-look-tile.png |
| W2 | Website tile: application bundle card (icon, name, version, green-check rows for App Sandbox / Hardening / Signed By, then Bundle ID, Architecture, Requires, Copyright, footer "31.4 MB - Modified ...") | https://unfold.tools/assets/application-quick-look-tile.png |
| W3 | Website tile: TSV table with a header row, zebra rows, large mono cells | https://unfold.tools/assets/tabular-quick-look-tile.png |
| W4 | Website tile: plain Makefile with hard-wrapped long lines, line number aligned to the first wrapped row | https://unfold.tools/assets/plain-text-quick-look-tile.png |
| W5 | Website tile: SRT subtitle with colored index, timestamps and inline-tag highlighting | https://unfold.tools/assets/subtitle-quick-look-tile.png |
| W6 | Website tile: .torrent with Trackers / Web Seeds panes above a size-sorted file tree, footer "Created ... 52.61 GB" | https://unfold.tools/assets/torrent-quick-look-tile.png |
| W7 | Website tile: MHTML web archive rendered as an article | https://unfold.tools/assets/web-archive-quick-look-tile.png |
| W8 | Website tile: EPUB with chapter sidebar (wider variant of #5) | https://unfold.tools/assets/ebook-quick-look-tile.png |
| W9 | Website tile: ZIP archive with footer "ZIP archive - 6 folders, 7 files" and empty striped rows below the list | https://unfold.tools/assets/archive-quick-look-tile.png |
| W10 | Website: macOS System Settings > Login Items sheet, "Unfold Extensions - 13 extensions installed", one toggle per format ("Folder QuickLook Preview" etc.) | https://unfold.tools/assets/unfold-settings-extensions.png |
| W11 | Website hero poster: Finder icon view with real content thumbnails for .swift and .md files | https://unfold.tools/assets/unfold-hero-poster.jpg |
| W12 | Website tiles for Markdown, LaTeX and source code exist at the same path pattern; not inspected separately (the App Store shots 2, 7, 6 cover those formats) | https://unfold.tools/assets/markdown-quick-look-tile.png |

### Observations by rubric dimension
**1. Preview anatomy — 4/5**
- No custom header on text formats: the host title bar, then content edge to edge. Structure is added per format: a left outline sidebar for Markdown (#2), a left chapter list for EPUB (#5, W8), a toolbar row for folders (#3).
- Folder anatomy is the richest seen in this cluster: a summary line ("Scanned size: 55 MB", "2 folders, 18 files"), back/forward chevrons in one capsule, list/grid segmented control, sort and "..." menu capsules, column headers with a sort caret, and a breadcrumb path bar docked at the bottom (W1).
- Footers differ by type: ZIP gets a centered "ZIP archive - 6 folders, 7 files" caption (W9); an app gets "31.4 MB - Modified ..." (W2); a torrent gets "Created ... / 52.61 GB" (W6). The 2.8.2 changelog says a "metadata-strip" was added to plain-text, tabular and subtitle previews, so a shared strip exists but is not visible in the marketing tiles.
- Content-first: chrome is one capsule row at most; no persistent toolbar on code (#6).

**2. Content presentation — 4/5**
- Code (#6): large mono (point size not stated; the shot is scaled), generous roughly double line height, line numbers right-aligned in a dimmed grey gutter with no divider, warm coral keywords and lavender types on #1e1e1e. Very legible at small window size, but sparse (about 14 lines visible).
- Long plain-text lines wrap with the number aligned to the first wrapped row (W4); tables use zebra rows and a small header row over large mono cells (W3).
- Rendered documents (LaTeX #7, MHTML W7) use a proportional reading column with a small-caps category line, byline and "9 min read" meta; Markdown (#2) uses large system sans with inline code chips.
- All marketing shots are dark appearance only. Light mode is not shown anywhere.

**3. Interaction & discoverability — 4/5**
- Markdown outline: nested disclosure rows, current heading in a blue selection pill, "Animate scrolling to a section" setting (#8). Mermaid diagrams have zoom controls (feature copy, not shown).
- Folder: switchable layout, sortable columns, adjustable scan depth and hidden-item toggle (copy), disclosure triangles; the "..." menu holds the options (contents not shown).
- Live reload (3.0) and "remember scroll position" with a configurable duration are settings-level behaviors, not visible affordances.
- Shortcuts are not shown. Selection and copying from preview is praised by a reddit quote on the site, which is the only evidence.

**4. States & honesty — 3/5**
- Changelog describes source or plain-text fallbacks "when too complex to render", progressive loading for comics/EPUB, and an "Open Unfold" button that appears in previews needing license activation. No screenshot of any such state exists.
- FAQ admits that macOS-owned types (txt, rtf, html, csv, Office, iWork, TypeScript, PDF) are not handled and why. Honest, but it is in a FAQ, not in the product.
- Hidden files (.DS_Store) are dimmed rather than removed (#3, W1): a good, quiet honesty cue.
- Empty state, error state and truncation notices: not shown.

**5. Companion / settings app — 4/5**
- One window, a macOS System Settings clone: sidebar with colored rounded-square icons (General, Markdown, LaTeX, Ebooks, Source Code, Plain Text, Folders & Archive, About), a "Search Settings" field at the top, and back/forward chevrons next to the page title (#8-#10).
- Every format page starts with a **live sample** pinned above the controls (code sample #10, EPUB with outline #9) and the controls change it in place. Controls use inset-grouped rows with one-line grey captions explaining consequences ("Turn off to open large JSON files faster and use less memory").
- Theme choice for books is a row of five "Aa" chips (Auto, Black, Light, Sepia, Glass) with a selected ring (#9); code has font/size slider (A...A, "13pt") but no color theme gallery.
- Per-type enablement lives in System Settings, not the companion: 13 extension toggles, not 262 (W10). The companion shows no extension status, no first-run flow, no diagnostics.

**6. Visual identity & native feel — 4/5**
- Convincing macOS 26-style settings window; capsule toolbars, SF-like type, system blue accents. Icon is a minimal glyph on black. The "Aa" chips and colored sidebar tiles are the only decorative color.
- Marketing uses large dark-blue gradients; real UI stays neutral.

**7. Trust & privacy communication — 2/5**
- "Processing is local" is store/site copy. No in-UI badge, no "read-only" statement, no secret handling (landscape file already notes none). FAQ says no preview history or contents are collected.

**8. Delight and friction — 4/5**
- Delight: continuous reading view for comics, progressive loading, scroll-to-section animation, "Glass" book theme.
- Friction: FAQ says macOS prompts for permission in Downloads, Pictures and external drives and recommends Full Disk Access, a heavy ask for a previewer. 3.2.0 fixes "previews opening at the wrong size or resizing unexpectedly", showing that trying to control Quick Look window sizing is fragile. A Reddit quote on the site reports `.md` not working because several Quick Look extensions were enabled, with no in-app help.

### Worth matching or beating
1. **Live sample on every settings page** with captions that state the trade-off in one line.
2. **Folder/archive anatomy**: summary line + view/sort capsules + disclosure table + dimmed hidden files + bottom path bar.
3. **Per-type chrome without a global frame**: the Markdown outline sidebar and the app-bundle card (green-check rows) are examples of structure that fits the format.

### Mistakes to avoid
1. Dark-only marketing and an unseen light appearance.
2. Marketing counts that disagree: the App Store text says "more than 140", the site says "250+" and the extension list says 262.
3. Handing per-type control to System Settings only; the companion cannot show what is on or off.

---

## LookQuick
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Media marketing slide: MKV playing in a QuickTime-style window with custom control bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/11/15/1b/11151b54-bf98-3839-2e41-c1b43886fe1a/01-system-media_2880x1800.png/1600x1000bb.jpg |
| 2 | Marketing: grid of file-type cards (DOCX, SWIFT, MD, JSON, ZIP, SQLITE, STEP, TORRENT, PEM...) - each card colored per category, label + kind + size | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e2/19/cf/e219cf1d-e239-4935-34b1-050f96686920/gdownload_2880x1800.png/1600x1000bb.jpg |
| 3 | Marketing collage "No more icon-only dead ends": app inspector (badge pills Development/Sandboxed/Hardened Runtime/Valid + key/value table), code, folder summary, font specimen, Windows executable detector (magic-byte, SHA-256), HAR table, DMG partitions | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/26/6c/7b/266c7bab-07ed-7fbc-d9a0-74618b7ec087/02-system-media_2880x1800.png/1600x1000bb.jpg |
| 4 | Marketing: Matrix-green animated theme on Makefile, plus two folder list/tree screenshots; feature call-outs "Browse Nested Directories / Smart Information Layout / Premium Matrix Theme" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/75/7f/82/757f8248-4b84-1053-6586-6452efacd96a/App_Store_Assets-2560x1600.png/1600x1000bb.jpg |
| 5 | Marketing mock-up: INI file with gradient animated theme and PE executable detail card | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d4/88/ee/d488eebc-12f2-fba5-112e-439e6a928c17/Screenshot_02_1280x800.png/1600x1000bb.jpg |
| 6 | Marketing mock-up: .reg with animated blue theme and a JAR tree with an odd right-hand time column | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fe/b7/bc/feb7bcb2-4b88-6f64-81e1-ad13ffdea7b8/Screenshot_01_1280x800.png/1600x1000bb.jpg |
| W1 | Vendor site: xcodeproj summary card (36 source files / 6 resources / 0 frameworks, target and configuration chips, raw pbxproj below) shown at spacebar size next to the Finder sidebar-pane size | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/06/d2/75/06d275be-fe2e-d7ea-c931-d6b261031912/Screenshot_2026-03-01_at_1.30.41_U202fAM.jpg/1600x1000bb.jpg |
| W2 | Vendor site: folder+archive preview with Compressed / Uncompressed / Compression ratio footer, Finder sidebar pane variant at right | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ca/10/a7/ca10a781-47fc-c9c5-09f3-6bfbdfdf5ccc/AppStoreImage-1280x800.png/1600x1000bb.jpg |
| W3 | Vendor site, companion app: sidebar (Appearance, Code, Markdown, Formats, Directories, General); "Syntax Theme" grid of 4x5 theme cards, each a live mini code sample, selected card has orange ring and check | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/2b/30/61/2b30613d-3c6f-8089-bdeb-7fd4dc1e9b95/Screenshot_2026-03-01_at_1.46.49_U202fAM.jpg/1600x1000bb.jpg |
| W4 | Vendor site: directory preview at two sizes (spacebar window and Finder pane) with Name/Size/Kind/Date and disclosure arrows | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/3b/b0/22/3bb02221-be6b-dac1-abd6-078184064b68/AppStoreImage-1280x800.png/1600x1000bb.jpg |
| W5 | Vendor site: xcodeproj preview in a dark red theme, hard to read at thumbnail size | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/64/c3/38/64c33880-4df3-afa7-4137-e5880b78873a/AppStoreImage-1440x900.png/1600x1000bb.jpg |
| W6 | Vendor site: xcodeproj summary in Finder preview pane (right) next to the file list | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d8/6a/5d/d86a5dcd-2436-46e3-b782-6b5051272eee/AppStoreImage-1440x900.png/1600x1000bb.jpg |
| W7 | Vendor site: Info.plist as a Key / Type / Value outline ("14 entries" header, colored type names, zebra rows), spacebar size and pane size side by side | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/4f/a0/ef/4fa0efb6-6cb9-1633-5077-f1c6add235a2/AppStoreImage-1440x900.png/1600x1000bb.jpg |

### Observations by rubric dimension
**1. Preview anatomy — 3/5**
- Structured previews open with a header block: icon, title, small caps subtitle, pill badges (Development, Sandboxed, Hardened Runtime, Valid) and then a two-column key/value table (#3). xcodeproj has a count line (36 source files, 6 resources, 0 frameworks), target chips, build-configuration chips and a raw excerpt below (W1).
- Plist keeps a "Info.plist - 14 entries" centered caption over a Key / Type / Value outline (W7).
- The store copy says a short badge such as "Folder - LookQuick" names the provider. **No screenshot shows it**, so its position and weight are unknown.
- Different formats get different anatomies and different theme treatments (a gallery of looks rather than one frame).

**2. Content presentation — 3/5**
- 20 named syntax themes (Xcode, GitHub, Monokai, Dracula, Cyberpunk Neon, Shades of Cyan, Vaporwave, Blood Moon, AmberCRT, Hacker Green, Synthwave, Solarized, Nord, One Dark, Midnight UV; W3). Plist types are colored (String green, Dictionary magenta).
- Animated themes (Matrix rain, gradient wash) put text over moving or patterned backgrounds (#4, #5). In #4 body text is crisp but the Matrix rain is visible at the edges; in W5 the small summary labels are dim red on a near-black red wash and are low contrast. Accessibility risk, not evidenced as handled (a reduced-motion setting is not shown; only the Off/Low/Medium/High animation level is described in copy).
- Markdown, directory and archive previews adopt "native browsing style" (Finder-like lists, #4 lower row, W4) when the user chooses not to theme everything.

**3. Interaction & discoverability — 3/5**
- Directory previews offer split-pane inspection (list left, details right) and disclosure arrows (#4, W4). Archive and folder footers show "Compressed: 87 KB / Uncompressed: 141 KB / Compression ratio: 62.4 %" (W2).
- Search, shortcuts and in-preview controls: not shown. Media previews use the QuickTime transport (play/pause, scrubber, volume, subtitles, fullscreen; #1).

**4. States & honesty — 3/5**
- Copy promises a hex analysis or strings view when no dedicated preview exists, and a detector card for unknown binaries ("Detection: magic (confidence: 95%)", Magic Bytes, SHA-256; #3). Stating confidence is a good honesty pattern; no screenshot of the hex/strings fallback.
- Truncation, loading, error states: not shown.

**5. Companion / settings app — 4/5**
- Window with a sidebar (Appearance, Code, Markdown, Formats, Directories, General) and a single scrolling "Syntax Theme" page: a 4-column grid of cards, each card a 6-line live mini sample in that theme's own colors with the name below, selected card ringed in orange with a check badge. Caption: "choose a color scheme for code syntax highlighting in quicklook previews" (W3).
- Copy claims changes apply instantly to the extension and that the app checks extension status and scans /Applications, ~/Downloads and external volumes for conflicting plugins, offers an in-app preview, a Quick Action and a keyboard-shortcut service. **None of the conflict scanner, status page or in-app preview is visible in any screenshot.**
- Formats page content: not shown.

**6. Visual identity & native feel — 3/5**
- Icon is a flaming eye (variants per theme in marketing); store art is neon, Matrix green and gradient. Companion window itself looks native (traffic lights, sidebar toggle, SF type, system orange accent) but the marketing sells a gamer look rather than macOS restraint.
- Several marketing mock-ups (#5, #6) look like composites rather than real captures (the JAR tree has a stray right-hand time column); I cannot tell which UI is real.

**7. Trust & privacy communication — 3/5**
- "No analytics, no trackers, no usage data" and "Everything stays on your Mac" are copy. The nearest in-UI trust cue seen is the byte-level detector card (magic bytes, SHA-256, confidence), which shows what the app inferred. The provenance badge is described in copy only.

**8. Delight and friction — 3/5**
- Delight: 20 themes with instant effect; animation level Off/Low/Med/High, a thoughtful control for motion sensitivity; feature-rich inspectors.
- Friction: store copy attacks other plugins and says the developers deleted competing players. Pricing is split oddly (animated themes only), the vendor site still says "3 Premium animated themes" while the store says 21 and the site shows v3.0 against store 3.2.

### Worth matching or beating
1. **Theme picker as a grid of live mini-samples** with a ring and check on the chosen one.
2. **Provenance label** ("who made this preview") as a diagnostic that costs one line.
3. **Archive footer with compressed / uncompressed / ratio** and adaptive sizing for the small Finder pane versus the spacebar window (W1, W2 show both).

### Mistakes to avoid
1. Animated or patterned backgrounds behind text without a visible reduce-motion or contrast guarantee.
2. Promising a conflict scanner and keyboard-shortcut workaround that a user cannot see in the product.
3. A different layout language per format, which makes the preview family feel like 10 apps.

---

## iPreview
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Marketing: feature list (Source Code, Document, Archive, 3D Models, Other) beside a MacBook showing Finder + a Markdown Quick Look window | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/db/75/4f/db754f05-066b-3e67-57ba-bd9f5e3f0bc0/p1.png/1600x1000bb.jpg |
| 2 | Companion preferences window: 3-item toolbar (Code / 3D / About); Theme, Appearance (Auto), Font (Menlo 12pt), Line Numbers, Word Wrap, Tab Width + live code sample + "More information" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/1b/66/7d/1b667d47-3582-8451-de4e-845d80ac347d/p2.png/1600x1000bb.jpg |
| 3 | Companion preferences, 3D tab: Render mode popup, Animation checkbox + repeat count, Default lighting, live rotating model | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/51/32/f9/5132f9b8-9a2a-12af-1bb7-7ea3d74f86d0/p3.png/1600x1000bb.jpg |
| 4 | Swift file in Quick Look (spacebar) and Finder preview pane; gutter and mono on dark slate | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/13/c5/42/13c54270-f1af-b18a-01fd-76a3a5786b61/p4.png/1600x1000bb.jpg |
| 5 | Markdown + math typesetting at spacebar and pane sizes | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/a9/16/26/a91626a4-23cd-8bc4-a20d-428eb5442050/p5.png/1600x1000bb.jpg |
| 6 | ZIP preview: Name / Size / Date columns, nested disclosure, "Uncompress" button; pane variant | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/4b/72/99/4b72990f-2ef7-0dc0-6462-b6f284b33712/p6.png/1600x1000bb.jpg |
| 7 | FBX 3D model preview on gradient background, no chrome beyond title bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f4/14/17/f4141763-2b2f-7af3-cb37-def2501816d4/p7.png/1600x1000bb.jpg |
| 8 | Spotlight search result for Example.zip with the same archive preview | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/0e/51/17/0e5117cd-7aaf-5958-be49-de4a2304301d/p8.png/1600x1000bb.jpg |
| W1 | Vendor site: NSObject.h at spacebar size (14 themes claim) | https://www.appful.dev/images/d1.png |
| W2 | Vendor site: Markdown with math | https://www.appful.dev/images/d2.png |
| W3 | Vendor site: ZIP table | https://www.appful.dev/images/d4.png |
| W4 | Vendor site: FBX with wireframe + skeleton render mode (green bones over mesh) | https://www.appful.dev/images/d5.jpg |
| W5 | Vendor site: light and dark variants of the Code and 3D preference tabs | https://www.appful.dev/images/p1.jpg |

### Observations by rubric dimension
**1. Preview anatomy — 2/5**
- Content only, directly under the host title bar ("Open with Xcode", "Uncompress"). No header block, no metadata strip, no mode switch (#4, #5, #6). Archives and images advertise name/size/date and image dimensions as the metadata, shown only as table columns.
- Same plain anatomy at Finder pane size (small copy of the same content, "More..." button from Finder).

**2. Content presentation — 3/5**
- Code: 12 pt Menlo default, gutter in grey, 14 themes, light/dark following system (#2, W1). Markdown uses a GitHub-like sans with rules under headings, bulleted lists and typeset math (#5, W2). Archive table is native-looking with disclosure and alternating rows (W3).
- 3D: dark teal figure on a plain or translucent ground, optional wireframe and skeleton overlay in bright green (W4).

**3. Interaction & discoverability — 2/5**
- No in-preview controls shown. 3D animation plays automatically with a repeat count set in preferences; interactive rotation: not shown.
- Archive "Uncompress" is the Finder-supplied button.

**4. States & honesty — 2/5**
- The FAQ explains system-reserved types (".ts, .png, .jpg") cannot be taken by third-party extensions and gives a step list for "doesn't work". Good candor, but only on the website. No in-preview states shown.
- Marketing sample text has a typo ("Welcome to iPrevew" in #5 and W2).

**5. Companion / settings app — 2/5**
- A classic three-item toolbar preferences window (Code, 3D, About; #2, #3, W5). Code page: Theme popup (Default), Appearance popup (Auto), Font with system font well, Show checkboxes (Line Numbers, Word Wrap), Tab Width stepper, and a live sample below. 3D page: Render mode popup, Animation checkbox with repeat stepper, Default lighting, live model.
- No per-type toggles (enable/disable is via System Settings, per FAQ), no first-run flow, no conflict help.

**6. Visual identity & native feel — 3/5**
- Faithful macOS controls, correct in light and dark (W5 shows both), but visually dated (toolbar preferences from earlier macOS). Store art is a pastel illustration with a stock character (appful.dev p1), unrelated to the product.

**7. Trust & privacy communication — 2/5**
- Nothing in-UI. Site has a privacy page and a Google Tag Manager script (page source), which is a mismatch for a "local previewer" brand.

**8. Delight and friction — 3/5**
- Delight: animated 3D playback and render modes (physics, bounding boxes, wireframe, skeleton) in a previewer; Spotlight preview of an archive (#8).
- Friction: settings page lists only Code and 3D, so Markdown/Archive/Image have no appearance settings visible.

### Worth matching or beating
1. **Live sample under the controls** in a small preferences window; the whole preference surface fits one screen.
2. **Same preview rendered in Finder, Quick Look and Spotlight** is shown in marketing (#8): a good reminder to test all three surfaces.
3. **Candid FAQ about reserved types**.

### Mistakes to avoid
1. No visible metadata or status anywhere in the preview.
2. Spelling mistakes in the product's own sample text.
3. A tracker script on the site of a privacy-sensitive utility.

---

## GoodQuickLook
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Marketing: 12 plugin cards (Code, Markdown, Archives, Images, Documents, Data, Config, Scripts, Fonts, Packages, Media, More) with 2-3 letter badge icons | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ab/ad/70/abad70c5-976c-42d2-0ff8-7c761c5254c9/05-plugin-coverage-2880x1800_copy.png/1600x1000bb.jpg |
| 2 | Folder preview: header block (big folder icon, name, "20 file(s) - 1 hidden - 13.9 MB"), Name/Date Modified/Size/Kind table, bottom bar with mono path left and two small icons right | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/2c/bd/eb/2cbdebd1-6105-f9aa-20c9-748707cbfbfa/02-folder-preview-2880x1800.png/1600x1000bb.jpg |
| 3 | Archive preview (7z): header block (green zip icon, name, "8 items - 8.6 MB", "7z"), blue "Extract Here" button, tree table, bottom bar "7z  8 items  16.2 MB -> 8.6 MB  47%" and three icons | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e0/6f/fe/e06ffef4-25e2-18ad-7756-45f173000b88/03-archive-preview-2880x1800.png/1600x1000bb.jpg |
| 4 | Markdown preview "Modern Media" theme: red-rule headings, quote block, bottom bar "2 KB" left, {} / list icons and theme popup right | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/c7/ca/6b/c7ca6b54-966b-5af9-63f4-24423918abf5/04-markdown-preview-2880x1800.png/1600x1000bb.jpg |
| 5 | Code preview (jQuery): line-number gutter on tinted block, links underlined, bottom bar "253 KB - 9405 lines - UTF-8 - LF" left, theme popup "Coldark-Cold" and copy icon right | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d5/1a/e7/d51ae78a-1a1d-1f03-9839-454dc8a8f08c/01-code-preview-2880x1800.png/1600x1000bb.jpg |
| W1 | Vendor site (funnytoys.app/goodquicklook) has no image files; its showcase is HTML mock-ups of folder, 7z, image-metadata, code and Markdown previews, plus a Free vs Lifetime Pro table | https://funnytoys.app/goodquicklook |

### Observations by rubric dimension
**1. Preview anatomy — 5/5**
- The only app in the cluster that shows one shared frame across formats: host title bar, then (for folders and archives) a **header block** with a large format icon, bold name and a grey summary ("20 file(s) - 1 hidden - 13.9 MB", "8 items - 8.6 MB"), then content, then a **thin bottom status bar** (#2, #3, #4, #5).
- Status bar: left = facts in small mono ("253 KB - 9405 lines - UTF-8 - LF"; "7z 8 items 16.2 MB -> 8.6 MB 47%"; "2 KB"; a path "/Users/demo/bmp"), right = 1-3 icon controls and, for text, a theme popup ("Coldark-Cold", "Modern Media"). The bar sits over a faint pastel gradient.
- A primary action sits in the header's right corner as a tinted pill: "Extract Here" (blue, #3), "Open with TextEdit" (host). Website mock-ups also show breadcrumb path, image metadata rows (Width, Height, Pixels, Format, Location) and an "Extract" button.

**2. Content presentation — 3/5**
- Code: mono in a tinted block, grey right-aligned gutter, underlined link colors, shown with the Coldark-Cold light theme (#5; default not stated). Markdown "Modern Media": red accent bars next to headings, italic quote with a left rule, centered "..." divider, generous margins (#4).
- Folder/archive tables are standard: Name, Date Modified, Size (mono), Kind, zebra rows, disclosure arrows (#3).
- Default visuals are light; dark appearance not shown in screenshots.

**3. Interaction & discoverability — 4/5**
- Theme popup lives inside the preview's own status bar, so a user can try themes without opening the companion. That is the key discovery here.
- The unlabeled icons (a copy glyph on code, `{}` and a list glyph on Markdown, share/hash/sidebar glyphs on archive) are not explained in any screenshot. Their meaning (source toggle, outline, copy) is inference from the glyph, so **treat as unknown**.

**4. States & honesty — 3/5**
- Status bar tells hidden count ("1 hidden"), compression delta and percent, encoding and line endings: more facts than any other app here.
- The free tier has a "simultaneous plugin limit" (website FAQ: "Confirm that its plugin is enabled. The free version has a simultaneous plugin limit") and the support page calls it a "plugin quota". A preview can therefore silently fall back to the native one, and no screenshot shows a message explaining it.
- Empty, error and truncated states: not shown.

**5. Companion / settings app — 2/5**
- Not shown in any screenshot. Copy says the app prompts to enable Quick Look, Thumbnail and Finder extensions and has theme and font settings; "Finder toolbar integration" is mentioned without screenshot.
- Support page advises "relaunch Finder or restart your Mac" if the native preview still shows.

**6. Visual identity & native feel — 4/5**
- Light, airy; hairline separators, pill action, popup buttons that match macOS. Store frames use a white card on pale blue waves, with large headings ("Browse folders at a glance"): consistent and calm.

**7. Trust & privacy communication — 3/5**
- Website FAQ: "Never" uploads, strictly local rendering. Nothing in the preview itself. Mock-ups show no secret handling.

**8. Delight and friction — 3/5**
- Delight: consistent bar; the "47%" compression ratio and the arrow from original to compressed size are quick wins.
- Friction: quota; unlabeled icons; no visible explanation of limits.

### Worth matching or beating
1. **Shared bottom status bar** (facts left, mode controls right) and **header block** for container formats.
2. **Theme popup inside the preview** (then also in the companion).
3. **Compression delta in the footer** and encoding/line-ending facts for text.

### Mistakes to avoid
1. Unlabeled icon buttons with no tooltip evidence.
2. A free-tier quota that makes a previously working preview fall back without a notice.
3. Tinted text blocks whose contrast changes with the chosen theme without a contrast guard.

---

## Cluster synthesis

### Patterns most apps share (table stakes)
- Host title bar plus content-first layout; "Open with X" comes from Quick Look, not the app.
- Folder and archive previews as a four-column Name / Date / Size / Kind table with disclosure triangles and zebra rows (Unfold #3/#4, iPreview #6, GoodQuickLook #3, LookQuick W4).
- Source code with a dimmed line-number gutter and a named theme; word wrap and font size in the companion (all four).
- Appearance follows the system; preview works at both Finder pane and spacebar size (shown by LookQuick and iPreview).
- Companion app = sidebar or toolbar prefs window with a live sample (Unfold, LookQuick, iPreview).

### Patterns only one or two apps have that users would notice
- Unfold: Markdown outline sidebar; EPUB chapter list; app-bundle card with green-check rows; torrent panes; per-page live samples in settings; settings search; layout/sort capsules and bottom path bar in folders; "Aa" book themes.
- LookQuick: theme grid of live mini-samples; provenance badge, conflict scan and in-app preview (copy only); byte-level detector with confidence; compressed/uncompressed/ratio footer.
- GoodQuickLook: shared header + bottom status bar; in-preview theme popup; file facts (encoding, line endings, line count).
- iPreview: animated 3D with render modes; Spotlight preview shown.

### Where every app in this cluster is weak (our opening)
- **Trust is copy only.** No app shows "local / read-only / nothing uploaded" or any secret-masking cue inside a preview or in the companion.
- **Honest partial results are not shown.** No screenshot of a truncated, oversized, too-complex or unsupported state in any of the four.
- **No first-run onboarding or extension-health page is visible.** Unfold shows the System Settings sheet only as marketing; LookQuick describes a status checker; nobody shows it.
- **Provider conflict help is thin.** Only LookQuick addresses it, and only in copy.
- **No accessibility story**: no mention of VoiceOver, keyboard navigation of outlines, or contrast guards; animated themes make this worse.
- **Languages**: only GoodQuickLook's site and Unfold's changelog (3.1.0 adds Chinese, Japanese, Korean, English dialects) mention localization; none shown in app.
- **Consistency** is the exception, not the rule: only GoodQuickLook has one frame for all formats, and it is light and small.

### Scorecard (out of 5)
| App | 1 Anatomy | 2 Content | 3 Interaction | 4 States | 5 Companion | 6 Visual | 7 Trust | 8 Delight |
|---|---|---|---|---|---|---|---|---|
| Unfold | 4 | 4 | 4 | 3 | 4 | 4 | 2 | 4 |
| LookQuick | 3 | 3 | 3 | 3 | 4 | 3 | 3 | 3 |
| iPreview | 2 | 3 | 2 | 2 | 2 | 3 | 2 | 3 |
| GoodQuickLook | 5 | 3 | 4 | 3 | 2 | 4 | 3 | 3 |

Scores reflect marketing material only; "not shown" is scored as 2-3, never as absent.

### Ten ranked recommendations for SpacePane
1. **A shared bottom status strip across all 76 types (facts left, mode controls right).** Facts such as size, line count, encoding, line endings, container counts and how many likely secrets are concealed; right side: Source/Rendered, Tree/Raw and a copy action, each with a tooltip and VoiceOver label. Why: GoodQuickLook is the only app with one anatomy and it scored 5/5 on this dimension (#2-#5); the Unfold 2.8.2 changelog added a "metadata-strip" for the same reason. Rules: strings localized in 14 languages, no source values (typed counts only, per safety-findings decision), selectable text unaffected, native AppKit. Cost M.
2. **Folder and archive preview anatomy.** Header (icon, name, "N files - M hidden - size"), sortable disclosure table with dimmed hidden files, footer with compressed to uncompressed size and ratio, plus an explicit "showing first N of M" notice at our budget limits. Why: Unfold #3/W1, GoodQuickLook #3, LookQuick W2. Rules: bounded, read-only, no nested archive recursion; do not imply a full scan. Cost M.
3. **Theme page as a grid of live mini-samples.** Cards for Light, Dark, High Contrast, System and each profile, each rendering the real format sample (we already have one per format) in that palette, with a selected ring and check. Why: LookQuick W3 is the clearest theme picker observed; Unfold's "Aa" chips (#9) show a compact variant. Rules: no animated themes (contrast and reduced-motion), accessible contrast variants kept, appearance-only change never touches the source. Cost M.
4. **Honest "made by" line, not a conflict scanner.** A small localized origin label inside the preview footer ("Preview by SpacePane") plus a companion help card, "If a preview looks different, another app may be handling that type". Why: LookQuick's badge is the only provider-conflict affordance in the category, and a Reddit quote on unfold.tools shows users hit conflicts. It is true by construction, so it stays within "we never claim Finder uses this provider"; scanning other apps is not sandbox-safe and we should not mimic it. Rules: wording must say who rendered this preview, never who Finder will choose. Cost S.
5. **Markdown outline sidebar that collapses when narrow.** Left outline tree, current heading highlighted, toggle in the status strip, auto-hidden below a width threshold; same pattern for notebooks and Jupyter cells. Why: Unfold #2 (outline) and #5 (chapters); GoodQuickLook's markdown copy mentions a live Table of Contents. The landscape file lists TOC as a gap. Rules: native NSOutlineView with accessibility metadata, no web view. Cost M.
6. **A per-type settings detail with a live sample on top, and a settings search field.** In File Types and Theme, pin the format's built-in sample above its controls; add one-line captions giving the cost of each choice; add a sidebar search box. Why: Unfold #8-#10 do exactly this and it scored best among companions; iPreview #2 shows the minimal version. Rules: stay in the single-window fixed sidebar; no new windows. Cost S.
7. **Design for two sizes explicitly.** Define compact (Finder preview pane, Spotlight) and full (spacebar) densities: drop gutters/sidebars and shorten the strip in compact. Why: LookQuick W1/W2 and iPreview #4-#6 show both sizes, and Unfold 3.2.0 fixed "wrong size or resizing unexpectedly" (changelog), warning against trying to control the window. Rules: do not resize Quick Look windows; test all hosts separately. Cost S-M.
8. **A summary-card pattern for binary or structural types** (MIDI, SQLite schema, CAD): icon, name, labeled rows, green-check or neutral status rows, footer "size - modified". Why: Unfold W2 and LookQuick #3 present metadata as scannable key/value cards. Rules: show facts we actually derived, mark inferred values and give confidence in words (LookQuick's "confidence: 95%" is a good model), never claim signature verification we do not perform. Cost S.
9. **A visible fallback banner for every degraded path.** One line at the top or in the strip: "Too large to render; showing first 2 MB as text", "Concealed 3 values", "Type turned off in Settings". Why: Unfold's changelog describes fallbacks but no screenshot shows any; no competitor exposes limits (cluster weakness). GoodQuickLook's quota is the cautionary case. Rules: honest status wording, localized with plural rules. Cost S.
10. **Onboarding card with a localized picture of the System Settings extension list and an "Open Extensions Settings" button, plus a stale-state hint.** Why: Unfold shows the System Settings sheet only on its website (W10); GoodQuickLook's support page tells users to relaunch Finder or restart; no app shows onboarding. Rules: wording reports where settings are saved, never that Finder uses our provider; do not kill Finder or alter system preferences. Cost S.

**Not for us:** animated themes, transparent preview backgrounds, a rule-breaking conflict scanner that reads other apps' bundles, gamer branding, a free-tier plugin quota, third-party analytics scripts on the site, and marketing that attacks other plugins.
