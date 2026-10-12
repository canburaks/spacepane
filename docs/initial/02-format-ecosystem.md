# Task 2 — Quick Look format ecosystem and feasible additions

Research date: 2026-10-03 (Europe/Istanbul). Scope: the complete supplied catalog, plus the implementation and dependency consequences of its strongest candidates. This is research, not a compatibility test or approval to copy code.

## Recommendation

Build one modern, bounded preview pipeline and add reusable format adapters. Begin with the requested text/data/code/archive/MIDI baseline and customization. The most economical additions are notebook documents, unified diffs, XML/property lists/localization files, subtitle lists, OPML outlines, and code snippets. Use later waves for certificates/profiles, app archives, ebook/container cover summaries, offline geospatial plots, swatches, and more archive formats. Scientific arrays, unfamiliar media codecs, full 3D/CAD rendering, binary decompilers and proprietary document formats need independent business and technical gates.

The supplied projects are evidence that a preview is possible, not a set of packages to link. Many are complete applications, vendor products, or obsolete generators. Apple’s macOS 15 release notes explicitly direct developers away from deprecated Quick Look generators toward Preview and Thumbnail Extension APIs. No new `.qlgenerator` should be shipped. [Apple release notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes).

## Evidence method and limits

The inventory contains **116 supplied rows: 96 plugins and 20 packages**. Different owners of QLMarkdown and different video projects remain separate rows; the struck-out QuickPub row is retained. GitHub-backed entries were researched using bounded README retrieval, targeted repository listings/manifests, and license files for selected candidates. Vendor pages were read where available. A classifier was used only to shortlist architecture evidence; decisions were checked against primary text and selected manifests. No downloaded plugin was installed or executed, and no Finder routing was measured.

Evidence codes:

- **R**: primary GitHub README or targeted repository/source evidence inspected. This does not imply the source, every dependency, maintenance status or compatibility was fully audited.
- **V**: primary vendor/author/project page inspected. Vendor feature descriptions remain claims, not measured performance.
- **U**: source attempted but substantive evidence unavailable, or the named feature could not be found. Format claims are retained from the user list and qualified in the row.
- **T**: user table only; no source URL supplied.

Architecture codes: **M** modern app-extension evidence; **L** legacy generator evidence; **Media** modern Media Extensions rather than a Quick Look preview target; **Theme** assets only; **?** architecture not established. Mixed manifests can contain legacy keys alongside a valid extension point. “M” does not establish App Store suitability.

Priority codes are recommendations: **Core** requested baseline; **W1** first inexpensive additions after pipeline reliability; **W2** next product wave; **W3** specialized wave; **Gate** empirical feasibility required; **Native** test Apple’s current preview first; **Defer** no initial investment; **Exclude** reject the inspected implementation path. The final PLAN controls actual release scope.

Evidence coverage: **94 R + 8 V = 102 rows with inspected substantive primary evidence; 13 U; 1 T**. Architecture and licensing uncertainty remains explicit per row.

## Current corrections that affect the plan

