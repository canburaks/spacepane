# Platform baseline and world-class reference patterns — UX/UI observations

Researched 2026-10-06. Part A uses Apple documentation, Apple Support pages and Apple's HIG data feed. Part B uses vendor marketing (App Store, websites). Nothing was installed or tested, and no Quick Look window was opened on a live Mac.

**Evidence tags.** `[V]` = read on the cited Apple page or seen in a downloaded image. `[R]` = recalled platform behaviour or an inference that no source here confirmed; verify on a real Mac before building on it. "Observed in marketing material" applies to everything in Part B. Descriptions are in my own words.

**Scope warning.** Apple publishes no Quick Look window metrics, no Finder preview-pane widths and no visual spec for the Tahoe Quick Look window. Where a number is missing it says "not published". Apple's own pages now list "macOS 27 Golden Gate" next to Tahoe 26 and Sequoia 15 in the version picker (seen 2026-10-06 on the Mac User Guide pages). This document stays on macOS 15 and 26, the products' stated range.

---

# Part A — Apple's own Quick Look as the baseline

## A1. Source index (every page used)

| Id | Page | URL |
|---|---|---|
| S1 | Mac User Guide, "View and edit files with Quick Look" (macOS 26 edition, with figure) | https://support.apple.com/en-gb/guide/mac-help/mh14119/26/mac/26 |
| S2 | Same page, macOS 15 edition (figure only) | https://support.apple.com/guide/mac-help/mh14119/15.0/mac/15.0 |
| S3 | Mac User Guide, "Use the Preview pane in the Finder" (macOS 26 edition) | https://support.apple.com/guide/mac-help/mchl1e4644c2/26/mac/26 |
| S4 | "The Finder on your Mac" (Gallery View, Quick Actions, Quick Look paragraph) | https://support.apple.com/guide/imac/apdea61be6d6/2021/mac/12 |
| S5 | "Mac keyboard shortcuts" | https://support.apple.com/102650 |
| S6 | "Change Login Items & Extensions settings on Mac" (macOS 26 edition) | https://support.apple.com/guide/mac-help/mtusr003/26/mac/26 |
| S7 | Quick Look framework overview (data feed) | https://developer.apple.com/tutorials/data/documentation/quicklook.json |
| S8 | QLPreviewingController (data feed) | https://developer.apple.com/tutorials/data/documentation/quicklook/qlpreviewingcontroller.json |
| S9 | QLPreviewReply `title` and `attachments` | https://developer.apple.com/tutorials/data/documentation/quicklook/qlpreviewreply/title.json |
| S10 | `preparePreviewOfFile(at:completionHandler:)` | https://developer.apple.com/tutorials/data/documentation/quicklook/qlpreviewingcontroller/preparepreviewoffile(at:completionhandler:).json |
| S11 | QLPreviewPanel (in-app panel, responder-chain control) | https://developer.apple.com/tutorials/data/documentation/quicklookui/qlpreviewpanel.json |
| S12 | HIG "File management" (Quick Look previews section) | https://developer.apple.com/tutorials/data/design/human-interface-guidelines/file-management.json |
| S13 | HIG Settings | https://developer.apple.com/design/human-interface-guidelines/settings (data: …/tutorials/data/design/human-interface-guidelines/settings.json) |
| S14 | HIG Sidebars | https://developer.apple.com/design/human-interface-guidelines/sidebars |
| S15 | HIG Toolbars | https://developer.apple.com/design/human-interface-guidelines/toolbars |
| S16 | HIG Windows | https://developer.apple.com/design/human-interface-guidelines/windows |
| S17 | HIG Materials (Liquid Glass) | https://developer.apple.com/design/human-interface-guidelines/materials |
| S18 | HIG Segmented controls | https://developer.apple.com/design/human-interface-guidelines/segmented-controls |
| S19 | HIG Onboarding | https://developer.apple.com/design/human-interface-guidelines/onboarding |
| S20 | HIG Loading | https://developer.apple.com/design/human-interface-guidelines/loading |
| S21 | HIG Feedback | https://developer.apple.com/design/human-interface-guidelines/feedback |
| S22 | HIG Alerts | https://developer.apple.com/design/human-interface-guidelines/alerts |
| S23 | HIG Dark Mode | https://developer.apple.com/design/human-interface-guidelines/dark-mode |
| S24 | HIG Accessibility | https://developer.apple.com/design/human-interface-guidelines/accessibility |
| S25 | HIG Keyboards | https://developer.apple.com/design/human-interface-guidelines/keyboards |
| S26 | HIG Text views, Typography, Layout, Split views, Offering help | https://developer.apple.com/design/human-interface-guidelines/{text-views,typography,layout,split-views,offering-help} |
| S27 | "Adopting Liquid Glass" technology overview | https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass |
| S28 | MacMost, "17 things you may not know about Quick Look" (reputable third-party tips) | https://macmost.com/17-things-you-may-not-know-about-quick-look.html |
| S29 | Eclectic Light, "Explainer: QuickLook" and "Tackle QuickLook problems" (2026) | https://eclecticlight.co/2026/05/16/explainer-quicklook/ and https://eclecticlight.co/2026/05/20/tackle-quicklook-problems/ |

