# App Store listing research: how Quick Look apps present and rank

Researched 2026-10-10 (Europe/Istanbul) for [the listing content](../release/app-store-listing.md). The
[competitor landscape](2026-10-05-competitor-landscape.md) compares features; this record covers what it left
out: names, subtitles, keywords, descriptions, screenshots, localization and Apple's rules for each field.

## Method and limits

- **Sources.** Apple's public iTunes Search and Lookup API (`entity=macSoftware`), the store's own web search
  and product pages read in a browser, Apple's developer and App Store Connect help pages, and Apple's
  trademark list and guidelines. Five parallel researchers each covered one area; the lead read product
  pages, reviews and screenshots.
- **Labels.** "Observed" means read from the source on the research date. "Apple" means quoted from an Apple
  page. "Third-party" means a claim from an ASO vendor that Apple does not document. "Judgement" is ours.
- **No volume data exists.** Apple publishes no Mac search volumes and Apple Ads does not cover the Mac App
  Store. Demand is inferred from store autocomplete and from how users phrase the need. Autocomplete is
  iPhone-centric, so a missing suggestion proves nothing.
- **API order approximates store ranking.** The top 12 for three head terms were also read from the store's
  web search, and agreed closely.
- **Ratings are unusable.** The API returns zero for nearly every Mac app. All 24 product pages read (11 by
  the lead, 13 by a researcher) said the app has too few ratings to show a score.
- **Subtitles** are not in the API. About 30 were read from product pages and the web search; the rest are
  unknown.
- **Not done.** No Reddit or Hacker News thread was opened. Bangla was not researched. Features are vendor
  claims, as in the landscape record.

## Key findings

1. **"Quick Look" is the head term, and it is winnable.** 11 of the top 12 store results for it carry the
   phrase in the name or subtitle, and 9 or 10 of the API top 10 are real Quick Look apps. They are small and
   mostly new: 66 of 99 specialists were first released in 2026.
2. **Placement in the subtitle is enough to rank.** "Folder Preview", with the phrase only in its subtitle,
   was second for "quick look". 7 of 12 specialist subtitles read contain the phrase while their names don't.
3. **"Quick Look" is not on Apple's trademark list.** Finder, Mac, macOS, Spotlight and Xcode are. Apple's
   guidelines allow an Apple word mark in a referential phrase ("for", "compatible with") that is less
   prominent than the product's own name, and bar it as part of a product name. No documented rejection
   for the phrase was found. Absence from the list is not legal clearance.
4. **Spacing does not matter; word choice does.** "quick look" and "quicklook" share 35 of their top 50
   results. "preview", "previewer" and "viewer" return different apps and are not interchangeable.
5. **Demand is shaped "<format> viewer".** Autocomplete completes json, csv, sqlite, yaml, stl and step with
   "viewer". No Quick Look app is in the top 10 for any of those queries; editors and standalone viewers own
   them.
6. **Most direct competitors waste their subtitles.** "Beautiful Previews", "Readable file previews" and
   "Better previews. Press Space." carry no search term. Four of the fourteen read name a format. The
   newest rival, Gander (2026-10-07), already uses the efficient shape: "Gander: Quick Look Preview" with
   the subtitle "Markdown, Mermaid, JSON, YAML".
7. **Nobody has ratings.** A visible score is unclaimed ground, including against a competitor on sale
   since 2020.
8. **Screenshots follow one template.** A real preview window on a plain background under one short benefit
   headline. The newest leader ships three; the broadest ships ten.
9. **The safety angle is unclaimed in store copy.** Local processing and no account are standard. Two
   competitors mask secrets and neither leads with it. None of the 151 descriptions searched on 2026-10-05
   mentions hidden-character detection, archive risk notes or notebook health.
10. **Long-tail gaps match SpacePane's unusual formats.** "iges" and "stp" return fewer than 20 Mac apps each.
    No Quick Look app mentions IGES; two preview STEP. No specialist names CSV, notebooks, subtitles, draw.io
    or certificates in its name or the subtitles read.
11. **The store accepts 12 of the app's 14 languages.** Kurmanji and Hausa are not offered. English (U.K.) is
    the default or additional store language in Türkiye, India, Indonesia, Nigeria, Germany, France, Brazil
    and Russia.
12. **Mac apps get few page tools.** Custom product pages, product page optimization and in-app events are
    iPhone and iPad features. Promotional text and featuring nominations do apply.

## Direct competitors on the store

