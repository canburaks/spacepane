# SpacePane app preview film (design version)

The source of a 29.8-second Mac App Store app preview for SpacePane, made on 2026-10-12. This is the hand-animated
version; a Remotion version was made separately by another session and lives elsewhere. Nothing here has been
uploaded.

| | |
|---|---|
| Deliverable | `docs/release/store-listing/app-preview/design/spacepane-preview.mp4` |
| Poster frame | `docs/release/store-listing/app-preview/design/poster.png` (the frame at 5.0 s) |
| Source | this folder: `film/` (the film), `footage/` (the real captures), `render.mjs` (the renderer) |
| Work files | `.build/store-preview/design/` (frames, contact sheets; ignored by git) |

## Render

```sh
node script/store-preview/design/render.mjs
```

About 15 seconds for the frames and 70 seconds for the encode on the Mac it was made on (18 cores). It needs:

- Node (made with v26.8.2).
- Playwright and its Chromium, taken from the `node_modules` of the `spacepane-web` repository (`SPACEPANE_WEB_REPO`, default `../spacepane-web` beside this repository; made with Playwright 1.63.0, Chromium headless shell
  153.0.8010.12). If the browser is missing: `cd ../spacepane-web && npx playwright install chromium`. Nothing is installed here
  and nothing in the website repository is changed.
- `ffmpeg` and `ffprobe` on `PATH`, built with libx264 (made with ffmpeg 9.0.1).
- macOS, for the system fonts: SF Pro through `system-ui`, and New York Italic and SF Mono read from
  `/System/Library/Fonts` at render time. No font is copied into the repository.

Other modes:

```sh
node script/store-preview/design/render.mjs --stills 1.25,5,12.5   # single frames (seconds), 1920x1080 PNG
node script/store-preview/design/render.mjs --sheet 9.3,10.0,12    # contact sheet: 12 frames between two times
node script/store-preview/design/render.mjs --draft                # 1x frames, every third frame, no encode
node script/store-preview/design/render.mjs --encode-only          # re-encode the frames already rendered
```

