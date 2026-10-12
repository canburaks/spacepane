# SpacePane UX/UI self-audit (code-level)

Audited 2026-10-06 from source only. Nothing was built, launched or measured. Sizes are the values coded; where a size comes from a system text style it uses the macOS defaults (caption1/footnote 10 pt, subheadline 11, callout 12, body/headline 13, title2 17). Pixel heights are arithmetic from layout constants, not screenshots. Finder-hosted behavior (tooltips, key routing, VoiceOver order) is unverified in the repo's own records (`docs/validation/interaction-2026-10-05.md:37`, `companion-redesign-2026-10-04.md` "Not verified"), so those findings say "verify".

Severity: 0 none, 1 cosmetic, 2 minor, 3 major, 4 blocker. "Rule" = whether the fix touches a product rule (single window, localization, honesty wording, privacy). Paths are relative to the repo root; `PR` = `Packages/PreviewCore/Sources/PreviewRenderers`, `APP` = `Apps/PrevApp/Views`.

## Headline

The safety, privacy and honesty engineering is ahead of the visual communication. Wording is careful, but it is rendered as 10 pt full-ink captions, a tooltip glyph and green ticks. The preview chrome has no spare hierarchy tier (no muted ink), no metadata strip, and no designed non-content states. The companion has the right structure but repeats one status four times, says "success" in green about a thing it cannot verify, and hides the one useful live feedback (the Theme sample) below the fold.

---

## 1. What the user actually sees

### 1a. Preview surface (one `NativePreviewView`, used by Finder and the companion)

Container: Finder host view starts 800x600 (`Extensions/PrevPreviewExtension/PreviewViewController.swift:23`), `hostManaged` visibility. Background is the scheme palette background (`NativePreviewView.swift:513`). There is no file name, size, encoding or line count anywhere in the header; the Quick Look title bar carries the name, and the companion draws its own name above the pane (`APP/DirectPreviewView.swift:20-25`).

Header, top to bottom (all x-inset 12):

| Row | Coded size/spacing | Source |
|---|---|---|
| Status line | caption1 10 pt, wrapping, **full foreground ink** (not secondary), top 10; collapses to 0 when empty and a mode control exists | `NativePreviewView.swift:90,156,503,514,591-601` |
| Info badge | 16x16 `info.circle`, 13 pt symbol, trailing 12, full ink; tooltip only; sits on the mode-control row, else on the status row (forcing a 26 pt row for one icon) | `Interaction/PreviewInfoBadge.swift:8,25-35`; `NativePreviewView.swift:158-166,520-524` |
| Findings banner | top 8; each row = symbol + callout 12 pt message + optional caption 10 detail; row gap 6; max 6 rows then "More findings: n"; then small push button "Copy Concealed Text" + confirmation caption; **no max height, no scroll, no collapse** | `Findings/NativeFindingsBanner.swift:11,46,116-139,76-85` |
| Mode control | `NSSegmentedControl` default style, 26 pt, top gap 8; hidden (and gap 0) with one mode; no accessibility label | `NativePreviewView.swift:128-145,603-615` |
| MIDI strip | 90 pt: rounded "Play" button, slider, `0:00 / 1:23` (small digits), static line "Playback starts only when you press Play." in system secondary | `NativeMIDIPreviewView.swift:16-35,29-30`; `NativePreviewView.swift:193,309` |
| Accessory bar | 8 pt gap always, then 30 pt only for outline filter or Go to Line | `PreviewAccessoryBar.swift:9`; `NativePreviewView.swift:172` |

Chrome before content, by arithmetic: plain text with no notices = 10 + 16 + 8 = 34 pt, then a 12 pt text inset. JSON with modes and no notices = 8 + 26 + 8 = 42 pt. A `.env` file with four secret kinds = about 190 pt (status 2 lines, 4 finding rows, Copy button, mode row), i.e. about 48 % of a 400 pt tall window.

Defaults for content: 13 pt system monospaced, wrap on, line numbers off, line spacing 0, tab 4 (`PreviewContracts/Preferences.swift:30-33`). Gutter width = digits x digit width + 16, drawn in full foreground, no separator (`LogicalLineNumberGutter.swift:52-57,97`). Chrome and content share one ink because `NativeTextPalette` only has background, foreground and twelve roles (`NativeTextAppearance.swift:9-14`).

Wireframes (not to scale):