U.S. storefront. Name and subtitle lengths in characters. "Shots" is the number of Mac screenshots.

| App | Name | Subtitle | Category | Price | Updated | Shots | Description |
|---|---|---|---|---|---|---|---|
| QuickLook Pro | QuickLook Pro: File Preview (27) | Better previews. Press Space. (29) | Developer Tools / Utilities | $3.99 | 2026-09-22 | 3 | 1,644 |
| Unfold | Unfold - Quick Look Previews (28) | View code, Markdown, and more (29) | Utilities / Developer Tools | $9.99 | 2026-09-12 | 10 | 3,232 |
| Super Quick Look | Super Quick Look (16) | Readable file previews (22) | Utilities / Productivity | $3.99 | 2026-09-15 | 6 | 1,751 |
| LookQuick | LookQuick (9) | Quick Look for Everything (25) | Utilities / Developer Tools | Free + IAP | 2026-10-07 | 6 | 3,999 |
| QuickestLook | QuickestLook (12) | Beautiful Previews (18) | Developer Tools / Utilities | Free + IAP | 2026-05-01 | 7 | 2,594 |
| iPreview | iPreview: Enhanced Quick Look (29) | Folder, Code, Markdown, Zip (27) | Productivity / Utilities | $6.99 | 2026-10-03 | 8 | 3,178 |
| Peek | Peek — A Quick Look Extension (29) | Copy, Search, Jump, & more (26) | Developer Tools / Productivity | $7.99 | 2022-04-02 | 6 | 2,205 |
| GoodQuickLook | GoodQuickLook (13) | All-in-one preview extension (28) | Productivity / Utilities | Free + IAP | 2026-06-13 | 5 | 746 |
| Simple Quick Look | Simple Quick Look (17) | Simplest Quicklook for text (27) | Utilities / Productivity | Free | 2026-04-26 | 5 | 837 |
| Source Code Preview | Source Code Preview (19) | Quick Look Source Code & JSON (29) | Developer Tools / Utilities | $4.99 | 2026-09-01 | 3 | 965 |
| Gander | Gander: Quick Look Preview (26) | Markdown, Mermaid, JSON, YAML (29) | Developer Tools | $1.99 | released 2026-10-07 | 10 | not counted |
| Looq | Looq: Preview Files (19) | A better look at your files. (28) | Developer Tools / Utilities | $12.99 | 2026-09-29 | 8 | 1,411 |
| Syntax Look | Syntax Look (11) | Quick Look for Source Code (26) | Developer Tools / Utilities | $2.99 | 2026-09-09 | 6 | 2,534 |
| Peeka | Peeka - Ultimate QuickLook App (30) | Developer Tools (15) | Developer Tools / Utilities | Free + IAP | 2026-10-03 | 3 | 2,131 |

What the table shows:

- **Names.** Across the 19 all-in-one Mac apps profiled (these 14 plus Glance, PeekCode, Code Peek+,
  FinderPeek and QuickLook Video), 12 contain "Quick Look" or "QuickLook". Eight are a brand alone and use
  8 to 17 of the 30 characters. None names a format such as JSON, Markdown or 3D.
- **Subtitles.** Of the 14 above: four are slogans, four are vague ("for Everything", "All-in-one",
  "Simplest", a bare category name), four name formats (Gander, iPreview, Source Code Preview and, partly,
  Unfold), one names a use (Syntax Look) and one lists actions (Peek).
- **Categories.** Developer Tools is primary for eight of the 14, Utilities for four, Productivity for two.
  Every app launched since September chose Developer Tools.
- **Descriptions.** 746 to 3,999 characters. The 2026 launches that read well (QuickLook Pro, Syntax Look,
  Peeka, Gander) and Unfold share one structure in 1,600 to 3,300 characters: an outcome sentence about the
  Space bar, grouped format lists, a privacy block, the exact System Settings path, stated limits. The
  weak ones run under 1,000 characters with a generic hook and no setup; Peek opens with what it cannot do.
  "Local, no upload" appears in 9 of 19.
- **Upkeep.** Ten of the 14 were released or updated in the last six weeks. Peek has not changed since
  2022.
- **Closest new rival.** Gander ($1.99, macOS 15+) claims Markdown with Mermaid, JSON trees, read-only
  SQLite, masked `.env` values with a reveal switch, thumbnails and a copy button. Its first screenshot
  reads "Press Space — take a gander" and another "Secrets — hidden until you choose". SpacePane's copy
  should not lean on "Press Space" or on masking alone to stand apart.
