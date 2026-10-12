# Competitor UX/UI analysis and the gap to world-class

Researched 2026-10-06 (Europe/Istanbul). Follows [the competitor landscape](2026-10-05-competitor-landscape.md), which inventoried *features*. This report compares *experience*: what the user sees and does in a Quick Look window and in each companion app. Feature parity is largely done ([decision 025](../decisions/025-competitor-parity-program.md)); the question now is whether the same capabilities are presented better than anyone else's.

**Evidence.** Seven parallel reports under [ux-research/](ux-research/), one per cluster, all written against one rubric (eight dimensions, scored 1–5 with evidence) and one screenshot recipe. The researchers downloaded and looked at every App Store screenshot (about 150 frames) plus vendor-site and README images. **Everything about a competitor is observed in marketing material; nothing was installed or tested.** Where a vendor showed nothing, the report says "not shown" and scores conservatively. SpacePane's own column comes from a code-level audit, not from screenshots either.

| Report | Covers |
|---|---|
| [Closest rivals](ux-research/2026-10-06-closest-rivals.md) | QuickLook Pro, QuickestLook, Super Quick Look, Simple Quick Look |
| [Breadth leaders](ux-research/2026-10-06-breadth-leaders.md) | Unfold, LookQuick, iPreview, GoodQuickLook |
| [Code and Markdown](ux-research/2026-10-06-code-markdown.md) | Peek, Syntax Highlight, QLMarkdown, smittytone, Anybox, Peekdown, Code Peek+, PeekCode, Markdown Peek, Glance |
| [Data and databases](ux-research/2026-10-06-data-db.md) | JSON Loupe, QLook JSON, Fast SQLite Viewer, Quick Data Insights, Python Data Viewer, FinderPeek; OK JSON and TablePlus as styling references |
| [Folders, archives, 3D](ux-research/2026-10-06-folders-archives-3d.md) | Folder Preview, FolderPlus, SpacePeek, Loupe, Archive Quick Look, Quick Preview, BetterZip; Universal 3D Previewer, StepPreview, MakersPreview, Eyemesh, mesh-peek, Peek3D |
| [System baseline and benchmarks](ux-research/2026-10-06-system-and-benchmarks.md) | Apple's own Quick Look on macOS 15/26, HIG rules, and transferable patterns from best-in-class macOS apps |
| [SpacePane self-audit](ux-research/2026-10-06-spacepane-self-audit.md) | Code-level reconstruction of every preview state and companion page, 32 findings, top-20 fixes |

## Headline findings

1. **No competitor has a coherent experience across formats.** Only GoodQuickLook (one header plus one bottom status bar) and, less fully, QuickLook Pro (header card plus mode bar) present every type through one anatomy. Most apps are a different-looking renderer per format. Consistency is the exception in this category, which makes it cheap to win.
2. **The category never shows its limits.** Across about 150 frames, not one shows a truncated listing, a "showing first N of M" notice, a too-large state, an encrypted archive, an unsupported type or an error. Limits live in support pages (QuickLook Pro, BetterZip) or in a settings sentence (PeekCode). SpacePane already enforces budgets everywhere and words them honestly, but renders them as a 10 pt caption. Designing those states well is the clearest open position.
3. **Trust is copy, not interface.** "Local, read-only, no upload" appears in every store listing and in no preview. Only QuickestLook puts a privacy statement in the content ("15 variables · values masked by default"), and it over-masks ordinary values. Nobody in the data cluster masks at all; one app prints a PEM private key under a "safe for secrets" headline. SpacePane's typed findings are ahead on substance; the presentation (status line, banner rows, Copy button, sync warning) says the same thing up to four times and can take half the window.
4. **Interaction exists but is invisible, for them and for us.** Peek is the only app that labels its shortcuts on screen (floating ⌘L/⌘S pills) and scores 5/5 on interaction. SpacePane has find, filter, Go to Line, Copy All/Key/Value/Path, zoom and sort, and reveals almost none of it outside a right-click menu.
5. **The best companions teach; ours reports.** Unfold's System-Settings-like window with a live sample pinned on every page, Super Quick Look's status page with a sample gallery, Quick Preview's three-step start card and sbarex's inquiry window all guide the user to a working preview. SpacePane's General page is structurally right but reads as a status report: a green "shared" tone for something it cannot verify, a setup paragraph without a control, and the conflict scan as the last card.
6. **Structured views are where polish is visible.** OK JSON and TablePlus (not Quick Look apps) show what readable trees and grids look like: type glyphs, counts on collapsed nodes, a path bar, quiet zebra, right-aligned numerics, a range footer. No Quick Look app reaches that; SpacePane's outline and table are functional but carry none of these cues.
7. **3D previews have no chrome vocabulary yet.** The CAD specialists share an unlabelled bottom pill of axis views; Eyemesh (an app, not a Quick Look extension) has a named render-mode menu, a gizmo and a dimensions inspector. No Quick Look 3D preview shows units, part counts or how to orbit. SpacePane shows faces, triangles and millimetre dimensions, but in two rows of mixed buttons above the viewport.
8. **A landscape correction.** Unfold's own changelog lists 3.2.0 (2026-10-03) with interactive 3MF and STEP previews and Finder thumbnails, although the App Store API still returned 3.0.2. The landscape's claim that STEP is a SpacePane-only differentiator among general-purpose apps is no longer safe; IGES remains unmatched in what was found.

