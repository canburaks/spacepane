# Verification: are the proposed Quick Look previews really unclaimed?

Checked 2026-10-13 (Europe/Istanbul)

An adversarial pass over the "no Quick Look app found" claims in the eight expansion reports. Everything below about a competitor is a vendor claim (store listing, README, release notes, forum post) unless the row says otherwise. Nothing was installed or run, so no row says that a preview works on a real Finder.

## Method and limits

What worked:

- **GitHub REST search (`api.github.com/search/repositories`) through WebFetch.** It answered, which the earlier agents' fetches did not. It is the main source of the open-source finds.
- **WebSearch limited to `github.com`, `apps.apple.com` and `producthunt.com`.** This found most of the rest.
- **Direct `apps.apple.com` product pages and the `apps.apple.com/us/mac/search?term=` page.** The search page returns app names only, ranked loosely, so it gave leads but no proof.
- **Unfold's changelog and extension list, QuickLook Pro's home page, LookQuick's two pages, Super Quick Look's listing, Looq's listing and Setapp page, Universal 3D Previewer, MakersPreview, GeoPreview, LUT Preview, PCBAtlas, eInvoice Viewer.**
- **Vendor trackers:** McNeel's forum (Rhino), SketchUp's forum, Krita's forum, the MuseScore and Aseprite issues, and Poedit's NEWS.
- **`Oil3/List-of-modern-Quick-Look-extensions`**, which lists about 45 appex-based extensions. It names FreeCADCompanion, DicomPreview, DotTHzQL, QuickLookProtein, preview-scad and musescore-quicklook, which I then checked.

What did not work or is weak:

- **Reddit is blocked for WebSearch.** r/macapps was not searched. MacUpdate and Homebrew casks were not searched directly. Product Hunt was reached only through search results.
- **GitHub search gives false negatives.** A query such as `quick look macos gerber` returned 0 although KiCadQuickLook exists, because its description does not use those words. Every "0 repositories" below is a weak negative. For that reason no OPEN row is marked high confidence.
- **WebFetch answers come from a small summarising model.** Dates on App Store pages often lack the year (copyright 2026 on all of them). GitHub "Releases" panels came back empty even for projects that ship zips, so I do not give release dates for those.
- **Not found or not checked:** "Peeka", "Stats File Viewer" and "GIS Quick Viewer" returned nothing in my searches. The science agent reports Stats File Viewer (SAS/Stata/SPSS/R, free) and GIS Quick Viewer ($5.99, 2026-10-02); I did not verify either. Netron, LM Studio, Ollama and Hugging Face were searched together once with no Quick Look hit. Apparency and Suspicious Package were not re-checked. Eyemesh, QuickestLook and Syntax Highlight were not re-opened; the 2026-10-05 baseline stands for them. iTunes Search was not used.

**What a verdict means.** TAKEN means a macOS 15+ Quick Look preview or thumbnail provider claims the format. Open-source projects that you build or download from GitHub count as TAKEN and are marked "OSS". PARTIAL means something adjacent exists. LEGACY ONLY means only a pre-macOS-15 `.qlgenerator` was found. OPEN means nothing was found.

## Verdict table