```
Text/code file, no modes, no notices            JSON / YAML / XML (opens in SOURCE, see P6)
+--------------------------------------+        +--------------------------------------+
|                                  (i) |  26pt  | [Source|Outline]                 (i) |  26pt
|  1  struct Example {                 |        |  { "name": "x", "items": [ ...       |
|  2      let value = "..."            |        |  (switch to Outline: Key 220|Value 380,
+--------------------------------------+        |   alt rows, 24 pt rows, ellipsized)  |
 gutter only if enabled (default off)            |  filter bar 30pt appears ONLY here  |
```
```
CSV / TSV                                       ZIP / folder (default Files)
[Source|Table|Profile]                (i)       [Source|Summary|Files|Tree]           (i)
[Filter........] 3 of 120 rows [Sort v]         [Filter........] [Sort v]
 Name | Age | City   (sortable, 56-360 wide)     Name | Kind | Size | Modified (mono font)
 alt rows, 12 pt cell gap, tooltips >24 B        partial notice sits INSIDE the table view
 notice "This table is shortened..." (10pt)      Tree: Name 320|Items|Size|Modified, SF icons
```
```
Markdown (opens RENDERED)                        MIDI                    STEP / IGES (geometry)
Offline preview. External resources are         [Source|Summary] (i)    3D geometry is shown as stored.
not loaded.   <- on every Rendered doc          [Play] ====o==== 0:12/1:05   Document metadata is omitted. (10pt, top)
[Source|Rendered|Contents]            (i)       Playback starts only when   [Fit Model][Reset View][+][-]
# Heading (system bold 1.7x)                    you press Play.             [Front][Side][Top]  (2 rows ~50pt)
body text in the MONO code face, full width      summary JSON below          ( Metal viewport )
                                                                             Faces: n · Triangles: n · a x b x c mm (bottom)
```
States (all 10 pt caption, top-left, over an empty text view; no icon, no spinner, no action):
```
Loading     "Preparing preview..."                          (NativePreviewView.swift:246, key preview.loading)
Unavailable "The source file could not be read."  etc.       (:335-339, failure.* keys, one sentence each)
Disabled    status "This file type is disabled" (10pt)  +  body "Enable this file type in the companion app's
            File Types settings..." in the 13 pt MONOSPACED content font   (:330-334)  -> title smaller than body
Settings    "Shared extension settings are unavailable. Open the companion app..." (:250-256, 2-3 sentences)
Findings    status privacy line + banner rows + [Copy Concealed Text]  (can stack 3 messages for one fact, see P3)
```
Interaction chrome: Go to Line = 30 pt bar, "Go to Line" callout + 96 pt number field + range/error caption + close (`Interaction/GoToLineBar.swift:27-60`); outline filter = `NSSearchField` 140-280 pt + "Matches: n" (`OutlineFilterBar.swift:33-41`); zoom adds a status line "Temporary zoom: 120%. Press Cmd-0 to reset." (`NativePreviewView+Interaction.swift:36-49`).

### 1b. Companion (one window, hidden title bar, default 1040x720, min 820x560: `CompanionApp.swift:26-27`, `CompanionShell.swift:41`)

Frame: 224 pt opaque sidebar (`windowBackgroundColor`, not vibrant), 1 pt divider, page on `textBackgroundColor` (`CompanionStyle.swift:14,33-35`). Page header: 13 pt semibold title, 13 pt secondary subtitle, optional trailing accessory, padding 24/18/14, divider; content padding 24; cards 10 pt radius, 4 % fill, 9 % border, rows 10 pt padding (`CompanionPage.swift:22-50`, `SettingsCard.swift:55-60`). Two columns only when content >= 620 pt (Theme 720), so the minimum window (content 547) is single-column.

```
Sidebar (224)                          Sidebar contents (CompanionSidebar.swift)
[icon 34] SpacePane                     General        slider.horizontal.3
          Quick Look Extension (11pt)   File Types     doc.badge.gearshape
 > General                              Theme          paintbrush
   File Types                           About          questionmark.circle  <- "?" for About
   Theme                                (Developer) Try Preview   only if Developer Mode
   About                                footer: green dot "Settings shared" / "Enabled file types: 76"
```

General (`APP/GeneralView.swift`): header "General" + pill "Settings shared" (green). Content: banner card (40 pt tinted icon, headline 13 "Settings are shared with the Quick Look extensions", body, [Open System Settings]); two columns: left = "Finder & Quick Look" (row "Turn on the extensions" with a 30-word paragraph and **no control**; switch "Preview folders"; caption "macOS chooses which app...") / "Previews" (2 switches) / "Folder previews" (stepper "Levels: 1", switch) / "Developer" (switch). Right = "Text preview limits" (3 read-only values + footnote), "Settings storage" (3-4 text lines). Below both: "Quick Look conflicts" card (Scan Applications button, results, guidance paragraph).

File Types (`FileTypeSettingsView.swift`): header "File Types" + pill "n of 76 enabled" (blue). Control row: custom 260 pt search box + [Enable All Types][Disable All Types][Reset File Type Choices] (small bordered). Scope captions only while searching. Table card: caption header "FORMAT GROUPS AND TYPES ... PREVIEWS", then per group a 5 % tinted bar [chevron][tri-state checkbox][group name 13 bold][n of m enabled][...][status word "Enabled/Partially enabled/Disabled"], then an adaptive 190 pt grid of checkbox cells (name, optional "Off by default" capsule, 10 pt filename patterns, 2 lines max); footer with the refresh notice in a 10 pt caption.

Theme (`AppearanceSettingsView.swift`): header + "Reset Appearance" link button. Left (46 %): cards Appearance (Color mode: label, current value as subtitle, 4-segment picker), Color scheme (light/dark menus + 3-line note), Typography (family menu, size stepper, weight menu, italic checkbox, fallback note), Text layout (wrap/line-number checkboxes, line spacing/char spacing/tab width steppers, ligatures checkbox), Syntax styles (use-colors checkbox, disclosure with 12 roles x bold/italic checkboxes, hint). Right: "Live Preview / Updates as you edit": fake window frame (three grey dots, file name, type menu), real native pane min 300 / ideal 380 pt, status strip "13.00 pt · Tab width: 4"; then Profiles card (name field + Save, link-styled profile rows with Delete, Import/Export links, two hint captions).

About (`AboutView.swift`): title "About SpacePane"; left card (72 pt icon, name 17 semibold, version, description), Acknowledgements; right "How it works" (about 60 words), Privacy, optional Resources links.

