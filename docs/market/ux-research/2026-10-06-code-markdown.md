# Code and Markdown specialists - UX/UI observations
Researched 2026-10-06. Sources are vendor marketing (App Store, websites, repositories); nothing was installed or tested.

Scores are 1-5 judgements of what the marketing material shows; "n/s" means not shown. Everything below is **observed in marketing material**, not tested. Wording is paraphrased; only short UI labels are quoted. The feature inventory lives in `docs/market/2026-10-05-competitor-landscape.md` and is not repeated.

## Apps covered
| App | App Store ID / repo | Version seen | Screenshots inspected | Sources |
|---|---|---|---|---|
| Peek (Big Z Labs, $7.99) | id1554235898 | 2.6.4 (last update 2022-04-02) | 6 App Store | [App Store](https://apps.apple.com/us/app/peek-a-quick-look-extension/id1554235898), [vendor page](https://www.bigzlabs.com/peek) (returned no readable text) |
| Syntax Highlight (sbarex, free OSS) | github.com/sbarex/SourceCodeSyntaxHighlight | repo master, version not shown | 11 README images | [README](https://github.com/sbarex/SourceCodeSyntaxHighlight) |
| QLMarkdown (sbarex, free OSS) | github.com/sbarex/QLMarkdown | repo master, version not shown | 5 README images | [README](https://github.com/sbarex/QLMarkdown) |
| PreviewCode (smittytone, $2.99) | id1571797683 | 2.3.2 | 7 App Store | [App Store](https://apps.apple.com/us/app/previewcode/id1571797683), [site](https://smittytone.net/previewcode/index.html) |
| PreviewMarkdown (smittytone, $2.99) | id1492280469 | 2.4.3 | 6 App Store | [App Store](https://apps.apple.com/us/app/previewmarkdown/id1492280469), [site](https://smittytone.net/previewmarkdown/) |
| Source Code Preview (Anybox, $4.99) | id6759270528 | 1.5 | 3 App Store | [App Store](https://apps.apple.com/us/app/source-code-preview/id6759270528) |
| Markdown Preview - Quick Look (Anybox, $1.99) | id6739955340 | 2.5.3 | 5 App Store | [App Store](https://apps.apple.com/us/app/markdown-preview-quick-look/id6739955340) |
| Peekdown (Tim Gavin, $4.99) | id6757321612 | 3.2 | 8 App Store | [App Store](https://apps.apple.com/us/app/peekdown-markdown-viewer/id6757321612), [site](https://peekdown.app) |
| Code Peek+ (Onder Kadagan, free) | id6760186407 | 1.0.3 | 4 App Store (look like composited mockups) | [App Store](https://apps.apple.com/us/app/code-peek/id6760186407), [site](https://onderk.com/apps/code-peek-plus) |
| PeekCode (NeoLabs, free) | id6760995314 | 1.4.1 | 4 App Store | [App Store](https://apps.apple.com/us/app/peekcode/id6760995314), [site](https://neolabsapp.com) |
| Markdown Peek (Michael Thingmand, free) | id6753810611 | 1.8 | 6 App Store | [App Store](https://apps.apple.com/us/app/markdown-peek/id6753810611), [site](https://markdownpeek.com) |
| Glance (Samuel Meuli, archived) | github.com/samuelmeuli/glance, id1513574319 | repo master (2020 era) | 6 README images | [README](https://github.com/samuelmeuli/glance) |

Not inspected: any video demo; the anybox.ltd product pages; Peek's vendor page text. Peekdown and Markdown Peek are also full viewers (Peekdown an editor); only their Quick Look and settings surfaces are judged.


## Peek - A Quick Look Extension (Big Z Labs)
App Store tagline: searching, jumping, scroll restoring, syntax highlighting. $7.99, macOS 10.15+, last updated 2022-04-02 (macOS 15 behaviour unknown).

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Split light/dark reveal of C header: dim right-aligned gutter, selected line 28 highlighted full-width, 'Open with Xcode' host button, small eyes mark bottom-right | https://is1-ssl.mzstatic.com/image/thumb/Purple115/v4/1c/6a/52/1c6a52c9-02ef-a060-3638-012aaf204a91/13347946-5d65-403b-8aa5-8d3ab4a81355_source-code-transparent.png/1600x1000bb.jpg |
| 2 | Markdown README with left TOC sidebar (current section pill-highlighted, collapsible rows), split light/dark, per-code-block clipboard button | https://is1-ssl.mzstatic.com/image/thumb/Purple115/v4/8d/48/5c/8d485cb2-c878-9469-8bb0-a68ebed5de66/2955ba24-ff4d-4a91-b7c2-c2f5363fe374_markdown-with-table-of-contents.png/1600x1000bb.jpg |
| 3 | Find in page: inline Find bar with match count, prev/next, Done; every hit boxed, active hit yellow; centred search HUD | https://is1-ssl.mzstatic.com/image/thumb/Purple115/v4/6b/bf/72/6bbf723c-fc0c-f016-64ae-59b46a2ec3b9/5523559b-e45e-4b4f-b221-7a197fb0aa20_search-cmark.png/1600x1000bb.jpg |
| 4 | Jump to line: floating 'Line Number' HUD in Finder; ePDF shows 'Go to Page' and 'Search' pills with command-key labels plus a red close button | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource115/v4/18/29/dd/1829dd45-efc7-da74-8201-22c993dc7e78/d661adcc-5fe8-4a01-bbef-3b7d40e724a9_go-to-line_page-number-transparent.png/1600x1000bb.jpg |
| 5 | ePDF preview with thumbnail rail and find bar, plus Finder preview pane with 'Rename to .ePDF or .pdf' quick action | https://is1-ssl.mzstatic.com/image/thumb/Purple115/v4/0b/54/24/0b542408-7bca-23df-e834-afc7a9ea8bf7/2308d353-3f93-40eb-85ca-c5902e58bc10_ePDF-find-bar-selection.png/1600x1000bb.jpg |
| 6 | Look Up popover (dictionary) over a Markdown README in dark theme | https://is1-ssl.mzstatic.com/image/thumb/Purple115/v4/eb/98/47/eb98471c-f8a4-a0a3-eb46-f4735f5b55df/9110335a-9f1f-4aab-a445-15e22c130ad8_look-up-transparent.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 4/5.** Title carries a small eyes glyph after the filename and again in the content corner, a provider mark; host chrome only; find bar and HUDs are inline overlays, TOC is a left rail inside the preview.
- **2 Content presentation - 4/5.** Gutter is dim, right-aligned, ~11 px mono, selected line number turns bold; code on a dark pane with full-width selection band; README rendering is GitHub-like with 2 px rules under h1/h2 and a copy button on code blocks. Dense but clean.
- **3 Interaction and discoverability - 5/5.** Strongest in this cluster: search, jump-to-line and TOC; shortcut hints shown as ⌘L and ⌘S labels on floating pills, so shortcuts are discoverable without docs; scroll position restore and Look Up are claimed.
- **4 States and honesty - 2/5.** Only a size ceiling (5 KB to 1 MB) and a list of unsupported types are stated in the store text; no in-preview truncation notice shown.
- **5 Companion / settings - 1/5.** n/s - no companion or settings screenshot; 70+ themes are claimed in text only.
- **6 Visual identity and native feel - 3/5.** Pragmatic and consistent, but 2021-era; promo art uses wavy gradient backgrounds and heavy yellow reveal curve.
- **7 Trust and privacy communication - 2/5.** No statement in the UI; store text lists unsupported types honestly.
- **8 Delight and friction - 4/5.** Delight: the eyes mark doubles as proof of which provider drew the view. Friction: needs a Quick Action to rename PDFs to .ePDF to get search - clever but surprising.

### Worth matching or beating
- Inline find bar with count, prev/next and per-hit outlines, plus a one-field jump-to-line HUD; label the shortcuts on the floating controls.
- Markdown TOC rail that highlights the current section and collapses nested headings.
- Tiny provider mark in the corner of the content (which provider drew this) without claiming anything about routing.

### Mistakes to avoid
- Hiding the only discovery path for shortcuts in promo art - keep a hint inside the real preview.
- A theme count (70+) as the only customisation message with no settings screen shown.
- Unsupported-type disclosure only in the store text, not in the product.


## Syntax Highlight (sbarex)
Free open source; README is the only source. The most-used open-source code Quick Look; screenshots are undated. The Quick Look preview itself is not shown as a standalone screenshot, only the settings preview pane.

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | System Settings > Extensions > Quick Look list with 'Syntax Highlight Quicklook Extension' circled (older System Preferences chrome) | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/extensions.png |
| 2 | Settings, General tab: toolbar tabs General/Formats/Plain/Colors/Inquiry file; left form (render engine RTF, Light/Dark scheme cards, font, wrap, line numbers, tabs slider, data limit); live preview pane on the right with sample-format popup and light/dark toggle | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings.png |
| 3 | Same window with advanced settings shown (HTML engine, extra Highlight arguments, custom CSS, convert line ending, VCS, Debug switch); preview shows +/- change bars in the gutter | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_advanced.png |
| 4 | Formats tab: searchable format list with file icons and extensions; per-format override rows each with a checkbox (unchecked = inherited, dimmed); preprocessor field with a python3 json.tool command | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_format.png |
| 5 | Language Server popover: key/value table (executable /bin/clangd, delay, hover, semantic, syntax error, options) | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_ls.png |
| 6 | VCS popover: git/hg paths and light/dark colour wells for new, changed and removed lines | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_vcs.png |
| 7 | CSS preview showing green '+', red '-' and blue '|' bars in the gutter | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/vcs_preview.png |
| 8 | Plain tab: 'Settings applied to files without extension' with Binary files popup and pattern/syntax/format table | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_plain.png |
| 9 | Plain-file rule editor sheet: filename or MIME pattern, regex and case checkboxes, syntax popup, 'Use format of' radio list | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/settings_plain_editor.png |
| 10 | Colors tab: theme gallery with token thumbnails (left), token list editor with B/I/U and CSS (centre), live code (right) | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/theme_editor.png |
| 11 | 'Inquiry format' window: description, UTI, extensions, lexer, green dot 'Supported and handled' | https://raw.githubusercontent.com/sbarex/SourceCodeSyntaxHighlight/master/assets/inquiry.png |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 2/5.** Preview anatomy cannot be judged from Quick Look; the settings preview pane shows a bare code surface with gutter and optional +/-/| version-control bars.
- **2 Content presentation - 4/5.** System font mono 12 pt in the sample, right-aligned gutter numbers, wide scheme library (Base16, Kwrite, Godot, jEdit...). Per-format scheme overrides; hard-wrap at a set column (default 140); tabs-to-spaces slider.
- **3 Interaction and discoverability - 2/5.** No in-preview interaction is shown; interaction lives in settings (live preview, format picker, light/dark toggle for the sample).
- **4 States and honesty - 3/5.** Data limit setting (1-3 MB) and a Debug switch exist; the Inquiry window gives a green/other status per file type with 'Supported and handled'. No truncation notice shown.
- **5 Companion / settings - 4/5.** Best-in-cluster diagnostics: settings and preview side by side, sample-file popup, inherit-or-override checkboxes, 'Inquiry file' tool, plain-file rule table. But it is jargon-heavy: render engine RTF/HTML, extra Highlight arguments, preprocessor shell command, language server executable path, custom CSS. Five toolbar tabs plus popovers; an honest verdict is powerful but expert-only and very dense.
- **6 Visual identity and native feel - 2/5.** Plain classic AppKit forms, mixed control styles (popups, steppers, sliders, small bordered buttons), grey backgrounds; reads as a 2020 utility. Onboarding is a README screenshot of System Settings with the extension row circled.
- **7 Trust and privacy communication - 2/5.** No privacy, limit or read-only statement visible in the settings UI; only the data-limit field hints at bounded work.
- **8 Delight and friction - 3/5.** Delight: live preview and VCS gutter bars. Friction: the whole window is an options catalogue; defaults are hard to reason about without reading the README.

### Worth matching or beating
- Settings and live preview in one window with a sample-format popup and a light/dark toggle - keep the preview next to the controls.
- Per-format override rows where an unticked checkbox visibly means 'inherit the global value'.
- A file-inquiry window that explains how one file type resolves, with a status colour.

### Mistakes to avoid
- Exposing shell commands, CSS and language-server paths as primary settings.
- Five tabs plus nested popovers for what could be a handful of choices; no progressive disclosure beyond a View-menu toggle.
- A green 'Supported and handled' dot that could be read as proof Finder uses the app; SpacePane must word this as 'supported by SpacePane' only.


## QLMarkdown (sbarex)
Free open source; README includes a System Settings screenshot of the current Login Items & Extensions pane. Source: https://github.com/sbarex/QLMarkdown

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Single-window Preferences: theme, base font size, ~25 checkbox options and extensions in a 5-column grid, external-link popup, Quick Look size, 'Open System Settings' button; below, source panel and preview panel side by side with footer 'Rendered in ... seconds' and size | https://raw.githubusercontent.com/sbarex/QLMarkdown/master/assets/img/main_interface.png |
| 2 | Quick Look window showing the README as GitHub-style page in a centred column (annotated by the author) | https://raw.githubusercontent.com/sbarex/QLMarkdown/master/assets/img/preview_quicklook.png |
| 3 | macOS Shortcuts action 'Markdown format' with about 20 'predefined' popups | https://raw.githubusercontent.com/sbarex/QLMarkdown/master/assets/img/preview_shortcut.png |
| 4 | MathJax library menu: Linked from web / Embed (1,2 MB) / Fetch from web... / Disabled | https://raw.githubusercontent.com/sbarex/QLMarkdown/master/assets/img/mathjax_menu.png |
| 5 | System Settings > Login Items & Extensions > Quick Look sheet with QLMarkdown row circled | https://raw.githubusercontent.com/sbarex/QLMarkdown/master/assets/img/system_setings1.png |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** Quick Look view is host chrome plus a GitHub-like page inside a centred column; no mode switch visible (a 'Render as source code' option exists in settings).
- **2 Content presentation - 4/5.** GitHub-like theme CSS family (e.g. 'default-noborder.css'), generous leading, h1 rule, hairline blockquote bar, tables, task lists, math and Mermaid. Readable and conventional.
- **3 Interaction and discoverability - 2/5.** No in-preview controls shown; interaction is in the preferences window (refresh, dark/light toggle for the preview panel).
- **4 States and honesty - 3/5.** Footer shows render time and generated size, plus 'Show debug info'; unsafe options are labelled in the label itself ('Inline HTML (unsafe)', 'Math extension (linked)').
- **5 Companion / settings - 3/5.** Single window, but the top half is a wall of ~25 checkboxes in five columns above a live source/preview split. The split is great; the grid is exhaustive without grouping, and there is no onboarding beyond an 'Open System Settings > ... > Quick Look panel...' button.
- **6 Visual identity and native feel - 3/5.** Strong icon (eye with download arrow, dark squircle); preferences look like a utility, not a current macOS app.
- **7 Trust and privacy communication - 4/5.** Best trust copy in the cluster, in the product: labels mark linked-from-web libraries, the menu offers Embed or Disabled, and the README documents a Content Security Policy and 'no information collected'. The linked-from-CDN default is a trade-off SpacePane should not copy.
- **8 Delight and friction - 3/5.** Delight: live split with timing. Friction: dense, and web fonts or CDN scripts blur the 'local only' story.

### Worth matching or beating
- Live source-versus-rendered split inside the settings window with a render-time and size footer.
- Labelling risky or network-touching options in plain words directly on the control.
- A button that opens the right System Settings pane from the app.

### Mistakes to avoid
- Defaulting math and diagrams to CDN-linked scripts.
- 25 ungrouped checkboxes as the first thing a user sees.
- A Shortcuts action whose 20 'predefined' popups are meaningless without reading docs.


## PreviewCode (smittytone)
$2.99, macOS 12.4+, v2.3.2 updated 2026-08-06. Sources: App Store plus https://smittytone.net/previewcode/index.html

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Companion main window: wordmark 'PreviewCode 2', i / gear / mail icon buttons, one-time-run explanation, version | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/49/66/bf/4966bf5f-2023-03b5-d3f1-3017255188ca/ss001.png/1600x1000bb.jpg |
| 2 | Settings: text-size slider (16 pt), Light/Dark/Auto theme radios, two theme rows with thumbnails and '...' pickers, font/style/line-spacing popups, 'Display Line Numbers' switch; Defaults, Advanced..., ?, Apply | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/f1/43/0d/f1430ddf-7fea-4c63-deed-c00e35ea71ed/ss002.png/1600x1000bb.jpg |
| 3 | Theme popover: a vertical list of themes, each with a sample-code thumbnail on the left and name on the right; selected row in orange | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/78/f0/ba/78f0ba31-8b73-f812-bbc2-016cf272ee75/ss003.png/1600x1000bb.jpg |
| 4 | Finder Quick Look of a Swift file on light theme, no gutter, large window | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/21/b2/93/21b29391-6e26-0f99-194b-50a202b10a00/ss004.png/1600x1000bb.jpg |
| 5 | Same file with a zero-padded dim gutter (001...071) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/dc/90/34/dc9034f0-ad82-44d3-ec44-38d97f25e085/ss005.png/1600x1000bb.jpg |
| 6 | Finder icon view with content thumbnails of source files, and the preview pane showing a 'Language: basic' header | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/85/87/4c/85874c58-2ba9-c06b-d5f2-e1ba978404e1/ss008.png/1600x1000bb.jpg |
| 7 | Finder icon view full of source-file thumbnails showing real syntax-coloured text | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/2d/00/7d/2d007dd6-720d-398c-fd26-f9e010b96b0e/ss007.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** Quick Look uses host chrome only; content is flush to the window edges; the preview pane also leads with a 'Language: ...' header line.
- **2 Content presentation - 3/5.** Mono at 16 pt default in settings, JetBrainsMono Nerd Font in the screenshot, Xcode (light) / Atom One Dark; the gutter is a dim, zero-padded 3-digit column. A large, loose layout shows about 70 lines in a tall window.
- **3 Interaction and discoverability - 1/5.** Nothing interactive in the preview is shown; no find, copy or mode switch.
- **4 States and honesty - 2/5.** Honest about fixes: 'logging out of your Mac... and running this app once more'. No truncation or secret messaging.
- **5 Companion / settings - 3/5.** Tiny fixed-size window with three icon buttons; theme picker with visual thumbnails is the highlight; explicit Apply (no live preview), and an Advanced... sheet. Onboarding is one paragraph: run once, then manage in System Settings > Extensions > Quick Look.
- **6 Visual identity and native feel - 3/5.** Heavy slab-serif wordmark and a coloured header band per product (blue for code, magenta for Markdown); not macOS-26-native but distinctive.
- **7 Trust and privacy communication - 2/5.** No privacy statement in the UI shown.
- **8 Delight and friction - 3/5.** Delight: real-content thumbnails in Finder, theme thumbnails. Friction: the Apply button and the 'log out and run once more' fix.

### Worth matching or beating
- Theme picker rows that show a code sample in each theme, not only a name.
- Thumbnails that look like a miniature of the actual content, so folders full of source are scannable.
- A zero-padded, dim gutter that never shifts the code when line counts grow.

### Mistakes to avoid
- Apply/Defaults modal model with no live preview.
- Telling users to log out to repair a broken extension as the main troubleshooting line.
- No preview-level controls at all (find, copy).


## PreviewMarkdown (smittytone)
$2.99, macOS 11.5+, v2.4.3 updated 2026-05-01. Sources: App Store plus https://smittytone.net/previewmarkdown/

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Companion main window in dark: 'PreviewMarkdown 2' magenta wordmark with i / ... / mail buttons and the same run-once text | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/34/67/21/34672137-ddbf-a2ec-cf50-6ed7eb46e9cd/Screenshot_2025-07-29_at_15.27.05.png/1600x1000bb.jpg |
| 2 | Settings: body-size slider, body font and code mono font popups, 'Colour' popup (Headings, Code, Links, Blockquotes, YAML keys) opening the system Colors panel; three checkboxes; Defaults, ?, Apply | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/fb/12/18/fb121820-5da2-fbc9-b7c8-44eddf915efb/Screenshot_2025-08-16_at_15.39.03.png/1600x1000bb.jpg |
| 3 | Dark full-screen Quick Look: orange h1/h2, bold blue blockquotes, emoji checkbox, translucent floating pill with share, exit-full-screen and close | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/30/a1/d9/30a1d92b-4a25-9801-acb6-cc18bee1a89a/Screenshot_2025-08-16_at_15.41.20.png/1600x1000bb.jpg |
| 4 | Finder Get Info 'Preview' section with the rendered note and the MD thumbnail in the window behind | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/fa/b3/41/fab34143-27ae-a8f2-b31d-63614cf7924c/Screenshot_2025-07-29_at_15.29.20.png/1600x1000bb.jpg |
| 5 | Finder column view with the preview pane showing the same note beside a selected file | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/e4/57/f8/e457f8c8-4a2a-ed1b-4d44-f7f550ec1976/Screenshot_2025-07-29_at_15.29.59.png/1600x1000bb.jpg |
| 6 | Finder icon view of Markdown thumbnails: miniature rendered pages with a large grey 'MD' badge | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f9/f3/f0/f9f3f0a1-be61-0dc2-1140-728ef8579bd0/Screenshot_2025-07-29_at_15.31.17.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 2/5.** Host chrome only; in full screen the host's floating pill appears; no mode switch, no TOC.
- **2 Content presentation - 2/5.** Default look is idiosyncratic: bold orange headings, large bold blue blockquotes with no quote rule, green monospace, emoji checkbox; wide measure that fills the window (about 150 characters per line at full screen), tight paragraph rhythm.
- **3 Interaction and discoverability - 1/5.** No interaction in the preview is shown.
- **4 States and honesty - 2/5.** Settings option 'Render YAML front matter, if present' hints at honesty about metadata; no other states shown.
- **5 Companion / settings - 3/5.** Same small window as PreviewCode; colour per element is configurable but through the old system Colors panel with crayon pencils; no live preview and an Apply button.
- **6 Visual identity and native feel - 3/5.** Dark UI with magenta brand; coherent family with PreviewCode.
- **7 Trust and privacy communication - 2/5.** None shown.
- **8 Delight and friction - 2/5.** Thumbnails with an 'MD' badge are the delight; the loud default colours and unbounded line length are friction.

### Worth matching or beating
- Rendered-page thumbnails with a clear type badge.
- Per-element colour roles (headings, code, links, quotes) as the vocabulary for theming.

### Mistakes to avoid
- A saturated, wide-measure default that fights with Finder's calm look.
- Opening the stock system Colors panel for each role - it is a modal, hard-to-preview detour.
- Blockquotes distinguished only by size, weight and colour, not by an accessible shape cue such as a bar.


## Source Code Preview (Anybox)
$4.99, macOS 13+, v1.5 updated 2026-09-01. Source: https://apps.apple.com/us/app/source-code-preview/id6759270528 (no vendor page URL in the listing).

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Light preview of App.jsx: warm off-white code surface, right-aligned plain gray gutter, host bar 'Open with Zed' | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/4c/af/2c/4caf2ca5-6dd7-d796-6d88-402094e7aae3/1.png/1600x1000bb.jpg |
| 2 | Dark mode of the same file (Monokai-like on charcoal) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/25/fb/e0/25fbe034-2b4d-5c0d-86b2-6d6f61f67b6c/2.png/1600x1000bb.jpg |
| 3 | Companion window with segmented Home / Settings / About in the toolbar; grouped rows for Appearance (Light/Dark/Auto), Font (Fira Code, 12), Wrap Lines, Line Numbers, Remember Window Size; Color Theme rows for Light and Dark | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/70/a0/83/70a08301-0437-108e-885b-4fcf091f3a60/3.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** Pure host chrome; content is a quiet, unframed code surface with generous left margin.
- **2 Content presentation - 4/5.** Fira Code at 12 (per settings), comfortable line height, plain muted gutter, warm paper-like light surface and a good dark scheme; visual hierarchy is excellent for screenshots.
- **3 Interaction and discoverability - 2/5.** No find, copy or jump; 'Wrap Lines' and 'Line Numbers' toggles live only in the companion.
- **4 States and honesty - 1/5.** Only a lazy-loading claim for huge lines in the store text; no states shown.
- **5 Companion / settings - 4/5.** Smallest sensible companion: three segmented destinations, grouped inset lists, native toggles and steppers, exactly the settings people ask for. No live preview in the screenshot, and no per-type controls.
- **6 Visual identity and native feel - 4/5.** Looks like a current macOS 26 app (rounded 20 pt window, segmented toolbar, inset grouped lists).
- **7 Trust and privacy communication - 2/5.** None shown.
- **8 Delight and friction - 3/5.** Calm and polished; limited depth.

### Worth matching or beating
- Inset grouped settings lists with native toggles and one-line labels.
- A paper-warm light surface and clean dark scheme as the default look, with ligature-capable mono at 12 pt.

### Mistakes to avoid
- No live preview next to settings that are mostly visual.
- Hiding all limits and states from users who open a huge file.


## Markdown Preview - Quick Look (Anybox)
$1.99, macOS 12+, v2.5.3 updated 2026-06-24. Source: https://apps.apple.com/us/app/markdown-preview-quick-look/id6739955340

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Preview/Source tab strip under the host bar; GitHub spec rendered in New York serif with h1 and h2 rules, blockquote bar, table | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d6/79/ad/d679adad-9352-5d37-574f-0af9f18003b2/1.png/1600x1000bb.jpg |
| 2 | Source tab: syntax-highlighted Markdown with a line-number gutter, bold headings in blue, wrapped lines continue without a number | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/ef/3c/25/ef3c257b-2bef-729a-0eea-820967db0a98/md-1.png/1600x1000bb.jpg |
| 3 | Dark mode: near-black surface, white headings, inline code chips, bold lead-ins on bullets | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/b7/46/1c/b7461c44-ee59-62cd-af91-9e63383a5a66/5.png/1600x1000bb.jpg |
| 4 | Math typesetting: inline and display equations in serif | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/45/0e/0a/450e0a7b-2a68-f0de-873e-d158ae68e354/math.jpg/1600x1000bb.jpg |
| 5 | Companion window: Home / Settings / About segmented toolbar; Font San Francisco or New York radio; font-size slider with A / A | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/15/7a/01/157a017a-a55b-6ffe-8b62-7160a8adbe12/3.jpg/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 4/5.** A slim underlined Preview | Source tab strip sits at the top of the content; selected tab in blue, a thin rule beneath - cheap, legible and keyboard-friendly.
- **2 Content presentation - 4/5.** Serif (New York) body and headings give a book-like feel; h1/h2 have rules, tables have light borders; Source view uses mono with a gutter and numbers logical lines (wrapped continuation lines carry no number) - exactly SpacePane's rule.
- **3 Interaction and discoverability - 3/5.** One mode switch only; no TOC, find or copy shown. Shortcut hints not shown.
- **4 States and honesty - 1/5.** No state, limit or truncation messaging shown; claims RTL support in text.
- **5 Companion / settings - 4/5.** Tiny companion that edits only font family and size. Honest scope, no live preview.
- **6 Visual identity and native feel - 4/5.** Native, minimal, consistent with Source Code Preview; same family look.
- **7 Trust and privacy communication - 2/5.** None shown.
- **8 Delight and friction - 3/5.** Pleasant and calm; the single most reusable idea is the tab strip.

### Worth matching or beating
- A Preview | Source tab strip inside the content area with a blue underline selection.
- Source view that numbers logical lines only (wrapped continuations unnumbered).
- Serif body option for reading-mode Markdown.

### Mistakes to avoid
- No companion preview of the type choice (San Francisco vs New York).
- Having no state or limit wording at all for a text-heavy previewer.


## Peekdown (Tim Gavin)
$4.99, macOS 15+, v3.2 updated 2026-09-30. Sources: App Store plus https://peekdown.app. The app uses WebKit for rendering (stated in screenshot 8 text).

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Quick Look of README.md: callouts with icon and coloured rule ('Any provider', warning), yellow ==highlight== marks, a copy-document icon top right and a per-code-block copy icon | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/f7/80/ca/f780ca31-b54e-e246-611e-ae0c224be927/01.jpg/1600x1000bb.jpg |
| 2 | Settings window over the app: coloured-tile sidebar (General, Quick Look, Preview, Editor, Rendering, Sidebar, Folders); rows with title and one-line helper text; dark/light background swatches plus a custom-colour wheel; classic system Colors panel | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/6b/07/69/6b076933-c00a-608d-de00-d67c4a96fe91/02.jpg/1600x1000bb.jpg |
| 3 | App window with Spaces/Recents sidebar, inline annotations (strike, comment, lock) and popover note | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/c4/de/de/c4dede6e-96a8-a381-01d3-fe5c16aaa194/03.jpg/1600x1000bb.jpg |
| 4 | Side-by-side editor with syntax highlighting and live preview: checkboxes, callout, table | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/68/81/02/688102d2-de65-2343-9e78-161c2d0cc7ce/04.jpg/1600x1000bb.jpg |
| 5 | Finder column view: Quick Look of 'Replay Buffer.md' in dark, wikilinks and tags as chips | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/98/06/cc/9806cc6b-5a74-5bab-42ad-14b2d03c820d/05.jpg/1600x1000bb.jpg |
| 6 | MDX file in Quick Look and in the app (code, table, install snippet) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/56/1d/24/561d2467-3a45-54a6-279f-839c06b25c43/06.jpg/1600x1000bb.jpg |
| 7 | Mermaid flowchart and LaTeX equation rendered in the app | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d6/eb/d7/d6ebd76a-3b48-39ee-55c5-a3ac31ecf271/07.jpg/1600x1000bb.jpg |
| 8 | Native window with tables of keyboard shortcuts rendered in the document | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/55/d3/cc/55d3ccd5-56ba-ebbe-9d5b-9aff27f9767f/08.jpg/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 4/5.** Quick Look has a tidy header-free view with a copy-document icon in the content's top-right and per-block copy icons on code blocks; no TOC or mode switch.
- **2 Content presentation - 5/5.** Most polished rendered Markdown here: GitHub-like body, callouts with icons and coloured left rules, highlight marks, tag chips, wikilinks, tables with hairline borders, Mermaid and LaTeX; dark surface is a deep navy that stays calm.
- **3 Interaction and discoverability - 3/5.** Copy affordances in Quick Look are the main interactivity; in the app there are checkboxes, annotations and a source toggle; Quick Look find or TOC not shown.
- **4 States and honesty - 2/5.** 'Annotations visible in Quick Look' and file-change notices in the app; no limit or secret states.
- **5 Companion / settings - 5/5.** Settings look like System Settings (macOS 26 idiom): coloured icon tiles in a sidebar, grouped cards, each row with a caption ('Matches your Mac. Pick Light or Dark to override it.'), swatches for background presets. Seven sections is a lot, but each is quiet.
- **6 Visual identity and native feel - 5/5.** Clearly the most current macOS visual language in the cluster.
- **7 Trust and privacy communication - 3/5.** 'Rendered offline with no plugins' in the store text; 'Native on the Mac' framing; no in-UI privacy claims.
- **8 Delight and friction - 5/5.** Delight: callouts, copy icons, 'Press Space. View Markdown. Copy Code.' headline mirroring the use case. Friction: a WebKit render pipeline conflicts with SpacePane's no-web-view rule.

### Worth matching or beating
- Copy-document and copy-block icons in the preview corner.
- Callout blocks (note, warning) as styled blocks with an icon and a coloured rule, native-rendered.
- Settings sidebar with a one-line helper caption under every row.

### Mistakes to avoid
- Using WebKit for content (not for SpacePane).
- Exposing annotation features inside Quick Look - out of scope for a read-only previewer.
- Leaving the settings view for the page background to the system Colors panel, losing contrast guidance.


## Code Peek+ (Onder Kadagan)
Free, macOS 14+, v1.0.3 updated 2026-04-10. Sources: App Store plus https://onderk.com/apps/code-peek-plus. **Caution:** the four screenshots look like generated composites with misspelled labels (for example 'Appearsnce Studio', 'Diagoestics'), so layout evidence is low confidence.

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Marketing composite: laptop on a desk with cascading Quick Look windows (README, TSV table, Python, JSON) and a purple app icon; text in the stacked windows is partly garbled | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/89/40/4a/89404a12-de10-8f7c-3dcd-979fde71dc38/01.jpg/1600x1000bb.jpg |
| 2 | Companion window 'Code Peek+' with tabs Getting Started / Appearance Studio / File Types / Diagnostics, theme dropdown (Dracula, Nord, Solarized, GitHub, VS Code Dark+, System Adaptive, Custom), and a Custom Theme card with ten colour wells | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/6a/4b/a2/6a4ba2c9-12d8-e124-961f-13ea7d2f4dc6/02.jpg/1600x1000bb.jpg |
| 3 | Finder column view with a dark Quick Look preview in the preview pane (garbled sample text) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/55/5a/fa/555afa9d-8b91-70fe-30de-a5af4747faf2/04.jpg/1600x1000bb.jpg |
| 4 | File Types tab: list of extensions with checkboxes, 'Add' field, and a code preview with minimap on the right (garbled text) | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/6a/fe/28/6afe28c3-8748-4127-d897-5f300435fc63/03.jpg/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** Cannot judge real chrome; text claims toolbar-less content with line numbers, word wrap and a minimap for long files; a minimap strip is visible at the right edge of the code in screenshot 4.
- **2 Content presentation - 3/5.** Themes named after editors (Dracula, Nord, GitHub, VS Code Dark+), ten editable token colours (Background, Text, Keyword, String, Comment, Function, Type, Number, Link, Preprocessor).
- **3 Interaction and discoverability - 3/5.** Minimap and line numbers for long files; shortcut guidance ('Control + Space') is explained in the companion per the release notes.
- **4 States and honesty - 2/5.** 'Diagnostics' tab exists; nothing else shown.
- **5 Companion / settings - 3/5.** Sidebar-ish tabs: Getting Started, Appearance Studio, File Types, Diagnostics; per-type toggles and add-your-own extension; live preview beside controls. Sound IA for SpacePane's four-section model; the screenshots are unreliable.
- **6 Visual identity and native feel - 3/5.** Neon purple/green icon and glow headlines - loud, not native in feel.
- **7 Trust and privacy communication - 2/5.** None.
- **8 Delight and friction - 3/5.** Idea: Getting Started plus Diagnostics tabs. Friction: unconvincing, possibly fabricated marketing images erode trust.

### Worth matching or beating
- A 'Getting Started' destination that explains enabling and shortcut alternatives, and a 'Diagnostics' destination.
- Ten semantic colour wells as the whole custom-theme vocabulary (no hex fields needed).

### Mistakes to avoid
- Marketing screenshots with garbled text - they read as unreal.
- Neon glow styling that clashes with Finder.


## PeekCode (NeoLabs)
Free, macOS 13+, v1.4.1 updated 2026-08-20. Sources: App Store plus https://neolabsapp.com. Interface claims English, Chinese, Japanese, Korean.

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Finder Quick Look of hello.java on a light theme: a slim caption strip 'PeekCode · java' with a Copy button; gutter; the wide content clips at the right edge | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/eb/29/38/eb29384c-c0ac-206f-d332-ac62c49c25c8/Screenshot_2026-03-23_at_19.39.53__U00282_U0029.png/1600x1000bb.jpg |
| 2 | Dark JSON preview with the same caption strip | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/92/c8/d0/92c8d09c-441c-6acd-5f70-039c959ff6d8/Screenshot_2026-03-23_at_19.41.27__U00282_U0029.png/1600x1000bb.jpg |
| 3 | Finder column view with the preview pane showing the same strip and Copy button | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/0a/85/29/0a852965-2b69-b10d-eb9c-7d70e5c6989b/Screenshot_2026-03-23_at_19.39.36__U00282_U0029.png/1600x1000bb.jpg |
| 4 | Companion window: Language popup, Light/Dark theme popups (atom-one-light/atom-one-dark), Font Menlo, size 13 pt, Show Line Numbers, two preview-limit sliders (4000 lines, 128 KB) with a limit explanation, live code preview docked below | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c3/ba/84/c3ba84a8-9a0c-9de7-dc21-24a47f1ffaf0/Screenshot_2026-03-23_at_19.40.20__U00282_U0029.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 4/5.** A slim caption strip inside the content ('PeekCode · java' left, Copy right) separates the file's language from the code and holds the one control; host chrome untouched.
- **2 Content presentation - 4/5.** Menlo 13 pt default, light gutter, syntax from 80+ themes; JSON gets formatting; long lines clip at the edge in the screenshot, with no visible horizontal scroller.
- **3 Interaction and discoverability - 2/5.** One-click Copy of the whole file; no find or jump shown.
- **4 States and honesty - 4/5.** Best honesty in the cluster: the settings text 'Files exceeding limits render only the beginning; copy still includes full content' and two limit sliders in lines and KB.
- **5 Companion / settings - 3/5.** One compact window: popups, a slider, a checkbox, plus a live preview of a Swift snippet under the controls. No sidebar, no per-type controls shown; theme names are raw ids.
- **6 Visual identity and native feel - 3/5.** Plain, readable, native widgets; unremarkable.
- **7 Trust and privacy communication - 3/5.** 'Lightweight, ad-free, no code upload' in the store text only.
- **8 Delight and friction - 3/5.** Delight: live preview in the settings. Friction: raw theme ids; clipped lines.

### Worth matching or beating
- Preview limits expressed as lines and KB with a sentence that copy still gets the full content.
- A slim caption strip with language label and Copy.

### Mistakes to avoid
- Raw theme ids as user-facing names.
- Clipping long lines without a scroller or wrap hint.


## Markdown Peek (Michael Thingmand)
Free, macOS 15.5+, v1.8 updated 2026-09-25. Sources: App Store plus https://markdownpeek.com. Ten interface languages claimed.

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | App window: GitHub-style document with emoji headings; a </> toggle icon at the top right of the title bar | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/11/c7/e0/11c7e0dd-89d5-dca2-a67b-01fe09fbe174/resized-1-hero.png/1600x1000bb.jpg |
| 2 | Code blocks in light grey cards, ordered and unordered lists | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/53/c7/19/53c719b1-a88f-34a3-2065-689042652da2/resized-2-code.png/1600x1000bb.jpg |
| 3 | Dark source view: plain monospaced Markdown, an eye icon top right to flip back | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/a0/74/03/a0740319-ee03-22eb-c2c3-4144a49232c2/resized-4-dark.png/1600x1000bb.jpg |
| 4 | Rich content: tables with emoji checks, blockquote | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/1c/31/84/1c318440-5339-40f4-8da2-22e1b5550b65/resized-3-feature.png/1600x1000bb.jpg |
| 5 | KaTeX equation and Mermaid flowchart in the preview | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/56/46/55/564655b5-93e5-250b-90a2-0864bf29b06c/resized-6-math-mermaid.png/1600x1000bb.jpg |
| 6 | Quick Look host window (Danish 'Åbn med Markdown Peek' button) with rendered preview; strikethrough still shown as ~~tildes~~ | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/15/fe/31/15fe3143-f729-e27f-a118-a0d3db11bab8/resized-5-quicklook.png/1600x1000bb.jpg |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** In the app a minimal title bar and one 24 px icon toggle; in Quick Look the host chrome only.
- **2 Content presentation - 4/5.** Clean GitHub-like rendering with 700-900 px measure, h1/h2 rules, rounded code cards; Mermaid and math; source view is plain mono without gutter.
- **3 Interaction and discoverability - 3/5.** Spacebar flips between rendered and raw - a memorable shortcut; copy as Markdown on selection (release notes).
- **4 States and honesty - 1/5.** No limit or error states shown. The Quick Look screenshot shows unrendered '~~Strikethrough~~', a visible difference from the app view.
- **5 Companion / settings - 1/5.** n/s - no settings window shown.
- **6 Visual identity and native feel - 4/5.** Looks native, light, unfussy; localised host button visible.
- **7 Trust and privacy communication - 3/5.** Store text: sandboxed, no data collected, no telemetry; none shown inside the UI.
- **8 Delight and friction - 3/5.** Delight: Space to flip rendered/raw. Friction: inconsistent rendering between app and Quick Look.

### Worth matching or beating
- A single-key flip between rendered and source (and the icon that reflects the current mode).
- 'Copy as Markdown' that preserves source when copying rendered text.

### Mistakes to avoid
- Different renderers in the app and Quick Look that disagree on basic syntax.
- No settings or state surface at all.


## Glance (Samuel Meuli) - archived reference
Archived 2020-era repo; macOS 10.15+. Source: https://github.com/samuelmeuli/glance and the App Store id1513574319.

### Screenshot inventory
| # | What it shows | URL |
|---|---|---|
| 1 | Marketing montage: dark Jupyter notebook preview, Swift source, and archive tree | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Listing/Screenshots/Screenshot1.jpg |
| 2 | Source code: dark charcoal, centred filename, 'Open with Xcode' and share buttons, scrollbar, no gutter | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Assets/Screenshots/ScreenshotSourceCode.png |
| 3 | Markdown: dark GitHub-like page with rules under h1/h2, code card, inline code chip | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Assets/Screenshots/ScreenshotMarkdown.png |
| 4 | Archive: sortable tree with Name / Date Modified / Size and a footer 'Compressed / Uncompressed / Compression ratio', 'Uncompress' button | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Assets/Screenshots/ScreenshotArchive.png |
| 5 | Jupyter: execution counters '[2]:' in a left gutter, rendered LaTeX, DataFrame table | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Assets/Screenshots/ScreenshotJupyterNotebook.png |
| 6 | TSV: zebra-striped table, truncated cells with an ellipsis, column headers; striped empty rows continue below | https://raw.githubusercontent.com/samuelmeuli/glance/master/AppStore/Assets/Screenshots/ScreenshotTSV.png |

### Observations by rubric dimension (all observed in marketing material)
- **1 Preview anatomy - 3/5.** Host chrome with centred title; the host adds a type-specific button ('Open with Xcode', 'Uncompress', 'Open with Numbers'); content in a 1 px bordered inset.
- **2 Content presentation - 3/5.** Consistent family: one dark charcoal surface and pink/teal syntax, GitHub-like Markdown, Jupyter with In/Out counters. No line numbers.
- **3 Interaction and discoverability - 1/5.** No interaction beyond scrolling.
- **4 States and honesty - 2/5.** Footer stats on archives (compressed, uncompressed, ratio) are informative; the README FAQ honestly says large files are skipped and remote assets are blocked.
- **5 Companion / settings - 1/5.** n/s - no settings UI; the FAQ says the app is a thin host.
- **6 Visual identity and native feel - 3/5.** Pleasantly consistent for its time; dated now.
- **7 Trust and privacy communication - 3/5.** README FAQ explains why a network-client entitlement exists despite local-only data.
- **8 Delight and friction - 2/5.** Delight: consistent dark family. Friction: no customisation; no search; no copy.

### Worth matching or beating
- Footer summary stats on a container preview (compressed, uncompressed, ratio).
- A consistent surface and hierarchy across code, Markdown, notebook, table and archive.

### Mistakes to avoid
- No settings or states at all.
- A web-view architecture whose entitlement needs a FAQ to justify.


## Cluster synthesis

### Patterns most apps share (table stakes)
- A dark and a light syntax theme following system appearance, with a named theme list (nine of twelve show one).
- Line numbers as an optional dim, right-aligned column; wrapped continuation lines are rarely numbered (Anybox's Markdown source tab is the clear example).
- GitHub-like Markdown: h1/h2 rules, grey inline-code chips, rounded code cards, hairline tables.
- A companion app that is a thin settings shell with three or fewer destinations and a first-run line telling you to enable the extension in System Settings > Quick Look.
- Almost no in-preview chrome beyond what Quick Look itself shows ('Open with X', share).

### Patterns only one or two apps have (users notice them)
- In-preview search, jump to line, TOC and shortcut labels on floating pills (Peek only).
- A slim caption strip with language and Copy (PeekCode) and per-block/whole-document copy icons (Peekdown).
- A Preview | Source tab strip inside the content (Anybox Markdown); a spacebar flip (Markdown Peek).
- Live settings preview, inherit/override checkboxes and a file-inquiry diagnostic (sbarex).
- Theme picker with sample thumbnails (PreviewCode); honest limit sentence (PeekCode).
- Content thumbnails for source and Markdown (smittytone pair).
- Rendered-page callouts and Mermaid/math with offline rendering (Peekdown).

### Where every app in this cluster is weak (our opening)
- Nobody shows what was hidden or truncated *in the preview*: no 'secrets hidden', no 'showing first N lines of M', no 'binary or unsupported' state. PeekCode only says it in settings.
- No app addresses provider conflicts in the UI; only sbarex's FAQ and Peek's eyes mark come close. Nobody has a status line like 'saved here; macOS chooses the provider'.
- No accessibility story is visible: no high-contrast variant, no VoiceOver wording, no reduced-motion choice.
- Settings do not teach: no first-run walkthrough with an annotated System Settings image and an open-pane button in the same window (sbarex has an image only in the README; QLMarkdown has the button).
- No app presents a per-type on/off list tied to what Quick Look will do, apart from Code Peek+'s extension list (low confidence).
- Languages: PeekCode and Markdown Peek claim a few interface languages and Anybox Markdown claims RTL support; none shows localisation or RTL in screenshots.

### Scorecard (1-5; n/s = not shown)
| App | 1 Anatomy | 2 Content | 3 Interact. | 4 States | 5 Companion | 6 Identity | 7 Trust | 8 Delight |
|---|---|---|---|---|---|---|---|---|
| Peek | 4 | 4 | 5 | 2 | n/s | 3 | 2 | 4 |
| Syntax Highlight | 2 | 4 | 2 | 3 | 4 | 2 | 2 | 3 |
| QLMarkdown | 3 | 4 | 2 | 3 | 3 | 3 | 4 | 3 |
| PreviewCode | 3 | 3 | 1 | 2 | 3 | 3 | 2 | 3 |
| PreviewMarkdown | 2 | 2 | 1 | 2 | 3 | 3 | 2 | 2 |
| Source Code Preview | 3 | 4 | 2 | 1 | 4 | 4 | 2 | 3 |
| Markdown Preview (Anybox) | 4 | 4 | 3 | 1 | 4 | 4 | 2 | 3 |
| Peekdown | 4 | 5 | 3 | 2 | 5 | 5 | 3 | 5 |
| Code Peek+ (low confidence) | 3 | 3 | 3 | 2 | 3 | 3 | 2 | 3 |
| PeekCode | 4 | 4 | 2 | 4 | 3 | 3 | 3 | 3 |
| Markdown Peek | 3 | 4 | 3 | 1 | n/s | 4 | 3 | 3 |
| Glance | 3 | 3 | 1 | 2 | n/s | 3 | 3 | 2 |

### Ten ranked recommendations for SpacePane
1. **Native in-preview find and a jump-to-line HUD, with shortcut labels on a small floating control.** Why: Peek is the only app scoring 5 on interaction; shortcut labels on floating pills (screenshot 4) make them discoverable. Rules: native AppKit find bar, read-only, localized labels, VoiceOver names, no new windows. Cost M.
2. **A slim bottom status strip inside source, outline and Markdown previews: format name, logical line count, and an honest limit sentence ('Showing the first 4,000 lines of 52,310. Copy copies everything shown').** Why: PeekCode's limit sentence and QLMarkdown's render footer are the only state messaging in the cluster; every app is weak on partial results. Rules: typed finding counts only, no source values, localized plurals. Cost S-M.
3. **Mode control as a Preview | Source underline tab strip inside the content area for Markdown (and Tree | Raw for JSON/YAML).** Why: Anybox's tab strip is the clearest, lowest-chrome switch in the cluster; Markdown Peek's spacebar flip shows users want a one-key switch. Rules: keyboard accessible, state preserved across files, source view keeps logical line numbers. Cost S-M.
4. **Settings preview next to controls with a sample-format popup and light/dark toggle, plus visible 'inherited vs customised' per-field state.** Why: sbarex has the best live settings model but hides it in a jargon-heavy UI; our Theme page already has a live preview. Rules: samples synthetic, stay local, one window, no shell or CSS fields. Cost M.
5. **A diagnostic file check in the companion (Developer Mode): drop a file to see its resolved type, which catalog format applies, whether that format is enabled and what was concealed.** Why: sbarex's Inquiry window and green 'Supported and handled' dot are praised in the README for troubleshooting. Rules: word it as 'SpacePane supports this type', never 'Finder uses SpacePane'; drop uses the existing one-file contract. Cost S-M.
6. **Copy affordances: copy-document and per-code-block icons in the preview corner, plus 'Copy as Markdown/source' semantics.** Why: Peekdown, PeekCode and Markdown Peek each ship one; the copy path matters for code. Rules: copied text must follow the concealed safe text; label what is copied when secrets are hidden. Cost S.
7. **Markdown TOC rail for long documents (appears above a width threshold; current section highlighted; collapsible).** Why: Peek's rail is the strongest rendered-Markdown interaction; Unfold and PeekCode claim it. Rules: native outline view, selection and expansion metadata for accessibility, hidden in narrow Quick Look windows. Cost M-L.
8. **First-run and troubleshooting screen in General: annotated System Settings illustration (localised), an 'Open Quick Look extensions' button and honest status text.** Why: sbarex/QLMarkdown teach this with a README image and a button, PreviewCode with 'log out and run once more'; none is in-app, annotated and honest. Rules: never claim enablement or routing we cannot read; 14 languages. Cost M.
9. **Gutter and rendering details: dim, right-aligned, zero-padded to the widest number; emphasise the selected line's number (Peek); keep numbers on logical lines only; blockquotes marked by a bar not only colour.** Why: PreviewCode's zero-padding, Peek's selection emphasis and Anybox's logical numbering are small tells of polish; PreviewMarkdown's colour-only quotes are an accessibility lapse. Rules: gutter outside selectable text. Cost S.
10. **Content thumbnails for source and Markdown with a type badge, redacting secrets and skipping sensitive types.** Why: PreviewCode/PreviewMarkdown's miniature-content thumbnails with an 'MD' badge are the most visible win in Finder icon view. Rules: no sensitive content in thumbnails; privacy review of what is drawn; sandbox time budget. Cost M-L.

