# SpacePane Mac App Store app preview (Remotion)

A 29-second, 1920 x 1080, 30 fps app preview for the SpacePane product page, built with
[Remotion](https://www.remotion.dev) from the real window captures in
`.build/store-screenshots/raw/`. One composition (`SpacePanePreview`), one scene per file.

Deliverables (written by `npm run render`):

- `docs/release/store-listing/app-preview/remotion/spacepane-preview.mp4`
- `docs/release/store-listing/app-preview/remotion/poster.png` (recommended poster frame, 4.33 s)

Nothing here ships in the app. This folder is tooling for a store asset only.

## Render

```sh
cd script/store-preview/remotion
npm ci                  # exact versions from package-lock.json; first run downloads Remotion's headless Chrome
npm run render          # = ./scripts/render.sh
```

`render.sh` does, in order: copy the captures and icon into `public/` and synthesise the dither tile
(`scripts/make-assets.mjs`); synthesise the soundtrack (`scripts/make-audio.mjs`); render a ProRes 422 HQ
intermediate with Remotion into `.build/store-preview/remotion/` (about 600 MB, git-ignored); two-pass encode
H.264 High@4.0 plus 256 kbps AAC with ffmpeg; export the poster still. About 50 s on an Apple silicon Mac.

Other commands: `npm run studio` (Remotion Studio), `npm run typecheck`,
`SKIP_REMOTION=1 npm run render` (re-encode from the existing intermediate),
`scripts/contact-sheets.sh video.mp4 outdir [seconds]` (frame sheets for review).

Requirements: Node 20 or later (developed on 26), `ffmpeg` and `ffprobe` on PATH, macOS (the final encode uses
`aac_at`, Apple's AudioToolbox AAC encoder, because ffmpeg's native `aac` encoder ignores the 256 kbps target on
quiet material and wrote about 41 kbps). Fonts are the macOS system fonts (SF Pro via `-apple-system`, New York
for the italic accent), so frames render correctly only on a Mac.

Pinned: `remotion` and `@remotion/cli` 4.0.534, `react` and `react-dom` 19.2.0, TypeScript 5.9.3.

## Apple's specification, as verified

Read on 2026-10-12 from
<https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications>
(the upload page, <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots>,
adds only the poster-frame procedure and says previews must meet guidelines 2.3.3 and 2.3.4):

| Item | Apple's Mac requirement | This file |
|---|---|---|
| Resolution | 1920 x 1080, landscape only | 1920 x 1080 |
| Duration | 15 to 30 s | 29.00 s video (container 29.01 s) |
| Frame rate | 30 fps maximum | 30 fps, progressive |
| Container | .mov, .m4v, .mp4 (H.264); .mov only for ProRes | .mp4 |
| H.264 | Progressive, up to High Profile Level 4.0, target 10 to 12 Mbps | High@4.0, 10.7 Mbps, yuv420p, BT.709 |
| Audio (H.264) | Stereo AAC, 256 kbps, 44.1 or 48 kHz; all tracks enabled | one stereo AAC-LC track, 256 kbps, 48 kHz |
| Size | 500 MB maximum | about 39 MB |
| Previews | up to 3 per device size and language | one |
| Poster frame | default at 5 s, owner can choose | `poster.png` (frame 130, 4.33 s) |
| Order | previews show before screenshots on Mac | n/a |

An audio track is therefore expected. It is fully synthesised (a soft key thunk on the Space press, faint ticks at
scene changes, a quiet chord under the end card; no samples, no third-party audio). The video reads with the sound off.

Guideline 2.3.4 (App Review Guidelines, same date): previews "may only use video screen captures of the app itself",
and textual or video overlays are allowed to explain things. See Weaknesses for how this video sits against that.

## Storyboard (30 fps, 870 frames, scenes overlap 0.4 s)

| Time | Scene (file) | Headline | Source capture | Motion |
|---|---|---|---|---|
| 0.0 to 5.0 | Hook (`HookScene`) | "Press Space. See what's really inside." | `1-finder`, `1-panel` | Keycap press (0.8 s); headline shrinks to the header; Finder and the Quick Look panel rise in their real relative placement; camera settles on the panel |
| 4.6 to 9.2 | Secrets (`SecretsScene`) | "Likely secrets concealed, and counted." | `2-panel` (Source view) | Dissolve from Outline; push to 1:1 on the findings banner and the two `••••` values; amber rings and a dim |
| 8.8 to 12.6 | Database (`DatabaseScene`) | "A database at a glance. Read-only." | `4-panel-table`, `4-panel-summary` | Push in on the table, dissolve to Summary, ring on "Source read only: Yes" |
| 12.2 to 15.4 | Archive (`ArchiveScene`) | "Look inside. Nothing is extracted." | `5-panel` | Window fills the frame; ring on the listing counts |
| 15.0 to 18.1 | Notebook (`NotebookScene`) | "Notebooks as saved. Never run." | `3-panel` (Rendered) | Push to code cell and saved output; dim and ring |
| 17.7 to 20.6 | Markdown (`MarkdownScene`) | "Markdown, ready to read." | `6-panel` | Push in, then a pan down the rendered document |
| 20.2 to 23.2 | Model (`ModelScene`) | "Models you can turn." and "STEP and IGES are off until you switch them on." | `7-panel` | Push toward the gear and the view buttons |
| 22.8 to 24.9 | File Types (`SettingsScene`) | "A switch for every file type." | `8-app` | Push in on the companion window |
| 24.9 to 26.8 | Theme (same scene) | "Your colors. Your type." | `9-app` | Dissolve to Theme (sidebar selection changes), hold |
| 26.4 to 29.0 | End card (`EndScene`) | "SpacePane for Quick Look", "Preview JSON, SQLite, Markdown" | `public/icon.svg` | Icon pops with a violet glow, text rises |

Where things live: `src/theme/tokens.ts` (brand tokens, easings, springs, layout), `src/theme/timing.ts` (every
duration and start frame), `src/data/captures.ts` (capture names and native sizes),
`src/components/` (Background, Header, Stage, Camera, Win, Spotlight, Keycap, `view.ts` camera maths), `src/scenes/`.

## How the truthfulness rules are kept

- Every pixel of app UI is a real capture, GitHub Dark scheme (the owner-chosen look). Captures are moved, scaled,
  masked, cross-faded and dimmed; nothing is drawn, retyped or edited inside them.
- Camera magnification is capped at 1.0 (one capture pixel per output pixel, `MAX_SCALE` in `components/view.ts`); wider
  framings are downscales.
- The only additions are the gradient background, headline and eyebrow text, the keycap, the icon, window shadows, a
  dim-and-ring highlight over the capture (`Spotlight`), and a synthesised soundtrack. The rings mark things that are
  in the capture (the findings banner, the `••••` values, "Source read only", the listing counts, the saved output).
- No Finder thumbnails, no icon view, no prices, no rankings, no other apps' names, no performance figures, no claim
  that Finder always uses SpacePane. Headlines are the owner-approved ones in `docs/release/app-store-listing.md`
  (the serif italic is typography only). The eyebrow labels (JSON, SQLite, ZIP, Jupyter, Markdown, STEP 3D, File
  Types, Theme) name the format shown. The End card line is the store subtitle.
- No Apple marks drawn. The Finder window and Quick Look panel appear only as the real captures.

## Remotion licence (read 2026-10-12, summarised from the project's LICENSE.md; the owner should confirm)

Source: <https://github.com/remotion-dev/remotion/blob/main/LICENSE.md> and <https://www.remotion.dev/docs/license>.

- Free licence: individuals; for-profit organisations with up to 3 employees; non-profit or not-for-profit
  organisations; anyone evaluating Remotion and not yet using it commercially. Free users may use it commercially to
  make videos and images.
- Everyone else needs a paid Company Licence (pricing at <https://remotion.pro>); it also adds prioritised support.
- You may not copy or modify Remotion's code to sell, rent, license, relicense or sublicense your own derivative of it.
  Software is provided as is. Free-tier support is best effort. The page says the licence changes slightly in Remotion 5.
- Only the rendered video leaves this folder; no Remotion code ships in the app or on the website. Whether the
  publisher's headcount and form fit the free tier is the owner's call.

## Weaknesses and things not verified

- Guideline 2.3.4 asks for "video screen captures of the app itself". This preview is built from still window
  captures with motion added, plus about 4 s of graphics with no app UI (the 1.5 s keycap hero and the 2.8 s end card).
  Apple's wording may or may not accept stills in motion; nobody has submitted it. A real screen recording of the
  select, Space, switch-view flow would be safer and would show true Quick Look behaviour. The opening Finder and
  Quick Look "appearance" is a staged reveal of two real captures, not a recording of the panel opening.
- The Outline-to-Source and Table-to-Summary changes are cross-dissolves between separate captures, not a recorded
  view switch. The Outline-to-Source dissolve briefly overlays two differently sized windows.
- Text inside the app is small at the store's thumbnail size (the app's own text is about 11 to 13 pt). Zooms reach
  at most 1:1, so the headlines carry the message and the UI is detail.
- The archive scene shows macOS's own "Uncompress" button in the capture's title bar (mostly hidden by the header
  mask in the held view, visible in the first second). It sits next to "Nothing is extracted"; owner may want to
  reword or reshoot.
- Findings, concealment, STEP and the other scenes were seen only on the development-signed local build
  (`docs/release/store-listing/screenshots.md`). Nothing here was checked on a store-signed build, and the
  claim-check table in the listing still applies to every scene.
- Not checked: playback in App Store Connect's uploader (it processes up to 24 h), QuickTime/Safari playback on other
  Macs, a sound-on listen (sound is synthesised and was checked only by its levels: -3 dBFS peak, about -35 dB RMS),
  colour on a wide-gamut display (BT.709 tagged; the render is sRGB), the 3 s poster at store size.
- Fonts depend on the render machine's system fonts. Re-rendering elsewhere changes glyph shapes.
- A one-pass ProRes then H.264 pipeline was chosen to keep gradients clean; banding was checked on a 4x contrast crop
  of the end card and none was visible, but only on that frame.