HIG has no Quick Look page of its own. The only Quick Look guidance there is the short "Quick Look previews" section inside File management `[V S12]`.

## A2. How the system Quick Look window is chromed

Figures inspected: S1 (macOS 26 Yellow Flower.jpg window) and S2 (macOS 15 Flowers.png window).

**Common anatomy `[V S1 S2]`** (left to right, one title bar, no other chrome):
- Left: close (x) and a second round window control that S1 calls the full-screen button, then the file name in bold. Apple does not title it with the app name or "Quick Look".
- Right: a cluster of small outline icon buttons (Live Text/info glyph, Markup, Rotate, Share), then one text button, "Open with Preview" (the default app's name).
- Below: the content, inset from the window edge by a thin border on all sides, so the content reads as a card inside the window.
- For several selected items: left/right arrows near the top-left, and an Index Sheet button (2x2 grid glyph) next to Share. Audio/video add Trim. Live Photo adds a "Live Photo" label in the bottom-left of the content.

**macOS 15 vs 26 differences visible in the two figures `[V]`:**
- 15: flat translucent grey title bar, small corner radius, buttons are bare glyphs, the "Open with" button is a subtle grey rounded rectangle.
- 26: noticeably rounder window and content corners, a taller title bar, the "Open with" button is a pill (capsule) with a soft fill, and the icon glyphs sit in the same row with more air. The overall look is a lighter, more rounded frame that matches Tahoe's Liquid Glass bars.

**What this means for a third-party extension.**
- The extension supplies only the view-controller content (or a data reply); the window frame, title, Share, Open With and window controls belong to Quick Look `[V S7 S8]`. The preview must not add its own title bar or a second "Open with" button.
- A data-based preview can set a custom display title; an empty string means "use the file name" `[V S9]`. A view-based preview inherits the file name.
- `preparePreviewOfFile(at:completionHandler:)` is called once, on the main thread, before the view is presented; Apple says to avoid heavy work there `[V S10]`. Show something fast and fill in later (see HIG Loading, A9).
- Apple tells view-based previews not to present extra view controllers over the preview and not to use large-area gesture recognizers, because they collide with standard preview behaviour; it also says to keep the file open only for the duration of an interaction `[V S8]`.
- Preview window size is not published. Users resize by dragging corners or go full screen `[V S1]`. Design for a continuous range, not one size (HIG Windows, A9).

## A3. What the built-in previews look like

Apple names the types Quick Look previews natively: iWork and Office documents, images, Live Photos, text files, PDFs, audio and video, and (iOS) USDZ `[V S7]`. It publishes no figure of the text, CSV, folder or USDZ preview, so look and feel below is limited to what a source states.

| Type | What is documented | Gap |
|---|---|---|
| Image | Zoom with Cmd + and Cmd -, rotate (Option reverses), Markup, Live Text, HDR shows only while Quick Look is frontmost, Copy Subject via Control-click `[V S1 S28]` | none |
| Audio/video | Trim with yellow handles, Play, Revert/Done, two-finger scrubbing, speed control `[V S1 S28]` | none |
| PDF / Pages / Word | Page thumbnails on the right, scrolling documents, Numbers sheet switching, text selectable and copyable with Cmd-C `[V S28]` | none |
| Plain text, source, CSV | Text files are a supported type `[V S7]`; selection and copy work in text-based previews `[V S28]` | Typeface, size, margins, any CSV table treatment: `[R]` not documented. CSV is shown as text in my recollection. Verify. |
| Folder | no Apple page | `[R]` large folder glyph with kind/size/dates; verify |
| USDZ | iOS and iPadOS only for AR; "list may change between OS releases" `[V S7]` | macOS look not documented |

**Lesson.** The system previews that people trust share one property: content fills the window, controls are few, and every control acts on the content (rotate, markup, trim, page jump). Informational chrome (kind, size, dates) is not drawn in the Quick Look window at all; it lives in the Finder Preview pane (A4).

## A4. Finder Preview pane and Gallery View

Figures: S3 (macOS 26 column/list view with Preview pane) and S4's Gallery figure (macOS 12-era artwork).

- Show with View > Show Preview, or Shift-Command-P to open/close; choose what appears with View > Show Preview Options, whose checkboxes depend on the file type `[V S3 S4]`.
- Resize by dragging the divider between the file list and the pane; dragging it fully to the right closes it. No minimum or maximum width is published `[V S3]`.
- Pane anatomy `[V S3 figure]`, top to bottom: large preview, then the file name in bold with a grey "kind - size" line (for example "JPEG image - 892 KB"), then an "Information" heading with a blue "Show More" link at the right edge, then label/value rows (grey labels at left, darker values right-aligned), then a hairline, then a bottom row of three icon-over-label Quick Action buttons (Rotate Left, Markup, More...).
- Gallery View `[V S4 figure]`: a big preview on the left, the same Preview pane on the right (icon thumbnail, name, kind - size, Information rows, Tags), and a scrubber bar of thumbnails along the bottom. Command-J then "Show filename" adds names. In Gallery View the More button at the bottom right of the window holds the Quick Actions `[V S4]`.
- Third-party Quick Look previews also render in the Gallery View and Preview pane (Suspicious Package and Apparency show this, B8 and B9). The pane is narrow, so each line of text must stay meaningful when truncated.

## A5. How the system says "cannot be previewed"

- No Apple page describes the wording or layout. `[R]` The usual fallback is a large generic file icon with name and basic details.
- For thumbnails, the system shows the generic type icon when no generator handles the type; Apple's own generators give up quickly on a mismatched extension, while preview code checks the data and ignores the extension `[V S29]`.
- Since macOS 15, third-party generators must be app extensions inside an app bundle; users find them under System Settings > General > Login Items & Extensions > Quick Look `[V S29 S6]`.
- Takeaway for us: the system's failure state is silence and a generic icon. A third-party preview that explains why (disabled type, limit reached, concealed content) is already better than the baseline. Wording must still never claim that Finder uses this provider (product rule).

## A6. Keyboard conventions

| Action | Keys | Source |
|---|---|---|
| Open / close | Space (selected item); Space or the close button closes | `[V S1 S5]` |
| Open via menu | Command-Y | `[V S5]` |
| Close | Space again or the close button; Esc exits full screen `[V S28]`; Esc also closes the window `[R]` (reported by Apple Discussions, not confirmed on an Apple page) | `[V S1]` |
| Browse selection | Left / Right arrows (also while the window stays open in Finder; Finder selection changes update the preview) | `[V S1 S28]` |
| Zoom | Command + / Command - | `[V S1]` |
| Index Sheet (grid) | Command-Return | `[V S1]` |
| Slideshow / full screen | Option-Command-Y (slideshow), Option-Space (full screen), Play button in full screen | `[V S5 S28]` |
| Exit full screen | Move pointer to the bottom and click the exit button; Esc | `[V S1 S28]` |
| Copy text | Command-C on selected text in text-based previews | `[V S28]` |
| Open settings | Command-, (HIG standard) | `[V S13 S25]` |

Implication: Space/Esc/arrows belong to the host. A preview that binds those keys breaks muscle memory; extra keys (Command-F, Command-C, Tab, VoiceOver commands) are fair game inside the view.

## A7. Full-screen Quick Look

Full screen is reached by the button at the top-left of the window or Option-Space; it hides the window frame, shows a slideshow Play button for multi-item selections and a bottom edge exit control `[V S1 S28]`. The extension's view is just resized, so layouts must reflow from a roughly 400 pt-wide Finder pane up to a full display; keep line length bounded in rendered prose when the window is huge (HIG Layout: keep content centred at very large sizes `[V S26]`).

## A8. Tahoe Liquid Glass changes an extension must harmonize with

From HIG Materials, Toolbars, Windows and "Adopting Liquid Glass" `[V S15 S16 S17 S27]`:
1. Liquid Glass is the functional layer for bars, sidebars, controls; content sits beneath. "Don't use Liquid Glass in the content layer"; use standard materials for content backgrounds. Use glass on custom controls sparingly.
2. Reduce custom backgrounds and tints in toolbars, split views and tab bars; they interfere with system effects such as the scroll edge effect. Prefer the content layer to inform bar colour.
3. Use two glass variants for legibility: regular (blurs, for text-heavy components) and clear (only over rich media, with an optional 35% dark dim).
4. Corners are concentric with their container; standard components get concentric radii automatically; custom ones must match. Windows and sheets are rounder; controls offer an extra-large size.
5. Lists, tables and forms have larger row heights and padding; section headers use title case, not ALL CAPS; section corners are rounder.
6. Toolbars group items that share a glass background; do not mix text and icons within one group; every icon gets an accessibility label.
7. Scroll views offer scroll edge effects that keep content legible under bars; custom bars must opt in.
8. Test Reduce Transparency, Increase Contrast and Reduce Motion; test dark with both on. Tahoe 26.1 added a user choice between Clear and Tinted glass `[R]` (search-result summaries of Eclectic Light: https://eclecticlight.co/2025/11/05/appearance-revisited-get-tahoe-26-1-looking-in-better-shape/ and MacStories https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2/, headlines only).
9. `[R]` Whether Tahoe's Quick Look frame lets content scroll beneath a glass title bar, and what safe-area inset a view controller gets, is not documented. Test with a long text file and `additionalSafeAreaInsets`/`contentLayoutGuide` before trusting any fixed top padding.

## A9. HIG rules relevant to SpacePane (verbatim ideas, own wording)

**Quick Look extensions `[V S12]`.** Offer a Quick Look viewer so people can preview what your app cannot open; consider a generator so Finder, Files and Spotlight show your custom types. That is the entire official brief. Everything else comes from adjacent pages:

| Topic | Rule | Source |
|---|---|---|
| Settings window (macOS) | Open from the App menu item plus Command-,; contains a toolbar with buttons switching "panes"; toolbar is non-customizable, always visible, always shows the active pane; window title reflects the visible pane (or "App Name Settings"); restore the last pane; dim minimize/maximize | S13 |
| Settings content | Best defaults for most people; minimize the number of settings; do not ask for what you can detect; do not duplicate system settings; put infrequent options in settings and task-specific options in the task | S13 |
| Dark mode | Avoid an app-specific appearance setting; look good in light, dark, Increase Contrast and Reduce Transparency | S23 |
| Sidebars | Two levels of hierarchy at most; short labels; familiar symbols; allow hiding; avoid putting critical info or actions at the bottom (windows move); sidebar icons use the system accent colour unless colour has a purpose; row height depends on the user's sidebar-size setting | S14 |
| Toolbars | Few items; icons over text where well-known; no settings button in a toolbar; one primary action at the trailing edge; every toolbar item is also a menu command; titles under about 15 characters; do not title with the app name | S15 |
| Windows | Support arbitrary sizes; avoid critical info in a bottom bar; use system-defined window appearances; window controls follow key/main/inactive state | S16 |
| Split views | Thin 1 pt divider; set sensible min/max pane sizes; multiple ways to reveal hidden panes | S26 |
| Segmented controls | One choice per control (or multi-choice on macOS); noun labels; text or images, not mixed; about 5-7 segments at most; equal-width segments | S18 |
| Loading | Show something as soon as possible; placeholders, not blank | S20 |
| Feedback | Match interruption to importance; prefer passive status near the item; confirm significant completions; alerts only for critical, actionable news | S21 S22 |
| Onboarding | Fast, fun, optional; teach by interacting; prefer contextual tips; postpone non-essential setup; show permission requests with a reason | S19 |
| Accessibility | Meet contrast (WCAG AA values), offer a higher-contrast variant, never convey information by colour alone, label for VoiceOver | S24 |
| Keyboards | Support Full Keyboard Access; respect standard shortcuts; do not repurpose them | S25 |
| Text | Make useful text selectable and copyable; keep text legible with multiple fonts/colours only if readability holds. macOS has no Dynamic Type | S26 |

**Tensions with SpacePane's own rules (to resolve consciously, not by accident).**
- HIG's macOS Settings idiom is toolbar panes in a separate window; SpacePane uses one window with a fixed sidebar by user decision (AGENTS.md). The sidebar idiom is itself HIG-legal for app windows `[V S14]`. Keep the parts of the settings idiom that still apply: Command-, selects a destination, the title reflects the current page, the last page is restored.
- HIG says no app-specific dark/light setting `[V S23]`. SpacePane's Theme page edits preview palettes, not UI appearance; keep an "Automatic (follow system)" default and show both appearances.
- HIG Alerts: do not use an alert merely to inform `[V S22]`. SpacePane's honest limit notices should therefore be inline, not modal.

## A10. macOS 26 settings-app idioms to match `[V S27, S6]`

- System Settings is a sidebar and detail pane, grouped form sections, rounder windows and glass bars (Apple describes the pattern in HIG Sidebars/Forms; no Apple page shows the Tahoe System Settings window itself).
- Quick Look extensions are enabled in System Settings > General > Login Items & Extensions > Quick Look; the page says these extensions "allow you to click on a file, then press spacebar to preview the file" and that, per category, you click the info button next to the option, switch the extension on or off, then click Done `[V S6]`. The same page says Finder extensions must be enabled for use in the Finder and Preview pane.
- Therefore the companion's enablement guidance should name this exact path and the info-button/Done step, and should not claim the result; macOS chooses the provider.

## A11. Part A summary: baseline numbers worth remembering

| Item | Value | Status |
|---|---|---|
| Quick Look window: toolbar items | 4 icons + 1 text button | `[V S1]` |
| Chrome inside the content area | none (title bar only) | `[V S1 S2]` |
| Preview pane content order | image, name + kind-size, Information (4-6 rows), Show More, Quick Actions | `[V S3]` |
| Segments in a segmented control | about 5-7 max | `[V S18]` |
| Toolbar title length | under about 15 characters | `[V S15]` |
| Quick Look window default size, pane widths | not published | gap |

---

# Part B — Transferable patterns from best-in-class Mac apps

Observed in marketing material; nothing installed. Screenshots were downloaded and viewed. "Transfer" notes say what to take to (a) the Quick Look preview, (b) the four-page companion. Product rules apply: native UI, no web views, local/read-only, 14 languages, honest wording.

## B1. Kaleidoscope 7 (file and folder comparison) — https://kaleidoscope.app
Screenshots viewed (4): https://framerusercontent.com/images/fjpgoCvMGiPwgiXCzURKu4BNaBc.jpg (3-way merge), https://framerusercontent.com/images/4VN7t6xeg0xbAjRG9YCy5VRJpv4.png (compare plus history sidebar and popover), https://framerusercontent.com/images/xjh306BiwP0pFq7HWiGq2qNj8A.png (conflict view with inline compare popover), https://framerusercontent.com/images/mYiGF7138QAMaETZkV6kJ3uNw.png (not studied).
- Two-line title: file name, then a grey summary line of counts ("9 Additions, 24 Deletions, 32 Changes, 29 Conflicts"). The title doubles as the summary.
- A centred status capsule in the title bar, "29 Unresolved Conflicts" with a yellow warning glyph: the single most important state is a pill, not a banner.
- A trio of mode buttons at the right (layout styles) plus an info toggle; breadcrumb path bars under the header; unchanged regions folded into a labelled row ("12 Unchanged Lines"); a thin colour-marked overview ruler along the right edge; bottom bar with "Conflict 1 of 29" and up/down steppers; hover popovers with commit details.
- Transfer (a): title-plus-counts line for the findings summary; a folded-row pattern for collapsed or concealed ranges ("3 lines concealed"); an overview ruler of finding positions for long files. (b) Not applicable.
- Not for us: dense three-pane layouts, heavy toolbars.

## B2. Base (SQLite editor) — App Store id 6744867438, v3.3.0, http://menial.co.uk/base/
Screenshots viewed (4): https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/53/fa/f9/53faf907-2657-30bc-c3ff-7ae823f4da0b/1-schema.png/800x500bb.jpg ; https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/5d/0a/b7/5d0ab759-1455-c33e-27d6-729081f3583d/2-data.png/800x500bb.jpg ; https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/2c/84/fc/2c84fce1-238a-1b1f-7525-0220c2df7c79/3-altering.png/800x500bb.jpg ; https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/23/41/53/234153a5-cc26-3ea3-e85b-78e4357d5987/4-sql.png/800x500bb.jpg
- The mode switcher is a four-segment control (Schema, Data, SQL, Log) in the title bar next to the file name, with the sidebar toggle at the left. Content below has no second control row; the mode switch costs zero content height.
- Constraint letters (P N U C D C F G) are small colour chips that light up per column, with a click popover that lists details. Special values are chips too: `NULL` is a grey pill in the data grid.
- Alternate-row striping, a header row with sortable column titles, right-aligned status line below the grid: "1-100 of 19127" with prev/next arrows and a filter-builder row ("status is completed" with +/-).
- Dark mode is a named selling point and the SQL editor shows line numbers in a dimmed gutter.
- Transfer (a): put the mode control in the title/toolbar zone when the host allows (it does not for Quick Look, so use one 26 pt row); render NULL/empty/concealed values as chips, not prose; use "1-100 of 19,127" notation for any truncated table. (b) none.

## B3. BBEdit 16 (code typography, Settings IA) — App Store id 404009241, https://www.barebones.com/products/bbedit/
Screenshots viewed (3): https://is1-ssl.mzstatic.com/image/thumb/PurpleSource126/v4/6b/5d/b6/6b5db6c3-5c63-2579-8fcc-54f4e0391585/6e0fada2-cd1f-418d-bac1-5165a286ca06_1_-_HTML_project_window.png/800x500bb.jpg ; https://is1-ssl.mzstatic.com/image/thumb/PurpleSource126/v4/0c/6a/d4/0c6ad4e5-ea87-3032-f77c-da5be90ff6e9/a7a7d241-8d67-4698-8ed6-5d35b428c0b9_6_-_Minimap.png/800x500bb.jpg (listed, not studied) ; https://is1-ssl.mzstatic.com/image/thumb/PurpleSource126/v4/7f/e7/bb/7fe7bb8d-da6b-3b7c-3893-0ad7ecfeeab5/9bde3d4c-67dd-4ccd-a012-d80f0c841115_2_-_Source_File_and_Color_Prefs.png/800x500bb.jpg
- A single dense bottom status bar: line:column, language, encoding, line breaks, save time, three counts, zoom. Each field is a small pop-up, so the bar both informs and edits. The dimmed gutter has line numbers, folding triangles and a thin separator from the code.
- Settings window: left sidebar of icon+label categories (Appearance, Editing, Keyboard, Text Colors...), a search field pinned at the bottom of the sidebar, a "Color scheme" pop-up with a New... button, a swatch list grouped under disclosure ("General": Plain text, Document background, Selected text...), and a "Restore Defaults" button at the bottom-left, plus a labelled checkbox at the bottom-right. The window title names the page ("BBEdit Text Colors Settings").
- Transfer (a): a quiet, uniformly small status/metadata footer that is also the control surface (encoding, line endings) — here as read-only status text. (b) Theme page: named scheme pop-up, per-token swatch rows grouped under headings, an always-visible Restore Defaults, a search box in the sidebar of long lists (our File Types page has 76 rows).

## B4. iA Writer 8 (reading typography) — App Store id 775737590, https://ia.net/writer/
Screenshots viewed (5): https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/d7/4b/b0/d74bb0c2-24a8-44fd-c0a3-7dbc4ed914c9/Mac_01.png/800x500bb.jpg ; …/PurpleSource211/v4/5c/e1/9a/5ce19a36-64cc-fe45-467a-5ad719afdfed/Mac_02.png/800x500bb.jpg ; …/PurpleSource211/v4/68/1e/56/681e5695-4435-654e-11bd-2de44aa3b1ab/Mac_04.png/800x500bb.jpg ; …/PurpleSource211/v4/e0/60/a1/e060a1db-5371-9b45-7bc7-629aa913089d/Mac_05.png/800x500bb.jpg ; …/PurpleSource211/v4/ec/02/d1/ec02d19c-ad41-b089-0f6a-db8e2bb303f7/Mac_03.png/800x500bb.jpg (prefix `https://is1-ssl.mzstatic.com/image/thumb/` throughout)
- Text is monospaced, large relative to the window, with very open line spacing (about 1.8x in the marketing image; approximate), in a single column of roughly 50-55 characters, centred in a wide window. Margins are generous; nothing but the cursor competes with the words.
- Chrome: the file name centred in a thin top bar with a small file glyph, three round glass buttons at the right (text-style menu, search, preview/play), a sidebar-reveal chevron at the left. Controls are quiet and consistent with Tahoe glass.
- Syntax highlight for prose (parts of speech) is an opt-in mode with its own colour set; dimming marks pasted text. The sidebar list shows a title, a date and a two-line text excerpt per document.
- Transfer (a): for Markdown and plain text, bound the measure and enlarge leading; do not stretch lines across a wide window; keep the highlight palette as a separate, optional layer. (b) Preview of readability settings should show a real paragraph at the chosen size.

## B5. Things 3 (information hierarchy and micro-interactions) — App Store id 904280696, https://culturedcode.com/things/
Screenshots viewed (4): https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d8/98/87/d89887d8-e25f-5be8-322a-2a8b33772922/Mac_-_1.png/800x500bb.jpg ; …/PurpleSource221/v4/6b/30/06/6b300695-2036-d47d-1e6e-7e57f53f4f62/Mac_-_3.png/800x500bb.jpg ; …/PurpleSource221/v4/04/ff/91/04ff91f9-5b90-ebe4-5612-2ed2c8a3a181/Mac_-_4.png/800x500bb.jpg ; …/PurpleSource221/v4/b1/d5/96/b1d5966e-5923-6854-b5fd-27556a27d11b/Mac_-_5.png/800x500bb.jpg
- Sidebar with coloured, glyph-led, one-word destinations and small counts at the trailing edge (a red "1" badge, grey "7"); section groups separated by space, not lines.
- A detail view with an extremely quiet toolbar: five icon-only buttons at the bottom edge in light grey; metadata as small rounded chips (tag "Important", a date "Sep 30"); section headings in accent blue with a "..." menu.
- Natural-language date entry: typing "Mon" produces three completions each labelled with a relative hint ("in 7 days") in a small dark popover.
- Transfer (a): metadata as chips with a clear hierarchy (title > body > grey chips). (b) A sidebar where counts or state live at the trailing edge (File Types: "62 of 76 on"), and where a one-line hint appears at the moment of input.
- Mistake to avoid: relying on accent colour alone to separate sections; HIG requires more than colour `[V S24]`.

## B6. Raycast (keyboard discoverability and settings IA) — https://www.raycast.com ; https://manual.raycast.com/settings
Screenshots viewed (2, marketing crops): https://www.raycast.com/_next/static/immutable/media/file-search.1h2o4dmp-4j8e.png ; https://www.raycast.com/_next/static/immutable/media/quicklinks-showcase.1-5j8fsgp_l5i.png. Settings window screenshots: not shown; IA below is from the manual text.
- File search: results list at the left, a large preview at the right with a "Metadata" heading and Name/Path/Type rows separated by hairlines; a back arrow chip left of the query.
- Settings tabs `[V manual]`: Account, General, Launcher, Shortcuts, Keyboard, Advanced, Organizations, About, AI, Applications, Extensions. Command-F searches inside Settings (settings, commands, extensions, keywords); Shift-Command-, jumps to the selected item's settings; a Shortcuts tab lists every assigned shortcut with conflict detection; hotkeys and aliases can be assigned from the Action Panel (Command-K) without opening Settings; the onboarding step proposes a default hotkey rather than leaving it blank.
- Transfer (a): metadata as hairline-separated key/value rows under the preview. (b) Search within the long list; a single place that lists every shortcut/state; context menu on a row to jump to its setting.

## B7. CleanShot X (permission-heavy utility; evidence thin) — https://cleanshot.com
Screenshots viewed (3 crops): https://cleanshot.com/img/home/more/history.png ; https://cleanshot.com/img/home/more/settings.png (a toggle crop only) ; https://cleanshot.com/img/home/more/macos.png (a Dock crop). Not inspected: onboarding and permission screens (none found in vendor material; a Setapp how-to describes Settings > Shortcuts with a "Use System Default Shortcuts" button and a Quick Access pane: https://setapp.com/how-to/no-clutter-screen-capturing-for-mac). Permission flow: not shown.
- History shows a segmented filter as pills (All, Screenshots, Videos, GIFs) with the selected pill in solid accent; the focused item gets an accent outline and a keycap-style action chip underneath ("Return Restore"), so the keyboard action is shown at the point of focus.
- Transfer (a): show the available action next to the focused element only when needed. (b) Offer a one-click "use recommended defaults" beside a long setup (Settings > Shortcuts). Do not extrapolate onboarding quality; there is no evidence.

## B8. Suspicious Package (package inspector; ships a Quick Look preview) — https://mothersruin.com/software/SuspiciousPackage/
Screenshots viewed (3): https://www.mothersruin.com/software/SuspiciousPackage/images_2x/feature-ql.png ; …/images_2x/feature-info.png ; …/images_2x/feature-files.png
- The Quick Look preview (Gallery View and Preview pane both shown) is a verdict card: a large file name, a small-caps subtitle ("DEVELOPER ID SOFTWARE - DISTRIBUTION ARCHIVE"), a hairline, then five single-line facts, each led by a round grey glyph: "Installs 4,734 items - 142.5 MB on disk", a dark "DEVELOPER ID" chip plus "Signed by ...", "Notarized by Apple - Stapled Ticket", "Runs 4 install scripts", "Downloaded by Safari - June 11, 2021". Rows with detail carry a circled arrow at the trailing edge; one low-key "Open with Suspicious Package" button at the bottom.
- In the narrow Preview pane the same rows truncate with an ellipsis but stay one line each, so the card degrades without a different layout.
- Good states use a green chip ("APPLE INC."), neutral facts a grey glyph, warnings differ by shape as well as colour.
- Transfer (a): for archives, bundles, databases and secret-bearing configs, lead with a three-to-five-row verdict list before any raw content, and make each row independently truncatable. This is the strongest single reference for SpacePane's Summary mode.

## B9. Apparency (app/bundle inspector; ships a Quick Look preview) — https://mothersruin.com/software/Apparency/
Screenshots viewed (3): https://www.mothersruin.com/software/Apparency/images_2x/feature-ql.png ; …/images_2x/feature-contents.png ; …/images_2x/feature-security.png
- The Quick Look/Gallery preview shows the app icon at the left and a muted-label key/value block at the right: name (bold), kind, version, bundle ID, architectures, minimum OS, copyright, size, modified.
- A two-state scope control sits inside the preview body ("For app and 20 sub-components" with two icon segments); below it a labelled list with status glyphs: green check "Enabled", grey minus "Not enabled", "Not applicable", each with muted label at the left and value right.
- Transfer (a): an in-content scope toggle is acceptable when it changes what is counted; glyph plus word for every status; muted left labels, primary right values, matching the Finder pane's own Information table `[V S3]`.

## B10. Not used (and why)
Nova (Panic) was checked for Settings material but its site shows only a project picker (https://nova.app/images/features/ui.png); Craft's App Store screenshots are iPhone only (https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/16/03/cc/1603cc2b-e02c-bbae-fa40-0446549a2c45/0_APP_IPHONE_69_0.png/320x480bb.jpg); Xcode Quick Help was not inspected; TablePlus and Sip returned no App Store listing. No claim is made about them.

---

# Twelve principles for a world-class Quick Look preview and companion

1. **Spend chrome like money.** Quick Look's own window has a title bar and five buttons and nothing inside the content (A2); budget one header row of about 26-28 pt for SpacePane previews and move everything else into inline, collapsible detail.
2. **Let the host own the title and the window.** The system draws the file name, Share and Open With and lets a data preview set the title (S9, A2); never repeat the file name or add a second "Open with" in the content.
3. **Lead with a verdict list, then the raw content.** Suspicious Package's card (B8) and Apple's Information table (A4) both put 3-6 muted-label facts before detail; give archives, databases and secret-bearing files that first screen.
4. **One stable, text-only mode control, five segments at most.** HIG segmented controls (S18) and Base's title-bar Schema/Data/SQL/Log (B2) agree: noun labels, equal widths, never mix icons and text; hide it when there is one mode.
5. **Say limits in counted, quiet notation, never by colour alone.** Base's "1-100 of 19127" (B2), Kaleidoscope's "12 Unchanged Lines" (B1) and Apparency's glyph-plus-word statuses (B9) are scannable; HIG demands more than colour (S24), and alerts are for actionable news only (S22).
6. **Match type to content, and bound the measure.** iA Writer's large, open mono text in a 50-55 character column (B4) versus BBEdit's dense dimmed gutter and uniform footer (B3): prose gets leading and a narrow measure, code gets a quiet gutter; the macOS system font has no Dynamic Type (S26), so offer size controls.
7. **Show something immediately.** HIG Loading says show content or placeholders as soon as possible (S20) and Apple's `preparePreviewOfFile` is called once on the main thread and should stay light (S10); render the cheapest useful view first and refine.
8. **Inherit the host's keys; add only conventional extras.** Space, Esc, arrows, Command-Y and Option-Space belong to Quick Look (A6) and Apple warns against large-area gestures (S8); add Command-F, Command-C and Tab only, and publish the list inside the companion as Raycast does with its Shortcuts tab (B6).
9. **Few settings, good defaults, searchable and resettable.** HIG: minimize settings, no duplicate system options (S13); BBEdit pins search and Restore Defaults to its Settings window (B3) and Raycast's Command-F searches all of it (B6); our 76-row File Types page needs both.
10. **Put the live preview next to the control it explains.** HIG prefers task-specific options in context (S13); Apple's own Show Preview Options lives in the preview pane (S3) and BBEdit shows a scheme beside its swatch list (B3); the Theme page should render a real sample for the current choice and both appearances.
11. **Tell people exactly where to enable the extension, and stop there.** Apple's path is General > Login Items & Extensions > Quick Look, then the info button, switch, Done (S6); HIG says make onboarding short and optional (S19); the status line may report where settings are saved but never that Finder uses this provider (AGENTS.md).
12. **Harmonize with Liquid Glass by doing less.** Tahoe wants glass confined to bars, standard materials in content, concentric radii, and tested Reduce Transparency/Increase Contrast (S17, S27); use system controls, no custom bar backgrounds, and treat any fixed top inset as unverified until tested on 26.

## Anti-patterns to avoid

- A header taller than the content's first screen, such as stacked banners above a three-line file (A2 budget; Apple's window has none).
- Informational text at 10 pt in full-contrast ink with no muted tier; Apple and Mother's Ruin both use grey labels against darker values (S3, B9).
- A modal alert or sheet for a size limit or concealed-secret notice (S22).
- A tooltip-only explanation for something the person needs to know (accessible, keyboard and VoiceOver users cannot hover).
- Colour-only status (red/green dots, accent-only sections) (S24).
- Custom glass, custom bar backgrounds or tinted toolbars (S15, S17, S27).
- Rebinding Space, Esc or arrow keys, or large-area gesture recognizers (S8).
- A settings toggle that implies macOS will pick us, or text saying "Finder uses SpacePane".
- App-specific light/dark toggles (S23); a bottom-edge control bar for key actions (S14, S16).
- Dense three-pane layouts and always-visible toolbars borrowed from IDEs and diff tools (B1, B3) inside a Finder-sized preview.

## Gaps that need a live Mac (not resolved by this research)

1. Built-in Quick Look appearance for text, CSV, folder and USDZ on 15 and 26 (A3): screenshot on both OS versions.
2. Default Quick Look window size, Finder Preview pane minimum/maximum widths and what safe area a view controller receives under the Tahoe title bar (A2, A8).
3. Exact system wording and layout of the "cannot be previewed" state (A5).
4. How our extension's view behaves in the Finder Preview pane versus the floating window at narrow widths (B8, B9 show other extensions do this).
5. CleanShot X and Raycast onboarding/permission screens: no vendor material found; test the apps if those flows are to be benchmarked.
