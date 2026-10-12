# Task 3 — Apple Human Interface Guidelines

Research date: 2026-10-03. Baseline: macOS 15; later App Store distribution.

- [x] Research current primary Apple design guidance.
- [x] Map guidance to the companion app and Quick Look extension.
- [x] Identify accessibility acceptance criteria and platform verification gates.

## Recommendation

Use a small native companion app for setup, sample previews, help, and customization. Give it a separate Settings window. Keep Finder previews focused on the selected file, with selectable content and a small number of relevant controls. System controls should retain their platform behavior and appearance; customized themes and typography belong mainly to document content. This follows Apple's emphasis on desktop flexibility, familiar inputs, and personalization. [Apple HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

The following maps verified Apple guidance to proposed product decisions. Product choices and acceptance targets are recommendations, not Apple requirements or a guarantee of App Store approval.

## Surface ownership

| Surface | Our responsibility | Boundary |
|---|---|---|
| Companion main window | Setup, read-only sample/test-file rendering, supported-format information, help | Native menus, window controls, resizing, and focus handling |
| Companion Settings | Persistent preview appearance and format preferences | Separate app-owned window, available through the App menu and Command–Comma |
| Finder Quick Look preview | Content delivered by the extension and controls within its content view | Finder owns the surrounding preview experience, window lifecycle, file navigation, and provider routing |
| Thumbnail extension | Bounded, privacy-safe thumbnail output | No interactive controls; system and other apps may display the representation |

Apple's `QLPreviewingController` guidance says the conforming controller should present the main preview, avoid presenting additional controllers over it, avoid broad gesture interception, and keep file handles open only when necessary. Therefore, use inline controls or compact content-contained disclosures; do not build a modal setup or settings flow inside a Finder preview. [Apple: QLPreviewingController](https://developer.apple.com/documentation/quicklook/qlpreviewingcontroller)

