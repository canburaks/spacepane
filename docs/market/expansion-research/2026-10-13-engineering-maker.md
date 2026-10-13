# Engineers, makers, 3D printing, electronics, architecture: expansion candidates

Researched 2026-10-13 (Europe/Istanbul). One of 11 parallel research angles for the post-1.0 expansion. Angle: the audience the STEP/IGES cut ([decision 028](../../decisions/028-no-cad-in-version-1.md)) leaves without a CAD story.

## 1. Method and limits

Evidence labels used throughout:

- **V** = verified: I opened the primary source (spec page, repository file, API response, store listing).
- **VC** = vendor claim: a store listing, README or product page says it; I did not test the product.
- **I** = my inference from verified facts. Treat as a hypothesis.
- **CNV** = could not verify.

What I did:

- Read `docs/decisions/028-no-cad-in-version-1.md`, `docs/decisions/024-mesh-formats.md`, `docs/market/2026-10-05-competitor-landscape.md` and grepped the other market documents for this angle's formats. I did not read the pipeline, renderer or adapter code, so statements about "what the renderer can do" come from decision 024 and are labelled accordingly.
- About 55 tool calls: web searches, GitHub API calls (licence, last push), `raw.githubusercontent.com` licence files, vendor docs, App Store listings through the iTunes Search/Lookup API.
- **iTunes Search API limits.** The API answered the first 16 queries (plus one later retry for IFC) and then returned HTTP 403/429 for the rest of the session, including retries with 14-second spacing. Answered: `gcode quick look`, `gcode viewer`, `dxf quick look`, `dxf viewer`, `gerber viewer`, `kicad quick look`, `kicad viewer`, `dwg quick look`, `dwg viewer`, `sldprt solidworks viewer`, `3dm rhino viewer`, `sketchup skp quick look`, `ifc bim viewer`, `eagle brd schematic viewer`, `embroidery pes viewer`, `vcd waveform viewer`. Not answered (403/429): STEP/IGES, Fusion/FreeCAD/Inventor, Intel HEX/firmware, LAS/point cloud, resin formats, LightBurn, glTF, GDSII, STL volume. For those I used web search instead.
- **Absence of an iTunes hit is weak evidence.** The query `sldprt solidworks viewer` returned 41 apps and none mentioned SOLIDWORKS with a preview word, yet Universal 3D Previewer (which claims SOLIDWORKS) exists. Search ranking hides apps. Where I write "no Quick Look app found", read "none found by iTunes search plus web search", not "none exists".
- I did not download or test any competitor, library or sample file. I had no real CAD, PCB, G-code or firmware sample files, so every "file X contains Y" statement is second-hand unless marked V.
- Bed sizes of common printers, filament densities and prices are not in this document on purpose: I did not verify vendor specification pages, and the candidate that needs them must source them first.

## 2. Key findings

1. **G-code, DXF and slicer-project 3MF previews stopped being open ground in 2026.** G-code Viewer (2026-07-21), DXF Viewer (2026-07-29), DeXeF (2026-07-30), MakerLook (v1.1.4, 2026-10-07) and Universal 3D Previewer (G-code, STEP, SOLIDWORKS) all claim Quick Look for these (V, store listings). Offering them is parity. The way to stand out is an insight layer on top (checks, facts, estimates), which none of the listings I read mention.
2. **Still unclaimed, as far as I could find:** a print-readiness layer for meshes (volume to weight, bed fit, non-manifold/open edges, flipped winding, unit guess); embedded-preview thumbnails for Inventor, Revit, Solid Edge, Rhino, SketchUp, DWG, Fusion and FreeCAD files; KiCad PCB and schematic previews; VCD waveform previews; firmware-image facts (Intel HEX, SREC, UF2, ELF); a text-level STEP/IGES/IFC inspector.
3. **There is no ready non-OCCT route to shaded STEP.** `truck-stepio` is an Apache-2.0 crate whose input module sits behind a feature flag and whose crate-level docs (`lib.rs`) still say input is "further down the road"; `ruststep` labels itself "DO NOT USE FOR PRODUCT"; `foxtrot` is a proof of concept last pushed 2022-09-06. I found no published pass-rate benchmark on real files (CNV). The licence-clean, credible alternative is a **text-level inspector** (header, schema, product tree, census, units, extents, PMI presence, AP242 tessellation if present, edge wireframe). It does not show a shaded solid, and the product copy must not imply it does.
4. **Embedded previews are the cheapest CAD value, with a thin evidence base.** OLE compound files (MS-CFB, an open specification) carry the previews of most Autodesk and Siemens CAD files; ZIP-based formats (FreeCAD, Fusion, 3MF) are trivial. The only source that documents the per-format locations is a three-month-old MIT repository with 0 stars (`cad-preview`). It needs confirmation on real files. Universal 3D Previewer claims SOLIDWORKS now previews as interactive 3D, not a flat image (VC), so a static image is "parity minus" for that one format.
5. **The PCB and EDA family shares one engine.** KiCad (public file-format docs), Gerber/Excellon (Cuprum already ships Quick Look), Eagle XML (Autodesk ended sales and support on 2026-06-07, so files outlive the app) and DXF are all layered 2D vector drawings. Build one layered 2D plot and four readers.
6. **The renderer contract is the hidden cost of every "3D" candidate here.** Decision 024 describes a triangle-only `PreviewMesh` with no colours, lines or points. Toolpaths, STEP wireframes and point clouds need a line/ribbon or point primitive plus per-vertex colour. 2D candidates (PCB, DXF, Gerber, waveform) avoid that cost. This is my inference from the decision text, not from the code.
7. **Licence landmines for this angle:** libbgcode and PrusaSlicer are AGPL-3.0; LibreDWG is GPL-3.0; KiCad is GPL-3.0; GTKWave is GPL-2.0; IfcOpenShell is LGPL-3.0; web-ifc is MPL-2.0; OCCT is LGPL-2.1 (all V via GitHub API). For each, implement from the published file-format specification, never from the code. openNURBS has a custom permissive licence that GitHub cannot classify.
8. **Vendor-side previews are fragile.** `.qlgenerator` plug-ins stopped loading in macOS 15. McNeel's Rhino lost Finder previews on Sequoia (issue RH-84357, fixed in Rhino 8 Service Release 17 per a McNeel forum reply, V), and users still reported problems afterwards. A reader that works without the vendor app installed helps colleagues, clients and fabricators who receive files.

## 3. Ranked candidate table

Ranking weighs: audience pull, distinctiveness against what I found, licence cleanliness, effort. "Ref" numbers point to section 4.

