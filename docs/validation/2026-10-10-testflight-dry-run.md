# TestFlight dry run on a Mac — 2026-10-10

First run of the TestFlight pipeline (`script/build_and_run.sh --archive-unsigned`, `--archive`, `--export`, `--upload`;
[runbook](../release/testflight.md)) on a Mac. The pipeline was authored without a compiler; hosted runs 131 and 133
had only proven the OCCT helper build and found the Swift 6.3.3 optimizer crash in `PreviewHostSession.deinit`.
This record says what each mode did here. It is observation, not a release pass: nothing was uploaded, and no
TestFlight install, Finder host or store-signed CAD peer check (decision 027, D27) has happened.

## Host and toolchain

| Item | Value |
|---|---|
| Branch / commit | `claude/competitor-ux-ui-analysis-0fab0e` at `a60b2ab` (worktree) |
| macOS | 27.2 (26B5091g) |
| Xcode | 27.0 (27A266a), SDK macOS 27.0 |
| Swift | 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1), swift-driver 1.168.6 |
| Xcode account | signed in to team `Z743N6D8DS` (individual, paid) |
| Signing identities in the login keychain | one `Apple Development: Can Burak Sofyalioglu (NAUYWDYWY2)`; no `Mac App Distribution`, no `Mac Installer Distribution` |
| App Store Connect API key | none (`PREV_ASC_KEY_PATH`, `PREV_ASC_KEY_ID`, `PREV_ASC_ISSUER_ID` unset; no `.p8` on the machine; no GitHub Actions secrets or variables) |
| `Configuration/Local.xcconfig` (ignored) | `DEVELOPMENT_TEAM = Z743N6D8DS`, `PREVIEW_BASE_BUNDLE_IDENTIFIER = org.webmeister.spacepane`, `APP_GROUP_IDENTIFIER = Z743N6D8DS.org.webmeister.spacepane.shared`, `CURRENT_PROJECT_VERSION = 2` (added for this run; no build has been uploaded yet) |

## Step 1 — `--archive-unsigned` (no identities)

Outcome: **passed**, exit 0, `** ARCHIVE SUCCEEDED **`.

- The pinned OCCT helper (`.build/cad/OCCT-a016080…`, `worker-arm64/CADWorker`) was already built on this Mac, so
  `build_cad_worker.py --architecture arm64` finished in seconds; the hosted runner's 8-minute build was not repeated.
- The Release archive (`-O`, whole-module, `-default-isolation nonisolated`, Swift 6 mode) compiled every package
  target and the three app targets with Xcode 27 / Swift 6.4. **No compiler crash**: no "Stack dump" or "While running
  pass" line anywhere in the 5,966-line log. The `@inline(never)` teardown in
  `Packages/PreviewCore/Sources/PreviewCore/PreviewHostSession.swift:36` compiled; none of the other nine
  `isolated deinit` sites (ten in total under `Packages/PreviewCore/Sources`) needed the same workaround on this
  toolchain. The hosted crash remains a Swift 6.3.3 (Xcode 26.6) observation only.
- Warnings: four, all `Metadata extraction skipped, no AppIntents.framework dependency found` (expected, no App Intents).
- Archive composition printed by the script, relative to `.build/archive/Release.xcarchive/Products/Applications/SpacePane.app`:

  ```
  Contents/Helpers/CADWorker
  Contents/PlugIns/PrevPreviewExtension.appex
  Contents/PlugIns/PrevPreviewExtension.appex/Contents/Resources/PrivacyInfo.xcprivacy
  Contents/PlugIns/PrevPreviewExtension.appex/Contents/XPCServices/CADImportService.xpc
  Contents/PlugIns/PrevPreviewExtension.appex/Contents/XPCServices/CADImportService.xpc/Contents/Helpers/CADWorker
  Contents/PlugIns/PrevPreviewExtension.appex/Contents/XPCServices/CADImportService.xpc/Contents/Resources/PrivacyInfo.xcprivacy
  Contents/PlugIns/PrevThumbnailExtension.appex
  Contents/PlugIns/PrevThumbnailExtension.appex/Contents/Resources/PrivacyInfo.xcprivacy
  Contents/Resources/PrivacyInfo.xcprivacy
  org.webmeister.spacepane: 1.0.0 (1) minimum 15.0
  org.webmeister.spacepane.preview: 1.0.0 (1) minimum 15.0
  org.webmeister.spacepane.thumbnail: 1.0.0 (1) minimum 15.0
  ```

  Two extensions, the XPC service, two CADWorker copies, four privacy manifests, no `embedded.provisionprofile`
  (unsigned). Build 1 here because `CURRENT_PROJECT_VERSION` was added to `Local.xcconfig` only before step 2.