## Scorecard: who leads each dimension

Scores are the cluster researchers' (1–5, marketing evidence only). SpacePane's row is the self-audit's score from code. "Leader" names the app whose evidence set the bar.

| Dimension | Leader (score) | What sets the bar | SpacePane | Gap |
|---|---|---|---|---|
| 1 Preview anatomy | GoodQuickLook (5), SpacePeek (5) | One header (icon · name · "20 files · 1 hidden · 13.9 MB") and one bottom facts strip ("253 KB · 9405 lines · UTF-8 · LF") for every type; SpacePeek's Overview/Contents with one insight sentence | 3 | No file facts anywhere; status line and badge are the only chrome; states are captions |
| 2 Content presentation | Peekdown (5), OK JSON (5), TablePlus (5) | Reading-grade typography, typed tree rows, quiet grids | 4 | Eleven contrast-tested schemes and a safe gutter; but no muted ink tier, prose set in the code face at full width, full-ink line numbers |
| 3 Interaction and discoverability | Peek (5), SpacePeek (5) | In-preview find with counts, jump-to-line HUD, TOC rail, shortcut labels on screen; sibling pager | 3 | Rich commands, all hidden |
| 4 States and honesty | JSON Loupe (5), BetterZip (5 by docs) | Inline parse markers with exact column, "1 of the first 4 records failed" ribbon; documented limits | 3 | Honest wording, undesigned rendering; failure copy names the cause, not the next step |
| 5 Companion | Peekdown (5), Unfold (4), Super Quick Look (4) | Settings-style sidebar, live sample pinned on every page, captions that state each choice's cost, status page with sample gallery | 3 | Right IA; live sample scrolls away, green overclaim, setup paragraph, conflicts last |
| 6 Visual identity and native feel | Peekdown (5), SpacePeek (5) | Current macOS idioms, restraint, one accent | 3 | Native controls; opaque custom sidebar, flat 13/13/13 hierarchy, no motion |
| 7 Trust communication | QuickestLook (4), Fast SQLite Viewer (4), Quick Data Insights (4) | A masked-by-default line beside the data; "opened immutable" stated concretely; an "Offline by design" card | 3 | The strongest substance in the category, shown as a tooltip glyph and repeated captions |
| 8 Delight and friction | Peekdown (5) | Copy icons on blocks, callouts, calm motion | 2 | No designed empty states, no feedback on copy, three prompts to open a file |

Reading the table: no competitor scores above 3 on dimensions 4 and 7 except JSON Loupe and the three trust apps, and those lead with a single pattern each. SpacePane is level with or ahead of the field on substance in every row, and behind the leader on presentation in every row. The program in [decision 026](../decisions/026-world-class-ux-program.md) is therefore a presentation program on top of a finished pipeline, not a feature program.

## Table stakes the field already has

Match these without debate; users will compare against them in the first minute.