- **App languages.** Most are English-only. Source Code Preview declares 11 languages, GoodQuickLook 10,
  iPreview 6, Unfold 4. None declares Turkish, Indonesian, Bangla, Hausa or Kurmanji.
- **Translated store pages are rare.** Each of 19 apps was queried in ten storefronts. Five have any
  translated store text: Unfold (Japan, China), iPreview (Germany, Japan, China), Gander (Spain), and
  description only for PeekCode (Japan) and Peeka (China). None has translated text for Türkiye, Brazil,
  France, Russia, Indonesia or India. Declared app languages do not predict it: three apps declaring 10 or
  11 languages have English-only pages everywhere. Translated names use Apple's local name for the feature
  (Übersicht, クイックルック, 快速查看, Vista rápida).
- **Accessibility labels.** iPreview and Unfold declare Dark Interface. Peek, GoodQuickLook, Simple Quick
  Look and Source Code Preview declare nothing.
- **App Privacy.** iPreview and Simple Quick Look show "Data Not Collected". GoodQuickLook collects
  diagnostics.

### Screenshots

First screenshot of each, viewed on 2026-10-10:

| App | Headline | Composition |
|---|---|---|
| QuickLook Pro | A README, ready to read. | Light background. Small category label above the headline, one supporting line, a Finder window beside the preview, a "Select a file in Finder → Space" hint |
| Unfold | Preview almost anything | Dark gradient. Three overlapping preview windows (code, Markdown with a Mermaid diagram, an ebook) |
| Super Quick Look | A clearer Quick Look. | Light background. Two supporting lines and the app's own status window |
| LookQuick | QuickTime just learned a lot of new tricks. | Dark. A video player window and a list of video formats |
| QuickestLook | From source to styled, instantly | A list of feature cards in a laptop frame; little real preview shown |
| Source Code Preview | Syntax Highlight for 50+ Languages | A system wallpaper with one code preview window |
| Gander | Press Space — take a gander | Light background. One supporting line, a Finder window beside a rendered README with a diagram |

Every one pairs a real window with a headline. The clearer ones (QuickLook Pro, Source Code Preview) show one
file type per image and say what it is. QuickLook Pro's second and third are "Look inside. Leave it zipped."
and a code preview: one idea each.

### What reviewers say

Only two of the pages read had written reviews (iPreview, Peek). Paraphrased:

- People arrive because older Quick Look plug-ins stopped working after a macOS upgrade, and they name the
  one they are replacing.
- They ask for text selection in the preview and for a way to treat unusual extensions as plain text.
- One buyer's STL files lost Apple's own preview when the app took the type over, and they uninstalled it.
- A developer bought one app because the previous tool had no YAML support.
- Praise goes to small things: Markdown contents, dark mode, remembered scroll position, no menu-bar icon,
  no background processes left running.
- One reviewer calls $7.99 a lot for syntax highlighting when free tools exist, while another says it is
  worth it.

For SpacePane this supports saying plainly what macOS decides, pointing at the per-type switches, and
naming extension-free text files and selectable text.

## Specialists and naming vocabulary

166 searches returned 2,314 Mac apps, of which 99 are single-purpose Quick Look apps (the earlier survey
estimated about 70).

| Word in the app name | Apps (of 99) |
|---|---|
| Look (incl. "Quick Look", "QuickLook") | 29 |
| Preview / Previewer | 27 |
| "Quick Look" or "QuickLook" as a phrase | 23 (15 spaced, 8 fused) |
| Viewer | 21 |
| Markdown | 17 |
| Folder | 13 |
| Peek | 13 |
| 3D | 5 |
| JSON | 3 |
| Code | 2 |
| Finder, Syntax | 1 each |
| STEP | 0 |

- **Name shapes.** About 66 are plain descriptors ("Folder Quick Look"), 25 are "Brand: Descriptor", 8 are
  a brand alone.
- **Prices.** Free 34. Paid: up to $1.99 22, $2 to $4.99 29, $5 to $9.99 9, $10 and over 5. The common paid
  points are $1.99, $2.99 and $4.99.
- **App languages.** 51 are English-only, 33 declare German and 29 Japanese.
- **Crowded.** Markdown (17 names) and folders and archives (20).
- **Thin.** IGES (no Quick Look app; four standalone viewers at $4.99 to $24.99), STEP (two Quick Look
  apps), MIDI (one player). No specialist names CSV, notebooks, subtitles, draw.io or certificates.

