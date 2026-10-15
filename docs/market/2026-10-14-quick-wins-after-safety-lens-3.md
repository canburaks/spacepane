# Remaining feature improvements, quick wins first

Assessed 2026-10-14 (Europe/Istanbul), at the owner's request, after Safety Lens 2 ([decision 029](../decisions/029-safety-lens-2-what-a-file-will-do.md)) and Safety Lens 3 ([decision 030](../decisions/030-safety-lens-3-models-add-ons-and-packages.md)) reached `main`. It re-rates what is left of [the 2026-10-13 research](2026-10-13-new-file-types-and-features.md) against the code as it is now.

**Status:** proposals. Nothing here is a plan commitment until it goes through `PLAN.md` and a decision record. Every rating is a reading of the code and the research, not a spike: nothing was built, run or observed in Finder for this list.

**Excluded:** everything Safety Lens 2 and 3 shipped. That is tier A of the research except `.skill`, `.1pux`, ONNX, Keras and Core ML, plus the launchd lens and certificate and profile validity. The two earlier quick-win lists, which led to those decisions, were given in conversation and were not saved.

## Method

- Five audit agents each took one area: Safety Lens 2 and 3 leftovers; dialect lenses and developer binaries (research B1 and B2); office, business and creative formats; science, maker and hobby formats with tier C; interaction features and cross-cutting engineering. Each read the sources, decisions, `PLAN.md`, the validation records and the research reports, and rated each item for status, reuse, new pieces, blocker and effort.
- Two further agents tried to refute the twelve ratings that looked cheapest. Seven of the twelve grew and two shrank. The ranking below uses the corrected ratings.
- The lead read the code behind two claims that would have changed the ranking. One was refuted (see the property-list item in tier 1); one stands (the Kubernetes item under owner decisions).
- Uniqueness verdicts come from [the uniqueness verification](expansion-research/2026-10-13-verification-uniqueness.md); where a domain report disagrees, the verification file wins. No web or App Store queries were made.
- Code paths that do not start with `Packages/` are relative to `Packages/PreviewCore/Sources/`.

**Effort** includes everything an item needs to ship in this repository: code, tests, fixtures, strings in 14 languages. XS is a day or less, S is two to four days, M is one to two weeks, L is longer.

**Fixed cost of a new format.** A new catalog entry adds about a day: the catalog entry, manifest regeneration, an appearance sample, host fixtures, a host-matrix row, strings and `npm run data:sync` in `spacepane-web`. A lens, a mode or a fix on a format that is already cataloged and already reaches the panel avoids most of that. This is the main reason the order below differs from the research's order.

## What the code allows today

These facts set most of the ratings.

- **A lens returns findings only.** `PreviewTextLens.findings(in:request:context:)` returns `[PreviewFinding]` (`Packages/PreviewCore/Sources/PreviewContracts/PreviewTextLens.swift:19`). It cannot add a table, a graph or facts. Its request carries the format, the file name and one parent folder name, so `.github/workflows` is seen as `workflows`. Lenses never run on app-made summaries (`PreviewCore/PreviewPipeline.swift:231`), so HAR, archives and other summary formats must report their own findings.
- **Structure-only dialects need no catalog change.** The launchd lens recognises a job by its keys, not by a sub-type. An OpenAPI table can be a renderer mode on the JSON tree that is already built.
- **There is no YAML reader in `PreviewFormats`.** The YAML subset lives in `PreviewRenderers`, which `PreviewFormats` cannot import. GitHub Actions, docker-compose, Kubernetes, `SKILL.md` front matter and YAML OpenAPI all wait for one.
- **A new finding kind** is an enum case, wording, a severity, strings in 14 languages and fixtures ([decision 012](../decisions/012-safety-findings.md)). That is routine, but it makes a "one rule" lens an M when it needs several kinds.
- **Routing** (observed 2026-10-14, macOS 27.2, [panel record](../validation/safety-lens-2-panel-2026-10-14.md)): `data.json`, `data.xml`, `data.yaml`, `archive.tar`, `.strings` and `.stringsdict` reach SpacePane in the panel. CSV, STL, OBJ and PLY stay with Apple's previewers even when claimed exactly. `data.jsonc`, `data.har` and `text.log` are not observed.

