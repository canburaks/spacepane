# New file types and features after the STEP and IGES cut

Researched 2026-10-13 (Europe/Istanbul). This is the lead's synthesis of eleven research reports and two verification reports in [expansion-research/](expansion-research/). It builds on [the competitor landscape](2026-10-05-competitor-landscape.md) and [the unique-feature research](2026-10-05-unique-feature-opportunities.md).

**Why:** version 1.0 ships without STEP and IGES ([decision 028](../decisions/028-no-cad-in-version-1.md)), which were the headline differentiator. The owner asked for file types and features that competing Quick Look apps do not offer.

**Status of everything below:** proposals. None is a plan commitment until it goes through `PLAN.md` and a decision record. Competitor features are vendor claims, not tested. Nothing here was observed in Finder.

## The answer in short

1. **Adding formats no longer differentiates on its own.** An adversarial check of 87 candidates found a current Quick Look tool for 21 and an adjacent one for 18 more. Most are small open-source extensions, several pushed in the last ten days, or extensions bundled with the format's own app. More than a dozen claims of "no Quick Look app does this" in the research reports were wrong.
2. **What stayed open is an answer, not a format:** "what will this file do if I run, install or trust it?" Nobody found gives that answer for scripts, auto-run project configuration, agent bundles, packages, extensions or AI model files. SpacePane already ships the machinery for it (typed findings, the Safety Lens) and already parses the containers these files use.
3. **Recommendation:**
   - Lead with one story: **the Quick Look that tells you what a file will do.** It covers candidates A1 to A5 and A7 below, and it absorbs the "Quick Look for the AI era" idea.
   - Ship **Mesh Print Check** (A6) for the makers who lost STEP. It works on four types already in the catalog and needs no dependency.
   - Treat everything else as breadth. Add the open items in tier B by demand, and add tier C only for parity.
4. **No licence-clean route to shaded STEP is ready.** The three permissive Rust options are unfinished or stale. A text-level STEP and IGES inspector is possible without a kernel, and would be a new owner decision.

## Method and limits

- **Research:** nine angles, one report each: science and geo data, engineering and makers, creative media, developer and AI artifacts, insight and platform features, the trust lens, office and business documents, hobby and personal files, and mined demand signals. Two further reports digest the repository's earlier research and refresh the competitor facts.
- **Verification:** two independent passes. One tried to refute 69 load-bearing facts against primary sources (52 confirmed, 8 partly, 3 refuted, 6 not verifiable). The other tried to find a competitor behind every "none found" claim.
- **No App Store-wide scan.** Apple's iTunes Search API returned HTTP 403 to this Mac from about 20:52, because several agents queried it at once. The 2026-10-05 research scanned 151 store descriptions; this round could not repeat that. The queries to re-run are listed in [the competitor refresh](expansion-research/2026-10-13-competitor-refresh.md).
- **"Open" is weak evidence.** It means web search, GitHub search and App Store product pages found nothing. No open row is rated above medium confidence, and one GitHub query missed a project that a second query found.
- **Nothing was observed in Finder.** `qlmanage` failed or timed out for the agents. "macOS native today" means which provider declares the type on the development Mac (macOS 27.2), not what Finder shows.
- **Audience figures are platform sizes**, such as Chess.com members or Minecraft copies sold. None is a count of Mac users who keep these files. VS Code install counts measure developer popularity, not Mac demand.
- **Two agents read local files outside the repository, read-only,** to check format facts: the trailers of 12 disk images in Downloads, and one local agent session transcript. Nothing was modified.

Effort: S ≈ days, M ≈ 1 to 2 weeks, L ≈ several weeks, per item, including localization and fixtures. Uniqueness verdicts are from [the uniqueness verification](expansion-research/2026-10-13-verification-uniqueness.md): **Open** (nothing found), **Partial** (something adjacent exists), **Taken** (a current macOS 15+ Quick Look tool claims it), **Legacy only** (dead `.qlgenerator` tools).

## Tier A: lead with

Open after the adversarial check, cheap because the parser already exists, and an extension of the shipped Safety Lens.

