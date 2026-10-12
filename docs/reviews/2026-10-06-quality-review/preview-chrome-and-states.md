# Preview chrome and non-content states review — 2026-10-06

Reviewed from source only, on Linux, on 2026-10-06: nothing was compiled, run, rendered or measured, so every runtime statement is inferred from code, Apple's documentation or the repository's validation records unless it says otherwise. The dimension is the chrome `NativePreviewView` draws around content in both hosts (status line, info badge, findings banner, mode-control row, accessory bar, gutter ink, notices), every non-content state (loading, empty, unavailable, disabled, settings unavailable, cancelled), copy feedback, density and accessibility order: Contract 1 of decision 026 with its `ux-chrome` and `ux-copy` workstreams. Verdict: the wording is careful and the header collapses when it has nothing to say, but the chrome has no fixed geometry, no facts and no designed states, it carries one honesty defect, and several Contract 1 promises (a Finder loading spinner, limit values in failures, plural counts, a muted tier distinct from body text in every scheme, a popover in the remote host) need contract, tooling or Mac work before they can be built as written.

## Scope and method

Paths are relative to the repository root, with these prefixes: `PR/` = `Packages/PreviewCore/Sources/PreviewRenderers/`, `PC/` = `Packages/PreviewCore/Sources/PreviewContracts/`, `CORE/` = `Packages/PreviewCore/Sources/PreviewCore/`, `PF/` = `Packages/PreviewCore/Sources/PreviewFormats/`, `RT/` = `Packages/PreviewCore/Tests/PreviewRenderersTests/`, `APP/` = `Apps/PrevApp/`. Line numbers are at commit `4a1580c`.

- **Read in full:** `PR/NativePreviewView.swift`, `PR/Interaction/NativePreviewView+Interaction.swift`, `PreviewInfoBadge.swift`, `PreviewAccessoryBar.swift`, `GoToLineBar.swift`, `OutlineFilterBar.swift`, `PreviewZoom.swift`, `PreviewShortcut.swift`, `PR/Findings/NativeFindingsBanner.swift`, `FindingText.swift`, `PR/PresentationNotices.swift`, `PR/LogicalLineNumberGutter.swift`, `PR/NativeTextAppearance.swift`, `PR/NativeColorSchemes.swift`, `PR/PreviewStrings.swift` (key enum and lookup), `PR/NativePreviewPane.swift`, `Extensions/PrevPreviewExtension/PreviewViewController.swift`, `APP/Views/DirectPreviewView.swift`, `APP/Views/AppearanceSampleView.swift`, `PC/PreviewModels.swift`, `PC/GeometryPresentation.swift`, `PC/PartialInputContracts.swift`.
- **Read in part:** the table, outline, geometry, MIDI, listing tree and listing files views (layout, notices, copy); `PR/SafePreviewModes.swift`, `SafeDelimitedTable.swift`, `Listings/SafeListing.swift`, `Images/DocumentPresentationNotices.swift`, `Markup/MarkupRendering.swift`, `SafeSchemaLabels*.swift`, `SafeDataProfilePresentation.swift`; `CORE/PreviewPipeline.swift`, `PartialTextPrefix.swift`, `DefaultPrivacyFilter.swift`, `TextDecoder.swift`; `PF/JSONSourceAdapter.swift`, `PF/Code/CodeFormatAdapters.swift`, `PF/Containers/MIDIAdapter.swift`, `PF/Geometry/MeshFormatAdapters.swift`; `PC/PreviewFindings.swift`, `BinaryPreviewContracts.swift`; `APP/Models/PreviewSession.swift`, `AppearanceSampleSession.swift`, `APP/Views/AppearanceSettingsView.swift`, `APP/App/CompanionApp.swift`, `APP/Views/Components/CompanionStyle.swift`.
- **Tests:** `RT/NativeInitialLayoutTests.swift`, `RT/Interaction/ZoomBadgeAndReloadRenderingTests.swift`, `InteractionTestSupport.swift`, `RT/Findings/FindingsBannerTests.swift`, `RT/Settings/ColorSchemeContrastTests.swift`, `RT/NativeTextAppearanceTests.swift`, `RT/LocalizationTests.swift`, plus `rg` over `Packages/PreviewCore/Tests` for subview lookups, status reads and notice assertions.
- **Tools:** `tools/add_localizations.py`, `generate_localization.py`, `merge_localizations.py`, `validate_localization.py` (format-key discovery), `test_localization.py`, `tools/localization/README.md`.
- **Documents:** the brief, `AGENTS.md`, decision 026, the analysis, the self-audit, the platform baseline, the ranked recommendations of the closest-rivals and code/Markdown reports, `PLAN.md` (UX program and line 160), decision 021 (badge section), `docs/initial/01-macos-apis.md`, and the validation records `interaction-2026-10-05.md`, `installed-host-2026-10-04.md`, `shared-settings-configuration.md` and `native-renderer-performance-2026-10-04.md`.
- **Apple documentation fetched 2026-10-06:** QuickLookUI `preparePreviewOfFile(at:completionHandler:)` and the iOS/Catalyst `QLPreviewingController` overview. `support.apple.com` was blocked by the egress proxy, so the Finder shortcut names below are recalled, not re-read.
- **Run:** `python3 tools/test_localization.py` (13 tests, OK), `python3 script/sync_manifests.py --check` (280 preview and 276 thumbnail types, 53 imported declarations), `python3 script/generate_appearance_samples.py --check` (76 formats). Scratch scripts in the agents scratch directory: WCAG contrast of every palette's foreground, comment colour, 75 % alpha foreground and an estimate of system secondary-label ink; a String Catalog inventory (words, apostrophes, punctuation, plural variants); rough segmented-control widths per language.
- **Out of scope:** the internals of outline, table, listing, Markdown, 3D and MIDI views beyond the chrome they add; companion pages beyond how they host the preview; thumbnails; the five owner decisions.

## Current state

The base is stronger than the competitor comparison suggests, and these properties should survive the program:

- **The header spends little when it has nothing to say.** An empty status row collapses to zero when a mode control exists, and the mode row and its 8 pt gap vanish with one mode (`PR/NativePreviewView.swift:591-615`). Plain text costs 34 pt and JSON 42 pt before content, and two layout tests pin it (`RT/Interaction/ZoomBadgeAndReloadRenderingTests.swift:159-192`).
- **Copy is honest and complete.** All state, failure and notice keys exist in 14 languages with translator comments (none missing in the inventory). The privacy sentence stays text because it changes what copying returns, and the badge names no provider for loading, failure or disabled states (`PR/NativePreviewView.swift:318-320,519-524`; decision 021 amendment).
- **Findings are typed.** Severity-sorted rows, shape-coded glyphs with colour as reinforcement only, and one VoiceOver item per row that starts with the severity (`PR/Findings/NativeFindingsBanner.swift:116-139,151-166`). Concealment counts per kind sum to the redaction count by construction (`CORE/DefaultPrivacyFilter.swift:152-188`).
- **Palettes are tested.** Every role and the foreground meet 4.5:1 in all eleven schemes and 7:1 in high contrast (`RT/Settings/ColorSchemeContrastTests.swift:40-60`); the status ink is tested against forced themes (`RT/NativeTextAppearanceTests.swift:155-163`); Increase Contrast overrides any scheme (`PR/NativeColorSchemes.swift:52-54`).
- **Copy paths are safe and testable.** Copy All copies the displayed concealed text and never source (`PR/Interaction/NativePreviewView+Interaction.swift:124-139`); tests use private pasteboards (`RT/Interaction/InteractionTestSupport.swift:25-28`).
- **Keyboard handling is polite.** Key equivalents act only while focus is in the preview or nowhere (`...+Interaction.swift:71-77`), Escape is consumed only inside the bars (`PR/Interaction/GoToLineBar.swift:115-118`), and zoom is temporary and never saved (`PR/Interaction/PreviewZoom.swift:4-7`).
- **The request lifecycle is sound.** Cancellation, generation identity and `hostManaged` visibility for the remote host (`Extensions/PrevPreviewExtension/PreviewViewController.swift:22-75`), and a measured single-layout-pass invariant for wrapped text (`RT/NativeInitialLayoutTests.swift:46-74`) that every chrome change must keep.