## Tier 1: quick wins

No new catalog format, no owner decision, effort XS to S.

| # | Item | Effort | Why | Watch for |
|---|---|---|---|---|
| 1 | **Script effects for `.tool` files.** Add `tool` to the shell row of `SourceLanguageDetector` and a test. | XS | Research A1 names `.tool`, and the lens is silent for it today: the detector has no `tool` suffix (`PreviewFormats/Code/SourceLanguageDetector.swift:94`) and the lens is gated on the language (`PreviewFormats/Lenses/ScriptEffectsModel.swift:57-58`). | Whether macOS types `.tool` as a shell script is not recorded, so routing needs one observation. The detector's doc comment still says language only colours text; correct it. A `.tool` with a Python `#!` line would be read as shell. |
| 2 | **Make the advertised Cmd-F work in table modes.** | XS | The info panel and command availability offer Cmd-F in tables (`PreviewRenderers/Interaction/NativePreviewView+Information.swift:14`), but it reaches the filter only when the table already has focus (`PreviewRenderers/NativeTablePreviewView.swift:507-512`). Elsewhere the key does nothing and nothing says so, unlike the Contents view (`PreviewRenderers/Markup/MarkupContentsView.swift:402`). Decision 021 (line 85) leaves Cmd-F to the table filter in table modes. | Found by code reading; observe it in the panel first. Either route Cmd-F to the filter from anywhere in the preview, or announce that it is unavailable. `Q53CommandAvailabilityTests` asserts the current offer. An announcement adds a string, so it also needs `npm run data:sync` in `spacepane-web`. |
| 3 | **Stop escaping `/` in property-list Source views.** | XS | `PreviewFormats/PropertyListSourceAdapter.swift:47` omits `.withoutEscapingSlashes`, so URLs and paths read as `https:\/\/…`. | Not a leak: the lead checked that an escaped string whose decoded value holds a URL password is concealed whole (`PreviewFormats/JSONSourceAdapter.swift:192`). After the fix only the password is concealed. Update `Packages/PreviewCore/Tests/PreviewFormatsTests/TextExpansion/PropertyListOutputBudgetTests.swift:38`, and add a plist URL-credential test, because none exists. |
| 4 | **Move the provenance notes into the info panel.** | XS | The owner approved it (`docs/reviews/2026-10-06-quality-review/owner-questions.md:153,157`); the ux-chrome box that includes it (`PLAN.md:280`) is unchecked. The shortcut list in the panel already exists (`PreviewRenderers/Interaction/PreviewInfoPanelCopy.swift:7-28`). | Needs a Mac check. |
| 5 | **OpenAPI and Swagger endpoint table for JSON.** A mode keyed on a root `openapi` or `swagger` key with `paths`. | S | Open in the uniqueness check, and the strongest demand among the cheap items: Swagger Viewer has 1.04 million VS Code installs. Renderer-only; the JSON tree is already built in `SafePreviewModes`, and `NativePreviewMode` is not a contract enum. | Three `switch` statements over the mode have `default:` branches and need a manual sweep. The outline cap (256 KiB, `PreviewRenderers/SafeStructuredText.swift:31-32`) leaves large specs without a table. YAML specs wait for the YAML reader (tier 3). The mode label is a new string, so `npm run data:sync` in `spacepane-web` follows. |
| 6 | **`.code-workspace` tasks and `.cursor/hooks.json` in the auto-run lens.** | S | Same question as the shipped lens, on files it does not read yet. `.code-workspace` already reaches the lens as JSON with comments; `hooks.json` under `.cursor` is matchable by its parent folder. | Workspace files have free names, so they need a suffix role, and their tasks sit under `tasks.tasks[]`. Cursor's hook layout could not be confirmed offline. `data.jsonc` routing is not observed. |
| 7 | **Download-then-run split across lines.** | S–M | A limit decision 029 states (line 88). Lens-only, on formats that already reach the panel, with the existing finding kind. | Keep the line window small so comments and quoted text still do not count. |