| # | Candidate | What the user gets | Uniqueness | Evidence of need | Effort |
|---|---|---|---|---|---|
| A1 | **Script effects lens**: `.sh .bash .zsh .command .tool .applescript .ps1 .bat` | Findings such as "downloads and runs a file", "decodes and runs hidden text", "removes the quarantine mark", "asks for your password", "installs a login item" | Open (medium). Every app found only highlights scripts | ClickFix lures using `base64 -D \| zsh` (Objective-See, February 2026) and a Script Editor lure (Malwarebytes, April 2026), both confirmed | S to M |
| A2 | **Auto-run configuration lens**: `.vscode/tasks.json`, Claude Code settings and hooks, `mcp.json`, `.cursor/mcp.json`, `devcontainer.json`, `package.json` scripts | "Opening this folder runs these commands", which servers start, which environment keys they receive, which URLs they fetch | Open (medium). Adjacent: quicklooker lists `package.json` scripts and compose services without saying what they do | DPRK "Contagious Interview" repositories with `runOn: folderOpen`; Cursor CurXecute and MCPoison; all confirmed | S to M |
| A3 | **Bundle and extension cards**: `.mcpb`, `.dxt`, `.vsix`, `.xpi`, `.crx`, `.skill` | Declared tools, commands that run, permissions and host access in plain language | `.mcpb`, `.dxt`, `.vsix`, `.xpi`: Open (medium). `.crx`: Legacy only. `.skill`: Partial, Looq lists it (low confidence) | GlassWorm in VS Code and OpenVSX; the `postmark-mcp` theft; Snyk's ToxicSkills study; all confirmed | M |
| A4 | **Install-time package lens**: npm `.tgz`, Python wheels and sdists | What the package tries to run on install: lifecycle scripts, `binding.gyp`, `.pth` files, bundled binaries | Open (medium). Listing exists everywhere; nobody reads the hooks | Shai-Hulud (CISA), Phantom Gyp (June 2026), the LiteLLM `.pth` incident; all confirmed | M |
| A5 | **AI model files**: `.gguf`, `.safetensors`; pickle and PyTorch `.pt .pth .ckpt`; later `.onnx`, `.keras` | Architecture, parameter count, quantisation, context length, chat template, licence tag and a "download incomplete" check from the header alone. For pickles, an inventory of what loading would import, never an "all clear" | GGUF, safetensors, pickle: Open (medium). ONNX, Keras, Core ML: Open (low) | nullifAI: malicious PyTorch models that evaded picklescan (ReversingLabs, February 2025), confirmed. VS Code viewers for pickle and HDF5 have tens of thousands of installs | M each |
| A6 | **Mesh Print Check** on the existing STL, OBJ, PLY and 3MF | Weight, filament and cost from volume; bed fit; open and non-manifold edges; flipped faces; a unit guess | Open (medium). The two dedicated maker apps list none of it. Slicer facts read from 3MF are Partial (MakersPreview, MakerLook) | Serves the audience the STEP cut left behind. The earlier UX research recorded that competitors' 3D previews show no units | S to M |
| A7 | **Credential-export guard**: `.1pux`, Bitwarden JSON, password CSVs, one-time-code backups | A file-level finding such as "312 logins in readable form", counts only | Open (medium). Only converters exist | 1Password and Bitwarden both tell users to delete such exports | S |

Notes on tier A:

- **A1 wording.** macOS 26.4 warns when commands are pasted into Terminal, and Malwarebytes says it warns about the Script Editor lure too. Do not claim that any route bypasses the system warning. The lens covers script files, which the paste warning does not.
- **A4 framing.** npm 12 (general availability 2026-07-08, confirmed) disables dependency install scripts and implicit `node-gyp` builds by default. Phantom Gyp used a 157-byte `binding.gyp` and no lifecycle script. So the useful question is "what does this artifact try to run", not "what will my install run".
- **A5 risks.** Model files are often several gigabytes, so the reader must touch the header only. Reading a header from an iCloud placeholder file may trigger a full download (not verified). macOS types `.pkl` as Apple's Pkl configuration language, so pickle files need content sniffing. LGPL fickling stays excluded; the opcode walker is our own.
- **A6 routing.** Apple's own extensions declare STL, OBJ and PLY on macOS 27.2. Whether Finder sends those types to SpacePane there needs a signed-build observation. This affects three types that already ship.

