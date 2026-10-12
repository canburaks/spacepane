# SpacePane — English App Store listing (draft)

Superseded on 2026-10-10 by [../app-store-listing.md](../app-store-listing.md). Do not enter the text below in App Store Connect; it is kept as the earlier draft and for its list of claims left out.

Status: draft for the 1.0.0 submission, English only, not entered in App Store Connect. Written 2026-10-10. Every limit below was measured with a command on 2026-10-10 (see "How the counts were measured" at the end); recount after any edit. Field limits are from Apple's App Store Connect reference, read 2026-10-10. Recheck them and the live form before entering anything.

Truthfulness rules applied (from `AGENTS.md` and `docs/validation/host-matrix.json`): the text lists what the app supports, not what Finder will choose; it never says a specific type previews or gets a thumbnail in Finder; it says plainly that macOS decides which app previews a type. See "Claims deliberately left out" at the end.

## Name (2 to 30 characters)

```text
SpacePane
```

9 characters. The visible name comes from `PREV_DISPLAY_NAME` in `Configuration/Branding.xcconfig`; the App Store name must match the owner's reserved name in App Store Connect.

## Subtitle (30 characters at most)

| # | Candidate | Characters |
|---|---|---|
| 1 | `Quick Look for code and data` | 28 |
| 2 | `Quick Look for developer files` | 30 |
| 3 | `Private Quick Look previews` | 27 |

Recommendation: **1**. It says what the product is for in plain words and does not repeat a word from the name. Candidate 2 sits exactly at the limit, so any later wording change risks truncation. Candidate 3 leads with privacy, which is true (no network entitlement) but says less about the purpose. "Quick Look" is Apple's name for the feature the app extends; it is used descriptively, not as another app's name.

## Promotional text (170 characters at most)

```text
Preview code, data, archives, notebooks and more with Quick Look. Everything stays on your Mac: no network, no accounts, and likely secrets are hidden by default.
```

162 characters. Promotional text can be changed at any time without a new build.

## Description (4,000 characters at most)

Plain text, as App Store Connect expects (no Markdown). The bullet character is U+2022. Everything between the lines below is the field value.

```text
SpacePane adds Quick Look previews and thumbnails for developer, data and document files on your Mac. It runs entirely on your Mac, only ever reads your files, and hides values that look like passwords, tokens or keys.

EXTENSIONS THIS APP PROVIDES
SpacePane includes two Quick Look extensions:
• SpacePane Preview, a Quick Look Preview extension. It shows file contents when you select a file and press Space.
• SpacePane Thumbnails, a Quick Look Thumbnail extension. It can draw thumbnails for some of the supported types. Other types keep the standard icon.

To turn them on, open SpacePane, then open System Settings and find the Quick Look extensions in the Extensions or Login Items & Extensions settings. The exact location differs between macOS versions. The General page in SpacePane has a button that opens System Settings. Switch on SpacePane Preview and SpacePane Thumbnails there.

macOS decides which app previews a file type when several apps support it. SpacePane cannot override that choice, and some types, such as plain text, may keep the built-in macOS preview.

WHAT IT CAN PREVIEW
SpacePane supports 76 file types in five groups:

Text
Plain text, source code in many languages, logs, Markdown, LaTeX, BibTeX, AsciiDoc, reStructuredText, Org, Fountain screenplays, diffs and patches, Mermaid and draw.io diagrams, subtitle and caption files (SRT, WebVTT, SSA and ASS, TTML, SBV, LRC, MicroDVD), NFO files, Jupyter notebooks, EPUB and FictionBook ebooks, MHTML web archives, and text files that have no extension.

Structured Data
JSON, JSON Lines, JSONC and JSON5, YAML, TOML, XML, property lists, strings files, OPML, INI and .env files, package.json, CSV, TSV, Parquet, Avro, Arrow, NumPy, HAR, GeoJSON, GPX, KML, provisioning profiles and certificates.

Archives and folders
ZIP, TAR, GZIP, bzip2, xz, 7z, RAR and XIP archives, CBZ comic books, app bundles, IPA, APK and AAB packages, installer packages, disk images, torrent files and folders. Archives are listed, never extracted.

Databases
SQLite databases.

Media
MIDI files, STL, OBJ, PLY and 3MF 3D models, and optional STEP and IGES 3D models (see below).

CUSTOMIZE IT
• Switch each file type on or off in File Types. A type you turn off shows a short notice instead of its contents.
• Choose fonts, spacing, line numbers, tab width and wrapping.
• Pick color themes with light, dark and high-contrast variants.
• Save your look as a named profile, and export or import a theme as a file. Imported themes are plain data and cannot run code.
• The Theme page shows a live sample of every supported type with your settings.

PRIVATE AND SAFE BY DESIGN
• Everything happens on your Mac. SpacePane has no network access, no accounts, no analytics and no tracking.
• Files are only read, never changed. Scripts and notebook cells inside files are never run, and archives are never extracted.
• Values that look like passwords, tokens or keys are concealed by default, even in the source view. This is a best-effort check and cannot catch every secret.
• Previews can point out things worth checking before you open or run a file, such as hidden or direction-changing characters and risky archive entries. These are notes to review, not a verdict.
• Files are read within fixed limits on size and processing time, so a very large file may show only its first part.

OPTIONAL 3D PREVIEWS FOR STEP AND IGES
Previews for STEP (.step, .stp) and IGES (.igs, .iges) files are off by default because reading CAD models takes more time and memory. Turn each on in File Types if you want it. The model is read in a separate sandboxed helper that runs only while a preview is prepared, and you can rotate, pan and zoom the result.

REQUIREMENTS
A Mac with Apple silicon and macOS 15 or later.

LANGUAGES
[OWNER DECISION: list the interface languages that ship in 1.0.0 once reviewed, or delete this section.]
```

