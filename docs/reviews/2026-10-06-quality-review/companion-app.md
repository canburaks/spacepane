# Companion app review — 2026-10-06

Reviewed from source only, on Linux, on 2026-10-06. Nothing was compiled, run, rendered or measured; every runtime statement below is either inferred from the Swift sources or quoted from the repository's validation records, and each says which. The dimension is the companion's single window: the shell and fixed sidebar, General, File Types, Theme, About and the Developer Mode Try Preview page; every status string and tone; the setup guidance and System Settings link; the Quick Look conflict scan; the Theme sample, schemes, typography and syntax controls, profiles and theme transfer; bulk actions; menus and shortcuts; window behaviour and restoration; and the companion-facing parts of `PreviewPreferences`. Verdict: the models underneath are careful and well tested and the information architecture is right, but the window still says more than it can know in two visible places (a File Types subtitle that promises Finder routing, and a green success state that persists even after a failed save), and two elements of Contract 2 (the renderer pill and the scheme gallery) depend on shared contracts that decision 026 assumes but does not define, while its file ownership leaves out the store and models that Undo, conflict markers and the Try Preview inspector need.

## Scope and method

Paths are relative to the repository root. Companion files are cited by file name (every name under `Apps/PrevApp/` is unique) and `Packages/PreviewCore/Sources/` is shortened to `PC/`.

Read in full: all 46 Swift files under `Apps/PrevApp` (3,624 lines across `App`, `Models`, `Stores`, `Support`, `Views`, `Views/Components`); the structure of `Apps/PrevApp/Resources/AppearanceSamples.json` (version 1, 76 samples, 203,610 bytes); `script/test_companion_models.py`, `script/test_appearance_interactions.py`, `script/stage_companion.py`; the companion-facing `PreviewPreferences` sources (`PreferenceStore.swift`, `PreferencesLocation.swift`, `BoundedPreferencesData.swift`, `AppearanceThemeCodec.swift`). For the contracts the companion consumes: `PC/PreviewContracts/Preferences.swift`, `PreviewAppearance.swift`, `PreviewSyntaxStyle.swift`, `FormatCatalog.swift` and its `FormatCatalog.json`, `PreviewModels.swift`, `PartialInputContracts.swift`; `PC/PreviewCore/PreviewPipeline.swift`; `PC/PreviewRenderers/PreviewStrings.swift`, `HostedConfiguration.swift`, `NativePreviewPane.swift`, `NativeTextAppearance.swift` (header), `SafePreviewModes.swift`; the preview extension's settings lookup (`Extensions/PrevPreviewExtension/PreviewViewController.swift:30-60`); `Configuration/app.entitlements`, `App-Info.plist`, `Branding.xcconfig`, `Metadata.xcstrings`. Outlined `Tests/Integration/CompanionModelChecks.swift`, `SettingsModelChecks.swift` and `AppearanceInteractionChecks.swift`.

Documents: `AGENTS.md`, the brief, decision 026, the competitor UX/UI analysis, the self-audit; decisions 003, 005, 006 (direct file drop), 008, 010 and 023; validation records `companion-redesign-2026-10-04.md`, `settings-2026-10-05.md`, `single-window-tabs.md`, `direct-file-drop.md`, `ui-quality-2026-10-04.md`, `shared-settings-configuration.md` and, for routing evidence, `finder-matrix-2026-10-04.md`; the companion recommendations of the closest-rivals (4–8), breadth (3, 4, 6, 10), code (4, 5, 8), data (10) and folders (9) reports; the platform baseline's HIG settings and sidebar rules (A9, A10); PLAN's UX program section.

Run here, all passing: `python3 script/sync_manifests.py --check` (280 preview and 276 thumbnail content types, 53 imported declarations), `python3 script/generate_appearance_samples.py --check` (76 formats), `python3 tools/test_localization.py` (13 tests). Two read-only scratch scripts (outside the repository) listed every `PreviewStrings` key the companion uses with its English value and its longest translation, and measured the catalog's filename-pattern captions.

Out of scope: renderer internals beyond what the companion embeds, the extensions' own views, thumbnails, the CAD helper, the website, and performance budgets (handed to the performance dimension where the companion touches them).

## Current state

Strengths to preserve:

- One funnel for every settings change, with validation, fail-closed recovery that a same-value reset still repairs, and a single-writer save loop that drains to the newest revision (`CompanionSettings.swift:121-163`); a slow load cannot overwrite an edit made meanwhile (`:41-59`). Undo can be added once, here.
- Correct, tested group and search semantics: search hides rows but never changes group membership (`FileTypeSettingsGroup.swift:5-16`), a group toggle publishes one atomic change (`CompanionSettings.swift:66-73`, `FileTypeGroupSection.swift:85-90`), and the scope of bulk actions is stated while a search is active (`FileTypeSettingsView.swift:57-65`).
- Catalog-driven pages with no format special-casing; filename patterns keep their technical spelling and only list punctuation follows the locale (`FormatFilenameSummary.swift:4-19`).
- Appearance edits never reread a source: Try Preview reloads only for policy or request-option changes (`PreviewSession.swift:40-54`) and the Theme sample requests a file only when another format is chosen (`AppearanceSampleSession.swift:41-69`); one native pane keeps its identity across resizing (`AdaptiveColumns.swift:3-5`).
- A narrow direct-drop path: one item, metadata-only hover, synchronous URL read, no item providers (`DirectPreviewFileDrop.swift:6-25`, `DirectPreviewDropTarget.swift:63-90`).
- A bounded, read-only provider scanner that never follows links, opens plists with `O_NOFOLLOW`, checks cancellation, drops late results and never claims routing (`QuickLookProviderScanner.swift:35-56,229-292`, `QuickLookProviderDiagnostics.swift:33-54`).
- Inert, strict, 16 KiB-bounded theme transfer guarded by a request generation and an appearance revision (`PC/PreviewPreferences/AppearanceThemeCodec.swift:12-60`, `AppearanceThemeTransfer.swift:60-90`).
- Developer Mode lives only in the companion's defaults under `companion.developerMode` (`CompanionPreferences.swift:4-26`); the shared document has no such field (`PC/PreviewPreferences/PreferenceStore.swift:129-141`). AGENTS is satisfied.
- No literal user-visible strings: a search for `Text("`, `Button("` or `.help("` in `Apps/PrevApp` finds none; everything goes through `PreviewStrings` in 14 languages.
- Accessibility craft: a disclosure button that presents itself as a `DisclosureGroup` (`FileTypeGroupSection.swift:66-72`), steppers with explicit label, value and hint (`PreviewBehaviorSections.swift:45-53`, `AppearanceFontControls.swift:29-35`), combined status elements, the one animation gated on Reduce Motion (`FileTypeSettingsView.swift:157`), stronger strokes under Increase Contrast (`SettingsCard.swift:59`), an RTL-aware chevron (`FileTypeGroupSection.swift:60`).
- Several strings are already exemplary: `setup.unverified`, `settings.providers.guidance`, `settings.providers.none` ("in the folders that could be read"), `settings.saveFailed`.

Window and lifecycle today:

| Aspect | Today | Evidence | Confidence |
|---|---|---|---|
| Scene | One `Window`, hidden title bar, default 1040×720, minimum 820×560 from the content frame, presented at launch | `CompanionApp.swift:21-28`, `CompanionShell.swift:41` | Verified in code; window observed (`docs/validation/companion-redesign-2026-10-04.md:47-58`) |
| Closing | Closing the sole `Window` may quit the app; decision 005 accepts it | `docs/validation/single-window-tabs.md:38` | Recorded |
| Restoration | The page is App-level `@State` and always starts on General; the sample type resets to JSON; search text and collapsed groups reset on every page switch because each page is rebuilt | `CompanionApp.swift:13`, `AppearanceSampleSession.swift:24`, `FileTypeSettingsView.swift:7-8`, `CompanionShell.swift:78-88` | Verified in code; frame restoration needs a Mac |
| Keyboard | The sidebar is a native `List(selection:)`, so arrow keys work once it has focus; View menu Command-1…5; Command-comma selects File Types; Command-O in Developer Mode | `CompanionSidebar.swift:16-30`, `CompanionApp.swift:45-64`, `CompanionRoute.swift:20-27` | Menu routes observed (`companion-redesign-2026-10-04.md:53`); Full Keyboard Access not verified (`:94`) |
| VoiceOver | Native list rows with `Label`; identity and footer are combined elements; page titles carry the header trait | `CompanionSidebar.swift:42-45,63,84`, `CompanionPage.swift:26` | Needs a Mac |
| Text size | Semantic styles plus fixed metrics; no record shows the window under a larger text setting | `companion-redesign-2026-10-04.md:94`, `docs/validation/ui-quality-2026-10-04.md:105-116` | Needs a Mac |
| Long languages | German, Portuguese and Russian rendered offscreen only. Fixed widths: sidebar 224, search 260, font menu ≤170, banner text 240–320, type cell ≥190, sample ≥300 high, column breakpoints 620 and 720 | `companion-redesign-2026-10-04.md:38-39`; `CompanionStyle.swift:10,14`; `FileTypeSettingsView.swift:87`; `AppearanceFontControls.swift:26`; `GeneralView.swift:138-143`; `FileTypeGroupSection.swift:20`; `AppearanceSampleView.swift:32`; `AppearanceSettingsView.swift:19` | Verified in code |
| Motion, transparency, contrast | One gated animation; no materials, so Reduce Transparency has nothing to adapt; Increase Contrast strengthens card, search, table, sample and pane strokes | `FileTypeSettingsView.swift:90,135,157`, `SettingsCard.swift:59`, `AppearanceSampleView.swift:37`, `DirectPreviewView.swift:57,92` | Verified in code |
| Drag region | The transparent title-bar strip above sidebar and page; the page header itself is not a drag area | `CompanionApp.swift:26` | Inferred; needs a Mac |

