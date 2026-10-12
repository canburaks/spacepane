# Task 5 — UI and UX design

Research date: 2026-10-03. Working product name: **Prev**. Baseline: macOS 15.

- [x] Define the companion and Finder preview experiences.
- [x] Define setup, customization, per-format interactions, and unavailable-file states.
- [x] Define prototype gates and measurable UX acceptance criteria.

This is a proposed product design supported by the platform evidence in [Task 3](03-apple-hig.md) and the architecture in [Task 4](04-technology-stack.md). Wireframes, defaults, and targets below are decisions to validate, not observations from an implemented app.

## Product promise and scope

The central job is: select a file in Finder, press Space, understand its contents quickly, and return to work. The companion app handles enablement, preferences, a safe sample playground, and diagnosis. It can quit while the installed extensions serve previews. Apple describes Quick Look as a quick glance without opening an app; this design keeps the selected content primary. [Apple Support: Preview files on your Mac](https://support.apple.com/guide/mac-help/preview-a-file-mchlgtd_prev01/mac)

Customization should improve reading without making setup a design exercise. Start with a readable system theme, monospaced code, wrapping defaults appropriate to the format, hidden likely secrets, and explicit bounds. Advanced controls remain available in Settings. Apple's onboarding guidance recommends deferring nonessential customization; its macOS guidance supports personalization. [Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

The phrase **missing-file previews** has two plausible meanings. Preserve both in the plan until the user chooses a narrower interpretation:

1. **Missing format coverage:** add useful renderers for types the comparison app or macOS does not preview well. The format research report prioritizes these additions; unknown readable text can use a bounded text fallback if Finder actually invokes Prev.
2. **Unavailable file content:** show an informative state when an invoked request refers to a moved/deleted file, broken link, unreadable item, disconnected volume, or unavailable cloud content. Do not claim to reconstruct absent bytes. Finder may never invoke our extension for such an item, so the custom state is conditional on receiving the request; the companion can also display it for a user-selected test file.

## Information architecture

### Multilingual experience

All app-authored visible text must be internationalized from the first implementation: navigation, menus, setup instructions, Settings, format descriptions, tooltips, loading/empty/disabled/error messages, help, accessibility labels/hints and any text drawn into previews or thumbnails. Bundle and system-facing descriptions also use localized resources where supported. The English wording and wireframes in this report are source-copy proposals, not an English-only product requirement.

Use typed localized resources with translator context, plural variants and reorderable placeholders. Human-readable metadata follows the presentation locale. File contents, code, exact source values, names, paths and identifiers retain their original meaning and bytes. App-generated failure explanations are localized domain messages, not raw parser diagnostics.

Layouts must accommodate longer translations and right-to-left navigation, preserve selection/focus, and avoid clipping at enlarged text sizes. Use semantic alignment while keeping source code and direction-sensitive content appropriate to its meaning. Verify VoiceOver labels and actual language/resource selection in the companion and both Finder extensions; a companion-only test is insufficient. The shipping languages remain to be chosen, with at least two complete, reviewed real localizations required; pseudolocalization and RTL testing supplement that coverage. Follow the implementation gates in [PLAN.md](../../PLAN.md).

### Surfaces

```text
Companion main window
  Setup                 enablement guidance and observed sample result
  Try Previews          bundled samples + one user-selected test file
  Supported Files       capabilities, enabled choices, limits, settings link
  Help                  setup steps, privacy, troubleshooting

App menu → Settings… (Command–Comma)
  Appearance            automatic appearance, theme, live sample
  Typography            code/prose/data fonts and advanced attributes
  File Types            search, individual/group switches, enable/disable all
  Format Options        default mode, line numbers, wrap, table behavior
  Privacy               redaction explanation and thumbnail policy

Finder preview content
  File summary          kind, relevant metadata, partial/hidden-value status
  Compact controls      mode, find/filter where meaningful, overflow
  Read-only content     text / outline / table / archive / playback
  Bound/recovery note   only when needed
```

Use a native, lightweight sidebar for the four main destinations and a separate Settings scene. The first launch lands on Setup; later launches return to the last companion destination. A sidebar row needs one label and at most one short secondary status, not stacked diagnostic counters. Support a normal Dock app lifecycle; no login item, permanent menu-bar presence, account, or background monitoring is required for the core experience.

The main window can start near 900 × 600 points with a tested minimum near 640 × 440. These are layout experiments, not HIG constants. Settings uses its own appropriate sizing and system window controls. Keep user customization in content rather than restyling the app's chrome. Apple's settings guidance places durable app settings in a dedicated window and recommends minimizing their number. [Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings)

## Setup and honest status

### First launch

1. Show a short explanation: “Preview supported files in Finder with the Space bar. Your files are processed on this Mac.”
2. Show the enablement path: **System Settings → General → Login Items & Extensions → Quick Look**. Explain enabling the preview and thumbnail entries that the installed build actually exposes. Offer **Open System Settings** only with a tested public mechanism; always retain written instructions. Never call this button “Enable.” Apple documents enabling/disabling these extensions in System Settings. [Apple Support: Login Items & Extensions](https://support.apple.com/en-gb/guide/mac-help/-mtusr003/mac)
3. Offer **Try in Finder** using a small bundled fixture copied into an accessible test location. Reveal/select it and explain “Press Space.” Use an app-owned diagnostic file type to test a known extension path, plus representative real-format samples to test realistic routing.
4. Return a narrowly worded result: **“Prev displayed this sample”** after a verified invocation, or **“Not verified yet”**. An app-rendered sample alone is not a Finder test.
5. Show **“You can quit Prev. New previews use your saved settings.”** only after the packaging and companion-quit test passes. Offer a normal inline action to open Settings, not a compulsory customization step.

Suggested Setup wireframe:

```text
┌ Prev ────────────────────────────────────────────────────────┐
│ Setup          │ Preview files with Space                    │
│ Try Previews   │ 1. Enable the Quick Look extensions          │
│ Supported Files│    [Open System Settings]   Show steps       │
│ Help           │ 2. Check a sample in Finder                  │
│                │    [Try in Finder]                          │
│                │    Not verified yet                         │
│                │ macOS chooses a provider for each file type │
└──────────────────────────────────────────────────────────────┘
```

### Status vocabulary

| Evidence available | Truthful wording | What it does not establish |
|---|---|---|
| App contains extension bundles | “Extensions included” | Installed registration, enabled state, provider choice |
| A supported public registration check succeeds | “Extension registered” with check time | Enabled status or successful Finder rendering |
| App-owned diagnostic fixture reaches the extension | “Prev displayed this sample” with check time | Every JSON/Markdown/folder/extensionless file reaches Prev |
| A real-format sample reaches the extension | “Prev displayed the JSON sample” | Provider selection for all files or future requests |
| No invocation/result has been observed | “Not verified yet” | Proof that the extension is disabled or broken |

Do not build status around undocumented PlugInKit introspection or shell commands. A minimal invocation receipt in shared storage may be useful after a sandbox prototype: timestamp, app build, renderer ID, and fixture ID only, with no file path or file contents. It is diagnostic evidence, not an enabled-state oracle. If no reliable public signal is available, use manual confirmation and transparent instructions. User confirmation is labelled as such.

Registration, enablement, supported types, and selected preview provider are separate concepts. A “supported files” search is a capability catalog, not an OS routing selector. Do not present per-extension switches as though changing a runtime preference rewrites the extension's static supported-type declaration. Registration/deep-link/receipt behavior are P0 verification gates.

## Customization with a live sample

### Choose which file types Prev previews

The user requires individual file-type toggles. **Settings → File Types** is the canonical editor; Supported Files displays the same effective choices and offers **Manage File Types**. This is separate from the operating system's whole-extension controls. [File-type controls decision](../decisions/002-file-type-controls.md).

Search by name or suffix and group related formats under plain labels such as Text & Code, Structured Data, Archives and Media. Each shipped logical type has a labelled switch, visible aliases and relevant limitations. JSON and JSONL remain independent even if they share a decoder; `.md` and `.markdown` are aliases of one Markdown choice. Do not show roadmap formats as enabled capabilities.

Offer group enable/disable with mixed state, **Enable All Types**, **Disable All Types**, and **Reset File Type Choices**. All Types always means the whole catalog, including while search is active; label any separate filtered operation as Search Results. Disable All also establishes the disabled default for formats added in future updates. Group changes modify member choices, with no hidden competing group override. New catalog entries automatically gain the standard controls.

Use the short footer: **“Choose which file types Prev previews. macOS chooses the Quick Look provider. Changes apply to new previews; existing previews and thumbnails may remain cached.”** Do not label these switches Default Provider or imply Finder will switch apps when a type is disabled.

Disabled requests skip content decoding and return **“Previews for this file type are turned off in Prev.”** Thumbnails use a generic glyph. The companion provides Manage File Types and cancels/clears its active content when disabled. Samples obey the same policy. Switching to source mode must not bypass a disabled type. Settings save failures stay visible; corrupt existing choices must not silently become Enable All. Test persistence, mixed states, keyboard focus, VoiceOver labels, new-format upgrades and actual Finder cache behavior.

### Appearance and typography

The Settings sample renders through the same renderer and validated preferences model used by the extension. Bundled fixtures are the default; opening a user's file for testing requires an explicit file-picker or drop action. There is no preview history by default.

```text
┌ Settings ─ Appearance / Typography / Formats / Privacy ─────┐
│ Scope: [Code ▾]              │ Sample: [Swift ▾]              │
│ Theme: [System ▾]            │  1  struct Example {           │
│ Font:  [System Mono ▾]       │  2      let value = "Hello"     │
│ Size:  [-] 13 pt [+]         │  3  }                          │
│ Weight: [Regular ▾]          │                                 │
│ Line spacing: [slider]       │ Live sample                     │
│ ▸ Advanced attributes        │ Uses the current draft settings │
│ [Reset This Section]         │ New Finder previews use saved   │
│                             │ settings; reopen an old preview  │
└───────────────────────────────────────────────────────────────┘
```

Use automatic saving for ordinary validated settings, with a visible unobtrusive saved/error state. A failed save must not display “Saved.” Debounce slider-driven persistence while the local sample updates. Maintain a clear display-setting precedence: temporary preview change → renderer-family override → global preference → built-in default. File-type enablement is an independent gate that display overrides cannot bypass. A Reset action restores only the named section and supports Undo where feasible.

| Control group | Initial offering | Constraints |
|---|---|---|
| Appearance | System, paired Light/Dark themes, high-contrast variant | Theme affects document content; preserve native focus and selection colors. “System” follows host appearance. |
| Typeface | Installed family/style picker for Code, Prose, Data | Default code/data monospaced; missing font falls back with an inline explanation. Do not download/install fonts automatically. |
| Metrics | Font size, supported weight/italic, line spacing | Preview at each setting; at least 200% enlargement, no clipped controls. Reject NaN/out-of-range imported values. |
| Advanced text | Character spacing, ligatures, tab width, token emphasis | Font capabilities vary. Monospaced code alignment must be tested when ligatures/spacing change. Keep these optional. |
| Format defaults | Code wrap and line numbers; Markdown rendered/source; JSON tree/source; data density | Controls vary by renderer, with explicit labels. Switching a default does not change source bytes. |
| Later customization | Named profiles, declarative theme import/export, supported variable-font axes | Only inert schema-validated data. No imported CSS, scripts, grammars, or executable renderer plugins. |

Installed-font and custom-font behavior needs runtime testing in the extension. Apple distinguishes UI fonts from document/custom fonts; do not bundle or redistribute fonts without their license. [Apple: Fonts](https://developer.apple.com/documentation/technologyoverviews/fonts)

New Finder requests read a settings snapshot. The live companion sample updates immediately, but existing Finder views and thumbnails may retain earlier settings. The UI should say **“Close and reopen the preview to see changes”** until cross-process refresh behavior is proven. Do not promise instant refresh or a universal thumbnail-cache purge.

## Finder content design

Use the same anatomy for all renderers: compact summary, relevant controls, readable content, and an inline bounds/recovery note when needed. Add a quiet Prev identity only where useful for routing diagnosis; avoid a promotional banner in every preview. Apple recommends keeping contextual options in the task and using progressive disclosure rather than overloading the initial layout. [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

| File family | First useful view | Interaction and limits |
|---|---|---|
| Source/plain text | Selectable highlighted text; detected encoding; line numbers for code | Find within loaded content, wrap toggle, temporary zoom; horizontal scroll when wrapping is off. No edit/save. |
| JSON | Collapsible key/type/value outline, top-level count when known | Tree/source modes, copy path/value, bounded expansion. Preserve numeric text and duplicate-key warnings; invalid or partial data stays source text. |
| JSONL | Record list with loaded-record count and per-record errors | Select a record for bounded tree/source. A malformed record does not hide earlier valid records. |
| YAML/TOML/plist/XML | Structured view for accepted syntax, otherwise highlighted source | Explain fallback. No entity/network resolution. Secret-bearing configuration fallbacks still pass through redaction. |
| `.env` and secret-bearing config | Keys and masked likely-secret values | “Likely secrets hidden” with a clear explanation that detection is heuristic; explicit per-value Reveal; copy follows the displayed representation. |
| Markdown | Readable rendered blocks with source mode | Select/copy; safe links; no document scripts. Blocked remote resources show a placeholder. Broader diagrams, math, or active MDX are separate coverage decisions. |
| `package.json` | Name/version, dependencies, scripts, package metadata | Scripts are displayed as text. Do not execute them. Bounded details and a source mode. |
| SQLite | Tables/schema/indexes list, then bounded table page | Read-only row selection, paging, copy cell/row; label loaded rows instead of making an expensive exact total. No arbitrary SQL editor or editing. Decline incoherent WAL/sidecar states. |
| ZIP/TAR/GZIP/XIP | Entry list with paths, sizes, and bounded listing status | Expand directory groups or filter the loaded list. Initial view does not extract files. XIP lists content without claiming signature verification. Unsupported/encrypted/split cases are explicit. |
| Folders | Immediate-child summary and entries | No recursive traversal or symlink following by default; no total-size claim based on an incomplete scan. Folder routing/access is a gate. |
| MIDI | Format/tracks/duration when validated; stopped transport | Explicit Play/Pause, labelled scrubber/time, no autoplay. Space remains host-owned; playback stops on closure or request replacement. |
| Later specialist formats | Bounded format-specific metadata plus useful visual content | Add only after parser, routing, resource, accessibility, licensing, and sandbox gates pass. |

Use a real table for rectangular data and an outline for hierarchy; do not mimic tables with arbitrary stacks of text. Selection feedback, column headings, and disclosure behavior need to match the data model. [Apple HIG: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)

Search/filter results explicitly say **“in loaded content”** when bounded. A large file note reports what was actually read or displayed, for example **“Showing the first 20,000 lines; preview limit reached.”** Do not offer an unbounded “Load all” escape hatch. A Next Page action may load another bounded data window if the renderer and total work policy support it. Preserve an omission marker for an overlong displayed line.

## Unavailable, unsupported, and damaged content

Errors should preserve file identity where known, name the problem, and show one useful next step. Keep them inline; avoid successive alerts or automatic retries. Apple's feedback guidance recommends explaining unavailable commands and reserving interruption for important actionable information. [Apple HIG: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)

| State | Suggested copy | Recovery contract |
|---|---|---|
| Unsupported format, callback received | “No specialized preview for this file type.” | Offer bounded text/hex metadata only if safely classified; otherwise use a generic summary. |
| Extension not invoked | Companion help: “macOS may be using another preview provider for this type.” | Explain enablement, real sample tests, and manual provider settings. Do not blame the file parser. |
| File moved or deleted after request | “This file is no longer available.” | Retry reads the current authorized URL once; companion offers Choose File. No stale cached content. |
| Cloud bytes not available | “File contents aren’t available on this Mac yet.” | Suggest making the file available in Finder and retrying. Do not promise no provider network activity or trigger an app-managed download. |
| Read access denied | “Prev couldn’t read this file.” | Companion can choose the file again through the system picker. No Full Disk Access demand for ordinary use. |
| Broken link / inaccessible target | “The linked file isn’t available.” | Explain the link separately from target content; no unrestricted target traversal. |
| Malformed or truncated input | “Structured preview unavailable; showing source text.” | Only if safe text decoding/redaction succeeds; show the parse location when useful. |
| Encrypted archive/database | “This preview can’t read encrypted content.” | Metadata only where supported; no password storage or password prompt in MVP. |
| Empty valid file | “This file is empty.” | Successful empty state, distinct from read error. |
| Work/resource limit reached | “Preview limit reached.” | Show partial content with exact bounds or a safe summary. No spinner that continues indefinitely. |
| File changes while being read | “The file changed while creating this preview.” | Discard inconsistent output; offer one explicit Retry. |

The companion must distinguish file-not-found from access-denied using the actual error when possible. Avoid exposing full sensitive paths in an error unnecessarily. No lost-file reconstruction, stale-content history, or system-wide missing-file interception is promised.

## Privacy must survive every representation

Redaction is a shared model/output policy, not only a visual blur. Hidden content must be absent from visible text, tooltips, VoiceOver values, Copy Value, Copy Row, search snippets, error descriptions, and thumbnails. An invalid-parser fallback must not bypass it. Source and rendered modes must share the policy.

For MVP, generated thumbnails for text/configuration/database previews should use generic format identity or nonsensitive metadata rather than source excerpts. Never generate an unredacted thumbnail from a Reveal action. Treat thumbnail output as visible beyond the immediate preview: Quick Look Thumbnailing enables the operating system and other apps to request/display these representations. No verified system-wide deletion guarantee exists in this design. [Apple: Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing)

Reveal is explicit, per value, session-only, keyboard accessible, and labelled **Reveal Value** / **Hide Value**. It resets when the request changes. Copy of a hidden value returns the redacted representation; after a deliberate reveal, ordinary selection/copy may include the now-visible value, which the UI must make clear. Do not include a hidden “Copy Original” bypass. Heuristic detection may miss secrets, so do not market it as complete secret protection.

Proposed privacy wording: **“Prev processes preview content on your Mac and does not upload it. Likely secrets are hidden by default. Detection may not identify every sensitive value.”** The no-upload claim requires an implementation network audit. macOS or a file provider may retrieve cloud content independently, so “local processing” must not claim that opening any file can never cause network activity. Ask for file access only in the relevant workflow. [Apple HIG: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)

## Keyboard, accessibility, and attention

The companion exposes common commands in native menus. Content controls support keyboard focus and activation even when they do not receive a unique shortcut. Inside Finder, preserve host Space/Escape and multi-file navigation; the actual responder behavior is a prototype gate. Use native text selection and table/outline semantics instead of custom gestures over large preview areas. [Apple HIG: Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [Apple: QLPreviewingController](https://developer.apple.com/documentation/quicklook/qlpreviewingcontroller)

Avoid autoplay, successful-operation alerts, unsolicited notifications, animations under reading content, and global keystroke monitoring. A persistent but quiet bounds or hidden-values indicator is more useful than a toast. Keyboard users must be able to open an outline node, select text, copy a table cell, reveal a value intentionally, and operate transport without a pointer.

Theme/typography acceptance includes 200% enlargement, visible focus, normal text contrast of at least 4.5:1, and information conveyed without color alone. Test VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Motion, Reduce Transparency, mixed writing systems, and font fallback. The app should retain native semantic UI colors even if document content uses a custom palette. [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Color](https://developer.apple.com/design/human-interface-guidelines/color)

## Acceptance and prototype plan

These are proposed product gates; none has been executed in this research task.

- [ ] A first-time test participant reaches a verified Finder diagnostic sample in under two minutes excluding system installation/authorization waits, without choosing appearance options. Report observed results and friction rather than assuming success.
- [ ] An installed signed build shows previews with the companion quit; the Setup status distinguishes fixture use, real-format use, registration, and unknown enablement.
- [ ] Finder Space/Escape closes the preview reliably from each focused content/control state; multi-file navigation never leaves stale content or running audio.
- [ ] Every essential action is keyboard accessible; VoiceOver can read file identity, content, bounds, errors, and hidden-value state with useful semantics.
- [ ] Settings live sample responds within a proposed p95 100 ms for a small bundled fixture; new requests adopt a complete saved snapshot. Existing-request and thumbnail behavior is documented accurately.
- [ ] Preferences corruption, removed fonts, unsupported styles, and invalid theme values recover to readable defaults without a crash or misleading saved status.
- [ ] Ordinary preview targets from Task 4 are measured in the real Finder host. No performance claim is published from this design alone.
- [ ] Large text, deep trees, huge cells, long lines, cloud placeholders, access failures, changing files, and malformed archives always produce useful bounded or recoverable states.
- [ ] Masked test secrets never appear in accessibility output, clipboard paths, search output, diagnostics, source fallback, or thumbnail bytes. Explicit Reveal behavior is verified separately.
- [ ] Markdown/local asset/link handling produces no document-triggered remote request or code execution; relative-resource access stays within proven authorization.
- [ ] All delivered renderers work at tested minimum widths, 200% text scaling, and both appearances; theme focus/selection does not disappear.
- [ ] A support export contains app/OS version and nonsensitive renderer/error identifiers only; the user can inspect it before sharing. No automatic file attachment or upload.

P0 validates packaging, routing, interactions, settings snapshots, privacy boundaries, and unavailable-file behavior. P1 delivers the baseline renderer experiences plus themes and typography. Later phases add specialist formats and advanced profiles only when their value and safety/performance gates are established. The root plan should retain these gates as unchecked until implementation evidence exists.
