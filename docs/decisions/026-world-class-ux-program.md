# Decision 026: the world-class UX/UI program

Date: 2026-10-06. Status reconciled 2026-10-07: **absorbed into decision 027; implementation in progress, acceptance open**. Researched and planned at the user's request ("implementation is only one part; we must also provide the same features with better UX and UI"). The original proposal below is historical; apply the amendments in [decision 027](027-best-in-class-quality-program.md), which correct ownership, string integration, facts and limits contracts, gates 1, 2, 4, 5 and 11, key handling and overlays. The [continuation plan](../plans/2026-10-07-quality-program-continuation.md) records implemented foundations and the remaining deliverables; an unchecked acceptance box does not mean that no source exists. Research evidence remains in [the competitor analysis](../market/2026-10-06-competitor-ux-ui-analysis.md), its [seven reports](../market/ux-research/) and the [ten-dimension review](../reviews/2026-10-06-quality-review/README.md). Implementation follows disjoint file ownership, agreed shared contracts and lead-owned integration and validation.

## Why a program, not a list of fixes

The research found that SpacePane is level with or ahead of every competitor on substance (bounded, honest, private, typed findings, 76 types, eleven contrast-tested schemes) and behind the leader on presentation in all eight rubric dimensions. The gaps are systemic, not local: there is no shared vocabulary for chrome (no facts strip, no muted ink, no designed states, status said four ways), so every renderer and page expresses the same idea differently. Fixing them one view at a time would reproduce the inconsistency the research criticises in competitors. The program therefore starts with two written contracts, the preview anatomy and the companion page anatomy, and one owner of chrome metrics, then lets workstreams apply them in parallel.

The twelve principles below are the baseline report's, condensed. Each workstream's acceptance gate cites them.

## Principles

1. **Spend chrome like money.** Quick Look's own window draws nothing inside the content. Budget one header row before content, and collapse every strip that has nothing to say.
2. **The host owns the title and the window.** Never repeat the file name, add an "Open with", bind Space, Escape or the arrow keys, or try to size the window.
3. **Lead with facts, then content.** A one-line facts strip for every type; a short verdict list before raw content for archives, packages, databases and secret-bearing files.
4. **One stable, text-only mode control**, default first, five segments at most, hidden with one mode, labelled for VoiceOver, switchable from the keyboard.
5. **Say limits in counted, quiet notation.** "Showing the first 5,000 of 12,431 entries" in the muted tier, inline, never an alert, never colour alone.
6. **Match type to content and bound the measure.** Code gets a quiet gutter; prose gets leading and a narrow measure.
7. **Show something immediately**, and design every non-content state (loading, empty, unavailable, disabled, settings unavailable) as a real view with a symbol, title, body and at most one action.
8. **Make power discoverable.** Every command is in a menu or a visible control, the shortcut sheet is one click away, and every action gives feedback.
9. **Few settings, good defaults, searchable, resettable, undoable.**
10. **Put the live preview beside the control it explains**, and keep it on screen.
11. **Tell people exactly where to enable the extension, and stop there.** Status reports where settings are saved; nothing says or implies that Finder uses this provider; nothing is green until there is a verified signal, and there is none.
12. **Harmonize with macOS 15 and 26 by doing less:** system controls, system materials, no custom bar backgrounds, concentric radii, tested with Reduce Transparency, Increase Contrast and Reduce Motion.

## Contract 1: preview anatomy (Finder extension and companion Try Preview)

One `NativePreviewView` serves every format, so the anatomy is a renderer contract, not a per-format choice. Measurements are the design target; `PreviewChrome` (new, in `PreviewRenderers`) is their single owner, as `CompanionMetrics` is for the companion.

