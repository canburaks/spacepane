# Competitor refresh, 2026-10-13

Retrieved 2026-10-13 from Apple's public iTunes Search/Lookup API (US storefront) and two vendor pages; every feature is the vendor's own claim, not tested.

**Partial run.** The iTunes Search API returned HTTP 403 ("Rate limit has been exceeded") from about 20:52 on 2026-10-13 onward. The baseline Lookup batch succeeded earlier, at 20:41. Only 13 name searches succeeded before the block. The broad new-entrant searches did not run at all. Treat the new-entrant list below as incomplete and the claim counts as a count over the 26 in-scope apps, not over the market.

## Method and limits

- **Baseline reference:** `docs/market/2026-10-05-competitor-landscape.md`.
- **Step 1, Lookup (succeeded):** one batched `lookup?id=...&country=us` call for the 12 baseline IDs, run at 20:41. Eleven returned. `1709782189` (PreviewBundle 2) is a `bb` storefront listing and returned zero results on the US storefront.
- **Step 1, name searches (partly succeeded):** 13 baseline apps were found by name searches and are in scope. Some matches were confirmed through same developer and price or the last-update date. Others are matched on name only, because the baseline does not name the developer. Those are flagged below.
- **Step 1, name searches not run (rate-limited):** Marked QL, Peekdown, Markdown Quick Look (Bitfield), Markdown Peek, MD QuickView, MarkLook, quicklook.md, JSON Loupe, QLook JSON, Fast SQLite Viewer, Quick Data Insights, Python Data Viewer, SpacePeek, FolderPlus (the saved response was empty), Quick Preview: Folder Preview, Loupe, Archive Quick Look, Folder QuickLook, Preview Folders (found incidentally, see below), FolderPreview, FolderVitrine, Scope, StepPreview, MakersPreview, Eyemesh, mesh-peek, Peek3D, 3MF Viewer, QLPlay, QLMedia, Ogg Quicklook, Sequences, Book Preview, QuickLook for IPA & APK, PlantUML QuickLook, GPX Preview, the DICOM apps, FITS, PSB Quick Look HD, inddPreview, ChmPages, Apparency, Suspicious Package, Pacifist, BetterZip, ProvisionQL. PreviewBundle 2 was not queried on the US storefront beyond the Lookup above.
- **Name searches run with no App Store match:** Syntax Highlight (sbarex) and QLMarkdown (sbarex) are GitHub-only in the baseline. The US search returned no matching listing. QLStephen returned zero results on 20:42. That saved response was valid, but I removed it in a later cleanup step, so only this note remains.
- **Step 2, new-entrant searches (NOT run):** `quick look`, `quicklook`, `file preview`, `finder preview`, `preview extension`, `quick look plugin`, `quick look extension`, each with `entity=macSoftware&country=us&limit=200`. These must be re-run later.
- **Step 3, vendor pages (succeeded):** fetched with curl on 2026-10-13. `unfold.tools/changelog` and `quicklookpro.com`. WebFetch was also tried for the search endpoint and was refused with 403, so it was not used for any data.
- **Step 4 scope:** 26 apps. The 11 baseline Lookup apps, the 13 name-matched baseline apps, and 2 Quick Look-mentioning apps absent from the baseline. Descriptions were classified by keyword match, then checked by hand against the matched text.
- **Classification rules:** the 74-type list was read literally, with three conventions. (a) Programming languages, configuration files, Markdown-family extensions and extension-free developer files count as covered by "source code", "plain text" or "Markdown family". (b) Negated limitation sentences ("cannot handle .pdf") are not claims. (c) Font-size or font-setting controls are not font-file claims.
- **Discrepancy to check:** the 74-type list supplied for this task does not include STEP or IGES. The baseline lists SpacePane's STEP and IGES support as a differentiator. The STEP row below follows the list as supplied.
- **Not verified:** nothing was installed or tested. All feature statements are vendor descriptions or vendor release notes.

## Changes since 2026-10-05

"Baseline" is the value in the 2026-10-05 document. Where the baseline did not record a value, the row says so.

