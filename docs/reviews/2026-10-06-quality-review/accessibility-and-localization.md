# Accessibility and localization review — 2026-10-06

Reviewed from source only, on Linux, on 2026-10-06. Nothing was compiled, run, rendered, spoken by VoiceOver or measured; every runtime statement below is inferred from code and from the repository's validation records, and says so. The dimension covers VoiceOver labels, values, hints, order and announcements in every renderer and companion page; keyboard-only use and host key conflicts; contrast of every text tier; Increase Contrast, Reduce Motion, Reduce Transparency and enlargement; hit targets; right-to-left readiness; and localization: the 14-language catalogs, the tooling, translator context, placeholders, plural support, formatting, typography, branding metadata and effective language selection. Verdict: the accessibility and localization plumbing is unusually thorough for a Quick Look app (labels and values nearly everywhere, contrast-tested palettes, complete and synchronized 14-language catalogs), but none of it has been heard or driven on a Mac, one table speaks the wrong data after sorting, chrome text sits below AA in several places, and the tooling cannot express the plural counts that decision 026's copy needs.

## Scope and method

Documents read: the shared brief; `AGENTS.md`; `docs/market/2026-10-06-competitor-ux-ui-analysis.md`; `docs/decisions/026-world-class-ux-program.md`; the self-audit `docs/market/ux-research/2026-10-06-spacepane-self-audit.md` (sections 1–6); the platform baseline `2026-10-06-system-and-benchmarks.md` (A5–A9); `PLAN.md` (localization contract, UX program section); decisions 008, 025 (string handling) and 015 (Contents/References); validation records `language-quality-2026-10-04.md`, `ui-quality-2026-10-04.md`, `companion-redesign-2026-10-04.md`, `interaction-2026-10-05.md`, `interaction-continuation-2026-10-04.md`, `native-renderer-performance-2026-10-04.md`, `parallel-expansion-2026-10-04.md` (accessibility parts).

Source read in full: `PreviewRenderers/NativePreviewView.swift`, `Interaction/*` (info badge, accessory bar, Go to Line, outline filter, shortcuts, zoom, interaction extension), `NativeOutlinePreviewView.swift`, `NativeTablePreviewView.swift`, `Listings/NativeListingTreeView.swift`, `Listings/NativeListingFilesView.swift`, `NativeGeometryPreviewView.swift`, `NativeMIDIPreviewView.swift`, `Findings/*`, `LogicalLineNumberGutter.swift`, `NativeTextAppearance.swift`, `NativeColorSchemes.swift`, `NativeMarkdownStyling.swift`, `PresentationNotices.swift`, `PreviewStrings.swift`, `NativePreviewPane.swift`, `SafePreviewModes.swift`; accessibility parts of `Diagrams/NativeDiagramView.swift`, `Images/NativeImagePagesView.swift`, `Markup/MarkupContentsView.swift`, `Markup/MarkupReferencesView.swift`, `Markup/BibliographyFormatter.swift`, `Data/NativePlotPreviewView.swift`; every file in `Apps/PrevApp/Views` and `Views/Components`, plus `CompanionApp.swift`, `CompanionRoute.swift`, `FormatFilenameSummary.swift`; `Extensions/PrevPreviewExtension/PreviewViewController.swift`; tests `ColorSchemeContrastTests.swift`, `LocalizationTests.swift`, `NativeTablePreviewViewTests.swift` (spoken descriptions), `InteractionLogicTests.swift` (shortcuts); tooling `tools/*.py`, `tools/localization/*`, `script/check_bundle_localizations.py`, `script/build_metadata.py`; `Configuration/Metadata.xcstrings` and the Info.plists; `web/public/locales` and the language switcher.

Run here: `python3 tools/test_localization.py` (13 tests, OK); `python3 script/sync_manifests.py --check` and `python3 script/generate_appearance_samples.py --check` (both pass). Own read-only scripts under the scratch directory: `analyze_catalogs.py` (key counts, coverage, identical-to-English, placeholder parity over all keys, comments, lengths, expansion, apostrophes and typography, Swift-to-catalog references, `.lproj` and translation-input synchronization without `plutil`, website parity) and `contrast.py` (WCAG ratios for all 14 palettes, alpha-blended inks, approximate system colours, muted and hairline feasibility). A dry run of `add_localizations.py` → `merge_localizations.py` → `generate_localization.py` → `validate_localization.py` against a scratch mirror of the repository.

Out of scope: thumbnails' drawing (they draw no app-authored text today), the website beyond its language switcher and catalog parity, performance, and the five owner decisions.

## Current state

### Strengths to preserve

- **Contrast-tested palettes with a high-contrast override.** All twelve normal palettes (Standard in both appearances, ten single-appearance schemes) must give the foreground and all twelve roles at least 4.5:1, both high-contrast palettes at least 7:1, and High Contrast or the system Increase Contrast setting replaces every scheme (`Tests/.../Settings/ColorSchemeContrastTests.swift:42-61,153-169`). The preview restyles live when the accessibility display options change (`NativePreviewView.swift:213-216,455-457,497`).
- **Labels, values and help almost everywhere.** Text view label and help (`NativePreviewView.swift:106-107`); findings rows read severity first (`Findings/NativeFindingsBanner.swift:131-132`); table cells carry their column title and a spoken value for sparklines (`NativeTablePreviewView.swift:220-224,464-468`); outline rows expose Copy Value/Key/Path as accessibility custom actions (`NativeOutlinePreviewView.swift:155-161`); diagrams expose one element per node with a role description plus a connection summary (`Diagrams/NativeDiagramView.swift:241-283`); the 3D viewport is labelled with the model summary as its value (`NativeGeometryPreviewView.swift:113,270-274`); the gutter is a ruler with the line count (`LogicalLineNumberGutter.swift:24-26,37,46-47`); Contents rows read "Heading level n: title" (`Markup/MarkupContentsView.swift:117-119`); the References style control is labelled (`Markup/MarkupReferencesView.swift:92`); MIDI's slider has a time value (`NativeMIDIPreviewView.swift:84`).
- **Announcements exist for the main reading tools:** Copy All, Go to Line, outline filter counts, table sort, Copy Concealed Text (`Interaction/NativePreviewView+Interaction.swift:137,181-191,225,240-247`; `NativeTablePreviewView.swift:428-435`; `Findings/NativeFindingsBanner.swift:99-104`), with an injectable recorder for tests.
- **Companion semantics are native.** The sidebar is a real `List(.sidebar)` with selection, not a custom stack (`CompanionSidebar.swift:16-30`); page and section titles carry the header trait (`Components/CompanionPage.swift:26`, `Components/SettingsCard.swift:18`); switch rows are one element labelled by the title with the subtitle as hint (`Components/SettingsCard.swift:110-116`); steppers expose spoken values (`AppearanceFontControls.swift:33-35`, `PreviewBehaviorSections.swift:51-53`); the group disclosure is represented as a `DisclosureGroup` (`FileTypeGroupSection.swift:66-72`); decorative dots and icons are hidden; Increase Contrast thickens borders (`Components/SettingsCard.swift:59`, `FileTypeSettingsView.swift:90,135`).
- **Motion and transparency are already safe.** The only animation is gated by Reduce Motion (`FileTypeSettingsView.swift:157`); there is no material, vibrancy or `NSVisualEffectView` anywhere, so Reduce Transparency has nothing to change today.
- **Locale-aware formatting at most call sites:** byte counts, lists, numbers, dates and durations follow the presentation locale (`Findings/FindingText.swift:47,132-134`; `Listings/SafeListingFiles.swift:12-26`; `GeneralView.swift:58-65`; `PresentationNotices.swift:16-17`; `FormatFilenameSummary.swift:17-19`; `QuickLookProviderDiagnosticsView.swift:102-111`; zoom percent at `NativePreviewView+Interaction.swift:41-46`).
- **Right-to-left foundations.** No `leftAnchor`/`rightAnchor` anywhere; text uses natural writing direction and alignment (`NativePreviewView.swift:276`, `NativeTextAppearance.swift:74-75`); right-to-left paragraphs in markup are honoured (`NativeMarkdownStyling.swift:75-77`); the disclosure chevron rotates correctly in RTL (`FileTypeGroupSection.swift:60`); a forced right-to-left render of General mirrored the custom two-column layout (`docs/validation/companion-redesign-2026-10-04.md:40,74`).
- **Branding and metadata are localized properly:** bundle names are `%@` templates per language, compiled into `InfoPlist.strings` for all three bundles together with imported type descriptions (`script/build_metadata.py:21-47`).

