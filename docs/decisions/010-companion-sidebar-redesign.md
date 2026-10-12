# Companion redesign: sidebar destinations and Developer Mode

Date: 2026-10-04. Status: accepted by the user from supplied UI prototypes; implementation and validation tracked in [PLAN.md](../../PLAN.md). This record amends the presentation part of [the single-window decision](005-single-window-tabs.md). The single-window contract itself is unchanged.

Amended 2026-10-06 ([decision 027](027-best-in-class-quality-program.md), owner decision D23a; authored without a compiler, verification pending): Command-comma is the standard "Settings…" menu item and selects General; the Help item "SpacePane Help" selects About, whose short help section it shows; the window title names the current page; the window opens on the page it was left on, stored in the companion's defaults and never in the shared snapshot. The single window and fixed sidebar are unchanged.

## Navigation

The companion still owns exactly one window. Its six grouped tabs are replaced by a fixed sidebar with four destinations — General, File Types, Theme and About — plus Try Preview, which is offered only in Developer Mode.

| Earlier tab | Now |
|---|---|
| Setup | General |
| Supported Files | File Types (one catalog-driven table shows names, filename patterns and choices; each description is the row's help tag and accessibility hint) |
| Settings | File Types |
| Customization | Theme |
| Help | About |
| Try Preview | Try Preview, under a Developer heading, only while Developer Mode is on |

The sidebar is the only navigation, so it has a fixed width and cannot be collapsed. The window hides its title bar text; the sidebar shows the replaceable app name and each page shows its own heading. The window keeps its system title for Mission Control and accessibility.

Command-comma selects File Types. The About and Help menu commands select About. Command-1 to Command-4 select the four destinations and Command-5 selects Try Preview when it is offered. Every command targets the same singleton scene. No Settings scene, About panel, sheet-based preference screen or second window is introduced.

## Developer Mode

Developer Mode is a switch on the General page. It is off by default. While it is off, Try Preview does not appear in the sidebar or the View menu, Open File and its shortcut are unavailable, and a stored route that points to Try Preview resolves to General. Turning it off while Try Preview is open returns to General and closes the session: the request is cancelled and the file is forgotten, so a later file-type change cannot read it again while its destination is hidden.

The choice is a companion-only preference stored in the app's own defaults under a typed key. It is deliberately not part of the versioned App Group snapshot: extensions never read it, it does not change any preview or thumbnail, and it needs no schema migration. Checks use an isolated defaults suite and never read the user's defaults.

The direct preview keeps [the direct-file-drop contract](006-direct-file-drop.md) and the shared pipeline unchanged. It remains the way to inspect a file when Finder selects another provider; it is now an opt-in tool rather than a primary destination.

## What the prototypes showed that the app does not do

The prototypes are a visual target. Several of their controls have no truthful backing and are not implemented. Each is listed so a later pass can decide it deliberately.

| Prototype element | Handling | Reason |
|---|---|---|
| "Extension active", "registered with Finder" | Replaced by the settings storage state and the enabled-type count | A sandboxed app has no public API to learn whether its Quick Look extensions are enabled or chosen |
| Enable-extension switch | Replaced by an Open System Settings button | Only System Settings enables an extension; a real master switch would need a new shared preference and a schema migration |
| Restart Finder, Clear Cache, Reset Quick Look Cache, cache size | Omitted | Not possible in the sandbox, no durable cache exists by policy, and hiding a routing defect this way is prohibited |
| Open unsupported files, Refresh automatically | Omitted | No generic fallback for unrecognized types; Finder owns refresh |
| Default preview, Maximum file size, Archive item limit pickers | Read-only text preview limits taken from the fixed budget | Configurable budgets need a shared preference and pipeline changes in three hosts |
| Preview folders | Implemented as a switch bound to the Folders catalog type | Same policy as its File Types row |
| 47 formats including PDF, DOCX and PSD | The real catalog | Only shipped types appear |
| Updates section | Omitted | No updater exists; it would need a dependency and network access |
| Acknowledgements naming unused libraries | The actual third-party component | Truthful attribution |
| Website, support, documentation and privacy links; feedback form | Optional links read from branding configuration; hidden while unset. No form | No address is agreed, and the app has no network entitlement |
| System, Light and Dark color modes | High Contrast kept as a fourth choice | It is a shipped accessibility option |

The General status wording reports where settings are saved. It never states that Finder uses this provider.

## Structure

Shared presentation lives in `Apps/PrevApp/Views/Components`: a page frame, a section heading, a card with separated rows, labelled rows, a status pill and a two-column layout that stacks when narrow. The two-column layout is one `Layout`, so the native appearance sample and focused controls keep a single identity across resizing, as [the appearance decision](003-preview-appearance.md) requires.

Each destination is its own view. The shell owns routing, the preview session and the settings observation, as before. File-type rows, counts and group states derive from the format catalog and one enablement summary value; no format is special-cased in a view, so adding a format still needs no settings-screen change. Group and bulk controls still reach types hidden by a search ([decision 002](002-file-type-controls.md)); their scope is shown as text while a search is active and as help otherwise.

The General "Preview folders" switch and the File Types row write the same choice through the same store. Parser, preference schema, extension behaviour and Finder provider selection are unchanged by this redesign.

Optional About links are `PREV_*_URL` build settings in `Branding.xcconfig`, passed through the app's Info.plist and validated to `https` (or `mailto` for support and feedback). They are branding, not technical identity.

## Strings

All new text is in the String Catalog with typed keys and translator context, in the 14 selected languages. Counts use a "Label: number" form so no plural variants are needed. Translations are drafts pending native-speaker review, as recorded in [the language decision](008-languages-and-appearance-transfer.md).

## Validation

Verify: sidebar selection and every menu command in the one window; Developer Mode default, persistence, and the removal of Try Preview and Open File when off; group tri-state and bulk actions including hidden search results; appearance editing with one live sample across resizing; long-language layout at the minimum window size; light, dark and increased contrast; keyboard navigation and VoiceOver labels. Offscreen renders of the companion's own views are layout evidence only. They do not prove signed-app behaviour, VoiceOver, translated quality or any Finder behaviour.
