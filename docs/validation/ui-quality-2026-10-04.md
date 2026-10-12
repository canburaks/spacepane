# Customization, cancellation and accessibility checks — 2026-10-04

This pass validates actual companion models with isolated temporary storage. It
does not close the live Customization, VoiceOver, translated-layout, macOS 15 or
Finder-host gates. The lead performs live UI inspection separately. The existing
uncommitted implementation and validation changes were preserved.

## Concrete fixes

- `CompanionSettings.saveAppearanceProfile` now rejects duplicate names at the
  model boundary, matching the existing UI rule. Profile IDs, the persistence
  schema, saved appearance fields and file-type policy remain compatible.
- `AppearanceThemeTransfer` owns a single import task and request generation.
  Cancelling, replacing or releasing its owner prevents late results from applying.
  A newer manual appearance edit wins over a pending import; an unrelated file-type
  policy edit survives a successful import. A transient appearance revision detects
  A→B→A edits even when the final appearance equals the request's initial value;
  it neither changes persisted schema nor advances for file-policy/profile edits.
  Cancellation does not forcibly preempt
  a noncooperative native read; the existing reader still bounds the source to
  16,384 bytes and owns security-scoped access on its actor.
- The Customization view cancels its import on disappearance and uses native
  import/export cancellation callbacks. Export data is an immutable appearance-only
  snapshot and is released after the sheet completes or is cancelled. Cancellation
  clears transfer feedback instead of displaying a failure. Imported appearance
  is applied in memory before persistence; the separate storage status continues
  to report a failed save and supports retry without losing the visible choice.
- `PreviewSession.fileImporterFailed(error:)` ignores Swift cancellation and
  Foundation's typed user-cancelled error. A dismissed picker preserves the
  current source URL, immutable safe presentation, request generation and in-flight
  request. Actual picker errors retain the existing clear/error behavior.
- Typography steppers expose explicit localized accessibility values, preserving
  current point values and tab width when their accessibility labels are overridden.
  Profile Apply buttons expose the existing localized Apply hint. This is source
  attribute hardening; VoiceOver speech and focus order remain unverified.

The selected SDK declares import/export overloads with explicit cancellation
callbacks available on macOS 14, so their use respects the macOS 15 baseline.
The API shapes were checked against the local SwiftUI interface and Apple's
[import documentation](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:oncancellation:))
and [export documentation](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttypes:defaultfilename:oncompletion:oncancellation:)).
The existing FileDocument export implementation remains in use; no newer document
API, auxiliary companion window, localization key or dependency was introduced.

## Isolated verification

`script/test_appearance_interactions.py <SwiftPM-bin-directory>` compiles the
production settings, preview-session and theme-transfer models with Swift 6,
complete concurrency checking and a macOS 15 deployment target. Its temporary
fixtures never access the user's preferences or general clipboard. All five groups
passed:

1. Full profile application/reset, invalid and duplicate-name rejection, 32-profile
   bound, deletion, preserved policy and restoration by a new settings instance.
2. Inert export snapshot, cancelled import/export status, all-field import,
   retained profiles/policy, unchanged source bytes, typed invalid-version failure
   and restoration by a new settings instance.
3. Import followed by an actual blocked-directory save failure, retained visible
   appearance and disabled policy, repaired storage, same-value retry and complete
   restoration by a new settings instance.
4. A deliberately suspended noncooperative reader: cancellation, replacement,
   stale completion, newer manual and A→B→A appearance choices, concurrent policy changes
   and owner release. None lets stale data overwrite the current choice.
5. Picker cancellation during an in-flight preview and after ready safe content.
   Swift `CancellationError`, typed `CocoaError(.userCancelled)` and the bridged
   Foundation NSError preserve lifetime state; an actual permission error clears it.

Recreating a settings model is persistence evidence, not a signed application
quit/relaunch observation. Calling completion handlers is model evidence, not a
system file-sheet interaction. Export completion checks do not demonstrate a
sandbox write grant to a destination selected by the user.

## Lead-observed signed companion interactions

The lead's subsequent live UI inspection used the canonical signed companion
build. Command-2, Command-3, Command-4, Command-6 and Command-1 selected Try Preview,
Supported Files, Settings, Help and Setup in the same `companion.main` window.
The loaded concealed JSON presentation survived a round trip through those tabs.
Command-O loaded a synthetic JSON fixture; invoking Command-O again and cancelling
the native picker retained the ready JSON presentation without an error. These
observations supplement the model cancellation checks with an actual file sheet
and provide keyboard route evidence for five tabs.

Command-5/Customization was deliberately not re-inspected because its known
inspection-service failure remained unresolved. No keyboard focus traversal,
profile/theme-sheet interaction, VoiceOver or complete Customization audit is
claimed from the five successful route shortcuts.