### Catalog facts (computed here)

| Metric | Value |
|---|---|
| Keys | `Localizable.xcstrings` 924 (772 `PreviewStrings` keys + 152 catalog names and descriptions); `Metadata.xcstrings` 3 |
| Coverage | 14/14 languages, 12,936 values, all state `translated`, 0 empty, 0 leading/trailing or double spaces |
| Placeholders | 0 count/order/type mismatches across all keys (not only the 113 formatted keys); 39 values per language use positional arguments, and SOV languages do reorder (`preview.listing.filter.status` in ja, hi, bn) |
| References | 0 missing and 0 unreferenced keys; `.lproj` files equal the catalog in all 14 languages (924 entries, 0 diffs, checked without `plutil`); all 13 translation inputs equal the catalogs; website `formats.json` matches the catalog in all 1,064 entries |
| Translator comments | every key has one; 271 keys (29 %) share four generic comments; 2 count keys (`appearance.syntax.count`, `appearance.profile.count`) do not explain their placeholder |
| Identical to English (excluding format names) | tr 15, de 43, fr 45, zh-Hans 11, ja 13, hi 14, ku-Latn 21, ru 14, id 34, bn 13, ha 26, pt 29, es 28; mostly cognates and brands, but about 10 Hausa and 5 Kurmanji values are untranslated English ("Binary", "Node", "Build", "Trackers", "Metadata", "Boolean", "Schema: %1$@") |
| Length | 94 English values exceed 12 words; 9 of the 45 status/state strings shown in the preview header do; total characters vs English: fr 1.23, de 1.21, es 1.21, pt 1.18, ha 1.16, ru 1.15, ku 1.11, tr 1.10, id 1.10, hi 1.06, bn 1.01 |
| Plural variants | none; the generator and validator reject them by design (`tools/generate_localization.py:25-26`, `tools/validate_localization.py:97-102`) |

### Per-surface accessibility (from code; nothing heard)

| Surface | VoiceOver gets | Keyboard | Announced | Gaps |
|---|---|---|---|---|
| Text modes (Source, Rendered, Invisibles) | "Preview content" text with help; gutter ruler | ⌘F find bar, ⌘G, ⌘L (Esc closes), ⌘⇧C, ⌘+/−/0 | Copy All, Go to Line | mode control after the text in order; rendered headings are not headings; zoom silent |
| Outline, Records, Summary, Cues | "Outline" with key/value cells, duplicate-key help, three custom actions | arrows, ⌘C, ⌘↑/↓, ⌘F filter, Return/⇧Return, Esc twice | filter count | row copies silent; filter field follows the rows; node type not spoken |
| Table, Profile, Files, Rows | "Rows: n, columns: m"; cells labelled by column | header click or Sort menu, ⌘F, ⌘C | sort | filter count silent; Profile speaks the wrong row after sort or filter (AL1) |
| Tree | "Name" cells with kind as help, icon described | arrows, ⌘C | none | no filter or sort; copy silent |
| Contents, References | rows read "Heading level n: title" with help; labelled style control | Return, Enter, Space activate | none | Space taken from the host (AL15) |
| Diagram | group summary, node children with roles, connections | focus ring, arrows pan, +/−/0 | layout change only | children rebuilt on every query |
| Pages | labelled page images | Space, arrows, Page Up/Down, Home/End | none | Space and arrows taken from the host |
| 3D | image "Interactive 3D model" with summary value and 26-word help | arrows, ⇧arrows, +/−, F, R, 1/2/3; buttons with Full Keyboard Access (FKA) | none | failure text unreachable, presets silent (AL17) |
| MIDI | Play button with help; position slider | needs FKA | none | failure message silent; note in system ink |
| Header chrome | status line text; info badge as an image; findings group | Copy button and mode control need FKA | Copy Concealed | mode control unlabeled and out of order; states silent |
| Companion | native sidebar, headers, toggles with hints, stepper values | ⌘1–5, ⌘O (Developer Mode), ⌘,; controls need FKA | nothing | `.updatesFrequently` does not speak; hidden-label toggles; static window title |

What must be observed in Quick Look before any keyboard claim: whether the panel delivers ⌘L/⌘F/⌘G/⌘+/⌘0/⌘⇧C to the extension view; whether Space, Esc, ← and → still reach the host after clicking into text, an outline, Contents, Pages, the 3D viewport or a diagram; the Tab order with FKA off and on; whether the system find bar and a popover appear inside the remote view; and whether VoiceOver hears announcements posted from the extension process. The records hold one relevant observation: automated mode clicks in Finder's panel and in the companion sometimes returned `AXError.failure`, attributed to the inspection service (`native-renderer-performance-2026-10-04.md:180-182`, `parallel-expansion-2026-10-04.md:81-86`); it needs reproducing with VoiceOver.

