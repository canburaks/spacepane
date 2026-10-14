# Expansion research: creative-production files (design, photo, video, audio, 3D, games)

Researched 2026-10-13 (Europe/Istanbul). One of eleven parallel angle reports for the post-CAD expansion; this one covers designers, illustrators, photographers, video editors, audio producers, and 3D and game artists. It builds on [the competitor landscape](../2026-10-05-competitor-landscape.md) and [the unique-feature opportunities](../2026-10-05-unique-feature-opportunities.md). Everything here is a proposal, not a plan commitment.

## Method and limits

**Evidence labels.** **[V]** verified: I opened the source or ran the check on this Mac. **[VC]** vendor claim I opened. **[S]** a search-result snippet I did not open. **[I]** my inference or prior knowledge, not verified in this session.

**What I ran locally (macOS 27.2, Xcode SDK 27.0).** A Swift probe of `UTType` declarations for about 250 suffixes; `CGImageSourceCopyTypeIdentifiers()`; `MDLAsset.canImportFileExtension`; the manifests of the system Quick Look app extensions (`pluginkit`, `plutil`); `qlmanage -m`; a scan of this repository's `FormatCatalog.json`. Caveats: the declarations I saw include types exported by apps installed on this Mac (for example `com.autodesk.mac.fbx`); I did not separate stock macOS from third-party declarations. `qlmanage -t` timed out for every file in this sandbox (even plain text), so I could not observe what Finder shows for any file. "Native today" below therefore means "which system provider claims the type", not an observed Finder result, and it is for macOS 27.2 only, not the macOS 15 baseline.

**What I could not do.** The iTunes Search API (`itunes.apple.com/search`) returned HTTP 403 from both `curl` and WebFetch here, so I did not run the bulk App Store search. Competitor checks used web search ("<format> quick look mac", "<format> Finder preview") plus single store pages, and cross-read the landscape document. A search that finds nothing is weak evidence of absence; I label it "none found", never "none exists". I did not verify prices unless stated.

**Repository check.** None of the suffixes in this report except `.ply` and `.stl` are in the 305 suffixes of `FormatCatalog.json` **[V]**. Existing building blocks I counted on: the Metal mesh renderer (16 MiB input and 500,000-triangle caps, vertex colours and textures ignored, [decision 024](../../decisions/024-mesh-formats.md)), the image-pages view with decode admission, the facts header, the findings banner, the sortable table, the MIDI transport with sound-bank loading (`NativeMIDIPlayback.swift`), the shared `ZIPArchiveReader`, and the content-thumbnail rules of [decision 022](../../decisions/022-content-thumbnails.md).

## Key findings