## Step 2a — `--archive` (automatic signing, development identity)

Outcome: **passed**, exit 0. `validate_signing.py` accepted the resolved identities; `check_release_archive.py`
reported:

```
Release archive checks passed for SpacePane.app 1.0.0 (2): 6 Mach-O files, 4 sandboxed bundles, 2 helpers, 4 privacy manifests.
note: CAD peer requirement accepts the team's certificate or the Mac App Store marker; only a TestFlight install proves the store-signed form (decision 027, D27)
```

Signatures in the archive (`codesign -d --verbose=2`), all `Authority=Apple Development: Can Burak Sofyalioglu (NAUYWDYWY2)`,
team `Z743N6D8DS`: `org.webmeister.spacepane`, `.preview`, `.thumbnail`, `.cad-import` (the XPC service) and
`org.webmeister.spacepane.CADWorker`. An archive is development-signed by design; distribution re-signing happens at export.

## Step 2b — `--export` (App Store Connect export)

Outcome: **failed**, exit 70, `** EXPORT FAILED **`. The export options were written as intended
(`method app-store-connect`, `destination export`, `signingStyle automatic`, `teamID Z743N6D8DS`,
`uploadSymbols true`, `manageAppVersionAndBuildNumber false`). xcodebuild reported:

```
error: exportArchive No signing certificate "Mac Installer Distribution" found
  No "Mac Installer Distribution" signing certificate matching team ID "Z743N6D8DS" with a private key was found.
error: exportArchive No profiles for 'org.webmeister.spacepane' were found
  Xcode couldn't find any Mac App Store provisioning profiles matching 'org.webmeister.spacepane'. Automatic signing is disabled and unable to generate a profile. To enable automatic signing, pass -allowProvisioningUpdates to xcodebuild.
error: exportArchive No signing certificate "Mac App Distribution" found   (×5, one per bundle)
```

Cause: the Mac held no distribution certificates and the script added `-allowProvisioningUpdates` only together with
an App Store Connect API key (`PREV_ASC_*`), which does not exist either.

## Step 2c — `--export` again after the account holder created the certificates

The account holder created an "Apple Distribution" and a "Mac Installer Distribution" certificate in Xcode
(Settings → Accounts → Manage Certificates); `security find-identity` then listed
`Apple Distribution: Can Burak Sofyalioglu (Z743N6D8DS)` and `3rd Party Mac Developer Installer: Can Burak Sofyalioglu (Z743N6D8DS)`.
The script gained `PREV_ALLOW_PROVISIONING_UPDATES=1`, which passes `-allowProvisioningUpdates` alone so the signed-in
Xcode account can generate profiles without an API key. The account holder ran
`PREV_ALLOW_PROVISIONING_UPDATES=1 ./script/build_and_run.sh --export` (the session's permission policy does not let
the agent register profiles in the developer account).

Outcome: **passed**, `** EXPORT SUCCEEDED **`. Xcode generated and embedded
`Mac Team Store Provisioning Profile: org.webmeister.spacepane` (`Contents/embedded.provisionprofile` of the app only).
The export is `.build/export/SpacePane.pkg` with `DistributionSummary.plist`, `ExportOptions.plist` and `Packaging.log`;
there is no `.app` beside it, so the script's original read-back exited early and the bundles were inspected from
`pkgutil --expand-full`. The script now expands the package itself into `.build/export-expanded` and runs the same
read-back (verified against this export).

Read-back of the distribution re-signing (`codesign --verify --strict` passed on every bundle):

| Bundle | Identifier | Authority / team |
|---|---|---|
| `SpacePane.app` | `org.webmeister.spacepane` | `Apple Distribution: Can Burak Sofyalioglu (Z743N6D8DS)` |
| `PrevPreviewExtension.appex` | `org.webmeister.spacepane.preview` | same |
| `PrevThumbnailExtension.appex` | `org.webmeister.spacepane.thumbnail` | same |
| `CADImportService.xpc` | `org.webmeister.spacepane.cad-import` | same |
| `Contents/Helpers/CADWorker` | `org.webmeister.spacepane.CADWorker` | team `Z743N6D8DS` |
| `CADImportService.xpc/Contents/Helpers/CADWorker` | `org.webmeister.spacepane.cad-import.CADWorker` | team `Z743N6D8DS` |
| `SpacePane.pkg` | — | `3rd Party Mac Developer Installer: Can Burak Sofyalioglu (Z743N6D8DS)` |

