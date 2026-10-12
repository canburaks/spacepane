# App Store listing content

Drafted 2026-10-10 for SpacePane 1.0. Paste-ready text for the Mac App Store product page, with the
reasoning kept short and the evidence in
[the listing research](../market/2026-10-10-app-store-listing-research.md). Review notes, privacy answers and
the archive steps stay in [app-store-submission.md](app-store-submission.md).

Brought into this repository on 2026-10-10 from the working tree of the sibling `prev` checkout, where it
was drafted. Two changes were made on the way: the description gained the closing Open CASCADE paragraph
that [app-store-submission.md](app-store-submission.md) requires while STEP and IGES ship, and decision 1
was reworded, because this repository's worksheet records no rule against "Quick Look" in the name. This
file supersedes the name, subtitle, keywords, promotional text and description in
[store-listing/listing.en.md](store-listing/listing.en.md); the App Store Connect answers in
[store-listing/app-store-connect-worksheet.md](store-listing/app-store-connect-worksheet.md) still apply.

**Status: entered as a draft, not submitted (updated 2026-10-12).** On 2026-10-10 the English (U.S.) and
English (U.K.) text below was entered in App Store Connect for version 1.0.0 and saved; see
[What App Store Connect holds](#what-app-store-connect-holds). Build 1.0.0 (1) was uploaded on 2026-10-10 and
will not be submitted; build 2 is being prepared. Nothing has been added for review. Decisions 1, 3 and 5
are taken; decision 2 and the validation gate are open (next two sections), and decision 4 is not a copy
decision. The text below describes build 2: it says 12 color schemes, which the text stored in App Store
Connect does not yet say. Prices, availability and the effective store text live in App Store Connect; this
file is the intended copy, not a second source of truth.

Every length below was counted by script: names and subtitles in characters (limit 30), keyword fields in
UTF-8 bytes (limit 100), promotional text in characters (limit 170), descriptions in characters (limit 4,000).

## Decisions for the owner

| # | Decision | Recommendation | Why |
|---|---|---|---|
| 1 | Use "Quick Look" in the app name? The earlier draft in [store-listing/listing.en.md](store-listing/listing.en.md) kept the name `SpacePane` and used the phrase only in the subtitle. | Yes, as `SpacePane for Quick Look`. **Decided 2026-10-10:** the owner saved this name in App Store Connect. | "Quick Look" is the category's head term: 11 of the top 12 store results for it carry the phrase in their name or subtitle. 12 of the 19 direct all-in-one competitors and 23 of 99 specialist preview apps have it in the name. It is not on Apple's trademark list (Finder, Mac and macOS are), and "for" is the referential wording Apple's guidelines allow. No rejection for it was found, and none was ruled out. Fallbacks B and C are below if App Review objects. |
| 2 | Do IGES and STEP ship in 1.0 (decision 027 D20, OCCT licence)? | Not a copy decision. | **Open.** The legal review of the source-offer route (D20) has no recorded outcome; nothing here states or implies clearance. If they don't ship, apply the "no CAD" swaps below. |
| 3 | Which languages ship (D22: reviewed languages only)? | Publish English (U.S.) and English (U.K.) at launch. Add each other store language when its app translation is reviewed. | **Taken (owner rule "only reviewed languages ship", applied 2026-10-12): English (U.S.) and English (U.K.) at launch.** No language has a recorded review, so build 2 ships English only; the other 13 translations stay in the repository as drafts. The store page lists the app's languages. A German store page for an English-only app invites refunds and one-star reviews. English (U.K.) is the default or additional store language in Türkiye, India, Indonesia, Nigeria, Germany, France, Brazil and Russia. |
| 4 | Price model (PLAN M6). | Not a copy decision. | The description avoids price wording. Paid upfront is what App Store Connect holds (USD 9.99 base, 2026-10-12), so the optional line under "Private by design" may be added. |
| 5 | Primary category: keep Utilities, or Developer Tools? | ~~Developer Tools primary, Utilities secondary.~~ Superseded: keep Utilities primary, Developer Tools secondary (review readiness plan, R-5). | **Closed (2026-10-12): Utilities primary, Developer Tools secondary.** The build setting `PREV_APP_CATEGORY` and App Store Connect already agree. The earlier reasoning is kept for the record: both categories are indexed by search, so the choice only changes where the app is browsed; 8 of the 14 direct competitors read, and all four launched since September, chose Developer Tools; no data was found on which converts better. |

## Validation gate: what the copy may claim

The repository's rule is to claim Finder previews only for types seen to open in SpacePane. As of 2026-10-12,
[the host matrix](../validation/host-matrix.json) records the Finder preview for 4 of 76 types and the Quick
Look panel for 23 of 76 (SpacePane's own content seen), all on development-signed builds on one Mac running
macOS 27.2, and no Finder thumbnail for any type. Plain text and Swift source were shown by another provider
in the panel; `.env` got a generic icon. No store-signed install has been observed.

So the copy is built in two layers:

- **Name, subtitle, promotional text, the formats in the opening paragraph and screenshots 1 to 5** use only
  the observed set: JSON, JSON Lines, YAML, TOML, package.json, Markdown, diffs, XML, property lists, strings
  files, OPML, notebooks, SQLite, ZIP, TAR, GZIP, XIP, folders, MIDI, IGES, STEP and extension-free text.
- **The opening's safety claims are the exception.** Concealed secrets and the findings banner have been
  seen in Finder. Hidden-character and archive-risk findings pass package tests only. They are the lead
  claim, so they are the first thing to observe on the internal TestFlight build; if they cannot be shown,
  the opening falls back to secrets alone.
- **The description's feature list and the keyword field** also name capabilities that pass package tests
  but have not been seen in Finder. Each sits behind the sentence "macOS chooses which app previews each file
  type. When it uses SpacePane, you get:". The table in [Claim check](#claim-check-before-submission) lists
  them. After the installed-build validation (review readiness plan, Phase 3 and Phase 5), delete every line
  whose type did not open in SpacePane. No claim has been cut yet.

## What App Store Connect holds

Read directly from the app record (Apple ID 6819445086, macOS, version 1.0.0, "Prepare for Submission") on
2026-10-12. This is an observation of one day, not a mirror; App Store Connect is the source of truth. The
text fields were first entered and read back on 2026-10-10.

Text fields, the same for English (U.S.) and English (U.K.) except where noted:

| Field | Held |
|---|---|
| Name | `SpacePane for Quick Look` |
| Subtitle | `Preview JSON, SQLite, Markdown` |
| Promotional text, description, keywords | Entered. The stored description still says "11 color schemes" and must be re-pasted from this file (12) before submission. |
| Support URL | `https://spacepane.com/support` |
| Marketing URL | `https://spacepane.com` |
| Privacy Policy URL | `https://spacepane.com/privacy` |
| Copyright | `2026 Can Burak Sofyalioglu` |

The three addresses returned HTTP 200 on 2026-10-10. Other fields entered:

- Version record: 1.0.0 (not "1.0"), matching `MARKETING_VERSION`.
- Primary category Utilities, secondary Developer Tools. Age rating 4+. Content rights: "does not contain
  third-party content".
- Price: USD 9.99 base in the United States, available in 175 regions. Tax category "App Store software".
- App Review contact: name, phone and email entered. They are not recorded in this repository.
- App Privacy: "Data Not Collected" entered, **not yet published**.
- Release option: "Automatically release". The review readiness plan (R-4) says manual release; change it.
- Already set and left as found: bundle ID `org.webmeister.spacepane`, SKU `org.webmeister.spacepane`, primary
  language English (U.S.), Apple's standard licence agreement.

Builds and TestFlight:

- Build 1.0.0 (1) was uploaded on 2026-10-10. It is processed and "Ready to Submit", has zero installs and is
  not attached to the version. It will not be submitted; build 2 is being prepared.
- An internal TestFlight group "Internal" exists (owner decision R-7: internal testing only, never external
  testers or a public link).

Not in App Store Connect yet:

- Screenshots: 0 of 10. App previews: none.
- A selected build for the version.
- Review notes and the attachment.
- Digital Services Act trader status: still "Set Up".
- Paid Apps Agreement: status "New", unsigned. The Free Apps Agreement is active.
- Accessibility label: a draft that declares only Dark Interface.
- What's New is not offered for a first version.

## English (U.S.), primary

| Field | Text | Length |
|---|---|---|
| App name | `SpacePane for Quick Look` | 24 / 30 |
| Subtitle | `Preview JSON, SQLite, Markdown` | 30 / 30 |
| Keywords | `viewer,code,syntax,highlight,file,plugin,yaml,csv,toml,plist,xml,jupyter,zip,rar,step,iges,stl,cad` | 98 / 100 |
| Promotional text | `Press Space and see what's really inside: JSON as an outline, SQLite as tables, archives as a list. Made on your Mac, read-only, with likely secrets concealed.` | 159 / 170 |
| What's New | `The first release of SpacePane.` | |

How the three indexed fields work together:

- Apple matches words across name, subtitle and keywords, so no word is repeated. "json viewer" is `JSON`
  from the subtitle plus `viewer` from the keywords. "quick look plugin" is the name plus `plugin`.
- `viewer` is the strongest demand word found: store autocomplete completes json, csv, sqlite, yaml, stl and
  step with "viewer". `plugin` catches people replacing the `.qlgenerator` plug-ins that macOS 15 dropped.
- `step`, `iges`, `stl` and `cad` are long-tail terms with thin competition ("iges" and "stp" return fewer
  than 20 Mac apps each) and no Quick Look app in the top 10.
- "quick look" and "quicklook" return nearly the same apps (35 of 50 in common), so the fused form is not
  repeated in the keywords.
- Left out on purpose: `finder`, `mac` (Apple marks, and "finder extension" returns sync tools), `thumbnail`
  (owned by YouTube thumbnail makers), `folder` (taken by six folder specialists), other apps' names
  (guideline 2.3.7), category words (already indexed), `7z` and `3d` (App Store Connect asks for keywords
  longer than two characters).

### Description

3,721 of 4,000 characters, recounted with python3 on 2026-10-12 after "11" became "12" (the count does not change). Plain text with line breaks; the store supports no other formatting. Apple
does not list the description as a search field, so it is written to convert and to feed the store's
automatically generated tags, not to carry keywords.

```text
Quick Look previews that tell you what's really in a file.

Select a file in Finder and press Space. Where your Mac shows a blank icon or a wall of text, SpacePane shows structure: JSON opens as an outline you can fold, a SQLite database as its tables, an archive as a list of what's inside. It also points out what you can't see, such as hidden characters, risky archive entries and likely passwords and keys, which appear as ••••. Everything is read on your Mac and nothing is changed.

HOW IT WORKS
SpacePane is a small setup app with two Quick Look extensions: SpacePane Preview and SpacePane Thumbnails. Turn them on once in System Settings, then use Quick Look as you always do. There is no new app to switch to and nothing to learn.

macOS chooses which app previews each file type. When it uses SpacePane, you get:

STRUCTURE, NOT A WALL OF TEXT
• JSON, JSON Lines, YAML, TOML, XML and property lists as outlines, with the source one click away
• SQLite databases with their tables, columns and row counts, opened read-only
• ZIP, TAR, GZIP, XIP, RAR and 7z archives, and folders, listed without extracting anything
• Jupyter notebooks with their cells and saved outputs, never run
• Markdown as a readable document with a Contents view
• Diffs and patches in color
• CSV and TSV as sortable tables, with a profile of every column
• Mermaid and draw.io diagrams, Parquet files, EPUB books, comics and subtitles
• MIDI files with play and scrub controls
• Source code with syntax coloring for 84 languages
• Text files that have no extension, such as Makefile or zprofile
• STL, OBJ, PLY and 3MF models you can turn, plus STEP and IGES CAD models once you switch them on

That is 76 file types, each with its own switch.

KNOW WHAT'S HIDDEN INSIDE
Most previews show what a file looks like. SpacePane also tells you what to check first.
• Likely secrets such as passwords, tokens and keys are concealed, and counted by kind
• Invisible and look-alike characters are flagged, including text hidden in instruction files for AI coding tools
• Archive entries that would land outside the destination folder, disguised names and encrypted entries are called out
• Notebooks whose cells ran out of order are noted
These are things for you to review, not a verdict that a file is safe.

PRIVATE BY DESIGN
• Every preview is made on your Mac
• The app and its extensions have no network access
• Files are only read, never changed
• Scripts inside files never run
• No account, no analytics, no ads

MAKE IT YOURS
• Turn any file type off and SpacePane leaves it alone
• Light, Dark and High Contrast themes with 12 color schemes
• Your font, size, spacing and line numbers
• Save your look as a profile and share it as a small theme file

GOOD TO KNOW
• If macOS or another app already previews a type, such as plain text or some source code, SpacePane can't override that choice. An info symbol in the preview shows when SpacePane made it, and the app can list other apps that preview the same types.
• STEP and IGES previews are off by default, because large models take time and memory. Their measurements are approximate.
• Concealing secrets relies on patterns and can miss an unusual one.
• Files kept only in the cloud are previewed once they are downloaded.
• Thumbnails skip files that hold secrets, and some types keep their usual icon.

Requires a Mac with Apple silicon and macOS 15 or later.

Mac, macOS, Finder and Quick Look are trademarks of Apple Inc. SpacePane is not affiliated with Apple.

3D previews use Open CASCADE Technology under the GNU LGPL 2.1 with the Open CASCADE exception. The helper's source and the written offer for the library source: https://github.com/canburaks/spacepane-cad-source
```

Why it is shaped this way:

- **The opening is a position, then proof.** The first lines are all a visitor sees before "more". The
  better competitor pages open with an outcome about the Space bar; a rival released on 2026-10-07 opens
  "Press Space on a developer file and actually see what's inside". SpacePane's own tagline is close to
  that, so the store text opens on the claim no competitor makes: previews that tell you what is in a file.
- **It names both extensions and how to turn them on.** Guideline 4.4 requires the marketing text to
  disclose the extensions, and a Quick Look app does nothing until they are switched on.
- **It leads with the Safety Lens, not with "private" or "local".** Local processing and no account are
  standard claims in this category, and two competitors also mask secrets. None of the 151 store
  descriptions searched on 2026-10-05 mentions hidden-character detection, archive risk notes or notebook
  health.
- **"Good to know" states the limits.** The harshest review read was from a buyer whose STL files lost
  Apple's own preview when a competitor took the type over. Saying what macOS decides, and pointing at the
  per-type switches, answers that before it is asked.
- **No superlatives, speed claims, prices, other apps' names or language counts.** The first three are
  barred by the project's own rules, the fourth by guideline 2.3.7, and the translations are unreviewed.

Optional line if the app is paid upfront, added as the last bullet under PRIVATE BY DESIGN:

```text
• One purchase, no subscription
```

## English (U.K.)

Same name, subtitle, keywords, promotional text and What's New. The description differs in three spellings
("in colour", "syntax colouring", "colour schemes"); 3,724 of 4,000 characters, recounted on 2026-10-12 with
"12 colour schemes". Enter it as its own
localization so that storefronts whose store language is English (U.K.) get the full page.

## Fallbacks if App Review rejects the name

| | App name | Subtitle | Keywords |
|---|---|---|---|
| B: phrase only in the keyword field | `SpacePane: File Previews` (24) | `JSON, YAML, Markdown, SQLite` (28) | `quicklook,viewer,code,syntax,highlight,plugin,csv,toml,plist,xml,jupyter,zip,rar,step,iges,stl,cad` (98) |
| C: phrase in no indexed field | `SpacePane: File Previews` (24) | `JSON, YAML, Markdown, SQLite` (28) | `viewer,code,syntax,highlight,plugin,csv,toml,plist,xml,jupyter,zip,rar,folder,epub,step,iges,stl,cad` (100) |

B keeps most of the reach: an app with the phrase only in its subtitle ranks second for "quick look" today.
C follows the recorded rule to the letter and gives up the head term; the description still says "Quick
Look", which Apple's referential-use wording covers. An equal-strength alternative to the recommended name
is `SpacePane: Quick Look Previews` (30) with the subtitle `JSON, YAML, Markdown, SQLite`; it reads as a
product name that contains the phrase, which is the form Apple's guidelines discourage, and it differs from
one competitor's name only in the brand.

## Swaps for open decisions

| If | Change |
|---|---|
| IGES and STEP do not ship in 1.0 | Keywords: `viewer,code,syntax,highlight,file,plugin,yaml,csv,toml,plist,xml,jupyter,zip,rar,folder,epub,stl,obj` (100). Description: end the 3D bullet after "you can turn", and delete the STEP and IGES line under GOOD TO KNOW and the closing Open CASCADE paragraph. Drop screenshot 8 or reshoot it with an STL model. |
| No source-code type opens in SpacePane on the TestFlight Macs | Keywords: `viewer,file,plugin,yaml,csv,toml,plist,xml,jupyter,zip,rar,folder,epub,midi,srt,step,iges,stl,cad` (97). Description: delete the "Source code" bullet. |
| Source code does open in SpacePane on a clean Mac | Consider the subtitle `Code, JSON, Markdown, SQLite` (28) and move `preview` to the keywords: "code" is one of the six strongest terms. |
| The minimum macOS is raised (D21) | Name the version in the "Requires" line. |
| The brand name changes | Only the name and the description's brand mentions change. Subtitle and keywords carry no brand word. |

## Claim check before submission

Evidence tiers in the "Evidence today" column follow the validation records: **seen** = opened in SpacePane
through Quick Look on a development-signed build; **tested** = package or companion tests only. Nothing here
was seen on a store-signed install.

The two right-hand columns come from [the host matrix](../validation/host-matrix.json) and the format
catalog (`Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json`), read on 2026-10-12.
The matrix records one outcome per surface: `provider` (SpacePane's own content was seen; this is the
matrix's word for an observation), `otherProvider` (another provider's content was seen), `generic` (a
generic icon and metadata only) and `notObserved`. Values are given as Finder preview / Quick Look panel /
Finder thumbnail. No claim has been cut; cuts wait for the installed-build validation (Phase 5 of the
[review readiness plan](../plans/2026-10-12-review-readiness-plan.md)).

Claims with no Finder or panel observation at all (Finder preview and Quick Look panel both `notObserved`):

- RAR and 7z listings (`archive.rar`, `archive.7z`).
- CSV and TSV tables and Profile (`data.csv`, `data.tsv`), also in the keyword field (`csv`).
- Mermaid, draw.io, Parquet, EPUB, comics and subtitles (`text.mermaid`, `data.drawio`, `data.parquet`,
  `document.epub`, `archive.comic-book`, and the subtitle types).
- STL, OBJ, PLY and 3MF models (`model.stl`, `model.obj`, `model.ply`, `model.3mf`), also in the keyword
  field (`stl`).
- Hidden characters, archive risk notes and notebook health. These are findings, not formats, so the matrix
  has no row for them; nothing records one seen in Finder or the panel.
- Every thumbnail claim: `finderThumbnail` is `notObserved` for all 76 types.

Observed, but not the view the copy claims, or not by SpacePane:

- YAML, TOML, XML and property lists as outlines; Markdown as a rendered document: only concealed source
  was seen in the panel.
- Source code: the panel showed another provider (`text.source-code`).
- CSV: macOS has its own preview, so SpacePane may never be asked.

| Line in the copy | Catalog format ID(s) | Matrix: preview / panel / thumbnail | Evidence today | Before submission |
|---|---|---|---|---|
| JSON outline; concealed secrets; findings banner | `data.json` | provider / provider / notObserved | Seen | Re-run on the store-signed build |
| JSON Lines | `data.json-lines` | provider / provider / notObserved | Seen, but the resolved type belonged to another vendor's app on that Mac | Check on a Mac with no other Quick Look apps |
| YAML, TOML, XML, property lists as outlines | `data.yaml`, `data.toml`, `data.xml`, `data.property-list` | notObserved / provider / notObserved (each) | Seen as concealed source; outline tested | Observe the outline in Finder |
| SQLite tables, columns, row counts | `database.sqlite` | notObserved / provider / notObserved | Seen (summary) | Observe the table view |
| ZIP, TAR, GZIP, XIP and folder listings | `archive.zip`, `archive.tar`, `archive.gzip`, `archive.xip`, `container.folder` | notObserved / provider / notObserved (each) | Seen | |
| RAR and 7z listings | `archive.rar`, `archive.7z` | notObserved / notObserved / notObserved | Tested | Observe, or delete from the bullet |
| Jupyter notebooks | `text.jupyter-notebook` | provider / provider / notObserved | Seen | |
| Markdown as a readable document with Contents | `text.markdown` | notObserved / provider / notObserved | Seen as source only; rendered view tested | Observe the rendered view, or reword to "Markdown with its source" |
| Diffs in color | `text.diff` | notObserved / provider / notObserved | Seen | |
| CSV and TSV tables and Profile | `data.csv`, `data.tsv` | notObserved / notObserved / notObserved | Tested; macOS has its own CSV preview | Observe, or delete the bullet |
| Mermaid, draw.io, Parquet, EPUB, comics, subtitles | `text.mermaid`, `data.drawio`, `data.parquet`, `document.epub`, `archive.comic-book`; subtitles: `text.subrip`, `text.webvtt`, `text.substation-alpha`, `text.ttml`, `text.sbv`, `text.microdvd` | notObserved / notObserved / notObserved (each) | Tested | Observe each, or delete it |
| MIDI play and scrub controls | `audio.midi` | notObserved / provider / notObserved | Seen with a silent file | Confirm audible playback |
| Source code, 84 languages | `text.source-code` | notObserved / otherProvider / notObserved | Tested; Swift went to another provider | See the swaps above |
| Extension-free text files | `text.extensionless` | provider / provider / notObserved | Seen | |
| STL, OBJ, PLY, 3MF | `model.stl`, `model.obj`, `model.ply`, `model.3mf` | notObserved / notObserved / notObserved (each) | Tested; macOS has its own previews for some | Observe, or delete |
| STEP and IGES once switched on | `cad.step`, `cad.iges` | notObserved / provider / notObserved (each) | Seen on one Mac | Store-signed check (D27), licence gate (D20); the legal review of the source-offer route has no recorded outcome |
| Hidden characters, archive risk notes, notebook health | none (findings on text, archive and notebook types; archive risk: `archive.zip`, `archive.tar`, `archive.rar`, `archive.7z`; notebooks: `text.jupyter-notebook`) | no row | Tested | Observe one of each in Finder |
| No network access, read-only, no account, no analytics | none | not a format claim | Entitlements checked in the archive | Re-check the exported package |
| Info symbol; list of other apps that preview the same types | none | not a format claim | Tested | Observe |
| Thumbnails skip files that hold secrets | thumbnail-enabled types, none observed | notObserved for all 76 | Tested; no Finder thumbnail observed | Observe a content thumbnail, or remove "SpacePane Thumbnails" claims beyond naming the extension |
| 12 color schemes, profiles, theme files, per-type switches | none | not a format claim | Eleven schemes, profiles and switches seen in the signed companion (build 1). Aurora, the twelfth, was added on 2026-10-11 and is in the source only | Observe all twelve in build 2; the stored description still says 11 |
| macOS 15 or later | none | not a format claim | Owner's report (2026-10-12): the app works on macOS 15. A macOS 15.2 virtual machine exists. No session has recorded an observation | Record the run on macOS 15 (D21) |

The keyword field depends on the same IDs: `csv` on `data.csv`, `rar` on `archive.rar`, `stl` on
`model.stl`, `step`, `iges` and `cad` on `cad.step` and `cad.iges`, `yaml`, `toml`, `plist`, `xml`,
`jupyter` and `zip` on the rows above.

## Screenshots

Mac screenshots are 16:10; upload one 2880 × 1800 set as PNG or JPEG without transparency (1 to 10 images).
Up to three can appear in search results, so the first three carry the whole pitch. Each image is a real
capture of SpacePane on a plain background with one short headline above it, the format every strong
competitor uses and which guideline 2.3.3 allows. Captions carry no prices, no other apps' names and no
claims the capture does not show. All file contents are synthetic
(`python3 script/generate_host_fixtures.py`); the fake secret it writes makes concealment visible.

| # | Headline | Scene | Stage with | Evidence |
|---|---|---|---|---|
| 1 | Press Space. See what's really inside. | Finder window with the Quick Look panel open on a JSON file in Outline view | `03-data.json` | Seen |
| 2 | Likely secrets concealed, and counted. | The same kind of file in Source view: values shown as ••••, with the findings banner counting them | `05-config.yaml` or `03-data.json` | Seen (JSON) |
| 3 | A database at a glance. Read-only. | SQLite preview: tables, columns, row counts | SQLite host fixture | Seen (summary) |
| 4 | Look inside. Nothing is extracted. | ZIP archive listing | `17-listing.zip` | Seen |
| 5 | Notebooks as saved. Never run. | Jupyter notebook with the Source / Outline / Rendered control | `29-notebook.ipynb` | Seen |
| 6 | Markdown, ready to read. | Rendered Markdown with the Contents view | `09-document.md` | Tested; use only once seen in Finder |
| 7 | Hidden characters, made visible. | Invisibles view with markers on hidden characters | A synthetic text file with hidden characters | Tested; use only once seen |
| 8 | Models you can turn. | STEP model with the standard-view buttons; small line "STEP and IGES are off until you switch them on" | Synthetic STEP box, switched on in File Types | Seen on one Mac; drop if CAD does not ship |
| 9 | A switch for every file type. | The File Types page | Companion app | Seen |
| 10 | Your colors. Your type. | The Theme page with the live sample | Companion app | Seen |

Screenshots 9 and 10 are captures of the app's own window, the rest of Quick Look in Finder. If 6, 7 or 8
cannot be used, ship seven images rather than fill the gaps with unobserved scenes.

App Store Connect holds no screenshots (0 of 10, observed 2026-10-12). Build 1 has eleven color schemes and
build 2 has twelve, so the Theme page capture is retaken from the validated build (review readiness plan,
Phase 5).

An app preview video is optional (up to three, landscape, screen capture only). One 20-second capture is
enough: select a file, press Space, switch Outline to Source, select the next file. Record it after the
screenshots are settled; previews show before screenshots, so a weak one costs more than none.

## Other product-page fields

| Field | Value | Note |
|---|---|---|
| Categories | Utilities primary, Developer Tools secondary (decision 5, closed). App Store Connect holds the same (observed 2026-10-12) | The primary must match `PREV_APP_CATEGORY` |
| Accessibility labels | Declare Dark Interface only. App Store Connect holds a draft with only Dark Interface (2026-10-12) | Apple uses these labels in search. A label means every common task works with that feature, so VoiceOver, Sufficient Contrast and Differentiate Without Color wait for an audit (VoiceOver in Quick Look is unverified) |
| App Privacy | Data Not Collected | Entered in App Store Connect, not yet published (2026-10-12). Reasoning in app-store-submission.md |
| Age rating | 4+ | Entered in App Store Connect (2026-10-12) |
| Support, privacy, marketing URLs | As recorded above | The support, privacy and open-source pages are live and show `info@spacepane.com`. The domain has MX, SPF and DMARC records; whether the mailbox answers is unconfirmed (review readiness plan, Phase 0) |

Custom product pages, product page optimization, in-app events and Apple Ads are iPhone and iPad features;
none applies to a Mac app. The two levers that do exist on the Mac are the promotional text, which can be
changed at any time without a new version, and a featuring nomination in App Store Connect, which Apple asks
for at least two weeks before launch.

## Localized fields (drafts, not for launch)

The app name stays `SpacePane for Quick Look` everywhere: in every storefront searched, English "quick look"
returns largely the same apps as in the U.S., and format words (JSON, Markdown, SQLite) stay in English.
Only the generic words are worth translating. The three competitors that translate their names swap in
Apple's local name for the feature (クイックルック, 快速查看, Vista rápida, Übersicht); the keyword lines below
carry those names where they return Quick Look apps, which leaves the name stable. Each term below was searched in its own storefront.

These are drafts by a non-native writer. Per D22, publish a language's store text only when that language's
app translation has been reviewed, and have the same reviewer check these lines and translate the
description from the English master. Kurmanji and Hausa are not offered by App Store Connect. No Hindi or
Bangla keyword is proposed: Hindi searches returned thin, unrelated results, and Bangla was not researched,
so both should start from the English fields.

| Store language | Subtitle | Keywords |
|---|---|---|
| German | `Vorschau für JSON und Markdown` (30) | `dateivorschau,datei,viewer,sqlite,code,syntax,yaml,csv,toml,plist,xml,zip,rar,step,iges,stl,cad` (95) |
| French | `Aperçu JSON, SQLite, Markdown` (29) | `fichier,visionneuse,rapide,code,syntaxe,coloration,yaml,csv,toml,plist,xml,zip,rar,step,iges,stl,cao` (100) |
| Spanish (Spain, Mexico) | `Vista previa: JSON y Markdown` (29) | `rápida,visor,archivos,sqlite,código,sintaxis,yaml,csv,toml,plist,xml,zip,rar,step,iges,stl,cad` (96) |
| Portuguese (Brazil) | `Prévia de JSON e Markdown` (25) | `arquivos,visualizador,rápida,sqlite,código,sintaxe,yaml,csv,toml,plist,xml,zip,rar,step,stl,cad` (97) |
| Japanese | `JSON・SQLite・Markdownをプレビュー` (26) | `クイックルック,ファイル,ビューア,コード,yaml,csv,toml,xml,zip,rar,stl,step,cad` (96) |
| Chinese (Simplified) | `空格预览 JSON、SQLite、Markdown` (25) | `快速查看,文件,查看器,代码,高亮,sqlite,yaml,csv,toml,plist,xml,zip,rar,stl,step,cad` (95) |
| Turkish | `JSON ve Markdown önizleme` (25) | `dosya,görüntüleyici,göz at,sqlite,kod,sözdizimi,yaml,csv,toml,plist,xml,zip,rar,step,stl,cad` (97) |
| Russian | `Предпросмотр JSON и Markdown` (28) | `быстрый,просмотр,файлов,sqlite,код,yaml,csv,xml,zip,rar,stl,step,cad` (92) |
| Indonesian | `Pratinjau JSON dan Markdown` (27) | `cepat,file,penampil,sqlite,kode,sintaks,yaml,csv,toml,plist,xml,zip,rar,step,iges,stl,cad` (89) |

Notes:

- Apple's own name for Quick Look is used only where searching it returns Quick Look apps: Spanish "Vista
  Rápida" (`vista` in the subtitle plus `rápida`), Japanese クイックルック, Chinese 快速查看 and Russian
  Быстрый просмотр. The German (Übersicht), French (Coup d'œil), Turkish (Göz At) and Indonesian (Lihat
  Cepat) names return unrelated or almost no apps; `göz at` is kept in Turkish only because it is cheap.
- Non-Latin keywords cost two or three bytes per character. The counts above are bytes; confirm them with
  App Store Connect's own counter, and check there whether two-character Chinese keywords (文件, 代码, 高亮)
  are accepted.
- Some third-party tools report that a storefront also indexes keywords from its additional store
  languages (for example Spanish (Mexico) in the U.S.). Apple does not document it and nothing was found
  measuring it on the Mac App Store. Treat it as an experiment for after launch.

## After launch

- Apple publishes no search volumes for the Mac and Apple Ads does not run there, so rank is checked by
  hand: search "quick look", "json viewer", "sqlite viewer", "markdown preview" and "step viewer" in the
  U.S. and U.K. stores a week after release and again after a month, and note the position.
- Keywords, name and subtitle change only with a new version. Use the first update to drop terms that
  bring no rank and to act on the claim check.
- None of the eleven competitor pages checked for it has enough U.S. ratings to show a score, including
  one on sale since 2020. A visible rating would be a real edge; whether to ask for ratings in the app is a
  product decision that is not made here.