Small but low value, in the same class: the Chrome extension ID in `.crx` cards (S; the header is skipped today), a partial wheel summary above the 10,000-member ZIP limit (S), and install findings in plain `.tar` packages (S; npm and Python ship compressed tarballs).

## Tier 2: small new formats

Parser work of S each, plus the fixed cost of a catalog entry, so about M in total. Ordered by value.

| # | Item | Uniqueness | Why | Watch for |
|---|---|---|---|---|
| 8 | **1Password `.1pux` export**: the readable-logins count the other exports get. | Open (medium) | The one credential export research A7 names that is still missing. 1Password and Bitwarden tell users to delete these files. | A lens cannot do it: the logins are a member of a ZIP. Reuse `CredentialExportLens` counting and `ZIPArchiveReader`. |
| 9 | **SARIF summary**: rules, results by level, files. | No row in the uniqueness check | SARIF Viewer has 595,000 VS Code installs, the second-strongest developer demand after OpenAPI. Reuses the data summary paths (`PreviewContracts/DataSummaryPaths.swift`). | `.sarif` is not cataloged and needs its own exported type; routing is not observed. |
| 10 | **Reference files `.ris`, `.nbib`, `.enw`** in one entry. | Open (medium) | The bibliography model and formatter are generic and can be reused (`PreviewRenderers/Markup/MarkupBibliography.swift`, `PreviewRenderers/Markup/BibliographyFormatter.swift`). | Key the References mode on the format, not on BibTeX syntax, to avoid a contract change. No type ownership is recorded for these suffixes. |
| 11 | **Configuration profile `.mobileconfig`**: what the profile installs, in plain language (root certificates, VPN, device management). | Payload view taken: Pique (macOS 26 and later) and Looq (macOS 14 and later). Plain-language wording open (medium) | Fits "what this file will do"; reuses the profile reader (`PreviewFormats/Packages/ProvisioningProfileAdapter.swift:37`). | The value is the wording, not the view. `com.apple.mobileconfig` is a system type; an exact claim should win, but it is not observed. |
| 12 | **WebAssembly `.wasm`**: sections, imports, exports, WASI access. | Open (medium) | No competitor found; the table channel exists. | Needs its own exported type. |
| 13 | **Colour palettes `.gpl` and `.sketchpalette`** in one entry, as a swatch table. | Open (medium) | None of the general competitors claims palettes. Both are text or JSON. | A swatch thumbnail is decision 022's question. `.aco` and `.clr` are binary (S–M each); `.ase` shares its suffix with Aseprite and needs a content claim. |
| 14 | **Go `.sgf` board.** | Taken only on macOS 26 and later (SGF Tools) | SpacePane supports macOS 15, so users of 15 to 25 have nothing. | Board drawing on the existing diagram scene. |
| 15 | **3MF slicer facts**: printer, filament, layer height, time. | Partial (MakerLook, MakersPreview) | 3MF is the only mesh type that reaches the panel on macOS 27.2. The reader exists (`PreviewFormats/Geometry/ThreeMFAdapter.swift:116-131`). | Additive fact cases are a small contract change. Check that printer keys with secrets are concealed. |
| 16 | **GEDCOM family trees.** | Open (medium) | Unique suffix; the outline model fits the levels. | Names and dates of living people need a concealment rule. |
| 17 | **Krita `.kra` and OpenRaster `.ora` facts** (layers, size), without the embedded picture. | Partial: Krita's own extension is reported broken on macOS 15 | Listed in `PLAN.md:541`. | Krita declares `.kra` when installed. Showing the picture is decision 022's question (owner decisions). |
| 18 | **Genomics text headers**: FASTA, FASTQ, SAM, GFF, BED. | Open (medium) | One parser family on the text and table models. | Weak Mac demand. |
| 19 | **Niche single entries**: OpenTimelineIO `.otio`, Scratch `.sb3`, source maps (`sourcesContent` finding), and Spotify or Telegram JSON exports (no catalog change). | Open, except source maps (Partial) | S each. | Low demand. `.map` ownership is unknown. |

## Tier 3: worth doing, not quick

M or more. Grouped by what unlocks them.