Both CADWorker copies carry exactly `com.apple.security.app-sandbox = true` and `com.apple.security.inherit = true`.
The app's entitlements in the distribution summary: `application-identifier Z743N6D8DS.org.webmeister.spacepane`,
`team-identifier Z743N6D8DS`, App Group `Z743N6D8DS.org.webmeister.spacepane.shared`; both extensions carry the same group.
`CADImportService.xpc` keeps `CADAllowedClientTeamIdentifier = Z743N6D8DS`, and its designated requirement after
re-signing is `identifier "org.webmeister.spacepane.cad-import" and anchor apple generic and certificate leaf[subject.CN] = "Apple Distribution: Can Burak Sofyalioglu (Z743N6D8DS)" and certificate 1[field.1.2.840.113635.100.6.2.1]`.
The store re-signs again at delivery, so the Mac App Store marker branch of the peer requirement (D27) is still only
testable from a TestFlight install. `CFBundleVersion` is 2 throughout.

## Step 3 — `--upload`

Not attempted: it requires the API key (the script exits 2 without `PREV_ASC_KEY_ID`), and no App Store Connect app
record for `org.webmeister.spacepane` is known to exist. Export compliance and the internal TestFlight group remain unanswered.

## What this proves and what it does not

Proven on this Mac: the project, the pinned OCCT helper and the full archive composition build in Release with Xcode 27;
the hosted-run optimizer workaround compiles and no other `isolated deinit` crashes Swift 6.4; the signed archive with the
production identities and build 2 passes the release-archive checker; the App Store Connect export re-signs every bundle
and both helpers with the team's distribution identities and keeps the sandbox, the App Group and the CAD client
requirement intact. Not proven: upload acceptance, processing, the TestFlight install, D27 under store signing, macOS 15,
and `testflight.yml` on the hosted runner.

## To unblock step 3 (owner: the account holder)

1. Create the app record for `org.webmeister.spacepane` in App Store Connect (macOS app; App Groups capability on the
   app, preview and thumbnail identifiers).
2. Generate an App Store Connect API key (App Manager), keep the `.p8` outside the repository, and set
   `PREV_ASC_KEY_PATH`, `PREV_ASC_KEY_ID`, `PREV_ASC_ISSUER_ID`.
3. Run `./script/build_and_run.sh --upload` against the existing build-2 archive, then answer export compliance
   (`ITSAppUsesNonExemptEncryption` is NO) and add the build to an internal TestFlight group. Raise
   `CURRENT_PROJECT_VERSION` before any later archive.

## Correction note — 2026-10-10 (later the same day)

Two findings after this record was written. Neither changes what the steps above observed.

1. **A TestFlight build does not carry the Mac App Store certificate marker.** The sentence above that the Mac App Store marker branch of the peer requirement "is still only testable from a TestFlight install" is wrong in its premise. Measured on this Mac on 2026-10-10 against an app delivered by TestFlight (another vendor's, not SpacePane): the leaf certificate is "TestFlight Beta Distribution" with OID `1.2.840.113635.100.6.1.25.1` and without `1.2.840.113635.100.6.1.9`. A requirement of the shape `CADPeerRequirement` emits (the `6.1.9` marker or the team organizational unit) fails `codesign --verify -R` against it; the same requirement with `certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists` added passes. A TestFlight-delivered SpacePane preview extension would therefore be refused by the CAD service. The TestFlight marker was added to the code in source as a third branch on 2026-10-10; it is unproven on a SpacePane build until a TestFlight install. Only a store-delivered build can show the `6.1.9` branch working.
2. **The owner now reports that the App Store Connect app record and an API key exist** (statement of 2026-10-10; the account was not inspected). The "To unblock step 3" list above therefore describes steps already taken, apart from running `--upload` itself. The older advice to generate the key with the App Manager role is withdrawn: use a Team key with the Admin role (an Individual key cannot use provisioning endpoints; forum reports, unverified, say App Manager keys fail cloud signing). No upload has been made.

## First upload, 2026-10-10 evening

`./script/build_and_run.sh --upload` from `/Users/cbs/Github/spacepane` (commit `e3ab9f3`, Xcode 27.0, a Team API key) uploaded 1.0.0 (1). xcodebuild printed "Upload succeeded" and `** EXPORT SUCCEEDED **`. The only warning was a missing dSYM for `CADWorker`. Apple's processing result, TestFlight availability and every installed-build observation are still to be recorded here.

