# Sparkle 2 direct-distribution updater dependency audit

Recorded 2026-11-10. This record documents the adoption, build integration, sandbox
isolation, and licensing audit of Sparkle 2 for direct-distribution builds of the
companion application (`PREV_INCLUDE_SPARKLE = YES` in `Configuration/Base.xcconfig`).

## Identity and reproduction

- Official Sparkle `2.10.1` release in the
  [official repository](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1).
- Pinned distribution archive:
  `https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz`,
  SHA-256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`.
- `python3 script/build_sparkle.py --architecture arm64` verifies the SHA-256 digest
  of the archive in `.build/sparkle/`, extracts `Sparkle.framework` and its host
  tools (`generate_keys`, `generate_appcast`, `sign_update`, `BinaryDelta`) under
  `.build/sparkle/dist/`, and stages a stripped runtime framework at
  `.build/sparkle/runtime-arm64/Sparkle.framework` with:
  1. C/Objective-C headers and Modules removed from the embedded bundle.
  2. Non-shipped `.lproj` directories pruned from `Sparkle.framework` and
     `Updater.app` so only `Base.lproj` and the shipped languages in
     `tools/localization/languages.json` remain.
  3. All five Mach-O executables (`Sparkle`, `Autoupdate`,
     `Updater.app/Contents/MacOS/Updater`,
     `XPCServices/Downloader.xpc/Contents/MacOS/Downloader`, and
     `XPCServices/Installer.xpc/Contents/MacOS/Installer`) thinned to the target
     architecture (`arm64`) via `lipo`.
  4. The upstream `LICENSE` copied into `Sparkle.framework/Versions/B/Resources/LICENSE`.

## Extension and sandbox isolation

- Quick Look extensions (`PrevPreviewExtension` and `PrevThumbnailExtension`) never
  link, embed, or load `Sparkle.framework`. Preview and thumbnail rendering remain
  strictly local, offline, and free of network entitlements.
- The companion app (`SpacePane.app`) remains App-Sandboxed
  (`com.apple.security.app-sandbox = true`) and retains **no**
  `com.apple.security.network.client` entitlement.
- Update feed and archive downloads are isolated inside Sparkle's embedded XPC
  service `Sparkle.framework/Versions/B/XPCServices/Downloader.xpc`
  (`SUEnableDownloaderService = true` in `Configuration/App-Info.plist`), which is
  signed with `Configuration/SparkleDownloader.entitlements`
  (`com.apple.security.app-sandbox = true`,
  `com.apple.security.network.client = true`).
- Update installation is coordinated through
  `Sparkle.framework/Versions/B/XPCServices/Installer.xpc`
  (`SUEnableInstallerLauncherService = true`) and the companion's Mach-lookup
  temporary exception (`$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and
  `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` in `Configuration/app-sparkle.entitlements`).
- Every update archive is verified by Sparkle against both Apple Developer ID code
  signing (`Developer ID Application: Can Burak Sofyalioglu (Z743N6D8DS)`) and the
  pinned Ed25519 public key (`SUPublicEDKey` in `Configuration/Branding.xcconfig`)
  before installation.

## Licensing and retained notices

- Sparkle 2.10.1 is licensed under the MIT License, with embedded components under
  BSD-2-Clause (`bsdiff`/`bspatch` by Colin Percival; `SUSignatureVerifier.m` by
  Mark Hamlin), MIT (`sais-lite` by Yuta Mori), and the zlib-style permissive notice
  (`ed25519` by Orson Peters).
- The unmodified upstream license text is retained in `ThirdPartyNotices/Sparkle/LICENSE`
  and embedded inside `Sparkle.framework/Versions/B/Resources/LICENSE`.
