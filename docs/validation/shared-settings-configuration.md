# Signed shared-settings configuration

Date: 2026-10-03 (Europe/Istanbul).

## Reported failure and cause

The user's Finder preview displayed “Shared extension settings are unavailable. Open the companion app to review setup and saved choices.” Inspection of the registered preview extension with `pluginkit`, its built Info.plist and `codesign` confirmed a real Apple Development signature but compile-only bundle/App Group identifiers. Both metadata and the signed entitlement contained `group.invalid.example.previewprototype`.

`HostedConfiguration` deliberately rejects that reserved group prefix. The extension therefore returned before reading settings or source content. The companion could use private settings, but launching it could not repair the extension's build configuration. This was not evidence of damaged user preferences.

## Configuration applied

The user explicitly authorized generating identifiers. The ignored `Configuration/Local.xcconfig` now supplies brand-independent technical identities, reusing the development team already selected in the user's Xcode project:

- Base bundle: `com.canburaksofyalioglu.filepreview`
- Preview: base plus `.preview`
- Thumbnail: base plus `.thumbnail`
- App Group: the signing team ID followed by `.com.canburaksofyalioglu.filepreview.shared`

The precise team/group values remain in local configuration. This macOS-only team-prefixed group uses Apple's supported signature-based authorization without a provisioning profile. This differs from a `group.*` identifier requiring appropriate provisioning; see [Apple's existing macOS app container guidance](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). No developer-portal registration, Store listing or publication was performed. Future display-name changes must retain these identities; later distribution validation remains necessary.

The user's pre-existing changes to `Prev.xcodeproj/project.pbxproj` were preserved. The project was not regenerated. Existing private prototype settings were not moved or overwritten. New shared settings were written through the signed companion UI, with JSON restored to its initially enabled state after the test.

## Code correction

The preview now distinguishes a missing/unresolvable shared container from an unreadable/corrupt/unsupported saved snapshot. The former explains that build configuration and signing need checking; the latter retains companion recovery guidance. Both states clear displayed content and avoid parsing. No permissive fallback, container-permission change or disabled-policy bypass was added.

The new message uses the typed localization API and String Catalog, bringing development resource coverage to 102 keys. This is not a claim of additional shipping translations.

## Observed verification

Environment: full Xcode 27.0 (27A266a), Swift 6.4, macOS SDK 27.0, Apple silicon host running macOS 27.2. Deployment remains macOS 15 with Swift 6 complete checking and nonisolated default. The earlier license failure no longer occurs.

| Check | Result |
|---|---|
| `./script/build_and_run.sh --verify` | Signed full app build succeeded; companion launched; app and embedded extension signatures verified |
| Built metadata vs signed entitlements | Same App Group in the app and both extensions; placeholder IDs replaced |
| `pluginkit` read-only query | New preview extension registered from `.build/xcode/Build/Products/Debug/Prev.app` |
| Companion File Types | “Settings are shared with the extensions” and “Settings saved” observed; disabling JSON produced native mixed group state |
| Finder preview pane | `Fixtures/Normal/example.json` showed the disabled-type state while JSON was off |
| Finder Space-bar preview | After re-enabling JSON and requesting a new preview, the same fixture displayed its original number lexeme, duplicate keys and Unicode content with the read-only notice |
| `--test` | 90 package tests in 4 suites and 4 isolated companion model checks passed |
| `--check-compiler` | All 3 host source sets passed |
| `--check` and whitespace validation | 3 formats, 3 targets, 2 embedded extension declarations and 102 keys passed |

The shared container denies direct shell reads on this host; no permission bypass was attempted. Cross-process behavior is supported by the signed companion's saved status and the extension's observed disabled/enabled transitions, rather than a claimed direct inspection of its snapshot bytes.

The original screenshot was from an older preview request. Existing views may retain stale content; close/reopen Quick Look or select another file to issue a new request. No Quick Look cache reset, Finder kill, provider-priority override or system extension preference change was used.

## Remaining evidence boundaries

- The actual JSON Finder preview and preference handoff are verified on this host; this does not cover every format or Finder surface.
- Thumbnail bundle signing/embedding is verified, but thumbnail invocation is not independently observed.
- Companion quit was attempted, but the subsequent UI sequence did not establish a complete fresh-preview lifecycle check; that gate remains open.
- File Types settings inspection succeeded in this signed build. The earlier Appearance-specific inspection failure and full keyboard/VoiceOver audit remain unresolved.
- macOS 15 runtime, Intel, clean install/update, competing providers and release distribution still require separate validation.
