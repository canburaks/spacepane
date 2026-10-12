# Signed build checkpoint — 2026-10-09

Source: `67da062885c4b061f02e87ee883b070e8570a0f7`. This record establishes bundle build/signature/launch and resource lookup only. Actual Finder observations remain separately attributed to [the October 8 signed-host record](quality-program-signed-host-2026-10-08.md); its `3a97e4f` artifact predates Q55 and the October 9 additions.

## Artifact and environment

- Mac17,8 / Apple M5 Pro, 48 GiB RAM; arm64 macOS 27.2 (26B5091g), Xcode 27.0 (27A266a); macOS 15 deployment baseline.
- Debug artifact: `.build/xcode/Build/Products/Debug/SpacePane.app`.
- `./script/build_and_run.sh --verify` builds the app, both extensions and embedded CAD service, verifies signatures and confirms the companion process after launch. The unchanged Xcode graph resolves PreviewFileAccess transitively through PreviewCore.
- Manifest: `.build/quality-work/oct09-signed-bundle-manifest.json`, 177 files; SHA-256 `84344305e0ceee6986585c6a162134eec3595067dc7d0b9e7f4807b1008852e4`.
- Local build/signature evidence: `.build/quality-work/oct09-signed-verify.log` and `oct09-signature.txt`.

## Resource checks and limits

`script/check_bundle_localizations.py --app .build/xcode/Build/Products/Debug/SpacePane.app` passes 33 explicit language/fallback cases across all three signed app/extension bundle contexts, with 1,082 keys each and resources unchanged. Log: `.build/quality-work/oct09-bundle-localizations.log`.

This is not a macOS 15 runtime test, Finder routing/thumbnail observation, effective cross-process language test, VoiceOver check, or provider no-download proof. Q55 compact controls, Q72 quote bars and Q153 guarded reads are included in this artifact but have no new signed Finder observations in this record. Translation review, image footprint, delivered-build CAD signing, OCCT licensing and publication gates remain open.


## Later process-bootstrap artifact

Clean source `ed97406` subsequently builds, passes app/extension signature verification and launches via `--verify`. This artifact includes guarded random-access/classification, whole-code metadata and both extension process entrypoints with direct PreviewFileAccess links. Log: `.build/quality-work/q153-bootstrap-signed.log`. Manifest: `.build/quality-work/q153-bootstrap-bundle-manifest.json`, 177 files, SHA-256 `c4465e23ac01289870ceac15146fe6cc497717de20f61665240ec065c49a9cbf`. The artifact path is the same build-products path above.

All 33 explicit language/fallback cases also pass across the three signed bundle contexts with 1,082 keys each and resources unchanged (`q153-bootstrap-bundle-localizations.log`). The later code-copy service is not included in this artifact. Actual Finder/provider/minimum-OS/VoiceOver observations remain open.