- **ProvisionQL has modernized.** Its current repository includes preview/thumbnail targets and a tested shared core package, and its README covers app archives and provisioning profiles under MIT. Older statements in another fork that it lacks macOS 15 support are historical, not current evidence. [Current ProvisionQL](https://github.com/ealeksandrov/ProvisionQL).
- **Marginal/QLVideo has changed architecture.** It redirects to QuickLookVideo, whose current README describes Media Extensions plus Spotlight and GPL-2.0-or-later. Its media list contains `.wmv`; the supplied `.wmf` entry is not verified. Media demuxing/decoding is a separate product decision from text preview. [Current QuickLookVideo](https://github.com/Marginal/QuickLookVideo).
- **Syntax Highlight’s current minimum is macOS 12+**, not the supplied older 10.15+ description. It and sbarex/QLMarkdown are GPL-3.0 projects. Their settings are useful design references, while independent libraries are the preferred implementation route. [Syntax Highlight](https://github.com/sbarex/SourceCodeSyntaxHighlight), [QLMarkdown](https://github.com/sbarex/QLMarkdown).
- **markdown-quicklook’s MIT is not a blanket license for upstream PreviewMarkdown.** The wrapper explicitly separates its toggle/scripts/patch layer license from the upstream renderer. Local-build/quarantine-removal instructions are not distribution guidance for this app. [Wrapper license explanation](https://github.com/ruspg/markdown-quicklook#license).
- **AssetCatalogTinkerer has private CoreUI declarations.** A permissive top-level license cannot make private framework usage acceptable. Exclude that implementation from the App Store path; `.car` remains deferred until a supported independent reader exists. [Inspected private header](https://github.com/insidegui/AssetCatalogTinkerer/blob/main/ACS/Private%20Headers/CoreUI.h).

## Recommended adapter waves

| Wave | Additional formats/experience | Proposed implementation | Completion gate |
|---|---|---|---|
| W1 | `.diff`, `.patch` | Original bounded unified-diff scanner; colored additions/deletions, hunk and file navigation, source fallback. Reuse code text view and token theme. | Combined/binary/malformed diff stays readable; no patch application; depth/line/output limits. |
| W1 | `.xml`, `.xsd`, `.xsl`, `.rss`, `.plist`, `.strings`, `.stringsdict`, `.opml` | Public Foundation property-list/XML APIs plus a bounded outline model and highlighted source; binary plist gets a readable tree. | Disable external entity/resource resolution; never execute XSLT or fetch feed URLs; handle encodings and duplicate-key ambiguity visibly. |
| W1 | `.ipynb` | Parse notebook JSON; show cells, language, Markdown, code, and a capped subset of text/raster outputs using shared renderers. | No kernel, Python, nbconvert, code execution, widget JS, iframe, script or external URL load. Cap base64 decoding and raster pixels. |
| W1 | `.srt`, `.vtt` | Original timeline/table parser; cue count, duration, search and selectable text. | Malformed timings/markup fall back; no external subtitles/media fetched; bounded cues and text. VTT is a proposed extension of the SRT idea. |
| W1 | `.codesnippet`, `.sublime-snippet`, `.tmSnippet` | Plist/XML metadata plus code content through existing adapters. | Never evaluate snippet expressions or insert code into another app. |
| W1 | `.nfo`, `.diz`, `.asc` | Explicit CP437 option and monospaced text-art view; Unicode fallback. | Do not dispatch arbitrary `.bin` as ANSI; cap dimensions and line length; separate ANSI state-machine support. |
| W1 | `.csv`, `.tsv` | Bounded quoted-record parser and native table in companion app; register QL types only after provider test. | Standard CSV may route to Apple. Do not promise winning provider priority. CSV formulas remain text and are never evaluated. |
| W2 | `.pem`, `.der`, `.cer`, `.crt`, `.mobileprovision`, `.provisionprofile` | Public Security certificate/CMS APIs plus original metadata view; property-list adapter for decoded profiles. | No Keychain import or trust-setting changes; distinguish parsing/signature/trust; redact private-key blocks and device identifiers. Verify APIs and sandbox path in prototype. |
| W2 | `.ipa`, `.tipa`, `.apk`, `.apkm`, `.jar`, `.xcarchive`, `.appex` | Archive/package adapter plus public plist/manifest metadata; APK binary XML/resource decoding is explicit separate work. | No launches/builds/installing, signature-validity claims without verification, or private CoreUI icon extraction. Descendant access is sandbox-tested. |
| W2 | `.epub`, `.kra`, `.ora` | Select allowlisted embedded metadata/cover/merged-image entries through existing ZIP reader; bounded XML parsing and ImageIO decoding. | ZIP-bomb and path limits; no complete extraction; no DRM removal; no HTML script or external resource execution. Unavailable Krita repo does not verify container versions. |
| W2 | `.gpx`, `.geojson`, `.topojson` | Local geometry summary plus simple projected path plot, using Foundation/Core Graphics; TopoJSON arc reconstruction separate. | No remote base maps; cap points, rings, properties and transform math; precise-location redaction available. |
| W2 | `.ase`, `.torrent`, ANSI art | Original bounded swatch and bencode parsers; optional audited libansilove backend. | Color profiles/versions, raw-byte bencode hashes, font asset licenses and terminal-control safety are tested. No torrent traffic. |
| W2 | RAR/7z/BZip2/XZ/CPIO and other archive listings | A narrowly configured libarchive candidate after baseline reader decision; ZIPFoundation remains a focused ZIP candidate. | Advertise actual supported variants, not every BetterZip type. No external helper programs, password guessing, extraction, or unbounded scan. |
| W3 | FITS, HDF5/dotTHz, NetCDF, MATLAB subsets | Audited bundled C library adapters behind small Swift interfaces; metadata first, optional sampled array images. | Pin versions; no external filters/plugins, arbitrary links or full-array allocation; endian/cube/chunk fixtures; large C footprint justified by demand. |
| W3 | WOFF/WOFF2, DDS/PFM/IFF, glTF/mesh/VOX, Procreate/Adobe brush/pattern | Test public CoreText/ImageIO/ModelIO first; otherwise independent audited decoders for specific documented variants. | No blanket format claim; resource references denied or explicitly bounded; pixel/vertex/glyph/texture limits; use supported graphics APIs. |
| W3 | Non-native MKV/WebM/AVI codecs, waveforms | AVFoundation capability testing first. Consider separate Media Extensions or audited decoders only with a clear support matrix. | Demuxer versus codec compatibility, license build flags, patent questions, energy/cancel behavior and App Store extension packaging all verified. |

These are feasibility proposals, not verified runtime implementations. `.stringsdict`, `.vtt`, `.tsv`, certificate aliases and `.topojson` are deliberate adjacent additions, not claims that every supplied plugin implements them.

## Shared rules that prevent format expansion becoming unsafe

1. **Content signatures refine an already-routed request.** UTType declarations and Finder provider selection occur before the app can inspect bytes. A content sniffer cannot guarantee that unknown filenames or extensionless files reach this extension. Companion Open/Drop can offer a broader fallback.
2. **Resolve suffix collisions deliberately.** Garmin FIT versus astronomical `.fit`, X-Plane versus Wavefront `.obj`, FEI microscopy versus astronomical `.ser`, and ASCII `.nfo` versus XML/system reports need small signature/schema checks. Arbitrary `.bin`, `.pdb` and `.dat` must not be captured as one assumed format.
3. **Native redundancy is measured on supported OS versions.** Images, BMP/WebP/GIF, audio/video, fonts, USD models, clippings and CSV may already have useful Apple previews. Use runtime format enumeration and actual Finder fixtures rather than converting an old plugin list into a list of present-day gaps. ImageIO decode capability alone does not prove Finder routing or equivalent UX.
4. **Safe resource resolution is adapter-owned.** Every nested item read must have a byte/time/depth/pixel/node quota. ZIP paths and symbolic links cannot grant access outside the selected item. Markdown, ebooks, charts and notebooks cannot resolve URLs or sibling files simply because content asks for them.
5. **Do not execute the document’s tools.** No Asciidoctor shell override, nbconvert, Python/Jupyter kernel, Rscript, MATLAB process, Java decompiler subprocess, XSLT transformation, installer script, project build or embedded JavaScript. Code/source fallback is a product feature.
6. **View-only does not imply zero parsing risk.** Decompression/codec/font/C libraries parse untrusted bytes. Keep only justified readers enabled, disable external helper fallbacks, cap allocations and cancellation points, fuzz parser boundaries, and test corrupt fixtures.
7. **Privacy follows derived representations.** Redaction must cover previews, copy, notebook outputs, thumbnails, accessibility text, logs and caches. Certificates/private-key blocks, profiles with device IDs, precise GPS data and environment values deserve explicit handling. A secret-key heuristic is not complete protection.
8. **Missing bytes cannot yield file-content previews.** Absent/deleted/unavailable files may get an informative state if a request reaches the app; cloud placeholders require availability checks and policy, not fabricated content or automatic downloads. Format coverage does not remove this constraint.

## Dependency and license disposition

No third-party source is accepted for shipping in this research phase. Pin an exact revision/version before integration; inspect top-level and per-file licenses, transitive parser libraries, bundled grammars/fonts/themes/artwork and generated assets; record required notices. “No dependencies” in a project README is a project claim, not a completed dependency audit.

| Candidate | Verified evidence | Disposition |
|---|---|---|
| Foundation, Security, ImageIO, CoreText, AVFoundation, Core Graphics, ModelIO | Public platform frameworks; final API feasibility belongs to Task 1 and prototype. | Prefer for metadata/decoding that actually supports the format; do not infer support from suffix. |
| swift-markdown / cmark-gfm | relikd Markdown explicitly uses compiled swift-markdown, Apache-2.0, plus MIT CSS. | Good independently audited Markdown-parser candidate. Native attributed rendering remains a separate implementation. [Project](https://github.com/swiftlang/swift-markdown). |
| ZIPFoundation | MIT license file inspected. | Focused ZIP candidate; verify ZIP64, malformed directories, random access, memory and cancellation. [License](https://github.com/weichsel/ZIPFoundation/blob/development/LICENSE). |
| libarchive | COPYING inspected: mostly BSD-2-Clause, selected source BSD-3-Clause/public-domain/triple-license alternatives; build-script licenses vary. | Narrow build + transitive compression-library audit; library license must not be reduced to a single blanket label. [COPYING](https://github.com/libarchive/libarchive/blob/master/COPYING). |
| libansilove | BSD-2-Clause license inspected. QLAnsilove wrapper carries a different BSD-3-Clause notice. | Optional ANSI backend after font/raster/dependency review; plain CP437 view can precede it. [Library license](https://github.com/ansilove/libansilove/blob/master/LICENSE), [wrapper](https://github.com/ansilove/QLAnsilove/blob/master/LICENSE). |
| HDF5 | Official distribution license has multiple notices; wrapper projects are GPL-3.0. | Independent HDF5 library investigation for W3; never assume wrapper license equals backend license. [HDF5 license](https://github.com/HDFGroup/hdf5/blob/develop/LICENSE). |
| FreeType / WOFF2 | qlwoff requires FreeType; qlwoff own BSD-style license inspected. FreeType dual-license selection and optional Brotli/WOFF2 path not fully audited here. | Hold until chosen build and FTL/license requirements verified. Do not require Homebrew installed on users’ Macs. [qlwoff](https://github.com/Nyx0uf/qlwoff). |
| FFmpeg / VLCKit and Media Extensions | Oil3 README identifies LGPL paths. FFmpeg official guidance says GPL components/build flags change obligations. | Defer broad codec stack; exact artifacts/options/transitive licenses, patents and distribution terms need specialist review. [FFmpeg legal](https://ffmpeg.org/legal.html). |
| ProvisionQL, relikd QLJSON/QLMarkdown/QLAppBundle, GLTFQuickLook, ipynb-quicklook | MIT licenses inspected for these projects. | Potential source references after attribution/transitive audit; modernity/permissive license still does not validate private APIs, entitlements or unbounded processing. |
| QLPrettyPatch | BSD-2-Clause license inspected; README names PrettyPatch formatter. | Prefer original small diff parser. Audit formatter separately if any source is copied. [License](https://github.com/atnan/QLPrettyPatch/blob/master/LICENSE). |
| SourceCodeSyntaxHighlight, sbarex QLMarkdown, HDF5QL, DotTHzQL, QLMobi, QLVideo, QLdds, QLWindowsApps, lookdown, ReceiptQuickLook | GPL license text or explicit primary README licensing inspected as labeled per row. | Inspiration only for current plan. Copyleft is not an automatic ban, but no reuse without a deliberate distribution/license decision; never silently mix into a proprietary App Store build. |
| Closed/vendor products; freeware; missing/unspecified licenses | Vendor features or user list only; no granted source redistribution rights verified. | Reimplement from documented specifications or defer. Free download/free use does not grant copying rights. |

## Full supplied inventory

Row notes combine inspected facts (when evidence is R/V) with explicitly recommended dispositions. For U/T rows, format names come from the user’s catalog, not independent verification. License “unverified” means no reuse permission was established, not that the project necessarily lacks a license.

### Plugins — 96 rows

| # | Supplied project / primary source | Formats or feature | Evidence / architecture | Priority | Findings and disposition |
|---|---|---|---|---|---|
| 1 | [AsciiDocQuickLook](https://github.com/clydeclements/AsciiDocQuickLook) | AsciiDoc | R/L | W3 | MIT stated; archived in 2026; invokes installed Asciidoctor. Bundle a safe parser or source fallback; no user shell converter. |
| 2 | [BetterZ QuickLook Plugin Theme for Lion](https://github.com/farfanoide/BetterZ-QuickLook-plugin-theme-for-Lion) | Theme only | R/Theme | Defer | Theme assets only, no added format. Historical appearance example; reuse license unverified. |
| 3 | [BodymovinQL](https://github.com/fabionuno/BodymovinQL) | Bodymovin/Lottie JSON | R/L | W3 | Specialized JSON animation; requires renderer and bounded animation work. Disable expressions, external assets and autoplay. License unverified. |
| 4 | [HDF5QL](https://github.com/hacknus/HDF5QL) | hdf5, h5 | R/M | W3 | GPL-3.0 wrapper; README requires installed hdf5. Separate permissively licensed HDF5 library is a possible future backend. |
| 5 | [DotTHzQL](https://github.com/hacknus/DotTHzQL) | thz, thzimg, thzswp | R/M | W3 | GPL-3.0 wrapper; requires hdf5. Specialized HDF5 schema/image interpretation needs fixtures. |
| 6 | [ProvisionQL](https://github.com/ealeksandrov/ProvisionQL) | ipa, tipa, xcarchive, appex, mobileprovision, provisionprofile | R/M | W2 | Current modern app/core package, MIT. Supports profiles and app archives; historical incompatibility claims elsewhere are obsolete. |
| 7 | [QLColorCode](https://github.com/anthonygelibert/QLColorCode) | Source code | R/L | Core | Legacy highlight-based code preview with shell-tool paths; license/dependency audit needed. Implement the shared highlighter. |
| 8 | [QLColorCode-extra](https://github.com/BrianGilbert/QLColorCode-extra) | Source code additions | R/L | Core | Legacy extension to QLColorCode; no new renderer needed. License unverified. |
| 9 | [qlImageSize](https://github.com/Nyx0uf/qlImageSize) | bmp, bpg, exr, icns, ico, jpg, pbm, pgm, png, ppm, psd, sgi, svg, tga, tiff, gif, webp, jp2 | R/L | Native | BSD badge only; adds dimensions plus decoders. Use ImageIO metadata first; BPG remains a separate decoder/licensing gate. |
| 10 | [qlmarkdown](https://github.com/toland/qlmarkdown) | md, markdown | R/L | Core | Legacy Markdown generator; baseline adapter supersedes it. Reuse license unverified. |
| 11 | [markdown-quicklook](https://github.com/ruspg/markdown-quicklook) | md, markdown | R/M | Core | MIT wrapper/toggle/scripts only; upstream PreviewMarkdown license is separate. TextKit typography is useful inspiration. |
| 12 | [MultiMarkdown QuickLook](https://github.com/fletcher/MMD-QuickLook) | Markdown, OPML | R/? | W2 | Adds OPML/MultiMarkdown inspiration; full dialect compatibility is separate. README advertises another closed-source build; license unverified. |
| 13 | [Mkv Quicklook](https://github.com/Oil3/Mkv-Quicklook) | mkv | R/? | W3 | README describes FFmpeg and VideoLan LGPL-2.1 libraries. Modern packaging not verified here; decoder/build/license audit required. |
| 14 | [QLMobi](https://github.com/bfabiszewski/QLMobi) | prc, mobi, azw, azw3, azw4, some pdb | R/L | Defer | GPL-3.0-or-later stated. Legacy Kindle container/DRM variants; no bundled reuse planned. |
| 15 | [qlstephen](https://github.com/whomwah/qlstephen) | Extensionless text | R/L | Core | Bounded extensionless text inspiration. Unknown UTType routing cannot be guaranteed; binary sniffing and encoding are required. |
| 16 | [QuickLookASE](https://github.com/rsodre/QuickLookASE) | ase | R/L | W2 | Swatch inspector candidate; no license metadata found. Independent ASE parser and color-space handling preferred. |
| 17 | [QuickLookPrettyJSON](https://github.com/tomnewton/QuickLookPrettyJSON) | json | R/L | Core | Legacy pretty JSON example; no extra baseline coverage. License unverified. |
| 18 | [QLVideo](https://github.com/Marginal/QLVideo) | asf, avi, flv, mkv, rm, webm, wmf | R/Media | W3 | Now redirects to Marginal/QuickLookVideo: Media Extensions plus Spotlight, GPL-2.0-or-later. Current list uses wmv, not supplied wmf. |
| 19 | [QLAddict](https://github.com/tattali/QLAddict) | srt | R/L | W1 | SRT timeline/table idea; implement with shared text renderer. License unverified. |
| 20 | [QLCommonMark](https://github.com/digitalmoksha/QLCommonMark) | Markdown | R/L | Core | Legacy CommonMark generator; evaluate parser library separately. License unverified. |
| 21 | [inloop-qlplayground](https://github.com/inloop/qlplayground) | playground | R/L | W2 | MIT stated. Show package source/resources without running Swift or fetching playground dependencies. |
| 22 | [qlplayground](https://github.com/norio-nomura/qlplayground) | playground, swift | R/L | Core | MIT stated. Swift code fits baseline; playground packages need bounded traversal. |
| 23 | [MeshQuickLookPlugin](https://github.com/alecjacobson/MeshQuickLookPlugin) | mesh, obj, off, ply, stl, wrl | R/L | W3 | Independent mesh formats; inspect public ModelIO support first, then custom readers. OpenGL-era implementation is not the target architecture; license unverified. |
| 24 | [QLPrettyPatch](https://github.com/atnan/QLPrettyPatch) | patch | R/L | W1 | BSD-2-Clause top-level license inspected; PrettyPatch formatter is a transitive audit item. Implement bounded unified-diff UI natively. |
| 25 | [QLFits](https://github.com/onekiloparsec/QLFits) | fits | R/L | W3 | GPL stated; ObjCFITSIO/AstroCocoaKit dependencies. FITS cube/header/image handling is a specialized backend. |
| 26 | [QLfit](https://github.com/dbr/QLfit) | Garmin fit | R/L | W3 | Garmin FIT activity format, not astronomical FITS. License unverified; bounded FIT parser/SDK terms gate. |
| 27 | [QLAnsilove](https://github.com/ansilove/QLAnsilove) | ans, cia, ice, bin, adf, idf, xb, pcb, tnd, asc, nfo, diz, mem | R/L | W2 | Archived legacy wrapper; BSD-3-Clause file inspected. libansilove BSD-2-Clause is a candidate; font/palette assets need separate audit. |
| 28 | [qlvega](https://github.com/invokesus/qlvega) | Vega/Vega-Lite | R/L | W3 | Chart-spec renderer can resolve external data and expressions; default JSON view first. License unverified. |
| 29 | [Krita-QuickLook](https://github.com/Algorithmus/Krita-QuickLook) | kra, ora | U/? | W2 | Supplied repo 404. KRA/ORA embedded preview images are a feasible independent archive-adapter addition after fixture/spec validation. Evidence limit: supplied GitHub repository returned 404. |
| 30 | [pud-quicklook](https://github.com/war2/pud-quicklook) | pud | R/? | Defer | MIT stated. Warcraft II map-specific renderer; defer until audience demand and format specification exist. |
| 31 | [quicklook-pfm](https://github.com/lnxbil/quicklook-pfm) | ppm, pfm, pgm, pbm | R/? | W3 | Portable bitmap/float formats; ImageIO runtime type test first. Float endian/tone mapping and license unverified. |
| 32 | [QuickLookR](https://github.com/hrbrmstr/QuickLookR) | rdata, rda, rds, Feather | R/L | Defer | Requires installed Rscript and rdatainfo. Do not deserialize arbitrary R content by running R; Feather/Arrow is a separate bounded library path. |
| 33 | [quicklook-gpx](https://github.com/vibrog/quicklook-gpx) | gpx | R/L | W2 | Legacy OpenLayers/map tiles can contact servers. Parse XML locally and draw an offline coordinate plot; no base-map network by default. |
| 34 | [WebPQuickLook](https://github.com/emin/WebPQuickLook) | webp | R/? | Native | Retest modern ImageIO/Finder support before adding a decoder. License unverified. |
| 35 | [WebM QuickLook Preview extension](https://github.com/Oil3/Webm-QuickLook-Plug-In) | webm | R/M | W3 | Extension plist verified despite legacy keys retained. FFmpeg/VLCKit LGPL paths and codec/patent review are separate gates. |
| 36 | [ePub-quicklook](https://github.com/jaketmp/ePub-quicklook) | epub | R/L | W2 | EPUB metadata/cover from ZIP/XML; no script execution or external resources. License unverified. |
| 37 | [QuickPub (struck out in supplied list)](https://github.com/Crazor/QuickPub) | epub cover | R/L | W2 | Retained for coverage; obsolete cover-preview example. Use the same EPUB adapter, not a second implementation; license unverified. |
| 38 | [qltext-jp](https://github.com/mzp/qltext-jp) | Shift JIS, EUC-JP text | R/L | W2 | Encoding support idea; add explicit Shift JIS/EUC-JP decoding with user-visible encoding, not silent probabilistic corruption. License unverified. |
| 39 | [QuickNFO](https://github.com/planbnet/QuickNFO) | nfo | R/L | W1 | CP437 monospace text art is a cheap first step; ANSI control-state rendering is separate. License unverified. |
| 40 | [QuickJSON](https://github.com/johan/QuickJSON) | json | R/L | Core | Legacy JSON pretty-printer; baseline renderer supersedes. License unverified. |
| 41 | [quicklook-csv](https://github.com/p2/quicklook-csv) | csv | R/L | W1 | Apache-2.0 stated; NOTICE required if reused. Companion table view useful; Finder may select Apple provider. |
| 42 | [FictionBook2QL](https://github.com/gonzoua/FictionBook2QL) | fb2 | U/? | W3 | Repository exists but no README found; supplied FB2 claim only. XML ebook content/zip variants need schema and fixtures; license unverified. Evidence limit: repository root accessible; no README found; format claim retained from supplied list. |
| 43 | [ipynb-quicklook](https://github.com/tuxu/ipynb-quicklook) | ipynb | R/L | W1 | MIT license inspected; legacy generator uses nbviewer.js and points to newer viewer app. Build a read-only notebook adapter without a kernel. |
| 44 | [jupyter-notebook-quick-look](https://github.com/jendas1/jupyter-notebook-quick-look) | Notebook; supplied jupyter suffix | R/L | W1 | Legacy generator requires installed Python3/Jupyter; supplied jupyter suffix is not an accepted standard extension. Support ipynb after routing test. |
| 45 | [QLWaveForm](https://github.com/seagirl/QLWaveForm) | wav | R/L | W2 | Compute bounded waveform envelopes with AVFoundation for supported codecs. Standard audio playback may already be native; license unverified. |
| 46 | [QuickLookAPK](https://github.com/hezi/QuickLookAPK) | apk | R/L | W2 | APK metadata/icon/archive idea; Android binary XML is separate from ordinary XML. Never execute APK or run external tools; license unverified. |
| 47 | [GLTFQuickLook](https://github.com/magicien/GLTFQuickLook) | gltf, glb | R/L | W3 | MIT license inspected; legacy preview. glTF external buffers/textures require access policy; public ModelIO/runtime support gate. |
| 48 | [qlZipInfo](https://github.com/srirangav/qlZipInfo) | zip, jar | R/L | Core | Archive size/count/path summary inspiration; ZIP/JAR fit baseline archive reader. License unverified. |
| 49 | [QLZip](https://github.com/richie5um/QLZip) | zip | R/? | Core | ZIP baseline duplicate; no additional format justified. Architecture/license unverified. |
| 50 | [QLNetcdf](https://github.com/tobeycarman/QLNetcdf) | nc | R/L | W3 | Requires external ncdump. Bundle and audit a library only if needed; metadata-first and chunked numeric samples. |
| 51 | [matlab-quicklook](https://github.com/jaketmp/matlab-quicklook) | mat | R/L | Defer | README requires MATLAB libmat plus dependent libraries. Redistribution permission unresolved; matio may support a bounded subset independently. |
| 52 | [MikuMikuDanceQuickLook](https://github.com/magicien/MikuMikuDanceQuickLook) | pmd | R/L | Defer | PMD model-specific pipeline; license unverified. Defer after more general mesh formats. |
| 53 | [qlImagePreviewWithSize](https://github.com/srirangav/qlImagePreviewWithSize) | Images | R/L | Native | Title/dimensions feature inspiration. Host title is system-owned; put metadata inside content. License unverified. |
| 54 | [qlMoviePreview](https://github.com/Nyx0uf/qlMoviePreview) | mkv | R/? | W3 | Simplified BSD stated. Movie thumbnail/metadata inspiration; container and codec capability require separate fixture tests. |
| 55 | [qlwoff](https://github.com/Nyx0uf/qlwoff) | woff | R/? | W3 | BSD-style license inspected, exact SPDX unconfirmed. Requires FreeType; choose and comply with FTL option and audit WOFF2/Brotli dependencies. |
| 56 | [ql-bbc4](https://github.com/simongregory/ql-bbc4) | bbc4 | R/L | Defer | Historical BBC archive semantics; specialized and low priority. License unverified. |
| 57 | [qlboxnote](https://github.com/louije/qlboxnote) | boxnote | R/L | W2 | Box Note JSON-to-document candidate; source schema/version and sanitization need validation. License unverified. |
| 58 | [NDSQuickLook](https://github.com/gonzoua/NDSQuickLook) | Nintendo DS ROM | R/? | Defer | ROM header/icon candidate only; no execution. Nintendo format details and asset/licensing questions unresolved. |
| 59 | [quickgeojson](https://github.com/irees/quickgeojson) | GeoJSON, TopoJSON | R/L | W2 | README also supports TopoJSON. Offline geometry summary/path plot; do not use remote tile defaults. License unverified. |
| 60 | [QuickLookBPG](https://github.com/dethi/QuickLookBPG) | bpg | R/L | Defer | BPG decoder adds HEVC-related licensing and native parsing surface. Not justified for first release; license unverified. |
| 61 | [Provisioning](https://github.com/chockenberry/Provisioning) | mobileprovision | R/L | W2 | Legacy profile inspector; use public Security/CMS and property list path. Reuse license unverified. |
| 62 | [ql-iff](https://github.com/dalton-tulou/ql-iff) | iff | R/L | W3 | IFF container variants and palette/compression handling require specialist fixtures. License unverified. |
| 63 | [qlBitRate](https://github.com/jordansaints/qlBitRate) | mp3 metadata | R/L | Native | GPL-2.0 stated. MP3 metadata already accessible with AVFoundation; content metadata optional, host title cannot be promised. |
| 64 | [QuickLookPUZ](https://github.com/DianeWass/QuickLookPUZ) | puz | R/L | Defer | Crossword-specific parser/grid; independent support possible with fixtures. License unverified. |
| 65 | [colorxml-quicklook](https://github.com/fabiolecca/colorxml-quicklook) | XML, XSL, XSD, RSS, GXL, plist, MXML | R/L | W1 | README says freeware/source on request, not an open-source license. XML/XSL/XSD/RSS/plist text/tree inspiration; do not run document XSLT. |
| 66 | [D64QLPlugin](https://github.com/arcanelab/D64QLPlugin) | d64, d71, d81 | R/? | Defer | Commodore disk images; bounded directory listing possible later. Architecture/license unverified. |
| 67 | [QuicklookDot](https://github.com/besi/quicklook-dot) | dot | R/L | W3 | Graphviz rendering adds a compiled library/process and resource-resolution policy. Highlight source first; license unverified. |
| 68 | [QLVJ](https://github.com/lov/QLVJ) | mov, qtz | R/? | Defer | Quartz Composer/OpenGL-era behavior; modern public API viability unverified. Standard MOV should remain native. |
| 69 | [FEI-SER-Quicklook](https://github.com/subangstrom/FEI-SER-Quicklook) | FEI ser | R/? | W3 | Scientific microscopy SER variant; not necessarily astronomical SER. Endian/dimensions/resource limits required; license unverified. |
| 70 | [VoxQL](https://github.com/heptal/VoxQL) | vox | R/L | W3 | MagicaVoxel chunk/model parser; mesh budget and unknown chunk fallback needed. License unverified. |
| 71 | [ltquicklooks](https://github.com/laptrinhcomvn/ltquicklooks) | Unspecified | U/? | Defer | Supplied repo 404 and no described files; cannot infer support or licensing. Evidence limit: supplied GitHub repository returned 404. |
| 72 | [QuickLookCodeSnippet](https://github.com/douglashill/QuickLookCodeSnippet) | codesnippet | R/L | W1 | MIT license inspected; README says generator no longer registers. Read plist source/metadata with native code adapter. |
| 73 | [rust-quicklook](https://github.com/yingDev/rust-quicklook) | rs | R/? | Core | Rust already a source-code grammar candidate. License/architecture unverified; no separate plugin needed. |
| 74 | [QLGradle](https://github.com/Urucas/QLGradle) | gradle | R/? | Core | Gradle/Groovy/Kotlin source preview only; never run builds. License/architecture unverified. |
| 75 | [XournalQL](https://github.com/catch22/XournalQL) | xoj | R/L | W3 | Compressed XML/page strokes; reuse gzip/XML plus specialized drawing. License unverified. |
| 76 | [OutlookContactQL](https://github.com/craibuc/OutlookContactQL) | olk14Contact | R/? | Defer | Outlook 2011 proprietary contact format; source semantics/license insufficiently verified. |
| 77 | [QuicklookVideo](https://github.com/BestPig/QuicklookVideo) | avi | R/? | W3 | Different owner from Marginal; README requires ffmpegthumbnailer. External tool dependency unsuitable as assumed user prerequisite; license unverified. |
| 78 | [qlvorbis](https://github.com/clemmece/qlvorbis) | Ogg Vorbis | R/L | W3 | MIT stated for wrapper; libogg/libvorbis licenses separate. Native codec capability test before adding backend. |
| 79 | [bmpQuickLook](https://github.com/hirobe/bmpQuickLook) | bmp | R/L | Native | MIT stated; ordinary BMP support overlaps ImageIO/Finder, unusual BMP variants require real fixtures. |
| 80 | [SublimeSnippetQL](https://github.com/hetima/SublimeSnippetQL) | sublime-snippet, tmSnippet | R/? | W1 | MIT stated; XML/plist snippet source extraction is feasible. Never execute snippets. |
| 81 | [Java-Class-Quick-Look](https://github.com/jaroslawhartman/Java-Class-QuickLook) | class | R/L | W3 | Decompiler toolchain/Java runtime and license unverified. Binary header metadata could be a smaller independent first step. |
| 82 | [QLMarkdownGFM](https://github.com/Watson1978/QLMarkdownGFM) | md | R/L | Core | Legacy GFM renderer; baseline Markdown supersedes. License unverified. |
| 83 | [QLOPML](https://github.com/relikd/QLOPML) | opml | R/L | W1 | MIT stated; bounded XML outline view is feasible. Disable entity loading and do not fetch feed links. |
| 84 | [BetterZipQL](https://macitbetter.com/BetterZip-Quick-Look-Generator) | ZIP, RAR, 7z, TAR/TGZ/TBZ/TXZ, GZip, BZip2, ARJ, LZH, ISO, CHM, CAB, CPIO, DEB, RPM, SIT, BinHex, MacBinary, winmail.dat; supplied DMG unconfirmed | V/M | W2 | Vendor is inspiration; free to use is not source reuse permission. Current vendor list omits DMG. |
| 85 | [CertQuickLook](https://code.google.com/archive/p/cert-quicklook/) | X.509 DER/PEM | U/? | W2 | Archive landing page only; modern certificate reader should use public Security APIs. No license verified. |
| 86 | [quicklookjson](http://www.sagtau.com/quicklookjson.html) | JSON | U/? | Core | Source timed out; redundant with baseline JSON adapter. No license verified. |
| 87 | [ReceiptQuickLook](https://github.com/letiemble/ReceiptQuickLook) | App Store cryptographic receipts | R/L | Defer | README GPL-3.0; ASN.1/CMS inspection is separate from proving purchase validity. |
| 88 | FGOutlook2011 | olk14Message | T/? | Defer | No source URL supplied; legacy Outlook message format and licensing not verified. |
| 89 | [Starcraft Replay QL](https://code.google.com/archive/p/sc2replay-ql/) | StarCraft replay/MPQ, DDS | U/? | Defer | Archive landing page only; replay semantics and MPQ backend require separate work. |
| 90 | [StringsFile](https://blog.timac.org/2014/0325-quicklook-plugin-to-preview-strings-files/) | strings, including binary property lists | V/L | W1 | Author page confirms text/binary strings; reuse license unverified. Implement using text/plist adapters. |
| 91 | [ElektrikTrickQuickLook](https://www.thingiverse.com/thing:376361) | STL, DXF, G-code | U/? | W3 | Supplied page unavailable. G-code text is easy; geometric toolpath/DXF support is separate. |
| 92 | [QuarkXPress](http://forums.quark.com/) | qxp | U/? | Defer | Generic forum inaccessible; no parser or redistribution rights verified. |
| 93 | [EPSQLPlugIn](https://www.eternalstorms.at/utilities/epsqlplg/epsqlplg/download.html) | eps | U/? | Defer | Source inaccessible. PostScript interpreters add a substantial security/licensing surface. |
| 94 | [QLEnscript](https://www.dribin.org/dave/blog/archives/2007/11/14/quick_look_enscript/) | Objective-C/C++, C/C++, Perl, Python, Java, shell, assembly | V/L | Core | Author confirms GPL-derived enscript generator. Use the shared code adapter instead. |
| 95 | [HetimaClipping](http://hetima.com/soft/clippingql-e.html) | textClipping, pictClipping | U/? | Defer | Source inaccessible. Native redundancy and historical clipping format handling need fixtures. |
| 96 | [BrushViewQL](http://brushviewer.sourceforge.net/) | abr | U/? | W3 | Source inaccessible; Adobe brush versions/compression require a bounded specialized reader. |

### Packages — 20 rows

| # | Supplied project / primary source | Formats or feature | Evidence / architecture | Priority | Findings and disposition |
|---|---|---|---|---|---|
| 1 | [Syntax Highlight](https://github.com/sbarex/SourceCodeSyntaxHighlight) | Code; extensionless plain files | R/M | Core | GPL-3.0 inspected; current README macOS 12+, unlike supplied 10.15+. Theme UX inspiration; independent highlighter preferred. |
| 2 | [QLMarkdown (sbarex)](https://github.com/sbarex/QLMarkdown) | md, rmd, qmd, mdx, mdc, apib, textbundle, mermaid | R/M | Core | GPL-3.0 inspected; rich Markdown extension is inspiration. RMD/QMD/MDX must be source-only where evaluation would be required. |
| 3 | [lookdown](https://github.com/qvacua/lookdown) | Markdown | R/? | Core | GPL-3.0 stated; app/UI inspiration only. No new baseline format. |
| 4 | [QLXPlaneObj](https://github.com/Marginal/QLXPlaneObj) | X-Plane obj | R/L | W3 | GPL-2.0-or-later stated; xptools separate MIT. X-Plane OBJ differs from Wavefront OBJ and needs signature dispatch. |
| 5 | [QLdds](https://github.com/Marginal/QLdds) | DDS, DX8/9/10, cubemaps | R/L | W3 | GPL-2.0-or-later stated. README excludes BC6/BC7 and floating formats; independently define actual supported texture encodings. |
| 6 | [QLWindowsApps](https://github.com/shysaur/QLWindowsApps) | dll, exe | R/L | Defer | GPL-3.0-or-later; README explicitly uses private QuickLook API. Reject copying that path; bounded PE metadata may be independent future work. |
| 7 | [quicklook-pat](https://github.com/pixelrowdies/quicklook-pat) | pat | R/? | W3 | Photoshop pattern versions require independent parser and fixture corpus. Architecture/license unverified. |
| 8 | [AssetCatalogTinkerer](https://github.com/insidegui/AssetCatalogTinkerer) | car | R/? | Exclude | BSD-2-Clause license inspected, but private CoreUI headers/source are present. Exclude private-API implementation from App Store plan. |
| 9 | [phew](https://github.com/sveinbjornt/Phew) | FLIF | R/? | Defer | BSD-3-Clause wrapper stated; FLIF LGPL-3.0-or-later dependency. Rare format and decoder footprint do not justify initial scope. |
| 10 | [ProcreateViewer](https://github.com/jaromvogel/ProcreateViewer) | procreate | R/? | W3 | README says Python/Objective-C mix and mostly reference. Embedded preview strategy only after format/version fixtures; license unverified. |
| 11 | [QLAppBundle](https://github.com/relikd/QLAppBundle) | ipa, tipa, appex, xcarchive, apk, apkm | R/M | W2 | MIT inspected; modern preview/thumbnail folders. Covers APK/APKM and IPA/TIPA; README explicitly removes provisioning-profile support. |
| 12 | [QLJSON](https://github.com/relikd/QLJSON) | json | R/M | Core | MIT inspected; modern QLPreview target, no dependencies per README. Foldable JSON is baseline; do not reuse arbitrary user JS customization. |
| 13 | [QLMarkdown (relikd)](https://github.com/relikd/QLMarkdown) | md, markdown | R/M | Core | MIT inspected; swift-markdown Apache-2.0/CSS MIT dependencies. README uses broad temporary file-access exception; do not copy entitlements. |
| 14 | [MacMD Viewer](https://macmdviewer.com) | md, markdown, mdown, mkd, mkdn | V/M | Core | Commercial UX reference; vendor advertises themes, diagrams and offline reading. No source reuse rights verified. |
| 15 | [Suspicious Package](http://www.mothersruin.com/software/SuspiciousPackage/) | pkg | V/M | W3 | Vendor confirms package inspection and QL extension. Independent XAR/payload reader required; never install or run scripts. |
| 16 | [Animated GIF](https://sourceforge.net/projects/animgifqlgen/) | gif | V/L | Native | Page describes OS X 10.5/10.6 plugin, MIT. Historical gap must be retested before overriding native preview. |
| 17 | [ImageFolderQLGenerator](http://hasseg.org/imageFolderQLGenerator/) | Image folders | V/L | Gate | Author marks unmaintained and documents historical folder restriction. Modern folder routing is an empirical gate. |
| 18 | [QLTorrent](http://technocrank.com/downloads/) | torrent | U/? | W2 | Vendor downloads page fetched but no Torrent entry verified. Write a bounded bencode metadata reader; no network discovery. |
| 19 | [quicklook-ipa](https://code.google.com/archive/p/quicklook-ipa/) | ipa | U/? | W2 | Archive landing page only; reuse archive reader and public plist metadata path. |
| 20 | [QuickFits](https://eurus.one/) | fits; supplied fit alias needs signature disambiguation | V/? | W3 | Vendor confirms local Finder FITS previews and debayer/stretch, App Store product. No reusable source verified. |

## Implementation acceptance gates

- [x] Account for every supplied plugin/package row and preserve separate owners/names.
- [x] Identify current-source corrections and primary evidence/unknowns.
- [x] Recommend adapter waves, implementation paths and license/security gates.
- [ ] Add a format registry with canonical UTType, aliases, signatures, adapter, fallback, thumbnail policy, limits and release status.
- [ ] Build real fixtures for each accepted suffix and collision; run Finder preview/thumbnail tests on macOS 15 and newer supported releases with Apple/third-party providers present.
- [ ] Select and pin only necessary parser dependencies; record license/SBOM/notices and extension-safe builds.
- [ ] Prove that thumbnails never expose redacted/sensitive file content and that adapter/copy/accessibility paths share redaction.
- [ ] Measure cold/warm preview latency, peak memory, cancellation and decompression limits before publishing any performance or coverage claims.

This report completes research Task 2. The unchecked items are implementation/release work and must remain unchecked until verified.