| App (trackId) | Baseline | Now (US API) | Change | Vendor release note |
|---|---|---|---|---|
| LookQuick (6759767692) | v3.2, 2026-09-15, Free with IAP, macOS 14+ | v4.0, 2026-10-07, Free, macOS 14 | **Major version since baseline** | MKV plugin crash fix; centering fix in small Finder preview pane; stability |
| Unfold (6760872758) | v3.0.2, 2026-09-12, $9.99, macOS 15.6+ | v3.0.2, 2026-09-12, $9.99, macOS 15.6 | No App Store change. Vendor changelog (step 3) lists v3.2.0 dated Oct 3, 2026. The App Store still shows 3.0.2. | n/a (see vendor pages) |
| Universal 3D Previewer (6764180617) | Free; version not recorded | v3.1, 2026-08-05, Free, macOS 14.6 | Version recorded now. Vendor says SOLIDWORKS files now preview as interactive 3D, not a flat image. | SOLIDWORKS interactive 3D; faster Finder previews for SOLIDWORKS |
| Source Code Preview (6759270528) | $4.99; version not recorded | v1.5, 2026-09-01, $4.99, macOS 13 | Version recorded now | PowerShell and Nix support; Gruvbox theme |
| PreviewJson (6443584377) | **Free** | **$2.99**, v2.0.2, 2026-05-01, macOS 12.4 | **Price differs from baseline** | none recorded |
| Preview Folders (6748542679) | Not priced individually; group range $0.99–$3.99 | **Free**, v64.0.6, 2026-10-08, macOS 14 | **Price differs from baseline group range.** Matched by name only. | asset optimisation; under-the-hood |
| Markdown Preview (Anybox) (6739955340) | $1.99; version not recorded | $1.99, v2.6, 2026-10-08 (listed as "Markdown Preview - Quick Look") | Version recorded now. Price unchanged. | better .qmd support; minor fixes |
| Folder Preview (Anybox) (6698876601) | $1.99; version not recorded | $1.99, v3.1.1, 2026-10-02 | Version recorded now | minor fixes |
| FinderPeek (6761670824) | $4.99; version not recorded | $4.99, v1.3, 2026-10-02 (listed as "FinderPeek: Quick Code Viewer") | Version recorded now | "Adding rating for appstore." |
| PeekCode (6760995314) | Free; version not recorded | Free, v1.4.1, 2026-08-20 | Version recorded now. Developer not named in baseline. | fixed known issues; performance and stability |
| Code Peek+ (6760186407) | Free; version not recorded | Free, v1.0.3, 2026-04-10, macOS 14 | Version recorded now | redesigned settings window; Finder Quick Look shortcut guidance |
| QuickLook Video (6759566961) | $3.99; version not recorded | $3.99, v3.12, 2026-09-21, macOS 26 | Version recorded now. Price unchanged. | "View Contact Sheet" Finder Services entry for video; CoreAudio codecs |
| Glance (1564688210) | "last updated 2024-07" | Free, v3.0, 2024-07-18, macOS 10.15 | Unchanged. Developer not named in baseline. | none recorded |
| PreviewMarkdown (1492280469) | $2.99 | $2.99, v2.4.3, 2026-05-01 | Price unchanged | thumbnail-generation crash fix for tables |
| PreviewCode (1571797683) | $2.99 | $2.99, v2.3.2, 2026-08-06 | Price unchanged | .bash and .tcsh preview fix |
| PreviewText (1660037028) | Free | Free, v1.0.9, 2025-04-13 | Unchanged | none recorded |
| PreviewYaml (1564574724) | $1.99 | $1.99, v1.2.3, 2025-04-13 | Unchanged | none recorded |
| iPreview (1519213509) | v3.3.0, 2026-10-03, $6.99 | Same | Unchanged | macOS 27 compatibility; crash fix on macOS 15 |
| Peek (1554235898) | v2.6.4, 2022-04-02, $7.99 | Same | Unchanged | dependency updates |
| Simple Quick Look (6762875743) | v1.0, 2026-04-26, Free | Same | Unchanged | none recorded |
| QuickestLook (6765485652) | v1.0, 2026-05-01, Free, macOS 26 | Same | Unchanged | none recorded |
| GoodQuickLook (6770471994) | v1.0.4, 2026-06-13, Free | Same | Version unchanged. **Description changed:** the baseline cited HEIC, SVG, PSD, OTF and TTF; the current description says "images" and "font settings" only. | none recorded |
| Super Quick Look (6783296336) | v1.0.3, 2026-09-15, $3.99 | Same | Unchanged | broader syntax highlighting; folder previews on demand; structured summaries for archives, JSON, CSV/TSV, SQLite, Parquet, Avro, Feather |
| QuickLook Pro (6812534537) | v1.1, 2026-09-22, $3.99 | Same | Unchanged | MIDI, XIP, ZIP64 and dotfile previews (already in baseline) |
| PreviewBundle 2 (1709782189) | $5.99 (bb storefront) | Zero results on US storefront | Not checkable on US storefront | none |
| Syntax Highlight, QLMarkdown (sbarex) | GitHub only | No US App Store match | Consistent with baseline | n/a |

