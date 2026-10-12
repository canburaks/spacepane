# Quality program signed-host checkpoint

Observed 2026-10-07/08, Europe/Istanbul. Source artifact: `603e0d08efb4b361724bc4a7c408e74134cb1327`. This records development-signed bundle and limited UI evidence, not release or complete Finder acceptance.

## Build and resources

`./script/build_and_run.sh --verify` completed on the Mac17,8 Apple M5 Pro host, macOS 27.2 (26B5091g), Xcode 27.0 (27A266a), deploying to macOS 15. The existing local signing configuration was reused without identity changes. Xcode built the companion, preview and thumbnail extensions and embedded CAD service; signature validation passed and the companion process launched. The original temporary build log was observed during execution but did not survive the interruption. The built artifact remains in the worktree's ignored `.build/xcode/Build/Products/Debug/SpacePane.app`.

`check_bundle_localizations.py --app ...` passed 33 explicit language/fallback cases in all three signed bundle contexts, with 1,040 keys per bundle and unchanged resources. This establishes resource lookup, not effective Finder language or translation review.

Artifact hashes at the checkpoint:

| Artifact | SHA-256 |
|---|---|
| Companion executable | `15ee7063e8c90190211d0dbb0e8ca8abf9ae8805d2f0b8784ee7a8d498bea6e4` |
| Companion debug dylib | `00617009c28600bddf1e8f0c74b91287728bc2269315ecd03ab27fa42c2e0be4` |
| Preview executable | `3fcbb6f6c53d8d33f808ac49830e34e863cbe70edce44a29b99123b16b095157` |
| Thumbnail executable | `c6d605df4fd432bcf875766d5dd9e86e436f1553fe977814cb31b72375a1a5d5` |

The app CDHash is `f7c293c34e089c6997809764cb6085ebf4835fe1`, signed October 7 at 22:34:15. A 177-file local hash inventory is retained at `.build/quality-work/signed-603e0d0-manifest.json` (manifest SHA-256 `63730d617d664b97fab86c305aba3282245fb24750679873d1b5096fb5bb7e88`). The development identity is `org.webmeister.spacepane`, with the repository's existing team configuration.

## Companion observations

The signed singleton window opened on General, with the four fixed sidebar destinations and Developer Mode off. General reports where settings are saved and that macOS chooses the provider. Theme displayed its pinned JSON sample, Source/Outline selector, typed View mode accessibility label, 13-point typography controls and scheme gallery. These were actual native accessibility-tree and screenshot observations. No preference was changed. No claim is made about spoken VoiceOver output, all widths, all languages or minimum-OS behavior.

## Initial Finder attribution ambiguity

A freshly generated synthetic fixture directory (`.build/host-validation/matrix-y06j2138`) contains a manifest of original bytes. The JSON fixture resolves to `public.json`. Finder's preview pane and Space-bar panel displayed the expected synthetic message, concealed password, findings and Source/Outline controls. The UI identified SpacePane.

However, a read-only process query found preview-extension processes from both the named worktree's app and the primary checkout's older `.build/xcode` app. `pluginkit -m -A -D -v -i org.webmeister.spacepane.preview` confirms two enabled registrations with the same version and identifier. This observation cannot attribute the visible surface to the new artifact, so it does **not** close the production-artifact matrix cell or any new-renderer host gate. No provider preference was changed, registration removed, Finder killed or shared Quick Look cache reset. A controlled single-install observation is still required.

## Hosted baseline