## Findings

| ID | Severity | Confidence | Title | Evidence |
|---|---|---|---|---|
| CH-1 | Blocker | Verified in code | A partly read wide CSV says "Source shows the complete concealed text" while the status line says only the first megabyte was read | `PF/Code/CodeFormatAdapters.swift:21-24`; `PR/PresentationNotices.swift:155-160`; `PR/SafeDelimitedTable.swift:101,130`; `PR/NativeTablePreviewView.swift:151-155`; key `preview.table.truncated` |
| CH-2 | Major | Verified in code | Mode notes, the zoom line and the font-fallback hint sit above the mode control, so switching mode or zooming moves the control and the content | `PR/NativePreviewView.swift:145,181,318-329,515-518,591-601`; `...+Interaction.swift:38-49` |
| CH-3 | Major | Verified in code; heights approximate | The findings stack has no height bound: about 230 pt before text for a `.env` with four secret kinds | `PR/Findings/NativeFindingsBanner.swift:11,31,46,67-85,116-139`; `PR/Findings/FindingText.swift:93-95`; `PC/PreviewFindings.swift:14` |
| CH-4 | Major | Verified in code | Concealment is stated three or four times, and Copy Concealed Text duplicates Copy All in most modes | `PR/NativePreviewView.swift:320,617-623`; `...+Interaction.swift:126-139`; `PC/PreviewFindings.swift:102-105` |
| CH-5 | Major | Verified in code | Non-content states are 10 pt captions over an empty, focusable text view; the disabled body is selectable text in the content font; nothing is announced | `PR/NativePreviewView.swift:89-90,246-256,330-345,459-477,503,514` |
| CH-6 | Major | Verified (computed) | Derived chrome ink fails AA: 75 % alpha foreground is 3.08:1 in Solarized Light, 3.79:1 in Solarized Dark, 4.37:1 in One Dark; system secondary ink ignores the palette | `PR/Interaction/OutlineFilterBar.swift:61`; `GoToLineBar.swift:109`; `PR/Findings/NativeFindingsBanner.swift:38`; `PR/NativeTablePreviewView.swift:287`; `PR/NativeMIDIPreviewView.swift:29`; `PR/Listings/NativeListingTreeView.swift:176` |
| CH-7 | Major | Verified (computed) | A 4.5:1 muted tier cannot look lighter than body text in Solarized Light (body 4.99:1) or Solarized Dark (5.61:1) | `PR/NativeColorSchemes.swift:114-126,137-141` |
| CH-8 | Major | Verified in code | Presentation fields change meaning by input path: folders report 0 bytes; archives, databases and MIDI report the lines and UTF-8 of the app-made JSON | `CORE/PreviewPipeline.swift:87-105`; `PC/PreviewModels.swift:63-84` |
| CH-9 | Major | Verified in code | The localization toolchain cannot carry plural forms, so "1,204 lines" or "3 secrets hidden" cannot be translated correctly | `tools/generate_localization.py:5-6,25-26`; `tools/merge_localizations.py:36`; `tools/add_localizations.py:47-49`; 0 of 924 keys use variations |
| CH-10 | Major | Verified in code | Failure states cannot name the limit that was hit; the "2 MB" in the self-audit and decision 026 is the output limit, not the input limit | `PC/PreviewModels.swift:108-162`; `PR/NativePreviewView.swift:765-785`; `CORE/PreviewPipeline.swift:57`; `PC/GeometryPresentation.swift:12-13` |
| CH-11 | Minor | Inferred (Apple documentation); needs a Mac | In Finder the system shows its own spinner until the completion handler, which this extension calls after the pipeline, so "Preparing preview…" is drawn into a view Quick Look has not yet presented | `Extensions/PrevPreviewExtension/PreviewViewController.swift:37,63-69` |
| CH-12 | Minor | Verified in code | Partial-content notices use eight phrasings in three positions, with and without counts and final periods; math and BibTeX notes also show in Source | `PR/PresentationNotices.swift:155-160`; `PR/Images/DocumentPresentationNotices.swift:12-25`; `PR/NativeTablePreviewView.swift:151-155`; `PR/Listings/NativeListingTreeView.swift:115-117`; `PR/SafeNotebookDocument.swift:120,312`; `PR/SafeDataProfilePresentation.swift:83-97`; `PR/Markup/MarkupRendering.swift:42-49` |
| CH-13 | Minor | Verified in code | The trust statement is a tooltip on an image, and `info.circle` also marks every concealment row and the "More findings" row | `PR/Interaction/PreviewInfoBadge.swift:6-8,25-35`; `PR/Findings/NativeFindingsBanner.swift:73,157`; `PC/PreviewFindings.swift:102-105` |
| CH-14 | Minor | Verified in code; spoken order needs a Mac | The mode control has no accessibility label and follows the content; lazily added mode views and the 3D view follow the accessory bar; no navigation order, key-view loop or focus handoff after a mode switch | `PR/NativePreviewView.swift:120-152,603-615,625-634,735,801` |
| CH-15 | Minor | Verified in code | Copy feedback: seven pasteboard writes in six files plus the text view's own copy; only Copy All announces; the Copy Concealed confirmation never clears; one writer bypasses the injectable pasteboard | `...+Interaction.swift:133-139`; `PR/NativePreviewView.swift:617-623`; `PR/Findings/NativeFindingsBanner.swift:61-64,99-104`; `PR/NativeOutlinePreviewView.swift:354-359,411-415`; `PR/NativeTablePreviewView.swift:478-482`; `PR/Listings/NativeListingTreeView.swift:302`; `PR/Markup/MarkupContentsView.swift:181-186` |
| CH-16 | Minor | Matching verified; layout and Finder behaviour inferred | Shortcuts match unshifted characters and reject Option, so ⌘0 cannot match on French AZERTY and Command-Option-digits need key codes; ⌘F, ⇧⌘C and ⇧⌘G are also Finder menu commands; the context menu restates the key table | `PR/Interaction/PreviewShortcut.swift:3-4,13-28`; `...+Interaction.swift:255-261` |
| CH-17 | Minor | Verified in code | No empty state: a 0-byte text file is a blank pane, a 0-byte JSON says "could not be parsed safely", an empty folder opens its Summary of zero counts under a filter bar | `PF/JSONSourceAdapter.swift:73-91`; `CORE/TextDecoder.swift:66`; `PR/Listings/SafeListing.swift:47-48` |
| CH-18 | Minor | Verified in code | Same fact twice: MIDI shows "Playback starts only when you press Play." above "Automatic playback: No"; 3D shows "Document metadata is omitted." above "Created with: …" | `PR/NativeMIDIPreviewView.swift:30`; `PF/Containers/MIDIAdapter.swift:109`; `PR/SafeSchemaLabels+Containers.swift:58-61,84`; `PR/NativeGeometryPreviewView.swift:144-155` |
| CH-19 | Minor | Verified in code | Companion loading differs from Finder: Try Preview tears down the native pane for an immediate SwiftUI spinner; the Theme sample's spinner covers the badge corner | `APP/Views/DirectPreviewView.swift:37-44`; `APP/Models/PreviewSession.swift:78-84`; `APP/Views/AppearanceSampleView.swift:50-55`; `PR/NativePreviewView.swift:176` |
| CH-20 | Minor | Needs a Mac | The header is anchored to the view's top, not its safe area; selection colours are not in the palette (body text on the default light selection is roughly 3.6:1 in Solarized Light, inferred) | `PR/NativePreviewView.swift:156`; no `safeAreaLayoutGuide` or `selectedTextAttributes` in `PR/` |
| CH-21 | Minor | Verified in code | Copy style: a straight apostrophe in `failure.unsupported`; fragments without periods beside sentences; mixed contractions; header notes up to 23 words; two strings for one copy event | String Catalog inventory below |
| CH-22 | Cosmetic | Verified in code | The 12 pt inset literal appears 25 times in 9 renderer files; chrome metrics have no owner yet | `rg "constant: -?12\b\|left: 12\|width: 12, height: 12" PR/` (22 constraints and 3 insets, e.g. `PR/NativePreviewView.swift:101,174,176,182`) |