```
┌ header row (26–28 pt) ─────────────────────────────────────────────────────┐
│ facts strip (11 pt, muted ink)                [Outline | Source]   (i)   │
│  "UTF-8 · 1,204 lines · 38 KB"                                            │
├ privacy row (one line, only when findings exist; expands on click) ───────┤
│  ⚠ 3 likely secrets hidden · selection and copying use the hidden text    │
│    [Show details] [Copy concealed text]                                    │
├ accessory bar (30 pt, only while open: filter, Go to Line) ───────────────┤
├ content ──────────────────────────────────────────────────────────────────┤
│  gutter (muted, hairline) │ text / outline / table / tree / document /    │
│                           │ viewport                                      │
├ limits strip (one line, muted, only when bounded) ────────────────────────┤
│  "Showing the first 20,000 lines · limit 2 MB"                             │
└───────────────────────────────────────────────────────────────────────────┘
```

Rules:

- **Facts strip.** Derived from fields the presentations already carry (`TextPresentation.lineCount`, `byteCount`, `encoding`, `redactionCount`; table rows × columns; outline node counts; listing entry counts and totals; geometry faces, bodies and dimensions). Locale-formatted; never a source value; at most four facts, middle-truncated when narrow. Replaces the bottom summary line in the geometry view and the counts hidden in accessibility labels.
- **Mode control.** Default mode first; labels per format ("Details" replaces "Source" where the text is an app-made summary; "Source" stays for exact safe text); accessibility label "View mode"; Command-Option-1…n switches; the control precedes the content in the accessibility order.
- **Info button.** A real `NSButton` with `info.circle`, opening a popover: read-only, processed on this Mac, "Preview by %@", concealed-value count, and the shortcut sheet for the current mode. The severity "info" glyph in findings changes so the symbol has one meaning.
- **Privacy row.** One line replaces the privacy status line, the findings banner rows and the sync-folder row. Expanded, it lists typed kinds, counts and lines, capped at 25 % of the view height with internal scrolling. The sentence about selection and copying stays as text because it changes what copying returns ([decision 021](021-preview-interaction-and-live-reload.md), amended 2026-10-06).
- **Ink tiers.** Every scheme gains `muted` (and the palette test requires at least 4.5:1 against the scheme background, like every role) and a hairline colour. Facts, limits, gutter numbers, filter counts and placeholder text use `muted`; a 1 px hairline separates the gutter.
- **States.** One `NativeStateView` (28 pt symbol, 15 pt semibold title, 13 pt body, one optional action) for loading (spinner after 300 ms), empty, unavailable (each `failure.*` split into title and body, body ending with the next step and the limit value where one applies), disabled and settings unavailable. The companion's Try Preview and Theme sample use the same view.
- **Limits strip.** One sentence from `PresentationNotices`, the same place for text, table, outline, tree, listing and geometry. It replaces the notices that today sit inside the table and listing views.
- **Feedback.** Copy of any kind shows a "Copied" chip beside the info button for about 1.5 s (no motion under Reduce Motion) and announces to VoiceOver.
- **Two densities.** Below a width threshold (compact: Finder preview pane, column view, Spotlight) the facts strip keeps two facts, the gutter hides, document rails hide and the mode control may become a pull-down. The threshold is measured in real hosts first.
- **Not allowed.** A second title, a brand chip, a custom accent, custom glass or bar backgrounds, overlays that cover content, more than one line of chrome when nothing needs saying.
- **Amended 2026-10-06 by decision 027.** Principle 2 is scoped: Space and Escape are never bound; arrow keys may act only inside a focused table, outline, page column, canvas or viewport, as listed in the shortcut sheet. A floating control group over the 3D viewport and a code-block copy button in the margin are accepted exceptions to the overlay rule; dimensions appear in the facts strip and not in a chip as well. The renderer pill of contract 2 comes from a `primaryView` catalog field with a drift test; the scheme gallery is twelve swatch tiles drawn from palette tokens; page titles use the `title2` text style; the storage card also appears for failed-save and recovered states; Command-comma keeps the standard "Settings…" title and selects General.

## Contract 2: companion page anatomy

The single window and fixed sidebar stay ([decisions 005](005-single-window-tabs.md) and [010](010-companion-sidebar-redesign.md)). Within them:

- **Hierarchy.** Page title 20 pt semibold, section headings 13 pt semibold, rows 13 pt, hints 11 pt secondary (never 10 pt). The sidebar uses the system sidebar material and the accent-coloured symbols of the destinations; About uses `info.circle`.
- **Status.** Storage state has one home, the sidebar footer, in a neutral tone; the General header pill and the duplicated storage card go; the storage card appears only in the private-only and unavailable states. Green is not used for any state the app cannot verify.
- **General** becomes a setup trail: a numbered card (1 Open System Settings → General → Login Items & Extensions → Quick Look, with the button; 2 turn SpacePane's preview and thumbnail entries on and click Done; 3 select a file in Finder and press Space), followed by "If a preview looks different, another app may be handling that type" with the conflict scan beside it. Behaviour switches, folder options and limits stay below. Developer Mode moves to the end.
- **File Types** rows gain a renderer pill ("Outline", "Table", "Files", "3D"…) from the catalog's presentation, a native search field with Command-F, conflict markers after a scan ("may be handled by another app"), and Undo for Enable All, Disable All and Reset.
- **Theme** pins the live sample: the sample column stays fixed while the controls scroll; below the stacking breakpoint the sample sits on top. A scheme gallery of live mini-samples (light and dark side by side, selected ring and check) replaces the two pop-ups; typography and syntax styles follow; a one-line note states that Finder previews use the saved settings when they next open. Reset Appearance and profile deletion get Undo.
- **Try Preview** (Developer Mode) makes the pane the drop target with one Open File button, and adds a "Check this file" card after a drop: extension, resolved type, catalog format, enabled or disabled, renderer, concealed count. Wording: "Supported by SpacePane", never "Finder uses SpacePane".
- **Menus.** Command-comma is labelled by its destination; Help opens About's help section.

## Workstreams and file ownership

Shared contracts the lead adds before parallel work (one commit, no workstream edits them afterwards): `PreviewChrome` metrics; `muted` and `hairline` in `NativeTextPalette`/`NativeColorSchemes` with the contrast test; `NativeStateView`; a `PresentationFacts` value computed in `PreviewRenderers` from existing presentation fields; the facts/limits strip slots in `NativePreviewView`; `PreviewStrings` keys for the shared wording, added in all 14 languages with `tools/add_localizations.py`; marker comments (`// [ux-<workstream>]`) at the shared registration points. Each workstream adds strings only below its own marker in the string files, as in decision 025.

**Amended 2026-10-06 by decision 027.** `PresentationFacts` is a typed, value-free contract in a UI-free module, filled by adapters or family providers and never derived from `lineCount`, `byteCount` or `encoding` for non-text families, so thumbnails can share it; `TextPresentation.origin` (`TextOrigin`) says whether the text is the file's own, reformatted, converted or an app-made summary, and the "Details" and "Text" labels follow from it. A `PreviewResult` carrying the effective budget replaces "limit values from the presentation", and `tooLarge`, `structureLimit` and `lineLimit` split into one key per limit. The shared-contract list also includes `unsupportedVariant`, `GeometryUnitProvenance`, `OmittedResources`, the counted string API, the announcer, the copy callback, the command table, the chrome scheduler, the worker executor and thumbnail admission, the completion policy and the host events. Strings: the marker rule cannot apply to the JSON catalogs; each workstream commits only `tools/localization/additions/<workstream>.json` plus its `PreviewStrings.swift` cases below its marker, and the lead applies the additions and regenerates the catalogs at integration.

| Workstream | Owns | Delivers | Principles |
|---|---|---|---|
| **ux-chrome** | `PreviewRenderers/NativePreviewView.swift`, `NativePreviewView+Interaction.swift`, `Interaction/PreviewInfoBadge.swift`, `Interaction/PreviewAccessoryBar.swift`, `Findings/*`, `PresentationNotices.swift`, `LogicalLineNumberGutter.swift` | Facts strip, limits strip, privacy row, info popover with shortcut sheet, Copied chip, gutter hairline, compact density, accessibility order | 1, 3, 5, 7, 8 |
| **ux-modes-structure** | `SafePreviewModes.swift`, `NativeOutlinePreviewView.swift`, `NativeTablePreviewView.swift`, `Interaction/OutlinePath.swift`, `Interaction/OutlineFilterBar.swift`, `Listings/NativeListingFilesView.swift`, `Listings/NativeListingTreeView.swift` | Default-first ordering and per-format labels, keyboard mode switching, type glyphs and counts on outline rows, path bar, quiet grid with range footer, row-action and filter parity, tooltips for truncated values, JSONL record separators | 4, 5, 6 |
| **ux-documents** | `NativeMarkdownStyling.swift`, `Markup/*`, `SafeMarkdownDocument.swift`, `SafeNotebookDocument.swift`, `Images/*` | Prose face (if approved), capped measure, Contents as a collapsible rail when wide, offline notice only when a resource was blocked, copy on code blocks, blockquote bar | 6, 8 |
| **ux-containers-3d** | `Listings/SafeListing*.swift`, `SafeSchemaLabels+Archives.swift`, `+Containers.swift`, `NativeGeometryPreviewView.swift`, `GeometryCamera.swift`, `NativeMIDIPreviewView.swift` | Summary header and hidden-item counts for folders and archives, encrypted and unreadable states, native floating 3D control cluster with labelled icons, dimensions chip with declared units, one-time camera hint, MIDI strip tidy-up | 3, 5, 8 |
| **ux-companion** | `Apps/PrevApp/Views/*`, `Apps/PrevApp/Views/Components/*`, `Apps/PrevApp/Models/CompanionRoute.swift`, `Apps/PrevApp/App/CompanionApp.swift` | Contract 2 in full: hierarchy, neutral status, setup trail, conflict markers, pinned sample, scheme gallery, renderer pills, native search, Undo, Try Preview inspector, menu labels | 9, 10, 11, 12 |
| **ux-copy** | `PreviewRenderers/PreviewStrings.swift`, `Resources/*.xcstrings` (shared with the others by marker), `tools/localization/translations/*` | Title/body split for every failure, next-step clauses with budget values, apostrophe and length sweep (header strings ≤ 12 words), jargon removal in Summary labels, 14-language drafts | 5, 7, 11 |
| **ux-thumbnails** | `PreviewThumbnails/*` | Type badge and shape-with-counts rendering within the existing content switch and privacy rule; 3D thumbnails only after the owner's decision | 3 |

Lead: contracts, integration, `--check`/`--check-compiler`/`--test`, signed build, real-window and Finder observation, the changelog and the plan. No workstream edits `CHANGELOGS.md`, `PLAN.md`, `PreviewContracts` or another workstream's files; a needed contract change is a request to the lead.

**Ownership amended 2026-10-06 by decision 027** (`tools/ownership.json` is the enforced table): `Interaction/PreviewShortcut.swift`, `SafeStructuredText.swift` and `Data/SafeDataPresentation.swift` go to ux-modes-structure; `NativePreviewPane.swift` and both extension hosts to the lead; `Apps/PrevApp/Stores/*`, `Models/*`, `Support/*`, the companion integration checks and `script/test_companion_models.py` to ux-companion; `PreviewThumbnails/*`, `Extensions/PrevThumbnailExtension/ThumbnailProvider.swift` and `script/probe_thumbnail.swift` to ux-thumbnails; the listing models and views together to ux-containers-3d, with `GeometryMetalRenderer.swift` and `NativeMIDIPlayback.swift`; `PreviewFormats/Documents/*` (text-producing lines) to ux-documents; `Diagrams/*`, `Data/NativePlotPreviewView.swift` and `SafeSubtitleCues.swift` as decision 027's backlog names them. Existing test files stay with the lead; each workstream adds its tests in new files named for it.

## Acceptance gates

Measured, not asserted. Each is checked in the signed companion and in Finder's Space-bar panel and preview pane; the preview pane counts as the compact density.

1. For any format without findings, chrome above the content is one row (≤ 28 pt) and the limits strip appears only when the preview is bounded.
2. Every non-content state renders through `NativeStateView` with a symbol, title, body and at most one action, identically in Finder and the companion; loading shows a spinner after 300 ms and never a bare caption.
3. A file with findings shows one privacy row; expanded, the row never exceeds 25 % of the view height; the same fact is never stated twice on screen.
4. `muted` and `hairline` exist in all eleven schemes and both high-contrast palettes, and the independent contrast test passes at 4.5:1 (7:1 for high contrast) for `muted` text.
5. Every shortcut and context-menu action in the self-audit's discoverability table is listed in the info popover for the modes where it applies, and copy of any kind shows the Copied chip.
6. The mode control carries an accessibility label, precedes the content in the accessibility order, opens on the format's default mode as the first segment, and never labels an app-made summary "Source".
7. The companion shows the storage state in one place, in a neutral tone; no green appears for an unverified state; the setup trail's three steps and the conflict help are visible on General without scrolling at the default window size.
8. The Theme live sample stays on screen while any control is edited at every width from the minimum window up.
9. Disable All, Reset File Type Choices, Reset Appearance and profile deletion can be undone.
10. All new strings exist in 14 languages with translator context; German, Russian and Bengali layouts are checked at the minimum width and at 200 % content size; VoiceOver reads the facts strip, privacy row, mode control, state views and the setup trail in order.
11. Release warm p95 for text, JSON and CSV first content does not regress against [the native renderer benchmark](../validation/native-renderer-performance-2026-10-04.md) by more than 10 ms; the chrome adds no source I/O.
12. Nothing claims Finder routing, nothing resizes the host window, nothing adds a window, and every string stays honest about limits.

**Gates amended 2026-10-06 by decision 027.** Gate 1 counts always-visible filter bars, the MIDI strip and the 3D button rows against the one-row budget, so filters open on demand behind a visible affordance. Gate 2 depends on the completion-handler policy chosen after the Wave 1 experiment; until then it reads "the companion shows the state view; Finder shows whichever state the policy selects". Gate 4 adds that `muted` differs from the foreground by at least 1.25:1 wherever the scheme has 7:1 headroom, with Solarized Light, Solarized Dark and One Dark accepting a muted tier equal to the foreground with a size cue, and a decorative hairline at 1.3:1 (3:1 in High Contrast). Gate 5 gets an inline fallback, an in-view info panel that pushes content down, with the popover optional until the remote-view spike succeeds. Gate 11 is rewritten: a re-baselined benchmark with CSV, listing, Markdown-with-Contents, `.env`-with-findings and 1 MiB cases, interleaved A/B comparison of medians with a 95 % bootstrap interval, a regression bound of max(10 ms, 5 %), p95 and maximum reported beside it, and physical footprint instead of resident size. Gates G13 to G20 of decision 027 apply as well, and the validation hosts are macOS 15, macOS 26 and the current release.

## What is not promised

- That Finder delivers key events, tooltips or popovers to the extension view, or keeps the extension alive; each is observed, not assumed.
- That a compact density threshold can be chosen without measuring real pane widths on macOS 15 and 26.
- That translated wording is native quality; drafts stay drafts until reviewed.
- Content-true 3D thumbnails, a prose font field, JSON opening in Outline, or a sample reveal in Finder, until the owner decides the five questions in the analysis.

## Rejected

Animated or patterned themes, custom CSS, web-rendered content, masking every value, status wording such as "ready", "enabled" or "active", cache resets or Finder restarts, brand chips or watermarks in content, controlling the Quick Look window size, a network heartbeat, inline extraction of archive members, real cell values in thumbnails, and any second window. Each is tied to an existing rule in [the analysis](../market/2026-10-06-competitor-ux-ui-analysis.md#patterns-rejected-with-the-rule-that-rejects-them).