- A file name and a one-line per-type facts strip (encoding · lines · size; files · folders · expanded size; records · size) next to the content (QuickLook Pro, GoodQuickLook, JSON Loupe, QuickestLook, Super Quick Look).
- A native segmented mode control (Preview/Raw, Tree/Raw, Data/Schema) in the header, never a brand strip (QuickLook Pro, JSON Loupe, Quick Data Insights).
- Source with a dimmed, right-aligned line-number gutter separated by a hairline, and a visible Wrap control (QuickLook Pro, Super Quick Look, PreviewCode).
- Folder and archive listings as Name / Kind / Size / Modified tables with disclosure, real type icons, a footer with counts and totals, and a path bar (every folder app).
- A theme picker that shows each theme as a live sample, not a name (LookQuick, PreviewCode, Unfold).
- Both appearances and both Quick Look sizes (Finder preview pane and Space-bar panel) in the marketing and the product (LookQuick, iPreview).
- A companion that opens on a status page with a primary action and a sample (Super Quick Look, Quick Data Insights, FinderPeek).

## Where nobody is good: the opening

These are the dimensions where every cluster report says "not shown" or scores 1–3 for every app. They align with what SpacePane already does on substance, so they are the cheapest route to a visible lead.

| Opening | Evidence | What world-class looks like for us |
|---|---|---|
| Designed limits and states | Zero screenshots of truncation, too-large, encrypted, unsupported, error or empty states in any cluster | A single state view (symbol, title, body, one action) used by Finder and the companion; a bottom limits strip ("Showing the first 5,000 of 12,431 entries"); encrypted entries with a lock and a sentence that says what Quick Look cannot do |
| Privacy in the interface | Only QuickestLook shows masking in the content; data apps show secrets in clear | One row: "3 likely secrets hidden · selection and copying use the hidden text · Copy concealed text", expanding to typed kinds and lines; the masked token drawn as a fixed-width pill only where the classifier fired |
| Discoverable power | Peek alone labels shortcuts; nobody else | A real info button with a popover: read-only, local, provider name, concealed count, and the shortcut sheet; a "Copied" chip; find and filter affordances visible when idle |
| Honest setup | "Quick Look is ready / Enabled" (Super Quick Look), "Active" (Loupe), "Installed Correctly" (FinderPeek) all overclaim; no in-app conflict help | A numbered setup trail with Open System Settings, a neutral (never green) storage state, "Preview by SpacePane" in the preview, and the conflict scan beside step 2 with per-type markers in File Types |
| Consistency across 76 types | One app (GoodQuickLook) has one anatomy | A written preview-anatomy contract and one owner of chrome metrics, so every renderer and every state shares the same strip, fonts, ink and spacing |
| Typed structure | No Quick Look tree has type glyphs, counts and a path bar; no grid has a range footer | Outline rows with SF Symbol type glyphs, "{8 keys}" on collapsed nodes, a trailing type word, a path bar with Copy Path; grids with a dim row gutter, right-aligned numerics, sticky header and "rows 1–200 of 55,991" |
| 3D legibility | No Quick Look 3D preview shows units, parts or camera hints | A floating native control cluster with labelled icons, a dimensions chip with declared units (or "unit not declared"), a one-time "Drag to orbit · Scroll to zoom" hint |
| Accessibility and languages | Not evidenced by any competitor | Keep: contrast-tested schemes, High Contrast, VoiceOver labels; add: labelled mode control in the right order, whole-row targets, 14-language layout proof |

## Patterns to adopt, deduplicated across clusters

Ranked by how many clusters independently recommended them and by the self-audit's impact rating. Each is specified in [decision 026](../decisions/026-world-class-ux-program.md).