**CH-1 (Blocker, honesty).** CSV and TSV opt into leading-prefix reads (`PF/Code/CodeFormatAdapters.swift:21-24`), so a 3 MB export is cut to its first megabyte and the status line says "Showing the first 1 MB of 3 MB" (`PR/PresentationNotices.swift:155-160`). If the file is wider than 64 columns, the table also truncates (`PR/SafeDelimitedTable.swift:101,130`), and its own notice, inside the table view below the mode row, ends with "Source shows the complete concealed text." (`PR/NativeTablePreviewView.swift:151-155`). Source then holds only the first megabyte. The two sentences contradict each other on one screen, and the second is false about the file. A rewording that stays true in both cases fixes it ("Columns, rows or long cells beyond the table limits are not shown here. Source shows them."); the limits strip later removes the duplicate. It touches the honesty rule in AGENTS.md and gate 12.

**CH-2 (Major).** The mode control's top is tied to the findings banner, which is tied to the status line (`PR/NativePreviewView.swift:145,181`). The status line holds notes that depend on the mode (Rendered's offline note, the Invisibles note, Profile notes: `:318-329`), the zoom line (`...+Interaction.swift:38-49`) and the font-fallback hint (`:515-518`), and it collapses when empty (`:591-601`). Clicking Source on a Markdown file therefore moves the control you just clicked up by about 23 pt (the 10 pt top plus one caption line), clicking Rendered moves it back, the first ⌘+ pushes the whole preview down, and CSV's Profile mode does the same whenever it has notes (sampling, ragged rows, duplicate names, concealed columns). Every Markdown or EPUB reader who changes mode and every reader who zooms meets it. The control needs a constant position in the first band, with notes below it or in the limits slot and zoom as a transient chip; Contract 1's header row implies this but never states it.

**CH-3 (Major).** The banner grows with its content: an 8 pt top inset, up to six rows plus "More findings", 6 pt gaps, then the button row (`PR/Findings/NativeFindingsBanner.swift:11,31,46,67-85`). Concealment findings carry line positions (`CORE/DefaultPrivacyFilter.swift:176-187`), so every secret row has two lines: the callout message and a "Lines: …" caption. A `.env` with four secret kinds needs about 23 pt of status line, 165 pt of banner and 42 pt of mode row before the text, about 230 pt at 640 to 800 pt widths: 38 % of the 600 pt host and 57 % of a 400 pt pane. A cloud-folder warning adds a row, and decoded hidden text adds up to 512 characters to a single row (`PR/Findings/FindingText.swift:93-95`; `PC/PreviewFindings.swift:14`), several caption lines at pane width. The banner alone can reach about 255 pt, against the self-audit's 100 to 150. P2's collapsed row with a 25 % cap and internal scrolling is the fix.

**CH-4 (Major).** For a concealed value the reader sees the status sentence (`PR/NativePreviewView.swift:320`), one row per kind ("API keys concealed: 3."), the Copy Concealed Text button with its tooltip, and for a synced folder a fourth sentence. Copy Concealed Text writes `safePresentation.text` (`:617-623`), which is exactly what Copy All writes in Source, outline, table and derived modes (`...+Interaction.swift:126-130`); the two differ only in Rendered and Invisibles. Secret kinds default to severity info (`PC/PreviewFindings.swift:102-105`), so every row also carries the `info.circle` of the trust badge. One row with one sentence and one action, as Contract 1 proposes, is right, and it should also drop the duplicate action.

**CH-5 (Major).** Loading, unavailable, settings-unavailable and cancelled outcomes set a caption1 status line in full palette ink over an empty, still focusable text view (`PR/NativePreviewView.swift:89-90,246-256,335-345,459-477,503,514`). Disabled puts its title in the 10 pt status line and its 15-word body into the text view in the user's code font, selectable (`:330-334`). VoiceOver lands on an empty "Preview content" text area, and no state change is announced. `NativeStateView` is the fix, with the caveats in CH-10, CH-11 and the contract table below.

**CH-6 (Major).** Where the code wants quieter ink it uses 75 % alpha foreground (`PR/Interaction/OutlineFilterBar.swift:61`; `GoToLineBar.swift:109`) or `secondaryLabelColor` (`PR/Findings/NativeFindingsBanner.swift:38`; `PR/NativeTablePreviewView.swift:287`; `PR/NativeMIDIPreviewView.swift:29`; `PR/Listings/NativeListingTreeView.swift:176`). Composited over the palette background, the alpha ink is 3.08:1 in Solarized Light, 3.79:1 in Solarized Dark and 4.37:1 in One Dark, below AA for 10 pt text. The system secondary ink is roughly 3.9 to 4.0:1 on the six light backgrounds (inferred from the recalled 50 % black). The contrast tests cover only palette constants (`RT/Settings/ColorSchemeContrastTests.swift:40-60`), so none of this is caught. The `muted` tier and a test of each chrome label's effective colour fix it.

**CH-7 (Major, contract).** Body text in Solarized Light is 4.99:1 and in Solarized Dark 5.61:1 (`PR/NativeColorSchemes.swift:114-126`), so any `muted` at 4.5:1 sits within 11 % and 25 % of the body's contrast and will not read as a separate tier; One Dark has 1.46× headroom (`:137-141`). Gate 4 can pass while the hierarchy disappears in those schemes. Seed `muted` from each scheme's already tested comment colour (4.57 to 13.08:1) and add a second cue, 11 pt regular, wherever the headroom is under about 1.5×.

**CH-8 (Major, contract).** `byteCount` is the decoded bytes for text, the shown bytes for partial reads, the file size for binary and random-access sources, and 0 for folders (`CORE/PreviewPipeline.swift:87-100`). `encoding` defaults to UTF-8 for binary, URL and random-access adapters (`:92-100`), and `lineCount` counts the concealed displayed text (`:105`), which for archives, SQLite, MIDI and packages is the app-made JSON summary. Nothing in `TextPresentation` says whether `text` is source or summary (`PC/PreviewModels.swift:63-84`). A strip built "from fields the presentations already carry" would print "UTF-8 · 312 lines · 0 bytes" for a folder. Decision 026's premise holds only for text families; facts need a provenance rule and per-family providers.

**CH-9 (Major, tooling).** `generate_localization.py` refuses any catalog entry with variations ("plural resources require a corresponding .stringsdict generator", `tools/generate_localization.py:5-6,25-26`), `merge_localizations.py` accepts only strings (`:36`), and `add_localizations.py` takes one flat value per language (`:47-49`). None of the 924 keys uses variations, which is why every count today reads "Label: n". Contract 1's "1,204 lines", "3 likely secrets hidden" and "Showing the first 5,000 of 12,431 entries" need one, few and many forms in Russian and one and other forms in most other languages. Either build the generator and validator first, or keep label-colon notation in chrome.

**CH-10 (Major, contract).** `PreviewFailure` has no associated values (`PC/PreviewModels.swift:108-115`), the outcome carries neither the format nor the budget, and budgets differ per registration: standard 1 MiB input, 2 MiB output, 20,000 lines, 2 s; containers 16 MiB and 5 s; meshes 16 MiB and 10 s; CAD 16 MiB, 32 MiB and 20 s (`PC/PreviewModels.swift:140-155`; `PC/GeometryPresentation.swift:12-13`; `PF/Geometry/MeshFormatAdapters.swift:22-25`; `CORE/PreviewPipeline.swift:57`). Three key pairs merge different limits: input and output size (`PR/NativePreviewView.swift:773`), depth and node count (`:777`), line count and line length (`:779`). The self-audit's "Limit: 2 MB" and Contract 1's "limit 2 MB" name the output budget; a partial read is cut at the 1 MiB input budget (`CORE/PartialTextPrefix.swift:6-8`). Stating the limit needs the effective budget to reach the renderer (see R9) and one key per limit.

### Self-audit and inconsistency-table verification