## Findings

| ID | Severity | Confidence | Title | Evidence | Fix (Minor/Cosmetic) |
|---|---|---|---|---|---|
| AL14 | Blocker | verified in code | Bibliography renders English-only terms in every language, with no recorded exception | `Markup/BibliographyFormatter.swift:211-235,249,253,281,290,297,303,345` | see below |
| AL1 | Major | verified in code | Profile table speaks another row's description after a sort or filter | `NativeTablePreviewView.swift:214` vs `:224` | see below |
| AL2 | Major | verified (tooling); inferred (digits) | No plural support and two number styles, while the plan and decision 026 copy need both | `tools/generate_localization.py:25-26`; `PLAN.md:373`; `PreviewStrings.swift:813-816` | see below |
| AL3 | Major | verified in code; order needs a Mac | Mode control unlabeled, out of visual order for text modes and MIDI, unreachable without FKA | `NativePreviewView.swift:120-152,603-615,735` | see below |
| AL4 | Major | verified in code; speech needs a Mac | State changes and most copy/filter results are not announced; companion announces nothing | `NativePreviewView.swift:246-256,459-477`; `NativeTablePreviewView.swift:383-420`; `AppearanceProfilesView.swift:50` | see below |
| AL5 | Major | inferred; needs a Mac | Shortcuts match `charactersIgnoringModifiers`, which is non-Latin on Russian, Hindi, Bengali and kana layouts | `Interaction/PreviewShortcut.swift:10`; `NativeOutlinePreviewView.swift:419`; `NativeTablePreviewView.swift:486-487` | see below |
| AL6 | Major | verified (arithmetic); system colours inferred | Chrome text below 4.5:1 and untested | `OutlineFilterBar.swift:61`; `GoToLineBar.swift:109`; `NativeMIDIPreviewView.swift:29`; `FileTypeGroupSection.swift:48` | see below |
| AL7 | Major | verified (arithmetic) | Gate 4's muted and hairline thresholds cannot produce a visible, quiet tier in three schemes | `NativeColorSchemes.swift:114-141`; decision 026 gate 4 | see below |
| AL8 | Major | verified (inconsistency); inferred (macOS names) | Setup copy names macOS UI differently from what macOS shows in the user's language | `setup.steps` vs `settings.providers.guidance` in bn, ku-Latn, ha; "Quick Look" in de, fr, es, pt, ru | see below |
| AL9 | Major | verified in code | Privacy and limit text is fixed at 10 pt and ignores font size and zoom; no 200 % evidence exists | `NativePreviewView.swift:90,503,514`; `ui-quality-2026-10-04.md:105-111` | see below |
| AL10 | Minor | verified in code | Small or label-less targets in the companion | `Components/SettingsCard.swift:112-115`; `AppearanceFontControls.swift:47-51`; `AppearanceSyntaxControls.swift:13-17`; `FileTypeGroupSection.swift:61` | Use the row title as the toggle label; make disclosure, clear and close targets at least 20 × 20 (28 default) |
| AL11 | Minor | verified (dry run) | Tooling gaps: `plutil`-only comparison, placeholder checks gated on call sites, no unreferenced, identical, typography or comment lint, no markers in JSON | `tools/validate_localization.py:50-63,142-148`; decision 026 "below its own marker in the string files" | R9 |
| AL12 | Minor | verified | Typography and casing drift | en 5 straight vs 8 curly apostrophes; fr 124 breaking spaces before `;:?!`, 23 straight vs 125 curly; tr 8 vs 3; ha 66 vs 21; "Import theme…", "Save current appearance"; `appearance.pointValue` = "%.2f pt" | Sweep with a lint (R9); "13 pt" via a number style |
| AL13 | Minor | verified | Translator context and review evidence lag the catalog | 271 keys on 4 generic comments; review covered 259 of 924 keys (`language-quality-2026-10-04.md:14`) | R13 |
| AL15 | Minor | verified in code; needs a Mac | Focus-scoped Space and arrow bindings conflict with decision 026 principle 2 | `Markup/MarkupContentsView.swift:174`; `Images/NativeImagePagesView.swift:367-376`; `NativeGeometryPreviewView.swift:374-379` | R12 |
| AL16 | Minor | inferred; needs a Mac | Effective language can differ between companion and Finder; untested preference tags; mixed system UI for bn, ku-Latn, ha | `PreviewStrings.swift:824-831`; `check_bundle_localizations.py:19-24` | R14 |
| AL17 | Minor | verified in code | 3D failure text is a subview of an accessibility image; presets not announced; help is 26 words | `NativeGeometryPreviewView.swift:75,242,270-273` | Expose the failure as the viewport's value; announce presets |
| AL18 | Minor | verified in code | RTL gaps: gutter numbers align right in absolute terms; "→" in strings; timeline slider and page arrows would mirror | `LogicalLineNumberGutter.swift:103`; `FindingText.swift:139`; `setup.steps` | R15 |
| AL19 | Minor | verified in code | Info badge is a non-focusable image; tooltip-only for sighted keyboard users | `Interaction/PreviewInfoBadge.swift:6,15-16,31` | Covered by decision 026's button; give it a 20 pt hit area |
| AL20 | Cosmetic | verified | Static window title; ALL CAPS header row (Turkish İ risk, macOS 26 style); French "Arborescence" for both Outline and Tree; Rows mode reuses `preview.summary.rows` | `CompanionApp.swift:21`; `FileTypeSettingsView.swift:107`; `SafePreviewModes.swift:54` | Page title as window title; title case; distinct French term; own key |

**AL14. English-only bibliography terms.** The References mode builds citations with literals: ordinal suffixes, "et al.", "n.d.", "(Ed.)/(Eds.)", "In ", "pp.", "Master's thesis", "Doctoral dissertation", "Report No.", ", editors", "edited by" (`Markup/BibliographyFormatter.swift:211-235,249,253,281,285,290,297,303,308,345,369`). They appear in every interface language, and neither decision 015 nor the notice (`preview.markup.references.notice`) records an exception. This is the only app-authored English found outside the catalogs. Fix: R7 (a recorded exception is enough). Rule: localization.

**AL1. Profile table speaks another row's description after a sort or filter.** The cell text comes from the source row `order[row]` but the spoken value from the display row (`NativeTablePreviewView.swift:214,224`). Descriptions exist only in Profile, for the Common values, Distribution and Notes cells (`SafeDataProfilePresentation.swift:58-73`), and Profile has the sort and filter bar like every table. After a header click, VoiceOver reads one column's histogram while the sparkline shows another's. The tests check descriptions only in unsorted order (`NativeTablePreviewViewTests.swift:259-295`). Wrong data to a screen reader is worse than none. Fix: index with `order[row]`; add a sorted-and-filtered test.