Try Preview (Developer Mode only, `DirectPreviewView.swift`): header with subtitle = the empty-state description + [Open File...]; dashed 52 pt drop area "Drop one local file here"; file name (13 semibold, selectable); the pane with its own empty state "Choose a file to preview" + second [Open File...].

---

## 2. Heuristic evaluation

Format: **ID (sev) title** - location. Experience / Why / Fix / Rule.

### Preview surface

**P1 (3) Loading, error, disabled and settings-unavailable states are a 10 pt caption over a blank page** - `NativePreviewView.swift:90,246-248,330-339,459-477,503,514`; `PreviewStrings` `failure.*`, `preview.loading`, `preview.disabled*`.
Experience: a tiny top-left sentence and an empty canvas. Disabled inverts hierarchy: title 10 pt, body 13 pt monospaced. Loading has no spinner in Finder, while the companion shows a `ProgressView` (`APP/DirectPreviewView.swift:41-43`). Why: Nielsen 1 and 9 (status, error recovery); HIG Feedback; doc 05 promised "name the problem, one useful next step". Fix: one shared centered state view (28 pt symbol, 15 pt semibold title, 12 pt body, optional hint), spinner after about 300 ms, same view in both hosts. Rule: honesty wording kept verbatim; localization needs a title/body split for each `failure.*` key x 14 languages.

**P2 (3) Findings banner has unbounded height** - `Findings/NativeFindingsBanner.swift:11,46-48,116-139`. Up to 6 two-line rows plus a button push content down roughly 100-150 pt; no collapse, scroll or dismiss. Why: HIG layout (content first), Nielsen 8. Fix: show a one-line summary row ("3 things to check, most serious: warning") that expands on click; cap expanded height at about 25 % with internal scroll; keep severity-first order and the `Copy Concealed Text` action inside. Rule: none (findings stay visible by default).

**P3 (3) A concealed secret is announced three times** - status privacy line (`NativePreviewView.swift:320`, `preview.privacyNotice`), finding rows ("API keys concealed: 3", `finding.secret.*`), and the Copy button; the sync-folder row adds a fourth. Why: noise trains users to ignore the header, Nielsen 8. Fix: one row: "3 likely secrets hidden. Selecting and copying use the hidden text. [Copy concealed text]" with kinds in the expanded detail. Rule: privacy, the "selection and copying use concealed content" meaning must survive (it is the reason the notice was kept as text, decision 021 amendment).

**P4 (3) No muted ink tier: chrome, gutter and content are the same weight** - `NativeTextAppearance.swift:9-14`, `LogicalLineNumberGutter.swift:44,97`, `OutlineFilterBar.swift:61` (alpha 0.75), `GoToLineBar.swift:109`, `NativePreviewView.swift:503,514`. 10 pt status text and line numbers use full foreground; no hairline between gutter and text. Why: no hierarchy, HIG color/typography; line numbers compete with code. Fix: add `muted` to the palette per scheme (>= 4.5:1, reuse the `ColorSchemeContrastTests` method), dim gutter and status, add a 1 px separator. Rule: none.

**P5 (3) Mode vocabulary misleads and ordering ignores the default** - `SafePreviewModes.swift:31-59,97-148`. "Source" is always segment 1 even when another mode is the default (ZIP/folder open on Files, segment 3 of Source|Summary|Files|Tree; Markdown opens on Rendered, segment 2). For containers, SQLite, MIDI and packages "Source" is an app-made JSON summary, and "Summary"/"Outline" vs "Tree" are three overlapping hierarchies. Why: Nielsen 2 (match real world), 4. Fix: order the default first or visually mark it; per-format labels ("Details" instead of "Source" for synthesized text); hide the JSON-ish summary behind Files/Tree for listings. Rule: localization x 14; "Source = exact safe text" remains for real text formats.

**P6 (2) JSON/YAML/TOML/XML open in Source, not Outline** - `SafePreviewModes.swift:129-148` has no rule returning `.outline`. Doc 05 listed the outline as JSON's first useful view and the competitor set leads with a tree. Verify against the Finder matrix; if intentional, say why. Rule: none.

**P7 (2) The trust affordance is a tooltip on a button-looking glyph** - `PreviewInfoBadge.swift:8,25-35`. 16 pt full-ink `info.circle`, an `NSImageView` (not a control), tooltip "Read-only preview / Preview by X". Looks clickable, does nothing; the only on-surface statement of "local, read-only" needs a hover (and tooltip delivery inside Quick Look is unverified). The same symbol means severity "info" in findings (`NativeFindingsBanner.swift:157`). Fix: make it a real button opening a small popover: read-only, local, provider name, concealed-value count, and the shortcut cheat sheet (also fixes section 4). Use a different glyph for severity info. Rule: honesty, keep "Preview by %@" and never claim Finder routing.

**P8 (2) Mode control and filter bar come after the content in the accessibility/Tab order, and the control is unlabeled** - subviews added in the order status, badge, banner, gutter, scroll view (`NativePreviewView.swift:120-127`) then mode control, outline, table, MIDI, accessory bar (`:147-152`); no `setAccessibilityLabel` on `modeControl` (`:128-140`). Verify with VoiceOver. Why: Nielsen 7, HIG accessibility. Fix: override `accessibilityChildren` / reorder `addSubview`, label "View mode", add Cmd-Option-number shortcuts. Rule: none.