## Tier B: add next

Open or partly open, but larger, more contested, or waiting on a design question.

| # | Candidate | Uniqueness | Evidence of need | Effort | Open question |
|---|---|---|---|---|---|
| B1 | **Dialect lenses on formats we already parse**: GitHub Actions job graph and findings; OpenAPI endpoint table; SARIF summary; Kubernetes; docker-compose graph; launchd plists in plain language; HAR waterfall with a share check; JSON shape with copy as TypeScript or Swift; log timeline | Actions, OpenAPI, Kubernetes, launchd: Open (medium). Compose: Partial (quicklooker shows a table). HAR, JSON shape, logs: Partial | VS Code viewers: OpenAPI 1.04M installs, SARIF 0.6M. Okta 2023: HAR files leaked session tokens (confirmed) | S to M each | Needs the dialect concept below |
| B2 | **Developer binaries**: Mach-O libraries (`.dylib .o .a`, `.dSYM`), `.wasm`, `.ips` crash reports, container image tarballs, `.pcap` | Open (medium) for each. Source maps: Partial | VS Code Hex Editor has 7.4M installs. A structured header inspector is the form of "hex view" that fits the earlier rejection of hex dumps | S to M each; `.pcap` L | The `.app` adapter already reads Mach-O headers |
| B3 | **E-invoice reader**: EN 16931 UBL and CII (XRechnung, Peppol, Factur-X XML), FatturaPA, Turkish UBL-TR, KSeF, Facturae; with signed containers `.p7m .p7s`, ASiC | Contested. The Eutopix viewer (free with in-app purchases, first released in August) mentions "Finder Quick Look" in a release note. `.p7m` and ASiC: Open (low; thin search) | Mandates confirmed: Germany must receive since 2025-01-01, France reception from 2026-09-01, Belgium from 2026-01-01, Poland from 2026-02-01 and 2026-04-01. Turkish thresholds not verified | M, then S per dialect | Routing by content inside `.xml`; findings with amounts |
| B4 | **Honest EPS and PostScript**: embedded preview image, document comments and source; never interpret the program | Contested. One paid app exists; Peek lists PostScript but is stale | The strongest demand signal found: a Hacker News thread on PostScript's removal drew 269 points; six store reviews of Peek and iPreview say EPS fails | S to M | How many real EPS files carry an embedded preview is untested |
| B5 | **Design files without the authoring app**: `.kra .ora`, `.procreate`, `.fig`, `.sketch`, `.xd`, `.xmind` | `.fig`: Open. Krita: Partial (the vendor plug-in is reported broken on macOS 15). `.procreate`: Partial (low). `.sketch`, `.xd`: not verified. Affinity: Taken by the vendor | Requested on Windows (PowerToys issue with 22 reactions; QL-Win plug-ins exist). No general Mac app lists them | M | May thumbnails show the embedded picture? See decisions |
| B6 | **Colour palettes and design tokens**: `.aco .gpl .clr .sketchpalette`, `.tokens`; `.ase` | Open (medium). `.ase`: Legacy only | None of the general competitors claims palettes. Demand not measured | S to M | Vendor apps may declare `.ase` and `.aco` and win routing |
| B7 | **STEP and IGES text-level inspector**: schema, originating system, assembly tree, entity census, units; not shaded | STEP facts: Partial (3D previews exist at Unfold, Universal 3D Previewer and others; none shows these facts). IGES: Open (low; one store listing was not opened) | STEP is still requested: PowerToys issue, three iPreview reviews, an open-source project with 104 stars | M | New owner decision; 028 covers the Open CASCADE route only |
| B8 | **Genomics headers**: FASTA, FASTQ, SAM, BAM header, GFF, BED; Newick trees | Open (medium) | No Mac request found. Much of this data lives on clusters | M | Demand |
| B9 | **Personal exports**: WhatsApp and Telegram chats as a conversation; Apple Health and streaming-history summaries; GEDCOM family trees; Anki decks; Scratch projects | Open (medium to low) | Platform sizes only | M each | A conversation presentation is new |
| B10 | **Bank statements**: camt.052/053, MT940, OFX | Open (medium). QFX and QIF: Legacy only | Not measured | M | Findings with amounts |
| B11 | **Reference files**: `.ris .nbib .enw` | Open (medium) | Every academic uses them; not measured | S | None |
| B12 | **Hardware text formats**: VCD waveforms, Intel HEX, UF2, Eagle XML | Open (medium) | VS Code WaveTrace has 97K installs | S to M each | Needs a 2D plot primitive |
| B13 | **Post-production text formats**: `.otio`, `.fcpxml`; captions SCC and EBU STL; Aseprite pixel art | Open (medium). EDL: Taken (open source). iTT: Partial | Not measured. Aseprite's own preview is reported broken; the fix is incomplete for at least one user | S to M each | Aseprite's format document states no licence |
| B14 | **Privacy findings for medical headers**: DICOM, EDF | Viewing DICOM is Taken. A "contains patient name and birth date" finding is Open (medium) | Not measured | M | macOS already thumbnails simple DICOM images |