## Search terms

U.S. storefront, 86 queries. "Quick Look apps" counts real preview extensions in the API top 10.

| Query | Quick Look apps in top 10 | Who owns the results |
|---|---|---|
| quick look / quicklook | 10 / 9 | Quick Look apps |
| quick look plugin / quick look extension | 9 / 8 | Quick Look apps |
| quicklook plugin, ql plugin | 0 | Unrelated; the fused two-word form breaks |
| file preview / preview files | about 7 | Quick Look apps |
| folder preview | 6 | Folder specialists |
| markdown preview | about 5 | Markdown previews |
| code preview | about 4 | Code previews |
| finder preview | about 4 | Mixed |
| json preview | 3 | Mixed |
| preview | about 6 | PDF readers first |
| markdown, json, yaml, toml | 0 or 1 | Editors |
| json viewer, csv viewer, sqlite viewer, xml viewer, plist viewer | 0 | Editors and standalone viewers |
| syntax highlight | 0 | Text editors |
| step viewer, stl viewer, cad viewer, 3d viewer | 0 | Standalone viewers ("stp" 18 results, "iges" 17) |
| zip viewer, rar, 7z | 0 | Extractors |
| epub reader, comic reader, midi player | 0 | Readers and players |
| finder extension | 0 | Sync and context-menu tools |
| thumbnail | 0 | YouTube thumbnail makers |

Variants, as apps shared between two result sets (top 10 / top 50):

| Pair | Shared | Reading |
|---|---|---|
| quick look / quicklook | 7 / 35 | Equivalent; use one form |
| syntax highlight / syntax highlighting | 7 / 35 | Equivalent |
| thumbnail / thumbnails | 7 / 25 | Equivalent |
| preview / previews | 4 / 20 | Partly different. Apple says plurals count as duplicates |
| preview / previewer | 0 / 8 | Different intent |
| viewer / view | 2 / 8 | Different intent |

Autocomplete completes: json, csv, sqlite, yaml (viewer, editor); markdown (reader, editor); stl viewer;
step viewer and "iges & step viewer"; 3d viewer; epub reader; code viewer; code preview; parquet viewer;
subtitles viewer; midi player; jupyter notebook. It offers nothing relevant for "quick look", "file prev",
"finder ext" or "syntax h".