- **A YAML reader in `PreviewFormats` (M).** It unlocks a GitHub Actions lens and job graph, a docker-compose graph, a Kubernetes lens, `SKILL.md` front matter and OpenAPI in YAML. The Actions lens is the best fit for the Safety Lens story among these.
- **A line and point primitive in the geometry renderer (M–L).** The renderer draws triangles only (`PreviewRenderers/GeometryMetalRenderer.swift:186`; `PreviewContracts/GeometryPresentation.swift:165-177`). It unlocks G-code toolpaths, VCD waveforms, KiCad and Eagle boards and DXF drawings. It changes decision 024's contract.
- **Lens families outside decision 029's scope (M each, after an owner nod on scope).** Localisation checks on `.xcstrings` (untranslated, placeholder mismatch across languages, plural gaps; a `.strings` file holds one language, so cross-language checks work only on `.xcstrings`); e-invoice (UBL, CII) and bank statement (camt.053) checks on `.xml` with count-and-line findings; a command and URL inventory for `AGENTS.md`. The XML delegate exposes no character data yet, so amounts need a new hook.
- **New formats and modes (M each):** `.skill` agent bundles; `.ips` and `.crash` reports; a container image summary inside the TAR listing (no new format); JSON shape with copy as TypeScript or Swift; a HAR token and cookie share check (after HAR routing is observed); a log timeline; ONNX, Keras and Core ML (ONNX and `.mlmodel` need a protobuf reader); Mach-O libraries and `.dSYM`; G-code facts (the highest maker demand, but `.nc` collides with NetCDF); a selection decoder (epoch, base64, URL, colour).
- **Mesh and subtitle checks (S–M each).** A flipped-face count is a new adjacency pass, not the existing edge pass, and reaches the panel only for 3MF. Subtitle overlap and reading speed need the SRT and VTT grammar lifted into one shared parser first; it is duplicated today.
- **Parity only.** HDF5 and NetCDF, KiCad, IFC, molecules, PMTiles and FlatGeobuf, LUTs, PGN, Minecraft schematics, EDL, DXF, glTF, statistics files, XLIFF and `.po` all have a current Quick Look tool. Add them for breadth, not for a claim.

## Also open, unranked

Audited and left out of the tiers above, because each is M or more with weak or unmeasured demand, or depends on an enabler above.

- **Developer:** network captures `.pcap` and `.pcapng` (L); localisation files `.arb`, `.resx`, `.tmx`, `.mo` and `.xcloc` (S each for `.arb` and `.resx`, M for `.xcloc`; Xcode owns `.xcloc`); well-known SQLite schemas such as Lightroom catalogs and browser histories; lockfile tables (Cargo, `Package.resolved`, `go.sum`); JavaScript for Automation in the script lens.
- **Business:** signed containers `.p7m` and `.p7s` and ASiC (M; the signer API has no call site yet); OFX and MT940 statements; flat `.mbox` mailboxes (Mail's package type collides); XMind maps; facts only for `.procreate`, `.fig` and `.sketch` (the preview picture they carry is decision 022's question).
- **Science and personal:** BAM headers (M, block gzip); Newick and Nexus trees; DICOM and EDF patient-field findings (a new kind; viewing DICOM is taken); WhatsApp and Telegram chats as a conversation and Apple Health exports (both need content-detected dialects).
- **Hardware and post-production:** VCD waveforms, Intel HEX, UF2 and Eagle XML (the plots wait for the line primitive); Final Cut `.fcpxml` and SCC captions.
- **Cross-cutting:** an integrity finding ("this file looks truncated") for gzip, ZIP and EPUB, like `model.incomplete`; one head-and-tail read policy with a notice; a grandparent folder in the lens request, so `.github/workflows` can be recognised by path.
- **Deferred defaults** already on record: Mermaid Gantt charts, draw.io colours and links, an Outline-first default for JSON and YAML, the prose typeface, and the measured compact-width threshold.
- **Not possible:** EBU STL captions, because `.stl` belongs to the mesh format and Apple's previewer on macOS 27.2.

## Needs an owner decision

Effort does not matter until these are decided.

