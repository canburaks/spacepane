# Closest general-purpose rivals — UX/UI observations
Researched 2026-10-06. Sources are vendor marketing (App Store, websites, repositories); nothing was installed or tested. Every statement below is **observed in marketing material** unless it says otherwise. "Not shown" means no screenshot or page text covered it.

## Apps covered
| App | App Store ID / repo | Version seen | Screenshots inspected | Sources |
|---|---|---|---|---|
| QuickLook Pro (Mucahit Tutuncu, $3.99, macOS 15+) | id6812534537 | 1.1 (2026-09-22) | 3 App Store frames, 1 Open Graph image, site icon; the live site's HTML was read as text (its interactive demo was not rendered) | [App Store lookup](https://itunes.apple.com/lookup?id=6812534537&entity=macSoftware&country=us), [site](https://quicklookpro.com/), [support](https://quicklookpro.com/support/) |
| QuickestLook (Helaia / Oliver Herbelin, free + optional tips, macOS 26+) | id6765485652 | 1.0 (2026-05-01) | 7 App Store frames; the site has no screenshots | [App Store lookup](https://itunes.apple.com/lookup?id=6765485652&entity=macSoftware&country=us), [site, troubleshooting and privacy](https://helaia.com/tools/quickestlook/), [status page](https://helaia.com/quickestlook/status/) |
| Super Quick Look (Lumik LLC, $3.99, macOS 12+) | id6783296336 | 1.0.3 (2026-09-15); screenshots show app build 0.1.5 | 6 App Store frames; no vendor site exists (seller URL empty, web search found nothing) | [App Store lookup](https://itunes.apple.com/lookup?id=6783296336&entity=macSoftware&country=us) |
| Simple Quick Look (wxio / 俊全 颜, free, macOS 11+) | id6762875743 | 1.0 (2026-04-26) | 5 App Store frames; vendor site [wxio.net](https://www.wxio.net) answered with a Cloudflare challenge and could not be inspected | [App Store lookup](https://itunes.apple.com/lookup?id=6762875743&entity=macSoftware&country=us) |

Every listing is English-only (`languageCodesISO2A` is EN for the three I checked). A note on the shared frame: the Quick Look window's top strip (close button, a no-entry glyph, share icon, "Open with <app>" button) is Apple's host chrome. Competitors do not draw it. Their own UI starts below it.

---

## QuickLook Pro
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Markdown README in a Quick Look window beside a Finder list: header card, `Preview | Raw` segmented control, rendered content | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ec/94/30/ec94301e-1b33-2b3d-ec33-adfc582b85f1/02-markdown.png/1600x1000bb.jpg |
| 2 | ZIP archive as an expandable Name/Size/Kind table, footer "7 files · 4 folders" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/de/2a/8e/de2a8e37-2dc8-4302-dfbb-9beeebe01435/01-zip.png/1600x1000bb.jpg |
| 3 | Swift source with line-number gutter, `Source` label and a `Wrap` toggle chip | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/11/7d/85/117d853d-c0a8-1606-b9dd-331bf85207c0/03-code.png/1600x1000bb.jpg |
| 4 | Site Open Graph image: ZIP preview over a Finder list on a plum background | https://quicklookpro.com/assets/social/og-home-v2.jpg |
| 5 | Site asset: plain generic document icon (used in the site's Finder demo) | https://quicklookpro.com/assets/file-zip.png |
| text | Site HTML only: a scripted "Interactive Finder demo" with a Finder-like sidebar (Recents, Favorites, Locations, Tags), a list view and an eye/Quick Look button titled "Quick Look (Space)". Hint text: "Select a file, then press space". Not rendered, so the look is unverified. | https://quicklookpro.com/ |

All three store frames carry the same furniture: a large headline and subline, a "Select a file in Finder → [Space]" key-cap hint, and the footer "Your files stay on your Mac." with a "01 / 03" counter.

### Observations by rubric dimension
1. **Preview anatomy — 4/5.**
   - Below Apple's title bar sits a header card. It has a 16 pt document, archive or `</>` glyph, the file name in semibold, and a small grey metadata line. Examples: "416 bytes · Markdown document · 68 words", "2 KB · 7 files · 528 bytes expanded", "619 bytes · UTF-8 · 23 lines". On the right is an outlined small-caps type pill (MARKDOWN, ZIP ARCHIVE, CODE).
   - Under the card is a slim mode bar. Markdown shows a two-segment control, `Preview` (selected, filled orange-red) and `Raw`. Code shows a "Source" label with a column icon on the left and an orange `Wrap` chip on the right. The ZIP shows a folder icon and "Contents".
   - Chrome is about three rows (title, card, mode bar) of roughly 120 pt in a roughly 480 pt window, so the content gets about three quarters. Controls are top-only.
   - The accent is a fixed orange-red, not the system accent colour (the Finder selection beside it is blue).
2. **Content presentation — 4/5.**
   - Code uses a monospace face of about 12 pt with generous line height (about 21 px between lines at 1600 px frame width). The gutter is a dimmed, right-aligned number column separated by a hairline rule. Syntax colours are muted: brown keywords, green strings. It looks restrained and editor-like.
   - The Markdown preview uses system-sans headings, bold in lists, grey inline code and no table of contents.
   - The ZIP view is a disclosure tree with folder icons, per-file-type icons, right-aligned sizes and a Kind column. Rows are zebra-striped, and the stripes continue as empty grey bars below the last entry. That fills the window but reads as unfinished.
3. **Interaction & discoverability — 3/5.**
   - Preview/Raw is a visible segmented control. Wrap is a visible chip. Disclosure chevrons are shown.
   - No search, copy action, zoom or shortcut hint appears inside the preview. The release notes mention "Faster Tree/Raw switching", so JSON also has a Tree/Raw mode, but no JSON screenshot exists.
4. **States & honesty — 3/5.**
   - The support page says "A partial preview is labeled" and that large files and deeply nested archives have "size, row, and time limits". No screenshot shows the label, so its look is not shown.
   - The page explains the routing limit in plain words: "macOS chooses which extension handles each file type. Another installed app or a built-in preview may take priority". It gives the CSV exception by name, and the App Store text repeats it ("standard CSV files currently use Apple's built-in preview").
   - Contradiction: the store text lists ZIP64 and XIP as supported, but the support page lists "ZIP64" among unsupported formats. Unverified which is current.
5. **Companion / settings app — 2/5.**
   - No companion screenshot exists. Only text: "The setup window shows whether the preview and thumbnail extensions are installed", and it "also has an Open System Settings button". The setup app "can quit while previews continue to work". No per-type switches, themes or conflict tools are mentioned.
6. **Visual identity & native feel — 3/5.**
   - The icon is a blue rounded square with a folder. Beyond it the site and frames are polished (large tight-tracked headlines, plum hero). The preview itself looks native: system fonts, light mode only. Dark mode is not shown.
   - The custom orange-red controls stand out from system blue.
7. **Trust & privacy communication — 2/5.**
   - "Your files stay on your Mac." and "Works offline" appear only in marketing frames. The preview has no in-UI statement. The `.env` secrets-hidden behaviour (store text) has no screenshot, so how it is signalled is not shown.
8. **Delight and friction — 3/5.**
   - Delight: the website's try-it-with-Space Finder demo is a clever proof of the product. The key-cap "Space" hint in every frame is memorable.
   - Friction: the empty zebra rows, the contradictory ZIP64 claim, and an Apple-silicon-only requirement stated only on the support page.

### Worth matching or beating
- One consistent header card (glyph, name, metadata line, type pill) plus a slim mode bar for every format. It makes unlike formats feel like one product.
- A metadata line that is informative per type (encoding and line count for code, expanded size and file count for archives) rather than a generic size.
- A footer count line on lists ("7 files · 4 folders").

### Mistakes to avoid
- Decorative empty zebra rows below short content.
- A non-system accent colour for controls in a Quick Look window.
- Claiming a format in the store text that the support page disclaims.

---

## QuickestLook
### Screenshot inventory
(The image file names on Apple's CDN do not match the content. Descriptions below are of what the pixels show. Frames 1–2 are mock laptops showing the vendor's cream-coloured web page, not the app.)
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Laptop mock of the vendor web page: six feature cards (source previews, macOS 26 design, privacy-first, notebooks, CSV/TSV, zip tree) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/0c/32/6f/0c326f83-0e7b-6bed-26d4-775fecb1e35b/whatdoes.jpg/1600x1000bb.jpg |
| 2 | Laptop mock: grouped extension chips (Source code, Data & config, Documents & tabular, Apple ecosystem, Logs & manifests, Archives & media) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ba/dc/58/badc5806-2aeb-b588-09f5-5bff931b8e01/fileslist.jpg/1600x1000bb.jpg |
| 3 | Dark Quick Look window: zip as a tree card ("21 files · 1.5 MB uncompressed"), right-aligned "4 items" counts, buttons "Uncompress" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/47/7d/71/477d716d-9510-da60-c890-636f0deb1426/zip.jpg/1600x1000bb.jpg |
| 4 | Dark Quick Look window: `package-lock.json` as a Name/Version/Source table, "220 dependencies", host button "Open with BBEdit" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/dd/f6/9e/ddf69ed1-a37b-9f44-0d5f-2b6d25e4410d/json.jpg/1600x1000bb.jpg |
| 5 | Companion window as a split editor/preview playground, sample "Xcstrings" | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/41/47/2a/41472a91-9098-9037-f739-2a4b4872db7d/Markdownscreenshot.jpg/1600x1000bb.jpg |
| 6 | Same playground (near-duplicate of 5) with a different headline: translations side by side by language | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/29/19/43/291943b8-fc8d-25da-c0fb-cd8d0c4fbf68/Xcstringsscreenshot.jpg/1600x1000bb.jpg |
| 7 | Same playground with an `.env` sample: every value rendered as a masked pill | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/78/09/e3/7809e3ad-f5c3-e5ce-2790-25ce557ace49/SettingsScreenshot.jpg/1600x1000bb.jpg |
| text | Website: feature list, a settings list, the troubleshooting section, privacy policy; no images beyond the app icon | https://helaia.com/tools/quickestlook/ |

### Observations by rubric dimension
1. **Preview anatomy — 3/5.**
   - Inside Apple's title bar the content is one floating rounded card on a dark navy ground. The card has the file name (semibold) and a one-line metadata strip ("package-lock.json · 220 dependencies", "String catalog · v1.0 · source: en · 3 keys", "15 variables · values masked by default"), then a hairline, then the body.
   - No mode switcher, toolbar or type pill appears in any frame, so how a user reaches raw source is not shown. The card floats about 36 px inside the window edge, which wastes width on a tall table.
2. **Content presentation — 4/5.**
   - Tables are the strongest piece. The lockfile table has small-caps indigo column headings (NAME, VERSION, SOURCE), about 36 px rows, hairline dividers rather than zebra, a monospace name column and yellow monospace versions, with the muted "npm" source in grey sans.
   - The `.xcstrings` renderer is semantic, not syntax-coloured source. Each key is a mono-blue heading, its translator comment is italic grey, and each language is an uppercase code (DE, EN, FR) beside its string.
   - The archive tree uses blue folder glyphs, chevrons and right-aligned "N items" or sizes in dim grey.
   - Dark navy with gradient-lit cards looks designed, but it is the "Vivid" theme from the store text; the "Calm" theme is never shown. Both are macOS-26-only.
3. **Interaction & discoverability — 2/5.**
   - Not shown inside the preview: no search, copy or keyboard hint. Only chevron disclosure and the host's "Uncompress" / "Open with BBEdit" buttons are visible.
4. **States & honesty — 3/5.**
   - Secrets: the `.env` sample shows each value as a fixed-width dotted pill, with the count line "15 variables · values masked by default". The same eight dots appear for every value, so no length leaks. But non-secrets (`NODE_ENV`, `APP_NAME`, `FEATURE_DARK_MODE`, `DATABASE_POOL_SIZE`) are masked too, which makes the file less useful. The comments from the file remain visible in grey italics, including one that says "API keys (these should be masked)".
   - Limits: a sample string in the `.xcstrings` frame reads "File is too large to preview" with the developer comment "Message shown when a file exceeds the per-renderer byte limit." This is sample content, so it hints at a per-renderer cap and a message but does not show how it looks.
   - The store text concedes routing limits plainly: "If you have another app installed that claims a file type … that other app's preview shows instead."
5. **Companion / settings app — 3/5.**
   - The only companion screens are a playground. A Mac window with a circular back chevron on the left and a gear on the right (the only visible route to Settings) holds a "Sample" label with a dropdown (Xcstrings / Env), an outlined `Open File…` button and a filled green `Render` button.
   - Below, a two-pane split. The left is an editable monospace source with a "Renderer: xcstrings" tag and the hint "Samples — not exhaustive. Use Open File… to render any supported file". The right is a "Rendered preview" pane. It is a developer workbench, not an onboarding screen.
   - Settings, from text only: theme (Calm/Vivid), font (SF Mono default, any monospace), size, per-renderer enable/disable, per-renderer maximum file size, a "Reveal secrets" toggle ("Off by default. Toggle on temporarily"), and a custom CSS file path. The window is not shown.
   - The troubleshooting copy documents the "Open With → Change All" workaround with numbered steps (right-click, Get Info, change "Open with" to the app, "Change All…", confirm) and names real conflicts: `.csv`→Numbers, `.toml`/`.cjs`→Warp, `.sql`/`.rs`→BBEdit, `.ts`→MPEG-2 video. A second problem, "extension is installed but doesn't show up", gets its own steps. All of this is web text; the app UI for it is not shown.
6. **Visual identity & native feel — 3/5.**
   - The app windows have a dark custom look (rounded cards, gradient glow, green primary button), more "designed" than native. The marketing uses teal gradients and a rounded geometric typeface unrelated to the app. macOS 26 only.
7. **Trust & privacy communication — 4/5.**
   - The strongest in the cluster in words: "values masked by default" lives in the preview itself, and a full privacy policy exists.
   - Honest disclosure: the app fetches `helaia.com/quickestlook/status` once per launch to check "whether the project is still maintained", and the policy names it as "the single exception" to no network traffic. The site also shows a public "actively maintained" heartbeat page.
8. **Delight and friction — 3/5.**
   - Delight: the translations-by-language view; the live "edit left, see render right" workbench; the humane one-person-studio support copy ("I'd rather give you a thoughtful answer than a corporate one").
   - Friction: over-masking; custom CSS invites a style system users must maintain; macOS 26-only; app shows one gear icon as the whole route to settings.

### Worth matching or beating
- A named, numbered, in-product-quality "another app is winning the preview" guide, with real examples of who wins which type.
- A summary line that states the privacy outcome next to the data ("values masked by default"), not only in settings.
- A try-it-yourself workbench: sample picker plus live render side by side.

### Mistakes to avoid
- Masking every value in a file, including plainly non-secret ones, with identical pills (it hides the useful structure and trains users to reveal everything).
- Making the network call at all, even a disclosed heartbeat, if the product promise is "everything stays local".
- Two App Store frames that are screenshots of a web page inside a laptop mock-up instead of the product.

---

## Super Quick Look
### Screenshot inventory
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | Companion window "Status" page: "Quick Look is ready", `Enabled` button, Quick actions, sample preview (1440x900 frame) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c5/37/03/c53703a0-c932-9ad0-42ee-a13bcf465082/01-settings.png/1600x1000bb.jpg |
| 2 | Light folder preview: header, chips, hierarchy table, footer with path | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/55/9b/5b/559b5bfe-be7a-7a85-63c9-c49f48d260b1/02-folder.png/1600x1000bb.jpg |
| 3 | Light ZIP preview: Archive Summary key-value table plus Contents table | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fb/48/76/fb487674-a9fc-3ec3-9c62-b36c292829e3/03-archive.png/1600x1000bb.jpg |
| 4 | Dark folder in a split pane: tree on the left, archive detail on the right | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/bb/6d/87/bb6d8715-afb3-52c9-5ef3-8649c5ba93cb/Frame_58__U00284_U0029.png/1600x1000bb.jpg |
| 5 | Dark folder: same split pane, selecting `shot_16.jpg` shows an inline image preview | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/99/e9/9f/99e99fd6-e3ed-b30b-0592-5e6056d4c55b/Frame_58__U00285_U0029.png/1600x1000bb.jpg |
| 6 | Dark XML source with gutter, coloured tokens, `Wrap` switch, chips | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/b5/9e/c7/b59ec7f9-a671-cd01-841f-72ea87fc4c0b/Frame_58__U00286_U0029.png/1600x1000bb.jpg |

Frames 1–3 are marketing headlines over soft glass/ribbon backgrounds. Frames 4–6 are real windows on a desktop picture. Frames 1–3 are 1440x900 and 4–6 are 1600x1000, so the set was assembled at two different times.

### Observations by rubric dimension
1. **Preview anatomy — 4/5.**
   - Anatomy is a title block (large file name, grey subtitle such as "Folder contents preview", "ZIP archive contents preview", "Syntax-aware text preview"), colour-coded rounded chips on the right (folder / 8 items / 2 levels, data / zip / 668 bytes, developer / xml / 2 kb), a hairline, then a bordered content panel.
   - A folder summary row repeats the folder icon, "Modified" and "Visible items" columns. The footer shows the real path, the item count and level count ("8 items … 2 levels"). A "Super QuickLook" brand chip sits at the bottom right of the light frames.
   - The light frames carry a page-width web-document feel: the content column is about 65% of the window width, with large outer margins.
2. **Content presentation — 3/5.**
   - Tables use small-caps column headings (NAME, KIND, SIZE, MODIFIED) and hairline rows. In the ZIP summary, the key-value table is a bordered two-column grid (Format, Size, Entries, Folders, Files). It reads like a documentation page, not a native app.
   - XML in frame 6 is crisp: about 12 pt mono, line numbers in a dim right-aligned gutter, red tags, green attribute values, italic grey comments, a switch labelled `Wrap` in a header strip above the code panel.
   - Folder rows use real file-type icons (small orange Swift-style icons on `.swift` rows in the light frames), and dates are cut with an ellipsis in the dark table ("Oct 29, 2024 at 06…"). The latter is a truncation the user cannot fix.
3. **Interaction & discoverability — 4/5.**
   - The split pane is the standout: select any row and an inline detail pane shows an archive listing (frame 4) or a full image (frame 5), with `Open in Finder` and a circular close button. Release notes add "on-demand previews" for large folders. Hierarchy chevrons let a user expand levels.
   - No search, keyboard hint or copy affordance appears.
4. **States & honesty — 3/5.**
   - Folder metadata is explicit about scope: "10 items · up to 2 levels", "Visible items 9". A cap on depth is communicated in the header, which is better than silence. No truncation notice, error or empty state is shown. The store text promises "useful structure instead of … an empty Quick Look window", and the release notes mention on-demand previews for large folders without showing them.
   - The companion's status card says "Quick Look is ready … Super QuickLook replaces weak default previews with readable, local renderers" next to an `Enabled` button. That overstates what the app can know: macOS chooses the provider. This is the wording SpacePane's rules forbid.
5. **Companion / settings app — 4/5.**
   - The only well-structured companion here. A 780 pt window with a left sidebar (app icon and name "Super QuickLook – Preview utility", then Status (selected, with an "On" badge), Preview, Formats, Advanced, About) and a "System Settings" link and version number pinned at the bottom.
   - The Status page: a small-caps blue "STATUS" kicker, a large title "Ready to preview", one explanatory sentence, a green-check status card with an `Enabled` button, a "Quick actions" pair of cards (Preview samples — "Open the renderer gallery"; Reset Quick Look — "Refresh Finder's cache"), and a "Preview sample" card with an "Open gallery" pill and a live miniature folder preview ("Sample Project"). Per-format toggles and theme editing sit on tabs that are not shown.
6. **Visual identity & native feel — 3/5.**
   - The companion looks like a current macOS sidebar app (translucent grey, SF text, rounded cards). The preview windows look like HTML pages: pill chips, bordered tables, an in-content brand chip. The marketing backgrounds are generic glass and ribbon imagery.
7. **Trust & privacy communication — 2/5.**
   - Only in copy: "Local, fast, and private." "Everything is rendered locally … No cloud account, subscription, or file upload". Nothing in the preview UI says what is hidden or not uploaded. No secret handling is claimed anywhere, and `.env`/PEM/key files are listed as supported.
8. **Delight and friction — 3/5.**
   - Delight: inline preview of a selected file inside a folder is useful, as is the "Preview samples" gallery on the status page.
   - Friction: the brand chip inside the content, the stale version in the screenshots (0.1.5 vs 1.0.3), a "Reset Quick Look" action phrased as refreshing Finder's cache, and the status overclaim.

### Worth matching or beating
- A real status page with a headline state, an explanation, a primary action and a built-in sample gallery (checking that the app itself renders).
- A footer that gives the exact path, the counts and the depth limit.
- Selecting a row to see a bounded inline preview (adapt only where a bounded, no-extraction reader exists).

### Mistakes to avoid
- "Quick Look is ready / Enabled" wording, which implies Finder is using the app.
- A permanent brand chip inside the previewed content.
- Silently ellipsising dates and names in tables.

---

## Simple Quick Look
### Screenshot inventory
All five are marketing frames: a Chinese headline over an English subline on a colourful geometric backdrop, with a companion window below. Each canvas is 1600x1000 but the artwork stops at about x=1422, leaving a white strip on the right and bottom.
| # | What it shows (one line) | URL |
|---|---|---|
| 1 | File Types tab: "Mini Program" and "Subtitles" groups, every row `Plain Text` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/04/99/af/0499afa4-c18c-fabf-763b-91d041350349/frame-4.png/1600x1000bb.jpg |
| 2 | Inspector tab: dashed drop zone and a File Info key-value list | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/39/6b/d6/396bd685-7791-c8a7-f0dd-1afffc0ded34/frame-5.png/1600x1000bb.jpg |
| 3 | File Types: "Config" group (toml, yaml, properties, conf, ini, cfg, env, lock) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/20/b0/1b/20b01bc9-57b1-20c9-86d6-61c1d32903f8/frame-2.png/1600x1000bb.jpg |
| 4 | File Types: mini-program group with `XML Pretty` vs `Plain Text` pills | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c8/d5/21/c8d521e9-ac81-27e8-071f-e3acfe24b307/frame-3.png/1600x1000bb.jpg |
| 5 | File Types: "Text" group (txt, md, swift/py/js… on one row, kt, jsx, tsx, gradle…) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/05/bd/33/05bd335f-6600-327c-a513-99f40e2e4ce2/frame-1.png/1600x1000bb.jpg |

### Observations by rubric dimension
1. **Preview anatomy — not shown.** No Quick Look window appears in any frame. The store text says "Minimal and distraction-free — preview only, no editing" and "Fast plain-text rendering".
2. **Content presentation — not shown, partial hint.** Render modes appear only as the pill names in the File Types list: `Plain Text` and `XML Pretty`. Nearly every type is `Plain Text`, including config, subtitles and stylesheets, so preview richness is minimal by design.
3. **Interaction & discoverability — 2/5.** The Inspector accepts a dropped file or `Choose File…`. Everything else is not shown. No toggles appear in the list.
4. **States & honesty — 3/5.** The Inspector's File Info panel states "Supported: ✓ Yes" and "Render: XML Pretty" for a file, so support is never ambiguous in the companion. Preview-time states are not shown.
5. **Companion / settings app — 3/5.**
   - A single window with a centred segmented control in the title bar: `File Types | Inspector | Settings`. (The Settings tab is not shown.)
   - File Types is a grouped list. Each row has the extension in large mono (several share a row, such as `.yml .yaml` or `.swift .py .js …`), the technical type identifier beneath it in small grey (for example `com.xiaomac.simplequicklook.toml`, `public.source-code`), and a right-aligned rounded pill for the render mode. It is a complete, honest map and good for debugging, but it exposes raw UTI strings to ordinary users.
   - The Inspector is the standout: a dashed drop zone ("Drop a file here / Choose File…") above File Info rows right-aligned by label: Name, Extension, Size, UTType, Kind, Supported, Render. It answers "why does this file look like this?" directly.
6. **Visual identity & native feel — 3/5.** A native-looking window with a pill-shaped segmented tab bar. The marketing is loud and the rendered canvas leaves a visible white strip, which looks unfinished.
7. **Trust & privacy communication — not shown** beyond "no editing"; nothing about secrets, locality or limits.
8. **Delight and friction — 2/5.** Delight: the Inspector. Friction: raw UTIs in the primary list, no enable/disable switch visible, a long single-column list with no search, English store text but Chinese-first headlines on every frame, and a vendor site behind a bot challenge so there is no public support page to check.

### Worth matching or beating
- A drop-a-file Inspector that reports extension, resolved type, supported or not, and which renderer applies.
- Showing the renderer name per type, as a pill, so users see what they will get.
- Grouping extensions that share one renderer on one row.

### Mistakes to avoid
- Surfacing internal type identifiers as the second line of every row.
- A list with no switch, no search and nothing but `Plain Text` pills.
- Shipping store frames whose artwork does not fill the canvas.

---

## Cluster synthesis

### Patterns most apps share (table stakes)
- Apple's host chrome plus one app-drawn header: file name and a metadata line, with a type label on the right (QuickLook Pro, Super Quick Look, QuickestLook all do it).
- Archives and folders as an expandable disclosure tree with Name / Size / Kind columns, folder glyphs and a footer count. This is in all three preview apps.
- Source with a dimmed line-number gutter and a `Wrap` control (QuickLook Pro, Super Quick Look).
- Local-only claims as a store-frame footer or a headline ("Your files stay on your Mac", "Local, fast, and private", "never sends your files anywhere").
- A companion window that is a utility, not a content app, with a sidebar or tab bar. All of them are English-only.
- Marketing frames with a key-cap "Space" hint or "Press Space in Finder".

### Patterns only one or two apps have that users would notice
- Preview/Raw segmented control and an orange mode bar (QuickLook Pro).
- Secrets masked as fixed-width pills with a "values masked by default" count (QuickestLook), plus a reveal toggle in settings.
- Inline detail pane for a selected item in a folder (Super Quick Look).
- A status page with a sample gallery and quick actions (Super Quick Look).
- A drop-a-file Inspector (Simple Quick Look).
- A source/render workbench with a sample picker (QuickestLook).
- A written conflict guide with named culprits (QuickestLook); an honest "macOS chooses" FAQ (QuickLook Pro).
- A try-it-with-Space interactive Finder on the website (QuickLook Pro).

### Where every app in this cluster is weak (our opening)
- **Limits and partial results are never shown in the UI.** No screenshot shows a truncation notice, depth cap or too-large state. The only text-based hints are QuickLook Pro's support copy ("A partial preview is labeled") and a sample string in a QuickestLook frame.
- **No in-app provider-conflict diagnosis.** Guidance lives on websites. The companions never say "this type is probably being handled by another app, and here is how to check". Super Quick Look's Status page overclaims instead.
- **Secrets communication is thin.** Only QuickestLook shows it, with all values masked and no per-line explanation; QuickLook Pro hides `.env` secrets in text only.
- **No theme editor with live preview in a native settings page.** The one live preview is QuickestLook's playground with an unseen settings window and a custom CSS file. Settings, onboarding and per-type switches have no screenshots in three of four apps.
- **Search, copy, keyboard shortcuts and accessibility** are absent from all marketing; nothing is shown about VoiceOver, text selection or localisation. Every listing is English only.
- **Honest status wording** is poor or not shown for every app.

### Scorecard (1–5; "–" means not shown)
| Dimension | QuickLook Pro | QuickestLook | Super Quick Look | Simple Quick Look |
|---|---|---|---|---|
| 1 Preview anatomy | 4 | 3 | 4 | – |
| 2 Content presentation | 4 | 4 | 3 | – |
| 3 Interaction & discoverability | 3 | 2 | 4 | 2 |
| 4 States & honesty | 3 | 3 | 3 | 3 |
| 5 Companion / settings | 2 | 3 | 4 | 3 |
| 6 Visual identity & native feel | 3 | 3 | 3 | 3 |
| 7 Trust & privacy communication | 2 | 4 | 2 | – |
| 8 Delight and friction | 3 | 3 | 3 | 2 |

### Ten ranked recommendations for SpacePane
1. **Show limits and partial results in a quiet footer strip inside every preview.** What: one line at the bottom ("Showing first N of M rows · read-only") with a short localized reason on hover/VoiceOver, plus a distinct state for "too large", "depth capped", "disabled type" and "unsupported". Why: no rival shows any limit in the UI, while Super Quick Look's header ("up to 2 levels") and QuickLook Pro's footer counts prove the space exists. Rule: bounded budgets, honest status, all strings localized. Cost: M.
2. **One consistent header card plus a slim mode bar for every format.** What: a 40–48 pt card with a type glyph, the file name, a one-line per-type metadata strip (encoding · lines · size; rows · tables; files · expanded size) and a quiet type label on the right; a mode bar beneath it with the Preview/Source or Tree/Raw segmented control and a Wrap switch. Why: QuickLook Pro and Super Quick Look both do it and it unified unlike formats. Use the system accent, not a custom one. Rule: native AppKit/SwiftUI, no web content, chrome kept to about two rows. Cost: S–M.
3. **Mask secrets with a visible, countable, selective treatment.** What: fixed-width pills only where the redaction classifier fires, a header note "N likely secrets hidden" beside the metadata, and the typed-count wording from the safety-findings decision; never mask ordinary values. Why: QuickestLook shows the idea but over-masks `NODE_ENV` and flags and has no per-item explanation. Rule: redact by default, findings are typed kinds and counts only, no source values. Cost: S.
4. **Make the companion Status honest and useful.** What: a headline state ("Settings saved", extension enablement steps, an "Open System Settings" button) and a "Preview sample" card using the built-in appearance samples, with wording that never says Finder uses SpacePane. Why: Super Quick Look's status page is the best layout in the cluster but says "Quick Look is ready / Enabled", which overclaims. QuickLook Pro's setup window is described only in text. Rule: companion text reports where settings are saved, never routing; one window with a fixed sidebar. Cost: S.
5. **Add an in-app "Why am I seeing another preview?" guide under File Types.** What: per-type help that explains macOS chooses one provider, shows the Open With → Change All steps for that exact type, and lists known common conflicts as plain text. Why: QuickestLook documents this on the web only; no companion offers it, and it is the top cause of "it doesn't work". Rule: we cannot force or observe routing, so no automation, no system-preference changes, no "Finder is using us" claims. Cost: M.
6. **Redesign File Types rows around an enable switch plus a renderer pill.** What: category groups, a search field, one switch per logical type, the extensions as chips, and the renderer shown as a small pill ("Tree", "Table", "Source"). Keep type identifiers behind Developer Mode. Why: Simple Quick Look's pill-per-renderer is a clean idea but its rows show raw type identifiers and no switch; QuickestLook has per-renderer switches only in text. Rule: catalog-driven rows, stable IDs, disabled types must not fall back to generic text. Cost: S–M.
7. **Add a "Check this file" panel to Try Preview (Developer Mode).** What: after a drop, show extension, resolved type, matching catalog format, enabled or disabled, and the renderer name. Why: Simple Quick Look's Inspector answers "why does this look like this?" in one table. Rule: direct-file-drop contract (one local URL, metadata only on hover), Developer Mode stays out of the extension snapshot. Cost: S–M.
8. **Make the Theme page a source/render workbench.** What: a sample picker, a raw view and the rendered view side by side, driven by the existing built-in samples; offer typography and contrast controls only, with reset. Why: QuickestLook's split playground is the one live theme-style surface in this cluster. Skip custom CSS. Rule: themes are inert schema-validated data, no scripts or style injection; fonts tolerate missing traits. Cost: M.
9. **Give lists and archives a footer summary and a selection detail line.** What: "7 files · 4 folders · 528 bytes expanded", the depth cap and the read-only path, and a one-line detail for the selected row (size, modified, kind). Why: QuickLook Pro's footer, Super Quick Look's path/levels footer. Do not copy Super Quick Look's inline full preview of a selected file unless a bounded, no-extraction reader already exists for that type. Rule: read-only, no extraction, no nested archive recursion. Cost: S (summary), L (inline detail).
10. **Use real Finder-sized screenshots and an interactive "press Space" demo on the site.** What: marketing built from actual preview windows (dark and light) in their real size and a scripted Space-bar demo; keep claims in sync with the support page. Why: QuickLook Pro's demo is memorable; QuickestLook's laptop-of-a-web-page frames and Simple Quick Look's unfilled canvas look weak, and QuickLook Pro's store text vs support page disagree on ZIP64. Rule: the website is JSON-driven in every app language, format names from the catalog (`npm run data:sync`), no unverified routing claims. Cost: S–M.