## Tier C: parity only

A current Quick Look tool already claims these. They can still be worth adding for breadth, because most of the tools below are open-source projects that a user must find and build, or need macOS 26. They cannot carry a "no other Quick Look app" claim.

| Candidate | Who has it (vendor claims) |
|---|---|
| HDF5 and NetCDF | [ndLook](https://github.com/abkfenris/gridded-quicklook) (BSD-3, build from source), [HDF5QL](https://github.com/hacknus/HDF5QL) |
| KiCad boards and schematics | [KiCadQuickLook](https://github.com/Architeuthis-Flux/KiCadQuickLook); [PCBAtlas](https://apps.apple.com/us/app/pcbatlas/id6759897822) partly |
| IFC building models | [IFC Quick Look](https://github.com/cioxideru/ifc-quicklook-macos), [ifc-quicklook](https://github.com/trapple/ifc-quicklook) |
| Molecular structures | [Burette](https://github.com/SergeiNikolenko/Burette), [QuickLookProtein](https://github.com/JethroHemmann/QuickLookProtein) |
| PMTiles, FlatGeobuf, GeoParquet, DWG and DXF as map layers | [GeoPreview](https://apps.apple.com/us/app/geopreview/id6758587360), $34.99 |
| LUTs | [LUT Preview](https://apps.apple.com/app/id6759214495) (Anybox), $4.99 |
| Outlook `.msg`; `winmail.dat` | [QuickMSG](https://github.com/rs2pt/QuickMSG); Letter Opener |
| XLIFF; gettext `.po` | [xlfql](https://github.com/capybara-translation/xlfql); Poedit 3.5.1's own extension |
| Configuration profiles `.mobileconfig` | [Pique](https://github.com/macadmins/pique) (macOS 26+), [Looq](https://apps.apple.com/app/id6760281430) |
| Chess `.pgn`; Go `.sgf` | [Manifest Chess Lite](https://apps.apple.com/us/app/manifest-chess-lite-pgn-reader/id6809753832), $17 (whether it draws a board is unclear); [SGF Tools](https://github.com/imabuddha/SGF-Tools) (macOS 26+) |
| Minecraft schematics | [LitematicaQL](https://github.com/Arcadi4/LitematicaQL) (AGPL) |
| Edit decision lists | [edl-quicklook](https://github.com/claude-coder-collab/edl-quicklook) |
| DICOM and neuroimaging | [DicomPreview](https://github.com/neuralink/DicomPreview), [MIQ](https://github.com/marcoduering/MIQ), two paid apps in the landscape |
| SolidWorks, Rhino, FreeCAD, SketchUp thumbnails | Universal 3D Previewer 3.1; the vendors' own apps; [FreeCADCompanion](https://github.com/graelo/FreeCADCompanion) |
| MuseScore; Affinity | Built into MuseScore Studio 4.7; Affinity 2.5.6 |
| G-code toolpaths, DXF drawings, slicer 3MF, glTF, embroidery, statistics files | Several apps each; see the engineering, creative, hobby and science reports |

Two candidates the research ranked highly shrink as a result:

- **"CAD Cover"** (embedded preview images from proprietary CAD files) is left with Inventor, Solid Edge, Revit and Fusion, all Open at low confidence. Its technical basis is one repository created in July 2026. No established documentation of the preview locations was opened, no sample file was tested, and no vendor terms were read.
- **The localisation lens** is left with `.mo`, TMX, `.xcloc`, `.arb` and `.resx` (Open, low to medium). Its progress and placeholder-mismatch findings remain undone by anyone found.

## Ruled out

| Item | Reason |
|---|---|
| Shaded STEP on a permissive kernel | `truck-stepio` documents input as still to come; `ruststep` says "DO NOT USE FOR PRODUCT"; `foxtrot`'s last commit is from 2021. All confirmed |
| Full PostScript rendering; DWG geometry; music engraving with Verovio; `libbgcode`; `fickling` | Ghostscript and `libbgcode` are AGPL; LibreDWG is GPL; Verovio and `fickling` are LGPL |
| Rhino `.3dm` through openNURBS | Not MIT as first reported. The licence file as read gives no clear grant for openNURBS itself |
| Garmin `.fit` | Reported as a proprietary licence with redistribution limits. The terms were not verified; out until someone reads them |
| Spotlight metadata | Apple's page still says Spotlight import extensions "don't provide functionality in macOS" (confirmed) |
| Finder risk badges; name and entity detection as privacy findings | A different extension type; the on-device name tagger works for English and Turkish only (measured on this Mac) |
| `.ts`, GeoTIFF, genomic `.vcf`, texture formats, OFD | The system owns the type: MPEG transport stream, `public.tiff`, vCard, ImageIO, and Apple's own OFD extensions on macOS 27.2 |
| Ableton `.als`, PSB | Specialist Quick Look apps exist |
| XPS, PST, Project, Publisher, OneNote, WordPerfect | Unworkable natively or off-licence |

## What the demand evidence says

From [the demand report](expansion-research/2026-10-13-demand-signals.md), which mined requests and reviews and did not brainstorm:

- **Requested and feasible:** EPS; design containers; a hex or binary-header view; OpenAPI and SARIF; HDF5 and NetCDF; VCD waveforms; `.msg` and `winmail.dat`; DXF and G-code. STEP is still requested.
- **Requested and impossible here:** TypeScript `.ts` (about a dozen reviews), camera RAW, MKV and WebM, Office and PDF, a user-defined suffix list for plain text.
- **Features asked for most:** selectable and copyable text; reliable light and dark switching; fewer extensions with visible provider conflicts; find in the preview; previewing an entry inside an archive.
- **Loudest complaints about rivals:** plug-ins abandoned after macOS updates (Peek has had no update since 2022); support lists that overpromise (about 12 iPreview reviews); trust, price and nag friction. A maintained, sandboxed app with no network access answers all three.

## Engineering findings that cut across candidates

1. **A dialect concept is needed.** Most of tiers A and B recognise a meaning inside a container we already parse (`.json`, `.yaml`, `.xml`, `.plist`, ZIP, TAR). The catalog has no way to express a content-detected sub-type, and the per-type switches have no rule for one. `PreviewNameHint` carries the file name and suffix only, so `.vscode/tasks.json` cannot be told from any other `tasks.json` without structural detection.
2. **Findings may need typed values.** [Decision 012](../decisions/012-safety-findings.md) keeps source values out of findings. "Line totals do not add up" and "this shortcut goes to host X" need a typed detail. Decision 017's scheme, host and port rule is the precedent.
3. **The mesh renderer draws triangles only.** Toolpaths, wireframes, waveforms and stitch plots would need a line or point primitive. This is the engineering agent's reading of decision 024, not something checked in code.
4. **Routing traps.** Besides STL, OBJ and PLY: `.xml` is shared with Apple's text provider; `.pkl`, `.mm`, `.exp` and `.abc` collide with system or developer types; types that live inside `.txt`, `.csv` or `.json` cannot be routed by suffix.
5. **Large files.** Header-only reads for model files; head and tail reads for G-code, whose statistics sit at the end.
6. **Platform.** The macOS 27 SDK adds no Quick Look API since macOS 12 (read from the SDK). Foundation Models documents a 4,096-token context. Whether Foundation Models, Translation or Vision run inside the sandboxed preview extension is untested; each needs a spike.
7. **Two new finding kinds were proposed** by more than one report: integrity ("this file looks truncated") and personal data.

## Decisions for the owner

1. **Which story leads:** "what will this file do" (recommended), a maker story built on Mesh Print Check and a STEP inspector, or breadth.
2. **A STEP and IGES text-level inspector.** It restores the two suffixes without Open CASCADE and without 3D. Decision 028 does not cover it.
3. **Thumbnails that show an embedded picture** for design files. [Decision 022](../decisions/022-content-thumbnails.md) keeps thumbnails free of content.
4. **Typed values in findings**, as in point 2 above.
5. **Legal reads before any work:** Microsoft's patent promises for the Outlook message, TNEF and Visio specifications (only MS-CFB was found on the Open Specifications Promise list); Aseprite's format document, which states no licence; the Garmin FIT terms.
6. **The request said "GIS file preview" was removed.** The catalog still has GeoJSON, GPX and KML, and decision 028 removed STEP and IGES only. This research assumed IGES (`.igs`) was meant.

## Corrections to earlier documents

Not edited in this round:

- **The competitor landscape** lacks about twenty tools found here, among them Looq, GeoPreview, LUT Preview, Pique and quicklooker; see the list in [the uniqueness verification](expansion-research/2026-10-13-verification-uniqueness.md). LookQuick is at 4.0 (2026-10-07). Universal 3D Previewer 3.1 claims interactive SolidWorks previews. Unfold's changelog lists 3.2.0 with STEP and 3MF while the store still serves 3.0.2.
- **Its statement that no app previews IGES** still holds, at low confidence.
- **The App Store listing research** assumes STEP and IGES ship. **Decision 010** names PDF, DOCX and PSD as catalog types.
- **The competitor refresh's list of "claims SpacePane lacks"** ranks thumbnails, math, contents and copy first. SpacePane has all four. That agent was given the list of file types only, so its feature rows are not gaps.

## Not established

- Any Finder behaviour, on any macOS version.
- An App Store-wide scan of descriptions for any candidate.
- Mac demand for any candidate beyond the request counts cited.
- The Turkish e-Fatura thresholds; whether Apparency ships a Quick Look extension; the Garmin FIT and Hancom HWP terms; Apple's Translation language list; Autodesk's Eagle end date.
- Two counts that passed through a page summariser (HDF5 entries in Debian's security tracker, one download figure) are left out of this document.

## Reports

| Report | Scope |
|---|---|
| [Science and geo data](expansion-research/2026-10-13-science-data.md) | HDF5, genomics, molecules, statistics files, medical headers, geo containers |
| [Engineering and makers](expansion-research/2026-10-13-engineering-maker.md) | Routes back to CAD value, mesh checks, electronics, G-code |
| [Creative media](expansion-research/2026-10-13-creative-media.md) | Colour, design files, timelines, audio, 3D and game assets |
| [Developer and AI artifacts](expansion-research/2026-10-13-developer-ai-artifacts.md) | Model files, pickles, transcripts, binaries, captures |
| [Insight and platform features](expansion-research/2026-10-13-insight-and-platform-features.md) | Dialect lenses, insight layers, what Apple's frameworks allow |
| [Trust lens](expansion-research/2026-10-13-trust-lens.md) | Scripts, auto-run configuration, bundles, packages, profiles |
| [Office and business documents](expansion-research/2026-10-13-office-business-documents.md) | E-invoices, signatures, mail, localisation, bank files |
| [Hobby and personal files](expansion-research/2026-10-13-hobby-personal.md) | Games, education, crafts, personal-data exports |
| [Demand signals](expansion-research/2026-10-13-demand-signals.md) | Requests, reviews and install counts |
| [Digest of existing research](expansion-research/2026-10-13-existing-research-digest.md) | Gaps, deferred ideas and rejections already on record |
| [Competitor refresh](expansion-research/2026-10-13-competitor-refresh.md) | Version and price changes since 2026-10-05; partial run |
| [Verification: facts](expansion-research/2026-10-13-verification-facts.md) | 69 claims checked against primary sources |
| [Verification: uniqueness](expansion-research/2026-10-13-verification-uniqueness.md) | 87 candidates checked for existing Quick Look tools |

The domain reports were written before verification and are not corrected. Where a report and a verification file disagree, the verification file is right.