1. **CSV and mesh reach.** On macOS 27.2 the CSV credential-export finding and the STL, OBJ and PLY print check reach only the companion, because Apple's previewers keep those types. Accept it, or say so in the copy (XS once decided).
2. **Kubernetes `Secret` values.** YAML concealment is by key name only (`PreviewFormats/ConfigurationPrivacyRanges.swift:62-74`; credential words at `PreviewContracts/PreviewModels.swift:456-461`), so values under `data:` in a `Secret` with ordinary key names show in the clear. A structural rule would close it; formats cannot change the privacy defaults today. Found by one auditor; the lead read the rule, but no fixture was run.
3. **A STEP and IGES text-level inspector** (M): schema, originating system, assembly tree, entity census, units, without Open CASCADE. [Decision 028](../decisions/028-no-cad-in-version-1.md) covers only the Open CASCADE route. A header reader exists in the CAD sources.
4. **EPS and PostScript, facts only** (S–M): the strongest demand signal in the research. [Decision 025](../decisions/025-competitor-parity-program.md) gates it, three apps claim the type, and the research disagrees on whether macOS still previews EPS. Facts only avoids adding TIFF to the image contract.
5. **Typed values in findings** ([decision 012](../decisions/012-safety-findings.md)): needed for invoice totals, bank balances and HAR hosts.
6. **Pictures in thumbnails** ([decision 022](../decisions/022-content-thumbnails.md)): a facts badge (decision 030 calls it later work), embedded pictures from design files, palette swatches.
7. **Claiming `.pkl` and PyTorch `.bin`**, which reverses decision 030 line 29. `.pkl` is also Apple's Pkl language, so it needs content sniffing.
8. **Interaction:** Cmd-G find-next, which decision 021 excludes; a companion "open as text" for one dropped file with an unsupported suffix (the top cross-platform request; Finder cannot do it); previewing one entry inside an archive, which decisions 012 and 013 forbid today; a reveal toggle for concealed secrets.
9. **Smaller rules:** a personal-data finding family; mesh bed-fit defaults and a price for cost estimates; tool-text phrase lists beyond English; a noise rule for Python source packages with uncommon build backends.
10. **Legal reads before work:** Microsoft's specifications for `.msg` and `winmail.dat` (MS-OXMSG and MS-OXTNEF are not on the Open Specifications Promise list); Aseprite's format document; SAS data files; Garmin FIT; a zstd dependency audit for Anki decks.

## Platform spikes

Each is about S in a signed build, and each decides whether a later feature is possible: Foundation Models, Translation and Vision inside the preview extension; App Intents for findings; reading the download source (quarantine and where-from attributes) from the sandbox; showing the winning provider in the preview header (the companion's read of `/Applications`); whether the Quick Look host forwards Cmd-G to the extension.

## Not features: validation still open

- Safety Lens 3 has no panel record: the panel, Finder, thumbnails and VoiceOver are open, and `.tool` and the Safety Lens 3 suffixes are not observed.
- Safety Lens 2 is observed through `qlmanage` only. Finder, thumbnails and VoiceOver are open.
- Native-speaker review of the Safety Lens 2 and 3 strings in 14 languages.
- Routing of CSV, STL, OBJ and PLY on macOS 15 and 26.
- The host-matrix rows for the mesh formats say not observed, which is older than the 2026-10-14 panel note.

## Defects noticed in passing

- A concealed quote can colour the following lines in source views (panel record); the cause was not located.
- The SRT and VTT grammar is implemented twice (`PreviewFormats/Subtitles/SubtitleParser.swift`, `PreviewRenderers/SafeSubtitleCues.swift`).
- The 256 KiB outline cap is well below the 1 MiB input budget, so large JSON gets no structure view.

## Not established

- Finder routing for every suffix this list proposes to add.
- Format details that need the web: `.skill`, `.1pux`, Cursor hooks, Codex configuration, ONNX, Keras, Core ML, the CRX header.
- Demand beyond the figures already in the research.
- Whether Eutopix's e-invoice extension previews in Finder; whether Krita, Xcode, Poedit, Peek or iPreview win routing when installed.