Two baseline items could not be checked: the Glance developer and the PeekCode developer. Both matches are by name.

## New entrants

Only the 13 name-search responses that succeeded were available. The broad new-entrant searches did not run. The list below is therefore incomplete.

Criteria: the description mentions Quick Look and the app is absent from the baseline, or its releaseDate is on or after 2026-08-01.

| App | Developer | Price | Release date | Version date (version) | App Store URL | What it previews (vendor description, paraphrased) |
|---|---|---|---|---|---|---|
| OK JSON - Viewer & Formatter | Anybox LTD | Free | 2021-08-19 | 2026-10-09 (3.1.1) | https://apps.apple.com/us/app/ok-json-viewer-formatter/id1576121509 | JSON viewer app with a bundled Quick Look extension for JSON files; formatted view in Finder. Not in the baseline. |
| QL Markdown by XN | XNsystems Co., Ltd | $2.99 | 2026-05-08 | 2026-05-17 (1.1) | https://apps.apple.com/us/app/ql-markdown-by-xn/id6764049637 | Markdown in Quick Look with KaTeX math, Mermaid, footnotes and folder-access handling for local images. Not in the baseline. Distinct from sbarex's QLMarkdown, which is GitHub-only. |

Baseline app that meets the date rule only: **QuickLook Pro** (releaseDate 2026-09-22). It is already in the baseline.

## Vendor pages

- **unfold.tools/changelog** (fetched 2026-10-13). The latest entry is v3.2.0, dated Oct 3, 2026. Nothing is dated after 2026-10-05. The 3.2.0 entry adds interactive previews and Finder thumbnails for 3MF and STEP files, Restore Purchases, and an "Open Unfold" button. The 3MF and STEP items are already in the baseline's amended key finding 5, but the baseline's comparison table still shows 3.0.2. Claims absent from the baseline body include the following. v3.1.0 (Sep 15) added localisation for Simplified Chinese, Japanese, Korean and several English regional variants. v2.8.x added a path bar, sub-folder navigation with copy in folder previews, line wrapping, Mermaid zoom and Markdown front matter. v2.7.x added archive encoding options, `.mdc` Markdown, PopClip support and Markdown hot reload. v2.4.0 added `.sif` and `.foundation` Swift files. v2.5.0 added per-category toggles. v2.1.1 added GROMACS extensions (`.top`, `.gro`, `.mdp`, `.itp`, `.xvg`, `.ndx`, `.err`, `.out`).
  - **Discrepancy:** the changelog dates v3.0.2 to Sep 8; the App Store shows Sep 12. The App Store still lists 3.0.2 while the changelog lists 3.2.0.
- **quicklookpro.com** (fetched 2026-10-13). The page says "300+ file types", lists folders, archives, source code and MIDI audio, and says "Works offline" with "macOS 15+". It has no version or date. Nothing new against the baseline.

## Claims SpacePane's catalog does not include

Counts are distinct in-scope apps (n = 26). Each claim is the vendor's own description or release note. Negated limitations are excluded (see Method).

### Documents

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| HTML pages | QuickestLook; Super Quick Look; Code Peek+ (described as "limited and system-dependent") | https://apps.apple.com/us/app/quickestlook/id6765485652 · https://apps.apple.com/us/app/super-quick-look/id6783296336 · https://apps.apple.com/us/app/code-peek/id6760186407 | **3** |
| PDF thumbnails (folder view) | Folder Preview | https://apps.apple.com/us/app/folder-preview/id6698876601 | 1 |
| PostScript and `.ePDF` documents | Peek | https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 | 1 |
| CBR and CB7 comics | Unfold | https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 | 1 |
| Font files (TTF, OTF) | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| Office (DOCX, XLSX, PPTX), OpenDocument, iWork, RTF, PDF as previews | None. Peek and PeekCode list them as things they cannot handle. | n/a | 0 |
| MOBI/AZW, DjVu, KEPUB, CHM, email (`.eml`, `.msg`), calendar and contacts (`.ics`, `.vcf`) | None in scope | n/a | 0 |

