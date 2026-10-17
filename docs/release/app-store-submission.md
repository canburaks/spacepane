# App Store submission worksheet

Updated 2026-10-17 for SpacePane (first written 2026-10-04, revised 2026-10-07, 2026-10-10, 2026-10-12 and 2026-10-13; the review notes, sample archive and prepared replies were completed on 2026-10-12, changed on 2026-10-13 when STEP and IGES were cut from 1.0, [decision 028](../decisions/028-no-cad-in-version-1.md), and corrected on 2026-10-17 after [the rejection-risk review](../reviews/2026-10-17-app-store-rejection-risk.md), findings 1, 3, 11 and 14). The version in review is 1.1.0 (build 5), submitted on 2026-10-17; build 6, prepared the same day and not uploaded, replaces it and is the build the block below names; the dated status table is in [version-1.1.0.md](version-1.1.0.md#submission-status). The notes and replies below are the corrected text; what App Store Connect holds is the block as it stood on 2026-10-15, until the owner re-pastes it. Use the [detailed publishing guide](app-store-publishing-guide.md) for the full workflow and [historical research](../initial/08-app-store-publishing-research.md) for problems and documented outcomes. Release gates remain in [PLAN M6](../../PLAN.md#m6--prepare-for-the-app-store-later).

The owner has created the App ID, name and pricing plans, and reports (2026-10-10) that the App Store Connect app record and API key exist and that the price, roughly USD 9.99 with local pricing, is set in App Store Connect. Preserve that setup. Active contact and support email: **info@spacepane.com**. This worksheet is a preparation aid, not a claim of submission readiness or authorization to upload/release.

The product-page text itself (name, subtitle, keywords, promotional text, description, screenshot plan) is in [app-store-listing.md](app-store-listing.md). It was entered in App Store Connect as a draft for English (U.S.) and English (U.K.) on 2026-10-10, with the support, marketing and privacy URLs from the table below; that file records what the record holds and what is still empty.

## Before archiving

- Archive with `PREV_INCLUDE_CAD = NO` ([decision 028](../decisions/028-no-cad-in-version-1.md)): the build in review is 1.1.0 (5), which has no CAD helper, CAD service or OCCT notices folder and, since 2026-10-17, no linked CAD module (Guideline 2.5.19). Build 1.0.0 (2) contains them, was uploaded for the owner's internal TestFlight testing only and was never submitted. The earlier submissions, 1.0.0 (3) and 1.1.0 (4), were removed from review.
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

It writes `SpacePane-Review-Samples/` and `SpacePane-Review-Samples.zip` (about 200 KB, 36 files since 2026-10-15, the same bytes on every run). The files come from `script/generate_host_fixtures.py`, `script/generate_store_demo_files.py` and one Swift sample in `script/generate_appearance_samples.py`, imported rather than copied; no generator makes a Python file or a `Makefile`, so the builder writes those two plain-text files itself. There is one sample for each format family the store description names, a `README.txt` that says what to look for in each, and a fake secret in `01-settings.json`. Every value is invented; the supplied private CAD model is never included. The README rows are what to look for, not Finder results: observe the set on the candidate store build before submitting (review readiness plan, Phases 3 and 4) and correct any row that Finder contradicts. `--check` fails if a file named in the Notes or the README is not in the archive, if a sample is not described, if the Notes pass 4,000 bytes or keep a bracketed placeholder, or if the README stops being plain ASCII under 80 columns and 60 lines.

## Notes for App Review

Paste the quoted block into the Notes field of App Review Information, attach `SpacePane-Review-Samples.zip`, and enter the review contact (name, phone with +country code) in App Store Connect only; none of it belongs in this repository. The block has no placeholder and is 2,754 bytes against Apple's limit of 4,000 (3,165 before build 6 dropped the `com.quicklookpro.*` paragraph); `python3 script/build_review_samples.py --check` recounts it. The block pasted on 2026-10-17 was the version of 2026-10-15 (2,982 bytes by the same count; the figure 2,562 recorded here until 2026-10-17 predated the 1.1.0 paragraph); the corrections of 2026-10-17 (step 1 names the banner, step 4 names the 3MF model, no thumbnail or macOS 15 claim, the `com.quicklookpro.*` wording) reach App Store Connect only when the owner re-pastes the block, which needs the version out of review; the block names build 6, so it is pasted together with the replacement build ([version-1.1.0.md, "Replacing the submission"](version-1.1.0.md#replacing-the-submission)). What the block rests on, as of 2026-10-17:

| Statement | Basis | Still to observe |
| --- | --- | --- |
| Version 1.1.0, build 5 | Build 5 was uploaded on 2026-10-17 at 10:39 and submitted at 11:08; it is Waiting for Review. Its archive (`.build/archive/SpacePane-1.1.0-build5.xcarchive`) was inspected on 2026-10-17: no `CADWorker`, no `CADImportService.xpc`, no `OCCT-Notices`, zero `PreviewCADFormats` references. The earlier submissions, 1.0.0 (3) of 2026-10-13 and 1.1.0 (4) of 2026-10-15, were removed (build 4 still linked the unreachable CAD client code, Guideline 2.5.19). Builds 1 and 2 (2026-10-10 and 2026-10-12, the second with CAD, internal TestFlight only) were never submitted ([decision 028](../decisions/028-no-cad-in-version-1.md)). | Nothing: the build is selected. Any replacement build raises `CURRENT_PROJECT_VERSION` and keeps `PREV_INCLUDE_CAD = NO`. |
| Version 1.1.0, build 6 (prepared) | Prepared on 2026-10-17 from the findings of the rejection-risk review and archived locally; **not uploaded**. It differs from build 5 in the type declarations (SQLite, Parquet and RAR now reach `public.data`, so step 4's `07-stations.sqlite` works; build 5 shows the generic icon for it on every Mac, [the resolution record](../validation/uti-resolution-2026-10-17.md)), the thumbnail list (content formats only), the removed `com.quicklookpro.*` identifiers and the CAD service key. Step 4 keeps `07-stations.sqlite` because build 6 fixes it. | Upload, select the build and re-paste the block only on the owner's instruction, then observe `.sqlite`, `.parquet` and `.rar` on the signed build. |
| Tested on macOS 27.2, Apple silicon | The host matrix and the signed-host records, all development-signed and dated 2026-10-04 to 2026-10-14, so they predate build 5. | Repeat on the store-signed build (plan Phases 3 and 4). |
| macOS 15 (not claimed since 2026-10-17) | The owner reported (2026-10-12) a run in a macOS 15.2 virtual machine. No session observed it and `docs/validation/host-matrix.json` has no macOS 15 host, so the block no longer says "Tested on macOS 15.2"; it says only that macOS 15 is the minimum. | Record a dated macOS 15 run in the host matrix, then restore the sentence. |
| Enabling the extensions | Step 1 points to the "Open System Settings" button in the banner at the top of the General page (`Apps/PrevApp/Views/GeneralView.swift`, `banner` and `openSystemSettingsButton`); the row "Turn on the extensions" under Finder & Quick Look repeats the macOS 15 path as text and has no button (the block said it had one until 2026-10-17). The button opens the deep link `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`, marked unverified in code, and falls back to opening System Settings; it has not been observed on macOS 26 or 27, and no route for those versions is recorded in `docs/validation/` or `CHANGELOGS.md`. | The exact System Settings route on 27.2, word for word. Add it to step 1 if the button lands elsewhere. |
| Sample files and their behavior | Names come from the builder. The archive holds no STEP or IGES file. Step 4 names `31-model.3mf` as the model to turn, because on macOS 27.2 Apple's own previewers take STL, OBJ and PLY and only 3MF reached SpacePane ([the panel survey of 2026-10-14](../validation/safety-lens-2-panel-2026-10-14.md)); `28-binary.stl` stays as a second model with the Try Preview fallback. | The README rows, on the store build. No mesh format has a Finder observation, and `32-model.gguf`, `33-extension.vsix` and `34-package.whl` are `notObserved` on every surface. |
| No CAD in the product | Decision 028: the build setting `PREV_INCLUDE_CAD` is NO, so the notes make no claim about STEP, IGES, Open CASCADE or a source offer. | Done for build 5: its archive was inspected on 2026-10-17 (no CAD service, worker, notices or module references); `script/check_release_archive.py` enforces the setting on every archive. |

STEP and IGES do not ship in 1.0 ([decision 028](../decisions/028-no-cad-in-version-1.md), decided 2026-10-13, which settled R-2 of the review readiness plan). The 3D paragraph and the two CAD file names were taken out of the block, and the two CAD samples out of `SAMPLES` in the builder; `--check` fails if the notes and the archive disagree. The notes make no claim about Open CASCADE or a source offer, because the build has none. If CAD returns, restore the paragraph and the two samples from git history (the commit before 2026-10-13) after the steps in decision 028, "Bringing CAD back".

> SpacePane 1.1.0 (build 6) is a small companion app plus two Quick Look extensions for Finder, SpacePane Preview and SpacePane Thumbnails. Everything runs on the Mac: no account, no sign-in, no network access, no in-app purchase. It needs Apple silicon and macOS 15 or later.
>
> Tested on macOS 27.2, on Apple silicon.
>
> To see it work (about two minutes):
> 1. Open SpacePane. The banner at the top of the General page has an "Open System Settings" button. Use it to open System Settings, then switch on SpacePane Preview and SpacePane Thumbnails among the Quick Look extensions. By hand on macOS 15: System Settings > General > Login Items & Extensions > Quick Look.
> 2. Unzip the attached SpacePane-Review-Samples.zip. Its README.txt lists every file and what to look for.
> 3. In Finder select 01-settings.json and press Space. It opens as a JSON outline with a Source view. The file holds a deliberately fake token and password; SpacePane conceals them and the file is unchanged.
> 4. Also try 07-stations.sqlite (database tables), 08-release.zip (archive listing, nothing extracted), 15-analysis.ipynb (notebook, never run), 16-document.md (Markdown), 31-model.3mf (a 3D model you can turn) and Makefile (a file with no extension). 28-binary.stl is a second model; if macOS shows Apple's own 3D preview for it, turn on Developer Mode on the General page and open the file in Try Preview, which then appears in the sidebar and uses the same preview engine.
>
> New in 1.1.0: previews say what a file would do if it were run, installed or trusted. 32-model.gguf shows an AI model's summary read from its header (the model is never loaded), 33-extension.vsix an editor extension's activation and permissions, and 34-package.whl a Python package's contents and the code it runs at start (nothing is installed). Findings are statements about the file's text; SpacePane never runs it.
>
> macOS decides which installed app previews each file type. If another app already previews a type, Quick Look may use it. An info symbol in the preview shows when SpacePane made it.
>
> The preview extension declares public.data exactly once so that text files with no extension (such as Makefile) can be previewed, and only for previews, never thumbnails. Quick Look matches that type exactly, so PDFs, images and files with an extension are not routed to it, and a binary file with no extension shows a short explanation instead of its bytes.
>
> Developer Mode (off by default, on the General page) only reveals a Try Preview page and an Open File command for checking a file inside the companion. It changes nothing in Finder.
>
> Contact details are entered in App Store Connect. Email: info@spacepane.com. Support: https://spacepane.com/support. Privacy: https://spacepane.com/privacy.

## If App Review objects

Replies to paste into App Store Connect or the Resolution Center. Each states facts and promises nothing about which app Finder uses for a file type.

**Guideline 4.2 (minimum functionality): "the app is only a settings window".** SpacePane is not a settings window. Inside the app, the Theme page shows a live preview of a built-in sample for any of the supported file types, rendered by the same engine the extensions use, with nothing to switch on first; that is the quickest place to see what the product does. Its purpose is two Quick Look extensions inside the app bundle, SpacePane Preview and SpacePane Thumbnails, which macOS runs when a person presses Space on a file in Finder. They show JSON, YAML, XML and similar files as outlines, SQLite databases as tables, archives and folders as listings without extracting anything, notebooks without running them, and 3MF models you can turn, and they conceal likely secrets. Quick Look extensions have no interface of their own, so the companion app turns them on, switches each file type on or off and sets the appearance; with Developer Mode on (General page) it also previews any file directly in Try Preview. The attached samples and README show each preview in about two minutes, and we can send a short screen recording on request.

**Guideline 2.1: "we could not find the app's features".** The features appear in Finder, not in the SpacePane window. After SpacePane Preview and SpacePane Thumbnails are switched on (the "Open System Settings" button in the banner at the top of the General page; on macOS 15, System Settings > General > Login Items & Extensions > Quick Look), select 01-settings.json, 07-stations.sqlite or 08-release.zip from the attached archive in Finder and press Space. macOS decides which installed app previews a type, and SpacePane cannot override that; an info symbol in the preview shows when SpacePane made it. If a file shows another app's preview, the Theme page previews a built-in sample of every supported type inside SpacePane without any setting, and with Developer Mode on (General page) the Try Preview page opens the same file with the same preview engine. We are glad to answer any step that does not work as written.

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
| Version/build | 1.1.0, build 5 in review; build 6 prepared, not uploaded | Build 5 was submitted 2026-10-17 at 11:08 and is Waiting for Review ([status table](version-1.1.0.md#submission-status)). Builds 1 (2026-10-10) and 2 (2026-10-12, with CAD, internal TestFlight only) were never submitted; the 1.0.0 (3) and 1.1.0 (4) submissions were removed. Increment the build for every replacement upload. |
| Compatibility | macOS 15+, Apple silicon only (`ARCHS = arm64`) | Run the candidate on the advertised OS range. The owner reports (2026-10-12) that it works in a macOS 15.2 virtual machine; no run is recorded in the host matrix, so the notes name only macOS 27.2. |
| Pricing/availability | Set in App Store Connect (owner, 2026-10-10: roughly USD 9.99, local pricing adopted) | App Store Connect holds the effective prices; verify agreements, territories and compliance. |
| Review login | Not required if accountless design is unchanged | Do not invent a demo account. |
| Review contact | Reachable person, email and phone with +country code | Confirm monitored contact details separately from the public support URL. |
| Release option | Manual (review readiness plan R-4) | App Store Connect holds **Automatically release this version** for 1.1.0 (observed 2026-10-17), so an approval would publish the app at once. The option is editable while the version is Waiting for Review and needs no resubmission; switching it is the owner's action. |

On October 7, the legacy `.html` support/privacy URLs redirected to the canonical pages and returned HTTP 200. The owner's active address is `info@spacepane.com`, and the review-readiness audit of 2026-10-12 found it on every live page. Live page availability does not prove mailbox operation (Phase 0 item 3 of the review readiness plan sends the test message) or every translated page.

## App Review Guidelines revision of October 2026

Apple's notice of 2026-10-17 lists six changes. Each was checked against SpacePane on 2026-10-17 (version 1.1.0; build 4 was waiting for review that morning and was replaced by build 5, submitted at 11:08 the same day):

| Change | What it means here | Status |
| --- | --- | --- |
| Before You Submit, After You Submit: links to more documentation | The checklist asks for complete metadata, current contact details and explanations of non-obvious features in the review notes. | The notes explain enabling the extensions, the samples, Developer Mode and `public.data`; the paragraph about the `com.quicklookpro.*` identifiers was removed with the identifiers themselves in build 6 ([decision 004](../decisions/004-json-lines-and-group-controls.md), amendment of 2026-10-17). |
| 1.2 User-generated content: scope and safeguards | Applies to apps that host or share content between users. | Not applicable: SpacePane previews the user's own local files and shares nothing. |
| 2.3.14 Creative assets (new) | Rules for the product-page creative-asset type. | None uploaded; the rule for adding any is in [app-store-listing.md](app-store-listing.md#other-product-page-fields). |
| 2.5.19 Hidden, dormant or undocumented features (new) | Every function must be clear to users and App Review. | No launch argument, environment variable, hidden preference, feature flag or debug-only code enables anything. Developer Mode is a visible switch on the General page, described there and in the notes. Build 4 still linked the CAD importer client into the companion and the preview extension although nothing could reach it (no service, no worker, no catalog entry, no type declaration); build 5, the build in review, links it in neither (zero `PreviewCADFormats` references in its archive, inspected 2026-10-17), and `script/check_release_archive.py` refuses any `PreviewCADFormats` code in a build without CAD. |
| 3.1.1(a) Music streaming and external purchase links | Applies to apps with purchases or purchase links. | Not applicable: paid up front, no in-app purchase, no purchase link. |
| 5 Removal for facilitating trafficking or child exploitation | Legal section. | Not applicable. |

## Submission reminder

Select the processed tested build, resolve compliance, save metadata, publish privacy answers, attach the reviewed packet, choose **Add for Review**, then **Submit for Review**. Keep each validation result with the exact version/build. Do not submit until the guide's release gates and the later publishing authorization are complete.