| Item | Verdict | Evidence and correction |
|---|---|---|
| P1 | Right, incomplete | Captions at caption1 in full ink, disabled body in the code font, three settings sentences (`PR/NativePreviewView.swift:90,250-256,330-334,503,514`). Missing: Finder users probably never see the loading caption (CH-11); neither host ever displays `.cancelled`; the empty text view stays focusable. |
| P2 | Right, understated | Secret rows have two lines each, so the banner reaches about 255 pt, not 100 to 150 (CH-3). |
| P3 | Right, incomplete | Adds the duplicated copy action and the shared info glyph (CH-4). |
| P4 | Right, incomplete | The existing quiet inks already fail AA in three schemes (CH-6); the proposed tier has almost no headroom in Solarized (CH-7). |
| P7 | Right | `NSImageView` with a tooltip (`PR/Interaction/PreviewInfoBadge.swift:6,31`); concealment rows share the glyph (CH-13). |
| P8 | Right; the fix is risky | Order and missing label confirmed (`PR/NativePreviewView.swift:120-152`); mode views and the 3D view are appended later (`:735,801`). Reordering `addSubview` would break 32 test lookups that take the first `NSTextField`, `NSScrollView` or `NSSegmentedControl` direct subview (the outline view is itself an `NSScrollView`, `PR/NativeOutlinePreviewView.swift:26`). Override `accessibilityChildrenInNavigationOrder` instead. |
| P11 | Right | Plus the persistent Copy Concealed label and the seven write sites (CH-15). |
| P13 | Symptom right, remedy premise wrong | No facts outside accessibility labels and the 3D summary, but the fields are not uniform (CH-8) and counts need plural tooling (CH-9). |
| P15 | Right, partly wrong | "Limit: 2 MB" is the output budget (CH-10). Straight apostrophes also occur in three more English keys (`general.finder.foldersSubtitle`, `preview.data.plotHelp`, `settings.providers.guidance`), 23 French and 8 Turkish values; Hausa's 66 are partly orthographic. |
| P17 | Right, incomplete | The default Summary repeats the fact (CH-18), and MIDI has the tallest chrome without findings, about 186 pt to the first Summary row. |
| Chrome arithmetic (self-audit line 30) | Plain 34 and JSON 42 right; `.env` understated | About 230 pt, not 190 (CH-3). |
| Copy word counts (section 3) | Overstated | `preview.privacyNotice` has 11 words (not 14), `preview.table.truncated` 23 (28), `preview.listing.partialNotice` 22 (28), `preview.invisibles.note` 16 (19). |
| Row: Truncation notice | Right, incomplete | Also inline in notebooks (`PR/SafeNotebookDocument.swift:120,312`), in the plot caption (`PR/Data/NativePlotPreviewView.swift:46`), in Profile status lines and as Summary rows. Outlines and 3D never truncate, because structured and geometry formats fail instead (`PC/PartialInputContracts.swift:199-200`). |
| Row: Counts | Right, incomplete | The table filter status is at `PR/NativeTablePreviewView.swift:417-419`, not 392-404. Add "Rows profiled: x of y", "Cells shown: x of y", "Showing the first x of y", "Line x of y". The label-colon style follows from CH-9. |
| Row: Loading | Code right, user view wrong | Finder shows the system spinner (CH-11); Try Preview's spinner replaces the native view (CH-19). |
| Row: Symbols | Right | Add the "More findings" row and every concealment row (CH-13). |
| Row: Ink | Self-contradictory | It calls the filter count both full ink and 75 % alpha; the code sets system secondary and then 75 % alpha (`PR/Interaction/OutlineFilterBar.swift:27,61`). See CH-6. |

### Chrome stack by format

Arithmetic from the coded constants at 640 to 800 pt width, with assumed macOS 15 metrics: a caption line about 13 pt, a callout line about 15 pt, a small push button about 21 pt, a search field about 22 pt, a table header about 24 pt (macOS 26 controls are taller). "Before content" ends at the top of the text view, first row or viewport.

| Format (default mode) | Stack from the top | Before content (pt) | Same fact twice |
|---|---|---|---|
| Plain text | Status row 10 + 16 holding only the badge, gap 8, text inset 12 | 34 (46 to the first line) | None; there are no facts at all |
| JSON, Source | Mode row 8 + 26 with the badge centred on it, gap 8, inset 12 | 42 (54) | None |
| JSON, Outline | Mode row, gap, filter bar 30, column header | about 96 | None |
| JSON with one concealed token | Status 23, banner 8 + 28 + 6 + 21, mode row 34, gap 8 | about 128 | Privacy sentence, "Password, token and key values concealed: 1.", Copy Concealed Text; that action equals Copy All |
| `.env` with four secret kinds (Source of Source, Summary) | Status 23, banner about 165, mode row 34, gap 8 | about 230; about 251 with a cloud-folder warning | Concealment three or four times (CH-4) |
| Table over 64 columns (Table of Source, Table, Profile) | Mode row 42, then inside the table: notice 4 + one or two lines + 4, filter bar about 34, header about 24 | about 121-134 to the first row | Rows × columns only in the accessibility label (`PR/NativeTablePreviewView.swift:422-425`) |
| Same table, file over 1 MiB | Adds the partial line above the mode row, which moves from 8 to 31 pt | about 144-157 | Partial read stated at the top and inside, and contradicted (CH-1) |
| ZIP listing, partial, two archive findings (Files of four modes) | Banner 8 + 15 + 6 + 15, mode row 34, gap 8, Files notice about 34, filter bar 34, header 24 | about 178 (about 100 when complete and clean) | "Partial" in the Files notice and as a Summary row in another mode (acceptable) |
| Markdown, Rendered | Status "Offline preview. External resources are not loaded." 23, mode row 34, gap 8, inset 12 | 65 (77); Source and Contents drop the line and the control jumps 23 pt | The math note stays in Source |
| STEP or IGES | Status row 10 + 16 with the CAD note and badge, gap 8, two rows of seven rounded buttons about 50, gap 6, viewport, gap 6, one to three caption lines of facts, 8 | about 90 above and 27-53 below the viewport | "Document metadata is omitted." above "Created with: …" (CH-18) |
| MIDI, Summary | Mode row 34, MIDI strip 90, gap 8, filter bar 30, header 24 | about 186 to the first row | Autoplay stated twice (CH-18) |

### Contract 1 in the real host

| Element | Code today | Host behaviour and evidence | Verdict |
|---|---|---|---|
| One header row of 28 pt or less (gate 1) | Collapsing status row and a 26 pt mode row | A four-segment control is roughly 200-300 pt in most languages and about 430 pt for the Russian Markdown labels (estimate), so facts, control and info button share one row only above about 600 pt. Outline and table filter bars (30 and 34 pt) are always shown (`...+Interaction.swift:27-32`; `PR/NativeTablePreviewView.swift:143`) | Feasible at regular width only if filters open on demand, which conflicts with the analysis's "find and filter affordances visible when idle"; the MIDI strip and the 3D button rows also fail gate 1 unless counted as content |
| Facts strip | None | None | Text families now; others need provenance and providers (CH-8) and plural tooling (CH-9) |
| Mode control label, order, ⌥⌘1…n | No label; `PreviewShortcut` rejects Option (`PR/Interaction/PreviewShortcut.swift:15`) | Key delivery into the remote view is unrecorded (`docs/validation/interaction-2026-10-05.md:36-38`) | Label and order: yes. Keys: implement with key codes (CH-16); delivery needs a Mac |
| Info button with a popover | `NSImageView` with a tooltip; no `NSPopover`, panel or alert anywhere in the renderers, extension or app | The macOS QuickLookUI pages say nothing about popovers; the iOS/Catalyst `QLPreviewingController` page says to avoid presenting additional view controllers; the code itself records that the remote backing window misreports occlusion (`PreviewViewController.swift:24-26`; `PR/NativePreviewView.swift:7`); tooltips and menus in Finder are unverified | Button: yes. Popover: needs a Mac. Build an in-view disclosure that pushes content down (no overlay, works in any host) and keep the popover optional |
| Privacy row with a 25 % cap | Unbounded stack | None | Feasible; the copying sentence plus two buttons needs two lines below about 600 pt, and in German or Russian at most widths |
| Accessory bar only while open | Filter shown for every outline mode | None | Needs an opening affordance (ux-modes-structure) |
| Ink tiers and hairline | Two inks; derived inks fail AA | Increase Contrast swaps palettes | Feasible, with a size cue in Solarized (CH-7) |
| Limits strip | Untyped strings in three places | None | Feasible with typed notices; totals are unknown for partial text reads (bytes only) and for tables past 20,000 rows; "Showing the first 20,000 lines · limit 2 MB" cannot be produced (CH-10) |
| States, spinner after 300 ms | `showLoading()` only in the extension, before the handler | Apple: "The operating system shows a loading spinner, so call the handler as soon as possible"; the handler fires after the pipeline (CH-11) | Finder shows the system spinner unless the handler is called early, a lifecycle change to test on a Mac. The companion needs `NativePreviewPane` to accept a loading state (CH-19). Release warm p95 for JSON is 434 ms (`PLAN.md:160`), so a 300 ms delay still flashes |
| Limit value in failures | Not available | None | Contract change (CH-10, R9) |
| At most one action | None | The extension cannot rely on opening the companion (`docs/initial/01-macos-apis.md:81`) | Finder states get no action except in-view ones; the companion can offer Open File and Enable this type |
| Copied chip, Reduce Motion | Seven write sites, one announcement; Reduce Motion is read nowhere in the renderers | The view already observes accessibility display changes (`PR/NativePreviewView.swift:213-216`) | Feasible with one copy callback shared by three workstreams; reserve the chip's slot so nothing moves |
| Two densities | No width logic beyond wrapping | Finder creates the view at 800 × 600 and resizes it (`PreviewViewController.swift:23`); representables start at zero (`PR/NativePreviewView.swift:102`); no pane width is published | Decide density from the view's own width, with hysteresis, before the text layout pass and never from the scroll view's width (the gutter would oscillate). The Theme sample is about 376-404 pt wide at the default window by arithmetic (`APP/Views/AppearanceSettingsView.swift:19`; `APP/Views/Components/CompanionStyle.swift:5-14`), so it would render compact |

