# Decision 023: preferences schema 6, color schemes and Quick Look provider diagnostics

Date: 2026-10-05. Status: implemented and checked in isolated models and package tests; real-window, VoiceOver, sandbox and Finder behavior are not verified (see [the validation record](../validation/settings-2026-10-05.md)). This is the settings workstream of [the competitor parity program](025-competitor-parity-program.md). It closes the customization and provider-conflict gaps found in [the competitor landscape](../market/2026-10-05-competitor-landscape.md): LookQuick, PeekCode, Code Peek+ and GoodQuickLook offer named themes, QuickestLook and LookQuick explain or scan for provider conflicts, and Unfold offers live reload and folder options. Every competitor feature there is a vendor claim; this is an original implementation.

## What changes

1. The shared preferences document moves to **schema 6** and persists the four behavior fields that already existed in the snapshot with defaults.
2. `PreviewSyntaxStyle` gains a **light-appearance scheme** and a **dark-appearance scheme** chosen from eleven built-in color schemes. Profiles, theme files and every renderer carry them because they are part of the style.
3. The companion's General page gains the behavior switches and a **Quick Look conflicts** scan. The Theme page gains the two scheme pickers.

The companion keeps its one window and fixed sidebar ([005](005-single-window-tabs.md), [010](010-companion-sidebar-redesign.md)). Nothing here adds a window, a Settings scene or an extension entitlement, and nothing changes which provider Finder uses.

## Schema 6

New persisted fields, all required in a schema 6 document:

| Field | Type and bound | Default for migrated files |
|---|---|---|
| `reloadsOnFileChange` | Bool | `true` |
| `showsContentThumbnails` | Bool | `true` |
| `folderDepth` | Int within `PreviewRequestOptions.folderDepthRange` (1 to 4) | `1` |
| `showsHiddenFolderItems` | Bool | `false` |
| `syntaxStyle.lightScheme` | a `PreviewColorSchemeID` valid for light previews | `standard` |
| `syntaxStyle.darkScheme` | a `PreviewColorSchemeID` valid for dark previews | `standard` |

`PreferenceStore.schemaVersion` is 6. `PreferenceStore(url:)`, `load()`, the `PreferencesLoadState` cases, `PreferencesLoadResult` and `PreviewPreferencesSnapshot` keep their source shape, so both extensions and the thumbnail workstream are unaffected. Their snapshots now read the persisted values through `requestOptions`, `reloadsOnFileChange` and `showsContentThumbnails`.

### Migration

Every migration decodes each field its schema had strictly and defaults only what it lacked. A migrated file is never written by a reader; the companion's first save publishes schema 6 atomically.

| From | Migrated strictly | Defaulted |
|---|---|---|
| 1, 2 | file-type choices, size and wrapping (as before) | everything newer, including the new fields |
| 3 | adds typography and theme | line numbers, syntax style, profiles, new fields |
| 4 | adds line numbers | syntax style, profiles, new fields |
| 5 | syntax style (`usesColor`, `boldRoles`, `italicRoles`) and every profile (`id`, `name`, and its whole appearance) through dedicated schema 5 types | the two schemes (Standard) and the four behavior fields |
| 6 | everything | nothing: a missing key is corrupt |

A schema 5 profile is decoded by `SchemaFiveProfile`, not by the current `PreviewAppearanceProfile`, because the current syntax style requires the scheme keys. A schema 5 file with a missing profile field is corrupt, as before.

Fail-closed behavior is unchanged. A corrupt, oversized, unreadable or unknown-version document returns the disabled-content fallback; an out-of-range `folderDepth`, an unknown scheme identifier or a scheme whose background does not suit its appearance (for example `nord` as the light scheme) is corrupt. Save rejects the same values with `invalidSnapshot` and leaves the saved file untouched. The 64 KiB document bound, the 1,024 override bound, atomic replacement and the single-writer rule are unchanged; a test saves the maximum profile count with long names and all roles styled, plus 500 overrides, and checks the result stays under the bound.

A migrated file that holds only defaults for the new fields keeps `showsContentThumbnails` at its default of `true`. `PreviewPreferencesSnapshot.disabledContentFallback` is unchanged: every format is disabled, so the fallback draws no content whatever the thumbnail default is.

## Color schemes

### Identifiers and polarity

`PreviewColorSchemeID` (in `PreviewSyntaxStyle.swift`) holds stable raw values: `standard`, `githubLight`, `githubDark`, `solarizedLight`, `solarizedDark`, `oneLight`, `oneDark`, `nord`, `dracula`, `paper`, `midnight`. A scheme carries no colors, only a name for a palette owned by the renderer, so a stored or imported scheme cannot introduce a URL, a font, a file or code. Standard is valid for both appearances. Each other scheme has one polarity (its own background is light or dark) and is valid only for that picker. The light picker offers Standard, GitHub Light, Solarized Light, One Light and Paper; the dark picker offers Standard, GitHub Dark, Solarized Dark, One Dark, Nord, Dracula and Midnight.

