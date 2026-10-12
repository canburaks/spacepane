# Folders, archives and 3D/CAD previews — UX/UI observations
Researched 2026-10-06. Sources are vendor marketing (App Store, websites, repositories); nothing was installed or tested. Every statement below is **observed in marketing material** unless marked otherwise. "n/s" means not shown in any source I could open.

Method: App Store metadata through the public iTunes lookup API; every screenshot downloaded at 1600x1000 and viewed; vendor sites fetched as HTML and their images viewed. Videos (FolderPlus "ninety seconds" demo, SpacePeek captures, mesh-peek GIF) could not be inspected.

## Apps covered
| App | App Store ID / repo | Version seen | Screenshots inspected | Sources |
|---|---|---|---|---|
| Folder Preview (Anybox) | 6698876601 | 3.1.1, $1.99 | 6 | App Store listing |
| FolderPlus (Sreehari Sreekantan Nair / GnomeApps) | 6759026641 | 1.3.2, $1.99 | 7 + 5 site images | App Store; https://gnomeapps.com/folderplus |
| SpacePeek (府 王) | 6777129953 | 2.2.1, free + Pro $3.99 IAP | 7 + 3 site images | App Store; https://spacepeek.space/ |
| Loupe — Quick Look Preview (Eduard Bruch) | 6806599791 | 1.0, $3.99 on App Store | 3 | App Store; https://www.eduardbruch.com/loupe (no images) |
| Archive Quick Look (茹辉 黄) | 6760940658 | 1.2, $2.99 | 7 | App Store |
| Quick Preview: Folder Preview (国华 谢) | 6762034949 | 1.2.4, $2.99 | 6 | App Store |
| BetterZip Quick Look extension | docs page | BetterZip 6 | 1 site image + docs text | https://macitbetter.com/library/betterzip/docs/quick-look-extension/ , https://macitbetter.com/library/betterzip/docs/settings-extensions/ , https://macitbetter.com/ |
| Universal 3D Previewer (Bryan Joseph) | 6764180617 | 3.1, free | 1 | App Store; https://github.com/bj97301/universal-3d-previewer-app (listing text only) |
| StepPreview (Shanghai Adaila) | 6761538980 | 1.0.2, $4.99 | 2 | App Store; https://whimwild.com/steppreview (redirect only) |
| MakersPreview (Shanghai Adaila) | 6751494785 | 2.2.2, $4.99 | 5 | App Store; https://whimwild.com |
| Eyemesh (Jimmy De Bruyne / prest Apps) | 6759490053 | 1.5.1, free on App Store | 9 | App Store; https://www.prestapps.com/eyemesh/index.php |
| mesh-peek (Benjamin Doyle) | 6806482002 | 1.1, $2.99 | 4 + 2 site images | App Store; https://www.imjackofitall.com/projects/mesh-peek |
| Peek3D (All Things Yellow / Sander Versluys) | 6760981214 | 1.0.1, free | 3 | App Store; https://sanderversluys.com/ (no product page) |
| Apple macOS USDZ Quick Look | system | — | none | **Not inspected.** Only WWDC23 sessions surfaced (https://developer.apple.com/videos/play/wwdc2023/10274); no first-party screenshot of macOS camera controls found. Verify manually before copying any gesture model. |

Source mismatches worth knowing: Loupe's own page says "completely free" while the App Store lookup says $3.99; Eyemesh lists as free on the App Store while its site says $14.99 one-time with a 7-day trial (likely in-app purchase); Archive Quick Look's About screenshot shows 1.1 (5) while the listing is 1.2 (screenshots lag the build). Treat marketing as snapshots.

---

## Folder Preview (Anybox)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Grid of 26-item folder, light, path bar and status bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/9b/8f/61/9b8f6162-36b7-ac66-399e-6650b8a10feb/1.png/1600x1000bb.jpg |
| 2 | List, Icons folder pre-expanded | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d4/3f/c4/d43fc4b5-4ae1-703c-76dd-e126e3b28a52/2.png/1600x1000bb.jpg |
| 3 | Icons.zip list with "Uncompress" button | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/2d/29/1d/2d291d6b-d558-a156-e25d-495ba747061e/3.png/1600x1000bb.jpg |
| 4 | Right-click menu: Copy / Copy Path | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/70/09/77/700977b3-c8d1-14b0-1e2d-ed11a7683bd5/4.png/1600x1000bb.jpg |
| 5 | Column chooser menu (Date Modified/Created/Last Opened/Added, Size, Kind, Comments, Tags, Dimensions) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ac/7b/03/ac7b03dd-4f80-18a4-12e7-de2f4376ae61/6.png/1600x1000bb.jpg |
| 6 | Dark mode grid of PNG icons | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ec/41/22/ec412236-d8ca-e722-e7b8-39adacd9a2fa/5.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Preview anatomy 4/5.** Content on a white sheet; below it a two-row footer: breadcrumb path bar (home › Folder Preview › Icons, each with a small folder icon) then a status bar with a gear menu at left, centred total ("85.2 MB, 26 items"), an icon-size slider and a list/grid segmented control at right. The slider disappears in list view and the zip view. No top toolbar beyond Quick Look's title bar, where an archive adds a pill "Uncompress".
2. **Content presentation 4/5.** Grid tiles are ~135 pt cards with a light tinted plate behind each thumbnail, name in two centred lines, and a blue secondary line that changes by type: "11 items" for folders, "9.7 MB" for PDFs, "7,396 × 3,900" for images. List has Name / Date Modified / Size / Kind with Finder-like alternating row tint, tree disclosure triangles and folders summed in size ("7 MB"). Long names are middle-truncated ("Apple II Human Interface...lines.pdf") but a zip name wraps mid-word ("Instrument_Serif.zi / p").
3. **Interaction 4/5.** Column header right-click picks columns (menu includes Dimensions); item right-click offers Copy and Copy Path; list/grid toggle and size slider. No search or filter shown; keyboard use n/s.
4. **States & honesty 2/5.** Only the archive view shows empty zebra rows under the list. No limit, truncation, encrypted or error state shown.
5. **Companion n/s.** The description only says to enable the extension in System Settings.
6. **Visual identity 4/5.** Reads as stock Quick Look plus Finder idioms; dark mode shown. Marketing frame ("It should be built-in.") sells nativeness.
7. **Trust n/s** in UI.
8. **Delight/friction 3/5.** Copy Path is a small useful touch; one-line total in the footer is calm. Friction: no way to see a folder's own metadata (created date, permissions) beyond columns.
### Worth matching or beating
- Type-specific secondary line under each tile (item count, size or dimensions).
- Footer total as a single quiet centred string.
- Column chooser on the header, so the default stays minimal.
### Mistakes to avoid
- Mid-word filename wrapping in tiles.
- Showing an archive's emptiness as blank zebra rows with no summary.
- Leaving every limit unstated.

---

## FolderPlus (GnomeApps)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Dark list/tree, status strip with Items / Size (39 files, 11 folders) / Modified | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e3/54/44/e35444c8-fed8-1547-aeaf-3f8277e13de6/01-folders-quick-look.png/1600x1000bb.jpg |
| 2 | Gallery with size slider | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/10/22/90/102290b7-bffe-1e23-bc3c-be4a593800f0/02-gallery-view.png/1600x1000bb.jpg |
| 3 | ZIP with "Uncompress", status "Archive: 66 KB / Unpacked: 71 KB" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/f6/89/8f/f6898fc1-e412-ba42-8cd7-3f3fef7ac0fd/03-browse-archives.png/1600x1000bb.jpg |
| 4 | Same Finder column view beside QL window | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/46/ef/2c/46ef2c2a-7a43-6a37-88f3-51559459faea/04-no-extraction.png/1600x1000bb.jpg |
| 5 | "Password-protected" slide: identical zip list, no password UI | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/36/dc/10/36dc10ef-b0ea-7c71-b687-e0f912ebc47b/05-password-protected.png/1600x1000bb.jpg |
| 6 | "Finder-style" plain list | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/55/32/41/5532411c-84fa-dd9e-5697-7683d5c0cca5/06-finder-style.png/1600x1000bb.jpg |
| 7 | Built for macOS slide (same QL beside Finder) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a2/c5/0d/a2c50dd7-e5c4-3176-eb19-c9e9570044b0/07-built-for-macos.png/1600x1000bb.jpg |
| site | hero, folders, gallery, archives, password images | https://gnomeapps.com/assets/img/folderplus/hero-window.png (also folders.png, gallery.png, archives.png, password.jpg) |
### Observations by rubric dimension
1. **Preview anatomy 4/5.** Four stacked bands: native title bar, column table, a back/forward chevron + breadcrumb row (sreehari › Documents › Projects › GnomeApps › Graphics, with an app icon in one crumb), and a status strip made of icon-labelled facts separated by thin dividers: "Items: 10 | Size: 24.4 MB (39 files, 11 folders) | Modified: 1 Aug 2025". At right, a list/gallery segmented control and a copy-path icon.
2. **Content presentation 4/5.** Dark table with Title / Kind / Size / Date Modified, tree disclosure, folders marked "—" for size, vertical column dividers and full-height zebra filler beneath the data. Gallery uses wide 16:9 thumbnails with small centred labels and a slider with small/large image glyphs at its ends. Inconsistencies: Kind reads lowercase "pdf" and "folder" in one screen but "PDF document" in another; `.DS_Store` is listed with a blank kind; dates are dd/mm/yy.
3. **Interaction 3/5.** Back/forward within breadcrumbs, sort by any column, size slider; site claims side-pane file preview, auto-routing image-heavy folders to gallery, and four thumbnail sizes (S/M/L/XL). The "Dashboard" view named in the App Store text is **not shown in any screenshot**.
4. **States & honesty 2/5.** Archive status distinguishes "Archive: 66 KB" from "Unpacked: 71 KB", which is a good honest pair. The "Opens password-protected archives" slide shows no password prompt or lock state; the claim is copy only.
5. **Companion n/s.**
6. **Visual identity 3/5.** Slide frames use loud one-colour backgrounds and orange keyword highlights, unlike the quiet window inside. Quick Look window looks native.
7. **Trust 2/5.** "100% offline, sandboxed and read-only" is website and slide text only; no in-preview cue.
8. **Delight/friction 3/5.** Breadcrumb as a navigation control and a one-click copy-path icon are helpful. The stats strip packs four facts but uses small type.
### Worth matching or beating
- Archive vs Unpacked sizes in the status strip.
- Files/folders split in the total ("39 files, 11 folders").
- Copy-path as a persistent icon rather than a hidden context action.
### Mistakes to avoid
- Selling encryption support with a screenshot that shows none of it.
- Listing system junk (`.DS_Store`) with no hide control or count.
- Mixed-case "Kind" strings.

---

## SpacePeek
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Overview: total, file/folder chips, insight line, type-mix bar, largest items, donut | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/55/f3/51/55f35114-7ca7-d9d4-d402-ea865bd47f57/01-overview.png/1600x1000bb.jpg |
| 2 | Contents: tree list + rendered Markdown pane + pager | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/44/17/f5/4417f550-3af1-f021-d762-ffe5c38b0662/02-markdown.png/1600x1000bb.jpg |
| 3 | ZIP outline: Original Size / Compressed / Kind; footer pill | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/9d/06/6d/9d066d79-c127-114f-2068-6a6bd39e2b1b/03-archive.png/1600x1000bb.jpg |
| 4 | Search with Location column, "10 results for…" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/9f/3c/05/9f3c0523-9891-5630-f379-e4b64f86f461/04-search.png/1600x1000bb.jpg |
| 5 | Expanded image preview with File 3 of 30 pager | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/a0/fd/11/a0fd11a8-dc77-6458-7fcc-d477b1a59347/05-expanded-preview.png/1600x1000bb.jpg |
| 6 | Grid with breadcrumbs, 32 items · 32.3 MB | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/be/eb/2f/beeb2f1a-3a20-0f7b-a0a6-eb4c07d31acb/06-deep-browse.png/1600x1000bb.jpg |
| 7 | Source file list + highlighted Swift pane | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/b2/fe/30/b2fe3024-ef00-d1cc-2882-64b9c3e0a330/07-source-code.png/1600x1000bb.jpg |
| site | real captures: Overview (1.6M items in 4.55 s), video Contents with MP4 pane, Downloads overview | https://spacepeek.space/screenshots/v13-004.webp , v13-006.webp , v13-007.webp |
### Observations by rubric dimension
1. **Preview anatomy 5/5.** A floating rounded header card: folder icon, back chevron + breadcrumb, a centred **Overview | Contents** segmented control, a search icon, and a pill with a bolt icon: "44 items scanned in 63 ms". Footer is another floating pill: "5 items · 338.3 MB", list/grid toggle, sort menu. Selecting a file opens a right pane with Rendered/Source toggle, "…" menu, expand and close; an on-pane pager reads "Release Notes.md ‹ File 15 of 19 ›". Chrome is heavy (glass cards) but each element earns its place.
2. **Content presentation 4/5.** Overview: very large bold total (338.3 MB), two icon chips (39 Files, 5 Folders), a single plain-language insight ("Media uses 66% of this folder." / "1.08 GB in archives & disk images — worth reviewing…"), a segmented colour bar with percentage legend, "Largest items" rows with per-row proportion bar, size, percent and a drill chevron, and a segmented donut whose centre shows total or the hovered item. Contents: Finder-like thumbnails and a typed secondary line in the preview pane ("MPEG-4 movie", "773 MB · 0:42"). Weakness: breadcrumb text is tiny and clips on the left ("icePeek 2.2 Overview Demo"), and the Markdown heading runs under the floating toolbar ("SpacePeek 2.2 Release Not…").
3. **Interaction 5/5.** Tabs, inline search with Location and relative dates ("1 day ago"), grid/list, sort, preview pane, expand, previous/next across siblings, drill into subfolders keeping a breadcrumb. Archive entries preview without extraction. Keyboard shortcuts n/s.
4. **States & honesty 3/5.** The scan-time pill is an honest performance and completeness cue; search counts results by query. The 2.2.1 release notes admit a flicker where "the wrong compact layout" showed while a preview started. Free vs Pro gating is described ("deeper navigation") but the locked state UI is n/s.
5. **Companion n/s** (users are told to "open SpacePeek once and enable both Quick Look extensions").
6. **Visual identity 5/5.** Translucent, macOS 26-style materials tinted by the wallpaper; consistent across folder, archive and Markdown. Risk: wallpaper tint reduces text contrast on pale backgrounds.
7. **Trust 3/5.** Every marketing slide carries a "Local · Read-only · Stay in Finder" pill; the in-UI evidence is the scan pill and absence of destructive actions.
8. **Delight/friction 4/5.** Auto layout choice, "Reveal in Finder" and copy-from-archive sit behind Pro. The narrative insight sentence is the standout micro-copy.
### Worth matching or beating
- One-sentence insight plus single stacked bar instead of a chart-heavy dashboard.
- "N items scanned in X ms" pill; extend it to say "partial" when bounded.
- Pager that moves between sibling files without leaving Quick Look.
### Mistakes to avoid
- Floating overlays that cover content (heading and code lines run under toolbars).
- Tiny, left-clipped breadcrumb text.
- Paywalling basic drill-down; it reads as a limit rather than a feature.

---

## Loupe — Quick Look Preview (Eduard Bruch)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Feature cards over Bliss-style wallpaper (emoji icons for Folders, ZIP, RAR, 7z, TAR) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ec/19/28/ec1928cc-55fa-1824-891d-5bb5a8890f71/02_formats.png/1600x1000bb.jpg |
| 2 | Companion window plus System Settings path chips | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/26/36/41/263641ea-4404-bc16-466d-5c5df7b4dd9c/03_home_clean.png/1600x1000bb.jpg |
| 3 | A "Loupe — Quick Look" window listing seven folders | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/8e/fd/fe/8efdfe65-d5d7-d513-5daf-d45aa830fcf3/01_hf_hero_2.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 2/5.** Shot 3 shows only name, date and "Folder" columns plus "7 items" footer. The window titled "Loupe — Quick Look" with traffic lights is not Quick Look's real title bar, so it looks mocked up.
2. **Content 2/5.** Single-weight white rows on dark with low-contrast dates; no sizes shown even though the listing promises "names, sizes, and structure". Archive listing n/s.
3. **Interaction 1/5.** Nothing shown beyond "press Space".
4. **States 1/5.** None shown.
5. **Companion 3/5.** Small dark window, no sidebar: large magnifier icon, "Loupe", green dot "Active", format chips (Folders, ZIP, RAR, 7z, TAR), a tip card ("Select a folder or archive in Finder / Press Space to preview contents instantly"), buttons Settings, Open Finder, Setup, and a red **Quit Loupe**. Above it a chip trail: System Settings › Extensions › Quick Look › "Loupe — Enabled". Clear and short, but the "Active" label could be read as proof Finder uses it (our rule forbids that claim), and a red Quit button is the loudest element on the window.
6. **Identity 2/5.** Wallpaper and emoji clash with the app's own dark UI.
7. **Trust 2/5.** "No network entitlement" is in listing copy only. The App Store text says the interface is available in 40+ languages.
8. **Delight/friction 2/5.** Price conflict between site ("free") and store ($3.99) damages credibility.
### Worth matching or beating
- A visible 4-step trail naming the exact System Settings path.
- One tip card telling the user what to do next.
- A format-chip row doubling as status.
### Mistakes to avoid
- "Active" without saying what is verified.
- Destructive-coloured Quit as the primary visual.
- Conflicting price statements across store and site.

---

## Archive Quick Look
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Companion "About" with Setup/About segmented titlebar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/bc/d7/65/bcd7656d-2fa7-14b9-ee5a-eecaa560249c/about-view-light-theme.png/1600x1000bb.jpg |
| 2 | ZIP grid view, light, grouped by path | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/0a/56/99/0a569980-d271-de3c-dcc9-bf17d1bd54dc/quick-look-grid-view-on-quick-look-window-light-theme-archive.png/1600x1000bb.jpg |
| 3 | ZIP list view, "2 Levels" stepper | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/61/2b/ab/612babc3-c851-84d3-e06c-672658f22998/quick-look-list-view-on-quick-look-window-light-theme-archive.png/1600x1000bb.jpg |
| 4 | Finder column-view preview pane | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fa/64/73/fa6473da-ea2d-0fa6-b0a3-e7b697282f62/quick-look-list-view-on-finder-columns-view-panel-light-theme-archive.png/1600x1000bb.jpg |
| 5 | Folder list, light | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/59/81/b7/5981b75c-2d07-5e56-5d8b-ec763d852081/quick-look-list-view-on-quick-look-window-light-theme-folder.png/1600x1000bb.jpg |
| 6 | ZIP list, dark | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ea/78/1a/ea781a05-8be3-90d6-6bc7-bba650acb5d9/quick-look-list-view-on-quick-look-window-dark-theme-archive.png/1600x1000bb.jpg |
| 7 | Finder column pane grid, dark | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/f9/c4/fb/f9c4fb1e-7ed0-5b66-f4b8-339a14776b13/quick-look-grid-view-on-finder-columns-view-panel-dark-theme-archive.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 4/5.** Beneath the title bar sits a summary header: a 40 pt kind icon, bold name, "ZIP Archive  20 items  8.7 MB", a dimmer line "5 folders · 15 files | Modified Mar 22, 2026 at 14:55", and at right a "2 Levels" stepper and list/grid segmented control. The stepper is greyed in grid view, so the control state is honest.
2. **Content 4/5.** List: Name (sorted caret) / Size / Kind / Modified with folder outline icons, tight ~20 pt rows, blank zebra bands under the data. Grid: section headers show the archive path ("…Kit/02 Artwork Previews"), image thumbnails, PDF "2 pages", images "540 x 540" in blue. Folder list also shows `.DS_Store` as "Document".
3. **Interaction 4/5.** Depth stepper, list/grid, sorting. The Finder column-view pane uses a compact outline with two-line rows (name over kind · size · date) and a metadata block below, so it works in a narrow pane. The host "Open with The Unarchiver" button is Quick Look chrome.
4. **States 3/5.** Disabled stepper in grid; otherwise n/s. On-demand extraction of small previewable files is described but not shown, and the limit is n/s.
5. **Companion 2/5.** A two-segment titlebar "Setup | About"; only About shown (icon, "Version 1.1 (5)", "Native archive preview for Finder Quick Look.", a list of supported suffixes, Privacy Policy and Support links). Setup content n/s.
6. **Identity 4/5.** Plain native, supports light and dark.
7. **Trust 2/5.** Description says "Everything runs locally"; no in-UI cue.
8. **Delight/friction 3/5.** Depth control directly addresses "huge nested archive" friction.
### Worth matching or beating
- Summary header with counts split into folders and files.
- Depth stepper that disables itself where it does not apply.
- A compact two-line outline variant for narrow Finder column previews.
### Mistakes to avoid
- Treating Kind strings as opaque (.DS_Store shown as "Document").
- Showing only About in the marketing set, hiding the setup flow.
- Blank zebra rows with no empty-state text.

---

## Quick Preview: Folder Preview (国华 谢)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Grid with breadcrumb, footer "256.3 MB, 24 items" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/3a/87/7f/3a877f6b-1f7a-55b9-2d73-b28ce70e0cbd/screenshot-1.png/1600x1000bb.jpg |
| 2 | EPUB/MOBI two-page reader with progress slider | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/98/31/f5/9831f5c9-3301-be39-376d-cffd01cdebd9/screenshot-2.png/1600x1000bb.jpg |
| 3 | Markdown with outline sidebar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/6c/70/f4/6c70f405-9fe7-39bd-1c74-ff793a038c1c/screenshot-3.png/1600x1000bb.jpg |
| 4 | Zip grid, Chinese-localised chrome | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/6a/80/17/6a801730-052c-01d7-8948-faa14b09750d/screenshot-4.png/1600x1000bb.jpg |
| 5 | List view with tree | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/9e/18/b4/9e18b4b3-4088-f597-d51e-f12352986cc7/screenshot-5.png/1600x1000bb.jpg |
| 6 | Companion Home with 3 steps | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/e0/6f/23/e06f23d9-4a85-c402-eb1e-a54a2f1528d3/screenshot-6.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 4/5.** Same pattern as Folder Preview (breadcrumb bar, then footer with grid/list toggle, an ellipsis menu, centred total, slider). Markdown adds a collapsible outline sidebar; the ebook reader adds a sidebar toggle, page arrows at the edges and "71 / 285" under a scrub bar.
2. **Content 4/5.** Grid shows true swatches/thumbnails with tiny dimension captions; list has Name / Modified Date / Size / Kind with "--" for folders; Markdown is typeset with tables and bordered header row.
3. **Interaction 4/5.** Grid/list, slider, outline nav, page turning; release notes say windows "can now be freely resized".
4. **States 2/5.** Preferences list "archive size limit" and "scan depth" (App Store text) but the UI and the over-limit wording are n/s.
5. **Companion 4/5.** Rounded window with a sidebar of four items, each with a coloured rounded-square symbol: Home, Settings, Preview, About (very close to our sidebar idea). Home shows "Start here": numbered cards "1 Enable Quick Look — Find Quick Preview in the Extensions section…", "2 Preview in Finder", "3 Refresh if needed — If it does not work right away, reopen Finder or launch Quick Preview again", then a "Preview Extensions" section with a "Manage Extensions" link to System Settings.
6. **Identity 4/5.** Bright blue wallpaper slides, laurel awards; windows look current.
7. **Trust 2/5.** n/s in UI.
8. **Delight/friction 3/5.** The three-step card gives a "refresh" fallback. Friction: screenshots mix English content with Chinese chrome ("目录", "通过 Xcode 打开", "解压缩") and a Chinese path ("下载"), which looks unfinished in a store set aimed at US buyers.
### Worth matching or beating
- Numbered start-here cards ending with a recovery step.
- "Manage Extensions" link next to its explanation.
- Per-type preferences expressed as limits (depth, archive size).
### Mistakes to avoid
- Mixed-language screenshot sets.
- "Reopen Finder" advice as the first recovery (our rule: never reset Finder merely to hide a routing defect).
- Bundling ebook and Markdown readers into the folder brand so the identity blurs.

---

## BetterZip Quick Look extension
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Quick Look of Vacation Photos.zip with status line and Show hidden items | https://macitbetter.com/img/screenshots/QL@2x.png |
| 2 | Password dialog inside the main app (not the extension) | https://macitbetter.com/img/screenshots/protected@2x.png |
| docs | Text only | https://macitbetter.com/library/betterzip/docs/quick-look-extension/ and /settings-extensions/ |
### Observations by rubric dimension
1. **Anatomy 4/5.** Beneath the title bar: one status line "17 items, uncompressed size: 13.4 MB (incl. 7 hidden)", a "Show hidden items" checkbox and an info (i) button at right, then a sortable outline. The extension is free; BetterZip's host "Open with BetterZip" button sits top right.
2. **Content 3/5.** Large 14-15 pt rows, folder sizes summed, date shown as "Today, 09:45". Dates sit slightly above the name baseline, a small misalignment visible in the screenshot. Docs list seven selectable columns: Name, Date Modified, Size, Packed, Ratio, Kind, Attributes.
3. **Interaction 3/5.** Click column to sort, click again to reverse; checkbox toggles dot-files and AppleDouble entries.
4. **States 5/5 (docs).** The best limit disclosure in the cluster, all in text: header-encrypted archives cannot be previewed "as the extension cannot prompt for a password"; not-yet-downloaded iCloud archives are skipped by default (switchable); tar archives above a megabyte ceiling show only header info; Dropbox/OneDrive/Google Drive restrictions are acknowledged. How these states look on screen is n/s.
5. **Companion 3/5 (docs).** Settings live in the main app's Extensions tab because "Apple removed the option to save settings inside Quick Look extensions"; checkboxes for columns, packages-as-folders, hidden files, tar cutoff. The UI itself is n/s.
6. **Identity 3/5.** Standard AppKit table.
7. **Trust 3/5.** "Free for everyone, no license needed" and the explicit refusal to trigger a cloud download.
8. **Delight/friction 3/5.** "incl. 7 hidden" is a rare honest count of what the view omits.
### Worth matching or beating
- Count what is hidden ("incl. 7 hidden") next to the toggle that reveals it.
- Explicit statements for encrypted, cloud-only and oversized cases.
- Explain why settings live in the companion.
### Mistakes to avoid
- Leaving these states as docs-only rather than designed on-screen states.
- Date baseline misalignment in dense rows.
- Hiding the tar cutoff in a settings tab with no in-preview notice (not observed on screen).

---

## Universal 3D Previewer
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | 3DBenchy.stl in Quick Look on near-black desktop | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/71/36/e1/7136e103-f63f-06e8-f613-7ea63d4da3db/app-store-hero.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 1/5.** Only the host title bar with "Open with Universal 3D Previewer"; no overlay controls, grid, axes or readout.
2. **Content 2/5.** Flat light-grey single material on a black background; model centred at roughly 60% of the height.
3. **Interaction 1/5.** n/s; no hints.
4. **States 1/5.** n/s.
5. **Companion n/s.** "Lightweight standalone viewer" mentioned, not shown.
6. **Identity 2/5.** Default Quick Look chrome.
7. **Trust 1/5.** n/s (the repo is a listing page, not source).
8. **Delight/friction 1/5.** Claims STEP and SolidWorks coverage in text, but the only evidence is an STL.
### Worth matching or beating
- None observed beyond the existence of the STEP promise.
### Mistakes to avoid
- Promoting STEP with an STL screenshot.
- Zero affordance for how to move the camera.
- Dark-on-dark backdrop that gives the model no ground reference.

---

## StepPreview (Shanghai Adaila)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Finder icon view of STEP thumbnails with a PCB.step Quick Look window | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/1e/c8/91/1ec89179-c607-1e6a-eb69-c8d60a027725/Screenshot_2026-04-02_at_18.39.50.png/1600x1000bb.jpg |
| 2 | Standalone viewer: asm.stp wireframe overlay with bottom toolbar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/a8/72/0b/a8720b3d-c8f2-3309-6264-1846bef7d050/Screenshot_2026-04-02_at_19.21.42.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 3/5.** Quick Look: bare viewport, host "Open with StepPreview". Viewer: transparent title bar and a floating bottom pill with eleven items: fit-to-view, two toggles shown in blue, a floor/light icon, then axis buttons -Y +Y +Z -Z -X +X. Icons are unlabelled in the screenshot (meaning of the two blue toggles is a guess; likely projection/grid and shading).
2. **Content 3/5.** Quick Look model keeps real colours (blue PCB with orange pins) on a pale blue gradient, filling and cropping the window. The viewer shows an assembly with white edge lines drawn over grey faces; at that density the lines hide the form.
3. **Interaction 3/5.** The six axis buttons give one-tap orthographic views, which is a strong CAD convention. Orbit/pan/zoom hints n/s.
4. **States 1/5.** n/s.
5. **Companion n/s.**
6. **Identity 3/5.** Frosted gradient plus white thumbnail cards; thumbnails keep model colours.
7. **Trust 1/5.** n/s.
8. **Delight/friction 2/5.** Window title and traffic lights sit on top of the model, hard to read. Screenshot 2 shows no sign of units, bounding box, part tree or assembly structure.
### Worth matching or beating
- Six axis-view buttons in one row.
- Thumbnails that keep the model's own colours, on neutral cards.
- Fit-to-view as the first control.
### Mistakes to avoid
- Unlabelled icon toggles.
- Cropped, over-zoomed first view.
- Edge overlay that overwhelms assemblies.

---

## MakersPreview (Shanghai Adaila)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Cover: Finder thumbnails and a 3MF Quick Look; colour-coded format pills | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/1b/0c/ab/1b0cabd9-9a4e-bc8a-9e92-983be0d3fc21/cover.jpg/1600x1000bb.jpg |
| 2 | 3MF styles: thumbnail Embedded image vs Rendered preview; Quick Look Card vs 3D model | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/9c/13/df/9c13dfd4-49b7-70ed-d917-1a16d40628d1/styles.jpg/1600x1000bb.jpg |
| 3 | GLB robot Quick Look and thumbnails | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/36/8d/fe/368dfebd-ed11-e52c-4a5a-f75c4d77182e/glb.jpg/1600x1000bb.jpg |
| 4 | Laser cutting: LAC card with photo and vector outline; XCS panel grid | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/26/a5/3d/26a53d95-5d65-f74d-9dbb-4c50ec0f7381/lasercut.jpg/1600x1000bb.jpg |
| 5 | Viewer windows with bottom toolbar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ad/e9/57/ade957d0-a611-1120-16d6-7e770a817c6c/viewer.jpg/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 4/5.** Two Quick Look layouts are offered: a pure 3D model, or a **card** with a hero photo ("Open in MakerWorld" button on the image), a metadata tile ("0.2mm layer, 2 walls, 15% infill", filament name, plate count, filament chips "PLA" in the filament colours) and a "Plate 1 / Plate 2" render column. The viewer repeats the StepPreview pill (fit, grid, floor, -Y…+X, plus an extra icon at right).
2. **Content 4/5.** Warm peach gradient background with soft-shaded, coloured models; vector laser files drawn in coloured outlines on white cards (blue for LAC, red for XCS).
3. **Interaction 3/5.** The style choice for thumbnail and preview is a user preference; camera hints n/s.
4. **States 2/5.** Printables support "requires the optional browser extension" (limitation stated in text only). Missing plate or parse errors n/s.
5. **Companion n/s** (style options implied by screenshot 2; the settings window itself is not shown).
6. **Identity 4/5.** Consistent pastel palette; format categories colour-coded (blue 3D print, green 3D assets, orange laser).
7. **Trust 1/5.** n/s.
8. **Delight/friction 4/5.** Plates shown separately and filament chips are information a maker needs at a glance.
### Worth matching or beating
- A card layout for files that carry rich metadata, with a one-tap switch to 3D.
- Letting users choose the thumbnail style (embedded image vs render).
- Colour chips for material/part facts.
### Mistakes to avoid
- Putting a third-party store button over embedded imagery.
- Unlabelled toolbar glyphs.
- Hiding the style choice in a screenshot rather than a visible control.

---

## Eyemesh (prest Apps)
Note: nearly all screenshots show the **standalone app**; the Quick Look preview is claimed ("Native QuickLook & Finder thumbnails") but never pictured.
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Library with a fox, rotation gizmo rings, Metadata inspector | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/fa/fc/a6/fafca613-a30f-4c57-8095-5ef6a60e8559/5.png/1600x1000bb.jpg |
| 2 | Folder tree, thumbnail grid, soda can, axis gizmo | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/77/b2/d7/77b2d76a-04f8-464b-2c78-4e1bdba7c2a8/8.png/1600x1000bb.jpg |
| 3 | Export sheet | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c8/f5/0b/c8f50b79-0185-7e6b-46bc-33cbfd1a78b2/3.png/1600x1000bb.jpg |
| 4 | Add to Favorites dialog and empty state "Select a file" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/14/63/65/146365cc-1398-07e9-8bd4-596481a788e8/7.png/1600x1000bb.jpg |
| 5 | Cross-section tool (French UI) with X/Y/Z, slider, flip | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fc/79/e3/fc79e384-0a77-63c1-30f5-a8c2f91d1867/2.png/1600x1000bb.jpg |
| 6 | Texture management remap dialog | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ad/2d/12/ad2d12d5-ea53-ab3f-1ab5-bff77e6da3fd/6.png/1600x1000bb.jpg |
| 7 | Info inspector: Geometry, Dimensions, Skeleton; animation bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/7d/05/60/7d0560ed-9d0b-7274-caf7-22075a3cc10c/4.png/1600x1000bb.jpg |
| 8 | Render-mode menu: Textured, Untextured, Wireframe, MatCap | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/3b/d5/01/3bd501f9-ff49-da92-8247-7a4aa0ed52c1/9.png/1600x1000bb.jpg |
| 9 | Side-by-side compare with floor grid and linked cameras | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/90/50/69/9050692d-4d8f-1959-af0f-1d1c4d722446/1.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 5/5 (app).** Viewport chrome: top-right row of nine round, saturated buttons (blue Home/reset camera; a black ring; green render mode; yellow lighting; grey scissors for cross-section, turning red when active; grey grid toggle; then yellow star, purple share, orange info). Bottom-left vertical zoom stack (fit arrows, +, slider, −); bottom-right XYZ axis gizmo (Y green, X red, Z blue); file name chip top-left with an orange refresh badge (a red warning badge appears on error). Cross-section opens a bottom bar with X | Y | Z, slider and a flip button. Animation bar: play, scrubber "0.0 … 20.4", x½ / x1 / x2.
2. **Content 4/5.** Black viewport by default; a second look in compare mode shows a dark vignette backdrop with a perspective floor grid whose red and blue axis lines meet at the origin. Wireframe is neon green; skeleton is yellow lines over the mesh.
3. **Interaction 5/5.** Menu with checkmark for render modes (MatCap has seven presets per the site), rotation gizmo rings, keyboard panning, remembered camera, linked cameras in compare, bone tree with disclosure and "Show bones" switch.
4. **States 3/5.** Empty viewport reads "Select a file — Click a thumbnail to preview the 3D model"; red warning badge for load error; export queue shows "Pending 0/4"; texture remap dialog for missing textures. Unit labels are missing: Dimensions list "Width (X) 0.526, Height (Y) 1.699, Depth (Z) 0.432, Center (-0.1, 0.8, -0.1)" with no unit.
5. **Companion 4/5.** Three-pane library: folder tree, thumbnail grid with star ratings and tags, inspector with Metadata and Info tabs; localised (French screenshot). It is a full viewer/library, outside our one-window scope.
6. **Identity 3/5.** Dark, dense, and the rainbow of saturated circular buttons departs from macOS idiom.
7. **Trust 2/5.** n/s in UI.
8. **Delight/friction 4/5.** Compare mode, turntable export. Friction: nine same-shaped coloured buttons with no labels visible.
### Worth matching or beating
- Geometry block: meshes, vertices, triangles, plus bounding box in a collapsible group.
- Render-mode menu with a check, a short, named list.
- XYZ axis gizmo bottom-right.
### Mistakes to avoid
- Dimensions without units.
- A bright, multi-hue icon row on a dark canvas.
- Marketing a Quick Look feature without picturing it.

---

## mesh-peek (Benjamin Doyle)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | SCAD in the app with Customiser panel, parts list, view cube | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/e7/0e/03/e70e0380-992f-3b69-02bc-c0ffd08ac99a/screenshot-1.png/1600x1000bb.jpg |
| 2 | Finder icon view with thumbnails | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/86/b8/68/86b8686a-9ab2-e18e-765a-82d960302a17/screenshot-2.png/1600x1000bb.jpg |
| 3 | Quick Look of acid_smiley.3mf | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c6/4a/f8/c64af87f-d4f8-9848-2334-40ccfffeb596/screenshot-3.png/1600x1000bb.jpg |
| 4 | App window: 3MF with All / Part 1 / Part 2 / Part 3 picker | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/07/37/97/07379717-8348-0a00-8535-4727e7c764b4/screenshot-4.png/1600x1000bb.jpg |
| site | Finder list view with small thumbnails; large Quick Look | https://www.imjackofitall.com/mesh-peek-thumbnails.png , https://www.imjackofitall.com/mesh-peek-quick-look.png |
### Observations by rubric dimension
1. **Anatomy 3/5.** Quick Look: title, host "Open with mesh-peek", a **view cube** (≈50 pt, top-right) labelled Bottom/Left/Right, and the creator's handle "@imjackofitall" as a small watermark bottom-right inside the viewport. In the app: a left vertical chip list of build parts and a Customiser panel; Quick Look keeps only the cube.
2. **Content 4/5.** Charcoal canvas with a faint **dot grid**, soft grey shading, colours kept when the file has them; the dots give scale and floor cues without lines. Thumbnails reuse the same dot-grid card so Finder and Quick Look match.
3. **Interaction 2/5.** Cube suggests click-to-face; no stated hints. The release notes add a plate picker "sidebar" and say plate switching is instant.
4. **States 2/5.** SCAD "open in the app, but don't preview from Finder" (site text), a limitation stated honestly.
5. **Companion n/s** beyond the standalone window.
6. **Identity 4/5.** Distinct, restrained and consistent across thumbnail, preview and app.
7. **Trust 1/5.** "No analytics, no subscription" is store copy.
8. **Delight/friction 3/5.** Dot-grid and small cube are charming; the baked-in watermark is a branding cost.
### Worth matching or beating
- View cube as the single, small camera control.
- Dot-grid ground that doubles as a scale cue and thumbnail background.
- Plate/part chips for multi-part files.
### Mistakes to avoid
- Watermarks inside the content.
- A cube with tiny, low-contrast face labels.
- Parametric customiser controls in a read-only previewer (out of scope for us).

---

## Peek3D (All Things Yellow)
### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Multi-object 3MF cropped by the window | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/2a/46/13/2a46139a-2c86-91c1-45d0-2abb1ea19d95/Screenshot_2026-03-23_at_10.06.53.png/1600x1000bb.jpg |
| 2 | cat.3mf, plain | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/16/f7/31/16f7314f-d8b3-fb36-7452-4e631c60a73e/Screenshot_2026-03-23_at_10.04.57.png/1600x1000bb.jpg |
| 3 | STL, "Open with Xcode" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/7b/a3/99/7ba399b9-e4e0-fcf8-8e92-dc80640dcdd7/Screenshot_2026-03-23_at_10.07.13.png/1600x1000bb.jpg |
### Observations by rubric dimension
1. **Anatomy 2/5.** Pure viewport. Note the host button changes by what macOS considers the default app ("Open with BambuStudio", "Open with Xcode"): it is not the app's choice.
2. **Content 3/5.** Matte pale-grey mesh on charcoal; no floor or axes. The first screenshot is too close; objects clip at the top and sides.
3. **Interaction 2/5.** "Interactive 3D preview" per text; no on-screen hints.
4. **States 3/5.** Release notes document a real failure ("previews could fail to appear on Macs with slicer apps … installed"), a cold-start behaviour ("large models now show their embedded thumbnail instantly, with the interactive 3D view loading right after") and robustness for very large 3MF.
5. **Companion n/s,** but notes say it "checks whether its Quick Look extension is enabled and helps you activate it".
6. **Identity 3/5.** Plain.
7. **Trust 1/5.** n/s.
8. **Delight/friction 2/5.** The thumbnail-first-then-3D hand-off is a good perceived-speed pattern.
### Worth matching or beating
- Show a thumbnail instantly, swap to interactive when ready.
- An extension-enabled check in the companion.
- Honest release-note admission of provider conflicts.
### Mistakes to avoid
- First framing that crops the model.
- No ground or axis reference.
- Zero hints for interaction.

---

## Cluster synthesis

### Patterns most apps share (table stakes)
- Folder and archive listings use one layout (Name, Date, Size, Kind) with tree disclosure and a list/grid toggle; the archive version only adds a title-bar "Uncompress" or "Open with" button (host-provided).
- A footer with item count plus total size; five of six folder apps also show a breadcrumb path bar.
- Light and dark appearances both shown; native Quick Look window with no custom title bar.
- 3D: a neutral grey, single-material model on a dark or gradient background, centred, with real orbit interaction and no persistent hint.
- Marketing claims of "offline / read-only / private" are everywhere, but none appears inside a preview.

### Patterns only one or two apps have (users would notice)
- SpacePeek: Overview tab with insight sentence, stacked type bar, largest-items bars, donut; sibling pager; scan-time pill.
- Archive Quick Look: summary header with folders/files split, depth stepper (disabled when irrelevant), grid grouped by archive path.
- Folder Preview: per-column chooser including Dimensions; FolderPlus: "Archive vs Unpacked" strip; BetterZip: "incl. 7 hidden".
- MakersPreview: metadata card with filament chips and per-plate renders, user-selectable thumbnail style.
- Eyemesh: render-mode menu, section tool, XYZ gizmo, geometry/dimension inspector, compare; StepPreview/MakersPreview: six axis-view buttons; mesh-peek: view cube and dot-grid ground, parts chips.
- Peek3D: thumbnail first, interactive second.

### Where every app in this cluster is weak (our opening)
- **Limits are never shown on screen.** No screenshot shows a truncated listing, "showing first N", oversize or depth cut-offs; only BetterZip's docs state limits (header-encrypted, cloud-only, large tar).
- **Encrypted archives:** FolderPlus claims support with no UI; BetterZip says "cannot prompt"; no app shows a lock/encrypted row state.
- **CAD scale:** no Quick Look preview shows units, a bounding box, part count or assembly structure; Eyemesh shows dimensions without units, and only in its app.
- **No camera hints:** no 3D Quick Look pictures how to orbit, pan, zoom or reset.
- **No privacy cues in UI** (secret masking is not a concept here), and no accessibility affordances or keyboard shortcut discoverability visible.
- **Provider conflicts and enabling:** only Peek3D (release notes) and Quick Preview (3-step card) address it; none diagnoses.
- Stable, honest status wording is rare ("Active", "Enabled" claims without scope).

### Scorecard (1–5; "–" = not shown)
| App | 1 Anatomy | 2 Content | 3 Interaction | 4 States | 5 Companion | 6 Identity | 7 Trust | 8 Delight |
|---|---|---|---|---|---|---|---|---|
| Folder Preview | 4 | 4 | 4 | 2 | – | 4 | 1 | 3 |
| FolderPlus | 4 | 4 | 3 | 2 | – | 3 | 2 | 3 |
| SpacePeek | 5 | 4 | 5 | 3 | – | 5 | 2 | 4 |
| Loupe | 2 | 2 | 1 | 1 | 3 | 2 | 2 | 2 |
| Archive Quick Look | 4 | 4 | 4 | 3 | 2 | 4 | 2 | 3 |
| Quick Preview | 4 | 4 | 4 | 2 | 4 | 4 | 2 | 3 |
| BetterZip QL (docs + 1 image) | 4 | 3 | 3 | 5 | 3 | 3 | 3 | 3 |
| Universal 3D Previewer | 1 | 2 | 1 | 1 | – | 2 | 1 | 1 |
| StepPreview | 3 | 3 | 3 | 1 | – | 3 | 1 | 2 |
| MakersPreview | 4 | 4 | 3 | 2 | – | 4 | 1 | 4 |
| Eyemesh (app, not QL) | 5 | 4 | 5 | 3 | 4 | 3 | 2 | 4 |
| mesh-peek | 3 | 4 | 2 | 2 | – | 4 | 1 | 3 |
| Peek3D | 2 | 3 | 2 | 3 | – | 3 | 1 | 2 |

### Ten ranked recommendations for SpacePane
1. **Designed "limits" strip for folders and archives.** One quiet line in the footer: counts, total, and when bounded, "Showing first 5,000 of 12,431 entries" with a localized reason; add a "hidden items (7)" count next to its toggle and hide system junk by default. Why: nobody shows limits on screen; BetterZip's "incl. 7 hidden" and FolderPlus's file/folder split are the closest. Rules: honest status wording; bounded/cancellable; 14 languages with plurals. Cost S.
2. **Encrypted and unreadable states as first-class rows/banners.** A lock glyph and one sentence ("Contents are encrypted. Quick Look cannot ask for a password.") for header-encrypted archives; per-entry lock badge for entry-level encryption; no password field in the preview. Why: FolderPlus claims prompts with no UI; BetterZip documents the limit only in text. Rules: read-only, local, no secrets handling; state what we cannot do. Cost M.
3. **A small, native 3D control cluster.** Bottom-centre floating pill with Reset/Fit, Shaded/Wireframe/Edges, and -X/+X/-Y/+Y/-Z/+Z views (tooltips and accessibility labels on every icon), plus an XYZ gizmo bottom-right. Why: StepPreview/MakersPreview pills (unlabelled), Eyemesh render menu and gizmo, mesh-peek cube. Rules: native Metal/AppKit, lazy Metal creation, localized labels, keyboard access. Cost M.
4. **CAD size readout with honest units.** Corner chip "120.5 × 40.0 × 18.2 mm" from the file's unit declaration, or "unit not declared" with the raw values, plus part/body count. Why: no previewer shows units in Quick Look; Eyemesh shows bare numbers. Rules: never guess units; bounded helper; localized number formatting. Cost M.
5. **Camera hint that teaches once.** A fading single line on first interaction ("Drag to orbit · Scroll to zoom · Double-click to fit") that does not return after use. Why: no 3D previewer shows any hint. Rules: verify against Quick Look's actual event handling first; Apple's own USDZ gestures were not inspected here. Cost S.
6. **Thumbnail-first, render-second for 3D.** Show the Finder-resolution render at once and swap to the interactive scene when the helper is ready, with a thin progress hint. Why: Peek3D release notes. Rules: keep sensitive content out of thumbnails (decide whether CAD geometry qualifies); cancellable; counts helper memory. Cost M.
7. **Content-true 3D thumbnails.** Three-quarter isometric render on a neutral card, model colours kept, a dot grid or soft floor for scale. Why: StepPreview, MakersPreview and mesh-peek thumbnails are the standout feature versus generic icons. Rules: no sensitive content in thumbnails, durable caches avoided; opt-in per type already exists. Cost M-L.
8. **Compact summary header for folders and archives.** Kind icon, name, "ZIP archive · 20 items · 8.7 MB", dim "5 folders · 15 files · modified …", plus Archive-vs-Unpacked sizes and a depth stepper that disables itself in grid. Optional "type mix" stacked bar and a single insight sentence, not a donut dashboard. Why: Archive Quick Look header, FolderPlus strip, SpacePeek insight line. Rules: bounded scan; localized plurals; no floating overlays covering content. Cost M.
9. **Companion setup trail with scoped wording.** A numbered start card (Enable in System Settings → Extensions → Quick Look; Select a file; Press Space) with a direct "Open System Settings" button, status text such as "Saved here; macOS chooses the preview provider". Why: Quick Preview's three steps and Loupe's path chips; Loupe's "Active" risks over-claiming. Rules: never claim Finder uses this provider; do not advise restarting Finder first; one window. Cost S.
10. **Filename and localization QA for dense lists.** Middle-truncate with the extension intact, tooltip with the full name, never wrap mid-word; verify 14 languages with long and RTL names; keep screenshots single-language. Why: Folder Preview's "zi/p" wrap, SpacePeek's clipped breadcrumb, Quick Preview's mixed-language store set. Rules: all strings localized; Unicode and RTL; accessible text selection. Cost S.

Gaps to close before relying on this research: no first-party evidence for Apple's macOS USDZ Quick Look camera model; no screenshot of any Quick Look preview for Eyemesh; FolderPlus Dashboard and password prompt not pictured; Loupe's archive listing not pictured; every companion window other than Loupe, Quick Preview and Archive Quick Look is unseen.