| # | Candidate (suffixes) | Audience | macOS native today | Quick Look competitor coverage | Route + licence | Reuses which presentation | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **Mesh Print Check**: volume to weight/filament/cost, bed fit, open and non-manifold edges, winding, shells, unit guess, overhang share (existing STL, OBJ, PLY, 3MF) | Makers, print farms, students | System shows STL/OBJ/PLY geometry (Hydra) but no analysis | None found. Competitor listings I read (MakerLook, Universal 3D Previewer, MakersPreview, mesh-peek) mention no volume, weight or integrity checks | Own Swift pass over indexed triangles, no dependency | Summary-facts header, typed findings banner, existing 3D mesh view | S to M | **Lead with** |
| 2 | **CAD Cover**: embedded preview and file facts for `.sldprt .sldasm .slddrw .ipt .iam .par .psm .asm .rvt .rfa .3dm .skp .dwg .f3d .f3z .FCStd .max` | Mechanical, architecture, product design | Nothing for these (Finder shows generic icons) | SOLIDWORKS only (Universal 3D Previewer, VC). No Quick Look claim found for the rest | Own reader: MS-CFB (open spec), ZIP, small chunk walkers. No third-party code needed | Pages/images, summary-facts header, content thumbnails | M | **Lead with** (conditional on a legal read of SOLIDWORKS) |
| 3 | **Board Lens: KiCad PCB and schematic** (`.kicad_pcb .kicad_sch .kicad_mod .kicad_sym`), later Eagle XML (`.brd .sch`) | Electronics makers, EE students, open hardware | Nothing | None current. Old "Viewee" qlgenerator (beta, pre-macOS 15); a $1.99 KiCad PCB Viewer app with no Quick Look claim in its listing | Own S-expression parser from the public KiCad file-format docs. No dependency | Offline plot (2D) extended with layers, summary-facts header, sortable BOM table | M | **Lead with** |
| 4 | **STEP and IGES Inspector** (`.step .stp .igs .iges`), text-level | Mechanical engineers, buyers, fabricators | Nothing | STEP geometry: Universal 3D Previewer, StepPreview (VC). Text-level inspection: none found. IGES: none found | Own ISO 10303-21 lexer and IGES fixed-column reader. No kernel, no dependency. **New owner decision** (028 forbids OCCT only) | Summary-facts header, outline/tree, sortable census table, typed findings; optional wireframe through a new line primitive | M (facts, tree, census); L (wireframe) | **Add** |
| 5 | **IFC Inspector** (`.ifc`, `.ifcZIP`), text-level | Architects, BIM coordinators | Nothing | Several standalone IFC viewers on the store; none claims Quick Look in its listing | Same ISO 10303-21 lexer as #4; own entity census | Summary-facts header, outline/tree, property-set table | M (after #4: S to M) | **Add** |
| 6 | **G-code and binary G-code**: facts, embedded thumbnail, checks (`.gcode .gco .gc .bgcode`) and CNC (`.nc .tap .ngc`) | FDM printing, CNC hobbyists | Plain text only | **Claimed**: G-code Viewer ($1.99, toolpath, `.bgcode`, thumbnails); Universal 3D Previewer | Own text parser; `.bgcode` from the published spec plus heatshrink (ISC) and zlib | Summary-facts header, typed findings, content thumbnails; toolpath needs new line primitive | S to M (facts, thumbnails, checks); L (3D toolpath) | **Add** (facts and checks); toolpath **Niche** |
| 7 | **VCD waveform** (`.vcd`; FST later) | FPGA/ASIC engineers, HDL students | Text only | None found. WaveCrux is iOS/iPadOS | Own VCD parser (plain text). FST: licence of libfst not verified, skip | New 2D waveform view on the diagram scene; summary-facts header | M | **Add** |
| 8 | **Gerber and Excellon** (`.gbr .ger .gtl .gbl .gto .gts .drl .xln`, Gerber `.zip`) | PCB designers, fab buyers | Nothing | Cuprum (free, IAP, Quick Look integrated, VC) | Own RS-274X/X2 reader from the Ucamco spec; aperture macros are the hard part | Same 2D layered plot as #3, ZIP listing, summary-facts header | M to L | **Add** |
| 9 | **Firmware image inspector** (`.hex` Intel HEX, `.srec .s19`, `.uf2`, `.elf`) | Embedded, Arduino, RP2040, ESP32 makers | Nothing | None found (CNV, weak) | Own parsers; UF2 spec is MIT | Summary-facts header, memory-map bar (diagram scene), findings (checksum errors) | S to M | **Add** |
| 10 | **Slicer project facts for 3MF** (Bambu, Orca, Prusa, Cura): plates, filaments, printer, plate thumbnail | Bambu/Orca/Prusa owners | Nothing | **Claimed**: MakerLook, MakersPreview, mesh-peek, 3MF Viewer | Existing ZIP/XML reader; read `Metadata/*` | Summary-facts header, content thumbnails (decision 024 left 3MF thumbnails generic) | S to M | **Add** (parity) |
| 11 | **DXF 2D drawing** (`.dxf`) with DWG thumbnail (see #2) | CNC, laser, architecture | Nothing | **Crowded**: MakerLook, DXF Viewer, DeXeF, GeoPreview ($34.99), Eyemesh and iPreview (as 3D) | Own ASCII DXF reader; Autodesk DXF reference is public | 2D plot from #3 | M | **Add** (parity) |
| 12 | **Rhino `.3dm` as real 3D** from cached render meshes | Rhino/Grasshopper users | Nothing (Rhino app only) | None found | openNURBS (custom permissive licence, V) or own chunk walker | Existing mesh view | L | **Niche** |
| 13 | **FreeCAD object and parameter inspector** (`.FCStd`) | FreeCAD users | Nothing | None found | ZIP plus `Document.xml`; folds into #2 | Outline/tree, summary-facts | S | **Niche** (fold into #2) |
| 14 | **Resin printer files** (`.sl1 .sl1s`, `.ctb .cbddlp .pwmo`) | SLA/MSLA owners | Nothing | None found (CNV) | SL1 is ZIP plus INI. CTB needs reverse-engineered layouts; UVtools is the reference, licence not verified | Summary-facts, content thumbnails | S (SL1); L (CTB) | **Niche** |
| 15 | **LightBurn and xTool** (`.lbrn2`; `.xcs .xs`) | Laser makers | Nothing | xTool: MakerLook, MakersPreview. LightBurn: none found | Own XML reader; LightBurn format is undocumented but readable (V, forum) | 2D plot | M | **Niche** |
| 16 | **SPICE netlist and LTspice `.asc`** | Analog EE | Text only | None found (CNV) | Netlist facts: own. `.asc` needs symbol libraries not in the file | Outline, summary-facts | S (netlist); L (schematic) | **Niche** |
| 17 | **GDSII layout** (`.gds`) | IC and photonics designers | Nothing | None found (CNV) | Own record reader; gdstk (Boost) as reference only | 2D plot | M | **Niche** |
| 18 | **Point clouds** (`.las .laz .xyz .pcd .e57`) | Surveyors, scanning | Nothing | GeoPreview (LAS/LAZ, VC); PurpleGeo (app window) | Own LAS reader; LAZ needs laszip (licence not verified) | New point primitive | M to L | **Niche** |
| 19 | **OpenSCAD Customizer table** (`.scad`) | OpenSCAD users | Text only (highlighted) | mesh-peek (VC) | Own annotation parser | Sortable table | S | **Niche** |
| 20 | **Embroidery stitch files** (`.dst .pes .jef .exp`) | Embroiderers | Nothing | **Crowded**: StitchBuddy-QL, ThreadView, Embrilliance Thumbnailer, JEFview | libembroidery (zlib licence, V) | 2D plot | M | **Rule out** (not distinctive) |
| 21 | JT, Parasolid, ACIS, Altium, FST, FPGA bitstreams, Assimp-based mega-importers, DWG geometry, CATIA, Creo | various | | | See section 6 | | | **Rule out** |

## 4. Serious candidates

### 4.1 Mesh Print Check (STL, OBJ, PLY, 3MF)

**What the preview shows.**

- A "Print check" block in the existing summary-facts header plus findings banner. Nothing new to learn for users who already use the Safety Lens findings.
- Facts: bounding box with a unit guess, triangle and shell counts, surface area, volume (already computed for closed meshes, decision 024).
- Estimates: mass = volume x density for a user-chosen material; filament length from volume and diameter; cost from a price per kilogram the user sets in the companion app. Show a range ("solid 62 g, about 25 g at 20 percent infill") and state the assumptions. A slicer is more accurate and the doc must say so.
- Bed fit: "fits on" or "too large for" a short list of printers the user selects in settings. The list needs a sourced data file; I did not verify any printer's build volume.
- Integrity findings: open boundary edges (an edge used by one triangle), non-manifold edges (used by more than two), inconsistent winding between neighbours, negative signed volume (inverted solid), floating shells, units that look wrong (a model under 1 mm or over 1 m across, which usually means inches or metres).
- Optional later: overhang share (faces steeper than a threshold from vertical), a thin-wall hint by casting inward rays from sampled vertices against a BVH. Label it a hint.
- Optional later: highlight problem edges in the 3D view. That needs a line or colour primitive (see key finding 6).

**Demand and competitors.**

- Slicers warn about it daily: PrusaSlicer's "show non-manifold edges" preference and repair warnings are discussed at length in [Prusa forum: Details on errors and warnings](https://forum.prusa3d.com/forum/prusaslicer/details-on-erros-and-warnings) (V). Users are told to run Blender's 3D-Print toolbox for counts (V, same thread).
- A browser tool already computes bounding box, surface area, volume, PLA weight and a watertight check from an STL, which shows the questions are asked often: [imageonline.io STL viewer](https://imageonline.io/stl-viewer/) (V, opened via search; not a Finder tool).
- The GrabCAD question ["grams and dimensions for an STL file"](https://workbench.grabcad.com/questions/is-there-a-way-to-find-the-grams-and-dimensions-for-an-stl-file) (V via search result, content not opened).
- No Mac Quick Look app in my sample does this. Verified listings: [MakerLook](https://apps.apple.com/us/app/makerlook/id6761732470), [Universal 3D Previewer](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617), [G-code Viewer](https://apps.apple.com/us/app/g-code-viewer/id6790530123). Earlier competitor notes cover MakersPreview, mesh-peek, Peek3D, Eyemesh and iPreview. CNV that no listing anywhere has it.

**Implementation route.**

- The shipped mesh builders weld positions by exact value and drop zero-area triangles before producing `PreviewMesh` (decision 024). The check must run on the indexed triangle list before or beside that step so open and non-manifold edges are still visible. I did not read the code; confirm where to hook it.
- Edge map with a hash of (min index, max index); one pass for edge use counts and winding direction; union-find for shells. O(n) memory and time for the 500,000-triangle ceiling in decision 024. Call `context.checkpoint()` in every loop like the readers do.
- Self-intersection testing is excluded: it is expensive and slicers do it better. Say "not checked" in the preview.
- No dependency and no licence issue.

**Safety and privacy.** Pure geometry; nothing sensitive. Thumbnails stay geometry-only (and STL/OBJ/PLY thumbnails are currently left to the system, per decision 024).

**Risks and unknowns.** STL/OBJ/PLY carry no units; the unit guess can be wrong and the dimensions label already assumes millimetres (decision 024 requested a "units are assumed" flag). The "faces" figure saturates at 100,000 (same decision). Weight is only as good as the user's density and infill assumptions. Hydra competes for the STL/OBJ/PLY preview on macOS (decision 024), so the insight layer may never be seen if Finder picks Apple's provider; the provider-conflict diagnostics matter here.

### 4.2 CAD Cover: embedded previews and facts for proprietary CAD

**What the preview shows.** The model's own saved preview image (large, in a Pages/images presentation), a facts header (application and file-format version where the container reveals it, title/author/part number from summary properties, size on disk), and a clear banner "Preview image saved by the CAD program; no geometry is read." The Finder thumbnail is the same image on a neutral background. Files saved without a preview show a plain icon and the facts.

**Per-format locations** (all from the MIT-licensed `cad-preview` README, [github.com/cinderblock/cad-preview](https://github.com/cinderblock/cad-preview), V that the README says this; unverified on real files; repository created 2026-07-05, single author, 0 stars):

| Format | Container | Where the preview lives |
|---|---|---|
| SOLIDWORKS 2015 and later (`.sldprt .sldasm .slddrw`) | Proprietary binary, no reliable magic | A 640x480 PNG stored as a raw-deflate stream; reverse-engineered, no vendor spec |
| SOLIDWORKS 2014 and earlier | OLE compound file | `PreviewPNG` stream, or a headerless DIB in `Preview` |
| Inventor (`.ipt .iam`) | OLE compound file | PNG embedded inside a stream |
| Solid Edge (`.par .psm .asm .dft`) | OLE compound file | DIB thumbnail in a stream or property set |
| Revit (`.rvt .rfa`) | OLE compound file | `RevitPreview` PNG stream (Autodesk staff and community describe a PNG inside the structured storage but I could not find a page naming the stream, CNV) |
| Rhino (`.3dm`) | openNURBS chunks | Start section plus Properties section; DIB with zlib-compressed pixels. McNeel documents that the thumbnail is an uncompressed DIB in `m_PreviewImage` and that only the start of the file needs reading ([McNeel guide](https://developer.rhino3d.com/guides/cpp/extracting-thumbnail-preview-images), V) |
| AutoCAD DWG | DWG header | "Image seeker" pointer at header offset 0x0D leads to a sentinel-delimited preview block; DIB for R13 to R2010, PNG for R2013 on (`cad-preview`; the ODA spec says the same about the seeker, secondary source) |
| DXF | Text | Optional `THUMBNAILIMAGE` section, hex-encoded DIB on group-code 310 lines |
| SketchUp (`.skp`) | Proprietary | Thumbnail PNG straight after the version header |
| Fusion (`.f3d`), FreeCAD (`.FCStd`), 3MF | ZIP | A `thumbnail` or `preview` image part (FreeCAD: `thumbnails/Thumbnail.png`, my recollection, CNV) |
| 3ds Max (`.max`) | OLE compound file | DIB thumbnail |

**Demand and competitors.**

- Finder shows generic icons for DWG; a DraftSight user asks for the Windows-style preview ([3DS community](https://3dswym.3dexperience.3ds.com/question/draftsight-user-community/preview-drawing-on-open-in-mac-os_4944), V via search snippet). Autodesk's community answer for a Mac DWG viewer is "online viewing" ([Autodesk forum](https://forums.autodesk.com/t5/autocad-for-mac-forum/dwg-viewer-for-mac-os/m-p/8989821), V via search snippet).
- Rhino previews vanished on Sequoia and a fix needed a Rhino release: [McNeel forum thread](https://discourse.mcneel.com/t/previews-still-missing-in-apple-sequoia-jan-15-2025/197869) (V). The vendor fix only helps machines with Rhino installed.
- macOS 15 stopped loading `.qlgenerator` plug-ins ([Eclectic Light](https://eclecticlight.co/2024/10/31/how-sequoia-has-changed-quicklook-and-its-thumbnails/), V via search result), which is why every vendor plug-in of this kind is a candidate for silent breakage.
- Competitors: Universal 3D Previewer lists `.sldprt .sldasm .slddrw .sldlfp` and its 3.1 notes say they "now preview as interactive 3D geometry rather than a flat embedded image" ([listing](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617), VC). How it gets that geometry is unknown to me. No Quick Look claim found for Inventor, Revit, Solid Edge, Rhino, SketchUp, DWG, Fusion or FreeCAD (CNV for exhaustive absence).

**Implementation route.**

- OLE compound reader written from [MS-CFB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/53989ce4-7b05-4f8d-829b-d08d6148375b) (V). Microsoft's notice grants copying "to develop implementations"; patents are covered by the Open Specifications Promise only where a document says so (V; have counsel confirm for CFB).
- Bounds: cap the sector count and chain length (cycle detection in FAT and mini-FAT), cap each stream read, cap decoded image dimensions before handing bytes to ImageIO, refuse files above a size limit before reading. Synthesise the 14-byte BMP header for DIB data and let ImageIO decode; decode PNG through ImageIO with a pixel-count ceiling.
- 3DM: walk the chunk list to the properties section only; no geometry. DWG: validate the seeker against file size and the sentinel before reading. SketchUp: look for the PNG signature at the fixed offset only.
- Raw-deflate for modern SOLIDWORKS: use the Compression framework with an output ceiling (inference that it accepts raw deflate).
- No third-party code; the `cad-preview` repo is a map, not a dependency (it is TypeScript).

**Safety and privacy.** The embedded image shows the design and could be confidential; it is the same exposure as Windows Explorer's thumbnails, but it is a policy decision: give it a per-type switch and keep summary-property strings (author, company, part number) out of thumbnails. Never run macros or scripts (none are read).

**Risks and unknowns.**

- **Legal.** The modern SOLIDWORKS container is reverse-engineered (README, V). I did not review SOLIDWORKS, Autodesk or Trimble licence terms. Ask counsel before shipping SOLIDWORKS. OLE-based formats and DWG carry less risk (open container spec, published DWG spec) but the vendor terms are unreviewed.
- **Correctness.** The README may be wrong for current versions. Test files are needed for each format; none were available to me.
- **Value.** A static image is weaker than interactive SOLIDWORKS in Universal 3D Previewer (VC). Its worth is in Finder thumbnails and the "what is this file" answer for the formats nobody covers.
- Files saved with preview graphics switched off return nothing (README, V).

### 4.3 Board Lens: KiCad PCB and schematic (then Eagle XML)

**What the preview shows.**

- PCB: board outline from the `Edge.Cuts` layer, copper layers in conventional colours with a layer toggle, silkscreen and fabrication layers, pads, vias and holes, footprints with reference designators. A summary header: board width and height, layer count, number of footprints, nets, vias and tracks, thinnest track, smallest drill, KiCad version string, generator.
- A sortable component table (reference, value, footprint, layer) that doubles as a bill of materials.
- Schematic: sheet title block, symbol and net-label counts, hierarchical sheet list, and a drawing of wires, labels and symbols. KiCad 6 and later schematics carry their library symbols in the file itself, which would make the drawing self-contained (my recollection; I did not confirm it in this session, CNV). If it is wrong, ship facts and the sheet table first.
- Footprint and symbol library files (`.kicad_mod`, `.kicad_sym`): the shape and pin table.
- Thumbnail: outline plus copper only, no text.

**Demand and competitors.**

- The KiCad forum asks for previews and is told the application would need to register a handler: [PCB layout preview without opening KiCad](https://forum.kicad.info/t/pcb-layout-preview-without-opening-kicad/1311), [PCB or schematic preview](https://forum.kicad.info/t/pcb-or-schematic-preview/19878) (V via search snippets).
- A beta Quick Look plug-in for Eagle and KiCad boards, "Viewee", was announced years ago ([SparkFun community](https://community.sparkfun.com/t/quicklook-plugin-to-view-pcb-layouts-for-eagle-and-kicad/31498), V via snippet). As a `qlgenerator` it cannot load on macOS 15 (see 4.2).
- [KiCAD PCB Viewer](https://apps.apple.com/us/app/kicad-pcb-viewer/id6450205342) ($1.99, v1.4.0 2026-10-07) is a viewer with DRC and a 3D view; its listing does not claim Quick Look (V). No `.kicad_sch` Quick Look found.
- Eagle: Autodesk announced it would stop selling and supporting EAGLE on 2026-06-07 ([Autodesk blog](https://www.autodesk.com/products/fusion-360/blog/future-of-autodesk-eagle-fusion-360-electronics/), [Hackster](https://hackster.io/news/autodesk-announces-the-end-of-eagle-707864d95d7e), V via search). The files keep circulating while the application becomes harder to run (the "cannot run after end of life" claim is a third-party blog, VC).

**Implementation route.**

- Own S-expression tokenizer and a typed reader for the tokens used. Format documentation: [KiCad developer docs, S-expression format](https://dev-docs.kicad.org/en/file-formats/sexpr-intro/index.html) (V: values in millimetres, lower-case tokens, UTF-8 strings, `module` renamed `footprint` in version 6, changes in version 7; the page states no licence for the docs). KiCad itself is GPL-3.0 (V via API): implement from the docs, copy nothing.
- Bounds: input size cap, nesting depth cap, node count cap, per-layer primitive cap with a "showing N of M" notice, like the diagram limits. Arcs and polygons flattened with a step ceiling.
- Eagle XML: the library packages are inside the `.brd`/`.sch`, so a file is self-contained (my recollection, CNV). Use `XMLParser` with no DTD and entity expansion off, as decision 024 does for 3MF.
- Proprietary Altium, OrCAD and PADS formats: not attempted (CNV on public specs).

**Safety and privacy.** Net names, values and notes can reveal a product; keep them out of thumbnails. Project files (`.kicad_pro`) are JSON and already covered by text presentations.

**Risks and unknowns.** KiCad's format changes between major versions (V, docs flag version-specific tokens); unknown tokens must be skipped, never fail the preview. Fonts and stroked text rendering need a decision (a simple stroke font or omit text on thumbnails). Zone fills are stored as polygons in recent versions; older boards without filled zones look empty.

### 4.4 STEP and IGES Inspector (text-level), and the case for it

This section answers question 1(a). It is a **new owner decision**: it uses no OCCT, so it does not conflict with decision 028, but it re-registers `.step/.stp/.igs/.iges` after they were removed from the catalog (their entries are kept in `Configuration/CADFormatCatalogEntries.json` per decision 028).

**What a pure text-level reader can deliver.**

| Item | STEP (ISO 10303-21) | IGES |
|---|---|---|
| Header, schema, originating system | `HEADER` section: `FILE_DESCRIPTION`, `FILE_NAME` (preprocessor version, originating system), `FILE_SCHEMA`. `CONFIG_CONTROL_DESIGN` is AP203, `AUTOMOTIVE_DESIGN` AP214, a name containing `AP242` is AP242 ([STEP Tools header doc](https://steptools.com/docs/stview/header.html), [Wikipedia](https://en.wikipedia.org/wiki/ISO_10303-21), V). Fields are free text and editable, so show them as "reported by the file" | Start and Global sections: sending system, units flag, scale, author, date (my knowledge of the 80-column record layout; not re-fetched) |
| Product and assembly tree | `PRODUCT`, `PRODUCT_DEFINITION`, `NEXT_ASSEMBLY_USAGE_OCCURRENCE`, `PRODUCT_DEFINITION_SHAPE` give names, part numbers and parent-child links; instance transforms through `ITEM_DEFINED_TRANSFORMATION` (I) | Subfigure definitions and instances (entity types 308 and 408) give a weaker tree (I) |
| Entity census | Count by entity type: faces, edges, B-spline surfaces, solids. A "complexity at a glance" line | Count by directory-entry type |
| Units | `SI_UNIT` / `CONVERSION_BASED_UNIT` in a complex entity | Global section units flag |
| Extents | From `CARTESIAN_POINT`s, bounded by what vertices and curves reference. Raw point scans overestimate: axis placements and B-spline control points lie outside the geometry. Better: vertex points plus analytic circle and ellipse extents. Label as "approximate" | From line and arc endpoints |
| PMI presence | AP242 semantic PMI: `GEOMETRIC_TOLERANCE`, `DATUM`, `DIMENSIONAL_SIZE`, annotation occurrences (I). Show counts only | None |
| Colours and layers | `COLOUR_RGB` via `STYLED_ITEM`; `PRESENTATION_LAYER_ASSIGNMENT` (I) | Colour and level fields in the directory entries |
| Tessellated geometry | AP242 adds `TRIANGULATED_FACE`, `COMPLEX_TRIANGULATED_FACE` (strips and fans), `COORDINATES_LIST` ([CAx-IF recommended practice, release 1.1, 2019](https://www.mbx-if.org/documents/rec_prac_3dtess_geo_v11.pdf), [entity definition](https://steptools.com/docs/stp_aim/html/t_tessellated_face.html), V). If a file has them, they can feed the existing mesh view directly. How common they are in files in the wild: CNV | None |
| Wireframe | `EDGE_CURVE` over `LINE`, `CIRCLE`, `ELLIPSE`, `B_SPLINE_CURVE_WITH_KNOTS` evaluates analytically. No face trimming, no kernel (I) | Entities 110 line, 100 circular arc, 104 conic, 126 rational B-spline curve, 102 composite curve, 124 transformation (I). IGES wireframe is the natural fit |
| Shaded solid | Needs surface trimming and tessellation: a kernel. Planar-only parts are feasible by ear clipping; B-spline and trimmed analytic surfaces are not (I) | Same |

**Is it a credible "STEP Inspector" preview?** For the people the cut hurt (an engineer asking "which revision, which tool, what units, how many parts, is it an assembly?") yes. For "show me the part" no. The honest label is *Inspector*, with a banner "Geometry is not shaded; edges are drawn from curve definitions." A wireframe makes the file recognisable without pretending to be a render.

**Does any Quick Look app do it?** Universal 3D Previewer and StepPreview render STEP geometry (VC); I found nothing documenting a header, product-tree or census view (CNV, absence not proven). IGES: no app found by the competitor note or by me.

**Implementation route.**

- Lexer for `#id = ENTITY(...)` records, nested lists, enumerations `.T.`, strings with `''` and `\X\` escapes, complex entities `( A() B() )`. Two passes: scan to record entity offsets (streaming, bounded by a record count and a total byte ceiling), then resolve only the references the views need.
- Large files: the pipeline reads a bounded buffer (16 MiB for meshes per decision 024). Real assemblies exceed that. Give files above the ceiling a header-and-first-N-entities view, with a notice, rather than failing. A head-and-tail read mode is not needed here.
- Bounds: entity count ceiling, reference depth ceiling with cycle detection, curve sampling step ceiling, transform chain depth ceiling.
- Spec status: ISO 10303-21 is a paid standard; the syntax is widely documented ([Wikipedia](https://en.wikipedia.org/wiki/ISO_10303-21), STEP Tools). The AP schemas are published as EXPRESS by multiple sites. I did not check redistribution terms; implement from the grammar, ship no schema text. IGES 5.3 availability and terms: CNV.

**Safety and privacy.** Product names, part numbers and the originating company are in the header and tree; show them in the preview, never in thumbnails. No thumbnail until a wireframe exists.

**Risks and unknowns.** Wireframe needs the line primitive. Hand-edited and vendor-extended files break strict parsing: make the lexer lenient and report "N records could not be read" as a finding. Units in STEP are easy to misread (complex `SI_UNIT` combinations).

### 4.5 IFC Inspector (BIM)

**What it shows.** Schema (`IFC2X3`, `IFC4`, `IFC4X3`), originating application (for example the authoring tool in `FILE_NAME`), project, site, building, storeys with elevations, element counts by class (`IFCWALL`, `IFCSLAB`, `IFCDOOR`, `IFCWINDOW` ...), a property-set and quantity-set table (gross floor area, volumes), materials, classification references, and validation-style findings (unresolved references, missing storey). IFC is an ISO 10303-21 file, so the lexer from 4.4 applies unchanged (V: buildingSMART states the `.ifc` physical file is the STEP clear-text encoding; [buildingSMART IFC](https://www.buildingsmart.org/standards/bsi-standards/industry-foundation-classes/), V via search; the standard is published under a Creative Commons licence per buildingSMART, VC).

**Geometry.** Not read. A permissive reader does not exist as far as I could find: IfcOpenShell is LGPL-3.0 (V), web-ifc is MPL-2.0 (V; outside the permissive-only rule even if the owner would accept file-level copyleft), xBIM is not checked. Assimp has an IFC importer under a BSD-style licence (V for the licence header; capability, IFC2x3 coverage and robustness not verified; I would not rely on it). Some IFC4 exports contain `IfcTriangulatedFaceSet`; if so they could feed the mesh view (I; frequency CNV).

**Demand and competitors.** Standalone IFC apps exist: [IFC Opener](https://apps.apple.com/us/app/ifc-opener-ifc-file-viewer/id6804017667), [IFC Viewer](https://apps.apple.com/us/app/ifc-viewer/id6758959860), [IFC View](https://apps.apple.com/us/app/ifc-view/id6792756993), [Point Cloud & BIM Viewer](https://apps.apple.com/us/app/point-cloud-bim-viewer/id6812413362) (V, iTunes). None of the four descriptions mentions Quick Look or thumbnails (V for those descriptions). Demand for Quick Look specifically: CNV.

**Risk.** Large IFC files (tens to hundreds of MB) cannot be read in full; the same header-and-prefix fallback as STEP applies, with a loud notice.

### 4.6 G-code, binary G-code and CNC

**Competitors (V).** [G-code Viewer](https://apps.apple.com/us/app/g-code-viewer/id6790530123) (Matthew Thornton, $1.99, 2026-07-21): toolpath per layer, `.bgcode`, Quick Look and thumbnails. Universal 3D Previewer lists "G-code/GCO". So a toolpath view is parity. Still unclaimed in the listings: slicer facts, embedded thumbnail, and checks.

**What the preview shows.**

- Facts from slicer comments: slicer name and version, estimated print time, filament used (length, volume, grams), layer height, layer count, nozzle and bed temperatures, printer and filament profile names, flavour (Marlin, Klipper, RepRapFirmware, Bambu).
- The embedded thumbnail as the Finder thumbnail and as the header image. PrusaSlicer writes it as base64 PNG (or QOI since 2.7) in comment lines between `; thumbnail begin` and `; thumbnail end` ([Prusa forum](https://forum.prusa3d.com/forum/hardware-firmware-and-software-help/how-to-view-gcode-thumbnails-on-pc/), [Prusa help](https://help.prusa3d.com/article/model-preview_648687), V via search).
- G-code checks (typed findings): no `G28` homing before the first move; no temperature set before extrusion; moves outside the stated bed or `MAXX/MAXY/MAXZ` header; temperatures beyond a sanity range; unusually high feed rates; `M600` filament change present; the stated layer count against the layers actually found; file truncated (no end-of-print lines). Compute the toolpath bounding box and compare with the bed.
- CNC (`.nc .tap .ngc`): units (`G20/G21`), work offsets, tool list, spindle speed range, feed range, min and max Z, estimated time from feed and path length. Block unsafe-looking ones with a finding ("rapid move below Z0").
- Optional layer-by-layer toolpath view: needs a line or ribbon primitive in the Metal view (L).

**Format facts.**

- Slicer statistics sit at the **end** of PrusaSlicer files ("; estimated printing time (normal mode) = ...", "; filament used [mm] = ...") and the settings dump starts at `; prusaslicer_config = begin` ([Prusa forum threads via search](https://forum.prusa3d.com/forum/prusaslicer/how-to-get-duration-and-filament-usage-on-cli/), V via snippet). The pipeline must read the head and the tail of a file that can be hundreds of megabytes. I did not check whether the pipeline can do this.
- Binary G-code (`.bgcode`): `GCDE` magic, version, checksum type; blocks for file, printer, print and slicer metadata, thumbnails (PNG, JPG, QOI) and G-code; compression none, deflate, or heatshrink with window 11 or 12 and lookahead 4; G-code optionally MeatPack-encoded ([libbgcode specification](https://github.com/prusa3d/libbgcode/blob/main/doc/specifications.md), V). The library and PrusaSlicer are AGPL-3.0 (V). The specification states no licence (V). Implement from the specification only; heatshrink is ISC (V via API); deflate through the Compression framework. Counsel should confirm that implementing from the spec in an AGPL repository is fine.
- Vendors differ: Cura writes `;TIME:`, `;Filament used:` and `;MINX..MAXZ` header lines, Bambu writes a header block with a model-time line and total layer number. I did not verify these two from a primary source (I).

**Bounds.** Line-count and byte ceilings; a move-count ceiling with decimation for display; refuse arithmetic that overflows; decompression ceilings for `.bgcode` blocks; never interpret macros or `M` commands that would trigger external effects (nothing is executed, only read).

**Safety and privacy.** G-code footers and project configs can contain print-host URLs and credentials in some slicer versions (I; not verified for any version). Route config blocks through the existing secret concealment and inventory. Embedded thumbnails are the slicer's own render; fine for Finder.

**Collisions.** `.nc` is also NetCDF and `.tap` and `.hex` have other uses (I); content sniffing before claiming the file.

**Verdict.** Facts, thumbnails and checks: **Add** (S to M). Toolpath 3D: **Niche** (L, already covered).

### 4.7 VCD waveform preview

**Why it fits SpacePane.** The app already highlights Verilog and VHDL sources. A `.vcd` file is the simulator's output and is plain text; it opens as thousands of lines of identifiers.

**What the preview shows.**

- Header facts: date, simulator version, timescale, scope hierarchy, signal and bus count, time span, total changes.
- A waveform canvas for the first signals with a collapsible hierarchy: digital traces, bus values in hex, `x`/`z` states drawn distinctly, time ruler, zoom to the first N changes.
- Summaries as findings: signals that never change; signals containing `x` or `z` after time zero; a clock period estimate for the busiest 1-bit signal; zero-width glitches. These are checks a reviewer cares about.
- Thumbnail: a small stack of traces.

**Demand and competitors.**

- GTKWave, the default viewer, is the Homebrew cask `gtkwave` flagged **disabled, discontinued, on 2025-10-29** ([Homebrew cask API](https://formulae.brew.sh/api/cask/gtkwave.json), V). MIT's course page says the stock install fails on recent macOS and recommends a community tap or Surfer ([MIT 6.205 waveform viewers](https://fpga.mit.edu/6205/F25/documentation/waveform_viewers), V via snippet). Surfer is on GitLab with 196 stars (V via API).
- [WaveCrux](https://apps.apple.com/us/app/wavecrux/id6787506007) (Ferrite Engineering, 2026-09-30) reads VCD, FST, GHW, LXT and LXT2, but the listing says iPhone and iPad (V). No Mac Quick Look found.

**Route and licence.** Own parser: `$timescale`, `$scope`, `$var`, `#time`, value changes for scalars, vectors, reals. The IEEE 1364 definition is paid but the format is stable and widely documented; I did not fetch a free specification (CNV). GTKWave is GPL-2.0 (V); do not read or copy its code. FST (GTKWave's binary format): I could not locate libfst's licence or a standalone specification, so FST is out until that is checked.

**Bounds.** Signal count, change count and string-length ceilings; stream the file rather than load it; decimate display.

**Risk.** Long traces (gigabytes) cannot be read in 16 MiB; show the first section and say so. Audience is small but unserved and aligned with the existing HDL support.

### 4.8 Gerber and Excellon

**What it shows.** A fabrication set drawn as a board: copper, mask, silk, outline and drills, coloured by layer; a layer table from `TF.FileFunction` attributes (Gerber X2); board size; hole table (diameters and counts) from Excellon; for a `.zip` of fabrication files, the whole set stacked, with the ZIP listing still available. Findings: missing outline, missing drill file, mixed units.

**Competitors.** Cuprum ([listing](https://apps.apple.com/us/app/cuprum/id1088670425), V): Gerber, Excellon, XNC and ODB++, "a QuickLook plugin is integrated". It is free with in-app purchases and was last updated 2025-07-21. So Gerber is claimed. A ZIP-aware, KiCad-aware lens in a general app remains different.

**Route.** The format is published by Ucamco (current revision 2023.08 per [Wikipedia](https://en.wikipedia.org/wiki/Gerber_format)); I did not confirm the download terms (CNV). Implement apertures (circle, rectangle, obround, polygon), flashes, linear and circular interpolation, regions, step-and-repeat, polarity, and aperture macros. Macros (arithmetic expressions, exposure-off cut-outs) are the hard part (L). `tracespace` (MIT, [repo](https://github.com/tracespace/tracespace), V via API) is a JavaScript reference to test against, not a dependency; `gerbv` is GPL and excluded.

**Risk.** Variation between CAD exporters is wide; Excellon dialects especially. Ship after #3 reuses the layered plot.

### 4.9 Firmware image inspector

**What it shows.**

- Intel HEX: record count, address range(s), total bytes, start address, per-line checksum failures as findings, a memory-map bar.
- SREC: same, with S0 header text.
- UF2: block count, target address range, flags, family ID, extension tags (firmware version, device description) per the [UF2 specification](https://github.com/microsoft/uf2) (V; MIT licence, V). A family ID table should be taken from the repository's family list (not fetched; CNV on its contents).
- ELF: class, machine, entry point, program headers and sections with sizes, symbol and string table counts, build ID, whether stripped. Pure header parsing, bounded.
- No hex dumps of unknown binaries (rejected in decision 025); this is for typed, self-describing formats only.

**Competitors.** None found for Quick Look (web search for Intel HEX, SREC, UF2, ELF returned only generic generators and a hex editor; CNV on absence).

**Audience evidence.** Weak: no thread found that asks for this. It is cheap and safe, and fits embedded and maker workflows (Arduino, RP2040, ESP32). Treat it as a low-cost breadth item, not a headline.

**Collision.** `.hex` has other uses; sniff the first record (`:` plus hex digits and a valid checksum).

### 4.10 Slicer project facts for 3MF

SpacePane already reads 3MF geometry. Slicer projects add: printer and plate settings, per-plate objects, filament names and colours, and per-plate preview images. Bambu Studio files hold `Metadata/plate_N.png`, `project_settings.config` (JSON), `model_settings.config` (XML), and for sliced files `slice_info.config` and `Metadata/plate_N.gcode` (V via [Printago](https://printago.io/blog/3mf-file-format) and PyPI `bambox` snippets; the contents of `slice_info.config` are not described in what I read). Standard 3MF also defines a thumbnail relationship in its package format (my recollection, CNV).

Value: use the embedded plate image as the Finder thumbnail (decision 024 records 3MF thumbnails as generic and the embedded image as future work) and show a plate picker with filaments. Competitors already do this (MakerLook shows plate layout, plate names, filament colours and names, printer, layer height, plate size, object count, V listing; MakersPreview lists plate previews, VC), so this is parity, not a headline. `project_settings.config` may contain printer host details (I); run it through secret concealment.

### 4.11 DXF 2D drawing, with DWG facts

DXF is crowded (section 3). Reasons to build it anyway: it is cheap once the 2D layered plot exists for PCB work, and it completes the "CAD value" story with CNC and laser users. Own ASCII reader for `LINE`, `LWPOLYLINE`, `POLYLINE`, `ARC`, `CIRCLE`, `ELLIPSE`, `SPLINE`, `TEXT/MTEXT`, `INSERT` with blocks, `HATCH` outlines; layers with AutoCAD index colours; `$INSUNITS`; extents; the optional `THUMBNAILIMAGE`. Bounds: entity ceiling, block-recursion ceiling, spline degree and control point ceiling. `ezdxf` (MIT, V via API) is a Python reference to cross-check, not a dependency. `libdxfrw` and `dxflib` are GPL (my recollection, CNV) and excluded. DXF Viewer's listing says it covers "lines, polylines (incl. bulge arcs), circles, arcs, ellipses, splines, text, blocks" and "layers with proper AutoCAD colours" (V), which sets the parity bar.

DWG geometry stays **ruled out**: LibreDWG is GPL-3.0 (V via API), the Open Design Alliance's toolkits are proprietary (VC, not opened), and the ODA's own specification is reverse-engineered and covers R13 to AutoCAD 2018 (secondary source). DWG gets the thumbnail and version string only (4.2).

### 4.12 Rhino `.3dm` as 3D (answer to 1(d))

- **Licence (V).** The openNURBS repository's [LICENSE](https://github.com/mcneel/opennurbs/blob/8.x/LICENSE) is a copyright line, an "as is" warranty disclaimer, and the bundled zlib licence, which it calls "similar" to its own. GitHub reports "NOASSERTION". McNeel's [openNURBS page](https://developer.rhino3d.com/guides/opennurbs/what-is-opennurbs/) says "Commercial use is encouraged" and "There are no restrictions. Neither copyright nor copyleft restrictions apply." So it is permissive in practice but non-standard; it is outside the owner's literal list of named licences and should get a legal read before it is linked. Repository pushed 2026-10-06 (V).
- **Cached meshes.** Rhino's `SaveSmall` command exists to save a file without render meshes to make it smaller, and the documentation says shading is slower on reopen because meshes are regenerated ([McNeel Save docs](https://docs.mcneel.com/rhino/8/help/en-us/commands/save.htm), V via search snippet). Normal saves therefore carry render meshes on Breps. A real 3D view through the mesh renderer is plausible for normally saved files and impossible for SaveSmall files. Whether openNURBS exposes them without constructing the full document, memory use on large files, and robustness against hostile input are CNV.
- **Route.** First deliver the thumbnail (4.2). Then, if wanted, either link openNURBS (large C++ code base inside the extension, hostile-input exposure) or write a chunk walker for the geometry (the chunk grammar is only described in the openNURBS sources; I found no standalone specification). Both are L.

### 4.13 Smaller candidates, in one place

- **FreeCAD `.FCStd`.** ZIP with `Document.xml` (objects, types, labels, properties), `GuiDocument.xml`, `.brp` BREP files and an optional thumbnail. An outline of features and the parameters they carry is a useful insight view. Fold into CAD Cover. The BREP files are OCCT's text format; do not parse geometry.
- **Resin printers.** `.sl1/.sl1s` is a ZIP with an INI config and PNG slices and thumbnails (V via [Prusa help](https://help.prusa3d.com/glossary/sl1-file-sl1_141519) and forum snippets). Easy: thumbnail plus exposure and layer facts. `.ctb/.cbddlp` binary headers are documented only by UVtools' source (licence not verified; assume GPL until checked). Do SL1 only.
- **LightBurn `.lbrn2`.** XML with `LightBurnProject`, `CutSetting` layers and `Shape` elements of type Path, Rect, Ellipse, Bitmap; undocumented but readable per LightBurn staff ([forum](https://forum.lightburnsoftware.com/t/lbrn2-file-documentation/52174/3), V via snippet). I found no confirmation that a thumbnail element exists (CNV). A 2D plot with cut/engrave layer colours is the preview.
- **xTool `.xcs/.xs`.** Covered by MakerLook (canvases, colour layers, machine and material, V) and MakersPreview (VC).
- **SPICE/LTspice.** Netlist inspector (components, models, `.tran/.ac/.dc` directives) is S. `.asc` schematics reference symbol definitions that live outside the file (my recollection), so the drawing would need built-in symbols. Low evidence of demand.
- **GDSII.** Binary record stream; gdstk is Boost Software License 1.0 (V via API) and would be a reference. Audience is small and I found no demand evidence.
- **Point clouds.** `GeoPreview` ($34.99) previews LAS/LAZ in Quick Look (VC); `.asc` is also used as a point-cloud suffix by MakerLook (V), a collision risk for any `.asc` claim. Needs a point primitive.
- **OpenSCAD.** Source is already highlighted. A Customizer table from `// [min:max]` annotations is S. Rendering requires running OpenSCAD, which is excluded. mesh-peek claims SCAD preview (VC).

## 5. Routes back to STEP and IGES value without OCCT

Decision 028 forbids restoring STEP or IGES **with OCCT** without a recorded licence clearance. Everything below is an option for a new owner decision, not a plan.

| Route | What the user gets | Licence | Maturity evidence | Effort | Main risk | Verdict |
|---|---|---|---|---|---|---|
| **(a) Text-level STEP/IGES Inspector** (4.4) | Header, schema, tree, census, units, approximate extents, PMI presence, colours and layers, AP242 tessellation if present, edge wireframe, IGES wireframe | None (own code) | Formats are plain text and widely documented | M (facts) to L (wireframe) | Not a shaded view; users expect one | **Do this first** if the owner wants a STEP/IGES story |
| **(b) Rust kernel: truck / truck-stepio** | Shaded B-rep for the entities it supports | Apache-2.0 (V). Repository pushed 2026-09-28, 1,618 stars (V). `truck-stepio` 0.3.0, updated 2024-09-20, 101,757 total downloads (V, crates.io). The input module sits behind feature `in`; the crate docs still say input will come "further down the road" (V) | No benchmark on real files found (CNV). `ruststep` (Apache-2.0, last push 2025-03-19) says "DO NOT USE FOR PRODUCT" (V) | L, plus a Rust toolchain in the build, plus a static library and C ABI | Unknown pass rate on real SolidWorks, Fusion and Creo files; panics and stack depth on hostile input must be contained | **Spike only** (below) |
| **(b2) Foxtrot** | Fast triangulation of AP214 files | Apache-2.0 or MIT (V). Last push 2022-09-06 (V) | "proof-of-concept demo, not an industrial-strength CAD kernel... It may not work for your models" (V, README) | L | Abandoned; some surfaces fail | **Reference reading only** |
| **(b3) Newcomers** (`BREP_kernel` 0.5.0, `monstertruck` fork of truck) | Claims NURBS B-rep and STEP import | Unknown for `BREP_kernel`; `monstertruck` licence not confirmed | Search snippets only (V that they exist) | L | Unvetted | **Ignore until vetted** |
| **(c) Embedded previews of proprietary CAD** (4.2) | A saved picture of the part | None (own code) | One unvetted MIT repo plus vendor docs; needs real-file testing | M | Legal read for SOLIDWORKS; files without previews | **Do this**; it serves native files, not STEP |
| **(d) openNURBS for `.3dm`** (4.12) | Real 3D from cached render meshes | Custom permissive (V), legal read needed | Maintained (pushed 2026-10-06) | L | Meshes absent in SaveSmall files; large C++ code in the extension | **Later**, after the thumbnail |
| **(e) Other exchange formats** | See below | See below | | | | |
| **(f) OCCT with Open Cascade's limited static-linking exception** (decision 028) | Full shaded STEP/IGES | Commercial exception; terms and price unknown to me | Shipped product exists (the repo's own CADWorker) | S (code exists) plus the licence cost | Cost, scope of the exception | Owner decision, outside this research |

**(e) Other exchange formats at a glance**

| Format | Reader | Licence | Verdict |
|---|---|---|---|
| IFC | Text inspector (4.5); geometry only through LGPL/MPL libraries | IfcOpenShell LGPL-3.0, web-ifc MPL-2.0 (V) | Inspector yes, geometry no |
| JT (ISO 14306) | The specification is a paid ISO standard (ISO 14306:2017 listed at EUR 259.90 by DIN; the series was split in 2024 and 2025) ([ISO](https://www.iso.org/standard/86063.html), [ANSI webstore](https://webstore.ansi.org/standards/iso/iso143062017), V via search). Segments are compressed. I found no free Siemens-hosted specification (CNV) | Siemens' toolkit is proprietary (VC) | Rule out |
| Parasolid `.x_t/.x_b`, ACIS `.sat` | B-rep text or binary with no tessellation (I). Parsing the container gives metadata only | Specifications not verified | Rule out |
| glTF/GLB | `cgltf`, MIT (V). Draco-compressed GLB needs a separate decoder (licence not checked) | MIT | Add only if the 3D/graphics agent recommends it; MakersPreview and Eyemesh claim GLB (VC) |
| FBX | `ufbx`, dual-licensed with MIT as alternative A (V). Eyemesh and iPreview claim FBX | MIT | Same |
| COLLADA, AMF, X3D/VRML, OFF | XML via `XMLParser` (COLLADA, AMF, X3D); OFF is trivial. AMF is largely replaced by 3MF (I) | Own code | Low priority; Eyemesh lists DAE and WRL (VC) |
| Point clouds | See 4.13 | LAS/LAZ licence not verified | Niche |

**Recommendation.** Do not restore shaded STEP or IGES on a non-OCCT route now. The permissive Rust options are not shown to work on real files, and the one with a real maintenance record (`truck`) only recently grew an input path. Choose between: (1) *no CAD story in 1.x* and spend the effort on #1, #3 and #7; (2) *a CAD-adjacent story*: CAD Cover (#2) plus the Inspector (#4, #5), which reads as "the Quick Look for CAD files you cannot open", clearly not a viewer; (3) *a measured spike* of `truck-stepio` on a 100-file corpus (SolidWorks, Fusion, Onshape, Creo, NX exports in AP203, AP214 and AP242), counting files that load, load with holes, or panic, and recording peak memory, before anyone commits to a Rust dependency. Option (2) can start immediately; option (3) is a two-week decision tool, not a feature.

## 6. Ruled out and why

| Item | Reason |
|---|---|
| DWG geometry | LibreDWG is GPL-3.0 (V); ODA toolkits are proprietary (VC). No permissive reader found. Thumbnail and version string only |
| JT, Parasolid, ACIS, CATIA, Creo, NX native | Specification is paid or absent; no tessellation in the text forms; no permissive reader found |
| `.ctb` and other binary resin formats beyond SL1 | Only reference is UVtools' source (licence unverified); effort L for a niche audience |
| Altium `.PcbDoc/.SchDoc`, OrCAD, PADS | Proprietary structures; no public specification found (CNV) |
| FST waveforms | libfst licence and a standalone spec not located; GTKWave is GPL-2.0 |
| FPGA bitstreams, IC mask formats beyond GDSII | Proprietary or undocumented; tiny audience |
| Embroidery stitch files | Crowded: StitchBuddy-QL, ThreadView ($24, VC), Embrilliance Thumbnailer ($39), JEFview (discontinued) ([search result](https://embrilliance.com/thumbnailer), VC). libembroidery is zlib-licensed (V), so it would be cheap, but it is not distinctive |
| OpenSCAD rendering | Needs the OpenSCAD engine; executing it is excluded by decision 025 |
| Assimp as a universal importer | BSD-style licence (V header) but a huge, historically fuzz-prone attack surface for a sandboxed extension (I); each format is better read by a small bounded reader |
| Hex-dump views of unknown firmware `.bin` | Rejected in decision 025 |
| Mesh repair or editing | Read-only product; a check is in scope, a fix is not |

## 7. Sources

Local documents read: `docs/decisions/028-no-cad-in-version-1.md`, `docs/decisions/024-mesh-formats.md`, `docs/market/2026-10-05-competitor-landscape.md`.

App Store listings (V, via iTunes lookup or page fetch):
- [MakerLook](https://apps.apple.com/us/app/makerlook/id6761732470), [G-code Viewer](https://apps.apple.com/us/app/g-code-viewer/id6790530123), [DXF Viewer](https://apps.apple.com/us/app/dxf-viewer/id6793224652), [DeXeF](https://apps.apple.com/us/app/dexef/id6781488401), [GeoPreview](https://apps.apple.com/us/app/geopreview/id6758587360), [Universal 3D Previewer](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617), [Cuprum](https://apps.apple.com/us/app/cuprum/id1088670425), [KiCAD PCB Viewer](https://apps.apple.com/us/app/kicad-pcb-viewer/id6450205342), [WaveCrux](https://apps.apple.com/us/app/wavecrux/id6787506007), [StitchBuddy](https://apps.apple.com/us/app/stitchbuddy/id1167912393)
- IFC apps: [IFC Opener](https://apps.apple.com/us/app/ifc-opener-ifc-file-viewer/id6804017667), [IFC Viewer](https://apps.apple.com/us/app/ifc-viewer/id6758959860), [IFC View](https://apps.apple.com/us/app/ifc-view/id6792756993), [Point Cloud & BIM Viewer](https://apps.apple.com/us/app/point-cloud-bim-viewer/id6812413362)

Repositories and licences (V via GitHub API unless noted):
- [ricosjp/truck](https://github.com/ricosjp/truck) (Apache-2.0), [truck-stepio source](https://github.com/ricosjp/truck/tree/HEAD/truck-stepio), [crates.io truck-stepio](https://crates.io/crates/truck-stepio), [docs.rs truck-stepio](https://docs.rs/truck-stepio/latest/truck_stepio/)
- [ricosjp/ruststep](https://github.com/ricosjp/ruststep) (Apache-2.0), [Formlabs/foxtrot](https://github.com/Formlabs/foxtrot) (Apache-2.0 or MIT), [docs.rs monstertruck](https://docs.rs/monstertruck), [docs.rs BREP_kernel](https://docs.rs/crate/BREP_kernel)
- [mcneel/opennurbs](https://github.com/mcneel/opennurbs) and its [LICENSE](https://github.com/mcneel/opennurbs/blob/8.x/LICENSE)
- [prusa3d/libbgcode](https://github.com/prusa3d/libbgcode) (AGPL-3.0), [PrusaSlicer](https://github.com/prusa3d/PrusaSlicer) (AGPL-3.0), [LibreDWG](https://github.com/LibreDWG/libredwg) (GPL-3.0), [KiCad mirror](https://github.com/KiCad/kicad-source-mirror) (GPL-3.0), [GTKWave](https://github.com/gtkwave/gtkwave) (GPL-2.0), [IfcOpenShell](https://github.com/IfcOpenShell/IfcOpenShell) (LGPL-3.0), [web-ifc](https://github.com/ThatOpen/engine_web-ifc) (MPL-2.0), [OCCT](https://github.com/Open-Cascade-SAS/OCCT) (LGPL-2.1)
- [cgltf](https://github.com/jkuhlmann/cgltf) (MIT), [ufbx](https://github.com/ufbx/ufbx) (MIT alternative A, [LICENSE](https://raw.githubusercontent.com/ufbx/ufbx/master/LICENSE)), [tinyobjloader](https://github.com/tinyobjloader/tinyobjloader) (MIT, [LICENSE](https://raw.githubusercontent.com/tinyobjloader/tinyobjloader/release/LICENSE)), [Assimp](https://github.com/assimp/assimp) ([LICENSE](https://raw.githubusercontent.com/assimp/assimp/master/LICENSE), BSD-style header), [heatshrink](https://github.com/atomicobject/heatshrink) (ISC), [libembroidery](https://github.com/Embroidermodder/libembroidery) (zlib), [gdstk](https://github.com/heitzmann/gdstk) (BSL-1.0), [ezdxf](https://github.com/mozman/ezdxf) (MIT), [tracespace](https://github.com/tracespace/tracespace) (MIT), [microsoft/uf2](https://github.com/microsoft/uf2) (MIT per page), [cinderblock/cad-preview](https://github.com/cinderblock/cad-preview) (MIT, created 2026-07-05)

Specifications and vendor documents:
- [MS-CFB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/53989ce4-7b05-4f8d-829b-d08d6148375b) (V, opened)
- [libbgcode binary G-code specification](https://github.com/prusa3d/libbgcode/blob/main/doc/specifications.md) (V, opened)
- [KiCad S-expression docs](https://dev-docs.kicad.org/en/file-formats/sexpr-intro/index.html) (V, opened)
- [CAx-IF tessellated geometry recommended practice 1.1](https://www.mbx-if.org/documents/rec_prac_3dtess_geo_v11.pdf), [STEP Tools tessellated_face](https://steptools.com/docs/stp_aim/html/t_tessellated_face.html), [STEP Tools header doc](https://steptools.com/docs/stview/header.html), [Wikipedia ISO 10303-21](https://en.wikipedia.org/wiki/ISO_10303-21) (V via search results)
- [Open Design Specification for .dwg files](https://opendesign.com/files/guestdownloads/OpenDesign_Specification_for_.dwg_files.pdf) (V that it exists; not opened)
- [McNeel: extracting thumbnails](https://developer.rhino3d.com/guides/cpp/extracting-thumbnail-preview-images) (V, opened), [openNURBS overview](https://developer.rhino3d.com/guides/opennurbs/what-is-opennurbs/) (V, opened), [Rhino Save docs](https://docs.mcneel.com/rhino/8/help/en-us/commands/save.htm) (search snippet)
- [buildingSMART IFC](https://www.buildingsmart.org/standards/bsi-standards/industry-foundation-classes/), [ISO 14306-1](https://www.iso.org/standard/86063.html), [ANSI webstore ISO 14306:2017](https://webstore.ansi.org/standards/iso/iso143062017)
- [Homebrew gtkwave cask API](https://formulae.brew.sh/api/cask/gtkwave.json) (V, opened), [MIT waveform viewers](https://fpga.mit.edu/6205/F25/documentation/waveform_viewers)
- [Autodesk: future of EAGLE](https://www.autodesk.com/products/fusion-360/blog/future-of-autodesk-eagle-fusion-360-electronics/), [Hackster: end of EAGLE](https://hackster.io/news/autodesk-announces-the-end-of-eagle-707864d95d7e)

Demand evidence (forum threads, V via search snippet unless noted):
- [McNeel forum: previews missing on Sequoia](https://discourse.mcneel.com/t/previews-still-missing-in-apple-sequoia-jan-15-2025/197869) (V, opened)
- [Eclectic Light: how Sequoia changed Quick Look](https://eclecticlight.co/2024/10/31/how-sequoia-has-changed-quicklook-and-its-thumbnails/)
- [KiCad forum: PCB layout preview](https://forum.kicad.info/t/pcb-layout-preview-without-opening-kicad/1311), [PCB or schematic preview](https://forum.kicad.info/t/pcb-or-schematic-preview/19878), [SparkFun: Viewee](https://community.sparkfun.com/t/quicklook-plugin-to-view-pcb-layouts-for-eagle-and-kicad/31498)
- [Prusa forum: errors and warnings](https://forum.prusa3d.com/forum/prusaslicer/details-on-erros-and-warnings), [gcode thumbnails](https://forum.prusa3d.com/forum/hardware-firmware-and-software-help/how-to-view-gcode-thumbnails-on-pc/), [Prusa help: thumbnails](https://help.prusa3d.com/article/model-preview_648687)
- [imageonline.io STL viewer](https://imageonline.io/stl-viewer/), [GrabCAD question](https://workbench.grabcad.com/questions/is-there-a-way-to-find-the-grams-and-dimensions-for-an-stl-file)
- [Autodesk forum: DWG viewer for Mac](https://forums.autodesk.com/t5/autocad-for-mac-forum/dwg-viewer-for-mac-os/m-p/8989821), [3DS community: DWG preview on macOS](https://3dswym.3dexperience.3ds.com/question/draftsight-user-community/preview-drawing-on-open-in-mac-os_4944)
- [Printago: 3MF structure](https://printago.io/blog/3mf-file-format), [LightBurn forum: LBRN2 documentation](https://forum.lightburnsoftware.com/t/lbrn2-file-documentation/52174/3), [Embrilliance Thumbnailer](https://embrilliance.com/thumbnailer)