Measured: 3876 characters, 3900 UTF-8 bytes. The `LANGUAGES` section is a placeholder; once filled, recount. The text has about 124 characters of headroom.

Notes on the text, for the owner:

- Guideline 4.4: the "EXTENSIONS THIS APP PROVIDES" section names the Quick Look Preview extension and the Quick Look Thumbnail extension and says how they are enabled. The extension names are the display names `SpacePane Preview` and `SpacePane Thumbnails` from `Configuration/Branding.xcconfig`; they change with the brand.
- The System Settings path is deliberately generic. The exact path has not been recorded on the store build for any macOS version (publication plan, Phase 5). When recorded, the sentence may be made specific; the owner should then also say which macOS versions were checked.
- "The General page in SpacePane has a button that opens System Settings" rests on `GeneralView.swift` and the review notes. Confirm it on the store build before submission.
- The five group headings and the type lists follow `FormatCatalog.json` (26 + 26 + 16 + 1 + 7 = 76 types). The headings "Text", "Structured Data", "Archives and folders", "Databases" and "Media" are the English group names used by the website's format list. If the catalog changes, regenerate the lists and the number 76.
- Guideline 2.3 (accuracy): the hidden-character and archive-risk sentence says "can point out" and "not a verdict", matching the website's Safety Lens text. The secrets sentence says "best-effort", matching `README.md`.
- The 3D section does not mention approximate measurements; if the owner wants it, take the wording from the website's CAD card, which says values are approximations measured on the displayed 3D mesh.
- The open-source notice and the source offer for the 3D helper are not mentioned. Whether and where the app shows them (About page) is stream D's work and not complete at the time of writing; add a sentence only after it exists.

## Keywords (100 bytes at most, comma-separated)

```text
preview,thumbnail,json,yaml,toml,markdown,csv,sqlite,archive,notebook,step,iges,3d,cad,midi,syntax
```

98 bytes (measured with `printf %s "…" | wc -c`). No spaces after commas, no word repeated from the name or subtitle ("SpacePane", "quick", "look", "code", "data" are indexed already), no other app's or company's name, no Apple product name, no "Finder", "Quick Look" or "macOS" (they appear in the subtitle and description). Singular forms are used to save bytes. All words describe supported formats or features: `step`, `iges`, `3d` and `cad` refer to the optional, off-by-default previews, which are real product features.

## What's New in 1.0.0 (4,000 characters at most)

```text
First release of SpacePane.

• Quick Look Preview and Quick Look Thumbnail extensions for 76 file types: text and documents, structured data, archives and folders, SQLite databases, and media.
• A companion app to turn each file type on or off and to choose fonts, colors and profiles.
• Optional 3D previews for STEP and IGES files, off by default.
• Local only: no network access, no accounts, no analytics. Files are read, never changed, and likely secrets are concealed by default.
```

485 characters. For a first release App Store Connect may not show this field to customers; it is kept so the text is ready.

## Languages placeholder

The description ends with a `LANGUAGES` section that is a marker, not copy. Decide before submission, per the publication plan's decision D-B: list only the languages that have a recorded review, or delete the section. The repository records all 13 non-English languages as "Draft translations; native-speaker and installed-host validation pending" (`tools/localization/languages.json`). Do not write "available in 14 languages" while that status stands. The same rule applies to the localized store texts; see `app-store-connect-worksheet.md` for which App Store locales exist.

## Claims deliberately left out

| Left out | Why |
|---|---|
| "Preview in Finder" for any named type, "Spacebar in Finder shows X", "replaces Apple's preview" | `host-matrix.json` records Finder preview as observed ("provider") for 4 of 76 types, all on development-signed builds; the store build has not been observed. macOS controls provider selection. |
| Thumbnails for any named type | `finderThumbnail` is `notObserved` for all 76 types. The text says only that the thumbnail extension "can draw thumbnails for some of the supported types". |
| "Works with every file" or "all 76 types preview in Finder" | 72 of 76 types have no recorded Finder preview observation; 2 plain-text and source-code Quick Look panel observations show another provider winning. |
| Exact System Settings path | Not recorded on the store build; differs by macOS version. |
| Number of colour themes, code languages or interface languages | Counts come from the website sync and would go stale; translations are drafts. |
| "Works on macOS 15" beyond the stated requirement | Decision D-I: the app has never run on macOS 15 (only macOS 27.2 was tested). The requirement line states the build's minimum, nothing more. Change it if the minimum is raised. |
| Performance claims ("instant", "fast") | Targets are unmeasured on release hardware per `AGENTS.md`. |
| Price, "free", "no in-app purchases" wording | Price is set in App Store Connect. The app has no in-app purchase code, but that is the owner's store configuration to state, not store copy. |
| Competitor and Apple-product comparisons | Store rules and the brief. |
| Open-source or licence statements | Pending the About page and the source offer. |

## How the counts were measured

```sh
# Run from the repository root. It reads the fenced blocks of this file and prints each count.
python3 - <<'PY'
import re, pathlib
text = pathlib.Path('docs/release/store-listing/listing.en.md').read_text()
def block(heading):
    section = text.split(heading, 1)[1]
    return re.search(r'```text\n(.*?)\n```', section, re.S).group(1)
for heading, limit in [('## Name', 30), ('## Promotional text', 170), ('## Description', 4000),
                       ('## Keywords', 100), ("## What's New", 4000)]:
    value = block(heading)
    print(heading, len(value), 'characters', len(value.encode()), 'bytes; limit', limit)
PY
printf %s "preview,thumbnail,json,yaml,toml,markdown,csv,sqlite,archive,notebook,step,iges,3d,cad,midi,syntax" | wc -c
```