### Facts available per family

| Family | Fields that exist today | Caveat | Missing |
|---|---|---|---|
| Text, source, configuration, logs, markup | `TextPresentation.encoding`, `lineCount`, `byteCount`, `truncatedSourceBytes`, `redactionCount`, `isReformatted`, `sourceLanguage`, `findings` (`PC/PreviewModels.swift:63-84`) | `lineCount` counts concealed displayed text: formatted lines when `isReformatted`, collapsed lines after multi-line concealment; `byteCount` is the shown bytes for partial reads | BOM flag (`DecodedText.hasByteOrderMark`, `PC/PreviewModels.swift:239`, is dropped), line-ending style (derivable), total lines of a partial read (unknowable) |
| JSON Lines, captions, draw.io | `sourceRecordCount` (records, cues, pages), `invalidRecordLines` | None | None |
| CSV, TSV | Renderer: `SafeTable.rows.count`, `columns.count`, `truncation`, `headerFieldCount` (`PR/SafeDelimitedTable.swift:9-26`); profile notes | `.rows` means more than 20,000 rows or 500,000 cells, and the total is not kept | Total records when truncated |
| JSON, YAML, TOML, XML, plist | Renderer: outline nodes derived once in `SafePreviewModes.init` (`PR/SafePreviewModes.swift:196-219`) | Count at derivation, not per display | Root kind and key count (derivable) |
| Folders, archives | Renderer: `SafeListing.entries` (`kind`, `bytes`, `isEncrypted`, `itemCount`), `isPartial` (`PR/Listings/SafeListing.swift:5-38`); `SafeListingTree.itemCountIsLowerBound`; the folder summary JSON also carries `fileCount`, `folderCount`, `listedBytes`, `hiddenEntries`, `inaccessibleEntries` and `depth` (`PF/Containers/FolderSummaryAdapter.swift:35-42`) | `byteCount` is 0 for folders; lines and encoding describe the JSON; the summary counts are untyped JSON | Typed access to the summary counts; totals for partial listings |
| Columnar data, SQLite, packages, ebooks | Only inside adapter summary JSON, labelled by `PR/SafeSchemaLabels+*.swift` | Typing them means reading adapter-owned schemas | One facts provider beside each label set |
| 3D | `GeometryPresentation.byteCount`; `mesh.faceCount`, `indices.count / 3`, `positions.count`, `bounds` in millimetres, `measurements` (area, volume, `bodyCount`), `headerFacts` (`PC/GeometryPresentation.swift:27-178`) | `originatingSystem` is file-supplied text (filtered to a safe alphabet), so keep it out of the strip; `sourceUnit` is never shown | Units for mesh formats |
| MIDI | `midi.format`, `trackCount`, `ticksPerQuarter`, `durationSeconds`, `events.count` (`PC/BinaryPreviewContracts.swift:47-60`) | None | None |
| Notebooks | Cells shown and total exist only inside the derived document (`PR/SafeNotebookDocument.swift:120`) | None | Typed counts on `SafeNotebookDocument` |
| Images, comics, covers | `images[].pixelWidth`, `pixelHeight`, `role`; `SafePreviewModes.imagePageTotal` | None | None |
| All | No field says whether `text` is source or an app-made summary | A naive strip misstates summaries | A `TextPresentation` provenance field (contract) or a renderer rule keyed on `SafeSchemaLabels.formats` |

### Copy inventory for ux-copy

Word counts are English. "Split" means the state needs a title and a body; a named budget field is the value the body would quote.

| Key | Words | Needs | Note |
|---|---|---|---|
| `failure.unsupported` | 5 | split | Straight apostrophe, contraction |
| `failure.missingFile`, `failure.unreadable` | 7, 7 | split; next step (moved or deleted; check access) | "source file" is jargon |
| `failure.notRegularFile` | 6 | split | "Choose" is the wrong verb in Finder |
| `failure.unavailableContent` | 7 | split; next step (download it first) | None |
| `failure.tooLarge` | 7 | split; `maxInputBytes` or `maxOutputUTF8Bytes` of the registration budget | Merges input and output size |
| `failure.binary`, `failure.encrypted` | 11, 10 | split | No next step in `binary` |
| `failure.unsupportedEncoding` | 7 | split; name UTF-8 and UTF-16 | None |
| `failure.malformed` | 7 | split | Wrong for 0-byte files (CH-17) |
| `failure.structureLimit` | 7 | split; `maxJSONDepth` 64 or `maxJSONNodes` 20,000 | Merges two limits |
| `failure.lineLimit` | 7 | split; `maxTextLines` 20,000 or `maxLineUTF8Bytes` 32 KiB | Merges two limits |
| `failure.deadlineExceeded` | 7 | split; `maxMilliseconds` (2, 5, 10 or 20 s) | No next step |
| `failure.invalidBudget`, `failure.resourceUnavailable` | 7, 5 | title only | Internal; the second is the missing-resource fallback (`PR/PreviewStrings.swift:807`) |
| `preview.loading` | 2 | spinner label | Fine |
| `preview.disabledTitle`, `preview.disabledDescription` | 5, 15 | already split, rendered inverted | The companion could offer "Enable this type" |
| `preview.cancelled` | 2 | none | Never displayed; no period |
| `settings.extensionUnavailable` | 15 | split | Fine |
| `settings.extensionConfigurationUnavailable` | 28 | split | Developer wording ("App Group configuration and signing") on a user surface |
| Notices | 3 to 23 | one sentence each | `preview.table.truncated` (23, CH-1), `preview.listing.partialNotice` (22, no count), `preview.invisibles.note` (16), `preview.package.notice.signature` (14), `preview.typographyFallbackHint` (13, a settings problem repeated in every preview); `preview.code.notice.truncated`, `preview.code.notice.reformatted` and `profile.status.sampled` lack the final period their neighbours have; `cad.privacyNotice` should name what is omitted (CH-18) |
| `finding.action.copied`, `preview.interaction.copied` | 3, 4 | one string | "Concealed text copied." and "Copied to the clipboard" for one kind of event |

