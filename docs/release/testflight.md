# TestFlight runbook

Recorded 2026-10-10 for SpacePane 1.0. How a build reaches TestFlight, what each step proves, and what only
you can supply. The pipeline is `.github/workflows/testflight.yml` over `script/build_and_run.sh`; the same
modes run on a Mac. Decision 027 D27 makes a TestFlight round a release gate: it is the only way to test the
store-signed CAD peer requirement and the cleanest way to reach macOS 15.

## What the pipeline does

| Level | Needs | Produces | Proves |
|---|---|---|---|
| `dry-run` | nothing | an unsigned Release archive on the hosted runner, its composition listed in the log | the project, the pinned OCCT CAD helper and the archive composition build with the release identities |
| `signed` | the certificate and API-key secrets below | a signed archive that passes `script/check_release_archive.py`, then an App Store Connect export with the helper identities read back | signing, entitlements, App Group, privacy manifests and helper identity under distribution re-signing |
| `upload` | the same secrets | the export uploaded; App Store Connect processes it | that the build is accepted for TestFlight processing |

Each run writes `Configuration/Local.xcconfig` from repository variables (defaults: the identities PLAN.md M6
adopted on 2026-10-06) and sets `CURRENT_PROJECT_VERSION` to the run number unless `build_number` is given.
App Store Connect rejects a build number it has already seen, so every upload needs a higher one.

## One-time setup you own

Update 2026-10-10 (owner statement, not checked against the account): the App Store Connect app record and an API key now exist, so steps 1 and 3 below are done in App Store Connect; the key's type and role are unknown and should be checked against step 3. Steps 2 and 4 are for the hosted pipeline only; the local route needs the certificates in the login keychain and the three `PREV_ASC_*` variables.

1. **App record.** In App Store Connect, create the macOS app with bundle ID `org.webmeister.spacepane`
   (register the identifier and the App Group `Z743N6D8DS.org.webmeister.spacepane.shared` in the developer
   portal first; enable the App Groups capability on the app, the preview and the thumbnail identifiers). The
   extensions' identifiers (`.preview`, `.thumbnail`) and the service (`.cad-import`) are registered by
   automatic signing when the first signed archive runs.
2. **Certificates.** In Xcode (Settings → Accounts → Manage Certificates) or the developer portal, create an
   "Apple Distribution" certificate and a "Mac Installer Distribution" certificate on a Mac you control. In
   Keychain Access, select both certificates with their private keys and export one `.p12` with a password.
3. **API key.** App Store Connect → Users and Access → Integrations → App Store Connect API: generate a **Team**
   key with the **Admin** role. Note the Key ID and the Issuer ID and download the `.p8` once. Corrected
   2026-10-10: an Individual key cannot use the provisioning endpoints, and forum reports (unverified) say a
   key with the App Manager role fails cloud signing, so the earlier App Manager recommendation is withdrawn.
   The role needed beyond that is not verified; if signing fails with a Team Admin key, record the message.