[Full run 37675384863](https://github.com/canburaks/prev/actions/runs/37675384863) passes at exact commit `603e0d0`: portable/static checks, macOS source compiler checks and the package/integration entrypoint. The local entrypoint at this source passed 3,125 parallel tests, five serial liveness tests, all companion/integration checks, 148 contrast ratios and 648 deterministic adversarial cases. Later Q150/Q155/Q15 work is not covered by this artifact or run.

## Single-registration JSON Lines observation

On October 8, the lead unregistered only the stale primary-checkout SpacePane app path with Launch Services `lsregister -u`, then force-registered the named worktree's signed app. This does not change either bundle on disk or the user's extension enablement preferences. The subsequent read-only PluginKit inventory contains one preview registration, pointing to the signed `603e0d0` artifact. No competing provider was disabled, no shared cache reset and Finder was not killed.

A new request for `04-records.jsonl` then displayed SpacePane's concealed synthetic password and Source/Records control in both the Space-bar panel and Finder preview pane. Unlike the earlier ambiguous view, the new hierarchy exposes the typed View mode label and mode shortcut hints. A process query shows the preview extension only at the named worktree's signed artifact path. The Records control, clicked by its visible coordinates, displayed two structured records and the concealed password. This is evidence for the two JSON Lines surfaces on this host and artifact; the resolved type remains `com.quicklookpro.file.jsonl`, so a suffix or catalog declaration alone would not have predicted the result. No third-party type ownership was added.

All generated fixture source hashes still match the creation manifest after these requests. Finder thumbnails remain unobserved. Remote accessibility actions returned AX failure/illegal-argument errors, while the coordinate click succeeded; keyboard mode delivery was not established through this automation and remains open. No general-clipboard copy was performed. The matrix updates only the actually observed JSON Lines surfaces and preserves the old retired-identity observations for other formats.

## Single-registration notebook observation

The same signed `603e0d0` artifact rendered fresh `29-notebook.ipynb` in Finder's preview pane and Space-bar panel. It displayed the synthetic heading/prose, code and saved text output, with the password concealed, and Source/Outline/Rendered controls with the typed mode label. `mdls` resolves the fixture to `com.quicklookpro.file.ipynb`; the running preview process still points only to the named signed artifact. All 83 original fixture-file hashes remain unchanged. This validates the two notebook surfaces for the retained baseline, not the larger-figure changes subsequently committed in `124e781`; thumbnails and actual image Pages still need observation.

After a coordinate click in the notebook body, the mode chord did not visibly change modes. Command-F reached Finder's search UI behind the Quick Look panel; Escape dismissed the panel, exposing that temporary search tab. The lead closed only that search tab and restored the fixture folder. This demonstrates delivery to Finder, not successful embedded-preview focus. Preview keyboard acceptance remains open and needs a focused host investigation; do not turn ambiguous automation focus into a claim that the extension shortcuts pass or fail.

## Information and facts in the signed 3a97e4f artifact

On October 8, `./script/build_and_run.sh --verify` built and signature-verified the companion, both extensions and embedded CAD service from clean `3a97e4fab6a3ac36c97f95df39cce90c63273191`, then launched the companion. The existing identity/configuration was retained. The same Mac17,8 / M5 Pro / macOS 27.2 (26B5091g) / Xcode 27.0 (27A266a) host and macOS-15 deployment target apply. This is a development artifact, not execution on macOS 15. The raw build log is `.build/quality-work/q53-signed-verify.log`.

The 177-file signed manifest is `.build/quality-work/signed-3a97e4f-manifest.json`, SHA-256 `0978dc7d53b50a85240da827dad6a7b0c37639d9bd8cb6bf61f1700ffe55ee74`. App CDHash: `65634ea11394f7037add9b392caa5044f3e733c8`, signing time October 8 at 20:41:30, team `Z743N6D8DS`.

| Artifact | SHA-256 |
|---|---|
| Companion executable | `1b786ec6cadb6b02b21ad3ab39ce15d9637f9248f51bafeec74bfea3d7e6fce1` |
| Companion debug dylib | `417e5ffd52a304e9e8ed894aad4b989bd30a2737d1c2c0b9194ece75ef792fb7` |
| Preview executable | `ccb55a8c962d3e8f1eadab1f793dbe33933ef5fc5180be4f639d6d10c245bcb2` |
| Thumbnail executable | `c2fff56e441b905f7416a474dacbef782d9f9188901d912f1742b6f4d7ccffd0` |

All 33 explicit language/fallback cases pass in all three signed bundle contexts, now with 1,082 keys (`q53-signed-localizations.log`). Resource bytes are unchanged. These checks do not establish native-speaker review or changed per-app/Finder language selection. Full hosted static/macOS [run 37818484024](https://github.com/canburaks/prev/actions/runs/37818484024) also passes at this exact source commit.

In the companion Theme page, the built-in JSON sample shows cached facts and the native Preview information button. Opening it changes its accessibility value from zero to one and exposes app-owned provenance, the zero concealed count and current commands. The panel is visually height-bounded with an internal scrollbar, leaving selectable content below. The facts field truncates visually in the fixed sample width but retains the complete accessibility value. Switching to Outline removes Go to Line from the open panel and retains the other applicable help. The radio action reported an AX failure, but the next fresh accessibility tree and screenshot confirmed that the action had changed the mode. No appearance setting was changed.

For Finder, a new task-owned tab was opened on the existing synthetic fixture directory. The user's personal tab was retained and restored when the task tab closed. A read-only PluginKit inventory contains one preview registration at the task worktree's signed app; the running preview process also points there. No registration repair, provider preference, shared-cache reset or Finder termination was needed.

`03-data.json` displays concealed source and cached facts in the preview pane and Space-bar Quick Look panel. The Preview information action works in both, exposing Read-only preview, Processed on this Mac, Preview by SpacePane, one concealed value and current commands. In the panel, setting the native accessibility scrollbar from zero to one visibly reaches the final command rows without moving the source content. The two automated wheel-scroll attempts did not change the view; wheel-event delivery is inconclusive, not a pass. Switching the actual remote view to Outline preserves concealment and updates the open help, removing Go to Line. Its radio action again reported AX failure even though fresh observations confirmed the mode change.

Returning to the pane and selecting `04-records.jsonl` creates a new preview with its information button collapsed and old panel metadata removed. It shows two records, encoding, displayed lines, source size, the concealed password and Source/Records modes. This revalidates the JSON Lines preview-pane cell for the new artifact; its panel and the notebook cells retain their older exact-artifact evidence. All 83 fixture-file hashes still match the creation manifest after these observations.

The screenshot/AX observations establish this limited English dark-appearance behavior. They do not measure actual safe-area points, first-paint latency, the compact threshold, all Finder surfaces, Full Keyboard Access, source-focused command delivery or spoken VoiceOver. Space opened the panel and Escape dismissed it while host focus was reported; this does not prove child-responder key forwarding. No general-clipboard copy was performed. Q55, the wider S2 matrix and release acceptance remain open.