**P9 (2) Rendered Markdown: code face for prose, unlimited measure, permanent offline notice** - body uses `typography.font` (`NativeMarkdownStyling.swift:27-31`, headings are system bold at 1.7x), text container spans the full width (`NativePreviewView.swift:676`), and "Offline preview. External resources are not loaded." is appended to every Rendered view (`:322`, `preview.markdown.localOnly`). Fix: prose face option (doc 05 had a Prose family), cap measure near 80 characters centered, show the notice only when a resource was actually blocked (else info popover). Rule: honesty satisfied, wording stays when it applies.

**P10 (2) Ellipsized outline values can't be read** - `NativeOutlinePreviewView.swift:150-153` tooltip only for duplicate keys; tables tooltip anything over 24 bytes (`NativeTablePreviewView.swift:22,218-219`). Fix: same rule in the outline (concealed text only). Rule: privacy, tooltip from concealed node only.

**P11 (2) Copy gives no visible confirmation** - outline copy writes silently (`NativeOutlinePreviewView.swift:354-359`), Copy All only announces to VoiceOver (`NativePreviewView+Interaction.swift:137,240-247`); only Copy Concealed has an inline label (`NativeFindingsBanner.swift:99-104`). Strings also differ: "Copied to the clipboard" vs "Concealed text copied." Fix: a 1.5 s inline "Copied" chip by the badge, honoring Reduce Motion. Rule: none.

**P12 (2) 3D controls and notices are scattered** - two rows of mixed text/icon rounded buttons above the viewport (`NativeGeometryPreviewView.swift:47-63`, `fillEqually`), orbit/pan help only as a viewport tooltip (`:274`), notice at the top (10 pt) but model summary at the bottom (`:66,84-86`). Fix: compact floating toolbar on the viewport, first-use hint "Drag to orbit, scroll to zoom", summary in the header. Rule: none.

**P13 (3) No file summary strip** - doc 05 "Finder content design" requires a compact summary (kind, encoding, metadata) and "Showing the first N lines" in the same place. The code shows none of byte size, line count, encoding, CSV rows x columns (only in accessibility labels, `NativeTablePreviewView.swift:421-425`) or JSON counts. Users cannot answer "is this the whole file, which encoding, how many rows". Fix: one 11 pt muted line in the header ("UTF-8 · 1,204 lines · 38 KB", "1,000 rows x 12 columns · truncated") fed from existing presentation fields. Rule: localization (locale-formatted numbers); honesty (state truncation here).

**P14 (2) Table/outline/tree parity gaps** - table has no row/cell context menu (outline has Copy Value/Key/Path: `NativeOutlinePreviewView.swift:318-334`, table has none in `NativeTablePreviewView.swift`); Files table has no icons while Tree has (`NativeListingTreeView.swift:211`); Tree has no filter or Sort while Files has; Tree column "Items" vs Files "Kind". Fix: shared row-action menu, icons in both, filter in both. Rule: privacy (copy concealed cells only).

**P15 (2) Failure copy names the cause but not the next step** - `failure.tooLarge` ("The file exceeds this preview's size limit.") omits the number (shown only in General), `failure.missingFile` says "source file", `failure.deadlineExceeded` and `failure.binary` give nothing to do. Mixed apostrophes: straight in `failure.unsupported`, `setup.notConfigured`, curly elsewhere. Fix: add a short clause ("Limit: 2 MB. Open the file in an editor.") using values from `PreviewBudget`. Rule: honesty; localization.

**P16 (1) Default look is dense** - wrap on, line spacing 0, mono 13, 12 pt inset, line numbers off (`Preferences.swift:30-33`); `appearance.pointValue` renders "13.00 pt". Fix: 2 pt default spacing, drop decimals for integers. Rule: persisted defaults need a migration decision (schema 6).

**P17 (1) MIDI strip** - static "Playback starts only when you press Play." line (`NativeMIDIPreviewView.swift:29-30`) and system-secondary ink not palette (`:29`), text "Play" button. Fix: move the sentence to the Play button help; use palette ink. Rule: honesty satisfied by help.

### Companion

**C1 (3) The live sample leaves the screen while you edit** - controls column about 17 rows tall, sample first in the trailing column, whole page one `ScrollView` (`APP/AppearanceSettingsView.swift:19`, `Components/CompanionPage.swift:37-42`); columns stack below 720 pt content (`:19`), so at the 820 pt minimum the sample is under every control. Why: Nielsen 1; the page exists to preview. Fix: `scrolls: false`, controls scroll left, sample pinned right (stack: sample on top, controls scroll below). Rule: none.

**C2 (3) Green success shown for something the app cannot verify** - banner green check "Settings are shared with the Quick Look extensions" (`GeneralView.swift:127-129`), green pill (`:15`), green sidebar dot (`CompanionSidebar.swift:67-69`), tone `.positive` (`StorageModePresentation.swift:16`). At first launch the page is green though extensions are probably not enabled. Words are honest (storage only); color says "all set". Fix: informational (accent/neutral) tone for storage, a distinct "next step" state until the user acts, green never (there is no verification signal). Rule: honesty, this reinforces it.

**C3 (3) Setup is a paragraph, not a path** - one row "Turn on the extensions" with a 30-word sentence and no control (`GeneralView.swift:32`, `setup.steps`), the button lives in a different card (`:90-107`), the System Settings path stops at "Login Items & Extensions" (no Quick Look hop, deep link unverified `:154-156`), no numbered steps, no "show me a sample" action (Try Preview sits behind Developer Mode, `CompanionRoute.swift:9`). Fix: 3-step card: (1) Open System Settings [button], (2) turn on SpacePane under Quick Look, (3) select a file in Finder, press Space [Reveal sample file]; steps are never ticked off. Rule: honesty; single window ok; a bundled sample reveal must respect the sandbox.