**AL2. No plural support and two number styles.** The plan requires plural variants (`PLAN.md:373`), the language record defers them until the first variable-count sentence (`language-quality-2026-10-04.md:114-121`), and decision 026's own examples are such sentences ("1,204 lines", "Showing the first 5,000 of 12,431 entries", "3 likely secrets hidden"). The generator raises on any variation and the validator rejects `%#@name@`; the dry run showed that a plural key added before its Swift call site passes the merge unchecked because placeholder parity is applied only to keys with a discovered `PreviewStrings.format(.key, …)` call (`tools/validate_localization.py:50-68`). English already says "1 entries" (`preview.markup.references.accessibility`), "1 of 1 rows" and "Plot of 1 paths". Separately, counts formatted through `%lld` are ungrouped ASCII ("Lines 1–20000", "Line 15000 of 20000"), while counts formatted with `.formatted(.number.locale:)` are grouped and, for Bengali (CLDR default numbering `beng`), drawn in Bengali digits; one line can mix both (`cad.summary` passes `%lld` faces next to locale-formatted dimensions, `NativeGeometryPreviewView.swift:131-132`). Fix: R2 before any ux-copy string lands. Rule: localization (plural variants, locale formatting).

**AL3. Mode control: no label, inconsistent order, no keyboard path.** `modeControl` gets segment labels but no accessibility label (`NativePreviewView.swift:128-140,603-615`), unlike the References style control (`MarkupReferencesView.swift:92`). Subview order is status, badge, findings, gutter, text (`:120-127`), then mode control, outline, table, MIDI, accessory bar (`:147-152`), with derived views (Files, Tree, Diagram, Contents, Pages, Plot, Rows, Icon) added lazily after everything (`:735`) and the 3D view likewise (`:801`). So the self-audit is right for the text modes (JSON, YAML, XML and Markdown open in a text mode, so the control follows the content) and wrong for tables, outlines and every derived view, where the control precedes the content. The MIDI strip, drawn above the content, follows the Summary rows. With keyboard navigation off, the macOS default (neither System Settings > Keyboard > Keyboard navigation nor Full Keyboard Access enabled), a segmented control, the Copy button and MIDI's Play are not in the Tab loop, and there is no shortcut, so a keyboard-only user cannot change modes. Fix: R4. Rule: none.

**AL4. State changes and most results are not announced.** `showLoading`, the settings states, disabled and unavailable all go through `clearContent(status:)` or the status label with no announcement (`NativePreviewView.swift:246-256,330-339,459-477`), while the empty text view keeps the label "Preview content" and help about copying (`:277-278`). Table and listing filter counts update a label only (`NativeTablePreviewView.swift:383-420`); row copies in outlines, tables, trees and Contents are silent; zoom, 3D presets and MIDI failures are silent. The companion marks scan results, theme transfer messages and save state `.updatesFrequently` (`QuickLookProviderDiagnosticsView.swift:49`, `AppearanceProfilesView.swift:50`, `SettingsStorageStatusView.swift:27`), which does not make VoiceOver speak on macOS (inferred). Announcements are posted on the view element (`NativePreviewView+Interaction.swift:243`); whether VoiceOver hears an announcement posted from the Quick Look extension process is unverified. Fix: R5. Rule: none.

**AL5. Shortcuts depend on the keyboard layout.** `PreviewShortcut` matches `event.charactersIgnoringModifiers` (`Interaction/PreviewShortcut.swift:10`), as do the ⌘C overrides in outline, table, tree and Contents (`NativeOutlinePreviewView.swift:419`, `NativeTablePreviewView.swift:486-487`, `Listings/NativeListingTreeView.swift:307`, `Markup/MarkupContentsView.swift:190`) and the 3D letters (`NativeGeometryPreviewView.swift:385`). On Apple's Cyrillic, Devanagari, Bengali and kana layouts that value is the native character, while AppKit's own menu matching falls back to the layout's Latin command keymap (inferred from how menu key equivalents behave on those layouts), so ⌘L, ⌘F, ⌘G, ⌘⇧C and ⌘C in the preview, and F/R in the 3D viewport, likely do nothing for Russian, Hindi and Bengali users, three of the 14 languages. In the companion, menu-routed ⌘C still works; in Finder there is no app menu of ours. Tests use Latin characters only (`InteractionLogicTests.swift:129-154`). Fix: R3. Rule: localization (keyboard behaviour per language).

**AL6. Chrome text below AA, outside every test.** Computed with WCAG 2.x from the palette values: the filter count and Go to Line range use `foreground` at 75 % alpha (`OutlineFilterBar.swift:61`, `GoToLineBar.swift:109`), which gives 3.08:1 in Solarized Light, 3.79:1 in Solarized Dark and 4.37:1 in One Dark. System `secondaryLabelColor` (approximated as black at 50 % or white at 55 %) is used for the MIDI note, the table filter status and the Copy confirmation (`NativeMIDIPreviewView.swift:29`, `NativeTablePreviewView.swift:287`, `NativeFindingsBanner.swift:38`) and gives about 3.9:1 on every light scheme. In the companion, secondary 10–11 pt text gives about 3.9:1 on the light page, card and group fills (5.2–5.9:1 in dark), and accent-coloured text ("Enabled" status words, About link titles; `FileTypeGroupSection.swift:48`, `AboutView.swift:86`) gives 3.6:1 with the default blue and far less with a yellow or orange accent. The warning glyph's `systemOrange` (`NativeFindingsBanner.swift:165`) gives 2.0–2.2:1 on light schemes, under the 3:1 non-text minimum, although its shape also carries the severity. Decision 026's companion hints at "11 pt secondary" would still be about 3.9:1 in light appearance. Fix: R6. Rule: AGENTS accessible contrast variants.

**AL7. Gate 4 as written cannot produce a muted tier in three schemes.** Solarized Light's published foreground is only 4.99:1 on its background, Solarized Dark's 5.61:1 and One Dark's 6.57:1, and the test pins those foregrounds (`ColorSchemeContrastTests.swift:100-112`). The weakest muted that still meets 4.6:1 differs from the foreground by 1.08:1, 1.22:1 and 1.42:1 respectively, which reads as the same ink. A hairline needs more than 45 % foreground ink to reach 3:1 in seven of the twelve normal palettes (at 45 % they range from 1.85:1 in Solarized Light to 4.25:1 in GitHub Dark), so a 3:1 hairline is nearly as dark as muted text and not "quiet". The invisible-marker pinks already pass everywhere (lowest 5.96:1, Nord). Fix: R6's test design. Rule: none; this corrects decision 026.