## Findings

| ID | Severity | Confidence | Title | Evidence | Fix (Minor and Cosmetic) |
|---|---|---|---|---|---|
| CO-01 | Blocker | Verified in code; contradicted by the repo's Finder run | File Types promises that the per-type choice decides what Finder previews | `FileTypeSettingsView.swift:24` (`fileTypes.subtitle`), `:102-106` (`fileTypes.header.state` "Previews" over Enabled/Disabled); `docs/validation/finder-matrix-2026-10-04.md:34-35,57-59` | See below |
| CO-02 | Major | Verified in code | Green tone and check mark for a state the app cannot verify (C2) | `StorageModePresentation.swift:16`; `GeneralView.swift:15,128-129`; `CompanionSidebar.swift:67-69,82`; neutral tone defined but unused (`CompanionStyle.swift:19,26`) | See below |
| CO-03 | Major | Verified in code | Storage summaries ignore failed saves and recovered settings, so General stays green while choices are unsaved or reset to all-off | `CompanionSidebar.swift:67-71`; `GeneralView.swift:15,126-135`; `SettingsSaveNotice.swift:24-29`; `CompanionSettings.swift:52,156` | See below |
| CO-04 | Major | Verified in code; layout arithmetic inferred | The Theme sample scrolls away, and below a 993 pt window it sits under every control (C1) | `AppearanceSettingsView.swift:12,19,40-44`; `CompanionPage.swift:37-42`; `AdaptiveColumns.swift:39-44`; `CompanionShell.swift:41` | See below |
| CO-05 | Major | Verified in code; link behaviour needs a Mac | Setup is a paragraph: no control beside it, the button in another card, an unverified deep link, no Quick Look hop, no extension names (C3) | `GeneralView.swift:32,90-124,153-165`; key `setup.steps`; `companion-redesign-2026-10-04.md:93` | See below |
| CO-06 | Major | Verified in code | Eight one-click actions overwrite saved choices with no undo; C6 and Contract 2 list five | `FileTypeSettingsView.swift:48-50`; `FileTypeGroupSection.swift:36-42,85-90`; `AppearanceSettingsView.swift:13`; `AppearanceProfilesView.swift:97-107`; `AppearanceThemeTransfer.swift:81`; `PC/PreviewContracts/Preferences.swift:141-155` | See below |
| CO-07 | Major | Verified in code; sandbox behaviour needs a Mac | The conflict scan is the last card, reports prose only, cannot see macOS's built-in previews or apps in subfolders, and is untested in the sandbox (C11) | `GeneralView.swift:23`; `QuickLookProviderDiagnosticsView.swift:52-100`; `QuickLookProviderScanner.swift:74-85,225-227`; `docs/validation/settings-2026-10-05.md:45`; `finder-matrix-2026-10-04.md:57-59` | See below |
| CO-08 | Major | Verified in code | Contract 2's renderer pill has no source: the catalog's `presentation` is text or geometry, and the opening view is chosen at runtime inside the renderer | `PC/PreviewContracts/FormatCatalog.swift:35,50` (70 text, 6 geometry in `FormatCatalog.json`); `PC/PreviewRenderers/SafePreviewModes.swift:97-148` | See below |
| CO-09 | Minor | Verified in code | The Source code checkbox exposes 252 patterns (about 2,000 characters) as its VoiceOver label and tooltip; two visible lines hide the scope | `FileTypeCell.swift:16-33`; `FormatFilenameSummary.swift:9-19` | First few patterns plus a localized "and n more"; full list stays searchable |
| CO-10 | Minor | Verified in code | Bespoke search box: no Command-F, Escape does not clear, fixed 260 pt, focus by tap gesture, result count not announced (C7) | `FileTypeSettingsView.swift:69-95` | `NSSearchField` representable with a view-scoped Command-F |
| CO-11 | Minor | Verified in code | Group rows state one fact three ways and color "Enabled" and "Partially enabled" alike (C7) | `FileTypeGroupSection.swift:43-48` | Keep the tri-state checkbox and "n of m"; drop the word and the header |
| CO-12 | Minor | Verified in code | The limits card says larger files show an explanation; text, source code, logs, CSV/TSV, INI and caption files show their leading part | `GeneralView.swift:58` (`general.limits.fileSizeHint`); `PC/PreviewContracts/PartialInputContracts.swift:4-34`; `PC/PreviewFormats/TextAdapter.swift:6`, `PC/PreviewFormats/SourceCodeAdapter.swift:12`, `PC/PreviewFormats/Code/LogAdapter.swift:18`, `PC/PreviewFormats/Code/CodeFormatAdapters.swift:21-22` | "Larger files show their first part when the format allows it, otherwise an explanation." |
| CO-13 | Minor | Verified in code | The app-only banner says the extensions "use their defaults"; they show a configuration notice and generic thumbnails instead | `GeneralView.swift:131` (`setup.notConfigured`); `Extensions/PrevPreviewExtension/PreviewViewController.swift:39-42`; `PC/PreviewThumbnails/ThumbnailPolicy.swift:35` | Describe what the extensions do; reachable only in unsigned or misconfigured builds |
| CO-14 | Minor | Verified in code | "Preparing preview…" labels loading settings and reading a theme file | `SettingsStorageStatusView.swift:21`; `AppearanceProfilesView.swift:92` | Two specific keys |
| CO-15 | Minor | Verified in code | Theme labels repeat themselves: three current-value subtitles, two hidden-label checkboxes, a section title that is also its disclosure label (C8, C9) | `AppearanceControlsView.swift:27-41`; `AppearanceFontControls.swift:13,37,47-51,60-65`; `AppearanceSyntaxControls.swift:10-18`; `AppearanceLayoutControls.swift:46-49` | One visible, clickable label per control |
| CO-16 | Minor | Verified in code | Font size is a 41-value stepper with its value at the opposite edge; `%.2f pt` shows "13.00 pt" and mixes digit systems with `.number` values on the same page | `AppearanceFontControls.swift:28-36,67-69`; `AppearanceLayoutControls.swift:21-44`; key `appearance.pointValue`; `AppearanceSampleView.swift:106-107,132-134` | Field plus stepper; a point formatter with 0–2 fraction digits and locale digits |
| CO-17 | Minor | Verified in code | Failures are hard to see or act on: Theme's save notice ends a column about 1,000 pt tall; transfer errors look like success; no retry or recovery action exists | `AppearanceSettingsView.swift:36`; `AppearanceProfilesView.swift:48-52`; `SettingsSaveNotice.swift:11-21`; `CompanionSettings.swift:126-127` | Notice at the top with Try Again; caution symbol for errors |
| CO-18 | Minor | Verified in code | Nothing is restored: the page, the sample type, search text and collapsed groups all reset | `CompanionApp.swift:13`; `AppearanceSampleSession.swift:24`; `FileTypeSettingsView.swift:7-8` | Remember the page in companion defaults; keep page state in the shell |
| CO-19 | Minor | Verified in code | "Settings" (no ellipsis) opens File Types; "Help" opens About, which has no help; About uses a question-mark symbol (C13) | `CompanionApp.swift:55-57,70-72`; `CompanionSymbol.swift:9` | Recommendation 9 |
| CO-20 | Minor | Verified in code; look needs a Mac | The sidebar is a native source list painted opaque; the self-audit's `.regularMaterial` fix would not give sidebar vibrancy, and neither gives the macOS 26 glass (C14) | `CompanionSidebar.swift:16,26-30`; `CompanionStyle.swift:35`; `CompanionShell.swift:33-37` | Recommendation 15 after observation |
| CO-21 | Minor | Verified in code | Try Preview prompts three times and its subtitle restates the empty state even with a file open (C12) | `DirectPreviewView.swift:14-16,45-50,64-87` | Pane-wide drop, one Open button, name in the header |
| CO-22 | Minor | Verified in code | File Types shows "0 of 76 enabled" and unchecked boxes while settings load; the sidebar hides its count in the same state | `FileTypeSettingsView.swift:23-29`; `CompanionSettings.swift:12`; `CompanionSidebar.swift:72` | Hide counts and boxes until loaded |
| CO-23 | Minor | Verified in code | About says license notices are included but offers no way to read them; the color-scheme notice is not bundled; three link rows show the same host | `AboutView.swift:23-28,104-123`; key `about.acknowledgements.body`; `script/stage_companion.py:69` | Reveal the bundled notices in Finder; bundle both |
| CO-24 | Minor | Inferred; contrast needs a Mac | Status words and link titles use the user's accent color as text; a yellow or orange accent drops far below 4.5:1 | `FileTypeGroupSection.swift:48`; `AboutView.swift:86` | Primary or secondary text; link color for links |
| CO-25 | Minor | Verified in code | The scan uses literal roots and `getpwuid`, skips subfolders such as Utilities or vendor folders, and its empty result does not say so | `QuickLookProviderScanner.swift:76-85,225-227`; key `settings.providers.none` | Platform directory APIs; one bounded subfolder level; say what was not read |
| CO-26 | Minor | Verified in code | The unavailable banner repeats its title in its body | `GeneralView.swift:132-133` | Body says what still works and what to do |
| CO-27 | Minor | Verified in code and Finder run | About states that secrets are hidden and choices apply to Finder previews, without "when SpacePane provides the preview" | key `about.howItWorks.body` (`AboutView.swift:57`); `finder-matrix-2026-10-04.md:59` | Add the condition |
| CO-28 | Cosmetic | Verified in code | Fake traffic lights in the sample frame, the format name twice, and a window title that never names the page | `AppearanceSampleView.swift:64-72,75,104`; `CompanionApp.swift:21` | Remove the dots and one name; page name in the window title |
| CO-29 | Cosmetic | Verified in code | A theme import is dropped silently if the appearance changed during the read | `AppearanceThemeTransfer.swift:72-75` | Say it was not applied and why |
| CO-30 | Cosmetic | Verified in code | Save Profile is disabled without a reason (trailing space, duplicate name); no marker shows which profile matches the current appearance | `AppearanceProfilesView.swift:120-124`; `PC/PreviewContracts/PreviewAppearance.swift:34-39` | Trim, explain, mark the current profile |