`tools/add_localizations.py` can add the new keys (title and body pairs, state and facts labels, the "Copied" chip) in one step: it writes English into the String Catalog and the other 13 values into the translation inputs, requires a translator comment and all 14 languages, and leaves merging, generation and validation to the follow-up scripts (`tools/add_localizations.py:2-13,42-66`). It cannot change existing values, because it rejects existing keys (`:11,43-44`), so the apostrophe sweep, the CH-1 wording and any rewording of `failure.*` are manual edits of the catalog and the 13 inputs. It cannot delete keys or express plural variants (CH-9). Formatted strings must be called with a literal key, because `validate_localization.py` rejects `PreviewStrings.format` with a variable key (`tools/validate_localization.py:50-63`), so the failure-to-state mapping has to format each case at its own call site.

## Score against best-in-class

**2 of 5.** The substance is good: honest, localized copy, typed findings, tested palettes and a header that collapses. But the chrome has no fixed geometry (the mode control moves), no facts, no designed states, a findings stack that can take more than half a pane, quiet inks that fail AA in three schemes and one false completeness claim, and several Contract 1 elements are blocked by contracts or tooling rather than by effort.

A 5 here is observable. In both hosts and every format, a header of 28 pt or less holds up to four locale-formatted facts, a text-only mode control with its default first, and an info button, and nothing moves when the mode or the zoom changes. Findings collapse to one row (two in compact) whose expansion never exceeds a quarter of the view. Limits appear as one muted bottom sentence with counts where they are known, worded the same way in every family. Loading, empty, unavailable, disabled and settings states are centred views with a symbol, a title, a body that names the limit and the next step, and an announcement. Every copy path shows the same chip, without motion under Reduce Motion. Every chrome ink, selection included, passes AA in all schemes. The listed shortcuts are the ones verified to reach the preview in Finder, and VoiceOver reads facts, findings, mode control, bars, content and limits in that order.

## Recommendations

| # | Impact × effort | What | Doable without a Mac |
|---|---|---|---|
| R1 | High × S | Make the table notice true for partial reads | Yes: a string change whose test runs later |
| R2 | High × M | Contract commit: chrome skeleton with a fixed mode-control position | Yes: layout code and off-screen tests |
| R3 | High × S | `muted` and `hairline` tiers; remove alpha and system inks from chrome | Yes: constants and contrast tests |
| R4 | High × M | Findings row with one statement, one action and a 25 % cap | Yes for layout; VoiceOver is partial |
| R5 | High × M | `NativeStateView`, state copy and an empty state | Partial: Finder loading visibility needs a Mac |
| R6 | High × S-M | Decide plurals: tooling or label-colon notation | Partial: the Python tests run here, `plutil` validation needs a Mac |
| R7 | High × M-L | `PresentationFacts` with provenance and per-family providers | Yes: pure derivation with unit tests |
| R8 | Medium-High × M | Typed notices and one limits strip | Yes: renderer code and tests |
| R9 | Medium × M | Carry the effective budget to the renderer; split merged failure keys | Yes: contract and pipeline code with tests |
| R10 | Medium × S-M | One copy callback and the Copied chip | Yes: views and tests |
| R11 | Medium × S | One command table; key-code digits; focus handoff | Partial: Finder key delivery needs a Mac |
| R12 | Medium × M | Info button with an in-view info panel | Partial: popover and tooltip behaviour need a Mac |
| R13 | Medium × M | Density decided before layout; threshold from measurements | No: the threshold needs measured pane widths |
| R14 | Low × S | Small fixes: safe area, selection colour, MIDI and CAD wording, confirmation timeout, inset constant | Partial: safe area and selection need a Mac |

**R1.** Reword `preview.table.truncated` so it never claims completeness ("Columns, rows or long cells beyond the table limits are not shown here. Source shows them.") and drop the duplicate partial-read statement when R8 lands. Files: `PR/Resources/Localizable.xcstrings` and `tools/localization/translations/*` (ux-copy; a manual edit because the key exists). Tests: `RT/Tabular/NativeTablePreviewViewTests.swift:148` keeps comparing with the key; add a renderer test with `truncatedSourceBytes` set and 70 columns that asserts no completeness claim. Risk: 13 translations to update by hand.

**R2.** The lead's contract commit (shapes below): `PreviewChrome`; a header layout guide in which the mode control has a constant top; notes below the control or in the limits slot; zoom as a chip; a content layout guide that every content view pins to; a bottom limits slot; `accessibilityChildrenInNavigationOrder`; a test accessor for chrome text. Keep the existing direct subviews in their current order. Files: `PR/NativePreviewView.swift`, `PR/Interaction/NativePreviewView+Interaction.swift`, new `PR/PreviewChrome.swift`. Prerequisites: lead approval as a shared contract. Tests (`RT`, off-screen window): the mode control's frame is identical across Source, Rendered, Profile, Invisibles and a zoom step; navigation order; the two header-geometry tests rewritten; `completedPasses == 1` kept in `RT/NativeInitialLayoutTests.swift`. Risks: the single-layout-pass invariant and the six status-line lookups.

**R3.** Add `muted` and `hairline` to `NativeSchemePalette` (one file; no test constructs it), put `muted` into `textColors` so the AA and 7:1 tests cover it, seed it from each scheme's comment colour, and add an 11 pt size cue where body headroom is under about 1.5×. Replace every alpha and `secondaryLabelColor` ink in chrome, dim the gutter numbers and draw a 1 px hairline. Files: `PR/NativeColorSchemes.swift`, `PR/NativeTextAppearance.swift`, `PR/LogicalLineNumberGutter.swift`, `PR/Interaction/OutlineFilterBar.swift`, `GoToLineBar.swift`, `PR/Findings/NativeFindingsBanner.swift` (the table, MIDI and tree lines belong to other workstreams). Tests: `RT/Settings/ColorSchemeContrastTests.swift` gains muted, hairline and "muted differs from foreground" cases, plus a rendering test that composites each chrome label's colour on the palette background. Risk: Solarized hierarchy depends on the size cue.

**R4.** One `PreviewFindingsRow`. Collapsed: the most severe glyph, "N values hidden. Selecting and copying use the hidden text." when `redactionCount > 0` (decision 021), otherwise "N things to check", and Show details. Expanded: a scroll view capped at a quarter of the view height, decoded text clipped to two lines in the row, the cloud-folder warning first. A concealment glyph other than `info.circle`; Copy Concealed Text only in Rendered and Invisibles, Copy All elsewhere. Files: `PR/Findings/*`, `PR/NativePreviewView.swift:320`. Prerequisites: R2, R3, R6. Tests: rewrite the six `RT/Findings/FindingsBannerTests.swift` tests; add height bounds with 32 findings at 400 pt and the sentence present exactly when something is concealed. Risk: the sentence must fit two lines in every language at compact width.

**R5.** `NativeStateView` plus `NativeStateContents`, a mapping that formats each case at a literal call site; title and body keys for every failure through `add_localizations.py`; an empty state when a ready presentation has 0 bytes and no text; an announcement on every state; header, facts and content hidden; no action in Finder. Ask the lead for a pipeline rule so 0-byte structured files are not reported as malformed. Give `NativePreviewPane` an optional outcome and a loading flag so Try Preview keeps one native view (with ux-companion). Files: new `PR/NativeStateView.swift`, `PR/NativePreviewView.swift:246-256,330-345,459-477,765-785`, `PR/PreviewStrings.swift`, `PR/NativePreviewPane.swift` (owned by no workstream in decision 026). Tests: every `PreviewFailure` maps to a non-empty title and body in 14 languages; badge and facts hidden; announcement recorded through `announcementHandler`; spinner delay with an injected clock; 0-byte text, JSON and CSV. Risk: the Finder loading question (CH-11).

**R6.** Decide before any count copy is written: extend generation, merging, validation and `add_localizations.py` to emit `.stringsdict` with CLDR plural categories, or keep "Lines: 1,204" notation in chrome. Files: `tools/*` (lead), the String Catalog. Tests: `tools/test_localization.py` cases for variants and placeholder parity per category; `RT/LocalizationTests.swift`.