**AL8. Setup copy and macOS's own UI names disagree.** For Bengali, Kurmanji and Hausa, `setup.steps` translates the path ("সিস্টেম সেটিংস → সাধারণ → লগইন আইটেম ও এক্সটেনশন") while `settings.providers.guidance` on the same page keeps "System Settings > General > Login Items & Extensions" in English; to my knowledge macOS ships no Bengali, Kurmanji or Hausa interface, so the English names are the ones these users will see (confirm on a Mac). Japanese and Chinese use Apple's names for Quick Look (クイックルック, 快速查看), but German, French, Spanish, Portuguese and Russian keep "Quick Look" in all 14 strings that name it, where Apple's interfaces use their own names (Übersicht, Coup d'œil, Vista Rápida, Visualização Rápida, Быстрый просмотр; from memory, confirm against Apple's localization glossaries). The two strings also use different separators ("→" and ">"). The setup trail of decision 026 will reuse these strings. Fix: R8. Rule: honesty of setup guidance; localization.

**AL9. Important chrome text is fixed at 10 pt.** The status line, which carries "Selection and copying use the concealed content", is `caption1` (10 pt) in full ink (`NativePreviewView.swift:90,503,514`); findings rows are 12 and 10 pt; filter, Go to Line, MIDI and 3D summaries are 10–13 pt. The Theme font size and ⌘+ scale the content, rows and gutter but none of this chrome, and 10 pt Devanagari and Bengali conjuncts are hard to read. There is no 200 % evidence at all: the only attempt rendered without SwiftUI controls (`ui-quality-2026-10-04.md:105-111`) and the companion record lists large text as not verified (`companion-redesign-2026-10-04.md:94`). macOS has no Dynamic Type for third-party text, so "200 %" has to be defined (R10). Rule: AGENTS accessibility in every bundle.

### Self-audit and decision 026 claims checked

| Claim | Verdict | Evidence |
|---|---|---|
| P8: mode control and filter bar come after the content | Partly right: true for text modes and the outline filter; false for tables, outlines and derived views, where the control precedes the content; MIDI strip mis-ordered (not mentioned) | `NativePreviewView.swift:120-152,735,801` |
| P8: control unlabeled | Right | `NativePreviewView.swift:128-140` |
| C8: four hidden-label Theme checkboxes | Half right: Italic and Use colors hide labels; Wrap lines, Line numbers and Ligatures show clickable labels; every General switch hides its label and is `.small` (missed) | `AppearanceFontControls.swift:47-51`; `AppearanceSyntaxControls.swift:13-17`; `AppearanceLayoutControls.swift:14-15,47-48`; `Components/SettingsCard.swift:112-115` |
| C8: size stepper without field | Right; its spoken value is "13.00 pt" | `AppearanceFontControls.swift:28-36` |
| §5 secondary text about 4:1 | Right in light appearance (3.9–3.95:1); dark is fine | AL6 |
| §5 colour reliance | Orange glyph: contrast problem, not colour-only (shape differs). Group state word: wrong, the word itself differs; the real issue is accent text contrast | `NativeFindingsBanner.swift:153-166`; `FileTypeGroupSection.swift:46-48` |
| §5 motion | Right; also no materials anywhere | `FileTypeSettingsView.swift:157` |
| §5 hit targets | Partly right: the badge is not a control; the 20 pt close button meets the HIG minimum; missed the 18 pt disclosure button and small switches | `GoToLineBar.swift:59-60`; `FileTypeGroupSection.swift:61` |
| §5 "200 % only checked offscreen" | Wrong: never successfully checked | AL9 |
| §5 announcements | Incomplete: outline filter yes, table filter no; row copies silent; companion none | AL4 |
| §5 RTL | Right; forced-RTL companion render exists | `companion-redesign-2026-10-04.md:40,74` |
| §3 word counts | Overstated by 1–20 words (`cad.interactionHelp` 26 not 45; `about.howItWorks.body` 40 not 60); ranking holds | catalog |
| P15 apostrophes | Incomplete: five English values are straight, not two | AL12 |
| Decision 026, string markers | Not possible: `.xcstrings` and translation inputs are JSON without markers, and `add_localizations.py` appends at the end, so parallel branches always conflict there | `tools/add_localizations.py:56-66` |
| Decision 026, principle 2 (never bind Space or arrows) | Already broken, focus-scoped, by Contents, Pages, 3D and diagrams | AL15 |

## Score against best-in-class

**3 / 5.** The code does more than any competitor evidences (labels, values, custom actions, contrast-tested palettes, 14 synchronized languages, locale formatting, RTL-safe layout), but nothing has been heard with VoiceOver or driven from a keyboard in Finder, one view speaks wrong data, several chrome inks fail AA, shortcuts likely fail on three shipped languages' layouts, and the copy pipeline cannot express plural counts.

A 5 in a Quick Look app looks like this, observably: in Finder's Space-bar panel and preview pane, VoiceOver reads facts strip, privacy row, "View mode, Outline, selected, 2 of 3", then the content, and speaks each state change, copy and filter result exactly once; every command has a shortcut listed in the info popover that works with US, AZERTY, Russian, Hindi, Bengali and kana layouts, and Space, Esc, ← and → always reach Quick Look; every text tier, including chrome and companion hints, measures at least 4.5:1 (7:1 in High Contrast) in all palettes with non-text cues at 3:1, enforced by tests; chrome grows with the preview's text size and a 26 pt preview and the companion at its minimum window in German, Russian and Bengali show no truncated control; counts are plural-correct and use one digit style per locale; setup text names macOS's own labels; and each shipped language has a reviewer's sign-off recorded.

## Recommendations

