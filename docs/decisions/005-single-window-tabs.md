# One companion window with tabs

> Amended 2026-10-04 by [the sidebar redesign](010-companion-sidebar-redesign.md): the six tabs became sidebar destinations (General, File Types, Theme, About, and Try Preview in Developer Mode), About and Help select About, and Command-comma selects File Types. The single-window contract below is unchanged.

Date: 2026-10-03. The user explicitly requests every app screen in the same window, including settings and customization. This decision supersedes the initial separate Settings-window recommendation in the research and macOS skill defaults.

## Navigation contract

The companion owns one singleton main window. Setup, Try Preview, Supported Files, Settings, Customization and Help are top-level tabs. File-type choices live in Settings; preview themes, fonts and layout live in Customization. Existing feature components remain separate views rather than becoming one large screen implementation.

Every in-app settings button and Command-comma selects the Settings tab. Help selects Help. About selects Setup rather than opening a standard About panel. Commands target the same singleton scene while the app is running; they must not create another instance. Closing the sole primary window may terminate the app, so reopening is not promised as an in-process menu lifecycle. Remove dedicated Settings scenes, SettingsLink entrypoints and multiwindow creation commands.

Tab selection is shared with commands at the app boundary. Preview request/session state and the settings store outlive tab changes, so opening customization does not discard an active file or reload it. Parser and extension behavior are unchanged. Normal app-window closure still performs request cleanup.

File selection is an OS-provided sheet attached to the main window, not another app content destination. Finder Quick Look remains hosted and controlled by macOS outside the companion; this navigation change does not replace Finder's UI or alter provider selection.

## Validation

Verify native tab navigation, every settings entrypoint, Command-comma, About/Help actions, file selection, retained preview state and keyboard focus. Confirm the window identity stays the same and the app offers no second content/settings window. Reuse existing preferences/parser/model checks; do not claim complete VoiceOver or language coverage from compilation alone.

## Translated navigation follow-up — 2026-10-04

Use explicit native grouped tab style (macOS 15+) within the existing singleton
window. Automatic toolbar-integrated tabs overflowed as a whole in Portuguese at
980 × 700; the grouped style keeps the tab row in the content area. Portuguese and
Spanish Setup checks show all six tabs. Selection bindings, menu routing and the
single-window contract are unchanged. Other languages and minimum-width layouts
remain part of the broader UI audit.