| # | Candidate | Verdict | Evidence | Confidence |
|---|---|---|---|---|
| 1 | Shell/AppleScript/PowerShell scripts with an "effects" analysis (download-and-run, decode-and-run, quarantine removal, persistence) | OPEN. Every general app only highlights scripts: [Unfold's list](https://unfold.tools) (sh, bash, zsh, ps1, applescript), [Super Quick Look](https://apps.apple.com/us/app/super-quick-look/id6783296336), [Pique](https://github.com/macadmins/pique), [Looq](https://apps.apple.com/app/id6760281430) (language detection by shebang). Queries: web "Quick Look shell script curl sh dangerous"; github+apple "Quick Look" script analysis | Searches above; no analysing preview in any format list | medium |
| 2a | Explain `.vscode/tasks.json` auto-run tasks, Claude Code hooks/settings, `mcp.json`, dev containers | OPEN. Queries: github+apple "Quick Look" mcp.json / tasks.json / devcontainer; Unfold lists `.code-workspace` as plain text only | [search result set](https://github.com/Oil3/List-of-modern-Quick-Look-extensions) (no entry) | medium |
| 2b | (adjacent) `package.json` scripts and `docker-compose` services shown as tables | PARTIAL. [QuickLook Pro](https://quicklookpro.com) claims a `package.json` overview. [quicklooker](https://github.com/fosron/quicklooker) (OSS, build from source) lists package.json scripts and dependencies, and compose services, ports, volumes, masked env, networks. Neither says what the commands do | quicklooker README; QuickLook Pro home page | medium |
| 3a | `.skill` agent bundles | PARTIAL. Looq's version history lists `.skill` previews (vendor claim); the description does not say what it shows | [Looq listing](https://apps.apple.com/app/id6760281430) | low |
| 3b | `.mcpb`, `.dxt`, Claude plugin bundles | OPEN. Only packaging docs found; the formats are ZIPs but no app declares them | web search "Quick Look .mcpb .dxt" | medium |
| 4 | Package archives with install-time behaviour: npm `.tgz`, `.whl`/sdist, `.gem`, `.crate`, `.nupkg`, `.deb`/`.rpm` (beyond listing an archive) | OPEN for inspection. Listing exists everywhere: [Unfold](https://unfold.tools) (tgz, tar.gz), quicklooker (tgz, jar manifest and Java version), Super Quick Look. No app reads scripts, hooks or metadata inside these. Queries: github+apple "Quick Look" vsix/whl/gem/nupkg/deb; GitHub API `quick look macos vsix` = 0 | search sets | medium |
| 5a | Chrome `.crx` permission card | LEGACY ONLY. [ChromeExtensionQuickLookPlugIn](https://github.com/nesty/ChromeExtensionQuickLookPlugIn), 2012 generator | repo | medium |
| 5b | VS Code `.vsix`, Firefox `.xpi` permission cards | OPEN. GitHub API `quick look macos vsix` = 0; web search nothing | searches | medium |
| 6a | `.mobileconfig` profile explained | TAKEN. [Pique](https://github.com/macadmins/pique): MacAdmins, Apache-2.0, free pkg, macOS 26+, shows profile metadata and payload details (vendor claim). Also Looq lists "configuration profiles" ([Setapp](https://setapp.com/pt-br/apps/looq)), and Unfold highlights `.mobileconfig` as code. Nobody claims plain-language risk wording | Pique README | high for existence; medium that nobody does plain-language wording |
| 6b | launchd LaunchAgent/LaunchDaemon plist in plain language | OPEN. Pique's list has no launchd; QuickestLook/Unfold show plists as trees or XML; LaunchdUI is a standalone app | [Pique](https://github.com/macadmins/pique) | medium |
| 6c | `.webloc`/`.inetloc`/`.url` destination shown | OPEN. No extension found; Apple's own behaviour was not tested (`qlmanage` crashed for the trust agent) | web search | low |
| 7 | Password-manager exports (`.1pux`, Bitwarden JSON, password CSVs) with a count warning | OPEN. Only converters ([pux-to-html](https://github.com/OzzyCzech/pux-to-html), [1PasswordExporter](https://github.com/rsgill1978/1PasswordExporter)); [gitleaks #1525](https://github.com/gitleaks/gitleaks/issues/1525) shows demand for detection, not a Quick Look | searches | medium |
| 8a | GGUF, safetensors header/metadata | OPEN. GitHub API `quicklook gguf` and `quicklook safetensors` = 0; App Store term "gguf" = chat apps only; web: only CLI/MCP inspectors ([safetensors_explorer](https://github.com/EricLBuehler/safetensors_explorer), gguf-mcp) | searches | medium |
| 8b | ONNX, `.keras`, Core ML (`.mlmodel`/`.mlpackage`) | OPEN. Nothing found; Netron, LM Studio, Ollama and Hugging Face apps show no Quick Look extension in one combined search. Apple/Xcode behaviour for `.mlmodel` not tested | search | low |
| 9 | Pickle / PyTorch `.pt/.pth/.ckpt` import or safety scan | OPEN. GitHub API `quick look macos pickle` = 0; web nothing | searches | medium |
| 10a | Claude Code / Codex session `.jsonl` as a conversation | PARTIAL. JSONL as records, not a conversation: [QuickLook Pro](https://quicklookpro.com), [Unfold](https://unfold.tools), quicklooker, Pique, [y-a-v-a/quicklooks](https://github.com/y-a-v-a/quicklooks) (OSS), OK JSON (jsonl QL since 2.6.2). The baseline notes QLook JSON markets "JSONL for AI-agent logs" | listings | medium |
| 10b | ChatGPT/Claude `conversations.json` | OPEN. Only web and CLI viewers ([ChatGPT-Export-Viewer](https://github.com/Notesong/ChatGPT-Export-Viewer---Enhanced), [chatgpt-export-tools](https://github.com/selberhad/chatgpt-export-viewer)) | web search | medium |
| 11a | Mach-O / dylib / static library / `.dSYM` inspector | OPEN. [LookQuick](https://inspirationull.com/lookquick.html) falls back to a hex or strings analysis for unknown files (baseline claim), and several apps inspect `.app` bundles ([Unfold](https://unfold.tools/changelog) 2.3.0). No raw Mach-O inspector found. github+apple, web "Quick Look Mach-O" = nothing | searches | medium |
| 11b | WebAssembly `.wasm` | OPEN. Unfold lists `.wat` text only; GitHub API `quick look macos wasm` = 0 | [Unfold list](https://unfold.tools) | medium |
| 11c | JavaScript source maps | PARTIAL. [JSON Loupe](https://jsonloupe.weinmayr.co/) lists `.map` as JSON (baseline). Not source-map aware | baseline | medium |
| 11d | `.ips` / `.crash` crash reports | OPEN. Super Quick Look lists "logs" but no crash reports; nothing else found | [Super Quick Look](https://apps.apple.com/us/app/super-quick-look/id6783296336) | medium |
| 11e | `.pcap` / `.pcapng` | OPEN. GitHub API `quick look macos pcap` = 0; web nothing | searches | medium |
| 11f | Docker/OCI image tarballs | OPEN. GitHub API `quick look macos docker image` = 0; tar listing only | searches | medium |
| 12a | GitHub Actions workflow graph or findings | OPEN for graph/findings. [ql-yaml](https://github.com/2b3pro/ql-yaml) (OSS) folds YAML and mentions workflows; no graph | README | medium |
| 12b | docker-compose / Kubernetes graph | PARTIAL for compose: quicklooker shows a services table, not a graph. Kubernetes: OPEN | [quicklooker](https://github.com/fosron/quicklooker) | medium |
| 12c | OpenAPI endpoint table | OPEN. Only generic JSON/YAML previewers | web search | medium |
| 12d | HAR waterfall | PARTIAL. HAR opens as JSON in [JSON Loupe](https://jsonloupe.weinmayr.co/) and is on LookQuick's unusual-types list (baseline). No waterfall | baseline | medium |
| 12e | JSON shape/schema inference, copy as TypeScript | PARTIAL. Super Quick Look gives a "structured summary" for JSON; JSON Loupe Pro copies key paths. No TypeScript output claimed | [listing](https://apps.apple.com/us/app/super-quick-look/id6783296336) | low |
| 12f | Log timeline / histogram | PARTIAL. QuickestLook (timestamps, severity colours, stack traces, baseline) and quicklooker (last 1 MB, levels counted) read logs; no timeline or histogram | quicklooker README | medium |
| 13a | Mesh print analysis for raw STL/OBJ: volume to weight/filament/cost, non-manifold/open edges, bed fit | OPEN. [Universal 3D Previewer](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617) and [MakersPreview](https://apps.apple.com/us/app/makerspreview/id6751494785) list no analysis (volume, weight, mesh checks, bed fit all absent from their pages); iPreview has bounding box and wireframe modes only | listings | medium |
| 13b | Slicer facts read from a 3MF (filament colours/use, information card) | PARTIAL. MakersPreview 2.2 shows 3MF "as a clear information card" (contents not described); MakerLook lists filament colours ([Bambu forum post](https://forum.bambulab.com/t/mac-quicklook-extension-for-3mf-files/251993), $5.99 per the poster). OSS 3MF thumbnail extensions also exist ([Preview3MF](https://github.com/tborovatz/Preview3MF), [threemf](https://github.com/guanchzhou/threemf)) | listings | medium |
| 14a | SolidWorks `.sldprt/.sldasm` | TAKEN. Universal 3D Previewer: free, Bryan Joseph, macOS 14.6+, v3.1 (Aug 5, 2026 per page); v3.1 notes say SOLIDWORKS now previews as interactive 3D. Already in the baseline | [listing](https://apps.apple.com/us/app/universal-3d-previewer/id6764180617) | high |
| 14b | Rhino `.3dm` | TAKEN by the vendor app: McNeel staff said the missing-preview bug RH-84357 was fixed in Rhino 8 SR17 (2025-02-12); a user still reported no thumbnails on 2025-03-12. Needs Rhino installed | [McNeel thread](https://discourse.mcneel.com/t/previews-still-missing-in-apple-sequoia-jan-15-2025/197869) | medium |
| 14c | SketchUp `.skp` | PARTIAL. SketchUp provides Finder thumbnails, but users report they stopped on macOS Tahoe (thread from 2026-06-01); one unnamed paid third-party previewer is mentioned in an older thread | [SketchUp forum](https://forums.sketchup.com/t/sketchup-thumbnails-no-longer-appear-on-macos-tahoe-ipados-and-ios/347354) | medium |
| 14d | AutoCAD `.dwg` (and `.dxf`, `.dgn`) | PARTIAL. [GeoPreview](https://apps.apple.com/us/app/geopreview/id6758587360) ($34.99, macOS 13+, v1.0.11) lists DWG, DXF and DGN among its formats, as geospatial vectors; the page says Space-bar preview. Many standalone DWG viewers exist (names only: Monge, DWG Lab, CAD Viewer Editor) and I did not open them | App Store | medium-low |
| 14e | FreeCAD `.FCStd` | TAKEN (OSS, source only). [FreeCADCompanion](https://github.com/graelo/FreeCADCompanion): macOS 15+, MIT, shows the embedded `Thumbnail.png` only; "intended for integration into FreeCAD" | README | medium |
| 14f | Inventor `.ipt/.iam`, Solid Edge, Revit `.rvt/.rfa`, Fusion `.f3d` | OPEN. Nothing found on GitHub, the App Store or the web. Inventor, Solid Edge and Revit have no Mac vendor app; Autodesk Fusion for Mac was not checked | searches | low |
| 15a | STEP text-level inspection (header, assembly tree, entity counts) | PARTIAL. STEP 3D previews are claimed by Unfold 3.2.0 ([changelog](https://unfold.tools/changelog)), Universal 3D Previewer, StepPreview, and OSS [quick-look-step](https://github.com/johnboiles/quick-look-step), [StepView](https://github.com/harry-finch/StepView), [Quick3DLook](https://github.com/yakitori-daisuki/Quick3DLook). None claims header, assembly tree or entity-count facts | listings | medium |
| 15b | IGES anything | OPEN (unverified lead). Not in Unfold, Universal 3D Previewer or the OSS STEP projects. An App Store result named "STEP File Viewer" has the subtitle "View & Explore STEP/IGES"; I did not open it, so Quick Look status is unknown | [App Store search](https://apps.apple.com/us/mac/search?term=dwg%20quick%20look) | low |
| 15c | IFC (BIM) | TAKEN (OSS). [cioxideru/ifc-quicklook-macos](https://github.com/cioxideru/ifc-quicklook-macos): MIT, 3D view of IFC2x3/4/4x3, macOS 14+, Apple Silicon only, notarised zip on GitHub, pushed 2026-10-09. Earlier: [trapple/ifc-quicklook](https://github.com/trapple/ifc-quicklook), pushed 2026-07-13. Neither shows per-element properties | READMEs | high |
| 16a | KiCad `.kicad_pcb/.kicad_sch` | TAKEN (OSS, details unconfirmed). [KiCadQuickLook](https://github.com/Architeuthis-Flux/KiCadQuickLook): "Finder extension to show previews of KiCad files", Unlicense, 1 commit, README names no file types. [PCBAtlas](https://apps.apple.com/us/app/pcbatlas/id6759897822) (free, Plus $24.99, macOS 14+, v1.2.1) reads KiCad projects; its 1.0.7 notes say "Better Quick Look thumbnails and previews", unclear whether system-level | READMEs, listing | medium |
| 16b | Gerber | PARTIAL. PCBAtlas imports Gerber through "recognized manufacturing packages"; its Quick Look scope is unclear | [listing](https://apps.apple.com/us/app/pcbatlas/id6759897822) | low |
| 16c | Eagle `.brd/.sch`, VCD waveforms, Intel HEX / UF2 | OPEN. github+apple "Quick Look" Eagle/VCD/Intel HEX/UF2 = nothing | search | medium |
| 17 | E-invoices from XML: XRechnung, ZUGFeRD/Factur-X, UBL, FatturaPA, UBL-TR, KSeF, Facturae | OPEN for Quick Look. Adjacent standalone viewers: [eInvoice Viewer](https://apps.apple.com/us/app/-/id6738959264) (Vogelbusch & Co, free + IAP $3.99/month, $22.99/year or $44.99 lifetime, macOS 15, v1.2.1; no Quick Look mentioned) and [Quba](https://github.com/ZUGFeRD/quba-viewer) (free, OSS). FatturaPA, UBL-TR, KSeF and Facturae were searched in English and Italian only | searches | medium for DE/FR formats; low for IT/TR/PL/ES |
| 18 | Signed containers `.p7m`, `.p7s`, ASiC `.asice/.bdoc` | OPEN. One English/Italian web search; only a .NET library found | search | low |
| 19a | Outlook `.msg` | TAKEN. [QuickMSG](https://github.com/rs2pt/QuickMSG) (OSS, MIT, macOS 13+, pushed 2026-10-07): subject, sender, recipients, attachment names, body. [Msg Viewer Pro](https://apps.apple.com/app/id1019539949) ($4.99, v2.6.2, 2024-05-02, macOS 10.13+) claims Quick Look but predates the macOS 15 removal | READMEs, listing | high |
| 19b | `winmail.dat` | TAKEN (vendor claim). Letter Opener's Winmail Viewer (free + IAP, macOS 12+, v17.1.2, Oct 3; [listing](https://apps.apple.com/za/app/winmail-viewer-letter-opener/id411897373)); a search snippet from another listing says Space-bar Quick Look; the fetched page does not mention Quick Look. BetterZip also lists winmail.dat (baseline) | listing | medium |
| 19c | `.mbox` | OPEN. GitHub API `quicklook mbox` = 0. Apple Mail covers `.eml` | search | medium |
| 20a | XLIFF | TAKEN (OSS). [xlfql](https://github.com/capybara-translation/xlfql): MIT, XLIFF 1.2, `.mxliff`, `.sdlxliff` as a source/target/note grid; unsigned; pushed 2026-04-22 | README | high |
| 20b | gettext `.po` / `.pot` | TAKEN by the vendor app: Poedit 3.5.1 "added modern Quick Look preview extension (required on macOS 15)" ([NEWS](https://raw.githubusercontent.com/vslavik/poedit/master/NEWS)). What it shows was not checked, and it needs Poedit installed | NEWS | medium |
| 20c | `.mo`, TMX, `.xcloc`, `.arb`, `.resx` | OPEN. Searches found nothing; Xcode's behaviour for `.xcloc` was not checked | searches | low-medium |
| 21a | camt.053, MT940, OFX | OPEN | web search | medium |
| 21b | QFX / QIF | LEGACY ONLY. A Quicken user says Quick Look once previewed them and no longer does ([thread](https://community.quicken.com/discussion/comment/20278517)) | thread | low |
| 22a | Visio `.vsdx` | OPEN. Only paid standalone viewers (per the office agent) and web previewers | search | medium |
| 22b | Mind maps `.xmind` / `.mm` | OPEN. No current extension found; XMind's own thumbnails not checked | search | low |
| 22c | EPS / PostScript facts | PARTIAL. Peek lists PostScript (baseline); macOS previews EPS natively; no "facts" view found | baseline | low |
| 23a | HDF5 / NetCDF (`.h5 .hdf5 .nc`; `.h5ad` unverified) | TAKEN (OSS). [ndLook / gridded-quicklook](https://github.com/abkfenris/gridded-quicklook): BSD-3, NetCDF, HDF5, GRIB, Zarr, Icechunk, xarray-style metadata, identifies by content, build from source. [HDF5QL](https://github.com/hacknus/HDF5QL): pushed 2026-04-08 | READMEs | high |
| 23b | MATLAB `.mat` | LEGACY ONLY. [matlab-quicklook](https://github.com/jaketmp/matlab-quicklook), 2017, "does not work in Mojave and later" | repo | high |
| 23c | R `.rds` / `.RData` | LEGACY ONLY on the evidence I saw: [QuickLookR](https://github.com/hrbrmstr/QuickLookR) says it does not work on modern Macs. The science agent reports a free "Stats File Viewer" with "R" and Quick Look; unverified by me | repo | low |
| 24a | FASTA/FASTQ, SAM/BAM, GFF/BED | OPEN. GitHub API `quick look macos fasta` = 0; github+apple search nothing | searches | medium |
| 24b | Newick trees | OPEN | search | medium |
| 25a | Reference files `.ris/.nbib/.enw` | OPEN. Unfold's BibTeX reference list (v2.6.0) is adjacent only | [changelog](https://unfold.tools/changelog) | medium |
| 25b | Molecular structures (PDB, mmCIF, SDF) | TAKEN (OSS). [Burette](https://github.com/SergeiNikolenko/Burette): MIT, Mol* 3D, PDB, mmCIF, SDF, MOL, XYZ, Apple Silicon, pushed 2026-10-13. [QuickLookProtein](https://github.com/JethroHemmann/QuickLookProtein): PDB, SDF, CIF, pushed 2026-05-20 | READMEs | high |
| 25c | DICOM | TAKEN, but not the "privacy findings" idea. [DicomPreview](https://github.com/neuralink/DicomPreview) (OSS, BSD-3, macOS 14+) shows the full tag table with no PHI warning; the baseline lists two paid DICOM apps. A PHI/privacy-findings view is OPEN. NIfTI/NRRD: [MIQ](https://github.com/marcoduering/MIQ) (OSS, pushed 2026-10-12) | READMEs | high that DICOM is taken; medium that findings are open |
| 25d | PMTiles, FlatGeobuf, MVT | TAKEN. [GeoPreview](https://apps.apple.com/us/app/geopreview/id6758587360): $34.99, Anton Novichikhin, macOS 13+, v1.0.11 (Jul 19 per page), Space-bar preview, lists FlatGeobuf, PMTiles, MVT, GeoParquet, GPKG, LAS/LAZ and DWG/DXF/DGN. No thumbnails mentioned | App Store | high |
| 25e | MBTiles | PARTIAL. quicklooker opens `.mbtiles` as SQLite; GeoPreview does not list MBTiles | [quicklooker](https://github.com/fosron/quicklooker) | medium |
| 26a | LUTs `.cube/.3dl` | TAKEN. LUT Preview: Anybox LTD, $4.99, macOS 13+, v1.1 (Mar 19; year not shown). Applies the LUT to a demo image and offers a slider. The page does not name `.cube` or `.3dl` ("more UTIs" in 1.1), and does not mention thumbnails | [listing](https://apps.apple.com/app/id6759214495) | medium-high |
| 26b | Palettes `.ase/.aco/.gpl/.clr/.sketchpalette`; design tokens | `.ase`: LEGACY ONLY ([QuickLookASE](https://github.com/rsodre/QuickLookASE), generator). Others and tokens: OPEN | repo; search | medium |
| 27a | Affinity files | TAKEN by the vendor: a user reports Affinity 2.5.6 brought Quick Look and thumbnails back through new preview options ([sir-apfelot](https://www.sir-apfelot.de/affinity-am-mac-so-kannst-du-die-thumbnail-und-quick-look-vorschau-aktivieren-68219/)). Needs the Affinity apps | secondary report | medium |
| 27b | Krita `.kra` / `.ora` | PARTIAL. Krita's source builds Quick Look and thumbnail plugins; users report both lost after Krita 5.3 on Sequoia ([Krita forum](https://krita-artists.org/t/no-preview-for-kra-thumbnail-after-5-3-update-on-mac/177587)) | forum | medium |
| 27c | `.sketch`, `.fig`, `.xd` | `.fig`: OPEN (Figma forum asks for it). `.sketch`, `.xd`: not verified; whether the Sketch or Adobe app ships a current extension was not found | web search | low |
| 27d | `.procreate` | PARTIAL. [Procreate-thumbnailer](https://github.com/devlinman/Procreate-thumbnailer) (not opened); [brushes-quicklook](https://github.com/pmwoz/brushes-quicklook) (OSS, brush files only, pushed 2026-10-11) | repo list | low |
| 28a | `.edl` | TAKEN (OSS). [edl-quicklook](https://github.com/claude-coder-collab/edl-quicklook): CMX3600 summary, timeline graphic and event table, macOS 13+, not notarised | README | medium |
| 28b | `.otio`, `.fcpxml` | OPEN. Search returned nothing | search | medium |
| 28c | Captions `.itt` | PARTIAL. iTT is TTML-based; TTML is previewed by QuickestLook and Unfold. SCC and EBU `.stl`: OPEN | [Unfold list](https://unfold.tools) | medium |
| 28d | `.aseprite` | OPEN. [Aseprite issue #4803](https://github.com/aseprite/aseprite/issues/4803) is open since 2024-11-21 and says Aseprite has no Quick Look support; I found no third-party fix | issue | medium |
| 28e | Tracker modules, SoundFonts, Gaussian splats, `.unitypackage` | OPEN. One combined search plus GitHub; nothing | search | medium |
| 29a | Chess `.pgn` | TAKEN (vendor claim, content unclear). [Manifest Chess Lite PGN Reader](https://apps.apple.com/us/app/manifest-chess-lite-pgn-reader/id6809753832): $17.00, Ordinary Ventures MB, macOS 12+, Apple Silicon, v1.0.1 (Sep 17); "preview them with Quick Look by pressing Space". It does not say a board is drawn | listing | medium |
| 29b | `.fen` | OPEN | listing says FEN only for starting a game | medium |
| 29c | Go `.sgf` | TAKEN. [SGF Tools](https://github.com/imabuddha/SGF-Tools): MIT, Quick Look board plus players and result, Finder thumbnails, Spotlight, Apple Silicon and macOS 26+ only, notarised dmg on GitHub, v2.0.9. An older [SGF-Tools](https://github.com/threeve/SGF-Tools) is a generator | README | high (macOS 26+ only) |
| 29d | Crosswords `.puz` | LEGACY ONLY. [QuickLookPUZ](https://github.com/DianeWass/QuickLookPUZ), generator tested up to macOS 10.12 | repo | high |
| 30a | Minecraft `.litematic/.schem/.nbt/.mcstructure/.mca` | TAKEN (OSS). [LitematicaQL](https://github.com/Arcadi4/LitematicaQL): AGPL-3.0, Metal rendering, macOS 13+, Homebrew cask, pushed 2026-10-13. `.mcworld` not listed | README | high |
| 30b | Scratch `.sb3`, Anki `.apkg` | OPEN | one combined search | medium-low |
| 31a | WhatsApp/Telegram chat exports; Apple Health export | OPEN | searches | medium |
| 31b | GEDCOM | OPEN. GitHub API `quick look macos gedcom` = 0; only editors such as [Swarm](https://github.com/samoilev/swarm) | searches | medium |
| 31c | MuseScore `.mscz` | TAKEN by the vendor: [issue #27136](https://github.com/musescore/MuseScore/issues/27136) closed 2026-02-16 (PR #29452), card "Done" in MuseScore Studio 4.7; the author says the Quick Look and thumbnail plugins were integrated into `mscore.app` (PR #27987). A search snippet says 4.7.5 includes them | issue | medium |
| 31d | MusicXML, Guitar Pro | OPEN. Guitar Pro's own app was not checked | search | low |

## Counts

The table has 87 rows after splitting the 31 numbered items. Each row is counted once, by the first verdict named in it:

- **TAKEN: 21** (6a, 14a, 14b, 14e, 15c, 16a, 19a, 19b, 20a, 20b, 23a, 25b, 25c, 25d, 26a, 27a, 28a, 29a, 29c, 30a, 31c). Of these, 14b, 20b, 27a and 31c are vendor apps that must be installed, and 6a, 14e, 15c, 16a, 19a, 20a, 23a, 25b, 25c, 28a, 29c and 30a are open-source projects without an App Store listing.
- **PARTIAL: 18** (2b, 3a, 10a, 11c, 12b, 12d, 12e, 12f, 13b, 14c, 14d, 15a, 16b, 22c, 25e, 27b, 27d, 28c).
- **LEGACY ONLY: 6** (5a, 21b, 23b, 23c, 26b for `.ase`, 29d).
- **OPEN: 42**, none higher than medium confidence.

Four rows are mixed: 12b (compose partial, Kubernetes open), 25c (DICOM taken, privacy findings open), 26b (`.ase` legacy, other palettes open) and 28c (iTT partial, SCC and EBU STL open).

## Claims the agents got wrong

Each of these was called unclaimed ("none found", "unserved", "nothing") in the agents' reports or in your brief. All are now TAKEN or PARTIAL.

- **KiCad** (engineering): "None current". Open-source KiCadQuickLook exists, and PCBAtlas ships a macOS app that mentions Quick Look.
- **IFC** (engineering): "none claims Quick Look". Two open-source Quick Look extensions exist, one pushed 2026-10-09.
- **Rhino, SketchUp, FreeCAD, DWG thumbnails** (engineering, "still unclaimed"): Rhino 8 SR17 claims the fix, SketchUp ships thumbnails, FreeCADCompanion exists, and GeoPreview lists DWG. Only Inventor, Solid Edge, Revit and Fusion stay open.
- **HDF5 / NetCDF** (science, "still unserved"): ndLook and HDF5QL (both OSS).
- **PMTiles and FlatGeobuf** (science, "none found"): GeoPreview's App Store page lists both, plus MVT, GeoParquet and DWG/DXF/DGN.
- **LUTs** (creative, "standalone apps only"): LUT Preview, Anybox, $4.99, Quick Look. Also **EDL** ("none found for timelines"): edl-quicklook.
- **Affinity and Krita** (demand signals, "unserved"): both ship vendor thumbnail and Quick Look extensions. Krita's are reported broken in 5.3.
- **XLIFF** (office, "no competitor"): xlfql. **`.po`**: Poedit has shipped a modern Quick Look extension since 3.5.1. **`.msg`**: QuickMSG, Oct 2026.
- **Chess and Go** (hobby, "None"): Manifest Chess Lite claims Space-bar preview for PGN; SGF Tools covers Go on macOS 26+.
- **Minecraft** (hobby): LitematicaQL, pushed 2026-10-13. **MuseScore** ("no Quick Look app was found"): MuseScore Studio 4.7 integrates it.
- **Configuration profiles** (trust): Pique previews `.mobileconfig` payloads, and Looq lists "configuration profiles". The "explain in plain words" angle is still open.
- **`.skill`** (developer): Looq's version history lists `.skill` previews.
- **Molecular structures** (science): the agent found Burette but wrote "none"; QuickLookProtein is a second one.

The agents were upfront that the iTunes API was rate-limited; the misses are mostly open-source projects on GitHub and vendor-bundled extensions.

## Strongest open ground

OPEN with medium confidence, ranked by how clear the search evidence is and how well the idea fits a "what will this do" lens:

1. **Script effects analysis (item 1).** Every general app and Pique only highlight shell, PowerShell and AppleScript.
2. **Explaining auto-run config (2a):** `tasks.json`, Claude Code hooks, `mcp.json`, dev containers. Nobody reads these as "what runs". The closest are quicklooker's `package.json` scripts and compose tables.
3. **Model files (8a):** GGUF and safetensors headers. Zero hits on GitHub, the App Store and the web, apart from CLI/MCP tools.
4. **Pickle and PyTorch safety scan (9).**
5. **Package and extension inspection (4, 5b):** npm `.tgz`, wheels, `.vsix`, `.xpi`, `.nupkg`. Listing exists everywhere; install-time behaviour and permissions are nowhere.
6. **Raw STL/OBJ print-readiness (13a):** volume to weight, open edges, bed fit. Even the two dedicated maker apps list none of it.
7. **`.mcpb` / `.dxt` bundles and plugin manifests (3b).**
8. **Binary and capture formats (11b, 11d, 11e):** `.wasm`, `.ips` crash reports, `.pcap`.
9. **E-invoices (17):** XRechnung, ZUGFeRD and Factur-X have only standalone viewers (one with a subscription), no Quick Look; plus **`.p7m` / ASiC (18)**, though that search was thin.
10. **Genomics (24a):** FASTA/FASTQ/BAM headers. Also open at medium: Aseprite (28d, upstream issue open), `.mbox`, `.otio`/`.fcpxml`, GEDCOM, password-manager exports, HAR waterfall, OpenAPI.

Caution: "open" means nothing found by search, and GitHub's search missed KiCadQuickLook until a different query. New OSS extensions are appearing weekly (several above were pushed within the last 10 days), so the engineering and science rows can close before release.

## New competitors not in the baseline

Prices are US list prices on the page, or "OSS" for GitHub projects that you build or download. Dates are the store's "last updated" (year not shown, copyright 2026) or GitHub `pushed_at` from the API.

| Name | Price | What it previews | Link | Release / update |
|---|---|---|---|---|
| Looq: Preview Files (PARCSE) | $12.99 on the App Store page I fetched; a search snippet says $7.99 and macOS 26.2; Setapp lists it from $10 | Markdown, 190+ languages, TSV, SQLite, diffs, archives, folders, app bundles, IPAs, installer packages, provisioning and configuration profiles, torrents, disk images, `.skill`, org-mode, Mermaid. macOS 14+ | [App Store](https://apps.apple.com/app/id6760281430) | v1.7.7, Sep 29 |
| GeoPreview (Anton Novichikhin) | $34.99 | GIS: Shapefile, GeoJSON, GPKG, KML/KMZ, GPX, FlatGeobuf, PMTiles, MVT, GeoParquet, OSM, LAS/LAZ, DWG/DXF/DGN, `.gdb` folders. macOS 13+ | [App Store](https://apps.apple.com/us/app/geopreview/id6758587360) | v1.0.11, Jul 19 |
| LUT Preview (Anybox) | $4.99 | LUT files applied to a demo image. macOS 13+ | [App Store](https://apps.apple.com/app/id6759214495) | v1.1, Mar 19 |
| Manifest Chess Lite PGN Reader (Ordinary Ventures MB) | $17.00 | PGN reader; Space-bar Quick Look claimed. macOS 12+, Apple Silicon | [App Store](https://apps.apple.com/us/app/manifest-chess-lite-pgn-reader/id6809753832) | v1.0.1, Sep 17 |
| PCBAtlas (Shanghai Astroform) | Free; Plus $24.99 | KiCad, Gerber packages, DSN, IPC-2581, ODB++; Quick Look wording unclear. macOS 14+ | [App Store](https://apps.apple.com/us/app/pcbatlas/id6759897822) | v1.2.1, Oct 2 |
| Pique (MacAdmins, Declarative IT) | OSS, Apache-2.0 | `.mobileconfig`/plist with payload details, YAML, shell, PowerShell, JSON Lines, HCL, AutoPkg, VPP token. macOS 26+ | [GitHub](https://github.com/macadmins/pique) | not shown |
| quicklooker (Vincent Bruijn) | OSS, MIT, build from source | JSON, JSONL, YAML, TOML, `.env` with masking, SQLite, package.json/composer, docker-compose, archives, `.class`, logs, fonts. macOS 13+ | [GitHub](https://github.com/fosron/quicklooker) | not shown |
| ndLook / gridded-quicklook | OSS, BSD-3, build from source | NetCDF, HDF5, GRIB, Zarr, Icechunk metadata | [GitHub](https://github.com/abkfenris/gridded-quicklook) | not shown |
| HDF5QL (hacknus) | OSS | HDF5 | [GitHub](https://github.com/hacknus/HDF5QL) | 2026-04-08 |
| IFC Quick Look (cioxideru) and ifc-quicklook (trapple) | OSS, MIT | IFC building models in 3D | [cioxideru](https://github.com/cioxideru/ifc-quicklook-macos), [trapple](https://github.com/trapple/ifc-quicklook) | 2026-10-09, 2026-07-13 |
| KiCadQuickLook (Architeuthis-Flux) | OSS, Unlicense | KiCad files | [GitHub](https://github.com/Architeuthis-Flux/KiCadQuickLook) | not shown |
| FreeCADCompanion (graelo) | OSS, MIT | `.FCStd` embedded thumbnail. macOS 15+ | [GitHub](https://github.com/graelo/FreeCADCompanion) | not shown |
| Burette (Sergei Nikolenko) and QuickLookProtein | OSS, MIT | PDB, mmCIF, SDF, MOL, XYZ in 3D | [Burette](https://github.com/SergeiNikolenko/Burette), [QuickLookProtein](https://github.com/JethroHemmann/QuickLookProtein) | 2026-10-13, 2026-05-20 |
| DicomPreview (neuralink); MIQ (marcoduering) | OSS | DICOM tag table plus image; NIfTI, MGH, MIF, NRRD | [DicomPreview](https://github.com/neuralink/DicomPreview), [MIQ](https://github.com/marcoduering/MIQ) | not shown; 2026-10-12 |
| QuickMSG (rs2pt) | OSS, MIT | Outlook `.msg` | [GitHub](https://github.com/rs2pt/QuickMSG) | 2026-10-07 |
| xlfql (capybara-translation) | OSS, MIT | XLIFF 1.2, mxliff, sdlxliff | [GitHub](https://github.com/capybara-translation/xlfql) | 2026-04-22 |
| edl-quicklook (claude-coder-collab) | OSS | CMX3600 EDL | [GitHub](https://github.com/claude-coder-collab/edl-quicklook) | not shown |
| SGF Tools (imabuddha) | OSS, MIT | SGF Go records, thumbnails, Spotlight. macOS 26+, Apple Silicon | [GitHub](https://github.com/imabuddha/SGF-Tools) | v2.0.9 |
| LitematicaQL (Arcadi4) | OSS, AGPL-3.0 | Minecraft schematics and `.mca` | [GitHub](https://github.com/Arcadi4/LitematicaQL) | 2026-10-13 |
| Preview3MF (tborovatz), threemf (guanchzhou), 3MF Preview (App Store) | OSS; price not checked | 3MF thumbnails and 3D | [Preview3MF](https://github.com/tborovatz/Preview3MF), [threemf](https://github.com/guanchzhou/threemf) | not shown |
| y-a-v-a/quicklooks, 2b3pro/ql-yaml, OK JSON | OSS / OSS / paid (price not checked) | JSON/JSONL/YAML/TOML previews | [quicklooks](https://github.com/y-a-v-a/quicklooks), [ql-yaml](https://github.com/2b3pro/ql-yaml) | not shown |
| Names seen only in App Store search results (not opened) | not checked | Preview3D, 3D Manager, 3D Viewer: STL OBJ glTF 3MF, STL 3D Viewer, STEP File Viewer (STEP/IGES), HDF5 Viewer, HighDeF, Monge DWG viewer | [search](https://apps.apple.com/us/app/mac/search?term=quicklook%20stl%203mf) | unknown |

Also note: Unfold 3.2.0 (2026-10-03) now previews 3MF and STEP with thumbnails ([changelog](https://unfold.tools/changelog)), and its list includes `.mobileconfig`, `.tfstate`, `.wat`, `.torrent` and `.app` as text or bundle views. Universal 3D Previewer claims SOLIDWORKS as 3D. The baseline already records both.
