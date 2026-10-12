# Preview interaction and live reload

Date: 2026-10-05. Status: accepted as the interaction workstream of [the competitor parity program](025-competitor-parity-program.md). Implementation and package-level validation are recorded in [the interaction validation](../validation/interaction-2026-10-05.md); Finder-hosted behavior is not verified.

## Gaps closed

Competitor claims, none tested by us: in-preview search and jump to a line (Peek), one-click copy of a whole file (PeekCode), copying a key, value or path from a JSON tree (JSON Loupe Pro, FinderPeek), reloading when the file changes (Unfold v3, Markdown Peek), a badge naming the provider that made a preview (LookQuick), and temporary zoom (this product's own plan). Every feature below is an original implementation on the existing safe presentations; none reads the previewed file, a preference or the clipboard except where the user asks to copy.

## Privacy rule that governs all of it

Everything displayed, copied, filtered or announced comes from the privacy-filtered presentation (`TextPresentation.text`, the text view's string, or `SafeOutlineNode` values). Copy commands, the filter and Go to Line never reach raw source, so a concealed value copies as its concealment token and cannot be found by searching for the secret it hides.

## Live reload

`PreviewCore/PreviewSourceMonitor.swift` watches one file or folder with a `DispatchSourceFileSystemObject` on an `O_EVTONLY` descriptor, which grants no read or write access. Only regular files and folders are opened (a `stat` before and an `fstat` after the open), so a pipe or device is never touched. Events: write, extend, attrib, rename, delete, link, revoke.

- **Coalescing.** Reports are made after a quiet period (300 ms) with an upper bound (2 s) so a continuously growing log still refreshes. A burst is one report.
- **Atomic saves.** Editors save by writing a temporary file and renaming it over the original, which deletes or renames the watched vnode. The monitor then re-opens the path, immediately and with a bounded schedule of delayed attempts (10 ms to 800 ms, about 1.6 s in total), and reports `.replaced` once a new file is there and watched. This is event-driven, not polling: the delayed attempts exist only after a vnode disappeared and stop after seven tries.
- **Ends.** If nothing reappears the monitor reports `.removed` and ends; on revoke (access withdrawn, for example an unmounted volume) it reports `.revoked` and ends. A file that returns after the retries is not noticed: there is no polling and no parent-folder watch, because the sandboxed extension holds access to the file, not its folder.
- **Teardown.** `stop()`, dropping the monitor, or cancelling the consuming task cancels the source and closes the descriptor in the source's cancel handler; `stopAndWait()` returns after the close. A process-wide counter of open descriptors is exposed to tests.
- **Never writes.** The monitor opens event-only, writes nothing, creates nothing and never opens the previewed file for reading.

`PreviewCore/PreviewLiveReloader.swift` ties a monitor to a host's pipeline. It owns one monitor and at most one reload; every report cancels the previous reload and bumps a generation, so a slow reload that finishes after a newer change, after `stop()` or after the reloader moved to another file is dropped and can never replace newer content. The host supplies `load` (read the preference snapshot again, run the pipeline) and `apply`. A reload that finds live reload switched off, or the shared settings unreadable, ends the watch.

### Hosts

- **Finder preview extension.** After the first display of a shown or curable outcome (`PreviewLiveReloader.watches`) with `reloadsOnFileChange` on, the controller starts a reloader. Each reload re-reads the App Group snapshot, so appearance and policy changes apply, and displays with `resetsContentState: false`. The reloader stops when the view disappears and when a new request starts; when the view appears again with a remembered file it watches again and reloads once, since changes meanwhile were not watched.
- **Companion.** `PreviewSession` watches while the Try Preview page is visible, the first request has finished and the outcome is one a change could alter. The reload keeps the session's `generation`, so the pane keeps mode, scroll position and selection, and does not flash the loading state. The page reports its visibility; hiding it stops the watch and showing it again reloads once. Turning the switch off or on in settings (`settingsChanged`) stops or starts the watch for the open file. The file's security scope is held for exactly as long as it is watched. A policy change (file-type enablement) still replaces the request and gets a new generation.
- **Deleted file.** The reload runs once more and shows the unavailable state, then the watch ends.

### Preserving the reader's place

`NativePreviewView.display(... resetsContentState: false)` with new content of the same format now keeps the selection (clamped to the new text), the scroll offset (clamped), the chosen mode, an open outline's expanded and selected rows (matched by key path and same-name ordinal, not object identity) and the outline filter. A new request (`resetsContentState: true`, `showLoading`, or an unavailable outcome) resets all of it, including zoom and the Go to Line bar. Tables are owned by the listings workstream and still reset their scroll and selection on replacement.

### Not promised

- Finder may not keep a Quick Look extension alive, or may stop delivering events to a preview that is not shown. Reload happens only while the extension process runs and the preview is shown; nothing here asks Finder to keep it running.
- Whether the extension's sandbox grants an event-only open of the previewed file, and keeps access after the completion handler, is unverified. If the open fails there is simply no live reload and the preview is unaffected.
- Whether a sandboxed companion can re-open a user-selected path after an atomic save (a path-based extension) is unverified.
- Network volumes, FUSE and some cloud-synced folders may not deliver vnode events.
- A reload never edits the file and never interrupts the displayed content on failure beyond showing the honest state the pipeline returns.

## Go to Line

Command-L in a text mode (Source or Rendered) opens an inline bar between the mode control and the text: a labelled number field, the valid range or an error, and a close button. There is no window or panel. The number is a logical line of the displayed, concealed text (`LogicalLineIndex`; soft wraps never count, CRLF is one break), so it is not an original-source line after a multiline concealment, like the gutter. Return selects the line (without its separator), scrolls it to mid-view, announces "Line n of m" and closes the bar; an invalid entry (not a whole number, zero, out of range, or text without lines) stays open with a localized error that is also announced. Native digits (for example Arabic-Indic or Bengali) are accepted. Escape or the close button dismisses and returns focus to the text. The shortcut is not offered over outlines, tables or non-content states, and only acts while keyboard focus is in the preview or nowhere in particular, so it never overrides a text field elsewhere in the companion window.

## Copy

Copy All (Command-Shift-C and the text view's context menu) copies the displayed text of the current text mode, never source. For outline, table and derived modes it copies the document's concealed text. It does nothing without content, and is not taken from an editing text field. Outline rows add context-menu commands and VoiceOver custom actions: Copy Value (a container's value is its readable subtree as indented `key: value` lines, not the `{…}` placeholder), Copy Key, and Copy Path. A path is JSONPath-style (`$.a.b[2]`): identifiers use dots, array positions use `[n]`, and every other key is bracket-quoted with RFC 9535 escapes (`$['my key']`), so a path is one line. A secondary click acts on the row under the pointer, or on the whole selection when that row is part of it; several rows give one line each. Hosts and tests substitute a private pasteboard.

## Outline filter

Outline presentations (Outline, Records, Summary, Cues) show a search field above the rows. It filters by key or value, ignoring case, diacritics and width, as a literal substring (never a pattern). Matches stay listed with their ancestors opened; a matching container with no matching descendants keeps its whole subtree available, collapsed. Container placeholders do not match. Clearing the filter restores what was open before it. Work is bounded: an outline has at most 20 000 nodes, searched text is folded once and cached, only the first 4 096 UTF-16 units of one key or value are searched, and the query is cut at 256 units. The result count is shown beside the field and announced to VoiceOver ("Matches: n" or "No matches"). Escape clears the text, and Escape on an empty field returns focus to the rows. Command-F focuses the field in outline modes and still opens the system find bar in text modes; Return, Shift-Return, Command-G and Command-Shift-G move to the next and previous match. Tables are filtered by the listings workstream; Command-F in a table mode is not claimed.

## Temporary zoom

Command-plus (also the equals key), Command-minus and Command-0 change the displayed font size for this preview only, across text, outline, table and derived modes. Zoom is a point offset from the saved size, clamped to `PreviewTypography.fontSizeRange`, applied through `effectiveTypography` and therefore reaches every renderer, including views registered in `SafeModeViewRegistry`, through `SafeModeStyle`. It is never persisted, restyles without source I/O, keeps selection and scroll, survives a reload, and resets with a new request. The status line shows the zoom and how to reset it. A key at a limit is still consumed. The 3D view keeps its own camera zoom. The text view's context menu lists Zoom In, Zoom Out and Actual Size.

## Provider badge

An info symbol (`info.circle`, `PreviewInfoBadge`) at the trailing edge of the header carries "Read-only preview" and "Preview by %@" in its tooltip and accessibility label. The name is the configured display name (`HostedConfiguration`, never a literal), in the Finder extension and the companion's Try Preview. The badge appears only while a preview is shown, not for loading, unavailable or disabled states. Hosts set `NativePreviewView.providerName` or pass `providerName` to `NativePreviewPane`. With nil, the Theme page sample's case, the tooltip has only the read-only caption.

Amended 2026-10-06: the two captions used to be the first and last lines of the status line, which cost two lines above every preview. The badge sits beside the mode control when there is one; otherwise it starts the status row, which then keeps one line even without notices. The status line now holds only notices about this document, such as concealed secrets, a structure fallback, Rendered or Invisibles notes, profile notes and zoom, and it collapses when there are none. The privacy notice stays as text because it changes what selection and copying return.

## Localization and accessibility

All 23 new strings (`preview.interaction.*`) are `PreviewStrings` keys with drafts in all 14 languages awaiting native-speaker review. Counts avoid plural forms ("Matches: n"). Controls carry accessibility labels, help and announcements; the context-menu copy commands are also VoiceOver custom actions on every outline cell. Real VoiceOver, keyboard focus inside Quick Look, translated layout and the keyboard route in a signed host are not verified.

## Shortcuts

| Key | Action | Where |
|---|---|---|
| Command-L | Go to Line | text modes |
| Command-Shift-C | Copy All | any shown preview |
| Command-F | find bar (text), focus filter (outline) | text, outline |
| Command-G, Command-Shift-G | next and previous find or filter match | text, outline |
| Command-plus, Command-minus, Command-0 | zoom in, out, actual size | text, outline, table, derived |

Key equivalents run in `NativePreviewView.performKeyEquivalent` and only while focus is within the preview or nowhere in particular.

## For other workstreams

- A derived mode view receives zoom automatically: use `SafeModeStyle.typography`, never the saved preference.
- Copy All falls back to the presentation's concealed text, so a derived view needs no copy code of its own; add context-menu copy of a selection from safe data only.
- A table filter belongs in the table view; Command-F is left to it in table modes. Reuse `OutlineFilterQuery` for matching.
- Do not read the preference store from a view; hosts re-read the snapshot on every reload.

## Rejected

- Polling or a timer-driven refresh: the monitor uses kernel events only.
- Watching a file's folder or the whole volume (FSEvents): wider access and heavier than a vnode watch for one file.
- Persisting zoom or a filter: temporary by definition; durable per-file history is not kept.
- A new window or panel for any tool: inline bars only, per the single-window decisions.