**C4 (2) One fact, four places** - sidebar footer (`CompanionSidebar.swift:66-85`), header pill (`GeneralView.swift:15`), banner (`:90-107`), storage card with up to four lines including the same refresh sentence as the File Types footer (`SettingsStorageStatusView.swift:10-28`, `FileTypeSettingsView.swift:141`). Fix: keep the sidebar chip; show the storage card only on problems; one refresh note. Rule: honesty wording kept.

**C5 (2) Weak hierarchy** - page title headline 13 semibold (`CompanionPage.swift:26`) equals section headings (13 regular, `SettingsCard.swift:18`) and row titles; About repeats the name in sidebar, title and card (`AboutView.swift:11,39`). Fix: 20 pt page titles, semibold section headings, drop the About title duplication. Rule: none.

**C6 (2) Bulk actions have no confirmation or undo** - Disable All (76 types) and Reset sit next to Enable All (`FileTypeSettingsView.swift:48-50`); `Reset Appearance` and profile Delete are link buttons (`AppearanceSettingsView.swift:13`, `AppearanceProfilesView.swift:96-108`). Nielsen 3/5. Fix: Undo toast (preferred) or confirm; delete behind a row menu. Rule: none.

**C7 (2) File Types semantics** - header "PREVIEWS" sits over group status words, while type rows have no state column (`FileTypeSettingsView.swift:102-106`, `FileTypeGroupSection.swift:43-48`); "n of m" and "Enabled" say the same; search is a bespoke box, no Cmd-F, hit-tested by a tap gesture (`:69-95`); filename patterns at 10 pt secondary. Fix: native `.searchable`/NSSearchField, drop duplicated word, make patterns 11 pt. Rule: none.

**C8 (2) Control idioms and hit targets** - switches on General (`SettingsCard.swift:112-115`), checkboxes with hidden labels on Theme where only the 14 pt box is clickable (`AppearanceFontControls.swift:47-51`, `AppearanceLayoutControls.swift:12-19,46-49`, `AppearanceSyntaxControls.swift:13-17`); font size 8-48 pt is a stepper with the value in the subtitle and no field (`AppearanceFontControls.swift:28-36`). Fix: whole-row toggle targets, numeric field + stepper, "13 pt". Rule: localization of the point value format.

**C9 (2) Theme IA** - five stacked cards before any look-and-feel choice; "Color mode" row repeats its current value as subtitle (`AppearanceControlsView.swift:27,30`); "Syntax styles" is both heading and disclosure label (`AppearanceSyntaxControls.swift:10,18`); "Color mode" vs "Color scheme"; High Contrast inside a mode picker; 4 long segments fall back to a menu (`:28-43`). Fix: swatch gallery of the 11 schemes on top, typography under "Advanced". Rule: none.

**C10 (2) Theme never says Finder previews update later** - "Updates as you edit" (`appearance.sample.updates`) is about the sample; the "applies to new previews" note lives only on File Types/General (`settings.extensionRefreshNotice`). Doc 05 called for "Close and reopen the preview to see changes". Fix: one line under the sample. Rule: honesty.

**C11 (2) Conflicts are the first failure mode and the last card** - the scan is an opt-in button at the bottom of General (`GeneralView.swift:23`); results list apps and overlapping types as prose with no per-type marker in File Types and no action (`QuickLookProviderDiagnosticsView.swift:52-124`). Fix: promote it next to setup step 2; mark conflicting rows in File Types after a scan. Rule: honesty (cannot say which provider Finder uses; "may be handled by another app" only).

**C12 (2) Try Preview asks three times** - subtitle = empty-state sentence, header [Open File...], 52 pt always-visible dashed drop zone, pane empty state with another [Open File...] (`DirectPreviewView.swift:14-16,45-50,64-87`); the file name duplicates the Quick Look title. Fix: the pane is the drop target; one button; name in the header. Rule: direct-drop contract unchanged.

**C13 (2) Menu and icon mismatches** - Cmd-, is labeled "Settings" but selects File Types (`CompanionApp.swift:55-57`, `navigation.settings`); About uses `questionmark.circle` (`CompanionSymbol.swift:9`); Help also opens About with no help content (`CompanionApp.swift:70-72`). Fix: label "File Types Settings..." or open General; `info.circle`. Rule: none.

**C14 (2) Non-native sidebar feel** - custom `HStack` with opaque background and hidden title bar rather than a vibrant source-list sidebar (`CompanionShell.swift:33-40`, `CompanionSidebar.swift:28-30`); fixed width by decision 010. Fix the material only (`.background(.regularMaterial)`/sidebar style) and confirm the page header is draggable. Rule: single-window/fixed sidebar kept.

**C15 (1) Smaller items** - fake traffic-light dots in the sample strip (`AppearanceSampleView.swift:64-72`) read as disabled controls; "Developer" is a top-level General section (`GeneralView.swift:43-50`); General's fixed "Text preview limits" look editable (`:56-67`); `StatusPill` and sidebar use `.subheadline` 11 pt.

### Rubric dimensions (self-score 1-5)

