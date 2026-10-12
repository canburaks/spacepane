# Companion sidebar redesign validation — 2026-10-04

Decision: [sidebar destinations and Developer Mode](../decisions/010-companion-sidebar-redesign.md). Date uses Europe/Istanbul.

## Implemented behavior

One SwiftUI `Window` (`CompanionSceneID.main`, hidden title bar text) shows a fixed sidebar and one page. The sidebar lists General, File Types, Theme and About, and — only in Developer Mode — Try Preview under a Developer heading. It also shows the replaceable app name and a status block with the settings storage state and the enabled-type count.

Developer Mode is a switch on General, off by default, stored in the companion's own defaults (`companion.developerMode`). With it off there is no Try Preview destination, no Open File command, no Command-O and no Command-5; a route to Try Preview resolves to General; turning it off closes the preview session.

General shows the storage banner with Open System Settings, the manual setup steps, a Preview folders switch bound to the Folders type, read-only text preview limits taken from `PreviewBudget.standard`, the settings storage state and the Developer Mode switch. File Types is one catalog-driven table with collapsible groups, a tri-state group checkbox, enabled counts and group status. Theme keeps every earlier appearance control in cards beside one framed live sample and the profiles card. About shows name, version, description, help text, privacy statement, the actual third-party acknowledgement and optional configured links.

Parser, preference schema, extension code and Finder provider selection were not changed.

## Environment

Apple silicon, macOS 27.2, Xcode 27.0 (27A266a), macOS SDK 27.0. Deployment remains macOS 15.

## Checks performed

| Check | Observed result |
|---|---|
| `./script/build_and_run.sh --check` | Project graph, 30 catalog formats, 356 localization keys in 14 locales and 13 localization tool tests passed |
| `./script/build_and_run.sh --test` | 453 package tests in 38 suites, 10 companion model checks, 3 file-drop checks, the SQLite snapshot checks, 5 appearance interaction groups and the adversarial corpus passed |
| `./script/build_and_run.sh --verify` | Signed app with both extensions built, signatures verified, companion process launched |
| `script/check_bundle_localizations.py` on that build | 33 explicit language cases, 3 signed bundles, 356 keys each |
| Companion source typecheck | All `Apps/PrevApp` sources typecheck for macOS 15, Swift 6, complete concurrency checking |

New model checks cover: enablement counts and `all`/`some`/`none` states for the catalog and each group, including the default snapshot with the two CAD types off; group status computed from all members while a search hides some; route availability and resolution with Developer Mode on and off; Developer Mode defaulting to off and persisting in an isolated defaults suite; and a closed session ignoring later file-type changes. New package tests cover the optional link validation in `HostedConfiguration`.

## Offscreen layout renders

Screen access to the running app was first declined, so layout was initially reviewed from offscreen renders of the companion's real views, produced by a temporary harness outside the repository that compiles `Apps/PrevApp` with temporary settings storage and an isolated defaults suite.

| Render | Observed |
|---|---|
| All five pages, 1040 × 720, light and dark | Sidebar, page headings, cards and status follow the prototypes' structure; text remains legible in both appearances |
| General and File Types, German, 1040 × 900 | Translated strings fit; long setup text wraps inside its card |
| File Types and Theme, Portuguese and Russian, 820 × 700 | Columns stack; bulk actions flow onto a second line without truncation; group rows and counts fit |
| General, forced right-to-left | Sidebar, columns, rows and controls mirror, including the custom two-column layout |
| Theme, 1040 × 1080 | Four control cards, framed sample with status line, profiles card; one native sample |

Render limits: the selected sidebar row draws as a solid bar and switches draw in their inactive tint, because the harness window is never key. The app icon is a generic placeholder. Translucency, window chrome, focus rings, hover, animation and scrolling are not represented.

## Signed window observations

After the rename to SpacePane the user granted screen access, and the signed development build (`SpacePane.app`, unchanged bundle identifier) was observed directly in dark appearance.

| Observation | Result |
|---|---|
| Window and sidebar | One window; the sidebar header shows SpacePane below the window controls without overlap; the selected destination uses the native sidebar highlight |
| App menu and About | The app menu is titled SpacePane; About SpacePane selects the About page in the same window; the page shows the name, version 0.1.0 (1) and a Website row for spacepane.com |
| View menu | General, File Types, Theme, About and Try Preview select their pages in the same window |
| Developer Mode off | Try Preview left the sidebar and the View menu and Open File left the File menu at once, without relaunch |
| Developer Mode on again | Try Preview and Open File returned at once |
| File Types | 30 of 30 enabled on this host; all five groups, counts, status labels and the off-by-default badges on the two CAD types are shown |
| Theme | Color mode shows four segments at this width; all control cards, the framed sample and the profiles card are shown |
| Try Preview | Drop area, empty state and both Open File buttons are shown |

The app has no icon asset, so the sidebar and About page show the system's generic application icon.

## Independent review

A separate read-only review compared the changed views with the previous commit. Fixed as a result:

- Turning Developer Mode off now closes the session instead of only cancelling it, so a later file-type change cannot reread the hidden file. A model check covers it.
- The scope of bulk and group actions is shown as text while a search is active.
- The File Types control bar uses one layout, so the search field keeps focus when actions wrap. The clear button has a localized label.
- Type cells expose their full label, including patterns and the off-by-default badge, to assistive technology.
- Theme switches to two columns only above 720 points of content width.
- Link validation rejects credentials in web links and mail links without a recipient.
- Two unused string keys were removed.

The review's concern that the custom column layout would not mirror in right-to-left was checked with a forced right-to-left render and did not reproduce.

## Live preview samples — added later the same day

The live sample now offers every catalog format. Checks after this change: `--check` (357 keys, 30 samples verified against the catalog), 453 package tests, 11 companion model checks, the file-drop, SQLite, appearance and adversarial checks, and the signed build of `SpacePane.app` with the sample manifest in its resources.

| Evidence | Observed |
|---|---|
| Model check | All 30 formats have a sample in catalog order. Each of the 28 text-presentation samples returns a ready presentation of its own format through the production pipeline with zero concealed values. A second quick selection wins over the first. Closing removes the temporary files. A missing manifest shows an explicit unavailable state. |
| Offscreen renders | JSON, Swift source, Markdown, CSV table, ZIP listing, SQLite, MIDI controls, folder, notebook and STEP were rendered on the Theme page. The STEP sample imported through the native helper (6 faces, 12 triangles, 10 × 20 × 30 mm); the Metal viewport itself does not appear in an offscreen render. |
| Signed sandboxed app | The Theme page loaded the default JSON sample from the app's temporary directory and exposes the menu as "Sample file type". |

Choosing another type in the real window was not exercised: the menu is a pop-up, and an overlay from another running app blocked the automated click. The selection path is covered by the model check and the offscreen renders, not by the signed app.

## Not verified

- Choosing each sample type in the real window, and the CAD samples under the sandbox.
- Live resizing of the real window across the column breakpoints, and light appearance in the real window.
- Opening the Website row in a browser.
- The Open System Settings deep link and its fallback.
- VoiceOver, Full Keyboard Access, large text and increased contrast at runtime; the disclosure control's expanded state as announced.
- Search, collapsed groups, the empty search result, drop-target feedback, a loaded preview, theme import/export panels, and failed-save or recovered-settings states on screen.
- Every language other than German, Portuguese and Russian in layout; all translations remain drafts pending native-speaker review.
- macOS 15 runtime, Intel, and any Finder preview or thumbnail behaviour. This redesign did not change extension code, and nothing here is evidence about Finder routing.