**R7.** `PresentationFacts` with per-family providers registered under markers, as `PresentationNotices` does, and a provenance rule (a `TextPresentation` field from the lead, or a renderer rule keyed on `SafeSchemaLabels.formats`). Each fact is one complete localized template and the separator is its own key, so no translated fragments are concatenated. Order: text family first, then table, outline, listing, 3D and MIDI; data and package providers come from their workstreams. Prerequisites: R2, R6. Tests: per family; facts never contain source values (fixtures with secret-like file and column names); locale formatting in German, Russian and Hindi; partial reads report shown and total bytes.

**R8.** `PresentationNotice` with a kind (limit, fallback, provenance) and its text, with `PresentationNotices.lines(for:locale:)` kept as a shim (six calls in three test files, one of them in the diagrams target); one bottom strip; the wording "Showing the first {shown} of {total}" where the total is known and "Showing the first {shown}" otherwise; table and listing notices move into the strip with ux-modes-structure; math and BibTeX notes only in rendered modes. Tests: typed notice tests; a CSV that is both partial and truncated shows exactly one partial statement.

**R9.** Add `PreviewLimit` and a pipeline entry point that returns the outcome with its effective budget, for example a `PreviewResult` holding `outcome` and `budget`, used by both hosts and passed to `display`. This leaves the 41 `== .unavailable(.limit)` assertions in 17 test files untouched; giving `PreviewFailure` associated values would change all of them and every `catch PreviewFailure.x`. Split `tooLarge`, `structureLimit` and `lineLimit` into one key per limit. Files: `PC/PreviewModels.swift`, `CORE/PreviewPipeline.swift` (lead), the two hosts, `PR/NativePreviewPane.swift`. Tests: `PreviewCoreTests` for the budget per registration family; state copy names the right value.

**R10.** A copy callback adopted by a text-view subclass (overriding `copy(_:)`) and by the outline, table, tree and contents views; a chip in a reserved slot beside the info button for 1.5 s, without animation when `accessibilityDisplayShouldReduceMotion` is on; one "Copied" string; an announcement; the timer cancelled by a new generation and by `suspendResources()`; an injectable pasteboard in `MarkupContentsView`. Prerequisite: the callback in the contract commit, since the copy sites span three workstreams. Tests: each copy path produces one chip and one announcement; a new request cancels the chip.

**R11.** One `PreviewCommand` table (title key, key, modifiers, modes) drives `PreviewShortcut`, the context menu and the shortcut list; digits match by key code, which fixes ⌘0 on AZERTY and enables ⌥⌘1 to ⌥⌘5 for modes; an explicit key-view loop; focus moves to the new content after a mode switch when it was inside the preview. Tests: key-code cases in `RT/Interaction/InteractionLogicTests.swift`; a focus test after switching from Source to Outline. Risk: Finder's own ⌘F, ⇧⌘C and ⇧⌘G may win in Finder, so list only verified shortcuts there.

**R12.** Make the badge an `NSButton` (22 pt target, accessibility label) that opens an in-view info panel: read-only, processed on this Mac, "Preview by %@", the concealed count and the commands of the current mode from R11. Try a popover only after the Mac check. Tests: update the six badge references; panel content per mode.

**R13.** Decide density in `display` and `layout()` from the view's width, with hysteresis, before `configureDocumentSize()`; record the threshold only after measuring; let `NativePreviewPane` force regular density for the Theme sample. Tests: the switch adds no layout pass (`LayoutPassCounter`, `RT/NativeInitialLayoutTests.swift:9-26`); hysteresis.

**R14.** Anchor the header to `safeAreaLayoutGuide`; add selection colours to the palette or test system selection contrast; word the CAD note as "Author, organization, file name and dates are not shown."; drop the MIDI sentence or the Summary row; clear the Copy Concealed confirmation after a few seconds; replace the 25 inset literals with `PreviewChrome.inset`.

### Shapes for the shared contracts

```swift
// PR/PreviewChrome.swift: the one owner of chrome metrics; values are targets until measured.
@MainActor enum PreviewChrome {
    enum Density: Equatable, Sendable { case compact, regular }
    static let inset: CGFloat = 12                 // 25 literals in 9 files today
    static let headerHeight: CGFloat = 28
    static let rowGap: CGFloat = 6
    static let accessoryHeight: CGFloat = 30       // PreviewAccessoryBar.height
    static let findingsMaximumFraction: CGFloat = 0.25
    static let infoButtonSide: CGFloat = 22
    static let chipDuration: Duration = .milliseconds(1_500)
    static let spinnerDelay: Duration = .milliseconds(300)
    static var compactWidth: CGFloat { 480 }       // placeholder until Finder pane widths are measured
    static let compactHysteresis: CGFloat = 24
    static func density(forWidth width: CGFloat, previous: Density) -> Density
    static func factsFont() -> NSFont              // 11 pt
    static func stateTitleFont() -> NSFont         // 15 pt semibold
    static func stateBodyFont() -> NSFont          // 13 pt
}

// PR/PresentationFacts.swift: value-free; the strip formats it with the presentation locale.
struct PresentationFacts: Equatable, Sendable {
    enum Fact: Equatable, Sendable {
        case encoding(TextEncoding), lines(Int), size(Int64), shownSize(shown: Int64, total: Int64)
        case grid(rows: Int, columns: Int, rowsAreLowerBound: Bool)
        case records(Int, RecordKind)              // records, cues, pages, cells
        case nodes(Int)
        case listing(files: Int, folders: Int, isLowerBound: Bool, listedBytes: Int64?)
        case geometry(faces: Int, bodies: Int?, extentMillimetres: SIMD3<Double>)
        case playback(tracks: Int, seconds: Double)
    }
    var facts: [Fact]                              // priority order: four shown regular, two compact
}
enum PresentationFactsProviders {                 // families add one line below their marker
    static func facts(for presentation: TextPresentation, modes: SafePreviewModes) -> PresentationFacts
    static func facts(for geometry: GeometryPresentation) -> PresentationFacts
}

// PR/PresentationNotices.swift: typed, with the old entry point kept as a shim.
struct PresentationNotice: Equatable, Sendable {
    enum Kind: Sendable { case limit, fallback, provenance }
    let kind: Kind
    let text: String
}
extension PresentationNotices {
    static func notices(for presentation: TextPresentation, locale: Locale) -> [PresentationNotice]
    // lines(for:locale:) becomes notices(for:locale:).map(\.text)
}

// PR/NativeStateView.swift
struct NativeStateContent: Equatable {
    enum Kind: Equatable {
        case loading, empty, unavailable(PreviewFailure), disabled, settingsUnavailable, configurationUnavailable
    }
    let kind: Kind
    let title: String                              // formatted at literal call sites
    let body: String
    let action: StateAction?                       // always nil in the Finder extension
}
enum StateAction: Equatable { case openFile, enableFormat(FormatID), showSource }
@MainActor final class NativeStateView: NSView {
    var onAction: ((StateAction) -> Void)?
    func show(_ content: NativeStateContent, palette: NativeTextPalette)
    func showLoading(generation: UUID, after delay: Duration)   // nothing appears if content arrives first
    func clear()
}
```

**Fit with `NativePreviewView`.** Keep `statusLabel`, `modeControl`, `scrollView` and the other direct subviews in their current order and append the new facts label, findings row, limits label, chip and state view after `accessoryBar`, because 32 test lookups take the first direct subview of a type. Add `headerGuide` and `contentGuide` (`NSLayoutGuide`). Constraints that move: the status top and the two badge arrangements (`:156-168`) give way to the header guide, in which the mode control (`:182-185`) has a constant top and `modeTop` (`:145`) disappears; the banner top (`:181`) follows the header; the accessory gap (`:172`) is 0 while the bar is hidden; content tops (`:194,197,201,739,805`) and bottoms (`:198,202,211,740,806`) pin to `contentGuide`, which ends above the limits slot; 3D stops anchoring to the status label (`:805`). Methods that change: `updateHeaderLayout()` (`:591-601`) becomes `updateChrome()`; `configureModes()` (`:603-615`) loses its height and top constants; `display` (`:318-329`) routes notes to the findings row, a note line below the control and the limits slot; `clearContent(status:)` (`:459-477`) becomes `showState(_:)`; `message(for:)` (`:765-785`) moves into `NativeStateContents`; `composedStatus` (`...+Interaction.swift:38-49`) becomes the zoom chip; `layout()` (`:442-445`) settles density before `configureDocumentSize()`.