| Dimension | Score | Why |
|---|---|---|
| 1 Anatomy | 3 | Disciplined, collapsing header; but no summary strip, 10 pt full-ink status, tooltip-only badge |
| 2 Content presentation | 4 | 11 schemes, contrast-tested palettes, safe gutter; prose in code face, no muted tier |
| 3 Interaction | 3 | Rich (filter, sort, go to line, zoom, copy path) but nearly all hidden |
| 4 States and honesty | 3 | Wording excellent; visual treatment of states weak (P1, P2, P15) |
| 5 Companion | 3 | Clear IA, catalog-driven toggles, live sample; setup path and sample placement weak |
| 6 Identity/native feel | 3 | Native controls throughout; opaque custom sidebar, flat hierarchy |
| 7 Trust communication | 3 | Truthful but quiet (P3, P7); positive color overclaims (C2) |
| 8 Delight/friction | 2 | No motion, no empty-state design, three-fold prompts |

### Nielsen's 10 and HIG

| Lens | Verdict |
|---|---|
| 1 Visibility of status | Fail for states (P1), pass for save/storage (but duplicated, C4) |
| 2 Real-world match | Mixed: "Source" for synthesized text (P5), "source file" in errors (P15) |
| 3 Control and freedom | Bulk actions without undo (C6); Esc/close in bars is good |
| 4 Consistency | See section 3 |
| 5 Error prevention | Strong data-level (bounded, read-only); weak UI-level (C6) |
| 6 Recognition vs recall | Shortcuts and 3D gestures are recall-only (section 4) |
| 7 Flexibility | Good power paths (Cmd-F/G/L/+/-); no on-screen index |
| 8 Minimalist design | Header can stack 3-4 messages (P2, P3), General repeats status (C4) |
| 9 Error recovery | Messages lack next step (P15) |
| 10 Help | About is the Help; no task help or first-run guide (C3, C13) |
| HIG layout | Header budget unbounded (P2); good adaptive columns |
| HIG typography | 10 pt for important text; 13/13/13 page hierarchy (C5) |
| HIG color | Semantic dot+text pairs are good; green overclaim (C2); no muted tier (P4) |
| HIG toolbars | Controls inside content, none floating; CAD toolbar is two rows of buttons (P12) |
| HIG sidebars | Fixed, no material (C14); About icon (C13) |
| HIG settings | Auto-save with state is right; no undo; Settings label mismatch (C13) |
| HIG feedback | Copy and mode changes silent (P11) |
| HIG accessibility | Strong labels in code; order and mode label gaps (P8); see section 5 |

---

## 3. Inconsistencies

| Thing | Variation | Where |
|---|---|---|
| Truncation notice | text: status line 10 pt top; table/listing: separate caption inside the view under the mode row; outline: none found; CAD: none | `PresentationNotices.swift:14-19`, `NativeTablePreviewView.swift:147-153`, `NativeListingTreeView.swift:115-117` |
| Counts | table "n of N rows" only while filtering; findings "Label: n"; filter "Matches: n"; Go to Line "Lines 1-n"; picker "Levels: n"; General "Enabled file types: n" vs File Types "n of 76 enabled" | `NativeTablePreviewView.swift:392-404`, `en.txt` keys |
| Search/filter | text: system find bar (Cmd-F); outline: always-visible 30 pt bar; table: always-visible bar with Sort; tree: none | `NativePreviewView+Interaction.swift:82-99`, `NativeTablePreviewView.swift:50-102` |
| Copy | text: Cmd-Shift-C + menu; outline: context menu Value/Key/Path; table: Cmd-C only; tree: Cmd-C; copy ack: VoiceOver / none / inline label | `:252-269`, `NativeOutlinePreviewView.swift:318-334` |
| Loading | Finder: caption text; companion Try Preview: spinner; sample: small spinner overlay | `NativePreviewView.swift:246`, `DirectPreviewView.swift:41`, `AppearanceSampleView.swift:50-55` |
| Notice placement | CAD: privacy line top, summary bottom; MIDI: line inside strip; listing: inside table | `NativeGeometryPreviewView.swift:84`, `NativeMIDIPreviewView.swift:30` |
| Symbols | `info.circle` = provider badge and severity "info"; warning symbols use orange `.systemOrange` for warning only (low non-text contrast on white, shape reinforces) | `PreviewInfoBadge.swift:7`, `NativeFindingsBanner.swift:155-166` |
| Ink | status/gutter/filter count full ink; MIDI label and finding confirmation use system secondary; filter count alpha 0.75 | `NativePreviewView.swift:503`, `NativeMIDIPreviewView.swift:29`, `NativeFindingsBanner.swift:38` |
| Companion controls | switches (General) vs checkboxes (Theme, File Types); link-style buttons for destructive actions vs bordered for bulk actions | `SettingsCard.swift:112`, `AppearanceProfilesView.swift:101,104` |
| Row structure | Files table: Name/Kind/Size/Modified; Tree: Name/Items/Size/Modified; Files has no icons, Tree has | `NativeListingTreeView.swift:62,211` |
| Apostrophes | `isn't`, `can't` straight; `file's`, `preview's` curly | `failure.unsupported`, `setup.notConfigured` |