| # | What | Impact | Effort | Doable without a Mac |
|---|---|---|---|---|
| R1 | Fix the Profile spoken-description index | High | S | yes: one-line fix and a package test |
| R2 | Plural and number pipeline before ux-copy | High | M | yes: Python tooling and a Swift API with tests |
| R3 | Layout-independent shortcut matching | High | S | partial: synthesized-event tests here, real layouts on a Mac |
| R4 | Preview accessibility order, "View mode" label, keyboard mode switching | High | M | partial: order and label are unit-testable; VoiceOver and Tab need a Mac |
| R5 | One announcer and an announcement policy | High | M | partial: recorder tests here; speech from the extension needs a Mac |
| R6 | Palette inks for all chrome and a redesigned contrast test | High | M | partial: palettes and tests yes; companion system colours need a Mac |
| R7 | Bibliography terms: record the exception or localize (Blocker AL14) | Medium | S | yes: a decision record and catalog strings with golden-string tests |
| R8 | Setup copy aligned with macOS's own names per language | Medium | S | partial: needs Apple's glossaries and a Mac look |
| R9 | Localization tooling hardening | Medium | S–M | yes: Python only, runs here |
| R10 | Chrome follows preview text size; define and test 200 % | Medium | M | partial: layout tests authored here, rendering at 200 % needs a Mac |
| R11 | Companion hit targets and labels | Medium | S | yes: SwiftUI edits; a visual check follows on a Mac |
| R12 | Host key policy for Space and arrows | Medium | S | no: observe in Quick Look first |
| R13 | Translator context, review queue and leftovers | Medium | M | partial: drafts yes, review needs speakers |
| R14 | Language-selection evidence and documentation | Medium | S | partial: test cases authored here; bundle checks and per-app language need a Mac |
| R15 | RTL readiness fixes | Low | S | partial: code here; forced-RTL rendering needs a Mac |
| R16 | Companion VoiceOver refinements | Low | S | partial: code here; speech needs a Mac |

**R1.** Why: AL1. In `NativeTablePreviewView.configure(_:row:column:)` read the description for `order[row]`. Owner: ux-modes-structure; no dependency. Test: `PreviewRenderersTests/Tabular/NativeTablePreviewViewTests`, "a described cell keeps its own description after sort and filter" (sort descending, filter to one row, check `accessibilityValue()` and `stringValue` belong to the same source cell). No risk.

**R2.** Why: AL2. Extend `tools/generate_localization.py` to emit `<lang>.lproj/Localizable.stringsdict` from `variations.plural`; teach `placeholders()` the `%#@name@` form; require each language's CLDR categories (one/other for en, tr, de, hi, ku, bn, ha; one/few/many/other for ru; one/many/other for fr, es, pt; other only for zh-Hans, ja, id); give translation inputs an object form for plural keys; validate placeholders for every key at merge time, not only call-site-discovered ones. Add a counted API and a rule that user-visible counts never use bare `%lld`:

```swift
public static func count(_ key: Key, _ value: Int, locale: Locale = .current,
                         languagePreferences: [String]? = nil) -> String
// format "%1$#@n@": %1$lld selects the category; each rule prints %2$@,
// the value formatted with .number.locale(locale), so digits and grouping follow the locale.
```

Files: `tools/*.py`, `PreviewStrings.swift` (lead, shared contract). Prerequisite for ux-copy, the facts and limits strips and the privacy row. Tests: `tools/test_localization.py` (categories per language, variant placeholders, stringsdict round trip); `LocalizationTests` (ru 1/2/5/21, bn digits consistent within a line). Risk: SwiftPM must process the generated `.stringsdict`; confirm on a Mac.

**R3.** Why: AL5. Match commands the way AppKit menus do: keep an offscreen `NSMenu` holding the preview commands (the items already exist for the context menu, `NativePreviewView+Interaction.swift:255-267`) and call `performKeyEquivalent(with:)`, or derive the character from `event.characters` when Command is down with a `keyCode` fallback for digits. Apply to `PreviewShortcut`, the four ⌘C overrides and the 3D letters. Owners: ux-chrome, ux-modes-structure, ux-documents, ux-containers-3d; the lead fixes one helper first so all four use it. Tests: `InteractionLogicTests` with synthesized events whose `charactersIgnoringModifiers` is Cyrillic and `characters` Latin, and AZERTY digits. Risk: double handling if both paths fire; keep one path.

**R4.** Why: AL3, decision 026 gate 6. Label the control (new key `preview.mode.controlLabel` × 14, "View mode"); override `accessibilityChildren()` on `NativePreviewView` to return visible elements in visual order (facts or status, privacy row, info button, mode control, MIDI strip, accessory bar, content, limits strip), and set the `nextKeyView` chain the same way; post `.layoutChanged` after a mode or state change; add ⌘⌥1…n with an announcement of the new mode.

```swift
override func accessibilityChildren() -> [Any]? { PreviewChromeOrder.visibleElements(in: self) }
```

Files: `NativePreviewView.swift` (ux-chrome), `SafePreviewModes.swift` (ux-modes-structure). Depends on Contract 1's strip slots. Tests: new `PreviewRenderersTests/Interaction/AccessibilityOrderTests` for text, JSON, CSV, ZIP, MIDI and 3D presentations, including lazily added views; key-equivalent tests for ⌘⌥n. Risk: the override must track lazily added mode views and the geometry view and drop hidden ones.

**R5.** Why: AL4, decision 026's Copied chip and gate 10. Add a single owner and a policy: announce once per user action or state change; unavailable, disabled and settings states (title and body); loading only after the 300 ms spinner delay; keyboard mode switches; every copy ("Copied"); table and listing filter results (debounced); sort; Go to Line; zoom level; 3D presets. Never announce file content or source values, and never announce a live reload. In the companion use `AccessibilityNotification.Announcement` (macOS 14+) for scan completion, theme import or export, save failure and rejected drops.

```swift
@MainActor final class PreviewAnnouncer {
    var handler: ((String) -> Void)?          // tests record instead of speaking
    func announce(_ text: String, from view: NSView, priority: NSAccessibilityPriorityLevel = .high)
}
```

Files: `Interaction/NativePreviewView+Interaction.swift`, `NativeTablePreviewView.swift`, `NativeOutlinePreviewView.swift`, `Findings/NativeFindingsBanner.swift`, `NativeGeometryPreviewView.swift`; companion `QuickLookProviderDiagnosticsView.swift`, `AppearanceProfilesView.swift`, `SettingsStorageStatusView.swift`, `DirectPreviewView.swift`. Depends on `NativeStateView`. Tests: extend the recorder tests in `GoToLineAndCopyTests` and `OutlineFilterAndCopyTests`; new table filter and copy announcement tests. Risk: chattiness; decide on a Mac which element (window or application) makes the extension's announcements audible.

**R6.** Why: AL6, AL7, gate 4. Depends on owner question 3. Add `muted` and `hairline` with a test that VoiceOver-independent arithmetic can enforce: muted at least 4.5:1 (7:1 in both High Contrast palettes); muted at least 1.25:1 away from the foreground wherever the foreground has 7:1 headroom; for Solarized Light, Solarized Dark and One Dark either muted equals the foreground (hierarchy by size and the hairline) as a recorded exception or the owner allows darker foregrounds; hairline at least 1.3:1 in normal palettes and 3:1 in High Contrast, treated as decorative because the gutter is also separated by spacing. Replace the 75 % alpha and system secondary inks (`OutlineFilterBar.swift:61`, `GoToLineBar.swift:109`, `NativeTablePreviewView.swift:287`, `NativeMIDIPreviewView.swift:29`, `NativeFindingsBanner.swift:38`) with `muted`, and the warning glyph with a palette colour at 3:1. In the companion, define a hint ink resolved to at least 4.5:1 on page, card and group fills, stop using `accentColor` for status words, and use `linkColor` for links.

