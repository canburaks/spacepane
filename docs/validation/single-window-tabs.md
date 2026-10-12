# Single-window navigation validation

Date: 2026-10-03 (Europe/Istanbul). Decision: [one companion window](../decisions/005-single-window-tabs.md).

## Implemented behavior

One SwiftUI `Window`, identified by the typed `CompanionSceneID.main`, owns six native tabs: Setup, Try Preview, Supported Files, Settings, Customization and Help. The app owns the selected route; the shell retains the preview session and settings observation above the tab contents. No dedicated Settings scene or multiwindow `WindowGroup` remains. The unused settings wrapper was removed.

Settings menu actions, Command-comma, toolbar Settings and Supported Files' Open Settings select the Settings tab. About selects Setup, and Help selects Help. Commands target the same singleton scene. Open File uses the existing attached system file-selection sheet and direct-preview pipeline. Parser, persistence, extension lifecycle and Finder provider selection are unchanged.

All three new app-authored labels use typed localization keys. This brings development resource coverage to 105 keys; shipping translations remain a separate gate. The user's existing Xcode project changes were preserved without regenerating it.

## Checks performed

Environment: Apple silicon, macOS 27.2, Xcode 27.0 (27A266a), Swift 6.4, macOS SDK 27.0. Deployment remains macOS 15.

| Check | Observed result |
|---|---|
| `./script/build_and_run.sh --verify` | Signed companion and both embedded extensions built; signatures passed; companion launched |
| `./script/build_and_run.sh --test` | 90 package tests in four suites and four isolated actual companion-model checks passed |
| `./script/build_and_run.sh --check` | Project/catalog/resources validated, including 105 typed localization keys |
| Setup, Supported Files, Settings, Help | Native tab selection observed in `companion.main` |
| Command-comma | Selected Settings in the existing window |
| Supported Files → Open Settings; toolbar Settings | Selected Settings in the existing window |
| About menu | Selected Setup without an About panel |
| Help menu | Selected Help in the existing window |
| Command-O | Opened a system sheet; selecting `Fixtures/Normal/example.json` displayed its exact synthetic content in Try Preview |
| Loaded Preview → Settings → Try Preview | Filename and exact JSON content remained available without reopening the file |
| File menu | Open File and close actions present; no New Window action |
| Visual layout | All six tabs visible across the top of the 980 × 700 window; selectable JSON below |

No settings values were changed during these navigation checks. No Finder cache reset, Finder termination or provider-preference change was used.

## Remaining validation

- Clicking Customization caused the native UI inspection tool to report that its pipe closed before a response, matching the previously observed Appearance inspection limitation. Its view compiles inside the same tab switch and has no separate scene, but live control interaction, appearance layout and return navigation were not verified in this run. This is a tooling observation, not evidence that those GUI checks passed.
- Complete keyboard focus/VoiceOver coverage, narrow-window and translated layouts, and macOS 15 runtime validation remain open. A current-SDK build with a macOS 15 deployment target does not prove macOS 15 runtime behavior.
- Closing/relaunching the singleton was not exercised as a full lifecycle test. The 2026-10-04 review corrected the earlier comment's unsupported promise that a menu reopens after closure: a sole primary `Window` can terminate the app when closed. Finder-hosted previews remain separate OS-owned surfaces and were not retested for this navigation-only change.