### Media

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| Video: MKV, WebM, AVI, WMV, FLV, MP4, MOV, RealMedia, MXF | LookQuick (over 50 formats via QuickTime); QuickLook Video | https://apps.apple.com/us/app/lookquick/id6759767692 · https://apps.apple.com/us/app/quicklook-video/id6759566961 | **2** |
| Lottie animations | Code Peek+ | https://apps.apple.com/us/app/code-peek/id6760186407 | 1 |
| SWF (Flash) | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| Audio (MP3, FLAC, WAV, Ogg) | None in scope | n/a | 0 |

### 3D and CAD

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| STEP (`.step`, `.stp`) | Universal 3D Previewer. Vendor changelog for Unfold 3.2.0 adds STEP previews (not in its App Store description). | https://apps.apple.com/us/app/universal-3d-previewer/id6764180617 | 1 (2 with Unfold changelog) |
| SOLIDWORKS (`.sldprt`, `.sldasm`, `.slddrw`, `.sldlfp`) | Universal 3D Previewer | https://apps.apple.com/us/app/universal-3d-previewer/id6764180617 | 1 |
| Alembic (`.abc`) | Universal 3D Previewer | https://apps.apple.com/us/app/universal-3d-previewer/id6764180617 | 1 |
| G-code | Universal 3D Previewer | https://apps.apple.com/us/app/universal-3d-previewer/id6764180617 | 1 |
| FBX | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| COLLADA (`.dae`) | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| 3DS | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| Blender (`.blend`) | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| DXF | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| Other legacy 3D formats (`.ac`, `.ase`, `.b3d`, `.cob`, `.csm`, `.lwo`, `.md2`, `.md5mesh`, `.mdl`, `.ms3d`, `.nff`, `.off`, `.q3o`, `.smd`) | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 each |
| IGES | None in scope | n/a | 0 |
| glTF/GLB, USD/USDZ | None in scope | n/a | 0 |

### Developer

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| Xcode projects (app inspection) | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| Signing, sandbox and hardened-runtime inspection of apps | Unfold (signing identity, App Sandbox status, hardened runtime status) | https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 | 1 |
| Chinese mini-program files (WXML/WXSS, AXML/ACSS, TTML/TTSS, SWAN) | Simple Quick Look | https://apps.apple.com/us/app/simple-quick-look/id6762875743 | 1 |
| PlantUML | Super Quick Look | https://apps.apple.com/us/app/super-quick-look/id6783296336 | 1 |
| Hex or strings fallback for unknown files | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |

### Data

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| DICOM, FITS, GROMACS, HDF5, R/Stata/SPSS, TCX/FIT, spreadsheet previews | None in scope | n/a | 0 |

Note: the Python Data Viewer and the DICOM apps were not searched, so this row is not a market count.

### Design (images)

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| WebP and AVIF | iPreview | https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | 1 |
| Animated JXL | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| SVG (vector preview) | QuickestLook | https://apps.apple.com/us/app/quickestlook/id6765485652 | 1 |
| HEIC, PSD | None in the current descriptions. The baseline cited these for GoodQuickLook. | n/a | 0 |

### Other

| Claim | App | App Store URL | Apps |
|---|---|---|---|
| Disk images and virtual machines (UTM, VMware VMs) | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| Vehicle diagnostic files | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |
| ZIPX; TAR.ZST (Zstandard) | Super Quick Look | https://apps.apple.com/us/app/super-quick-look/id6783296336 | 1 each |

### Features (outside the 74-type list)

The baseline records that SpacePane has generic thumbnails and has no Markdown math or table of contents. These rows are listed as the vendors describe them, not as confirmed gaps.

