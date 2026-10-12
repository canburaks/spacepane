# SpacePane — Mac App Store screenshot shot list (draft)

Status: the owner chose this set for the store on 2026-10-12. The nine images are in [screenshots/](screenshots/),
made on 2026-10-11 from the local development-signed Release build. They are not verified on a store-signed
build and have not been uploaded. A second set in the website's dark style with the Aurora scheme was made by
another session under `.build/store-screenshots/website-theater/`; it was not chosen.
The sections under "Earlier plan" were written on 2026-10-10 and are kept for their rules; where they differ
from the next section, the next section is what was done.

## What was made on 2026-10-11

Owner decisions that day: a real capture on a background with one headline above it; all nine scenes of
[app-store-listing.md](../app-store-listing.md#screenshots) except "Hidden characters"; vivid gradients;
the GitHub Dark color scheme; capture from the local build now and confirm each Finder scene on the TestFlight
install before submission.

| File | Headline | What the capture is |
|---|---|---|
| `01-press-space.png` | Press Space. See what's really inside. | Finder window and its Quick Look panel on `settings.json`, Outline view |
| `02-secrets-concealed.png` | Likely secrets concealed, and counted. | Quick Look panel, `settings.json`, Source view, zoomed |
| `03-notebooks.png` | Notebooks as saved. Never run. | Quick Look panel, `tide-analysis.ipynb`, Rendered view, zoomed |
| `04-database.png` | A database at a glance. Read-only. | Quick Look panel, `stations.sqlite`, Table view |
| `05-archives.png` | Look inside. Nothing is extracted. | Quick Look panel, `release-1.4.zip`, Tree view |
| `06-markdown.png` | Markdown, ready to read. | Quick Look panel, `README.md`, Rendered view, zoomed |
| `07-models.png` | Models you can turn. | Quick Look panel, `winch-gear.step`; the line under the headline says STEP and IGES are off until switched on |
| `08-file-types.png` | A switch for every file type. | The companion's File Types page |
| `09-theme.png` | Your colors. Your type. | The companion's Theme page |

How they are made, so they can be retaken:

1. `python3 script/generate_store_demo_files.py` writes the synthetic "Harbor" files to
   `.build/store-screenshots/Harbor`. Nothing in them is real; the secret-looking values are fake and are there
   so concealment shows. `winch-gear.step` is generated AP214 text (a gear outline with a hexagonal bore).
2. `script/store-screenshots/capture.sh` stages a clean Finder window, opens Quick Look on each file, picks the
   view with the panel's own controls, and captures each window by its window number with `screencapture`.
   It needs a Retina display mode, Screen Recording and Accessibility permission, and about two minutes with
   hands off. It restores Finder's preview pane, path bar, status bar and tab bar afterwards.
3. `script/store-screenshots/compose.sh` places the captures on 2880 × 1800 canvases with
   `script/compose_store_screenshot.swift`: a capsule label, the headline, a gradient from the website palette,
   and the capture at its own pixels (never enlarged), running off the bottom edge. The output has no alpha.

Nothing inside a capture is drawn or retouched. Zoom is the app's own Command-plus, sent after a click in the
preview's margin so the panel has the keyboard; the capture step checks that the picture changed. The scheme
tile is chosen with a real mouse click, because the tiles ignore an accessibility press.

Open before these are submitted:

- App Store Connect holds no screenshots (0 of 10, observed 2026-10-12). Build 1 has eleven color schemes and build 2 has twelve (Aurora, added 2026-10-11), so the Theme image (`09-theme.png`) is retaken from the validated build with the twelve tiles.
- Retake from the internal TestFlight install, or confirm each Finder scene there (provenance gate 1 below). The CAD
  scene in particular has only been seen on the development-signed build.
- Resolved 2026-10-11: Quick Look's "Open with" button named this Mac's default apps for notebooks and SQLite
  files, which are other vendors' products. The owner asked for them to go. The demo generator now gives those
  two files a per-file "Open with" binding to Xcode (the extended attribute Finder's Get Info writes), so the
  button reads "Open with Xcode" like the other scenes. No system default was changed and no pixel was edited.
- Seen while capturing, to be checked in the app: `deploy.yaml` reports "Structured view is unavailable"; long
  headings in the Contents rail overlap when they wrap; the color scheme tiles on the Theme page expose no
  accessibility label or selected state; pressing the light "Standard" tile did not change the selection.

## Earlier plan

## Rules that apply to every shot

Apple's constraints (App Store Connect reference, read 2026-10-10; recheck the live form):

- Mac screenshots are 1280×800, 1440×900, 2560×1600 or 2880×1800 pixels (16:10). One to ten. The first three are the ones shown in search results, so the strongest shots go first.
- No transparency (no alpha channel). The shots must show the real app in use; guideline 2.3 rules out mockups of behaviour that does not exist.
- Target size for this list: **2880×1800**. If the capture display is not 16:10 (many laptop panels are not), choose a display mode or a virtual display that is, or place an unscaled window capture on a solid 2880×1800 canvas. Never stretch a capture. Decide this once; it is an owner choice.

Provenance gates (from `AGENTS.md`, `docs/validation/host-matrix.json` and the publication plan, decision D-J):

1. **Shots are taken only from the validated store-signed build**: the TestFlight install of the exact build that will be submitted, installed in `/Applications`, with `pluginkit -mAD | grep -i webmeister` showing exactly one preview and one thumbnail extension (development builds registered from build folders compete with the store build for Finder routing).
2. **Finder shots need a recorded observation first.** `host-matrix.json` currently records Finder preview as observed for 4 of 76 types (`text.extensionless`, `data.json`, `data.json-lines`, `text.jupyter-notebook`) and Finder thumbnails for 0 of 76, all on development-signed builds. Before a Finder shot is allowed, the type must be observed to show SpacePane's preview in Finder on the store build, and `host-matrix.json` updated. If it is not, use the companion substitute named in the row, or drop the shot. Where Quick Look panel and Finder column preview are different surfaces, the shot says which one it shows.
3. **No thumbnail shot** (icon view, gallery or Finder list icons) unless thumbnails are observed on the store build for the types shown. None has been observed.
4. Use only synthetic files from `python3 script/generate_host_fixtures.py` (it prints a new directory; the only secret in them is the fake string `synthetic-host-matrix-secret`) or the app's bundled appearance samples. Copy the files into a folder named `Demo Files` on a clean demo user account or a tidied desktop. No private files, real names, real paths, real mail, iCloud folders or other apps' windows. The supplied private CAD model never appears (`AGENTS.md`).
5. Fresh settings (decision D-A: discard old group-container settings before the validation round), English interface, a single window of the app per shot, menu bar and Dock showing no personal items.
6. Capture with `screencapture` or the Screenshot app; then check each file: `sips -g pixelWidth -g pixelHeight -g hasAlpha <file>` must report 2880, 1800 and `hasAlpha: no`. Export as PNG (or JPEG) in sRGB.
7. Captions are optional overlays added in a separate step on a copy; the raw capture is kept. Each caption is 40 characters or fewer, plain, true to what the shot shows. Do not add claims the shot cannot support (no "Works in Finder for every file").
8. Screenshots are English only for now; localized sets follow the language decision (D-B). Do not reuse English captures for a locale with different UI text.

## Shot list (8)

| # | Scene | Window | Sample file | Caption (characters) | Size | Must be verified before the shot is allowed |
|---|---|---|---|---|---|---|
| 1 | A JSON file in Quick Look with the password value concealed; Source view with the concealed value visible as dots | Real Finder Quick Look panel (press Space on the file in a Finder window) | `03-data.json` (synthetic `password` key) | `Secrets hidden by default` (25) | 2880×1800 | JSON preview in Finder observed on the store build (`data.json`: Finder preview and panel previously observed on a development-signed build `3a97e4f` only). Value shows as dots, not the fake string. Hero shot. |
| 2 | A Jupyter notebook: markdown cell, code cell with output, the concealed assignment | Real Finder Quick Look panel | `29-notebook.ipynb` | `Notebooks, never run` (20) | 2880×1800 | `text.jupyter-notebook` Finder preview observed on the store build (previously observed on development builds only). |
| 3 | A CSV file in the Profile view (column types, missing values, distribution) | Real Finder Quick Look panel | `24-table.csv` | `CSV columns at a glance` (23) | 2880×1800 | `data.csv` is `notObserved` in Finder today. Allowed only after it is observed on the store build and the Profile view is confirmed present in that build. Otherwise replace with shot 3b below. |
| 3b | (substitute for 3) A Markdown file with headings, list and the concealed line | Real Finder Quick Look panel | `09-document.md` | `Markdown, rendered natively` (27) | 2880×1800 | `text.markdown` Finder preview `notObserved` today (Quick Look panel observed on development builds). Same gate as shot 3. If neither 3 nor 3b is observed, drop this slot and use the substitute rule below. |
| 4 | File Types page: the five groups with switches, STEP and IGES shown off | Companion window, File Types page (the one app window with its fixed sidebar) | none (app UI) | `Turn each file type on or off` (29) | 2880×1800 | Store build installed; default settings; window at a size that shows the group headings and at least the Media group's STEP and IGES rows off. No search text typed. |
| 5 | Theme page: live preview of a source-code sample with a colour theme, font and line numbers applied; light appearance | Companion window, Theme page | Built-in appearance sample from the preview menu (a code type, such as Source Code); not a user file | `Your fonts, your colors` (23) | 2880×1800 | Sample is the app's bundled synthetic sample (`script/generate_appearance_samples.py`). The shot is of the companion's live preview and is captioned as such if the caption names it; it must not be presented as a Finder preview. |
| 6 | A STEP model rotated in the 3D preview (box or the synthetic STEP fixture), with the opt-in switch on | Real Finder Quick Look panel | `23-box.step` (from `Native/CADWorker/Tests/Fixtures/box.step` via the generator) | `Optional 3D previews: STEP and IGES` (35) | 2880×1800 | CAD types are default off, so enable STEP in File Types first and record that. `cad.step` Finder preview is `notObserved` in the matrix (Quick Look panel observed on a development build). Needs the CAD service to accept the TestFlight-delivered preview extension (publication plan, gap 1) and a successful STEP preview on the TestFlight install. If it fails, drop the shot. |
| 7 | General page: where settings are saved and the button that opens System Settings | Companion window, General page | none (app UI) | `Set up once in System Settings` (30) | 2880×1800 | Status text must be the app's own (it reports where settings are saved, never that Finder uses this provider; `AGENTS.md`). Do not show a System Settings window unless the path on that macOS version has been recorded; if shown, state the macOS version in the shot record. |

Count: shots 1, 2, 3 (or 3b), 4, 5, 6 and 7 are seven; the plan allows up to eight with one more companion shot if a Finder slot fails. A Finder-only listing is not required: the store accepts any mix of real app windows.

## Substitution and ordering rules

- Order: 1, 2, 3 or 3b, 4, 5, 6, 7. The first three should be the Finder previews that were observed; if fewer than three Finder shots pass their gate, lead with the passing ones and fill the rest with companion shots 4, 5 and 7. A listing made only of companion shots is acceptable but weaker; say so to the owner rather than staging a Finder shot.
- A companion shot that includes a preview (Theme page, or Try Preview under Developer Mode) must not be captioned as Finder behaviour. Try Preview needs Developer Mode, which is off by default; do not enable Developer Mode just to get a shot unless the shot is of that page and the caption says so.
- If any gate fails on the store build, record the failure in `docs/validation/` and drop or substitute; never retouch a shot to hide a routing or rendering defect.

## Record to keep for each accepted shot

Build number and version, macOS version, display mode, file name and path of the source sample, date, the matrix row that was observed, and the output of the `sips` check. Keep these in a dated validation record, not in this draft.

## Caption counts

Measured with Python `len()` on 2026-10-10: 25, 20, 23, 27, 29, 23, 35, 30. All are 40 or fewer.