To look at the film in a browser, open `film/index.html?t=12.5` (one frame) or `?play` (a rough real-time run; the
end card's icon is shown whole there, because a page opened from disk may not read the SVG as text).

### How it is made

`film/film.js` exposes `window.renderAt(seconds)`, which lays out exactly one frame from the time value: no timers,
no CSS animations, no randomness. `render.mjs` opens the page in headless Chromium, calls `renderAt(frame / 30)` for
each of the 894 frames, captures each at twice the output size (3840 x 2160), and has ffmpeg scale them to
1920 x 1080 with Lanczos and encode. Nothing is recorded in real time and nothing on the visible screen is touched.

Checks built into the render:

- One frame is rendered twice, out of order, and the two PNGs must be byte-identical.
- A capture drawn larger than its own pixels stops the render (`placeRig` in `film.js`). The largest scale used
  is 0.988 of native (measured over all 894 frames).
- A missing footage file or a page error stops the render.

Repeatability, as measured on 2026-10-12: two complete renders from scratch, with the default eight workers, gave
byte-identical `spacepane-preview.mp4` and `poster.png`. Three things were needed for that, and each is commented
in `render.mjs`:

- Each worker is its own browser and takes a fixed, contiguous run of frames. With pages sharing one browser, or
  frames handed out first come first served, more than half the frames differed between runs by one level in a few
  pixels (PSNR 62 dB or better: not visible, but not identical).
- x264 runs on one thread. With its default threading under a VBV limit, two encodes of the same frames differed.
- The fine dither added before encoding is a fixed pattern, not per-frame grain.

A different `--workers` count changes which frames a page draws in sequence and may change the file at that
one-level scale. Another version of Chromium, ffmpeg or macOS (fonts) will change it more.

## Art direction

**One idea: the Space bar.** The product is "press Space, see inside", the icon carries a space bar, and the
website's hero sets a keycap inside its headline. So the film has one actor, a keycap, and one rule: every preview
is brought up by a press of it.

- It starts inside the opening headline, "Press [Space]", on the website's warm paper. The first press floods the
  frame with the aurora from the key outward, and the Quick Look panel opens out of the selected row of the real
  Finder window. Paper is "before Space"; color is "inside".
- The key then drops to the corner of the frame and stays there. Each later press does four things in order: the
  file label changes (a file is selected), the key goes down, the next preview springs up in front of the last, and
  the background takes that scene's color in a ring from the key.
- The app's own window (File Types, Theme) needs no key, so the key leaves by the bottom edge and the layout turns
  from a split to a centered one.
- On the end card the icon builds from its own bars; its space bar is pressed once, and that last press brings up
  the name.

**Palette.** The body uses the gradients of the approved store screenshots, scene for scene
(`script/store-screenshots/compose.sh`), so the video and the screenshots that sit beside it on the product page
are one family. The film adds a deeper left edge for the headline and two slow lights so the field is alive. The
bookends are the website's paper and navy (`DESIGN.md` in the `spacepane-web` repository), because that is where a keycap and a serif accent are
at home, and because paper against color makes the first press visible with no sound.

**Type.** SF Pro Display Bold, 78 px on an 84 px line, tight tracking, white on color and navy on paper, with one
word per headline in New York Italic, the website's heading accent. File names are SF Mono in a capsule with a
folded-corner file glyph. Headlines enter by word from behind a line mask and leave together, quicker than they
came.

**Grid.** 1920 x 1080 with a 96 px margin. Headline column from 96 to about 640; captures start at 704 and run off
the right and bottom edges, so the interface is shown large. The key rests at the bottom of the column. The coda
and the end card are centered.

**Motion.** Camera moves are eased in and out and interpolate scale geometrically; a slow drift whose speed ramps
up from zero keeps every held shot alive without a start or stop. Panels arrive opaque on a spring, in front of the
one that is leaving, so two previews are never read through each other. Dissolves are used only between two
captures of the same window at the same pixels (SQLite Summary to Table, GitHub Dark to Aurora). A page change in
the app is a cut, as it is in the app. Easing curves are the website's `ease-soft` and `ease-glide` plus damped
springs.

**Annotations.** Three kinds of mark are drawn over captures, in amber, mint and white, in a style the app does not
use: rings and numbered dots on the two concealed values with a rule under the banner's count, a ring on the
"Source read only: Yes" row, and an arc with an arrowhead under the 3D model. They sit in the capture's own pixel
coordinates so they stay locked to it.

## Storyboard

Times in seconds at 30 fps. Headlines are the approved ones from `docs/release/app-store-listing.md`, broken into
lines; the first drops its full stop after the keycap.

| Time | Scene | Headline | Footage |
|---|---|---|---|
| 0.0 – 1.25 | Hook, on paper. Finder window with `settings.json` selected; a ring points at the key | Press [Space] | `1-finder.png` |
| 1.25 – 5.3 | Press. Color floods from the key; the panel opens out of the selected row; the camera slides onto the Outline view | Press [Space] / See what's *really* inside. | `1-finder.png`, `1-panel.png` |
| 5.3 – 9.5 | The key drops to the corner. Push to the banner; Outline gives way to Source; the two concealed values are ringed and numbered; the banner's count is underlined | Likely secrets concealed, and *counted*. | `1-panel.png`, `2-panel.png` |
| 9.5 – 13.0 | Press. SQLite Summary with the read-only row ringed, then the Table view as the camera pulls back | A database at a glance. *Read-only.* | `4-panel-summary.png`, `4-panel-table.png` |
| 13.0 – 15.4 | Press. ZIP tree | Look inside. *Nothing* is extracted. | `5-panel.png` |
| 15.4 – 17.8 | Press. Notebook, Rendered view | Notebooks as saved. *Never* run. | `3-panel.png` |
| 17.8 – 20.0 | Press. Markdown, Rendered view | Markdown, *ready* to read. | `6-panel.png` |
| 20.0 – 22.2 | The key leaves. The app window rises: File Types | A switch for *every* file type. | `8-app.png` |
| 22.2 – 24.4 | Theme page; the scheme changes from GitHub Dark to Aurora and the live sample recolors | *Your* colors. *Your* type. | `9-app.png`, `9-app-aurora.png` |
| 24.4 – 27.2 | End card, on paper. The icon builds, its space bar is pressed, the name comes up | SpacePane *for Quick Look* / Preview JSON, SQLite, Markdown | `icon.svg` |

Poster frame: 5.0 s, the Outline view under "Press [Space] / See what's really inside." It is also Apple's default
poster time, so the preview is right even if the poster is never set by hand.

## Truthfulness

- Every pixel of app interface is from `footage/`: the window captures made on 2026-10-11 for the store screenshots
  (`.build/store-screenshots/raw/`, copied here unchanged so the film can be rendered from the repository), plus
  the Theme page from the Aurora set (`raw-aurora/9-app.png`). `footage/icon.svg` is `Configuration/AppIcon.svg`.
- Captures are moved, scaled down, cropped by the frame, wiped and cross-faded. None is retouched or drawn on
  except by the annotation marks listed above, and none is shown above its own pixels.
- The panel sits over the Finder window at the offset the two windows had on screen (`geometry.tsv`).
- The Outline-to-Source change is a roll-down between two captures whose title bar, view control and banner share
  the same pixels at the top left. The Source capture's panel is wider, so the control's segments are wider; the
  frame shows only the left part.
- The 3D model does not move: there is one capture of it. The arc is a hint, and the headline is the approved one.
- No Finder thumbnail, icon view or typing is shown. No prices, rankings, performance figures or other apps' names
  appear in the copy. "Open with Xcode" appears in the captured title bars, as it does in the approved screenshots.
- The captures come from the local development-signed build, as the screenshots do. The same gate applies: confirm
  each Finder scene on the TestFlight install before submission (`docs/release/store-listing/screenshots.md`).

## Apple's specification, as read on 2026-10-12

Source: <https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications>
(read through a page-to-text fetch, not in a browser). For macOS the page gives:

| Requirement | Apple | This file |
|---|---|---|
| Resolution | 1920 x 1080, landscape only | 1920 x 1080 |
| Length | 15 to 30 seconds | 29.8 s |
| Frame rate | at most 30 fps | 30 fps, progressive |
| Video | H.264, progressive, up to High Profile Level 4.0, target 10 to 12 Mbps (or ProRes 422 HQ) | H.264 High, Level 4.0, yuv420p, BT.709, 11.1 Mbps on average; the busiest second is about 18.7 Mbps |
| Audio | stereo, 256 kbps AAC, 44.1 or 48 kHz, one 2-channel track | one stereo AAC-LC track, 48 kHz, silent |
| Container | `.mov`, `.m4v` or `.mp4` | `.mp4`, fast start |
| File size | at most 500 MB | about 41 MB |
| Count | up to 3 per language | 1 |
| Default poster frame | 5 seconds | the recommended poster is the 5.0 s frame |

Also read the same day:

- <https://developer.apple.com/support/app-previews/>: previews use captured footage and "must show only content
  within the app itself"; overlays such as touch hotspots and copy are allowed; transitions must not imply
  functionality the app lacks; text must be legible and stay long enough to read; no prices; audio is optional and
  previews play muted by default.
- <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets>: upload
  under App Previews and Screenshots; the poster frame is set in Media Manager and cannot be changed after approval.
  That page is long and its last few thousand characters were not read.

The specification page lists the audio format but does not say an audio track is required. A silent stereo track is
included so the file matches the listed format either way. The encoder's 256 kbps is a ceiling; a silent track
comes out at about 2 kbps.

Encode quality was checked against the rendered frames: luma SSIM is 0.990 or better on every frame (mean 0.992).
A first encode with per-frame grain fell apart in the wipes at this bit rate, which is why the dither is fixed.

## Not done, and not checked

- The file has not been uploaded, so App Store Connect's own validation has not been seen. Whether it reads
  "target 10 to 12 Mbps" as an average (met) or as a ceiling for every second (not met in the transitions) is not
  known; `-bufsize` in `render.mjs` is the setting to lower if it objects.
- Whether App Review accepts staged stills in place of a continuous screen recording is not known. Apple's guidance
  speaks of captured footage; everything shown is captured from the app, but nothing was captured in motion.
- No motion blur. Fast moves (panel springs, the key's drop) are sharp frames at 30 fps.
- No sound design. The track is silent.
- The film was judged from rendered frames and contact sheets, not watched in real-time playback.
- On the Theme scene the Aurora tile that is chosen is below the bottom edge of the frame; the viewer sees the live
  sample recolor and the GitHub Dark tick disappear.
- In the notebook and Markdown scenes the panel is shown at about 0.59 of its pixels, because its content sits in
  the middle of a wide window; the body text there is small at store size and the headline carries the scene.