```swift
struct NativeSchemePalette { /* … */ let muted: UInt32; let hairline: UInt32 }
@Test func everySchemeMutedMeetsAA45AndStaysDistinct()
@Test func hairlineIsVisibleAndHighContrastHairlineMeets3()
```

Files: `NativeColorSchemes.swift`, `NativeTextAppearance.swift` (lead), `ColorSchemeContrastTests.swift`, the chrome files (ux-chrome), companion views (ux-companion), a new `Tests/Integration/CompanionContrastChecks.swift` that resolves system colours under aqua, darkAqua and the high-contrast appearances. Risk: muted values near 4.5:1 leave no margin for antialiasing; aim for 4.8:1.

**R7.** Why: AL14. Depends on owner question 4. Either record in decision 015 that citations render in the style guide's language (English) and add that clause to `preview.markup.references.notice` in 14 languages, or route the twelve terms through `PreviewStrings`. Files: `Markup/BibliographyFormatter.swift`, decision 015 (ux-documents, lead for the decision). Tests: `MarkupStylingTests` golden strings. Low risk.

**R8.** Why: AL8. Depends on owner question 1. Check each language's names for Quick Look, System Settings, General and Login Items & Extensions against Apple's localization glossaries; use them in `setup.steps`, `settings.providers.guidance`, `general.banner.sharedBody` and the setup trail; for languages macOS does not ship, keep the English system names (optionally with a translation in parentheses); use one separator. Record the policy in decision 008. Owner: ux-copy. Test: a `test_localization.py` check that the path strings of one language use the same system names. Risk: Apple renames between macOS 15 and 26; check both.

**R9.** Why: AL11, AL12, the dry run. Owner: lead or ux-copy, before the program's strings. In `tools/validate_localization.py`, replace `plutil` with a strict Python reader for the generator's JSON-quoted `.strings` (keep `plutil` when present), and add: unreferenced-key check; identical-to-English report with an allowlist of technical names; typography lint (English and French apostrophes, French no-break space before `;:?!`, a chosen Hausa glottal-stop character, German quotes); word and character budgets for chrome keys (12 words in English, 1.5 × English characters flagged per language); comment lint for generic comments and unexplained placeholders. Replace "below its own marker in the string files" with per-workstream additions files (for example `tools/localization/additions/<workstream>.json`) that only the lead applies with `add_localizations.py`, `merge_localizations.py` and `generate_localization.py`. Tests: `tools/test_localization.py`. Low risk.

**R10.** Why: AL9, gate 10. Depends on the `PreviewChrome` contract. Define "200 %" for this app as: preview content at 26 pt (Theme size or ⌘+) with chrome text following through `PreviewChrome` (strip text at least 11 pt and growing with the content size), plus macOS Zoom and the Displays "Larger Text" resolution for both hosts. Add AppKit layout tests at 13 and 26 pt, 400 pt wide, in all 14 languages that assert no truncated mode labels or status text (intrinsic size against frame), using a test-only language override:

```swift
extension PreviewStrings { @TaskLocal static var languageOverride: [String]? }
```

Files: `PreviewChrome` and `PreviewStrings.swift` (lead), `NativePreviewView.swift` (ux-chrome). Tests: new `PreviewRenderersTests/Interaction/LongLanguageLayoutTests`. Risk: AppKit measurement in tests needs an offscreen window; SwiftUI controls did not render offscreen before, so the companion part stays a Mac observation.

**R11.** Why: AL10. No dependency. Give `SettingsToggleRow`, Italic and Use colors their visible titles as toggle labels so the whole row toggles; enlarge the disclosure button to at least 20 × 20 (28 preferred), the search clear button and the Go to Line close button to at least 20 × 20, and the future info button's hit area to 20 × 20. Files: `Components/SettingsCard.swift`, `AppearanceFontControls.swift`, `AppearanceSyntaxControls.swift`, `FileTypeGroupSection.swift`, `FileTypeSettingsView.swift` (ux-companion), `GoToLineBar.swift` (ux-chrome). Tests: companion model checks cannot click; add accessibility-label assertions where views are testable. Low risk.

**R12.** Why: AL15, principle 2. Depends on owner question 6. First observe in Quick Look whether Space, ← and → still close or browse after clicking into Contents, Pages, the 3D viewport and a diagram; then either amend principle 2 to "focus-scoped bindings in focused content views; Space never" or remove Space from Contents and Pages. Files: `Markup/MarkupContentsView.swift`, `Images/NativeImagePagesView.swift`, `NativeGeometryPreviewView.swift`, `Diagrams/NativeDiagramView.swift`. Risk: removing arrows from the 3D viewport leaves keyboard users without orbit.

**R13.** Why: AL13. Depends on R9's comment lint. Replace the four generic comments on 271 keys with key-specific context (meaning, where shown, part of speech, length budget); explain the two count placeholders; rebase the review queue in `language-quality-2026-10-04.md` on 924 keys with the about 180 chrome, setup, state and failure strings first; translate the Hausa and Kurmanji English leftovers. Owner: ux-copy; review needs native speakers.

**R14.** Why: AL16. Depends on owner question 2. Rerun `script/check_bundle_localizations.py` on a fresh signed build (its evidence covers 259 keys); add preference cases `ku`, `ku-TR`, `kmr`, `ha-NG`, `bn-IN`, `zh-CN`, and expect English for `zh-Hant-TW` and `ckb`; observe a per-app language for the companion against the Finder preview's language and document the result (decision 008 says the hosting process chooses). Files: `script/check_bundle_localizations.py`, `Tests/Integration/LocalizedBundleChecks.swift`, `LocalizationTests.swift`.

**R15.** Why: AL18. No dependency. Align gutter numbers toward the text using the user interface layout direction; replace "→" in strings with a direction-neutral separator; keep the MIDI position slider left to right (AGENTS: do not mirror timelines); map page arrows to reading order; render File Types in forced right-to-left. Files: `LogicalLineNumberGutter.swift`, `NativeMIDIPreviewView.swift`, `FindingText.swift`, catalog.