**Minimal shared-core edit and blast radius.** One lead commit: the palette fields and their contrast tests; `PreviewChrome`, `PresentationFacts`, typed notices with the shim and `NativeStateView` (unused at first); the guides and slots with the fixed mode-control position and the zoom chip; a chrome-text test accessor with the six status helpers migrated (`RT/Interaction/InteractionTestSupport.swift:58-60`, `RT/Interaction/ZoomBadgeAndReloadRenderingTests.swift:167,181`, `RT/Tabular/SafeDataProfileTests.swift:861-862`, `RT/NativeTextAppearanceTests.swift:159`, `RT/Images/DocumentModesAndNoticesTests.swift:161-162`); the copy callback protocol; the shared strings through `add_localizations.py`. Rewritten now: the two header-geometry tests. Rewritten when R4 and R8 land: the six findings-banner tests and seven table and listing notice assertions (`RT/Tabular/NativeTablePreviewViewTests.swift:132,148-149`; `RT/Listings/ListingViewTests.swift:158,162,300,306`). Untouched: the 19 mode-control and 7 scroll-view lookups, the 41 limit-failure assertions, the six `PresentationNotices.lines` and four `DocumentPresentationNotices.lines` calls, and the single-layout-pass tests, which must keep passing.

## Verification plan

**Static checks that run here now.**

```sh
python3 tools/test_localization.py
python3 script/sync_manifests.py --check
python3 script/generate_appearance_samples.py --check
rg -n "withAlphaComponent|secondaryLabelColor" Packages/PreviewCore/Sources/PreviewRenderers   # no chrome hits after R3
rg -n "constant: -?12\b|left: 12|width: 12, height: 12" Packages/PreviewCore/Sources/PreviewRenderers  # only PreviewChrome after R2
rg -n "PreviewStrings\.format\(\s*[a-z]" Packages/PreviewCore/Sources Apps Extensions           # no variable keys
```

The contrast figures in CH-6 and CH-7 come from a scratch script that applies the WCAG formula to `NativeColorSchemes.swift`; R3's Swift test replaces it.

**Mac checklist, in order.** Record the OS build, hardware, Xcode and Swift versions, the host surface, what was observed and what was not, in a new `docs/validation/` record. Do not reset caches, kill Finder or change system extension preferences.

1. `./script/build_and_run.sh --check`, `--check-compiler` and `--test`: record test counts and the new chrome tests.
2. `swift test --package-path Packages/PreviewCore --filter "PreviewRenderersTests"`: confirm the layout-pass and contrast tests.
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/benchmark_release_native_renderer.py --build-only`, then the same with `--skip-build --output .build/performance/release-native-renderer-chrome-<date>.json`: warm p95 for text, JSON and CSV may not exceed the recorded values by more than 10 ms (gate 11).
4. A signed build (`./script/build_and_run.sh --verify`, as in `shared-settings-configuration.md`) with synthetic fixtures in an ignored `.build/finder-host-*` folder, on macOS 15 and 26, in the Space-bar panel and the preview pane:
   1. Loading: a 15 MB ZIP and a STEP file. Record whether the system spinner or SpacePane's state is visible, and the time to first content.
   2. Widths: the Accessibility Inspector frame of the preview at the panel's default and minimum size, the preview pane at its narrowest and widest in column and list views, gallery view and full screen. This sets `compactWidth`.
   3. Tooltips on the badge and on a long table cell; the text view's context menu; any popover or info panel (it opens, closes with Escape or a click outside, and never takes Space or Escape from Quick Look).
   4. Keys with the text focused and unfocused: ⌘F, ⌘G, ⇧⌘G, ⌘L, ⇧⌘C, ⌘+, ⌘−, ⌘0 on US and French AZERTY layouts, and ⌥⌘1 to ⌥⌘4. Record which reach the preview and whether Finder acts instead (use a scratch folder). Confirm Space, Escape and the arrows still drive Quick Look.
   5. VoiceOver: the VO-Right order through header, findings, mode control, bars, content and limits; the mode control's label; state announcements. Full Keyboard Access Tab order.
   6. The Tahoe title bar with a long file: does any chrome sit under the glass?
   7. Reduce Motion (chip), Increase Contrast and Reduce Transparency; selection colour in Solarized Light and Dracula with the panel key and not key.
   8. German, Russian and Bengali at the narrowest pane: header fit, findings row at most two lines, the privacy sentence never truncated.
   9. Zero-byte `.txt`, `.json` and `.csv` files and an empty folder.

## Open questions for the owner

1. May provenance notes (signatures not verified, certificate trust not checked, CAD metadata, Markdown offline, approximated formulas) move into the info panel, or must they stay on the surface? The answer decides whether the limits strip is one line or a stack.
2. Plural forms: build plural tooling for 14 languages, or keep "Lines: 1,204" notation in chrome?
3. In compact width, may the gutter hide when the user has turned line numbers on?
4. Should the outline and table filter bars open on demand, as gate 1 requires, or stay visible, as the analysis's "visible when idle" asks?
5. After a Mac experiment, keep Quick Look's spinner (handler when content is ready), or call the handler early and show SpacePane's own loading state?

## Notes for other dimensions

- **structured-views:** the CH-1 notice lives in `PR/NativeTablePreviewView.swift:151-155`; table and tree copies are silent (`PR/NativeTablePreviewView.swift:478-482`, `PR/Listings/NativeListingTreeView.swift:302`); the filter status and tree icons use system secondary ink (`PR/NativeTablePreviewView.swift:287`, `PR/Listings/NativeListingTreeView.swift:176`); keyboard mode switching needs `PR/Interaction/PreviewShortcut.swift` and `...+Interaction.swift`, which are outside your ownership list; always-visible filter bars conflict with gate 1.
- **documents-media-3d:** the pages view binds Space and the arrows when focused (`PR/Images/NativeImagePagesView.swift:351-376`) and the 3D view binds the arrows (`PR/NativeGeometryPreviewView.swift:375-392`), against principle 2; a floating 3D control cluster is an overlay, which Contract 1 forbids, so the lead should reconcile the two; `MarkupContentsView` writes `NSPasteboard.general` directly (`PR/Markup/MarkupContentsView.swift:181-186`); the CH-18 wording for MIDI and CAD; math and BibTeX notes show in Source (`PR/Markup/MarkupRendering.swift:42-49`).
- **companion:** Try Preview drops the native pane while loading (`APP/Views/DirectPreviewView.swift:37-44`, `APP/Models/PreviewSession.swift:78-84`); the Theme sample's spinner covers the badge (`APP/Views/AppearanceSampleView.swift:50-55`); the sample is about 376-404 pt wide and would render compact; only the companion can offer "Enable this type" in the disabled state.
- **performance:** a 300 ms spinner delay still shows for warm JSON (p95 434 ms, `PLAN.md:160`); density must not add a layout pass; count facts at derivation, not per display.
- **security-privacy:** CAD `originatingSystem` is file-supplied text shown in the 3D summary (`PC/GeometryPresentation.swift:83-103`), so keep it out of the facts strip; decoded hidden text (up to 512 characters) is shown verbatim by design, so clip it in the collapsed row.
- **accessibility-localization:** no plural support (CH-9); AZERTY shortcut matching (CH-16); system secondary ink on palette backgrounds (CH-6); the apostrophe sweep needs per-language rules (Hausa apostrophes are partly orthographic, Turkish uses them before suffixes); the mode control's label and navigation order (CH-14).
- **architecture:** decision 026 leaves `PR/NativePreviewPane.swift`, `PR/Interaction/PreviewShortcut.swift` and the extension's `PreviewViewController.swift` unowned, though states, density, the chip and keyboard work need them; `PR/PresentationNotices.swift` holds eight family markers, five of them in use, but is listed as ux-chrome's; 32 test lookups make subview order a de facto API.
- **platform-release:** completion-handler timing (CH-11); popovers, tooltips, menus and key equivalents in the remote host; the safe area under the Tahoe title bar (CH-20).
- **thumbnails:** nothing from this dimension.