**CO-01. File Types promises Finder routing.** The page opens with "Choose which file types are previewed in Finder and Quick Look." and a "Previews" column whose group rows read "Enabled", "Partially enabled" or "Disabled" (`FileTypeSettingsView.swift:24,102-106`). The repository's own Finder run contradicts both: with Plain text and Source code enabled, `.txt` and `.swift` were shown by another provider with the synthetic secret visible (`finder-matrix-2026-10-04.md:34-35,57-59`), and when macOS does pick SpacePane, turning a type off shows SpacePane's disabled notice rather than handing the file to another app (`docs/validation/shared-settings-configuration.md:40`, key `settings.extensionRefreshNotice`). AGENTS says these controls "do not promise a change in macOS provider selection", and principle 11 of decision 026 says nothing may imply that Finder uses this provider; this is the page users open right after setup. Fix: "Choose which file types SpacePane may preview. macOS decides which app previews each file." in 14 languages, remove the "Previews" header and the group state word (CO-11), keep the refresh notice. Effort S.

**CO-02. Green for an unverifiable state.** Storage mode `.shared` maps to `.positive` (`StorageModePresentation.swift:16`), which paints the sidebar dot and the whole footer chip green (`CompanionSidebar.swift:67-69,82`), the General pill (`GeneralView.swift:15`) and a green check badge beside "Settings are shared with the Quick Look extensions" (`:128-129`). The only fact behind it is that the App Group container URL resolved (`CompanionSettings.swift:26-27`); the app cannot know whether the extensions are on, chosen or reading. At first launch the user is told, in green, that all is well before doing anything. The words describe a location and are acceptable; the color and check are not. Fix: the neutral tone that exists and is unused (`CompanionStyle.swift:19,26`), no check mark, one home (recommendation 1). Rule: principle 11.

**CO-03. Green persists through failure.** The footer, pill and banner read only `storageMode` (`CompanionSidebar.swift:67-71`, `GeneralView.swift:15,126-135`). After a failed save (`CompanionSettings.swift:156`), or a recovered load that turned every type off (`:52`), File Types and Theme show a caution notice (`SettingsSaveNotice.swift:24-29`) while General still opens on the green banner, and the storage card that says otherwise sits further down under the limits. The page makes two contradictory statements and colors the wrong one green. Decision 026 shows the storage card only for private-only and unavailable storage, so it would keep this defect. Fix: one presentation derived from storage mode, save state, recovery and loading (recommendation 1). Effort S.

**CO-04. The Theme sample leaves the screen.** The page is one scroll view (`AppearanceSettingsView.swift:12`, `CompanionPage.swift:37-42`). At the 820×560 minimum the content is 547 pt wide (820 minus the 224 pt sidebar, the divider and 48 pt of padding), below Theme's 720 pt breakpoint (`AppearanceSettingsView.swift:19`), so the sample follows about seventeen control rows (`AdaptiveColumns.swift:39-44`). Side by side begins at a 993 pt window; there the sample tops the trailing column but scrolls away with everything else as soon as Text layout or Syntax styles is edited, and Profiles sits under it (`AppearanceSettingsView.swift:40-44`). The page exists to show what a control does, and gate 8 requires the sample on screen at every width. Fix: recommendation 3.

**CO-05. Setup is a paragraph.** The only setup content is a row titled "Turn on the extensions" whose subtitle is the 23-word `setup.steps` and which has no control (`GeneralView.swift:32`). The Open System Settings button lives in the banner card (`:90-124`). The path stops at Login Items & Extensions, before the Quick Look category, the info button, the two switches and Done that Apple's own page describes (`docs/market/ux-research/2026-10-06-system-and-benchmarks.md:165`), and the extension names the user must find are never given. The link is the undocumented `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`; `NSWorkspace.open` returns true whether or not the pane honours it, so the fallback (`GeneralView.swift:159-164`) runs only when the scheme itself fails, and neither is verified (`companion-redesign-2026-10-04.md:93`). Fix: recommendation 4.

**CO-06. No undo where it matters.** Eight actions replace saved choices in one click: Enable All, Disable All and Reset File Type Choices (`FileTypeSettingsView.swift:48-50`); a group checkbox, which erases a mixed group's individual choices (`FileTypeGroupSection.swift:36-42,85-90`); Reset Appearance (`AppearanceSettingsView.swift:13`); Apply profile and Import theme, both of which overwrite unsaved appearance edits (`AppearanceProfilesView.swift:97-103`, `AppearanceThemeTransfer.swift:81`); and Delete profile (`AppearanceProfilesView.swift:104-107`). Enable All also discards every per-type choice because it clears all overrides (`PC/PreviewContracts/Preferences.swift:141-151`). The self-audit's C6 and Contract 2 list five of the eight; Apply, Import and the group checkbox are missing. Fix: recommendation 2; principle 9, gate 9.

**CO-07. The conflict scan is buried and partly blind.** It is the last card on General (`GeneralView.swift:23`) and reports apps and type names as prose with no link to the types (`QuickLookProviderDiagnosticsView.swift:52-100`). It reads only the top level of three folders (`QuickLookProviderScanner.swift:74-85,225-227`), so it misses apps in `/Applications/Utilities` or vendor subfolders, and it cannot see macOS's own built-in previews at all. The Finder run does not name the provider that took `.txt` and `.swift`, on a Mac where another Quick Look product was installed (`finder-matrix-2026-10-04.md:57-61`), so the scan could not have explained that result with certainty. Whether the signed, sandboxed app can list `/Applications` at all is untested (`settings-2026-10-05.md:45`). Contract 2 is right to put the scan beside step 2 and mark types, but an absent marker must never read as "SpacePane will be used". The breadth report calls such a scanner "not sandbox-safe" and "rule-breaking" (`docs/market/ux-research/2026-10-06-breadth-leaders.md:323,331`); AGENTS does not forbid a read-only, bounded, on-demand scan, and decision 023 shipped one, but the sandbox result has to be observed before the scan is promoted. Fix: recommendations 4 and 10.

**CO-08. The renderer pill has no source.** Contract 2 asks for a pill "from the catalog's presentation". That field is `PresentationCapability`, with two cases, `text` and `geometry` (`PC/PreviewContracts/FormatCatalog.swift:35,50`). The view a format opens in is chosen at runtime by `SafePreviewModes.initialMode(for:)`, an internal renderer type that depends on the derived models and on format-specific rules (`PC/PreviewRenderers/SafePreviewModes.swift:97-148`). Only "3D" is derivable today, and a pill computed anywhere else would drift from what the preview shows. Fix: recommendation 12, which needs a lead-owned catalog field and owner decision 1 (JSON in Outline).

