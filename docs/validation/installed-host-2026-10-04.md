# Installed-host continuation

Date: 2026-10-04 (Europe/Istanbul). This continues [shared-settings validation](shared-settings-configuration.md) using the previously signed Debug build on the same Apple silicon macOS 27.2 host. It does not close the full supported-OS matrix.

## Companion-stopped requests

The Customization inspection attempt again closed the native automation pipe. A read-only process query immediately afterward confirmed the signed companion was still running. The scoped crash report names SkyComputerUseService, with a Swift assertion in `Array.remove(at:)`; this supports a tool-service failure, not an observed companion crash. The app was then stopped with SIGTERM for the following lifecycle check. This establishes requests while the companion process is absent, not graceful-quit or update/reinstall behavior.

Three new synthetic fixtures were created under an ignored, freshly named `.build/finder-host-*` directory after stopping the companion. They contained unique test messages and synthetic secret fields. No existing user file or Quick Look cache was modified. Both before and after JSON invocation, the companion process was absent; the preview extension process ran from this repository's signed app bundle.

| File | Observed metadata type | Finder preview observation | Attribution |
|---|---|---|---|
| `.json` | `public.json` | Preview pane and Space-bar panel displayed the fresh message, concealed `token` value, shared privacy notice and selectable Preview content | Matches this app's UI and redaction; signed preview extension process observed |
| `.jsonl` | `com.quicklookpro.file.jsonl` | Space-bar panel displayed only generic file metadata/icon | No Prev source preview observed; resolved third-party type differs from the catalog's declared types |
| `.txt` | `public.plain-text` | Space-bar panel displayed raw text including the synthetic assignment, without this app's privacy notice | Another provider's behavior; Prev's privacy policy does not control it |

The JSON Lines suffix is recognized by the companion parser, but that does not guarantee Finder dispatch. No third-party type ownership, blanket type declaration, provider override or priority change was added. Plain-text parser support likewise remains distinct from Finder provider selection.

All three source byte sequences were compared with their generated originals after the requests and remained unchanged. No account data, real secrets or private user documents were used.

## Thumbnail diagnostic

`qlmanage -t -s 256 -o <ignored-output-directory> <fresh-json-fixture>` produced a content thumbnail rather than this extension's generic page glyph. No running `PrevThumbnailExtension` process was observed by the subsequent process query. A post-request query cannot prove a process never ran, but neither the output nor that query establishes invocation of this thumbnail provider. The thumbnail gate stays open; `qlmanage` success alone is not accepted as proof.

## Scope still open

- JSON preview with the companion absent is now observed on this host. Graceful quit, cold extension launch, competing-provider combinations, updates and reinstall remain separate checks.
- JSON Lines/plain-text routing and our thumbnail invocation remain unverified or unavailable in the tested surfaces, despite parser support and valid signed bundles.
- macOS 15 and Intel runtime, complete keyboard/VoiceOver behavior, shipping translations and Customization UI interaction remain open.
- No system extension preferences were changed; Finder was not killed and shared caches were not reset.
