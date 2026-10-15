# App Store submission worksheet

Updated 2026-10-13 for SpacePane (first written 2026-10-04, revised 2026-10-07, 2026-10-10 and 2026-10-12; the review notes, sample archive and prepared replies were completed on 2026-10-12 and changed on 2026-10-13 when STEP and IGES were cut from 1.0, [decision 028](../decisions/028-no-cad-in-version-1.md)). Use the [detailed publishing guide](app-store-publishing-guide.md) for the full workflow and [historical research](../initial/08-app-store-publishing-research.md) for problems and documented outcomes. Release gates remain in [PLAN M6](../../PLAN.md#m6--prepare-for-the-app-store-later).

The owner has created the App ID, name and pricing plans, and reports (2026-10-10) that the App Store Connect app record and API key exist and that the price, roughly USD 9.99 with local pricing, is set in App Store Connect. Preserve that setup. Active contact and support email: **info@spacepane.com**. This worksheet is a preparation aid, not a claim of submission readiness or authorization to upload/release.

The product-page text itself (name, subtitle, keywords, promotional text, description, screenshot plan) is in [app-store-listing.md](app-store-listing.md). It was entered in App Store Connect as a draft for English (U.S.) and English (U.K.) on 2026-10-10, with the support, marketing and privacy URLs from the table below; that file records what the record holds and what is still empty.

## Before archiving

- Archive with `PREV_INCLUDE_CAD = NO` (the 1.0 setting, [decision 028](../decisions/028-no-cad-in-version-1.md)): the submission build is build 3 and has no CAD helper, CAD service or OCCT notices folder. Build 1.0.0 (2) contains them, was uploaded for the owner's internal TestFlight testing only and must not be submitted.
- Check the effective signing configuration against the existing app record. Production identities recorded in PLAN must replace the committed compile-only placeholders through the existing local configuration.
- Increment `CURRENT_PROJECT_VERSION` for each new/replacement upload; keep the app and embedded bundle versions consistent.
- Preserve prior candidate archives: the following command replaces `.build/archive/Release.xcarchive`.

```sh
./script/build_and_run.sh --archive
```

The script produces the signed arm64 Release archive for Apple silicon into `.build/archive/Release.xcarchive` and runs `script/check_release_archive.py`. The script checks:

- store keys and the compiled icon
- quarantine attributes and architectures
- nested signatures and the exact entitlement set of each role (app and the two extensions; with `PREV_INCLUDE_CAD = YES` also the CAD service and both CADWorker copies), one App Group array across the app and the extensions, a hardened runtime everywhere, signing identifiers equal to bundle identifiers and one team identifier, no `cs.*`, temporary-exception or network keys
- nested Info.plists free of `$(` and prototype identities, versions equal to the app's, extension identifiers prefixed by the app's, unique Quick Look content types
- the CAD setting: with `PREV_INCLUDE_CAD = NO` (1.0) the archive must hold no `CADWorker`, no `CADImportService.xpc` and no `OCCT-Notices` folder; with YES, the CAD helper identifiers and the peer requirement values (the service's allowed-client identifier and team equal the preview extension's, and the preview's service identifier equals the service's)
- a privacy manifest (`PrivacyInfo.xcprivacy`) in the app, both extensions and, when present, the CAD service, with Apple's reason codes for the file-timestamp, system-uptime and user-defaults categories the code uses
- bundled notices and dSYMs

These checks do not establish Organizer validation, App Store processing or Finder behavior. The checker's own tests run on Linux as part of the static gate (`python3 script/test_check_release_archive.py`); the first run on a real archive may still find profile-injected entitlement keys or a manifest placement the synthetic trees did not model, so read its notes rather than only its exit code.

The next paragraph and the helper command below concern the CAD service, which 1.0 does not ship ([decision 028](../decisions/028-no-cad-in-version-1.md)); they are kept for the version that brings CAD back.

Corrected 2026-10-10: an earlier version of this section said the App Store form of the CAD peer requirement (the Mac App Store certificate-marker branch) would be proven by a TestFlight install. It will not. A TestFlight-delivered app is signed with the "TestFlight Beta Distribution" certificate, whose leaf carries OID `1.2.840.113635.100.6.1.25.1` and not the Mac App Store marker `1.2.840.113635.100.6.1.9`. Measured on 2026-10-10 on one Mac against another vendor's TestFlight app: a requirement of the shape the CAD service emits (the `6.1.9` marker or the team organizational unit) fails `codesign --verify -R`, and adding the `6.1.25.1` branch makes it pass. The TestFlight branch was added to `CADPeerRequirement` in source on 2026-10-10 and is unit-tested (no Xcode build with it has been made yet); it is unproven until a TestFlight install. The Mac App Store marker branch can only be proven on a store-delivered build. After the first TestFlight build, run `codesign -d -r- <installed PrevPreviewExtension.appex>`, note which marker its leaf certificate carries, and preview a STEP file (decision 027, D27).

Then either open the archive in Xcode Organizer, choose **Validate App**, and distribute to App Store
Connect, or run `./script/build_and_run.sh --export` (inspect) and `--upload` (TestFlight); the hosted
pipeline in [the TestFlight runbook](testflight.md) does the same with an App Store Connect API key.
Distribution re-signs the app. After export, confirm the app and both extensions kept their identities. If a build with CAD is ever exported (`PREV_INCLUDE_CAD = YES`), also confirm the helper identities survived the re-signing (`--export` prints them) and inspect both workers and the service, not just the companion worker:

```sh
codesign -d --verbose=2 --entitlements - SpacePane.app/Contents/Helpers/CADWorker
```

See the guide for the separate TestFlight and store-delivered XPC client test, which applies only to a build with CAD.

## Review sample files

Build the attachment from the repository. The output is under `dist/`, which git ignores.

```sh
python3 script/build_review_samples.py            # dist/review-samples/
python3 script/build_review_samples.py --check    # also checks the Notes below against the archive
```

It writes `SpacePane-Review-Samples/` and `SpacePane-Review-Samples.zip` (about 200 KB, 33 files, the same bytes on every run). The files come from `script/generate_host_fixtures.py`, `script/generate_store_demo_files.py` and one Swift sample in `script/generate_appearance_samples.py`, imported rather than copied; no generator makes a Python file or a `Makefile`, so the builder writes those two plain-text files itself. There is one sample for each format family the store description names, a `README.txt` that says what to look for in each, and a fake secret in `01-settings.json`. Every value is invented; the supplied private CAD model is never included. The README rows are what to look for, not Finder results: observe the set on the candidate store build before submitting (review readiness plan, Phases 3 and 4) and correct any row that Finder contradicts. `--check` fails if a file named in the Notes or the README is not in the archive, if a sample is not described, if the Notes pass 4,000 bytes or keep a bracketed placeholder, or if the README stops being plain ASCII under 80 columns and 60 lines.

## Notes for App Review

Paste the quoted block into the Notes field of App Review Information, attach `SpacePane-Review-Samples.zip`, and enter the review contact (name, phone with +country code) in App Store Connect only; none of it belongs in this repository. The block has no placeholder and is 2,562 bytes against Apple's limit of 4,000; `python3 script/build_review_samples.py --check` recounts it. What it rests on, as of 2026-10-12:

| Statement | Basis | Still to observe |
| --- | --- | --- |
| Version 1.1.0, build 4 (1.0.0 build 3 was the first submission) | Build 1 was uploaded on 2026-10-10 and will not be submitted. Build 2 was uploaded on 2026-10-12 with CAD in it; it is for the owner's internal TestFlight testing only and must not be submitted ([decision 028](../decisions/028-no-cad-in-version-1.md)). The submission build is build 3, built without CAD. | `CURRENT_PROJECT_VERSION = 4` and `PREV_INCLUDE_CAD = NO` must be in the archive that is uploaded and selected for the version. |
| Tested on macOS 27.2, Apple silicon | The host matrix and the signed-host records. | Repeat on the store-signed build (plan Phases 3 and 4). |
| Tested on macOS 15.2 | The owner's report (2026-10-12) of a run in a macOS 15.2 virtual machine, taken as given on the owner's instruction. No session observed it and it is not in the host matrix. | Record the run in `docs/validation/host-matrix.json`. |
| Enabling the extensions | Step 1 relies on the in-app "Open System Settings" button first and gives the macOS 15 path (the companion's own setup text gives the same path) as the manual route. No path for macOS 26 or 27 is recorded in `docs/validation/` or `CHANGELOGS.md` (searched 2026-10-12), and the button, which opens the Login Items & Extensions pane (`GeneralView.swift`), has never been observed. | The exact System Settings route on 27.2, word for word. Add it to step 1 if the button lands elsewhere. |
| Sample files and their behavior | Names come from the builder. The archive holds no STEP or IGES file, and the notes name one mesh sample, `28-binary.stl`. | The README rows, on the store build; the STL row in particular, since no mesh format has a Finder observation yet. |
| No CAD in the product | Decision 028: the build setting `PREV_INCLUDE_CAD` is NO for 1.0, so the notes make no claim about STEP, IGES, Open CASCADE or a source offer. | `script/check_release_archive.py` on the archive of build 3; it enforces the setting. |

STEP and IGES do not ship in 1.0 ([decision 028](../decisions/028-no-cad-in-version-1.md), decided 2026-10-13, which settled R-2 of the review readiness plan). The 3D paragraph and the two CAD file names were taken out of the block, and the two CAD samples out of `SAMPLES` in the builder; `--check` fails if the notes and the archive disagree. The notes make no claim about Open CASCADE or a source offer, because the build has none. If CAD returns, restore the paragraph and the two samples from git history (the commit before 2026-10-13) after the steps in decision 028, "Bringing CAD back".

> SpacePane 1.1.0 (build 4) adds Quick Look previews and thumbnails to Finder. It is a small companion app plus two Quick Look extensions, SpacePane Preview and SpacePane Thumbnails. Everything runs on the Mac: no account, no sign-in, no network access, no in-app purchase. It needs Apple silicon and macOS 15 or later.
>
> Tested on macOS 27.2 and on macOS 15.2, on Apple silicon.
>
> To see it work (about two minutes):
> 1. Open SpacePane. On the General page, the row "Turn on the extensions" has an "Open System Settings" button. Use it to open System Settings, then switch on SpacePane Preview and SpacePane Thumbnails among the Quick Look extensions. By hand on macOS 15: System Settings > General > Login Items & Extensions > Quick Look.
> 2. Unzip the attached SpacePane-Review-Samples.zip. Its README.txt lists every file and what to look for.
> 3. In Finder select 01-settings.json and press Space. It opens as a JSON outline with a Source view. The file holds a deliberately fake token and password; SpacePane conceals them and the file is unchanged.
> 4. Also try 07-stations.sqlite (database tables), 08-release.zip (archive listing, nothing extracted), 15-analysis.ipynb (notebook, never run), 16-document.md (Markdown), 28-binary.stl (a 3D model you can turn) and Makefile (a file with no extension).
>
> New in 1.1.0: previews say what a file would do if it were run, installed or trusted. 32-model.gguf shows an AI model's summary read from its header (the model is never loaded), 33-extension.vsix an editor extension's activation and permissions, and 34-package.whl a Python package's contents and the code it runs at start (nothing is installed). Findings are statements about the file's text; SpacePane never runs it.
>
> macOS decides which installed app previews each file type. If another app already previews a type, Quick Look may use it. An info symbol in the preview shows when SpacePane made it.
>
> The preview extension declares public.data exactly once so that text files with no extension (such as Makefile) can be previewed, and only for previews, never thumbnails. Quick Look matches that type exactly, so PDFs, images and files with an extension are not routed to it, and a binary file with no extension shows a short explanation instead of its bytes.
>
> The com.quicklookpro.* identifiers in the extension's supported types are not declared by SpacePane, which neither imports nor exports them. They name types that another developer's Quick Look app may have declared on a user's Mac for the same file suffixes, so files tagged that way still preview. SpacePane claims no ownership of them, and a Mac without that app skips them.
>
> Developer Mode (off by default, on the General page) only reveals a Try Preview page and an Open File command for checking a file inside the companion. It changes nothing in Finder.
>
> Contact details are entered in App Store Connect. Email: info@spacepane.com. Support: https://spacepane.com/support. Privacy: https://spacepane.com/privacy.

## If App Review objects

Replies to paste into App Store Connect or the Resolution Center. Each states facts and promises nothing about which app Finder uses for a file type.

**Guideline 4.2 (minimum functionality): "the app is only a settings window".** SpacePane is not a settings window. Its purpose is two Quick Look extensions inside the app bundle, SpacePane Preview and SpacePane Thumbnails, which macOS runs when a person presses Space on a file in Finder. They show JSON, YAML, XML and similar files as outlines, SQLite databases as tables, archives and folders as listings without extracting anything, notebooks without running them, and STL, OBJ, PLY and 3MF models you can turn, and they conceal likely secrets. Quick Look extensions have no interface of their own, so the companion app turns them on, switches each file type on or off and sets the appearance; it also previews a file directly (General > Developer Mode > Try Preview). The attached samples and README show each preview in about two minutes, and we can send a short screen recording on request.

**Guideline 2.1: "we could not find the app's features".** The features appear in Finder, not in the SpacePane window. After SpacePane Preview and SpacePane Thumbnails are switched on (General > "Open System Settings"; on macOS 15, System Settings > General > Login Items & Extensions > Quick Look), select 01-settings.json, 07-stations.sqlite or 08-release.zip from the attached archive in Finder and press Space. macOS decides which installed app previews a type, and SpacePane cannot override that; an info symbol in the preview shows when SpacePane made it. If a file shows another app's preview, turn on Developer Mode (General page) and open the same file in the Try Preview page, which uses the same preview engine inside SpacePane. The Theme page also previews built-in samples inside SpacePane. We are glad to answer any step that does not work as written.

**Guideline 5.2.5 / 2.3.7: the app name.** "SpacePane for Quick Look" uses "Quick Look" only to name the macOS feature the app works with, and "for" shows that SpacePane is a separate product; the description states that SpacePane is not affiliated with Apple. If App Review still prefers a name without the phrase, we will change it to "SpacePane: File Previews" with the subtitle "JSON, YAML, Markdown, SQLite" (fallback B in docs/release/app-store-listing.md), keeping "quicklook" only in the keyword field. Please tell us which part of the metadata to change and we will update it at once.

**The public.data declaration.** The preview extension declares public.data exactly once, so that text files with no extension (Makefile, Dockerfile, zprofile) can be previewed. It is for previews only and is never used for thumbnails; Quick Look matches the type exactly, so PDFs, images and files with an extension are not routed to it; a binary file with no extension shows a short explanation, not its contents; and the app does not declare public.item or public.content. If App Review requires it, we will remove the declaration and the extension-free file format in the next build. Every other file type is unaffected, and files without an extension return to whatever macOS shows for them.

## App Store Connect answer worksheet

| Field | Entry or determination | Required verification |
| --- | --- | --- |
| Main bundle ID | Existing record; PLAN records `org.webmeister.spacepane` | Match the effective final archive and Apple account. |
| Categories | Utilities; optional Developer Tools secondary | Match actual positioning and bundle category. |
| Privacy policy URL | https://spacepane.com/privacy | Public, current and consistent with the build. The older `.html` forms redirect to this address. |
| Support URL | https://spacepane.com/support | Published contact must be info@spacepane.com; test delivery. The older `.html` form redirects. |
| Contact email | info@spacepane.com | Confirm the mailbox is monitored and replies can be sent. |
| Marketing URL | https://spacepane.com | Match release scope and compatibility. |
| App Privacy | Data Not Collected is a candidate answer | Audit actual app/dependencies/support flows; Save and Publish the accurate answers. |
| Export compliance | Existing `ITSAppUsesNonExemptEncryption = NO` | Reassess cryptography/dependencies; record the classification basis. |
| Age rating | Answer the 2026 questionnaire in full: content descriptions, in-app controls, capabilities and social media. Expected answers are "None" or "No" throughout, for an expected rating of 4+. | Answers are required for new submissions since September 2026. Read each question; SpacePane shows only the user's own local files, with no account, messaging, user-generated content or web browsing, but the calculated rating is Apple's. |
| Content Rights | Assess actual included/accessed content | Confirm licenses for bundled samples, assets and review/screenshot material. |
| Description: open-source line | Not applicable in 1.0 (no Open CASCADE in the product; [decision 028](../decisions/028-no-cad-in-version-1.md)). | The description holds no such paragraph. If CAD returns, the earlier text is in [decision 028](../decisions/028-no-cad-in-version-1.md), "Bringing CAD back". Other places that point at the source offer (the website's open-source page, the app's acknowledgements) are outside this file. |
| Copyright | Approved value from Branding.xcconfig | Match legal rights holder. |
| Version/build | 1.0.0, build 3 | Build 1 (2026-10-10) will not be submitted. Build 2 (uploaded 2026-10-12, with CAD) is for internal TestFlight testing only and must not be submitted. The submission build is build 3, without CAD. Increment the build for every replacement upload. |
| Compatibility | macOS 15+, Apple silicon only (`ARCHS = arm64`) | Run the candidate on the advertised OS range. The owner reports (2026-10-12) that it works in a macOS 15.2 virtual machine; no run is recorded in the host matrix yet. |
| Pricing/availability | Set in App Store Connect (owner, 2026-10-10: roughly USD 9.99, local pricing adopted) | App Store Connect holds the effective prices; verify agreements, territories and compliance. |
| Review login | Not required if accountless design is unchanged | Do not invent a demo account. |
| Review contact | Reachable person, email and phone with +country code | Confirm monitored contact details separately from the public support URL. |
| Release option | Manual recommended for first release | Approval and release are separate actions. |

On October 7, the legacy `.html` support/privacy URLs redirected to the canonical pages and returned HTTP 200. The owner's active address is `info@spacepane.com`, and the review-readiness audit of 2026-10-12 found it on every live page. Live page availability does not prove mailbox operation (Phase 0 item 3 of the review readiness plan sends the test message) or every translated page.

## Submission reminder

Select the processed tested build, resolve compliance, save metadata, publish privacy answers, attach the reviewed packet, choose **Add for Review**, then **Submit for Review**. Keep each validation result with the exact version/build. Do not submit until the guide's release gates and the later publishing authorization are complete.