4. **Repository secrets** (GitHub → Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `PREV_SIGNING_P12_BASE64` | `base64 -i distribution.p12 \| pbcopy` |
   | `PREV_SIGNING_P12_PASSWORD` | the `.p12` password |
   | `PREV_ASC_KEY_ID` | the key ID |
   | `PREV_ASC_ISSUER_ID` | the issuer ID |
   | `PREV_ASC_PRIVATE_KEY` | the `.p8` file contents |

   Optional variables, only if the identities differ from the defaults: `PREV_DEVELOPMENT_TEAM`,
   `PREV_BUNDLE_IDENTIFIER`, `PREV_APP_GROUP_IDENTIFIER`.
5. **Export compliance and test information** are answered once in App Store Connect:
   `ITSAppUsesNonExemptEncryption` is `NO` in the app's Info.plist, so no compliance document is needed; the
   beta app description and the review notes come from [the submission notes](app-store-submission.md).

## Running it

Actions → testflight → Run workflow on `main` (or the release branch):

1. `dry-run` first. It needs no secret and takes the longest the first time (the OCCT build is cached
   afterwards). Read the archive composition in the log: the two extensions, the XPC service, the two
   CADWorker copies, four privacy manifests, and the version line of each bundle.
2. `signed` after the secrets exist. The release-archive checker runs on the archive; the export step prints
   each bundle's identifier, team and authority and the CADWorker entitlements after re-signing. Compare them
   with the checker's expectations before the first upload.
3. `upload`. When App Store Connect finishes processing, add the build to an internal group in TestFlight.
   External groups need Beta App Review.

On a Mac the same steps are `./script/build_and_run.sh --archive`, `--export` and `--upload`, with
`Configuration/Local.xcconfig` holding the identities and, for a machine without a signed-in Xcode, the
`PREV_ASC_*` variables pointing at the API key.

## Local upload from the Mac

The same modes run on a Mac that holds the Apple Distribution and Mac installer certificates and the app's
distribution profile. Set the identities in `Configuration/Local.xcconfig` (ignored by git), raise
`CURRENT_PROJECT_VERSION` above any build App Store Connect has seen (build 2 was used by the 2026-10-10 dry
run), and give the shell the API key:

```sh
export PREV_ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8"   # the .p8 file; example path
export PREV_ASC_KEY_ID="..."       # the key ID
export PREV_ASC_ISSUER_ID="..."    # the issuer ID

./script/build_and_run.sh --check
./script/build_and_run.sh --archive
./script/build_and_run.sh --export
./script/build_and_run.sh --upload
```

`--check` runs the static gate and the project, manifest and localization checks. `--archive` builds the signed
Release archive for Apple silicon and runs the archive checker. `--export` writes the distribution package to
`.build/export` and prints each bundle's identity after re-signing; read it before uploading. `--upload` exports
again with the upload destination, so App Store Connect receives the build. The script requires all three
variables together and passes the key to `xcodebuild` with `-allowProvisioningUpdates`; `--upload` exits with
status 2 if they are missing. On a Mac whose Xcode is signed in to the team, `PREV_ALLOW_PROVISIONING_UPDATES=1`
lets `--archive` and `--export` fetch profiles without the key, but it does not satisfy `--upload`.

Keep the `.p8` file in a private directory (`chmod 700` on the directory, `chmod 600` on the file), never
inside the repository; on the owner's Mac the key file now lives in `~/.appstoreconnect/private_keys/`
(directory mode 700, file mode 600), and never put the key ID or issuer ID in a tracked file. The upload is outward-facing;
run it only when you mean to send a build to Apple.

## What the TestFlight round has to record

The round is observation, not a pass by construction. Record it in a dated `docs/validation/<date>-host-matrix.md`
per the Mac validation protocol in the platform review, at least:

- Install from TestFlight on the current macOS and on macOS 15 (the deployment target, never run so far).
- Finder: panel, pane and Gallery previews for the host matrix formats; thumbnails; the Contents rail,
  alert bars and code cards; VoiceOver on the preview and the companion.
- The CAD path under store signing (D27): turn STEP on, preview a model, record `pgrep -lf CADImportService`
  and the worker's spawn and exit. Corrected 2026-10-10: a TestFlight build is signed with the "TestFlight Beta
  Distribution" certificate (leaf OID `1.2.840.113635.100.6.1.25.1`), not the Mac App Store certificate
  (`1.2.840.113635.100.6.1.9`), so the Mac App Store branch of the peer requirement is not what a TestFlight
  install exercises. Measured on 2026-10-10 against another vendor's TestFlight app, a requirement of the
  old two-branch shape fails `codesign --verify -R`. The TestFlight marker has been in source since 2026-10-10:
  `CADPeerRequirement` now accepts the Mac App Store marker, the TestFlight marker or the team organizational
  unit, and its unit tests pass, but no Xcode build with the change has been made yet. A build made after that
  change should be accepted on a TestFlight install; a build made before it would be refused by the CAD service.
  Record `codesign -d -r-` of the installed preview extension and which marker its leaf certificate carries
  (`6.1.25.1` expected on TestFlight, `6.1.9` on the Mac App Store). The TestFlight form is unproven until an
  installed TestFlight build is observed; the Mac App Store form is proven only by a store-delivered build.
- The two `withKnownIssue` expectations (Q-72 RTL table columns, Q-74 zero-host container tracking).
- Memory of an image-heavy document and the first-visible timing of the dataless cases.

## Still open before external testers

- Q-171: the OCCT source-offer obligation. Internal testing stays inside the team; before an external group
  or the store, either publish the offer and the packaged sources or apply the approved CAD-exclusion fallback.
- Q-172: native-speaker review of the 13 translations, localized store copy, the live support and privacy
  pages and the support mailbox.
- Screenshots after the interface settles (Q-181).