### Self-audit C1–C15, verified

| Item | Verdict | Evidence and correction |
|---|---|---|
| C1 | Right | As CO-04. Addition: side by side begins at a 993 pt window, and pinning the column means moving Profiles. |
| C2 | Right, incomplete | Also the 12 % green fill of the whole footer chip (`CompanionSidebar.swift:82`), and the green survives failed saves and recovery (CO-03). |
| C3 | Right | `setup.steps` is 23 words, not 30. A documented alternative to the URL exists (recommendation 4). |
| C4 | Right | Three wordings in four places ("Settings shared", "…with the Quick Look extensions", "…with the extensions."), and the footer repeats the File Types count in a second format ("Enabled file types: 74" against "74 of 76 enabled"). |
| C5 | Right | Nit: `.headline` is 13 pt bold in Apple's macOS type table, not semibold. Contract 2's "20 pt" title has no macOS text style (title2 is 17, title1 22). |
| C6 | Right, incomplete | Five of eight overwriting actions (CO-06). |
| C7 | Right | `FileTypeSettingsView.swift:69-106`, `FileTypeGroupSection.swift:43-48`. |
| C8 | Partly wrong | Wrap long lines, Line numbers and Font ligatures have visible, clickable labels (`AppearanceLayoutControls.swift:14-15,47`). Only Italic (`AppearanceFontControls.swift:47-51`) and Use syntax colors (`AppearanceSyntaxControls.swift:13-17`) hide theirs. The switch/checkbox mix and the stepper are as described. |
| C9 | Partly wrong, incomplete | The first two cards are Color mode and Color scheme (`AppearanceControlsView.swift:13-17`), so look-and-feel does come first. Font family and Font weight also repeat their selection as subtitles (`AppearanceFontControls.swift:13,37`). |
| C10 | Right | No refresh note on Theme. |
| C11 | Right, incomplete | Blind spots and sandbox status (CO-07). |
| C12 | Mostly right | "The file name duplicates the Quick Look title" is wrong for the companion: no Quick Look title exists there, and `DirectPreviewView.swift:20-25` is the only place the name appears. |
| C13 | Right | Also no ellipsis on "Settings", and "Help" instead of "SpacePane Help". |
| C14 | Partly wrong | The sidebar is a native `List(selection:)` in `.sidebar` style (`CompanionSidebar.swift:16,26`) whose background is hidden and repainted opaque (`:27,30`); only the shell is custom. The proposed `.background(.regularMaterial)` blurs content inside the window, of which there is none behind the sidebar, so it would read as a flat tint rather than sidebar vibrancy (inferred; needs a Mac). |
| C15 | Mostly right | The limits render as secondary text values, not controls (`GeneralView.swift:75-80`), so "look editable" is weak. |
| Elsewhere | Two errors | Section 1b's footer would read "Enabled file types: 74" at defaults, not 76, because IGES and STEP are off by default. Section 5 says 200 % enlargement was checked offscreen; the records list large text as not verified and a 26-point offscreen attempt omitted the control glyphs (`companion-redesign-2026-10-04.md:94`, `ui-quality-2026-10-04.md:105-116`). |

### Contract 2, element by element

| Element | Today | Feasibility and what changes | Risks and unknowns |
|---|---|---|---|
| Hierarchy | Page title `.headline` (`CompanionPage.swift:26`), section titles at body size (`SettingsCard.swift:18`), twelve call sites at 10 pt caption size | Feasible, S: a `CompanionTypography` beside `CompanionMetrics`; semantic styles | A fixed 20 pt would not follow a text-size setting; long titles wrap at 547 pt |
| Sidebar material | Native sidebar list on opaque `windowBackgroundColor` (`CompanionStyle.swift:35`) | (a) a behind-window `NSVisualEffectView` with the sidebar material under the list, S; (b) macOS 15's `containerBackground(_:for: .window)` with an opaque page, S, verify in the SDK; (c) `NavigationSplitView` with a fixed, non-collapsible sidebar, M, the only route to the 26 glass sidebar, amends decision 010's mechanism | Today the title-bar strip is the drag area; a draggable page header needs macOS 15's `WindowDragGesture` (verify). Reduce Transparency is handled by the system in (a) and (c). HIG asks for accent-colored sidebar symbols, which the sidebar list style probably already applies (verify) |
| Neutral single-home status | Five surfaces, green (CO-02, CO-03) | Feasible, S: `StorageModePresentation` becomes failure-aware; `SettingsStorageStatusView` only for problems; General's `StatusPill` removed; footer neutral | HIG says not to put critical information at the bottom of a sidebar (`system-and-benchmarks.md:145`), so problems must also appear in the page; decision 026 omits failed-save and recovered states |
| Setup trail | Paragraph plus banner button; URL then app fallback (`GeneralView.swift:153-165`) | Feasible, M: a numbered card; step 2 names the embedded extensions from the app's own `PlugIns` | The pane identifier is undocumented and unverified on 15 and 26; `SMAppService.openSystemSettingsLoginItems()` is documented (ServiceManagement, macOS 13+) and opens Login Items, which macOS 15 turned into Login Items & Extensions (unverified); no documented anchor reaches the Quick Look category |
| Conflict scan beside step 2, per-type markers | Bottom card; each app carries `overlappingFormats` (`QuickLookProviderScanner.swift:21`) | Feasible, M: index by format; `FileTypeSettingsView` gets the diagnostics model, which the shell already owns (`CompanionShell.swift:13,27-28`) | Sandbox readability unverified; blind to built-in previews and subfolders; stale after installs; duration unmeasured |
| Renderer pills | None | Blocked by a missing catalog field (CO-08) | Owner decision 1 |
| Native search and Command-F | Custom `TextField` | On macOS `.searchable` places its field in a toolbar or a split view's sidebar; this window has neither, so it would most likely add a toolbar to the hidden title bar (inferred). Use an `NSSearchField` representable and a Command-F scoped to the File Types view, S | Precedence against the menu and the preview's own find needs a Mac |
| Undo | None | Feasible, S–M: `@Environment(\.undoManager)` is available to any SwiftUI view in the window; `CompanionSettings` is a main-actor class and a valid undo target; register in its single `change` funnel | A focused text field takes Command-Z first (standard); Undo must not cross a recovery reset |
| Pinned sample | `AdaptiveColumns` inside the page scroll view | Feasible, M: a new `Layout` that pins the sample beside or above a separately scrolling controls column, keeping one child identity | At 820×560 the stacked controls get roughly 150–200 pt; accessibility order must be set explicitly |
| Scheme gallery | Two menus (`AppearanceSchemeControls.swift:24-39`) | Feasible, M, with a lead contract: 12 tiles, not 22, because schemes have a polarity (five light, seven dark, `PC/PreviewContracts/PreviewSyntaxStyle.swift:19-38`); palette colors are internal (`PC/PreviewRenderers/NativeTextAppearance.swift:8`) | Live mini-samples would be twelve native panes restyled on every edit; draw swatches instead |
| Theme refresh note | None (C10) | S: one sentence under the sample, shared with File Types | None |
| Try Preview | Three prompts, strip-only drop target | Feasible, M: a parent drop view around the pane (AppKit looks for a registered drag destination up the superview chain, and a non-editable text view does not register for file drags; inferred) | Text selection and drop resolution need a Mac; contract 006 rules out SwiftUI item-provider drops |
| Menus | "Settings" opens File Types; Help opens About | S | "Labelled by destination" conflicts with the standard "Settings…" title (owner question 1) |
| Ownership | 026 gives ux-companion `Views/*`, `Components/*`, `CompanionRoute.swift`, `CompanionApp.swift` | Undo needs `Stores/CompanionSettings.swift`; markers need `Models/QuickLookProvider*.swift`; the inspector needs a new model; tests need `Tests/Integration/*Checks.swift` and `script/test_companion_models.py` | Extend the ownership before work starts |

Facts the Try Preview inspector can show today, all metadata-only:

| Fact | Source | Status |
|---|---|---|
| Extension | `PreviewSession.sourceURL` (`PreviewSession.swift:9`) | Available |
| Resolved type identifier | `URLResourceValues.contentType`; the pipeline resolves it privately and only for suffix misses (`PC/PreviewCore/PreviewPipeline.swift:148-153`) | Needs one metadata read |
| Whether SpacePane declares that type | Resolved type against the catalog's `contentTypes`, which `script/sync_manifests.py --check` keeps equal to the manifests | Derivable; explains the repo's `.env` (`public.data`) and JSON Lines (another product's identifier) results (`finder-matrix-2026-10-04.md:37,40,60-61`), a fact Contract 2 omits |
| Catalog format, enabled or turned off | `PreviewPipeline.inspect` returns `PreviewInspection` (`PreviewPipeline.swift:17-20`, `PC/PreviewContracts/PreviewModels.swift:125-129`) | Available |
| Renderer | Catalog `presentation` (text or geometry); the actual mode is internal | Partial until CO-08 |
| Concealed values, finding kinds, partial or whole | `redactionCount`, `findings`, `truncatedSourceBytes` (`PreviewModels.swift:69,79,84`) | Available |
| Thumbnail policy; other providers | Catalog `thumbnail`; the scan index | Available; after a scan |

### Honesty audit of status strings and tones

Green appears only for the storage state; accent for counts, group words, link titles and drop targeting; orange for problems the app has verified; the neutral tone is defined and never used. After the fixes nothing in the companion needs to be green: the verified local results ("Settings saved", "Theme exported") read fine as neutral text. One tension for the lead: decision 026 rejects status wording such as "enabled", while decision 010 (accepted) chose the enabled-type count for the sidebar and AGENTS speaks of enabling types. The rejection should be read as covering extension and routing status, not the user's per-type choice.

| Key | Text (abridged) | Where and tone | Verifiable by the app | Verdict |
|---|---|---|---|---|
| `status.shared`, `general.banner.sharedTitle`, `settings.shared` | "Settings shared"; "…shared with the Quick Look extensions"; "…with the extensions." | Footer, General pill, banner with check (green); storage card (secondary) | Only that the App Group container resolved | Location wording acceptable; neutral tone; must change on failure (CO-02, CO-03) |
| `general.banner.sharedBody` | "Turn the extensions on in System Settings. macOS chooses…" | Banner, secondary | Instruction | Honest |
| `status.enabledTypes` | "Enabled file types: %lld" | Footer beside the green state | Yes, a count of choices | Reads as system status next to green; drop from the footer |
| `fileTypes.enabledCount` | "%1$lld of %2$lld enabled" | File Types pill (accent), group rows (secondary) | Yes | Honest; shows 0 while loading (CO-22) |
| `fileTypes.subtitle` | "Choose which file types are previewed in Finder and Quick Look." | Page subtitle | No; contradicted by the Finder run | Blocker (CO-01) |
| `fileTypes.header.state` with `format.enabled`, `fileTypes.partiallyEnabled`, `format.disabled` | "Previews" over "Enabled…" | Header; accent or secondary | The choice yes, preview status no | Remove (CO-01, CO-11) |
| `settings.saving`, `settings.saved`, `settings.automaticSaving` | "Saving choices…", "Settings saved", … | Storage card, secondary | Yes, the atomic write returned | Honest; the right success state for the footer |
| `settings.saveFailed`, `settings.recovery`, `settings.storageUnavailable` | "…could not be saved…", "…could not be used…", "…unavailable…" | Caution notices and card lines | Yes | Honest; need actions (CO-17); unavailable title repeated (CO-26) |
| `status.appOnly`, `settings.private`, `general.banner.appOnlyTitle` | "App-only settings", "Finder integration is not configured" | Caution | Yes, no App Group | Honest |
| `setup.notConfigured` | "…Finder previews and thumbnails can't read them and use their defaults." | Caution banner body | No, and wrong | CO-13 |
| `settings.extensionRefreshNotice` | "New extension requests use saved choices…" | File Types footer and storage card, 10 pt | Statement of behaviour | Honest; said twice |
| `setup.unverified`, `settings.providers.guidance` | "macOS chooses which app…" | Secondary | Platform behaviour | Exemplary |
| `setup.steps` | "Turn on the Quick Look extensions in System Settings → General → Login Items & Extensions…" | Row subtitle | Instruction | Honest, incomplete (CO-05) |
| `general.limits.fileSizeHint` | "Larger files show an explanation instead of their content." | Limits card | Checkable against adapters | Wrong for six text families (CO-12) |
| `settings.providers.checked`, `.found`, `.none`, caveats | Counts; "…in the folders that could be read"; caution caveats | Conflict card | Yes | Honest; should name what the scan cannot see (CO-25) |
| `appearance.sample.updates`, `appearance.sample.typeDisabled` | "Updates as you edit"; caution | Theme sample | Yes | Honest |
| `appearance.themeTransfer.*` | "Theme imported."; errors | 10 pt secondary caption for both | Yes | Honest; errors need the caution style (CO-17) |
| `about.howItWorks.body` | "File Types choices apply to new Finder previews… Likely secrets are hidden…" | About | Only for previews SpacePane provides | CO-27 |
| `about.privacy.body` | "…No file content leaves your device." | About | Yes by construction: no network entitlement (`Configuration/app.entitlements`) | Honest |
| `about.acknowledgements.body` | "…License notices are included with the app." | About | OCCT yes (`script/stage_companion.py:69`); color schemes no | Partly true (CO-23) |
| `preview.dropHint`, `preview.dropRejected` | Drop strip; accent while targeted, caution when rejected | Try Preview | Yes | Honest |

### Theme page

The page holds about twenty control groups, some forty-five controls with Syntax styles expanded: Reset Appearance (a link in the header), Color mode (four segments, falling back to a menu), Light and Dark scheme menus (five and seven choices), every installed font family in one menu, size, weight, Italic, Wrap, Line numbers, line spacing, character spacing, tab width, ligatures, Use syntax colors, a disclosure with 24 Bold and Italic checkboxes, the sample's 76-item type menu, a profile field with Save, Apply and Delete links per profile, and Import and Export links. Duplicates and hit targets are listed in CO-15; the stepper and point format in CO-16. Profiles: Apply and Import replace the current appearance silently (CO-06), Delete is immediate, success and failure share one 10 pt style at the bottom of the card, and a failed save is reported at the end of the controls column (CO-17). The sample frame's strips follow the system appearance while the pane follows the preview theme, which is right; the dots and the second format name are not (CO-28).

A scheme gallery of live mini-samples would cost twelve more native panes (five light and seven dark palettes; twelve Metal viewports when the chosen sample is a 3D model), each restyled and laid out on every stepper click, to show what the pinned sample already shows. Cached offscreen bitmaps cut the steady cost but need about twelve main-thread renders per typography change and careful invalidation, and Metal content does not appear in offscreen renders (`companion-redesign-2026-10-04.md:83`). The cheaper rendering is a tile drawn from palette tokens: background, foreground and a short line of text in four or five role colors, with no file, no native pane and therefore no possible source read. The colors are internal to the renderer today (`NativeTextAppearance.swift:8`), so tiles need a small public accessor (recommendation 11).

### File Types cell budget

Each cell is a native checkbox whose label holds the type name, an "Off by default" capsule for IGES and STEP, and up to two lines of patterns (`FileTypeCell.swift:16-29`), in an adaptive grid with a 190 pt minimum (`FileTypeGroupSection.swift:20`): three columns at the default size, two at the minimum. Grid rows take the height of their tallest cell, so adding a renderer pill, a conflict marker and a limit sentence inline would leave large gaps in German or Russian. A budget that keeps the grid: line 1, the name and a short pill (raise the minimum to about 210 pt); line 2, one line of patterns ending in "and n more"; line 3 only after a scan, a marker symbol with "Also declared by n apps". The limit sentence belongs in the help tag, the accessibility hint and the Try Preview inspector. Search already matches localized names, descriptions, suffixes with or without the dot, exact names, prefixes and group names (`FileTypeSettingsGroup.swift:18-53`).

### Corrections to the research reports

- Closest rivals recommendation 5 proposes per-type "Open With → Change All" steps (`docs/market/ux-research/2026-10-06-closest-rivals.md:256`). That rests on QuickestLook's support text (`:102`); nothing here shows that the default opener decides the Quick Look provider for modern extensions, and for SpacePane it would require declaring document types and becoming the default opener of user files. Do not ship it without a Mac test and an owner decision.
- Breadth recommendation 10 and code recommendation 8 propose localized pictures of System Settings. Fourteen languages on two OS versions is 28 images that go stale with each macOS release; numbered text with the exact extension names and one button does the job.

## Score against best-in-class

**3 of 5.** The structure, the models and the honesty engineering are better than any companion the research found: catalog-driven pages, atomic and recoverable saves, inert theme transfer, a bounded conflict scan, careful wording almost everywhere. What holds the score down is presentation and guidance: a promise of routing on File Types, green for an unverifiable and sometimes failed state, setup as a paragraph, a live sample that scrolls away, no undo, a bespoke search, and the scan buried at the bottom.

A 5 for a Quick Look companion is observable: the window opens on a numbered setup trail fully visible at the default size, whose button lands on Login Items & Extensions on macOS 15 and 26 and whose step 2 names the two extensions exactly as System Settings lists them; status sits in one neutral place and turns to caution, with an action, only on a problem the app has verified; conflicts are summarized beside step 2 and marked per type after a scan, with a sentence saying what the scan cannot see; File Types has native search on Command-F, Escape clears it, every bulk change can be undone from the Edit menu and an inline Undo, and no cell is longer than three lines in any of the 14 languages; Theme keeps its sample on screen at every width, shows schemes as swatches and gives each control one label; Try Preview explains a file's type, declaration, choice, renderer and concealed count; the last page returns after a relaunch; VoiceOver reads short labels in order; nothing is green, and nothing says or implies that Finder uses this provider.

## Recommendations

| # | Recommendation | Impact | Effort | Doable without a Mac |
|---|---|---|---|---|
| 1 | Honest, failure-aware status in one home, with the copy fixes | High | S | Yes |
| 2 | Undo for every overwriting change | High | S–M | Yes |
| 3 | Pin the Theme sample | High | M | Partial |
| 4 | Setup trail with the conflict summary beside step 2 | High | M | Partial |
| 5 | File Types search, labels and pattern summary | Medium | S | Partial |
| 6 | Page hierarchy and an 11 pt floor | Medium | S | Yes |
| 7 | Theme controls cleanup | Medium | S | Yes |
| 8 | Try Preview: one prompt, pane-wide drop, inspector | Medium | M | Partial |
| 9 | Restoration, window title and menus | Medium | S | Yes |
| 10 | Conflict markers per type and honest scan coverage | Medium | M | Partial |
| 11 | Scheme gallery from palette swatches | Medium | M | Partial |
| 12 | Renderer pill from a catalog field | Medium | M | Partial |
| 13 | Error states with actions | Low | S | Yes |
| 14 | About: readable notices and distinct links | Low | S | Partial |
| 15 | Sidebar material | Low | S–M | No |
| 16 | Per-format limits in help | Low | S–M | Partial |

**1. Honest, failure-aware status in one home.** Replace the storage tone with one presentation derived from storage mode, save state, recovery and loading; show it only in the sidebar footer, neutral or caution; remove General's `StatusPill` and green banner; show `SettingsStorageStatusView` only for private-only, unavailable, failed-save and recovered states; drop the enabled-type count from the footer. In the same change fix `fileTypes.subtitle` and the "Previews" header (CO-01), `setup.notConfigured`, `general.limits.fileSizeHint` and `about.howItWorks.body`. Why: CO-01 to CO-03, CO-12, CO-13, CO-27, C4. Files: `StorageModePresentation.swift`, `CompanionSidebar.swift`, `GeneralView.swift`, `SettingsStorageStatusView.swift`, `FileTypeSettingsView.swift`, `Components/CompanionStyle.swift`; strings through ux-copy's marker in 14 languages. Prerequisites: none. Tests: a `CompanionModelChecks` group enumerating every combination, asserting no positive tone, caution exactly for problems and a stable key per state; new keys covered by `tools/test_localization.py`. Risks: draft translations only. Doable without a Mac: yes, a pure mapping, strings and wiring that a later run only confirms visually.

```swift
struct SettingsStatus: Equatable {
    enum Tone { case neutral, caution }
    let tone: Tone
    let titleKey: PreviewStrings.Key        // saved here / saving / not saved / app only / unavailable
    let problemKey: PreviewStrings.Key?     // non-nil shows the General card and page notices
    init(storage: CompanionSettings.StorageMode, save: CompanionSettings.SaveState,
         recovered: Bool, isLoading: Bool)
}
```

**2. Undo for every overwriting change.** Register undo for the eight actions of CO-06 inside `CompanionSettings`, restoring only the slice an action replaced so that an unrelated edit made in between survives; pass `@Environment(\.undoManager)` from the views; add an inline confirmation row ("All file types turned off · Undo") that stays until the next change and is announced to VoiceOver, for people who never press Command-Z. Why: CO-06, gate 9, principle 9. Files: `Stores/CompanionSettings.swift` (outside 026's ux-companion list), `FileTypeSettingsView.swift`, `FileTypeGroupSection.swift`, `AppearanceSettingsView.swift`, `AppearanceProfilesView.swift`, `AppearanceThemeTransfer.swift`. Prerequisites: extend the workstream's ownership. Tests: a `CompanionModelChecks` group with an `UndoManager` that does not group by event: each action undoes and redoes exactly; the CAD opt-ins come back; an appearance edit between Disable All and Undo survives; the snapshot persisted after Undo matches; Undo after a failed save still repairs storage; a deleted profile returns with its ID and position. Risks: Undo must not cross a recovery reset. Doable without a Mac: yes, a model change with isolated tests; the Edit menu wiring is confirmed later.

```swift
extension CompanionSettings {
    enum Slice: Equatable, Sendable {
        case fileTypes(defaultEnabled: Bool, overrides: [FormatID: Bool])
        case appearance(PreviewAppearance)
        case profiles([PreviewAppearanceProfile])
    }
    /// Applies `mutation` through `change(_:)` and registers the inverse slice under `action`.
    func perform(_ action: PreviewStrings.Key, undoManager: UndoManager?,
                 _ mutation: (inout PreviewPreferencesSnapshot) -> Void)
}
```

**3. Pin the Theme sample.** A `PinnedSampleLayout` places the sample beside a separately scrolling controls column at 720 pt of content or more, and on top (180–320 pt high) with the controls scrolling below it otherwise; the page uses `CompanionPage(scrolls: false)`; Profiles move into the controls column; a one-sentence note under the sample says Finder previews use these settings the next time they open (C10). Keep one child identity as `AdaptiveColumns` does and put the controls before the sample in the accessibility order. Why: CO-04, gate 8, principle 10. Files: `AppearanceSettingsView.swift`, `AppearanceSampleView.swift`, new `Components/PinnedSampleLayout.swift`. Prerequisites: none; align the sample's loading state with ux-chrome's `NativeStateView`. Tests: make the frame computation a static function and check it in `CompanionModelChecks` at 547×415, 767×574 and 1,200×900 (sample inside bounds and at least 180 pt high, no overlap). Risks: at 820×560 the stacked controls get about 150–200 pt, so consider a 600 pt minimum height; the 3D samples resize a Metal view. Doable without a Mac: partial, the geometry is testable here but visibility and identity across live resizing must be observed.

```swift
struct PinnedSampleLayout: Layout {
    var breakpoint: CGFloat = 720, sampleFraction: CGFloat = 0.46
    var stackedSampleHeight: ClosedRange<CGFloat> = 180...320
    static func frames(in size: CGSize, breakpoint: CGFloat, sampleFraction: CGFloat,
                       stackedSampleHeight: ClosedRange<CGFloat>) -> (sample: CGRect, controls: CGRect)
}
```

**4. Setup trail with the conflict summary beside step 2.** Replace the banner and the setup row with one numbered card: (1) "Open System Settings → General → Login Items & Extensions → Quick Look" with the button; (2) "Turn on “SpacePane Preview” and “SpacePane Thumbnails”, then click Done", with the names read from the app's own embedded extensions so they match what System Settings lists in the user's language, and beside it "If a preview looks different, another app may be handling that type" with the scan button and its count; (3) "Select a file in Finder and press Space", with a link to the Theme sample until owner decision 3 settles a Finder reveal. Steps are never ticked off. Caution cards for app-only and unavailable storage sit above the trail; behaviour, limits and Developer Mode follow. For the button, call `SMAppService.openSystemSettingsLoginItems()` first and keep the URL as the fallback, and record both. Why: CO-05, CO-07, gate 7, principle 11. Files: `GeneralView.swift`, `QuickLookProviderDiagnosticsView.swift`, new `Support/EmbeddedExtensionNames.swift`. Prerequisites: recommendation 1; owner decision 3 for step 3. Tests: `CompanionModelChecks` reads the names from a synthetic bundle with two `.appex` folders and localized `InfoPlist.strings`. Risks: pane identifiers can change with any macOS release; the documented call is not proven to land on the Extensions half of the pane. Doable without a Mac: partial, authored and unit-tested here, but the pane that opens and gate 7's no-scroll visibility must be observed.

```swift
/// Localized names of this app's own embedded extensions, as System Settings lists them.
enum EmbeddedExtensionNames {
    static func read(in bundle: Bundle = .main) -> (preview: String?, thumbnails: String?)
}
```

**5. File Types search, labels and pattern summary.** An `NSSearchField` representable (magnifier, clear button, Escape clears, search role for VoiceOver) with Command-F scoped to the File Types view so Try Preview keeps its own find; announce the result count; drop the "Previews" header and the group state word; show the first few patterns plus a localized "and n more" and keep the full list for search only, which shortens the Source code cell's label from about 2,000 characters; hide counts and boxes until settings load. Why: CO-09, CO-10, CO-11, CO-22. Files: `FileTypeSettingsView.swift`, `FileTypeGroupSection.swift`, `FileTypeCell.swift`, `FormatFilenameSummary.swift`. Tests: `CompanionModelChecks` for the summary in English, German, Japanese and Bengali, a bound on every descriptor's label length (for example 160 characters) and unchanged search matches. Risks: key-equivalent precedence needs a Mac. Doable without a Mac: partial, the model and view are authored here; the field's keyboard behaviour is observed later.

```swift
extension FormatFilenameSummary {
    /// The first `limit` patterns and a localized count of the rest; spellings are never translated.
    func text(locale: Locale, limit: Int) -> String
}
```

**6. Page hierarchy and an 11 pt floor.** Add a `CompanionTypography` beside `CompanionMetrics`: page titles `.title2.weight(.semibold)` (17 pt; a fixed 20 pt has no macOS text style), section headings `.headline`, rows `.body`, notes `.subheadline` and never `.caption`; About stops repeating the app name. Why: C5, principle 12. Files: `Components/CompanionPage.swift`, `Components/SettingsCard.swift`, `Components/CompanionStyle.swift`, `AboutView.swift` and the caption call sites. Tests: typecheck only; layout in long languages on a Mac. Risks: notes gain a line in German and Bengali. Doable without a Mac: yes, a style change whose look is confirmed later.

**7. Theme controls cleanup.** One label per control: remove the three current-value subtitles; give Italic and Use syntax colors visible, clickable checkbox labels; merge "Font features" with "Font ligatures" and the Syntax styles title, disclosure and count. Put a numeric field beside the font size stepper; format points with zero to two fraction digits and locale digits, and give VoiceOver "13 points"; list fixed-pitch families first with the rest in a submenu; explain a disabled Save (trim the name, name the duplicate); mark the profile matching the current appearance; style transfer errors with the caution symbol and say when an import was not applied; remove the fake traffic lights and the second format name. Why: CO-15, CO-16, CO-28 to CO-30. Files: `AppearanceControlsView.swift`, `AppearanceFontControls.swift`, `AppearanceLayoutControls.swift`, `AppearanceSyntaxControls.swift`, `AppearanceSampleView.swift`, `AppearanceProfilesView.swift`, `AppearanceThemeTransfer.swift`. Tests: `CompanionModelChecks` for the point formatter (13, 0.25, −1; German and Bengali digits) and the save explanation; `AppearanceInteractionChecks` stays green. Doable without a Mac: yes, view and formatter changes with isolated tests.

**8. Try Preview: one prompt, pane-wide drop, inspector.** Host the pane inside a parent drop view so the whole area accepts a file, keep one Open File button and the file name in the header, and drop the permanent subtitle. After a drop or Open, show a "Check this file" card with the metadata-only facts tabled above, worded "Supported by SpacePane" and never "Finder uses SpacePane". Why: CO-21; closest rivals 7, code 5. Files: `DirectPreviewView.swift`, `DirectPreviewDropTarget.swift`, new `Models/PreviewFileFacts.swift`. Prerequisites: recommendation 12 for the renderer name (until then "Text" or "3D"); Contract 1's facts strip, so the card does not repeat size, lines and encoding. Tests: a `CompanionModelChecks` group over temporary files (`.env`, `.jsonl`, an extensionless file, an unknown suffix, a disabled JSON) with a spy reader passed to `PreviewPipeline(reader:)` that fails on any read, proving the card is metadata-only; `DirectPreviewDropChecks` unchanged. Risks: drop resolution through the pane and text selection need a Mac; contract 006 rules out SwiftUI item-provider drops. Doable without a Mac: partial, the model and its no-read test are written here, the drop surface is observed later.

```swift
/// Metadata about one opened file and how this app's catalog treats it. Never reads content.
struct PreviewFileFacts: Equatable, Sendable {
    enum Declaration: Equatable, Sendable { case exact, conforming(String), notDeclared, unknownType }
    let pathExtension: String
    let resolvedTypeIdentifier: String?
    let declaration: Declaration
    let inspection: PreviewInspection
    let presentation: PresentationCapability?
    let thumbnail: ThumbnailPolicy?
    @concurrent static func inspect(_ url: URL, pipeline: PreviewPipeline,
                                    preferences: PreviewPreferencesSnapshot,
                                    catalog: FormatCatalog) async -> PreviewFileFacts
}
```

**9. Restoration, window title and menus.** Store the last page as a companion-only default (`companion.lastRoute`) in `CompanionPreferences`, beside Developer Mode and never in the shared snapshot, and resolve it through the existing Developer Mode rule at launch; scene storage depends on window restoration, which the system setting that closes windows on quit turns off (inferred). Keep collapsed groups and the sample type in the shell for the session. Name the page in the window title for the Window menu, Mission Control and VoiceOver. Give Command-comma the standard "Settings…" title, subject to owner question 1; retitle Help "SpacePane Help" and give About a short help section (setup recap, conflicts, where limits apply, the shortcut list) or open the configured support page; use `info.circle` for About. Why: CO-18, CO-19, CO-28; the HIG settings idiom (`system-and-benchmarks.md:142`). Files: `CompanionApp.swift`, `CompanionShell.swift`, `CompanionRoute.swift`, `Stores/CompanionPreferences.swift`, `Components/CompanionSymbol.swift`, `AboutView.swift`. Tests: `CompanionModelChecks` for stable raw values (now persisted), round trip in an isolated defaults suite and resolution. Doable without a Mac: yes, a small model and standard APIs confirmed by a later relaunch.

**10. Conflict markers per type and honest scan coverage.** Index the report by format and pass it to File Types; mark a cell only after a scan, with a symbol and "Also declared by n apps" and the names in the hint; after a scan, state that unmarked types can still be previewed by macOS's built-in previews or by apps the scan could not read; show when the scan ran; read one bounded level of non-bundle subfolders with the same no-link rules; take the two system roots from `FileManager.urls(for: .applicationDirectory, in:)`. Prerequisite: observe in the signed, sandboxed app whether the roots can be listed and plists read (`settings-2026-10-05.md:45`); if not, leave the scan where it is. Why: CO-07, CO-25. Files: `QuickLookProviderScanner.swift`, `QuickLookProviderDiagnostics.swift`, `FileTypeCell.swift`, `FileTypeSettingsView.swift`, `QuickLookProviderDiagnosticsView.swift`. Tests: extend `SettingsModelChecks` with the index (an app declaring a type that conforms to one format marks only that format), subfolder bounds and link rules, and the 2,000-app limit across levels. Risks: scan time on large folders is unmeasured; App Review may question reading other apps' bundles. Doable without a Mac: partial, the index and markers are pure additions, but the sandbox result decides whether they ship.

```swift
extension QuickLookProviderReport {
    /// Other apps whose extensions declare a type related to `id`, in report order.
    func providers(overlapping id: FormatID) -> [QuickLookProviderApp]
}
```

**11. Scheme gallery from palette swatches.** At wide widths, replace the two scheme menus with two rows of tiles (five light, seven dark) drawn from palette tokens, each a button with the scheme's name, a selected ring and check, the selected trait and keyboard focus; keep the menus for narrow widths. No file is read. Why: the analysis's table stakes, breadth 3, C9. Files: `AppearanceSchemeControls.swift`. Prerequisite: a lead-owned public accessor in `PreviewRenderers`, ideally in the commit that adds `muted` and `hairline`. Tests: a `PreviewRenderersTests/Settings` test that each swatch equals the colors the text palette resolves for that scheme and polarity. Risks: tiles approximate; the pinned sample stays the reference. Doable without a Mac: partial, accessor and tiles are written and tested here, the look is confirmed on a Mac.

```swift
public struct PreviewSchemeSwatch: Equatable, Sendable {
    public let background: UInt32, foreground: UInt32
    public let roles: [PreviewSyntaxRole: UInt32]       // sRGB values the palette tests already check
    @MainActor public static func make(_ scheme: PreviewColorSchemeID,
                                       polarity: PreviewColorSchemeID.Polarity) -> Self
}
```

**12. Renderer pill from a catalog field.** Add `primaryView` to `FormatCatalog.json` and `FormatDescriptor` (source, outline, records, rendered, table, files, diagram, pages, summary, plot, icon, geometry), show it as a short pill using the existing mode strings, and add a renderer test that runs every appearance sample through the pipeline and asserts that `initialMode(for:)` matches the declared view, so the pill cannot drift. Why: CO-08. Files: `FileTypeCell.swift` in the companion; the catalog and contract are lead-owned; the drift test sits with ux-modes-structure. Prerequisites: owner decision 1, since the JSON, YAML, TOML and XML pills read "Source" today. Tests: as described, in `PreviewRenderersTests`. Risks: the field duplicates a runtime rule; the drift test contains it. Doable without a Mac: partial, the field and test are written here and run on a Mac.

**13. Error states with actions.** A Try Again button on the failed-save notice (`retrySave()` republishes the current snapshot); a Reset File Type Choices button on the recovery notice; specific labels for loading settings and reading a theme; banner bodies that add information rather than repeat the title; storage problems at the top of the Theme page. Why: CO-14, CO-17, CO-26. Files: `SettingsSaveNotice.swift`, `SettingsStorageStatusView.swift`, `GeneralView.swift`, `AppearanceSettingsView.swift`, `AppearanceProfilesView.swift`, `Stores/CompanionSettings.swift`. Tests: extend the failed-save retry check in `CompanionModelChecks` to call `retrySave()` after repairing the directory. Doable without a Mac: yes.

**14. About: readable notices and distinct links.** A "Show License Notices" button that reveals the bundled notices in Finder (no new window), the color-scheme notice bundled beside OCCT's, each link's path instead of the same host three times, the link color instead of the accent, and no repeated name. Why: CO-23, CO-24, C5. Files: `AboutView.swift`; bundling belongs to platform-release. Tests: `script/check_release_archive.py` asserts both notice folders. Doable without a Mac: partial, the view is written here and the bundle path checked in a built app.

**15. Sidebar material.** Choose between a behind-window `NSVisualEffectView` under the existing list, which works on macOS 15 and follows Reduce Transparency by itself, and a fixed, non-collapsible `NavigationSplitView`, the only route to the macOS 26 glass sidebar, which needs its collapse affordances suppressed and amends decision 010's mechanism; avoid `.background(.regularMaterial)`. Why: CO-20, principle 12. Files: `CompanionShell.swift`, `CompanionSidebar.swift`, `Components/CompanionStyle.swift`. Prerequisite: owner question 2. Doable without a Mac: no, both options must be observed on 15 and 26 with Reduce Transparency and Increase Contrast first.

**16. Per-format limits in help.** Derive each format's request budget at the composition boundary from the registrations the app already passes to the pipeline (`CompanionApp.swift:10`; `AdapterRegistration.defaultBudget` is public) and add the size and time limits to the cell's help and hint, plus "shows the first part of larger files" where the adapter allows it; entry and row limits need a typed contract from the lead. Why: data report 10, principle 5. Files: new `Models/FormatBudgets.swift`, `FileTypeCell.swift`, `CompanionApp.swift`. Tests: `CompanionModelChecks` asserting the map equals the standard, container-scan or geometry budget for representative formats. Doable without a Mac: partial, byte and time limits are derivable now; semantic limits wait for a contract.

## Verification plan

Static checks that run here now:

```
python3 -B script/sync_manifests.py --check
python3 -B script/generate_appearance_samples.py --check
python3 -B tools/test_localization.py
rg -n "\.positive|\.confirmed" Apps/PrevApp/Views                       # after rec. 1: no storage use left
rg -n "frame\((min|max|ideal)?[Ww]idth: [0-9]|minimum: [0-9]" Apps/PrevApp/Views   # fixed widths to recheck
rg -n 'Text\("|Button\("|\.help\("' Apps/PrevApp                       # must stay empty
```

Mac checklist, in order, recording results in a validation record in the repository's usual style:

1. `./script/build_and_run.sh --check`, `--check-compiler` and `--test`. Record the counts of companion model, settings model and appearance interaction groups, including the new ones (status mapping, undo, layout frames, pattern summary, file facts with zero reads, provider index, point formatter, last page).
2. `./script/build_and_run.sh --verify`, then `python3 script/check_bundle_localizations.py` on the built app. Record key counts per bundle.
3. Sandbox scan in the signed app: Scan Applications. Record which roots were listed or reported unreadable, apps checked and skipped, and wall time. This decides recommendation 10.
4. Open System Settings on macOS 15 and 26, once through `SMAppService.openSystemSettingsLoginItems()` and once through the URL. Record the pane shown, whether the Quick Look category is visible without scrolling, and the two extension names as listed, in English and German.
5. Status: in the signed build, record the footer and General while shared, while saving, and after a repaired failed save; take the failed and recovered states from the model checks and never alter the user's App Group container. In the staged prototype (`script/stage_companion.py`), record the app-only banner.
6. Theme: sweep 820×560, 993×720, 1040×720 and full screen; at each, expand Syntax styles and toggle the last role. Record whether the sample stays fully visible, that it does not reload, and the VoiceOver order; repeat in German, Russian and Bengali.
7. Undo: each of the eight actions, then Command-Z and Shift-Command-Z. Record the Edit menu titles in three languages, the inline row and its announcement, and the state after relaunch.
8. File Types: Command-F focuses search only on this page and Escape clears it; Try Preview's find still works. Record VoiceOver on the Source code cell and a group header, and the markers and caveat after a scan.
9. Try Preview: drop onto the pane (text selection must still work), a rejected drop, and the inspector for `.env`, `.jsonl`, `.txt`, an extensionless file, an unknown suffix and a disabled JSON. Record each field.
10. Window: quit on Theme and relaunch (page and frame); a stored Try Preview with Developer Mode off opens General; drag from the strip above the page header; closing quits.
11. Accessibility: VoiceOver through the sidebar and every page, Full Keyboard Access, Increase Contrast, Reduce Transparency (after recommendation 15), Reduce Motion, dark mode and a yellow system accent. Record what is read and any contrast failure.
12. Repeat steps 4, 6 and 10 on macOS 15, the deployment baseline.

## Open questions for the owner

1. Command-comma: keep the standard "Settings…" title and select General, keep File Types as decision 010 says, or label the item by its destination as Contract 2 says? Each changes the menu and one decision record.
2. Sidebar on macOS 26: accept classic sidebar vibrancy in the fixed custom sidebar, or adopt the system split-view sidebar for the 26 glass at the cost of suppressing its collapse behaviour, which amends decision 010's mechanism?
3. Should the conflict scan stay strictly on demand (decision 023), or run once when General first appears so step 2 and the File Types markers fill in without a click? It reads other apps' bundles.
4. Should the "Check this file" facts stay behind Developer Mode with Try Preview, or should a metadata-only file check exist outside it, given that "why is another app's preview shown" is the most common support question?

## Notes for other dimensions

- **accessibility-localization:** the Source code cell's label is about 2,000 characters (`FileTypeCell.swift:16-33`); accent-colored status words and link titles (`FileTypeGroupSection.swift:48`, `AboutView.swift:86`); 10 pt secondary captions on 4–8 % fills, such as the "Off by default" capsule (`FileTypeCell.swift:36-43`), unmeasured; `%.2f pt` beside `.number` values mixes digit systems in Bengali (`AppearanceLayoutControls.swift:37`, `AppearanceSampleView.swift:106-107`) and reads as "13.00 pt"; the group header exposes three elements for one state; scan completion and drop rejection are not announced (`QuickLookProviderDiagnosticsView.swift:44-50`, `DirectPreviewDropTarget.swift:41`); gate 10's "200 % content size" has no defined mechanism for this window.
- **architecture:** decision 026's ux-companion ownership omits `Models/*` (except `CompanionRoute.swift`), `Stores/*`, `Support/*`, the integration checks and `script/test_companion_models.py`, all needed by Contract 2; the renderer pill needs a catalog field and the gallery a public palette accessor; `DirectPreviewView.swift:11` builds its own `HostedConfiguration()` instead of using the shell's; the scanner's literal roots sit uneasily with AGENTS' "platform directory APIs" (`QuickLookProviderScanner.swift:76-85`).
- **chrome-states:** Try Preview and the Theme sample should use `NativeStateView` for empty and loading (`DirectPreviewView.swift:41-53`, `AppearanceSampleView.swift:47-56`); the Theme sample passes no `providerName` (`AppearanceSampleView.swift:44-46`) while Try Preview does (`DirectPreviewView.swift:38-40`), so the info badge differs between them.
- **structured-views:** the pill and the inspector need one stable "default view" per format; `SafePreviewModes.initialMode(for:)` (`SafePreviewModes.swift:129-148`) is the truth a catalog field must be tested against, and owner decision 1 changes both together.
- **documents-media-3d:** a pinned, resizing Theme sample resizes the Metal viewport of the STEP and IGES samples on every layout pass; check that path once recommendation 3 lands.
- **performance:** the font family menu is rebuilt from every installed family whenever the Typography card re-renders, which includes each edit in that card (`AppearanceFontControls.swift:14-23`; inferred, measure it); each sample selection decodes the whole 203 KB manifest (`AppearanceSampleLibrary.swift:72-81`); the scan's duration on a real `/Applications` is unmeasured; live scheme mini-samples were rejected on cost.
- **security-privacy:** the scanner reads other apps' Info.plists (bounded, read-only, never persisted), so App Review policy needs a recheck before submission; About's "likely secrets are hidden" holds only when SpacePane provides the preview (`finder-matrix-2026-10-04.md:59`); the inspector must stay metadata-only, which recommendation 8's spy-reader test enforces.
- **platform-release:** the color-scheme notice is not bundled while About says notices are included (`script/stage_companion.py:69`; `script/check_release_archive.py:101` checks OCCT only); System Settings pane identifiers are undocumented and `SMAppService.openSystemSettingsLoginItems()` is the documented alternative; the macOS 26 sidebar choice (owner question 2).
- **thumbnails:** nothing new; the General thumbnail switch already says that macOS may keep earlier thumbnails.