Copy too long for a preview header (10 pt, wrapping): `preview.privacyNotice` (14 words), `preview.table.truncated` (28 words), `preview.listing.partialNotice` (28), `preview.invisibles.note` (19), `preview.markdown.localOnly` (9 but permanent), `preview.structure.fallback` (9), `finding.secret.syncedFolder` (24), `finding.archive.highCompression` (14), `finding.action.copyConcealedHelp` (22), `settings.extensionConfigurationUnavailable` (3 sentences), `cad.interactionHelp` (45 words, tooltip). Companion: `setup.steps` (28), `settings.extensionRefreshNotice` (31), `about.howItWorks.body` (60), `settings.providers.guidance` (46), `settings.behavior.thumbnailsSubtitle` (38). Tone: calm and specific, but "Payload contents read", "Source read only", "Recursive", "Automatic playback" (`preview.summary.*`) are internal jargon exposed in Summary views.

---

## 4. Discoverability

| Shortcut / action | Where defined | Revealed anywhere in UI? |
|---|---|---|
| Cmd-1..4 (5), Cmd-, (File Types), Cmd-O (Developer Mode) | `CompanionApp.swift:46-64`, `CompanionRoute.swift:20-26` | View/File menu only; sidebar rows have no tooltip or hint |
| Cmd-F / G / Shift-G (find, filter, table filter) | `PreviewShortcut.swift:18-22`, `NativePreviewView+Interaction.swift:64-66` | Filter bar visible for outline/table; text find has no cue |
| Cmd-L Go to Line | `:59` | Only in the text right-click menu (`:252-269`); not shown for outlines |
| Cmd-Shift-C Copy All | `:60-63` | Right-click menu of text view only |
| Cmd-+ / Cmd-- / Cmd-0 zoom | `PreviewZoom.swift`, `:67` | Right-click menu; after zooming the status line says "Press Cmd-0" |
| Outline Copy Value/Key/Path, Cmd-C, Cmd-Up/Down | `NativeOutlinePreviewView.swift:318-334,411-435` | Right-click and VoiceOver actions only; no shortcut shown |
| Table sort (header click, Sort menu), filter | `NativeTablePreviewView.swift:241-242,308-325` | Visible Sort pulldown; header affordance standard |
| Filter Return / Shift-Return next match, Esc clear | `OutlineFilterBar.swift:86-99` | Help text only (`preview.interaction.filter.help`, VoiceOver) |
| Contents mode Return/Space activates | `Markup/MarkupContentsView.swift:4-8` | No |
| 3D: drag orbit, Shift/right-drag pan, scroll zoom, arrows, +/-, F, R, 1/2/3 | `NativeGeometryPreviewView.swift:368-393` | Only the viewport tooltip and VoiceOver help (`:274`); buttons cover Fit/Reset/zoom/views |
| MIDI Play/Pause/seek | `NativeMIDIPreviewView.swift` | Visible controls; no keyboard shortcut note |
| Mode switching | segmented control | No keyboard shortcut at all |
| Copy Concealed Text | banner button | Visible, with tooltip help |
| File Types: search focus | none (tap only, `FileTypeSettingsView.swift:94`) | No Cmd-F |

Verdict: every power feature is discoverable only by right-clicking text or reading VoiceOver help. The info badge (P7) is the natural home for a cheat sheet. Whether Quick Look forwards these key equivalents to the extension view is unverified.

---

## 5. Accessibility risks visible in code

- **Order and labels**: mode control unlabeled and ordered after content; filter bar last (P8). Verify the Tab loop and VoiceOver rotor in a Finder host.
- **Small secondary text**: caption 10 pt in secondary ink on page cards (`FileTypeCell.swift:25`, `FileTypeSettingsView.swift:143`, `AppearanceFontControls.swift:53`, notes in 4 cards). System secondary label is roughly 4:1 on white (not measured here), under 4.5:1 AA for small text. Preview palettes are contrast-tested (`ColorSchemeContrastTests`), companion chrome is not.
- **Color reliance**: mostly handled (dot + text pills, shape-coded severities, underline for invisibles when color is off, `contrast == .increased` borders in `SettingsCard.swift:59`, `FileTypeSettingsView.swift:90,135`). Gaps: warning symbol orange on light backgrounds (`NativeFindingsBanner.swift:165`), group state word color only differs by accent vs secondary (`FileTypeGroupSection.swift:48`).
- **Motion**: no animation in renderers; the only animation honors Reduce Motion (`FileTypeSettingsView.swift:157`). Good. A new copied chip or sample crossfade must follow the same gate.
- **Hit targets**: Theme checkboxes with hidden labels (C8); 16 pt badge; 20 pt close buttons (`GoToLineBar.swift:59-60`); 7 pt status dots are decorative (hidden from AX, correct).
- **Text size**: preview has Cmd-+/- and a font-size setting; companion fixed text styles do not follow a user text-size choice; 200 % enlargement and long German/Russian layouts were only checked offscreen (`companion-redesign-2026-10-04.md`).
- **Announcements**: Go to Line, copy, filter counts, sort are announced (`NativePreviewView+Interaction.swift:240-247`, table `announceSort`); loading/error transitions in the Finder view are not posted as announcements.
- **RTL**: no RTL language is shipped (decision 008 set); the layout uses leading/trailing and RTL-aware chevrons (`FileTypeGroupSection.swift:60`), the gutter draws right-aligned at the leading edge (`LogicalLineNumberGutter.swift:103`). Low risk now; unverified if Arabic/Persian/Urdu are added.
- **VoiceOver strings**: good practice already present (explicit values on steppers, combined elements for status, per-finding label starting with severity, per-cell column labels).

---

## 6. Top 20 improvements (impact x effort)

Effort: S under a day, M a few days, L a week or more. Impact is user-visible gain across formats.