| Feature | App(s) | App Store URL(s) | Apps |
|---|---|---|---|
| Finder or Quick Look thumbnails | PreviewCode; PreviewJson; PreviewYaml; PreviewText; PreviewMarkdown; QuickLook Video; Universal 3D Previewer; GoodQuickLook (custom thumbnails); QuickLook Pro (thumbnail extensions). Folder-view thumbnails only: Folder Preview; Unfold. | https://apps.apple.com/us/app/previewcode/id1571797683 · https://apps.apple.com/us/app/previewjson/id6443584377 · https://apps.apple.com/us/app/previewyaml/id1564574724 · https://apps.apple.com/us/app/previewtext/id1660037028 · https://apps.apple.com/us/app/previewmarkdown/id1492280469 · https://apps.apple.com/us/app/quicklook-video/id6759566961 · https://apps.apple.com/us/app/universal-3d-previewer/id6764180617 · https://apps.apple.com/us/app/goodquicklook/id6770471994 · https://apps.apple.com/us/app/quicklook-pro-file-preview/id6812534537 · https://apps.apple.com/us/app/folder-preview/id6698876601 · https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 | **11** (9 for Finder or Quick Look thumbnails, plus 2 folder-view) |
| Math typesetting (KaTeX, MathJax, LaTeX math) | Markdown Preview - Quick Look; Peek; QL Markdown by XN; Unfold; iPreview | https://apps.apple.com/us/app/markdown-preview-quick-look/id6739955340 · https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 · https://apps.apple.com/us/app/ql-markdown-by-xn/id6764049637 · https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 · https://apps.apple.com/us/app/ipreview-enhanced-quick-look/id1519213509 | **5** |
| Table of contents | Peek; PeekCode; Unfold | https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 · https://apps.apple.com/us/app/peekcode/id6760995314 · https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 | **3** |
| Copy from preview | FinderPeek (select and copy); Folder Preview (copy file or path); PeekCode (one-click copy) | https://apps.apple.com/us/app/finderpeek-quick-code-viewer/id6761670824 · https://apps.apple.com/us/app/folder-preview/id6698876601 · https://apps.apple.com/us/app/peekcode/id6760995314 | **3** |
| Search inside preview | Peek; OK JSON - Viewer & Formatter (⌘F) | https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 · https://apps.apple.com/us/app/ok-json-viewer-formatter/id1576121509 | **2** |
| Quick Action, keyboard shortcut or CLI | LookQuick; Peek | https://apps.apple.com/us/app/lookquick/id6759767692 · https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 | **2** |
| Live reload | Unfold | https://apps.apple.com/us/app/unfold-quick-look-previews/id6760872758 | 1 |
| Jump to line or page | Peek | https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898 | 1 |
| Finder toolbar integration | GoodQuickLook | https://apps.apple.com/us/app/goodquicklook/id6770471994 | 1 |
| Folder size and item statistics | Super Quick Look | https://apps.apple.com/us/app/super-quick-look/id6783296336 | 1 |
| Provider-conflict handling | LookQuick | https://apps.apple.com/us/app/lookquick/id6759767692 | 1 |

## Sources

- Lookup, baseline IDs (run 2026-10-13 20:41): `https://itunes.apple.com/lookup?id=1519213509,1554235898,1709782189,6759270528,6759767692,6760872758,6762875743,6764180617,6765485652,6770471994,6783296336,6812534537&country=us`
- Lookup, PreviewBundle 2 on US storefront: `https://itunes.apple.com/lookup?id=1709782189&country=us` (zero results)
- Name searches, US storefront, `entity=macSoftware`, `limit=10`, that succeeded: QuickLook Video, Glance, PreviewMarkdown, PreviewCode, PreviewJson, PreviewText, PreviewYaml, Code Peek+, PeekCode, FinderPeek, QLMarkdown, Syntax Highlight, the QLStephen response was valid but was removed in a later cleanup step, and rate-limit error bodies were discarded. Each query used `https://itunes.apple.com/search?term=<name>&entity=macSoftware&country=us&limit=10`.
- Vendor pages (fetched 2026-10-13 with curl): `https://unfold.tools/changelog`; `https://quicklookpro.com/`
- Baseline: `docs/market/2026-10-05-competitor-landscape.md` in this repository.
- Raw saved responses (untrusted data, parsed with `python3 -I` only): `/private/tmp/claude-501/-Users-cbs-Github-spacepane/af5674aa-cef1-491c-95c9-2f78db05e16e/scratchpad/competitor-refresh/` (`lookup_baseline_ids.json`, `search_*.json`, `unfold_changelog.html`, `quicklookpro_home.html`, `status.log`).