How users phrase it, from forum titles and articles: "Quick Look plug-in" for the old `.qlgenerator` format,
"Quick Look extension" for the new one, usually with the file kind and often with "Sequoia"
([Eclectic Light](https://eclecticlight.co/2024/10/31/how-sequoia-has-changed-quicklook-and-its-thumbnails/),
[Michael Tsai](https://mjtsai.com/blog/2024/11/05/sequoia-no-longer-supports-quicklook-generator-plug-ins),
[TidBITS Talk](https://talk.tidbits.com/t/what-are-your-favorite-quick-look-extensions/29323)).

Priority (judgement from the above):

- **Must carry in name or subtitle:** quick look, preview, json, markdown. Also code, once source code is
  seen to open in SpacePane.
- **Keyword field:** viewer, syntax, highlight, file, plugin, csv, sqlite, yaml, toml, plist, xml, jupyter,
  zip, rar, step, iges, stl, cad, epub, srt.
- **Skip:** previewer, finder, thumbnail, folder, source, log, diff, hex, space bar, and the names of other
  apps and old open-source plug-ins (guideline 2.3.7).

### Other storefronts

English leads everywhere. For "quick look", each storefront shares 4 to 6 of its top 10 with the U.S. and 25
to 41 of the top 50. Format words stay in English in results and autocomplete.

| Storefront | Apple's name for Quick Look | Does that name return Quick Look apps? | Local terms that return relevant apps |
|---|---|---|---|
| Germany | Übersicht | No (calendars, planners) | Vorschau, Markdown Vorschau, Dateivorschau |
| France | Coup d'œil | Mostly not | aperçu, aperçu fichier, visionneuse |
| Spain, Mexico | Vista Rápida | Yes | vista previa, visor, visor de archivos |
| Brazil | Visualização Rápida | Thin (5 results) | prévia de arquivos, visualizador de arquivos |
| Japan | クイックルック | Yes | クイックプレビュー, ファイルプレビュー, ビューア |
| China mainland | 快速查看 | Yes | 空格预览, 文件预览, 代码高亮, 查看器 |
| Türkiye | Göz At | Thin (8 results) | önizleme, dosya önizleme, dosya görüntüleyici |
| Russia | Быстрый просмотр | Mostly photo apps | предпросмотр, просмотр файлов |
| Indonesia | Lihat Cepat | No (1 result) | pratinjau, pratinjau cepat, penampil |
| India | क्विक लुक | No | None; Hindi queries are thin, English behaves as in the U.S. |

Apple's names are from its localized support page "View and edit files with Quick Look on Mac"
(`support.apple.com/<locale>/guide/mac-help/mh14119/mac`).

## Apple's rules, by field

| Field | Limit | Indexed for search? | Rules that matter here |
|---|---|---|---|
| App name | 30 characters | Yes | Unique; no prices; no other apps' names |
| Subtitle | 30 characters | Yes | No references to other apps, no unverifiable claims |
| Keywords | 100 bytes, comma-separated, no spaces | Yes | Don't repeat name, subtitle or category words; plurals count as duplicates; each keyword longer than two characters; no other apps' or companies' names |
| Primary and secondary category | | Yes | Primary must match the category set in Xcode |
| Promotional text | 170 characters | No (Apple says so) | Can change without a new version |
| Description | 4,000 characters, plain text | Not listed by Apple | Must be accurate (2.3) and disclose the extensions (4.4) |
| What's New | 4,000 characters | | Must describe significant changes (2.3.12) |
| Screenshots | 16:10; 1280×800, 1440×900, 2560×1600 or 2880×1800; 1 to 10; no transparency | Up to three show in search results | Show the app in use; text overlays allowed (2.3.3); fictional data only (2.3.9); no prices (2.3.7) |
| App previews | Up to 3, landscape | Shown before screenshots | Screen capture of the app only (2.3.4) |

Other points, each from an Apple page read on 2026-10-10:

- **Search.** "Search results are based on a number of factors, including text relevance (matches for your
  app's title, subtitle, keywords, and primary category), as well as user behavior."
  ([App Store search](https://developer.apple.com/app-store/search/)). The same page says tags shown in
  search are generated by language models from the metadata, and that accessibility labels can be used in
  queries.
- **The keyword limit** is "100 bytes" in the App Store Connect reference and "100 characters" on the search
  page. They agree for ASCII. For other scripts, budget in bytes.
- **Trademarks.** The [trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
  has Finder, Mac, macOS, Spotlight, Xcode and five "Quick…" marks (QuickTime, QuickDraw, QuickPath,
  QuickTake, QuickType), not Quick Look. The
  [third-party guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
  allow a referential phrase and ask for an attribution line without trademark symbols outside the U.S.
- **Guideline 5.2.5** names Finder as an interface an app must not resemble. SpacePane's own window does
  not; its previews appear inside Apple's Quick Look.
- **Localizations** accepted include all four English variants, Turkish, German, French, Simplified Chinese,
  Japanese, Hindi, Russian, Indonesian, Bangla, both Portuguese and both Spanish variants
  ([list](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)).
  No Kurdish and no Hausa.
- **Not for Mac:** custom product pages, product page optimization, in-app events. Apple Ads' pages do not
  mention the Mac. Featuring nominations apply, with two weeks' notice.
- **Accessibility labels** are per device and voluntary for now. Declaring one means every common task works
  with that feature. Larger Text is not offered for Mac.
- **Price wording.** 2.3.7 bars prices in names, subtitles, screenshots and previews. It does not mention
  the description.

Third-party only, unverified for the Mac: that a storefront indexes keywords from its additional store
languages (for example Spanish (Mexico) in the U.S.), and that the description or screenshot text is
indexed.

Unverified on the research date: how an Apple-silicon-only app is labelled on the page, the length limits
for Mac app previews, and whether any app has been rejected for "Quick Look" in its name.

## What this means for the listing

- Put "Quick Look" in the name in Apple's referential form, with fallbacks ready.
- Spend the subtitle on formats proven to open in SpacePane, since competitors spend theirs on slogans.
- Put "viewer" in the keywords so every format in the subtitle also answers "<format> viewer".
- Use long-tail CAD terms while they are thin, if IGES and STEP ship.
- Lead the description with the Safety Lens and state the routing limit before a reviewer does.
- Ship seven to ten captioned screenshots, one idea each, the first three telling the whole story.
- Launch in English (U.S. and U.K.); add store languages as the app's translations are reviewed. A
  translated page would have no translated competitor in six of the ten storefronts checked.
- Treat a visible rating as a goal in its own right.