**R16.** Why: AL17, AL20. No dependency. Set the window title to the page name (VoiceOver and the Window menu then name the page); make each File Types group an accessibility container named by the group; use title case instead of `.textCase(.uppercase)` in the header row; expose the 3D failure message as the viewport's value. Owners: ux-companion, ux-containers-3d.

## Verification plan

Static checks that run here now:

```sh
python3 tools/test_localization.py
python3 script/sync_manifests.py --check
python3 script/generate_appearance_samples.py --check
# The catalog metrics and the contrast table in this report came from two read-only scripts that were not kept
# in the repository; decision 027 items Q-23 and Q-34 fold their checks into tools/validate_localization.py and
# ColorSchemeContrastTests so that they run as part of the gate.
rg -n "charactersIgnoringModifiers" Packages/PreviewCore/Sources                      # AL5 call sites
rg -n "secondaryLabelColor|withAlphaComponent\(0\.75\)|systemOrange" Packages/PreviewCore/Sources/PreviewRenderers
rg -n "updatesFrequently|accentColor" Apps/PrevApp/Views
```

The two scripts were reviewing aids outside the repository; their checks belong in `tools/validate_localization.py` (R9) and `ColorSchemeContrastTests` (R6).

Mac checklist, in order, recorded in the style of `docs/validation`:

1. `./script/build_and_run.sh --check`, `--check-compiler`, `--test`; `python3 tools/validate_localization.py`. Record key and locale counts and the new tests (R1, R2, R4, R6).
2. `./script/build_and_run.sh --verify`, then `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/check_bundle_localizations.py --app <signed app>`. Record cases × bundles × keys (expect 924 or more).
3. VoiceOver in the companion (⌘F5): every page; record reading order, heading navigation, toggle and stepper speech, the disclosure state, and whether scan results and save failures are spoken.
4. VoiceOver in Finder's Space-bar panel and preview pane with synthetic fixtures (JSON, CSV, ZIP, Markdown, `.env` with synthetic secrets, MIDI, STEP, a disabled type, an oversized file): record order (status or facts, findings, mode control, content), segment activation (retry the `AXError.failure`), each announcement, and Profile Distribution speech after sorting.
5. Keyboard with FKA off and on: Tab order; ⌘L, ⌘F, ⌘G, ⌘⇧C, ⌘+, ⌘0 and ⌘C with US, Russian, Hindi (Devanagari), Bengali, French AZERTY and Japanese kana layouts; Space, Esc, ← and → after clicking into text, an outline, Contents, Pages, the 3D viewport and a diagram. Record which keys reach the preview and which reach Quick Look.
6. Contrast with Digital Color Meter (sRGB) in light, dark and Increase Contrast: MIDI note, table filter status, Copy confirmation, filter count in Solarized Light, Solarized Dark and One Dark, companion hints on cards, "Enabled" with blue and yellow accents, warning glyph on Paper. Record ratios.
7. Enlargement: preview at 26 pt and after ⌘+, macOS Zoom, Displays "Larger Text"; companion at 820 × 560 in German, Russian, Bengali and Hindi. Record truncated or clipped controls.
8. Reduce Motion (File Types group toggle) and Reduce Transparency and Increase Contrast together on macOS 26.
9. Language: set the companion to Turkish in System Settings' per-app list with English as the system language and compare the companion with a Finder preview; set Bengali first and record mixed-language menus and panels; read the Quick Look and Login Items & Extensions labels in System Settings in German, French, Spanish, Portuguese, Russian and Hindi.
10. Right-to-left: launch the companion with `-NSForceRightToLeftWritingDirection YES`; record File Types, the gutter, the MIDI slider and Pages.

## Open questions for the owner

1. For Bengali, Kurmanji and Hausa, should setup text name macOS's controls in English (what those users' Macs show), translated with English in parentheses, or translated only?
2. Should Finder previews follow the companion's per-app language (a snapshot field, so a schema change), or is "each host follows its own language setting" acceptable and documented?
3. For gate 4 in Solarized Light, Solarized Dark and One Dark: accept a muted tier equal to the foreground, or allow those schemes' published foregrounds to be darkened?
4. Citations: keep the style guides' English terms as a recorded exception, or localize them?
5. Hausa glottal stop: U+02BC, U+2019 or U+0027 throughout (a reviewer's choice the lint needs)?
6. Keep focus-scoped Space and arrow bindings in Contents, Pages, 3D and diagrams (amend principle 2), or remove them?

## Notes for other dimensions

- **chrome-states:** `NativeStateView` should be one accessibility element (title and body), hide the empty text view that is labelled "Preview content" (`NativePreviewView.swift:277-278`), and announce once. The two copy confirmations differ ("Copied to the clipboard" vs "Concealed text copied."). A popover inside the remote view is unverified.
- **structured-views:** AL1 is in your file. The table and listing filter count is not announced; Esc returns focus to rows in the outline filter but not in the table filter. Tables, outlines and trees use system alternating row colours, not the palette (`NativeTablePreviewView.swift:60`, `NativeOutlinePreviewView.swift:59`); role contrast against a dark system row (about #2A2A2A) drops to 3.5:1 for GitHub Dark headings (approximate; measure). French uses "Arborescence" for both Outline and Tree.
- **documents-media-3d:** AL14 (bibliography), AL15 (Space and arrows), AL17 (3D failure text and presets). `cad.summary` prints a literal "mm" in every language; `Measurement` formatting would localize the unit. The MIDI note uses system ink. Diagram `accessibilityChildren` builds new elements on every query (`NativeDiagramView.swift:252-283`), which can reset VoiceOver's position.
- **companion:** AL6 (hints, accent text), AL10 and R11 (targets), R16 (window title, group containers, title case), and announcements via `AccessibilityNotification`.
- **performance:** measure diagram accessibility queries with VoiceOver running on a diagram at the node limit.
- **security-privacy:** announcements, spoken values and tooltips use only concealed text today (table tooltips show up to 1,000 characters of the concealed cell, `NativeTablePreviewView.swift:218`); keep that rule in `PreviewAnnouncer` and the info popover.
- **architecture:** `PreviewStrings` needs a counted API (R2) and a test-only language override (R10). `PreviewThumbnails` has no access to localized resources; a type badge or counts drawn into thumbnails would need a resource path that does not pull AppKit.
- **platform-release:** bundle-lookup evidence covers 259 of 924 keys; `validate_localization.py` needs `plutil`; bn, ku-Latn and ha users get English system menus and panels beside translated app text; the website already says translations are drafts, so keep that wording and list no App Store localizations until reviewed.
- **thumbnails:** any drawn text must be localized, locale-formatted (Bengali digits) and at least 4.5:1 at thumbnail size.