`./script/build_and_run.sh --check-compiler` passed for the companion and both
extensions after the fixes. Swift source compilation emitted no new diagnostics;
the existing SwiftPM native-build-system deprecation notice remains. This does
not prove Xcode resource linking, signing, installation or Finder routing. The
lead records the final Xcode and complete-suite results separately.

## Inspection-service failure and layout limits

The read-only inspection of
`SkyComputerUseService-2026-10-04-131304.ips` shows macOS 27.2 build 26B5091g,
capture time 13:13:03 +0300, `EXC_BREAKPOINT`/`SIGTRAP` on thread 1, and Swift
`_assertionFailure` followed by `Array.remove(at:)` and recursive `compactMap`
frames in the inspection-service binary. This supports an inspection-service
failure; it supplies no companion crash stack or evidence that changing the
companion's visual structure would repair that tool.

An offscreen fixture attempted to render the production Customization views with
26-point content, enlarged inherited control text, a long missing font family and
a long Unicode profile name at 760- and 980-point widths. An unordered fixture
window supplied native appearance context, but the bitmap omitted SwiftUI control
glyphs; it therefore cannot verify clipping or translated labels. The optional
probe source/script was removed rather than incorporated into a passing test.
No layout fix or effective German-language result is claimed from those images.

Remaining live checks include profile save/apply/delete and theme sheets through
the actual app, cancellation while changing tabs, successful and failed persistence
feedback, graceful relaunch, missing-font picker wording, 200% enlargement, long
translated labels, keyboard-only traversal, focus retention and VoiceOver. The
existing native renderer fixtures cover safe missing-font fallback and selected
text restyling; they do not replace these companion/Finder observations.

A targeted Nowledge thread search for the prior customization decisions was
attempted. The local service at `127.0.0.1:14242` refused the connection; repository
decisions and recorded validation remain the evidence used in this pass.

## DLS sound-bank preflight correction

The lead observed the existing registered Finder extension show a silent synthetic
MIDI summary and transport controls, then report that the sound bank could not be
loaded when Play was selected. The system bank file was present. Source inspection
found that the message originated in this app's filesystem preflight, after the
Apple DLS audio graph had already initialized successfully. That preflight combined
bundle lookup, metadata, file-open and header checks into one failure; it did not
actually load a bank into the audio unit. The Finder observation does not establish
which preflight step failed or whether the unit itself could play.

The correction removes direct lookup and reading of system sound-bank files.
After initialization, `MIDISoundBankQuery` checks the initialized DLS unit's public
read-only `kMusicDeviceProperty_SoundBankURL` property for support and pointer size,
then obtains optional loaded-bank metadata. The selected SDK explicitly documents
that property as read-only for DLS. Apple's
[AudioUnitGetProperty documentation](https://developer.apple.com/documentation/audiotoolbox/audiounitgetproperty(_:_:_:_:_:_:))
specifies that returned Core Foundation objects are owned by the caller despite
the function's Get name; the implementation consumes that retained result. Missing,
unsupported or unusable URL metadata is not an audio failure. Actual graph
initialization/start and MIDI event return codes continue to determine availability
and report failures. No custom bank, document URL, private API, filesystem grant,
entitlement or sound-bank path was introduced.

`PREV_VALIDATE_AUDIO=1 xcrun swift test --package-path Packages/PreviewCore
--build-system native --scratch-path Packages/PreviewCore/.build/validation
--filter MIDI` passed **13 targeted tests**, including three new query-boundary
tests and the actual silent native device initialize/start/silence/close smoke.
The boundaries cover unsupported/wrong-size property metadata, missing/failed
results, returned-size validation, non-file URLs, retained object transfer and a
synthetic nonexistent file URL that succeeds without any filesystem read. The
device smoke sent no notes. It is unsandboxed local lifecycle evidence; it does
not prove audible sound-bank output, successful hosted playback, pause/scrubbing
or supported-OS behavior. The lead rebuilds and rechecks the registered Finder
artifact separately after this source/test freeze.

## Final lead integration

The final signed canonical app and registered extension artifact both built
successfully. The integrated suite passed 184 Swift tests, five companion-model
and five appearance-interaction groups, three drop groups, independent SQLite
checks and the 176-case corpus. The signed-bundle checker again passed 33 language
cases across all three bundles after the MIDI rebuild.

[The rebuilt Finder follow-up](finder-matrix-2026-10-04.md#rebuilt-artifact-follow-up)
now verifies silent MIDI Play, Pause, scrubbing, resume and natural completion with
the companion stopped. This closes the observed false-preflight transport failure;
audible note quality and other OS/audio-device combinations remain open. The
original failed observation is retained to explain the correction.