1. **Vendor-bound previews go dark, and that is the gap.** Creative apps ship their own Quick Look extension, so a Mac without the app shows a generic icon, and several vendor extensions broke on macOS 15 and later: Krita 5.3 (users report no previews, a regression from 5.2.x, bug reopened, **[V]** [thread](https://krita-artists.org/t/no-preview-for-kra-thumbnail-after-5-3-update-on-mac/177587)), Aseprite (thumbnails missing on Sequoia, maintainer confirms, GitHub issue #5009 open, **[V]** [thread](https://community.aseprite.org/t/mac-file-thumbnails-not-showing/25109)), Affinity (Finder previews lost on macOS 15 until Affinity 2.5.6, **[S]** [report](https://www.sir-apfelot.de/affinity-update-endlich-wieder-thumbnail-und-quick-look-vorschau-63507/)), and the older PSB plug-in (its developer asks buyers not to purchase it for macOS 15+, **[S]**). None of the eight general competitors claims any of these file types (landscape document **[VC]**; Unfold's site lists no creative types **[V]**).
2. **The two cheapest, least contested wins are LUTs and colour palettes.** Both are small, well-specified, unclaimed by macOS (dynamic types for `.cube`, `.3dl`, `.ase`, `.aco`, `.act`, `.gpl` on this Mac **[V]**), parsed from text or simple big-endian binary, and both can produce a privacy-safe, content-bearing Finder thumbnail (a swatch strip, a graded ramp). That also closes the "generic thumbnails" gap the landscape document names.
3. **Some of the obvious candidates already have a specialist.** Ableton `.als` now has ALS Preview (arrangement preview, tempo, plugins, samples, macOS 15+, listed as available from 1 November 2026 **[VC]** [site](https://als-preview.de)). PSB has PSB Quick Look HD on the Mac App Store (macOS 15.2+ **[VC]** [site](https://psb-quick-look-plugin.com)). GLB has Eyemesh and MakersPreview; FBX and `.blend` have iPreview and Eyemesh **[VC]**. Lottie has Code Peek+ **[VC]** and Mottie **[VC]**. Lead with the types nobody covers.
4. **macOS 27.2 already previews more than the brief assumes.** Apple's `HydraQLPreviewExtension` claims USD, USDA, USDC, MaterialX, Alembic, STL, OBJ and PLY; `RAQLPreviewExtension` claims `.reality` and USDZ; ImageIO decodes DDS, KTX, KTX2, PVR, ASTC, TGA, Radiance HDR, OpenEXR, PSD and JPEG XL; Icon Composer `.icon` has an Apple preview extension **[V]**. Not natively handled: glTF/GLB (`MDLAsset.canImportFileExtension` is false for `glb` and `gltf`), FBX, `.blend`, `.vox`, splats, PSB (absent from the ImageIO list), LUTs, palettes, SoundFont, tracker modules, timelines **[V]**.
5. **A feasible insight layer exists even without sibling files.** Reference lists labelled "not checked" (project media, plug-ins, fonts), fonts used versus fonts installed (a system font query, not a sibling-file read, **[I]**, needs a spike), absolute paths and user names embedded in a project (a leak lens that fits Safety Lens), Lottie expressions and remote image URLs, and Unity packages that carry Editor scripts. These are the creative-file equivalent of the existing findings banner.
6. **Permissive routes exist for every Add-level candidate, and two common routes are blocked.** libopenmpt BSD-3-Clause, lottie-ios Apache-2.0, cgltf MIT, ufbx MIT or Unlicense, MetalSplatter MIT, spz MIT, OpenTimelineIO Apache-2.0 **[V]**. The chiptune libraries I know of (game-music-emu, libsidplayfp) are LGPL or GPL **[I]**, so NSF, SPC, VGM and SID are ruled out. The GIMP XCF specification text is GPL **[V]**: write a parser from the described layout, copy no code or text.
7. **Apple is moving into Gaussian splats on macOS 27.** An Apple engineer's reply in a developer forum thread says Preview can export `.ply` splats to USD and that `GaussianSplatComponent` works on macOS **[V]** ([thread](https://developer.apple.com/forums/thread/843416)). That is macOS 27 only, so it does not help the macOS 15 baseline, but it shortens the window in which a splat preview is distinctive.
8. **One policy decision is needed before design-file previews.** An embedded design preview is the file's actual content. [Decision 022](../../decisions/022-content-thumbnails.md) keeps thumbnails content-free unless a format's policy is `content`. Recommendation **[I]**: palettes and LUTs get synthetic content thumbnails; design-document thumbnails stay generic unless the user opts in, even though the vendors' own thumbnailers show the picture.

## Ranked candidates

Effort: S = days, M = 1 to 2 weeks, L = several weeks (per candidate, including localization and fixtures). "Native" is macOS 27.2 provider evidence, see the limits above.

| # | Candidate (suffixes) | Audience | macOS native today | Quick Look competitor coverage | Route and licence | Reuses | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | LUTs: `.cube`, `.3dl`, `.csp`; ASC CDL `.cdl`, `.ccc`, `.cc` | Colourists, editors, photographers | None. Dynamic types, no provider | None found. Standalone apps only: Lutme, IWLTBAP LUTs Previewer, LUT Tuner **[S]** | Own parser from the Adobe Cube spec and Blackmagic notes. No dependency | Image pages, facts header, findings banner, content thumbnail | S–M | **Lead with** |
| 2 | Colour palettes and tokens: `.ase`, `.aco`, `.act`, `.gpl`, `.clr`, `.sketchpalette`, Procreate `.swatches`, DTCG `.tokens`/`.tokens.json` | Designers, illustrators, front-end developers | `.clr` has a declared type but no preview provider seen. The rest are dynamic | None among the eight. Simple Color Palette (own format), Art View ($25, ASE), QuickLookASE (2016) **[S]** | Own parsers. MIT [ColorPaletteCodable](https://github.com/dagronf/ColorPaletteCodable) as a test oracle | Sortable table with a colour column, facts header, thumbnail | S–M | **Lead with** |
| 3 | Design documents without the app: `.sketch`, `.fig`, `.procreate`, `.kra`, `.ora`; later `.xd`, Affinity, `.clip`, `.xcf` | Designers' collaborators, developers, clients | None. Vendor extensions only when the app is installed; some broken | None among the eight. Art View covers InDesign, Illustrator, ASE **[S]** | ZIP reader plus a small manifest per format. No dependency | Image pages, facts header, listing tree, findings | M (first five) | **Lead with** (as a family) |
| 4 | glTF and GLB: `.glb`, `.gltf` | 3D and web artists, AI-3D users | None (ModelIO cannot import; SceneKit extension claims `public.3d-content`, behaviour unverified) | Eyemesh, MakersPreview **[VC]**; GLTFQuickLook (2022, legacy plug-in) **[S]** | Own bounded parser from the Khronos spec; cgltf (MIT) as cross-check | Metal mesh renderer plus a material-colour contract change | M | **Add** |
| 5 | Gaussian splats: `.splat`, `.spz`, 3DGS `.ply` | Photogrammetry, NeRF and splat users | None before macOS 27; RealityKit API on 27 only | None found | Own renderer or MetalSplatter (MIT); spz (MIT) spec | Metal viewer foundation; new splat pass | L | **Add** (spike first) |
| 6 | Lottie and dotLottie: `.lottie`, Lottie `.json` | Motion designers, app developers | None | Code Peek+ (JSON) **[VC]**; Mottie, whose Quick Look claim names the Files app **[VC]** | lottie-ios, Apache-2.0, behind a bounded pre-validator | Facts header, findings banner, JSON sniffing | M | **Add** |
| 7 | Edit timelines `.edl`, `.otio`, `.fcpxml`; captions `.scc`, EBU `.stl`, `.itt` | Editors, assistant editors, post and localization | SCC is declared as text; the rest are dynamic or unclaimed | None found for timelines; Unfold's 10 subtitle formats exclude SCC, EBU STL, iTT **[V]** | Own parsers; OTIO schema is Apache-2.0 | Subtitle pipeline, facts header, table; lane drawing is new | M (S for captions) | **Add** |
| 8 | Pixel art: `.aseprite`/`.ase`, `.piskel`, `.pxo` | Indie developers, pixel artists | None | None found; Aseprite's own extension is broken on Sequoia **[V]** | Own parser from the published spec (zlib via Compression) | Image pages plus a frame timer; palette strip | M | **Add** |
| 9 | Tracker modules: `.mod`, `.xm`, `.it`, `.s3m`, `.mptm` | Chiptune and demoscene hobbyists | None | None found | libopenmpt, BSD-3-Clause **[V]** | MIDI-style transport, table (pattern grid), facts | M–L | **Add** (niche but unique) |
| 10 | SoundFont: `.sf2`, `.sf3`, `.sfz` | Producers, game-audio and retro users | `.sf2` declared as audio; no preview seen | None found | Own RIFF reader; `AVAudioUnitSampler` loads `.sf2` **[V]** (SDK header) | Table, MIDI transport and sound-bank code | M | **Add** (niche) |
| 11 | Unity packages `.unitypackage`; later Unity and Godot text scenes | Game developers | None | None found | tar.gz reader the app already has | Listing tree, findings | S (package) | **Add** |
| 12 | Photographer presets and sidecars: `.xmp`, `.lrtemplate`, `.pp3`, `.dop` | Photographers | `.xmp` is text; the rest dynamic | None found | XML and Lua-table readers; no dependency | Outline, table, curve drawing | M | Niche |
| 13 | Reaper projects `.rpp` | Producers on Reaper | None | None found (one search) | Text format reader | Outline, table | S–M | Niche |
| 14 | FBX `.fbx` | Game and DCC artists | None (ModelIO false) | iPreview, Eyemesh **[VC]** | ufbx, MIT or Unlicense **[V]** | Mesh renderer | M | Niche (after GLB) |
| 15 | MagicaVoxel `.vox` | Voxel artists | None | None found | Own reader; spec repo labelled MIT **[V]** | Mesh renderer plus vertex colours | M | Niche |
| 16 | PSB (and layer facts for PSD) | Retouchers, print | PSD via ImageIO; PSB not | PSB Quick Look HD **[VC]** | Own reader from the Adobe spec | Image pages, listing | M–L | Niche |
| 17 | Blender `.blend` (header, version, embedded preview) | Blender users' collaborators | None | iPreview **[VC]**; Blender's own extension when installed **[S]** | Own header reader; zstd | Image pages, facts | M | Niche |
| 18 | ICC profiles `.icc`, `.icm` | Photographers, print, developers | Type declared; no preview seen | None found | Own reader from the ICC spec | Facts, curve plots | M | Niche |
| 19 | Texture facts: `.dds`, `.ktx2`, `.exr`, `.hdr`, `.tga`, `.pvr` | Game and VFX artists | ImageIO decodes all of them **[V]** | QLdds (legacy GPL) **[S]** | Header parsers | Facts header | S–M | Rule out as registered types |
| 20 | Ableton `.als` | Ableton users | None | ALS Preview **[VC]** | Gzip XML | n/a | M | Rule out |

## Candidate sections

### 1. LUTs: `.cube`, `.3dl`, `.csp` and CDL files (Lead with)

**What the preview shows.**
- **Header facts:** title, 1D or 3D, grid size N, input domain, entry count, file size, and any input or output colour-space hint found in the title or comments.
- **Main view:** a before-and-after split of a synthetic test chart rendered through the LUT. The chart is generated in code (grey ramp, saturated primaries and secondaries, a colour-cube slice grid, a skin-tone-like gradient), so no photo is bundled or read.
- **Curves:** neutral-axis response drawn for red, green and blue.
- **Findings:** "identity LUT" detection, out-of-range or clipped lattice points (as a percentage), a domain that is not 0 to 1, a size that suggests a log-to-display transform (a hint only).
- **Thumbnail:** a graded gradient strip. It contains no user content, so it satisfies the privacy rule.
- **CDL files:** slope, offset, power, saturation as numbers plus the same chart.

**Demand evidence.** People already pay for or build standalone LUT viewers: [Lutme](https://editingtools.io/software/lutme) (Mac App Store, previews `.cube` and exports images) **[S]**, IWLTBAP LUTs Previewer **[S]**, and Cut Point Labs [LUT Tuner](https://www.newsshooter.com/2026/08/01/cut-point-labs-lut-tuner-for-mac/) (new August 2026) **[S]**. LUT packs ship dozens of files, and the only way to judge one today is to import it into an editor. `.cube` is a dynamic type with no provider on this Mac **[V]**. Searched: "quick look .cube LUT preview mac finder"; no Quick Look extension found.

**Implementation route.**
- Parsing: `LUT_1D_SIZE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`, `TITLE`, then N cubed rows of three floats, red varying fastest. Adobe's spec link is dead; a [FFmpeg ticket](https://ffmpeg.org/pipermail/ffmpeg-trac/2023-June/066367.html) points to an archived copy and notes that `LUT_3D_INPUT_RANGE` is a different tool's keyword. Blackmagic's [forum notes](https://forum.blackmagicdesign.com/viewtopic.php?p=232952) document that variant. Accept both.
- Interpolation: trilinear for the chart, tetrahedral is what grading tools use **[I]**.
- Bounds: cap N (65 is about 275,000 rows; 129 is about 2.1 million), cap file size, cap tokens per line, checkpoint in the row loop.
- `.3dl` has two layouts (Lustre and Nuke styles) and no header size **[I]**; infer N from the row count. `.csp` (Cinespace) is text **[I]**.
- Licence: none needed.

**Safety and privacy.** Text-only, numeric tokens, no I/O. The `.cube` suffix is also used for Gaussian volumetric data in computational chemistry **[I]**; require a LUT keyword, otherwise fall back to the text path.

**Risks and unknowns.** Spec variants differ by vendor (the domain keyword conflict above). DaVinci Resolve, Premiere Pro or other vendor apps may declare `.cube` and win routing **[I]**, not checked. A built-in test chart is a design choice, not a measured one.

### 2. Colour palettes and design tokens (Lead with)

**What the preview shows.**
- **Swatch grid** with name, hex, RGB, HSL, grouped as the file groups them (ASE groups, GPL name lines).
- **Honest colour models:** CMYK, Lab and spot colours are flagged as "converted for display, approximate".
- **Contrast insight:** pick any swatch as foreground or background and see the WCAG 2.x ratio with AA and AAA results; for palettes of 16 colours or fewer, a matrix of which pairs pass AA for body text.
- **Copy:** hex, rgb(), Swift `Color` and CSS custom property.
- **Design tokens (DTCG):** a token tree with colour chips, aliases resolved (cycle-safe), types shown (dimension, font family, shadow).
- **Thumbnail:** a swatch strip, which is content-bearing and privacy-safe.

**Demand evidence.**
- Sindre Sorhus's [Simple Color Palette](https://sindresorhus.com/simple-color-palette) offers Quick Look and thumbnails for its own format and imports ASE and CLR **[S]**.
- Art View ($25, previews ASE, InDesign, Illustrator) **[S]** ([article](https://creativepro.com/take-a-deeper-look-your-documents-with-art-view/), not opened: HTTP 403).
- QuickLookASE, an open-source plug-in last released in 2016, is dead on macOS 15 **[S]**.
- [Color Palette Finder](https://apps.apple.com/app/id1488149884) is an iPad-designed app that claims thumbnails and Quick Look **[S]**.
- The DTCG specification reached its first stable version (2025.10) on 2025-10-28 **[V]** ([announcement](https://www.w3.org/community/design-tokens/2025/10/28/design-tokens-specification-reaches-first-stable-version/)), and recommends the suffixes `.tokens` and `.tokens.json` **[V]** ([format module](https://www.designtokens.org/tr/2025.10/format/)).
- Searched: "quick look color palette preview mac .ase .aco .gpl"; no general Quick Look app claims palettes.

**Implementation route.**
- **ASE:** magic `ASEF`, big-endian, blocks `0xC001` group start, `0xC002` group end, `0x0001` colour entry, a four-character colour model (`RGB `, `CMYK`, `LAB `, `Gray`), 32-bit floats, a 16-bit colour type **[V]** ([layout notes](http://www.selapa.net/swatches/colors/fileformats.php)). Adobe never published a formal ASE spec; ColorPaletteCodable's author used the same notes **[V]**.
- **ACO and ACT:** Adobe developer documentation (cited by ColorPaletteCodable) **[V]**. Byte layouts from my memory **[I]**.
- **GPL** is text. **`.sketchpalette`** is JSON **[I]**. **Procreate `.swatches`** is documented only by third-party code; a community forum post calls it a JSON text file **[S]**, I recall a ZIP holding JSON **[I]**, and ColorPaletteCodable reads it **[V]**. Unresolved; inspect a real file.
- **`.clr`** is an `NSColorList` archive. Do not hand untrusted bytes to `NSColorList(name:fromFile:)` without checking its secure-coding behaviour; a bounded reader is safer **[I]**.
- **`.ase` collides with Aseprite** (magic `0xA5E0` at byte offset 4 **[V]** per the Aseprite spec) and with 3ds Max ASCII scene export **[I]**. Sniff magic bytes, never the suffix alone.
- **DTCG** shares `.json`, so the JSON adapter needs a content sniff for `$value` and `$type`.
- Dependencies: none required. [ColorPaletteCodable](https://github.com/dagronf/ColorPaletteCodable) is MIT (copyright 2026 Darren Ford), reads and writes ASE, ACO, ACT, CLR, GPL, SketchPalette and Procreate swatches, and supports macOS 10.13 and later **[V]**. Use it as a differential test oracle in the test target only, or adopt it after the dependency audit.

**Safety and privacy.** Fixed record sizes, counts bounded before allocation, names run through the existing text-safety path (hidden-Unicode detector applies to colour names). No sensitive content.

**Risks and unknowns.** Adobe apps installed on a Mac may declare `.ase` and `.aco` and win routing **[I]**, not checked. Procreate `.swatches` structure unconfirmed.

### 3. Design documents without the app (Lead with, as a family)

**What the preview shows.** The file's embedded render at full size, plus facts.
- **Sketch:** pages, artboard names, fonts, app version, saved date. The `.sketch` ZIP holds `meta.json` (pages, artboards, app version, fonts), `document.json`, per-page JSON, `images/` and `previews/`; the preview is the last edited page, stored at full size under 2048 by 2048 and scaled down above that **[V]** ([Sketch file-format page](https://developer.sketch.com/file-format/); the page does not name the preview file).
- **Figma `.fig`:** `thumbnail.png`, `meta.json`, `images/` and the proprietary Kiwi-encoded `canvas.fig` in a ZIP **[S]** ([Grida notes](https://grida.co/docs/wg/feat-fig/)). Reverse-engineered, so Figma can change it at any time. Show the thumbnail and `meta.json` facts only.
- **Procreate `.procreate`:** a ZIP with a `QuickLook` folder holding a low-quality preview image, layer data in a UUID folder, and `Document.archive` **[S]** ([Silicate](https://github.com/Avarel/silicate)).
- **Krita `.kra` and OpenRaster `.ora`:** `mergedimage.png` (preview) and `preview.png` (thumbnail) at the ZIP root **[V]** ([Krita integration README](https://lxr.kde.org/source/graphics/krita/krita/integration/README.md)).
- **Later:** Adobe XD (the app is in maintenance mode and not sold standalone **[S]**, [overview](https://mapsoft.com/adobe-xd-end-of-life/); so `.xd` files outlive the tool), Affinity (embedded preview exists, container format unverified **[S]**), Clip Studio `.clip` **[I]**, GIMP `.xcf` (spec published, no embedded preview, so it needs layer compositing), Paint.NET `.pdn`.
- **Insight layer:** fonts used versus fonts installed ("3 fonts in this design are not on this Mac") through a system font query **[I]**, needs a spike in a Quick Look extension. Layer, page and image counts. Embedded image weight ("38 MB of the 41 MB is bitmaps"). A leak lens: absolute paths, user names and organisation names found in the metadata.

**Demand evidence.**
- The Krita 5.3 regression thread, the Aseprite Sequoia thread, and the Affinity report in key finding 1.
- Adobe community threads show XD users cannot preview `.xd` without the app ([Eagle support note](https://docs-en.eagle.cool/article/224-unable-to-add-adobe-xd-files)) **[S]**.
- `.sketch`, `.fig`, `.procreate`, `.kra` and `.ora` are dynamic types on this Mac **[V]**.
- Searched: "Quick Look .kra .ora procreate sketch preview mac without app", "Affinity afdesign quick look", "Figma .fig quick look". None of the eight general competitors claim any of them.

**Implementation route.** The shared `ZIPArchiveReader` (CRC-checked, encrypted members refused), read only the manifest and one preview member, decode the image through the existing decode-admission path. No dependency. Per-format cost after the first is small (S). Licence: none.

**Safety and privacy.** Bounded member sizes, refuse oversized preview images, never read the large document JSON of a Sketch file (only `meta.json`). Treat the privacy decision in key finding 8 as a gate for Finder thumbnails.

**Risks and unknowns.** Proprietary containers change without notice (Figma says nothing public). Vendor apps that are installed will register their own types and may win routing. Sketch's current Quick Look status could not be checked (its forum thread now redirects).

### 4. glTF and GLB (Add)

**What the preview shows.** The shaded model in the existing Metal viewer, with material base-colour factors per primitive (needs a small contract change, because the renderer ignores colours today), and facts: triangles, vertices, meshes, nodes, materials, textures with pixel sizes, animations with names and durations, skins, `asset.generator`, extensions used and required, and the bounding box in metres (glTF units are metres, so "2.3 m tall" is meaningful **[I]**). A scene outline reuses the tree view.

**Demand evidence.** GLB is the web and AI-generated 3D exchange format; MakersPreview markets GLB "including AI-generated models" **[VC]**. macOS cannot import it: `MDLAsset.canImportFileExtension("glb")` and `("gltf")` are false on macOS 27.2, and Apple's `HydraQLPreviewExtension` does not list glTF **[V]**. The SceneKit preview extension claims `public.3d-content`, which GLB conforms to; I could not verify that it renders glTF. Competitors: Eyemesh (FBX, glTF/GLB with Draco, USDZ and others, 16 or 17 formats) **[VC]** ([Product Hunt](https://www.producthunt.com/p/eyemesh)), MakersPreview **[VC]**, GLTFQuickLook (a 2022 `.qlgenerator`, dead on macOS 15) **[S]** ([Khronos forum](https://community.khronos.org/t/quicklook-gltf-plugin-for-macos/104566)). Searched: "Mac Quick Look glb gltf preview Finder".

**Implementation route.** A GLB is a 12-byte header plus a JSON chunk and a binary chunk. Write a bounded parser in the style of the existing readers (JSON chunk through the repository's bounded JSON reader, accessors validated before allocation). [cgltf](https://github.com/jkuhlmann/cgltf) is MIT (Johannes Kuhlmann, 2018 to 2021) **[V]** and is a single-header C library **[I]**; use it as a cross-check or as the reader if a C target is acceptable. The Khronos licence for the specification text was not visible on the repository page, so I could not verify it. Compressed geometry (`KHR_draco_mesh_compression`, `EXT_meshopt_compression`) and `KHR_texture_basisu` textures need extra decoders (Draco is Apache-2.0 and meshoptimizer is MIT **[I]**, not re-verified): first release states "compressed geometry not shown". A `.gltf` with external `.bin` or image URIs cannot be read (no siblings): show the structure and a "geometry is in a sibling file this preview cannot read" notice.

**Safety and privacy.** Same 16 MiB and 500,000-triangle ceilings as the other meshes; reject index and accessor ranges outside the buffer; never fetch URIs.

**Risks and unknowns.** Apple may add native glTF support later (no evidence either way). If SceneKit's extension does render GLB, routing becomes unpredictable. Competitors already cover this, so the gain is breadth in the 3D set, not uniqueness; it is the largest missing family now that CAD is out.

### 5. Gaussian splats: `.splat`, `.spz`, 3DGS `.ply` (Add, spike first)

**What the preview shows.** An orbitable splat render with depth-sorted, alpha-blended ellipse sprites, plus facts: splat count, bounding box, spherical-harmonic degree, format version, and "showing 200,000 of 3.1 million splats (evenly sampled)".

**Demand evidence.** Splat files are produced by Polycam, Luma, Scaniverse and research code, and there is a market for viewers: Spatial Fields is a paid viewer (PLY, SPZ, LCC) **[S]** ([listing](https://apps.apple.com/app/id6745549629)); PlayCanvas SuperSplat imports `.ply`, `.compressed.ply`, `.splat`, `.sog` **[S]** ([doc](https://developer.playcanvas.com/user-manual/supersplat/editor/import-export/)). No Quick Look extension found. Apple's forum thread confirms macOS 27 ships RealityKit splat APIs and a Preview export path, so this space is moving **[V]** ([thread](https://developer.apple.com/forums/thread/843416)). Today a 3DGS `.ply` would reach the existing PLY mesh reader, which expects faces **[I]**, check.

**Implementation route.**
- [MetalSplatter](https://github.com/scier/MetalSplatter) (MIT per the repository label **[V]**) loads PLY, SPZ and `.splat` and renders on iOS, macOS and visionOS.
- [spz](https://github.com/nianticlabs/spz) is MIT, documents a 32-byte header plus attribute streams in its README, and claims roughly ten times smaller files than PLY **[V]**.
- Own renderer: a per-frame back-to-front sort of at most about 200,000 splats on the CPU or a GPU sort, then instanced quads.
- Files can be hundreds of megabytes (a 3DGS PLY record is a few hundred bytes **[I]**), far above the 16 MiB input cap. Reading must be random-access and sampled: read the header, then every k-th record. A decimated cloud is a legitimate preview if the banner says so.
- Not RealityKit: `GaussianSplatComponent` is macOS 27 only **[V]**, below the macOS 15 baseline.

**Safety and privacy.** Bounded sampled reads, validate every property type and count before allocating, finite-value checks, a render budget.

**Risks and unknowns.** Quality without a proper sort or spherical harmonics looks wrong; time and memory in the extension are unmeasured. Effort L. Recommend a one-week spike measuring a 200,000-splat render in the extension before committing.

### 6. Lottie and dotLottie (Add)

**What the preview shows.** An animated, looping render with a play, pause and scrub bar, and facts: duration, frame rate, canvas size, layer counts by type, shape count, embedded versus external images, fonts, the Bodymovin version, and findings. Two findings fit Safety Lens: expressions present (Lottie allows JavaScript expressions; lottie-ios's support is unverified, so the safe stance is "not run"), and remote image URLs (listed, never fetched).

**Demand evidence.** Code Peek+ lists Lottie JSON previews **[VC]**; Mottie is a free player with `.lottie` thumbnails whose Quick Look sentence names the Files app, so its Finder behaviour is unclear **[VC]** ([listing](https://apps.apple.com/app/id6743446238)). The dotLottie format is a ZIP with a `manifest.json` **[S]** ([spec](https://docs.lottiefiles.com/en/format/dotlottie.md)). Competitors exist, so this is parity plus the findings layer, not a unique claim. Searched: "Lottie .lottie dotLottie quick look macOS finder".

**Implementation route.** [lottie-ios](https://github.com/airbnb/lottie-ios) renders through Core Animation, is Apache-2.0 **[V]** ([LICENSE](https://raw.githubusercontent.com/airbnb/lottie-ios/master/LICENSE)), and is marketed for iOS and macOS **[S]**. Its minimum macOS, memory behaviour and expression support were not verified. Put a bounded pre-validator in front (node count, depth, layer count, asset count) so hostile files never reach it. Lottie `.json` shares the suffix with all JSON, so the JSON adapter needs a content sniff (`v`, `fr`, `ip`, `op`, `layers`), a small shared-contract change. `.lottie` is a dynamic type **[V]**.

**Safety and privacy.** Never load external images or fonts; no network; offline asset provider only. Core Animation rendering is main-thread and not cancellable by design; budget with a frame limit.

**Risks and unknowns.** Dependency weight in an extension, Core Animation rendering in a Quick Look host, and complex files that render slowly. Rive `.riv` is the same idea at a higher cost, see "Ruled out".

### 7. Edit timelines and broadcast captions (Add)

**What the preview shows.**
- **EDL (CMX 3600):** events as lanes drawn to scale on a timeline, with reel, source and record timecode, frame rate and drop-frame from the `FCM` line, and `* FROM CLIP NAME` comments.
- **OpenTimelineIO `.otio`:** tracks, clips, gaps, transitions, rate, duration, and media references (`target_url`).
- **FCPXML:** events, projects, clips, asset references, resolution and frame rate.
- **Insight layer:** a "media references" list (the file paths exactly as stored, with the line "this preview cannot check whether these exist"), mixed frame-rate warnings, a leak lens for absolute paths and user names.
- **Captions:** SCC (CEA-608 hex pairs decoded to text and timing), EBU STL (binary GSI block of 1024 bytes plus 128-byte TTI blocks **[I]**), iTT (a TTML dialect).

**Demand evidence.** No Quick Look extension or Finder summary found for FCPXML, EDL or OTIO. The search returned only converters such as [EDL-X](https://apps.apple.com/app/edl-x/id539666579) and FCPXML tooling **[S]**. SCC is declared as a text-conforming type on this Mac, so macOS likely shows raw text **[V]**; EBU STL and iTT are dynamic **[V]**. Unfold's ten subtitle formats (ASS, LRC, SAMI, SBV, SMI, SRT, SSA, SUB, TTML, VTT) exclude SCC, EBU STL and iTT **[V]**.

**Implementation route.** EDL is line-based text (no free official spec link; ST 258 relates **[I]**). OTIO is JSON under the [Apache-2.0](https://github.com/AcademySoftwareFoundation/OpenTimelineIO) project **[V]**; its field layout is from my memory **[I]**, verify against the schema before writing the reader. FCPXML is XML with Apple's DTD (see [fcp.cafe](https://fcp.cafe/developers/fcpxml/) **[S]**) and the existing bounded `XMLParser` setup (no DOCTYPE) applies. The lane drawing is the only new presentation; the Diagram canvas code may be reusable.

**Premiere `.prproj` (hold).** It is gzip XML with media paths, sequences and bins **[S]** ([py-premiere](https://pypi.org/project/py-premiere/), [Gillware](https://www.gillware.com/video-recovery/premiere-pro-project-recovery/)), but an Adobe employee has said Adobe does not support parsing it and the schema changes between versions **[S]**. A "media list and sequence names" view is feasible but fragile. After Effects `.aep` and AAF were not examined.

**Risks and unknowns.** Interchange files are large (hundreds of thousands of events), so cap events and show "first N". Vendor apps (Resolve, Final Cut) may declare their own types **[I]**, not checked.

### 8. Pixel art: Aseprite and friends (Add)

**What the preview shows.** An animated, nearest-neighbour scaled playback using each frame's duration, a filmstrip, named animation tags, the layer list with visibility and blend mode, the palette strip, and facts (canvas size, colour depth: RGBA, grayscale, indexed; frame count). Bonus formats: Piskel `.piskel` (JSON with embedded PNG frames) and Pixelorama `.pxo` **[I]**.

**Demand evidence.** Aseprite shipped a macOS Quick Look plug-in with 1.3-rc1 **[S]**, which is broken on Sequoia: the maintainer confirmed the deprecated API is the cause and tracks it as issue #5009, with no fixed version stated **[V]** ([thread](https://community.aseprite.org/t/mac-file-thumbnails-not-showing/25109)). No third-party Quick Look found. Searched: "Aseprite .aseprite quick look macOS".

**Implementation route.** The [file-format spec](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md) **[V]**: a 128-byte little-endian header, magic `0xA5E0`, colour depths 32 (RGBA), 16 (grayscale), 8 (indexed), chunks for layers (`0x2004`), cels (`0x2005`), tags (`0x2018`), palette (`0x2019`), slices and tilesets, cel images normally zlib-compressed. The zlib stream needs the Compression framework's raw-deflate mode after skipping the two-byte zlib header **[I]**. The spec document states no licence **[V]**; Aseprite's own source is under a proprietary-style EULA **[I]**. Writing a clean parser from the published layout is the usual approach, but ask the owner to accept that risk. Cap canvas size (for example 4096 by 4096), frames and cels before allocation. `.ase` collides with Adobe Swatch Exchange, sniff the magic (candidate 2).

**Safety and privacy.** Decompression-bomb limits on every cel; draw nothing outside the canvas.

**Risks and unknowns.** A playback timer is a new presentation behaviour (the image-pages view does not animate). Indexed colour with transparent index and tilemap layers add edge cases.

### 9. Tracker modules (Add, niche but unique)

**What the preview shows.** Playback with the MIDI-style transport, the song title and format, the tracker "message", sample and instrument names (a demoscene art form in itself), channel, pattern and order counts, duration, and a pattern grid in the sortable-table view (rows by channels, in tracker notation).

**Demand evidence.** None found for Quick Look (search: "quick look tracker module mod xm it s3m macOS libopenmpt"). A forum thread asks how to play modules on a Mac and answers with third-party libraries **[S]** ([Xojo thread](https://forum.xojo.com/t/mac-os-x-playing-tracker-modules-mod-xm-it-s3m/20137)). The audience is small and loyal.

**Implementation route.** [libopenmpt](https://github.com/OpenMPT/openmpt) is BSD-3-Clause, with the licence text at the repository root `LICENSE` file **[V]**; it renders MOD, XM, S3M, IT, MPTM and dozens of legacy formats **[V]**, and has no required third-party dependencies **[I]**. It needs a C++ target in the Swift package and an `AVAudioSourceNode` feed. A metadata-only load (skip samples) keeps the listing fast and cheap **[I]**, verify the control name. Chiptune formats are out: NSF, SPC and VGM readers I know of are LGPL, and SID players are GPL **[I]**, not re-verified.

**Safety and privacy.** Render time and memory are bounded by duration and sample budgets; modules are untrusted binary inputs, so fuzz the integration; stop playback on cancellation.

**Risks and unknowns.** Library size and build integration (Effort M–L), real-time audio inside the Quick Look host (the MIDI path proves audio works there, **[I]** for the sandbox).

### 10. SoundFont (Add, niche)

**What the preview shows.** The bank name, copyright and comment (RIFF INFO chunks), preset list by bank and program with General MIDI names, instrument and sample counts, sample rates, total sample size, and an audition keyboard that plays a note through the selected preset.

**Demand evidence.** No Quick Look found; browsing presets needs an editor such as [Polyphone](https://www.polyphone.io/en/documentation/manual/soundfont-explorer) **[S]**. `.sf2` is declared as an audio type on this Mac, which may attract Apple's audio generator, behaviour not observed **[V]** for the declaration. Searched: "SoundFont sf2 quick look mac preview presets".

**Implementation route.** RIFF `sfbk` with INFO, `sdta` and `pdta` lists; read INFO and `pdta` (`phdr`, `inst`, `shdr`) and skip `sdta` by size, so a 500 MB bank costs a few kilobytes of reading. Audition uses `AVAudioUnitSampler.loadSoundBankInstrumentAtURL:program:bankMSB:bankLSB:error:`, present in the macOS SDK header since macOS 10.10 **[V]**, and the repository already loads a sound bank for MIDI playback (`NativeMIDIPlayback.swift`) **[V]**. `.sf3` stores samples as Ogg Vorbis **[I]**, so list only. `.sfz` is text mapping regions to sample paths in sibling files, so list regions and flag the references as unchecked. I did not open the SoundFont 2.04 specification.

**Risks and unknowns.** Sampler memory for large banks inside an extension is unmeasured; cap audition to banks under a size limit. The sampler may load the whole file.

### 11. Unity packages (Add), then game-engine text scenes (Niche)

**What the preview shows.** A `.unitypackage` is a gzipped tar of GUID-named folders, each holding `asset`, `asset.meta` and `pathname` **[V]** ([DEV article](https://dev.to/guardingpearsoftware/how-i-speed-up-my-asset-store-publishing-process-47fd), [Unity forum](https://discussions.unity.com/t/extract-files-assets-from-a-unitypackage-file/746386)). The existing archive view shows opaque GUIDs. Reading the tiny `pathname` entries gives the real project tree with sizes, grouped by Scripts, Plugins, Textures. Findings: Editor scripts (they run on import, **[I]**), native plug-ins (`.dll`, `.dylib`, `.bundle`), and an unusual number of scripts.

**Demand evidence.** Developers get packages from the Asset Store and from repositories and cannot see their contents without importing them, which runs Editor code **[I]**. No Quick Look found. A `preview.png` per GUID may exist **[I]**, not verified.

**Implementation route.** The app already streams gzip and tar; add a package view that reads `pathname` and the sizes of `asset` entries. Effort S. Unity YAML scenes and prefabs (a GameObject outline) and Godot `.tscn`/`.tres` (INI-like node trees) are text and need only outline views, but their references (script GUIDs, `res://` paths) point at sibling files, so they stay "Niche".

**Safety.** No extraction, bounded tar entries, no recursion into nested archives (existing rules).

### 12. Photographer presets and sidecars (Niche)

A Lightroom or Camera Raw `.xmp` preset (XML, `crs:` settings), a legacy `.lrtemplate` (a Lua table, data only), RawTherapee `.pp3` and DxO `.dop` hold develop settings. A preview could show a grouped table (exposure, contrast, white balance, tone curve drawn, HSL, colour grading, crop, lens), the preset name and group, and for sidecars the rating, label and keywords. Nothing found in Quick Look **[S]** (search: "Quick Look Lightroom preset .xmp .lrtemplate"). `.xmp` is XML, so macOS shows text **[I]**. Without a rendered result the value is lower than a LUT's; a rendered look is a large task. The Adobe `crs` schema is not published in one citable place **[I]**. Defer; do it after LUTs if a photographer audience matters.

### 13. Reaper projects (Niche)

`.rpp` is a plain-text, line-based project **[I]**. A preview could list tempo, sample rate, tracks, FX chains by plug-in name, and media sources (marked "not checked"). Ableton is covered by ALS Preview; Reaper was not found in any Quick Look **[S]** (one search, not exhaustive). Logic, FL Studio, Cubase, Bitwig and Pro Tools files are proprietary or obfuscated **[I]**; Audacity `.aup3` is SQLite, so a track list is feasible but sample data is in blocks **[I]**.

### 14 to 19. Short notes

- **FBX (Niche, after GLB).** [ufbx](https://github.com/ufbx/ufbx) is a single-source C loader for binary and ASCII FBX 3000+ and OBJ, MIT or Unlicense, with fuzzing and sanitising on by default **[V]**. A configurable memory limit was not documented on the page. iPreview and Eyemesh already cover FBX **[VC]**.
- **MagicaVoxel `.vox` (Niche).** RIFF-like chunks: `VOX ` version 150, `MAIN`, `SIZE`, `XYZI`, a 256-colour `RGBA` palette **[V]** ([spec](https://github.com/ephtracy/voxel-model); repository labelled MIT, the spec file carries no separate notice). Scene-graph chunks (`nTRN`, `nGRP`, `nSHP`, `MATL`) are not on that page. Needs per-vertex colours in the mesh contract. No Quick Look found **[S]**.
- **PSB and PSD layer facts (Niche).** PSB: header version 2, up to 300,000 pixels per side, composite stored in the final Image Data section, compression 0 raw, 1 RLE, 2 and 3 ZIP **[V]** ([Adobe spec](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)). The composite is absent when "maximize compatibility" is off, so some files cannot show a picture. Row-sampled RLE decoding would keep a multi-gigabyte file bounded **[I]**. There is a live need (Adobe community threads report missing PSB thumbnails and a 4.5 GB Finder limit **[V]**, [thread](https://community.adobe.com/t5/photoshop-ecosystem-discussions/no-thumbnail-previews-for-psb-in-mac-finder/m-p/15253975)) and a specialist already on the store; the landscape document lists it at $34.99 **[VC]**. For PSD, ImageIO already shows the composite **[V]**; a layer, blend-mode and fonts list would be the gain.
- **Blender `.blend` (Niche).** Blender ships its own thumbnail extension on macOS, which can be disabled in System Settings **[S]** ([manual](https://docs.blender.org/manual/en/dev/files/blend/previews.html)). Classic header: 12 bytes, `BLENDER`, pointer size, endianness, three-digit version **[S]**; Blender 5.0 changed the header and I found no specification **[S]** ([forum](https://blenderartists.org/t/shell-script-to-identify-blend-file-version/1625311)); files may be zstd-compressed **[S]** ([announcement](https://archive.blender.org/lists/bf-committers/2021-August/051124.html)). A header plus embedded-preview view is feasible but tied to an undocumented, moving format.
- **ICC profiles (Niche).** `.icc` and `.icm` map to `com.apple.colorsync-profile`, and `qlmanage -m` lists no generator for it **[V]**; I could not determine what Finder shows. A view of description, colour space, device class, intents, gamut triangle and tone curves would help photographers and print buyers. Specialists: Little CMS [Insighter](https://littlecms.com/insighter/) (standalone) **[S]**.
- **Texture facts (rule out as registered types).** ImageIO decodes DDS, KTX, KTX2, PVR, ASTC, TGA, Radiance and EXR on macOS 27.2 **[V]**, so these are "previewed by macOS" under constraint 4. The gain would be facts (mip count, block-compression format such as BC7 or ASTC 6x6, cube-map faces, EXR channels and layers); that is real but small, and claiming an existing system type invites routing conflicts. QLdds (GPL v2, DirectX 8/9 only) shows the older gap **[S]** ([repository](https://github.com/Marginal/QLdds)).

## Ruled out and why

| Item | Reason |
|---|---|
| Icon Composer `.icon` | Apple ships `com.apple.IconComposerQuickLookPreviewAppExtension` (shown as not elected on this Mac, probably because the app is not installed) **[V]**. The vendor's own extension exists; constraint 4. |
| USD, USDA, USDC, USDZ, Alembic, MaterialX, `.reality` | Apple's Hydra and RAQL extensions claim them **[V]**. |
| Ableton `.als` | ALS Preview covers arrangement, tempo, plugins, samples and Spotlight, macOS 15+ **[VC]**. A SpacePane view would be shallower. |
| Chiptune: NSF, SPC, VGM, SID | The decoders I know of are LGPL or GPL **[I]**. Constraint 3. |
| Rive `.riv` | The runtime is [MIT](https://github.com/rive-app/rive-runtime) with a Metal renderer **[V]**, but it is a large C++ GPU renderer and I found no published `.riv` specification **[V]** (the repository page does not link one). Effort L for a niche. Revisit if Rive grows. |
| Spine, DragonBones | Runtimes are licence-gated by the editor licence **[I]**, not verified. |
| After Effects `.aep`, AAF, Pro Tools `.ptx`, Cubase `.cpr`, FL Studio `.flp`, Bitwig, DaVinci `.drp`/`.drt` | Proprietary or undocumented; I did not verify any format. Not worth the reverse-engineering risk. |
| Tiled `.tmx`/`.tsx`/`.tmj`, bitmap fonts `.fnt`, TexturePacker atlases | A render needs sibling tileset or atlas images (constraint 1). The text is already shown as XML or JSON. |
| Lightroom catalogue `.lrcat` | SQLite, but it holds a whole library's paths and edit history; the privacy cost outweighs the value **[I]**. |
| EPS, Illustrator `.ai` | EPS stays deferred; `.ai` has Apple's `Illustrator.qlgenerator` in `qlmanage -m` **[V]**. |
| Texture formats as registered types | See note above. |
| Affinity, Clip Studio, Pixelmator as phase one | Container structure unverified; Affinity restored its own extension in 2.5.6 **[S]**. Add after inspecting real files. |

## Cross-cutting design notes

- **References are listed, not checked.** For project files (EDL, OTIO, FCPXML, Reaper, Lottie, `.sfz`, `.gltf`) show every referenced file path or URL as stored, with one fixed sentence: "This preview cannot check whether these files exist."
- **A leak lens for creative files.** Count absolute paths, home-folder user names and, where present, organisation or client folder names in the metadata. This reuses the typed-findings pattern (kind, count, lines) from [decision 012](../../decisions/012-safety-findings.md) and never prints the values it flags, apart from the lists above, which are the file's own content.
- **Content sniffing inside shared suffixes.** `.json` (Lottie, DTCG tokens), `.ase` (Adobe Swatch Exchange, Aseprite), `.cube` (LUT, chemistry volume data), `.stl` (the existing geometry type and EBU subtitle files, **[I]**). The catalog needs a way for a specific format to claim a file after classification; the `package.json` type is the closest precedent I know of, and I did not check how it matches. This is probably a small shared-contract change, listed so the lead can budget it.
- **Thumbnails.** Synthetic thumbnails (LUT ramp, swatch strip) are safe by construction. Embedded-picture thumbnails need an owner decision. The vendors do show the picture, so users may expect it.

## Sources

Local checks (macOS 27.2): `UTType` probe, `CGImageSourceCopyTypeIdentifiers`, `MDLAsset.canImportFileExtension`, `pluginkit` manifests of `SceneKitQLPreviewExtension`, `HydraQLPreviewExtension`, `RAQLPreviewExtension`, `QLPreviewGenerationExtension`, `IconComposerQuickLookPreviewAppExtension`, `qlmanage -m`, and the SDK header `AVAudioUnitSampler.h`; this repository's `FormatCatalog.json`, `docs/decisions/022`, `024`, `NativeMIDIPlayback.swift`.

Opened pages:
- [Competitor landscape](../2026-10-05-competitor-landscape.md)
- [Mottie: Lottie Player](https://apps.apple.com/app/id6743446238)
- [Als Preview](https://als-preview.de)
- [PSB Quick Look HD](https://psb-quick-look-plugin.com)
- [Adobe community: PSB thumbnails thread](https://community.adobe.com/t5/photoshop-ecosystem-discussions/no-thumbnail-previews-for-psb-in-mac-finder/m-p/15253975)
- [Krita 5.3 thread](https://krita-artists.org/t/no-preview-for-kra-thumbnail-after-5-3-update-on-mac/177587)
- [Aseprite thumbnails thread](https://community.aseprite.org/t/mac-file-thumbnails-not-showing/25109)
- [Aseprite file-format spec](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md)
- [Sketch file format](https://developer.sketch.com/file-format/)
- [DTCG format module](https://www.designtokens.org/tr/2025.10/format/)
- [ASE and palette formats (selapa.net)](http://www.selapa.net/swatches/colors/fileformats.php)
- [ColorPaletteCodable](https://github.com/dagronf/ColorPaletteCodable)
- [Unfold](https://unfold.tools)
- [OpenTimelineIO](https://github.com/AcademySoftwareFoundation/OpenTimelineIO)
- [cgltf LICENSE](https://raw.githubusercontent.com/jkuhlmann/cgltf/master/LICENSE)
- [lottie-ios LICENSE](https://raw.githubusercontent.com/airbnb/lottie-ios/master/LICENSE)
- [ufbx](https://github.com/ufbx/ufbx)
- [libopenmpt / OpenMPT](https://github.com/OpenMPT/openmpt)
- [MetalSplatter](https://github.com/scier/MetalSplatter)
- [spz](https://github.com/nianticlabs/spz)
- [rive-runtime](https://github.com/rive-app/rive-runtime)
- [MagicaVoxel format repository](https://github.com/ephtracy/voxel-model) and [format text](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt)
- [Photoshop file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [GIMP XCF specification](https://developer.gimp.org/core/standards/xcf/)
- [Apple developer forums: Gaussian splats thread](https://developer.apple.com/forums/thread/843416)

Search results used as snippets only (not opened):
- [Simple Color Palette](https://sindresorhus.com/simple-color-palette)
- [Color Palette Finder](https://apps.apple.com/app/id1488149884)
- [Art View article](https://creativepro.com/take-a-deeper-look-your-documents-with-art-view/)
- [Lutme](https://editingtools.io/software/lutme)
- [LUT Tuner](https://www.newsshooter.com/2026/08/01/cut-point-labs-lut-tuner-for-mac/)
- [FFmpeg ticket on the Cube spec](https://ffmpeg.org/pipermail/ffmpeg-trac/2023-June/066367.html)
- [Blackmagic LUT notes](https://forum.blackmagicdesign.com/viewtopic.php?p=232952)
- [Krita Quick Look integration README](https://lxr.kde.org/source/graphics/krita/krita/integration/README.md)
- [Silicate (Procreate viewer)](https://github.com/Avarel/silicate)
- [Grida .fig notes](https://grida.co/docs/wg/feat-fig/)
- [Affinity previews report](https://www.sir-apfelot.de/affinity-update-endlich-wieder-thumbnail-und-quick-look-vorschau-63507/)
- [Adobe XD status](https://mapsoft.com/adobe-xd-end-of-life/) and [Eagle note](https://docs-en.eagle.cool/article/224-unable-to-add-adobe-xd-files)
- [dotLottie format](https://docs.lottiefiles.com/en/format/dotlottie.md)
- [Eyemesh](https://www.producthunt.com/p/eyemesh)
- [GLTFQuickLook thread](https://community.khronos.org/t/quicklook-gltf-plugin-for-macos/104566)
- [Spatial Fields](https://apps.apple.com/app/id6745549629)
- [SuperSplat import and export](https://developer.playcanvas.com/user-manual/supersplat/editor/import-export/)
- [Unity package structure (DEV)](https://dev.to/guardingpearsoftware/how-i-speed-up-my-asset-store-publishing-process-47fd) and [Unity forum](https://discussions.unity.com/t/extract-files-assets-from-a-unitypackage-file/746386)
- [py-premiere](https://pypi.org/project/py-premiere/) and [Gillware](https://www.gillware.com/video-recovery/premiere-pro-project-recovery/)
- [fcp.cafe FCPXML](https://fcp.cafe/developers/fcpxml/) and [EDL-X](https://apps.apple.com/app/edl-x/id539666579)
- [Polyphone soundfont explorer](https://www.polyphone.io/en/documentation/manual/soundfont-explorer)
- [Xojo tracker thread](https://forum.xojo.com/t/mac-os-x-playing-tracker-modules-mod-xm-it-s3m/20137)
- [Blender previews manual](https://docs.blender.org/manual/en/dev/files/blend/previews.html), [Blender zstd announcement](https://archive.blender.org/lists/bf-committers/2021-August/051124.html) and [Blender file-version forum post](https://blenderartists.org/t/shell-script-to-identify-blend-file-version/1625311)
- [Little CMS Insighter](https://littlecms.com/insighter/)
- [QLdds](https://github.com/Marginal/QLdds)