| # | Change (finding) | Impact | Effort | Files |
|---|---|---|---|---|
| 1 | Shared designed state view for loading/unavailable/disabled/settings-unavailable, delayed spinner (P1) | High | M | `PR/NativePreviewView.swift`, new `PR/NativeStateView.swift`, `PR/PreviewStrings.swift`, `Resources/Localizable.xcstrings` |
| 2 | Pin the Theme live sample, controls scroll beside it (C1) | High | M | `APP/AppearanceSettingsView.swift`, `APP/Components/CompanionPage.swift`, `APP/Components/AdaptiveColumns.swift` |
| 3 | Replace green "shared" tone with neutral storage chip; first-run next-step state (C2) | High | S | `APP/Components/CompanionStyle.swift`, `APP/StorageModePresentation.swift`, `APP/GeneralView.swift`, `APP/CompanionSidebar.swift` |
| 4 | Numbered setup card with Open System Settings, Quick Look hop, sample reveal (C3) | High | M | `APP/GeneralView.swift`, `Apps/PrevApp/Models/CompanionRoute.swift`, strings |
| 5 | Collapse findings to a summary row, cap height, fold privacy notice into it (P2, P3) | High | M | `PR/Findings/NativeFindingsBanner.swift`, `PR/Findings/FindingText.swift`, `PR/NativePreviewView.swift:320` |
| 6 | Add muted ink tier and gutter separator (P4) | High | M | `PR/NativeTextAppearance.swift`, `PR/NativeColorSchemes.swift`, `PR/LogicalLineNumberGutter.swift`, `PR/Interaction/OutlineFilterBar.swift`, `GoToLineBar.swift`, contrast tests |
| 7 | One-line file summary strip (size, encoding, lines/rows, truncation) (P13) | High | M-L | `PR/NativePreviewView.swift`, `PR/PresentationNotices.swift`, presentation fields in `PreviewContracts` |
| 8 | Info badge becomes a popover: trust statement, provider, counts, shortcut cheat sheet (P7, section 4) | High | M | `PR/Interaction/PreviewInfoBadge.swift`, `PR/Interaction/NativePreviewView+Interaction.swift`, strings |
| 9 | Mode control: label, default-first ordering, "Source" renaming for synthesized text (P5, P8) | Med-High | M | `PR/SafePreviewModes.swift`, `PR/NativePreviewView.swift:120-152,603-615`, strings |
| 10 | Promote the conflict scan next to setup; mark conflicting File Types rows (C11) | Med-High | M | `APP/GeneralView.swift`, `APP/QuickLookProviderDiagnosticsView.swift`, `APP/FileTypeCell.swift`, `Models/QuickLookProviderDiagnostics.swift` |
| 11 | Visible "Copied" feedback everywhere (P11) | Medium | S | `PR/Interaction/NativePreviewView+Interaction.swift`, `PR/NativeOutlinePreviewView.swift`, `PR/NativeTablePreviewView.swift` |
| 12 | Markdown: prose face option, 80-char measure, notice only when something was blocked (P9) | Medium | S-M | `PR/NativePreviewView.swift:322,676`, `PR/NativeMarkdownStyling.swift`, `PreviewContracts/Preferences.swift` |
| 13 | Page and section hierarchy, About de-duplication (C5) | Medium | S | `APP/Components/CompanionPage.swift`, `APP/Components/SettingsCard.swift`, `APP/AboutView.swift` |
| 14 | Undo toast for Disable All/Reset/Delete profile/Reset Appearance (C6) | Medium | S-M | `APP/FileTypeSettingsView.swift`, `APP/AppearanceProfilesView.swift`, `Apps/PrevApp/Stores/CompanionSettings.swift` |
| 15 | Theme page: scheme swatch gallery, remove duplicate labels, "reopen previews" note (C9, C10) | Medium | S-M | `APP/AppearanceControlsView.swift`, `APP/AppearanceSchemeControls.swift`, `APP/AppearanceSyntaxControls.swift`, `APP/AppearanceSampleView.swift` |
| 16 | Try Preview: pane is the drop target, single Open button (C12) | Medium | S | `APP/DirectPreviewView.swift` |
| 17 | Table/outline/tree parity: row menu, tooltips for truncated values, tree filter, icons in Files (P10, P14) | Medium | M | `PR/NativeTablePreviewView.swift`, `PR/NativeOutlinePreviewView.swift`, `PR/Listings/NativeListingFilesView.swift`, `NativeListingTreeView.swift` |
| 18 | CAD floating toolbar and first-use gesture hint (P12) | Medium | M | `PR/NativeGeometryPreviewView.swift` |
| 19 | Failure copy with next step and limits; apostrophe sweep (P15) | Medium | S (M for 14 languages) | `Resources/Localizable.xcstrings`, `PR/PreviewStrings.swift`, `PR/NativePreviewView.swift:765-785` |
| 20 | Menu/label fixes and control polish: Cmd-, label, About icon, whole-row checkbox targets, numeric field for sizes, sidebar material (C7, C8, C13, C14) | Low-Med | S | `Apps/PrevApp/App/CompanionApp.swift`, `APP/Components/CompanionSymbol.swift`, `APP/AppearanceFontControls.swift`, `AppearanceLayoutControls.swift`, `APP/CompanionSidebar.swift` |

Open questions for a decision, not a fix: should JSON/YAML/XML open in Outline (P6)? Is a bundled sample file reveal allowed by the sandbox (C3)? Is a prose face worth a schema change (P9, P16)?