Separate light and dark choices follow what PeekCode and Code Peek+ offer. The pairing is by appearance rather than a "family" because users commonly mix (for example a Solarized light and a Dracula dark).

### Where a scheme applies

`NativeTextPalette(theme:isDark:increasedContrast:style:)` resolves the effective appearance (explicit Light or Dark, otherwise the system's) and takes `style.lightScheme` or `style.darkScheme` from it. Every renderer already receives its colors through this palette: the text view, line numbers, Markdown, outline, table, safe-mode views and the geometry viewport background. `NativeGeometryPreviewView` gained a `syntaxStyle` property that its palette now passes; the host must set it (an integration request, below).

**Overrides.** The High Contrast theme and the system Increase Contrast setting always use the Standard high-contrast palette, whatever schemes are chosen. A scheme whose polarity does not match the appearance (possible only for unvalidated input) falls back to Standard. "Use syntax colors" off still gives plain text in the scheme's foreground on the scheme's background: the scheme sets the page, the toggle sets the tokens.

**Standard is unchanged.** Its twelve roles map to the values the product shipped with, including the grouping (key, keyword, tag and type share a color), and a test pins every value independently.

### Palette sources and licenses

Values come only from published MIT-licensed palettes, read from the upstream files on 2026-10-05 and recorded with their license text in [ThirdPartyNotices/ColorSchemes](../../ThirdPartyNotices/ColorSchemes/NOTICE.md). The About page acknowledges them in all 14 languages. No code or theme file is copied.

| Scheme | Source | License |
|---|---|---|
| GitHub Light, GitHub Dark | [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) syntax classes (`github-markdown-light.css` and `-dark.css`), generated from GitHub Primer; Primer license at [github-vscode-theme](https://github.com/primer/github-vscode-theme/blob/main/LICENSE) | MIT |
| Solarized Light, Solarized Dark | [altercation/solarized](https://github.com/altercation/solarized), 16-color palette | MIT, Ethan Schoonover |
| One Light, One Dark | [atom/atom](https://github.com/atom/atom) `one-light-syntax` and `one-dark-syntax` `colors.less` (HSL converted to sRGB) | MIT, GitHub Inc. |
| Nord | [nordtheme/nord](https://github.com/nordtheme/nord) `src/nord.less` | MIT, Sven Greb |
| Dracula | [dracula/dracula-theme](https://github.com/dracula/dracula-theme) README palette | MIT |
| Paper, Midnight | Original to this product | not applicable |
| Standard | Original; unchanged from before schemes | not applicable |

Role mapping is this product's, since the upstream projects style different token sets. Each scheme assigns all twelve `PreviewSyntaxRole` cases (the memberwise initializer requires all of them) from the nearest upstream color: keywords and operators from the keyword color, strings from the string color, numbers from the number or orange color, keys from the property or blue color, and so on. The mapping is a design choice and does not claim to reproduce any upstream editor's highlighting.

### Contrast method and results

Contrast is the WCAG 2.x ratio of relative luminance from 8-bit sRGB values. A test (`ColorSchemeContrastTests`) recomputes it independently of the production code for every combination of scheme, appearance and role, plus the foreground, against that scheme's own background, and requires at least **4.5:1**. High-contrast palettes must reach at least **7:1**. Another test reads the colors back from `NativeTextPalette` and the rendered text view, so the table cannot drift from what is drawn.

Several published palettes are below 4.5:1 for text on their own backgrounds, notably Solarized accents and the Dracula and Nord comment colors. Each such value was moved toward black (light backgrounds) or white (dark backgrounds) in 1% steps until it reached 4.55:1, the smallest step with a rounding margin. The original is recorded beside the adjusted value in `NativeColorSchemes.swift`. Adjusted values (original to adjusted): GitHub Dark heading 1F6FEB to 2F79EC; Solarized Light blue 268BD2 to 2075B0, cyan 2AA198 to 207C75, magenta D33682 to C8337C, violet 6C71C4 to 6469B6, green 859900 to 687700, base1 comment 93A1A1 to 687272, yellow B58900 to 8D6B00, red DC322F to D3302D, orange CB4B16 to C34815; Solarized Dark blue 268BD2 to 3794D6, magenta D33682 to DD649F, violet 6C71C4 to 8488CD, comment 586E75 to 809196, red DC322F to E56563, orange CB4B16 to D67349; One Light red E45649 to C44A3F, green 50A14F to 3F7F3E, orange B76B01 to A86201 and CB7701 to A66201, cyan 0184BC to 0179AD, blue 4078F2 to 3A6DDC; One Dark red E06C75 to E1727B, comment 828997 to 8D94A0; Nord magenta B48EAD to B691AF, orange D08770 to D18B74, comment 616E88 to 959EAF, red BF616A to D08A91; Dracula comment 6272A4 to 8591B8, red FF5555 to FF5757.

Lowest text-role ratio per scheme (foreground and all twelve roles): Standard 6.10 light and 9.17 dark (unchanged), GitHub Light 5.36, GitHub Dark 4.57, Solarized Light 4.57, Solarized Dark 4.55, One Light 4.56, One Dark 4.58, Nord 4.55, Dracula 4.57, Paper 5.13, Midnight 7.20; Standard high contrast 10.37 light and 11.25 dark. Contrast on a syntax color alone does not make a theme accessible: bold and italic traits stay available per role and no meaning is carried by color only.

## Theme exchange

`AppearanceThemeCodec.schemaVersion` is 2. A version 2 file carries `lightScheme` and `darkScheme` inside `syntaxStyle`; import still rejects unknown fields, missing fields, scripts, URLs and file policy, and now also unknown scheme names and a scheme that does not suit its appearance. Version 1 files (three syntax-style keys) still import and use Standard for both. A version 1 file that contains scheme keys, or a version 2 file that lacks them, is invalid. Export always writes version 2, within the existing 16 KiB bound. Importing a theme applies appearance only and never changes file-type or behavior choices.

## Companion UI

- **General.** A Previews section with "Reload previews when the file changes" and "Show file contents in thumbnails". The thumbnail text explains that only text that passed the privacy filter is drawn and that macOS may keep earlier thumbnails. A Folder previews section with a depth stepper (1 to 4, the model clamps as well) and "Show hidden items". Rows use the existing toggle row (one VoiceOver element: the switch, hinted by its explanation) and the stepper pattern of the Theme page (label, value and hint on the control; the visible value is hidden from VoiceOver to avoid reading it twice).
- **Theme.** A Color scheme section with a Light appearance picker and a Dark appearance picker, each with its explanation as an accessibility hint, and a note that High Contrast and Increase Contrast keep Standard colors. The existing live sample reflects the choice at once because it renders through the same palette. Reset Appearance restores Standard for both along with every other appearance default, without touching behavior or file-type choices.

All text is localized in the 14 languages (47 keys under `settings.behavior.`, `settings.scheme.` and `settings.providers.`) as drafts pending native-speaker review. Scheme names keep their upstream proper nouns and translate only the Light and Dark words.

The companion does not claim that behavior switches change what a Finder view already shows. Both extensions read the saved values for new requests; whether Finder or macOS redraws an existing preview or thumbnail is outside this workstream.

## Quick Look provider diagnostics

An on-demand scan on the General page that lists other installed apps whose Quick Look extension declares types this app's catalog also covers. It never runs unless the user asks and can be cancelled.

**Scope and bounds.** Roots are `/Applications`, `/System/Applications` and the user's `Applications` folder, whose real home comes from the account database because a sandboxed process's home is its container. Only the immediate `*.app` children of each root are inspected: no deeper folders (so `/Applications/Utilities` is not entered), at most 2,000 applications in all, at most 20,000 directory entries read per folder, at most 32 `.appex` per app and 512 declared types per extension. For each app the scan reads `Contents/Info.plist` and each `Contents/PlugIns/*.appex/Contents/Info.plist` with a 256 KiB cap, opened read-only with `O_NOFOLLOW`, regular files only. Every directory level (`.app`, `Contents`, `PlugIns`, each `.appex`, its `Contents`) must be a real directory by `lstat`; a symbolic link is never followed, and a path with a trailing slash is normalized first because the system would otherwise resolve a final link. This was found by a test over a symlinked `PlugIns` folder. Nothing is executed, loaded, extracted, mounted or written.

**What counts.** An extension counts when `NSExtension.NSExtensionPointIdentifier` is `com.apple.quicklook.preview` or `com.apple.quicklook.thumbnail` and `NSExtensionAttributes.QLSupportedContentTypes` overlaps a catalog format's declared types. Two types overlap when their identifiers are equal, or when either conforms to the other, except that the abstract roots `public.data`, `public.item` and `public.content` match only exactly. Without that exception every provider that declares a root type would overlap every format. A provider declaring `public.data` therefore overlaps only the extension-free text format, which declares it exactly. The app's own bundle identifier is excluded. Results name each overlapping format by its localized catalog name (up to six, then a count), list preview and thumbnail kinds, and are sorted by app name.

**Sandbox behavior.** The companion's entitlements were not changed. A folder that exists but cannot be listed (for example because the sandbox denies it) is reported by name under "Could not be scanned"; a folder that does not exist (a missing `~/Applications`) is skipped silently; bundles whose files cannot be read are counted as "could not be inspected"; reaching the 2,000-app limit is stated. The scan never claims completeness: the empty result is worded "in the folders that could be read". Whether the signed sandboxed app can read any of these folders is not verified.

**Guidance, and what is never claimed.** The text says macOS chooses one Quick Look provider per type, that another app's Quick Look extension can be turned off in System Settings, General, Login Items & Extensions, and that the scan reads installed apps only and cannot tell which provider Finder uses. The page never states that Finder uses this app or another provider ([002](002-file-type-controls.md), [010](010-companion-sidebar-redesign.md)); the existing Open System Settings button sits on the same page.

**Structure.** `QuickLookProviderScanner` is an actor, so blocking reads run off the main actor, with cancellation checked between bundles and roots; its roots, limits, catalog and excluded identifiers are injectable. `QuickLookProviderDiagnostics` is a main-actor observable model that owns one scan, drops a late result from a cancelled or replaced scan and returns to its starting state on cancellation or failure. The view owns no scanning logic.

## What is not promised

- That a scheme, the behavior switches or a changed folder option refreshes a Finder preview, a cached thumbnail or a Quick Look window that is already showing.
- That the thumbnail setting has any effect until the thumbnails workstream consumes `showsContentThumbnails`, or that live reload has any effect until the interaction workstream consumes `reloadsOnFileChange`. This decision persists and exposes the choices; it does not implement those behaviors.
- That the provider scan finds every conflicting extension. It cannot see apps outside the three roots, inside subfolders, or in folders the sandbox denies, and an extension can conflict only through types it declares. A reported overlap shows that two extensions both declare related types, not that macOS chose the other one.
- That the palette values equal the upstream projects' current values: they were read on 2026-10-05 and some were adjusted for contrast.
- Native-speaker quality of any translation, or that scheme names read naturally in every language.

## Integration notes

- `NativePreviewView` should set `geometryView?.syntaxStyle = syntaxStyle` before showing a geometry presentation so the CAD viewport follows the scheme. Until then the geometry viewport uses Standard colors.
- `PreviewSession.settingsChanged` reloads only for file-type policy changes. A change in `folderDepth` or `showsHiddenFolderItems` does not reload an open folder preview in Try Preview until that method also compares `requestOptions`.
- `tools/test_localization.py` lists the formatted keys explicitly; this change added eight under `# [settings]`. Merging several workstreams will need a union of that list.
- Third-party license texts are in `ThirdPartyNotices/ColorSchemes/NOTICE.md`; bundling them with the app is a release decision.

## Acceptance gates

- [x] Schema 6 round trips and migrates from schemas 1 to 5 with strict decoding, corrupt-storage recovery, atomic publication and the existing bound.
- [x] Eleven schemes, separate light and dark choices, contrast of every role at least 4.5:1 and high contrast at least 7:1, overrides and Standard unchanged.
- [x] Theme exchange version 2 with version 1 imports as Standard.
- [x] Behavior switches, scheme pickers and the provider scan in the companion with isolated model checks.
- [ ] Real-window verification, VoiceOver and keyboard checks, translated layout, native-speaker review.
- [ ] The scan in the signed sandboxed app, and a Finder-hosted check that extensions read the new fields.

## Amendment, 2026-10-11: a twelfth scheme, Aurora

The owner asked for the palette of the website's live preview as a real scheme, so that store screenshots and the
website show colors the app can produce. `PreviewColorSchemeID` gains `aurora` (raw value `aurora`, dark, last in
the dark picker), with the palette `NativeColorSchemes.aurora`. The settings schema stays 6: a scheme is one more
value of an existing field, and a build that does not know it falls back to Standard for the appearance, as it does
for any scheme of the wrong polarity.

The values are the website's own (`.qv` in `web/src/styles/preview-theme.css`): background `0x1B1C21`, foreground
`0xE8E9EF`, key `0x8FB4FF`, string `0x9FE3B0`, number `0xF7C37B`, literal `0xC7A6FF`, keyword `0xFF8FC6`, type
`0x6FE0E8`, operator `0xA6A9B6`, addition `0x3FBF6F`, deletion `0xF05F5F`. One value changed: the website's comment
ink `0x6C7083` measures 3.47:1 on that background, so the scheme uses `0x7F8393`, the smallest step toward white
that reaches 4.5:1. Heading takes the literal color and tag the keyword color, the website having no such roles.
The muted ink is the website's chrome muted `0x8E909C` (5.36:1; body text is 14.04:1) and the hairline `0x36373C`
is the foreground blended 13 % into the background (1.43:1). Lowest text-role ratio: 4.51 (comment).

The website still draws this palette as its unnamed default, which it calls Standard, while the app's Standard dark
palette is different (`0x1B1B1B` with blue keywords). The website now also lists Aurora among the dark schemes;
making its default say what the app's Standard looks like is a separate change.