1. **One anatomy for every type:** a header facts strip (left) with the mode control (right), content, and a bottom limits strip that collapses when there is nothing to say. Recommended by all five competitor clusters; self-audit P13, P1.
2. **Designed non-content states** (loading with a delayed spinner, unavailable, disabled, settings unavailable, empty), identical in Finder and the companion. Self-audit P1; every cluster's "nobody shows this".
3. **One privacy row** instead of status line + banner rows + button, with a height cap and expansion. Self-audit P2, P3; closest-rivals 3; data 4.
4. **A muted ink tier and a gutter hairline** in every scheme, contrast-tested. Self-audit P4; code cluster 9.
5. **Info button → popover** carrying trust statements, provider name, counts and the shortcut sheet; "Copied" feedback; find/filter affordances visible when idle. Self-audit P7, P11, section 4; code 1 and 6; data 9.
6. **Mode control hygiene:** default first, per-format labels ("Details" rather than "Source" for synthesized summaries), accessibility label, keyboard switching; JSON/YAML/XML open in Outline (owner decision). Self-audit P5, P6, P8; code 3.
7. **Typed outline rows, path bar, quiet grid with range footer, row-action parity between outline, table and tree.** Data 2, 3, 5; self-audit P10, P14.
8. **Folder and archive summary header, hidden-item counts, encrypted states.** Folders 1, 2, 8; breadth 2.
9. **Markdown as reading:** a prose face option, a capped measure, the offline notice only when something was blocked, Contents as a collapsible rail when wide, copy on code blocks. Self-audit P9; code 6, 7; breadth 5.
10. **3D control cluster, dimensions chip with units, camera hint.** Folders 3, 4, 5; self-audit P12.
11. **Companion:** numbered setup trail; neutral storage tone with a first-run "next step" state; conflict scan promoted and reflected per type; Theme live sample pinned with a scheme gallery of live mini-samples; File Types rows with a renderer pill and native search; Try Preview with a "Check this file" inspector; undo for bulk actions; page hierarchy; sidebar material. Self-audit C1–C14; closest 4–8; breadth 3, 6, 10; code 4, 5, 8; data 10; folders 9.
12. **Two densities, explicitly:** compact (Finder preview pane, column view, Spotlight) and full (Space-bar panel), with the chrome collapsing in compact. Breadth 7; system baseline report.
13. **Thumbnails that show shape and counts with a type badge**, within the existing content-thumbnail switch and privacy rule; content-true 3D thumbnails as a separate decision. Data 7; code 10; folders 6, 7.

## Patterns rejected, with the rule that rejects them

- Animated or patterned themes, transparent preview backgrounds (LookQuick): contrast and reduced motion ([decision 003](../decisions/003-preview-appearance.md)).
- Custom CSS themes and web-rendered content (QuickestLook, Peekdown, QLMarkdown's CDN math): no web view for content, inert theme data ([decision 015](../decisions/015-markup-documents.md)).
- Masking every value with identical pills (QuickestLook): findings are typed and selective ([decision 012](../decisions/012-safety-findings.md)).
- "Quick Look is ready", "Enabled", "Active", "Installed Correctly" status wording: the companion reports where settings are saved, never routing (AGENTS, [decision 010](../decisions/010-companion-sidebar-redesign.md)).
- "Reset Quick Look cache", "Restart Finder" actions (Super Quick Look, GoodQuickLook support): prohibited by AGENTS.
- Brand chips inside content (Super Quick Look), watermarks in the viewport (mesh-peek): content first.
- Controlling the Quick Look window size (Unfold 3.2.0 had to fix it): macOS owns the host window.
- A once-per-launch network heartbeat (QuickestLook): the app has no network entitlement.
- Inline full previews of a selected archive member (Super Quick Look): no extraction; listings only ([decision 013](../decisions/013-archive-listings.md)).
- Real cell values in thumbnails (Fast SQLite Viewer, Python Data Viewer): no sensitive content in thumbnails ([decision 022](../decisions/022-content-thumbnails.md)).
- A separate viewer window or a Finder action that bypasses provider choice (LookQuick): single window ([decision 005](../decisions/005-single-window-tabs.md)).

## Open decisions for the owner

These change scope or persisted data, so they are recorded here rather than decided in the program.

1. Should JSON, YAML, TOML and XML open in Outline by default (self-audit P6)? The original design and the data cluster both lead with a tree; the current code opens Source.
2. Is a prose font family for Markdown, notebooks and ebooks worth a schema 7 field (self-audit P9, P16)? Without it, the code face is used for reading text.
3. May the setup trail reveal a bundled sample file in Finder (self-audit C3)? It needs a writable location the sandbox allows; the companion would copy a synthetic sample there on request only.
4. Should 3D content thumbnails be opt-in per CAD type (folders 7)? Geometry is not text, so the privacy rule needs an explicit answer.
5. Should the website's "STEP in a general-purpose app" claim be softened now that Unfold lists STEP previews?

## What this research cannot say

Scores describe what vendors chose to show. An app with no settings screenshot may have a good settings window. Nothing here measures speed, Finder routing or accessibility; the repository's own validation records remain the only evidence for SpacePane's installed behaviour. Recheck before any marketing comparison, and word claims as "no other Quick Look app we found".