Finder uses Space to open Quick Look and Space or Escape to close it. Our extension must preserve these behaviors rather than using Space globally for MIDI playback or Escape globally for a private shortcut. Route arrow keys to focused content only where the host permits it. Test multi-file navigation with focused text, outlines, tables, and playback controls. [Apple Support: Preview files on your Mac](https://support.apple.com/guide/mac-help/preview-a-file-mchlgtd_prev01/mac)

## Applicable guidance and concrete design decisions

| Apple guidance | Proposed application | Acceptance evidence |
|---|---|---|
| Menus organize commands in familiar groups and use clear labels. [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) | Preserve standard companion app menus. Add Open Test File…, Try in Finder, and format-specific view commands where relevant. Disable commands that cannot act on the focused surface. | Menu audit with no preview selected, text selected, and Settings focused. |
| Respect standard shortcuts; define custom shortcuts for frequent app commands. Support Full Keyboard Access. [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) | Use Command–O for a test file, Command–C for copy, Command–F for find where implemented, and Command–Comma for Settings. Use focus navigation for less frequent actions rather than a new shortcut for every button. | Complete essential flows using keyboard alone; test a non-US keyboard layout. |
| Context menus should be short, relevant, and have alternatives in the main interface. [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) | Offer Copy Value / Copy Path on JSON nodes, Copy on selected text, and Copy Entry Path on archive rows. Reveal is explicit for hidden values. No irrelevant right-click menus on switches or buttons. | Commands are also reachable through visible controls or companion menus; no source deletion commands. |
| Settings should start with good defaults, stay limited, and appear in a dedicated macOS settings window. [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) | Use grouped Appearance, Typography, Format Options, and Privacy panes. Keep durable controls there; keep transient document view changes in the preview. Use the system Settings scene rather than duplicating it as a main-window navigation destination. | First preview works with defaults; Command–Comma opens the same window consistently. |
| Windows support multitasking and use system window controls. [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) | Resizable main utility window with a sensible minimum; retain native chrome. Restore useful window size. A single utility window is sufficient initially; a document editor is outside scope. Settings follows its own auxiliary-window conventions. | Main window remains usable at its minimum size and on multiple displays. |
| Toolbars prioritize frequent commands and avoid overcrowding. [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | Main-window toolbar: Open Test File and relevant sample actions. Preview content row: one mode switch, search when meaningful, and overflow for rare actions. Do not add a persistent global settings gear to every toolbar. | Compact layout has no clipping and all overflow actions remain discoverable. |
| Onboarding should be brief, interactive, and avoid nonessential customization. [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) | Explain enablement and offer a safe sample test. Defer themes, fonts, and advanced options until the user has experienced a preview. Setup instructions remain accessible later. | A new user reaches a meaningful sample without choosing a theme or creating an account. |
| Tables are suitable for scannable textual attributes; selection feedback should match the interaction. [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) | Use native outlines for JSON/archive hierarchies and tables for SQLite rows. Keep selected nodes stable and display typed values with meaningful columns. | Arrow-key selection, disclosure, column headings, and VoiceOver descriptions work. |
| Use progressive disclosure and visual hierarchy. [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Start JSON trees partially collapsed; show schema before expensive data; hide advanced font attributes in a disclosure group. Label preview bounds near the affected content. | First view answers a file's basic identity without opening an advanced panel. |
| Support familiar scrolling and avoid nested scroll views with the same orientation. [Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views) | A single primary scroll region per pane. Code can scroll horizontally when wrapping is off. Tables manage their own scrolling rather than sitting inside another vertical scroller. | Trackpad, wheel, keyboard scrolling, and text selection behave consistently. |
| Report progress accurately and allow cancellation when feasible. [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) | Keep file identity visible while reading. Use determinate progress only with a meaningful denominator; otherwise use succinct activity text. Closing or changing the file cancels work. | No invented completion percentage; cancelled work cannot replace a newer preview. |
| Match interruption to importance; explain commands that cannot be carried out. [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) | Unsupported, unavailable, malformed, and bounded-preview states appear inline. Use modal alerts only for consequential companion settings operations such as discarding a customized profile. | No alert or notification on every preview failure or successful preference change. |
| Request access in context and use sandboxing to protect data. [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) | User-selected test files only; no broad disk permission onboarding. Explain local processing. Keep content out of diagnostics, persistent histories, and custom telemetry by default. | Network/content-log audit; rejected access produces actionable inline guidance. |
| System colors adapt to light, dark, and increased-contrast contexts. [Color](https://developer.apple.com/design/human-interface-guidelines/color) | Use semantic UI colors. Theme palettes apply to content and include light/dark/high-contrast behavior. Errors, data types, and redaction also use text or symbols. | Status remains understandable in monochrome and with increased contrast. |
| Materials should follow semantic purpose and preserve legibility. [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | Let native bars and sidebars use their system appearance. Document backgrounds remain stable reading surfaces. Avoid translucency under code that compromises contrast. | Readability tests over light, dark, and visually busy backgrounds. |

## Typography and accessibility

Use the system font for UI chrome and the system monospaced font for code by default. User-chosen document fonts are compatible with the product's personalization goal, but font fallback must retain language coverage and useful glyph distinctions. Apple distinguishes system, document, and bundled custom fonts; custom font licensing and runtime availability require verification before shipping. [Apple: Fonts](https://developer.apple.com/documentation/technologyoverviews/fonts)

Apple's accessibility guidance recommends supporting substantial text enlargement and auditing with Accessibility Inspector. For this product, require at least 200% content enlargement without losing controls, a 4.5:1 contrast target for normal text, and visible selection/focus in both appearances. These are product acceptance targets consistent with the guidance; check the current HIG when finalizing accessible typography. [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Additional product requirements:

- Provide meaningful control names, values, states, and logical reading order in VoiceOver.
- Expose code as readable selectable text rather than one accessibility element per syntax token or a bitmap.
- Let VoiceOver read JSON key/type/value and tree expansion state, SQLite column/row context, and archive entry metadata.
- Announce hidden values as hidden. Raw secrets must never exist in an accessibility label while the UI claims to conceal them.
- Keep focus out of decorative line numbers; a screen reader must be able to reach the content without traversing every gutter label.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, and relevant text-legibility settings. A theme never removes focus or selection cues.
- Test mixed scripts, combining characters, emoji, bidirectional text, long filenames, and a missing chosen font.

These are implementation acceptance criteria. Native controls provide useful behavior but do not prove the complete app or extension is accessible.

## Correcting overbroad local skill rules

The supplied `macos-design-guidelines` skill is useful as a design checklist. Its absolute wording should not be attributed to Apple:

| Skill wording to avoid applying literally | App-specific resolution |
|---|---|
| Every action/menu item needs a unique shortcut | Keyboard access for all essential actions; new shortcuts only for frequent commands. |
| Every interactive element needs a context menu | Consistent menus on relevant content objects; ordinary buttons and switches need their normal accessible behavior. |
| Delete must remove selected list rows | Data previews are read-only. Delete can edit a settings text field or remove a user-created profile where appropriate; it never deletes archive entries, database rows, or source files. |
| Every app needs multiple main windows and every toolbar needs customization | The setup app is a focused utility. Add multiwindow or toolbar customization only when a tested workflow benefits. |
| Never use an explicit font size | Semantic defaults for UI; explicit, validated sizes are necessary for the requested typography customization. |
| Every window must expose the same controls | Follow macOS settings-window conventions separately from main-window conventions. |
| Index app content in Spotlight / provide notifications | Neither is required for a local preview utility. Do not persist or index inspected user content just to satisfy a checklist. |

## Verification gates before implementation claims

- [ ] Verify keyboard routing, popovers/disclosures, copy, search, and VoiceOver inside the real Finder extension host on macOS 15 and the current supported macOS release.
- [ ] Verify the documented enablement path on each release; localize instructions. A System Settings deep link is an optional convenience only after testing, with a readable manual fallback.
- [ ] Verify any public mechanism used to detect extension registration or enablement. App launch, embedded extension presence, and one successful sample invocation do not establish routing for every format.
- [ ] Use availability checks for newer visual APIs. Keep macOS 15 fallbacks; no custom Liquid Glass adoption is required by this project.
- [ ] Audit themes, font scaling, focus, table/outline semantics, and redacted accessibility output in Accessibility Inspector.
- [ ] Complete later App Store packaging, entitlements, licensing, and review checks independently from this HIG report.

The current enablement instructions are grounded in Apple's Login Items & Extensions support page. They describe a user action in System Settings, not permission for the app to turn itself on automatically. [Apple Support: Login Items & Extensions](https://support.apple.com/en-gb/guide/mac-help/-mtusr003/mac)
